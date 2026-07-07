# encoding: UTF-8

require 'sketchup.rb'
require 'json'
require 'tmpdir'
require 'open3'

begin
  require 'MH_shared'
rescue LoadError
  shared_loader = File.expand_path('../MH_shared.rb', __dir__)
  require shared_loader if File.exist?(shared_loader)
end

module MH
  module Export
    extend self

    PLUGIN_NAME = 'MH Export'.freeze
    PREF_KEY = 'MH_Export'.freeze
    MM_PER_INCH = 25.4
    DEFAULT_TEMPLATE = 'D:/Cong viec/Sample/DMVT-VAN.xlsx'.freeze
    DEFAULT_EXPORTER = File.join(__dir__, 'exporter', 'mh_export_dmvt.py').freeze
    UNKNOWN_MATERIAL = '__UNKNOWN_MATERIAL__'.freeze
    @collect_payload_cache = nil
    @collect_payload_cache_key = nil

    def export_dmvt
      show_dialog
    end

    def show_dialog
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        UI.start_timer(0.1, false) { refresh_dialog(false) }
        return
      end

      @dialog = build_dialog
      @dialog.show
      UI.start_timer(0.1, false) { refresh_dialog(false) }
    rescue StandardError => error
      warn_error(error)
      UI.messagebox("MH Export lỗi:\n#{error.message}")
    end

    def build_dialog
      dialog = UI::HtmlDialog.new(
        dialog_title: 'MH Export - DMVT ván/nẹp',
        preferences_key: PREF_KEY,
        width: 1180,
        height: 760,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      dialog.set_file(File.join(__dir__, 'ui.html'))
      dialog.add_action_callback('ready') { |_ctx| refresh_dialog(false) }
      dialog.add_action_callback('refresh') do |_ctx, payload|
        options = parse_json(payload)
        refresh_dialog(!!options['show_paint_code'])
      end
      dialog.add_action_callback('export_excel') do |_ctx, payload|
        options = parse_json(payload)
        export_from_dialog(!!options['show_paint_code'])
      end
      dialog.add_action_callback('export') do |_ctx, payload|
        options = parse_json(payload)
        export_from_dialog(!!options['show_paint_code'])
      end
      dialog
    end

    def refresh_dialog(show_paint_code = false)
      return unless @dialog

      payload = preview_payload(show_paint_code)
      @last_preview_payload = payload
      @dialog.execute_script("window.mhExportLoad(#{payload.to_json})")
    rescue StandardError => error
      warn_error(error)
      @dialog.execute_script("window.mhExportError(#{error.message.to_json})") if @dialog
    end

    def export_from_dialog(show_paint_code = false)
      model = Sketchup.active_model
      default_name = default_output_name(model)
      default_dir = model.path.to_s.empty? ? Dir.home : File.dirname(model.path)
      notify_export_status('Đang chọn nơi lưu file...')
      output_path = UI.savepanel('Lưu DMVT ván/nẹp', default_dir, default_name)
      unless output_path
        notify_export_done('Đã huỷ xuất Excel.')
        return
      end

      notify_export_status('Đang tạo file Excel...')
      payload = @last_preview_payload
      payload = preview_payload(show_paint_code) unless payload && payload[:show_paint_code] == show_paint_code
      result = export_to_path(output_path, payload: payload)
      if result[:ok]
        notify_export_done("Đã xuất Excel: #{result[:output_path]}")
        UI.messagebox("Đã xuất DMVT:\n#{result[:output_path]}\n\n#{summary_message(result[:summary])}")
        open_file(result[:output_path])
      else
        notify_export_done("Xuất DMVT lỗi: #{result[:message]}")
        UI.messagebox("Xuất DMVT lỗi:\n#{result[:message]}")
      end
    rescue StandardError => error
      warn_error(error)
      notify_export_done("Xuất DMVT lỗi: #{error.message}")
      UI.messagebox("Xuất DMVT lỗi:\n#{error.message}")
    end

    def notify_export_status(message)
      return unless @dialog

      @dialog.execute_script("window.mhExportStatus(#{message.to_json})")
    rescue StandardError
      nil
    end

    def notify_export_done(message)
      return unless @dialog

      @dialog.execute_script("window.mhExportDone(#{message.to_json})")
    rescue StandardError
      nil
    end

    def parse_json(payload)
      JSON.parse(payload.to_s)
    rescue StandardError
      {}
    end

    def export_to_path(output_path, options = {})
      exporter_path = options[:exporter_path] || Sketchup.read_default(PREF_KEY, 'exporter_path', DEFAULT_EXPORTER)
      template_path = options[:template_path] || Sketchup.read_default(PREF_KEY, 'template_path', DEFAULT_TEMPLATE)
      raise "Không tìm thấy exporter Python:\n#{exporter_path}" unless File.exist?(exporter_path)
      raise "Không tìm thấy file mẫu Excel:\n#{template_path}" unless File.exist?(template_path)

      payload = options[:payload] || collect_payload
      payload[:template_path] = template_path
      payload[:output_path] = output_path
      payload[:proposer] = Sketchup.read_default(PREF_KEY, 'proposer', '')

      json_path = File.join(Dir.tmpdir, "mh_export_#{Time.now.to_i}_#{rand(1000)}.json")
      File.write(json_path, JSON.pretty_generate(payload), encoding: 'UTF-8')

      cmd = python_command + [exporter_path, '--input', json_path, '--output', output_path, '--template', template_path]
      stdout, stderr, status = Open3.capture3(*cmd)
      unless status.success?
        raise "Python exporter failed (#{status.exitstatus}).\n#{stdout}\n#{stderr}"
      end

      parsed = JSON.parse(stdout.to_s.lines.reverse.find { |line| line.strip.start_with?('{') }.to_s) rescue {}
      {
        ok: File.exist?(output_path),
        output_path: output_path,
        message: parsed['message'].to_s,
        summary: payload[:summary]
      }
    ensure
      File.delete(json_path) if json_path && File.exist?(json_path)
    end

    def preview_payload(show_paint_code = false)
      raw = collect_payload
      raw[:show_paint_code] = show_paint_code
      raw[:rows] = regroup_preview_rows(raw[:rows], show_paint_code)
      raw[:summary] = raw[:summary].merge(
        material_count: raw[:rows].map { |row| row[:material_code].to_s }.uniq.size,
        row_count: raw[:rows].size,
        show_paint_code: show_paint_code
      )
      raw
    end

    def collect_payload
      model = Sketchup.active_model
      cache_key = export_payload_cache_key(model)
      if cache_key && @collect_payload_cache_key == cache_key && @collect_payload_cache
        cached = deep_dup_data(@collect_payload_cache)
        cached[:generated_at] = Time.now.strftime('%Y-%m-%d %H:%M:%S')
        return cached
      end

      instance_records = collect_instance_records(model)
      sheet_id_to_material, material_stats = collect_sheet_stats(model, instance_records)
      material_candidates = material_stats.values
        .select { |stat| numeric_or_nil(stat[:thickness_mm]) }
        .map { |stat| { material_code: stat[:material_code], thickness_mm: numeric_or_nil(stat[:thickness_mm]) } }
      board_to_sheet = collect_board_sheet_ids
      edge_summary = { boards: 0, faces: 0, missing_material_boards: 0, inferred_material_boards: 0, missing_edge_types: 0 }

      instance_records.each do |record|
        entity = record[:entity]
        transform = record[:transform]
        path_names = record[:path_names]
        next if nesting_path?(path_names)
        next unless board_entity?(entity)

        edge_types = parse_edge_types(abf_attr(entity, 'edge-band-types'))
        next if edge_types.empty?

        board_index = abf_attr(entity, 'board-index')
        sheet_id = board_to_sheet[board_index.to_i]
        material_code = material_from_board(entity, sheet_id, sheet_id_to_material)
        inferred = false
        unless material_code
          material_code = infer_material_by_thickness(entity, transform, material_candidates)
          inferred = !material_code.nil?
        end
        material_code ||= UNKNOWN_MATERIAL

        edge_summary[:boards] += 1
        edge_summary[:inferred_material_boards] += 1 if inferred
        edge_summary[:missing_material_boards] += 1 if material_code == UNKNOWN_MATERIAL
        stat = material_stats[material_code]
        stat[:material_code] = material_code
        edge_sides = record[:edge_sides] ||= edge_band_sides(entity, transform, edge_types)
        edge_summary[:faces] += edge_sides[:face_count].to_i
        edge_summary[:missing_edge_types] += edge_sides[:missing_edge_types].to_i
        edge_sides[:material_totals].each do |key, length_m|
          stat[:edge_bands][key] += length_m.to_f
        end
      end

      rows = build_rows(material_stats)
      abf_excel_data = collect_abf_excel_data(model, board_to_sheet, sheet_id_to_material, instance_records)
      payload = {
        generated_at: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        source_model: model.path.to_s,
        content: model.path.to_s.empty? ? model.title.to_s : File.basename(model.path, '.*'),
        rows: rows,
        abf_excel_data: abf_excel_data,
        summary: {
          material_count: rows.map { |r| r[:material_code] }.uniq.size,
          row_count: rows.size,
          abf_data_rows: Array(abf_excel_data[:rows]).length,
          sheet_count: material_stats.values.sum { |s| s[:sheet_ids].size },
          edge_band_m: material_stats.values.sum { |s| s[:edge_bands].values.sum }.round(3),
          edge_boards: edge_summary[:boards],
          edge_faces: edge_summary[:faces],
          inferred_material_boards: edge_summary[:inferred_material_boards],
          missing_material_boards: edge_summary[:missing_material_boards],
          missing_edge_types: edge_summary[:missing_edge_types]
        }
      }
      if cache_key
        @collect_payload_cache_key = cache_key
        @collect_payload_cache = deep_dup_data(payload)
      end
      payload
    end

    def collect_abf_excel_data(model, board_to_sheet, sheet_id_to_material, instance_records = nil)
      edge_columns = []
      pending_rows = []
      records = instance_records || collect_instance_records(model)
      records.each do |record|
        entity = record[:entity]
        transform = record[:transform]
        path_names = record[:path_names]
        next if nesting_path?(path_names)
        next unless board_index_entity?(entity)

        board_index = abf_attr(entity, 'board-index').to_i
        dimensions = board_dimensions_mm(entity, transform)
        material_code = entity_material_code(entity)
        sheet_id = board_to_sheet[board_index]
        material_code = material_from_board(entity, sheet_id, sheet_id_to_material).to_s if material_code.empty?
        product = product_code_from_text((path_names + [entity.name.to_s]).join(' '))
        label = clean_abf_label(entity.name.to_s)
        edge_sides = record[:edge_sides] ||= edge_band_sides(entity, transform)
        dimensions = dimensions_from_edge_sides(dimensions, edge_sides)
        cutting_length = dimensions[:length].to_f -
          edge_sides[:edge_thicknesses][:left].to_f -
          edge_sides[:edge_thicknesses][:right].to_f
        cutting_width = dimensions[:width].to_f -
          edge_sides[:edge_thicknesses][:top].to_f -
          edge_sides[:edge_thicknesses][:bot].to_f
        edge_sides[:edge_totals].each_key do |edge_name|
          edge_columns << edge_name unless edge_columns.include?(edge_name)
        end

        pending_rows << {
          index: board_index,
          edge_totals: edge_sides[:edge_totals],
          base: [
          board_index,
          sheet_id,
          format_number(dimensions[:length]),
          format_number(dimensions[:width]),
          format_number(cutting_length),
          format_number(cutting_width),
          format_number(dimensions[:thickness]),
          grain_from_board(entity, material_code),
          material_code,
          '',
          '',
          '',
          product.to_s,
          label,
          edge_sides[:top],
          edge_sides[:right],
          edge_sides[:bot],
          edge_sides[:left],
          edge_sides[:_top_],
          edge_sides[:_right_],
          edge_sides[:_bot_],
          edge_sides[:_left_],
          ''
          ]
        }
      end

      headers = abf_excel_headers(edge_columns)
      rows = pending_rows.sort_by { |row| row[:index].to_i }.map do |row|
        row[:base] + edge_columns.map { |edge_name| format_edge_total(row[:edge_totals][edge_name].to_f) }
      end
      { headers: headers, rows: rows.sort_by { |row| row[0].to_i } }
    rescue StandardError => error
      warn_error(error)
      { headers: headers || abf_excel_headers, rows: [] }
    end

    def abf_excel_headers(edge_columns = [])
      base = [
        'index', 'sheet', 'length', 'width', 'cutting-length', 'cutting-width',
        'thickness', 'grain', 'material', 'Code N.1', 'Code N.2', 'Code N.3',
        'Ma_SP', 'label', 'top', 'right', 'bot', 'left', '_top_', '_right_', '_bot_', '_left_', ''
      ]
      base + Array(edge_columns)
    end

    def board_dimensions_mm(entity, transform)
      bounds = entity.definition.bounds
      min = bounds.min
      max = bounds.max
      origin = Geom::Point3d.new(min.x, min.y, min.z).transform(transform)
      vectors = [
        Geom::Point3d.new(max.x, min.y, min.z),
        Geom::Point3d.new(min.x, max.y, min.z),
        Geom::Point3d.new(min.x, min.y, max.z)
      ]
      dims = vectors.map { |point| origin.distance(point.transform(transform)) * MM_PER_INCH }
      dims = dims.select { |value| value && value > 0.001 }.sort
      {
        thickness: dims[0].to_f,
        width: dims[1].to_f,
        length: dims[2].to_f
      }
    rescue StandardError
      dims = [entity.bounds.width, entity.bounds.height, entity.bounds.depth].map { |value| value.to_f * MM_PER_INCH }.sort
      {
        thickness: dims[0].to_f,
        width: dims[1].to_f,
        length: dims[2].to_f
      }
    end

    def dimensions_from_edge_sides(dimensions, edge_sides)
      result = dimensions.dup
      edge_lengths = edge_sides[:edge_lengths] || {}
      length_candidates = [edge_lengths[:top], edge_lengths[:bot]].map(&:to_f).select { |value| value.positive? }
      width_candidates = [edge_lengths[:left], edge_lengths[:right]].map(&:to_f).select { |value| value.positive? }
      result[:length] = length_candidates.max if length_candidates.any?
      result[:width] = width_candidates.max if width_candidates.any?
      result
    rescue StandardError
      dimensions
    end

    def entity_material_code(entity)
      material = entity.respond_to?(:material) ? entity.material : nil
      material ? material.display_name.to_s.strip : ''
    rescue StandardError
      ''
    end

    def grain_from_material(material_code)
      match = material_code.to_s.match(/(?:^|\.)([12]M)(?:\.|$)/i)
      match ? match[1][0] : ''
    end

    def grain_from_board(entity, material_code)
      rotation = numeric_or_nil(abf_attr(entity, 'label-rotation'))
      return (rotation.to_i % 180).zero? ? '1' : '2' if rotation

      grain = grain_from_material(material_code)
      grain.empty? ? '1' : grain
    end

    def clean_abf_label(name)
      text = name.to_s.sub(/\A__/, '').strip
      text.sub(/\A\d+\.\s*/, '').strip
    end

    def format_number(value)
      number = numeric_or_nil(value)
      return '' unless number

      rounded = number.round(2)
      (rounded - rounded.round).abs < 0.001 ? rounded.round : rounded
    end

    def collect_sheet_stats(model, instance_records = nil)
      sheet_id_to_material = {}
      material_stats = Hash.new do |hash, code|
        hash[code] = {
          material_code: code,
          thickness_mm: nil,
          sheet_size: nil,
          sheet_ids: {},
          products: {},
          edge_bands: Hash.new(0.0)
        }
      end

      records = instance_records || collect_instance_records(model)
      records.each do |record|
        entity = record[:entity]
        material_code = abf_attr(entity, 'sheet-type').to_s.strip
        next if material_code.empty?

        sheet_id = abf_attr(entity, 'sheet-id')
        thickness = numeric_or_nil(abf_attr(entity, 'sheet-thickness'))
        dimension = abf_attr(entity, 'sheet-dimension')
        stat = material_stats[material_code]
        stat[:thickness_mm] ||= thickness
        stat[:sheet_size] ||= Array(dimension).join('x') unless dimension.nil?
        if sheet_id
          stat[:sheet_ids][sheet_id.to_i] = true
          sheet_id_to_material[sheet_id.to_i] = {
            material_code: material_code,
            thickness_mm: thickness,
            sheet_size: stat[:sheet_size]
          }
        end
      end

      supplement_sheets_from_abf(material_stats)
      [sheet_id_to_material, material_stats]
    end

    def export_payload_cache_key(model)
      return nil unless model && defined?(MH::ModelHub)

      MH::ModelHub.start! if MH::ModelHub.respond_to?(:start!)
      [model.object_id, MH::ModelHub.model_signature(model)]
    rescue StandardError
      nil
    end

    def deep_dup_data(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), copy| copy[key] = deep_dup_data(item) }
      when Array
        value.map { |item| deep_dup_data(item) }
      when String
        value.dup
      else
        value
      end
    end

    def supplement_sheets_from_abf(material_stats)
      return unless defined?(ABF::Statistics) && ABF::Statistics.respond_to?(:collect_sheets)

      Array(ABF::Statistics.collect_sheets).each do |item|
        data = normalize_hash(item)
        material_code = (data[:name] || data['name']).to_s.strip
        next if material_code.empty?

        stat = material_stats[material_code]
        stat[:thickness_mm] ||= numeric_or_nil(data[:thickness] || data['thickness'])
        qty = (data[:quantity] || data['quantity']).to_i
        if stat[:sheet_ids].empty? && qty.positive?
          qty.times { |i| stat[:sheet_ids][:"abf_#{i + 1}"] = true }
        end
      end
    rescue StandardError => error
      warn_error(error)
    end

    def collect_board_sheet_ids
      return {} unless defined?(ABF::PartData) && ABF::PartData.respond_to?(:collect_sheet_ids)

      raw = ABF::PartData.collect_sheet_ids
      return {} unless raw.respond_to?(:each)

      map = {}
      raw.each { |board_id, sheet_id| map[board_id.to_i] = sheet_id.to_i if board_id && sheet_id }
      map
    rescue StandardError => error
      warn_error(error)
      {}
    end

    def build_rows(material_stats)
      rows = []
      material_stats.values
        .select { |stat| stat[:sheet_ids].any? || stat[:edge_bands].any? }
        .sort_by { |stat| stat[:material_code].to_s }
        .each do |stat|
          material_code = stat[:material_code].to_s
          sheet_qty = stat[:sheet_ids].size
          if sheet_qty.positive?
            rows << {
              name: 'Ván',
              size: format_mm(stat[:thickness_mm]),
              material_code: material_code,
              unit: 'tấm',
              quantity: sheet_qty,
              note: ''
            }
          end

          stat[:edge_bands].sort_by { |(name, thickness), _m| [name.to_s, thickness.to_f] }.each do |(name, thickness), meters|
            next if meters <= 0

            rows << {
              name: edge_row_name(name),
              size: format_mm(thickness),
              material_code: material_code,
              unit: 'md',
              quantity: meters.round(3),
              note: ''
            }
          end
        end
      rows
    end

    def regroup_preview_rows(rows, show_paint_code)
      grouped = {}
      rows.each do |row|
        export_code = export_material_code(row[:material_code], show_paint_code)
        key = [row[:name].to_s, row[:size].to_s, export_code.to_s, row[:unit].to_s]
        target = grouped[key] ||= row.merge(
          material_code: export_code,
          quantity: 0.0
        )
        target[:quantity] = target[:quantity].to_f + row[:quantity].to_f
        target[:note] = ''
      end

      grouped.values
        .sort_by { |row| [row[:material_code].to_s, row[:unit].to_s == 'tấm' ? 0 : 1, row[:name].to_s] }
        .each do |row|
          row[:quantity] = row[:unit].to_s.downcase == 'md' ? row[:quantity].round(3) : row[:quantity].round
          row[:name] = board_row_name(row[:material_code]) if row[:name].to_s.strip == 'Ván'
        end
    end

    def board_row_name(material_code)
      code = material_code.to_s.strip
      standard = standard_material_item_name(code)
      return standard unless standard.empty?

      code.empty? ? 'Ván' : "Ván #{code}"
    end

    def standard_material_item_name(material_code)
      code = material_code.to_s.strip
      return '' if code.empty?

      names = []
      parsed = material_code_parse(code)
      if parsed.is_a?(Hash)
        layers = parsed[:layers] || parsed['layers'] || {}
        %w[chat_lieu nha_cung_cap be_mat].each do |layer_key|
          mapped = material_mapping_name(layer_key, layers[layer_key] || layers[layer_key.to_sym])
          names << mapped unless mapped.empty?
        end
      end

      if names.empty?
        code.split('.').each do |segment|
          next if segment.to_s =~ /\A\d+(?:[,.]\d+)?\z/

          mapped = material_mapping_name(nil, segment)
          names << mapped unless mapped.empty?
        end
      end

      names.map(&:strip).reject(&:empty?).uniq.join(' ')
    rescue StandardError => error
      warn_error(error)
      ''
    end

    def material_code_parse(code)
      if defined?(MH::MaterialCode) && MH::MaterialCode.respond_to?(:parse)
        MH::MaterialCode.parse(code)
      else
        {}
      end
    rescue StandardError
      {}
    end

    def material_mapping_name(layer_key, mapped_value)
      value_key = comparable_mapping_text(mapped_value)
      return '' if value_key.empty?

      material_mapping_rows.each do |row|
        group = row_value(row, 'nhom', 'layer', 'key', 'group')
        next if layer_key && comparable_mapping_text(group) != comparable_mapping_text(layer_key)

        mapped = row_value(row, 'gia_tri_map', 'mapped', 'canonical', 'map', 'material_code')
        source = row_value(row, 'gia_tri', 'value', 'raw', 'name')
        next if source.to_s.strip.empty?

        return source.to_s.strip if comparable_mapping_text(mapped) == value_key
      end
      ''
    end

    def material_mapping_rows
      @material_mapping_rows ||= begin
        rows = []
        if defined?(MH::Registry) && MH::Registry.respond_to?(:material_code_mappings)
          rows = Array(MH::Registry.material_code_mappings)
        end
        rows = read_config_material_mappings if rows.empty?
        rows
      end
    end

    def read_config_material_mappings
      return [] unless defined?(MH::ExcelBridge) && MH::ExcelBridge.respond_to?(:read_as_hashes)

      path = File.expand_path('../MH_Registry/Config.xlsx', __dir__)
      return [] unless File.exist?(path)

      MH::ExcelBridge.read_as_hashes(path, sheet: 'ma_vat_lieu')
    rescue StandardError => error
      warn_error(error)
      []
    end

    def row_value(row, *keys)
      keys.each do |key|
        value = row[key]
        value = row[key.to_sym] if value.nil? && row.respond_to?(:[])
        return value unless value.nil? || value.to_s.empty?
      end
      ''
    end

    def comparable_mapping_text(value)
      value.to_s.strip.upcase.gsub(/\s+/, '')
    end

    def export_material_code(code, show_paint_code)
      text = code.to_s.strip
      return text if show_paint_code

      strip_paint_suffix(text)
    end

    def strip_paint_suffix(code)
      parts = code.to_s.strip.split('.')
      return code.to_s.strip if parts.size < 2

      last = parts.last.to_s.strip
      paint_like = last.include?('/') ||
        last.include?('%') ||
        last =~ /bóng|bong|mờ|mo|sơn|son/i ||
        last =~ /\ABQ[A-Z0-9]/i
      paint_like ? parts[0...-1].join('.') : code.to_s.strip
    end

    def product_code_from_text(text)
      if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:first_product)
        code = MH::NameGrammar.first_product(text.to_s)
        return product_code_base(code) unless code.to_s.empty?
      end
      match = text.to_s.match(/(?:^|[^A-Z0-9.])([A-Z]+\d+[A-Z]?(?:\.\d+)?)(?=$|[^A-Z0-9.])/i)
      match && product_code_base(match[1])
    end

    def product_code_base(code)
      code.to_s.strip.upcase.sub(/[._]\d+\z/, '')
    end

    def material_from_board(entity, sheet_id, sheet_id_to_material)
      if sheet_id && sheet_id_to_material[sheet_id]
        return sheet_id_to_material[sheet_id][:material_code]
      end

      direct = abf_attr(entity, 'sheet-type').to_s.strip
      return direct unless direct.empty?

      nil
    end

    def infer_material_by_thickness(entity, transform, material_candidates)
      return nil if material_candidates.empty?

      lengths = small_edge_lengths_mm(entity.definition.entities, transform)
      return nil if lengths.empty?

      best = nil
      material_candidates.each do |candidate|
        thickness = candidate[:thickness_mm].to_f
        diff = lengths.map { |length| (length - thickness).abs }.min
        next unless diff
        next if best && diff >= best[:diff]

        best = { material_code: candidate[:material_code], diff: diff }
      end

      # Keep this conservative. If ABF did not map the part to a sheet and the
      # geometry is not close to a known sheet thickness, do not guess.
      best && best[:diff] <= 2.1 ? best[:material_code] : nil
    end

    def small_edge_lengths_mm(entities, transform, output = [])
      entities.each do |entity|
        if entity.is_a?(Sketchup::Face)
          entity.edges.each do |edge|
            a, b = edge.vertices.map { |vertex| vertex.position.transform(transform) }
            length = a.distance(b) * MM_PER_INCH
            output << length if length > 1.0 && length < 100.0
          end
        elsif entity.respond_to?(:definition) && entity.respond_to?(:transformation)
          small_edge_lengths_mm(entity.definition.entities, transform * entity.transformation, output)
        end
      end
      output.uniq
    end

    # One model traversal feeds sheet statistics, edge aggregation and the ABF
    # worksheet. This is the per-revision feature cache for the export pass.
    def collect_instance_records(model)
      records = []
      walk_instances(model.entities, Geom::Transformation.new, []) do |entity, transform, path_names|
        records << {
          entity: entity,
          transform: transform,
          path_names: path_names.freeze
        }
      end
      records
    end

    def walk_instances(entities, transform, path_names, &block)
      entities.each do |entity|
        next unless entity.respond_to?(:definition) && entity.respond_to?(:transformation)

        child_transform = transform * entity.transformation
        child_path = path_names + [entity.name.to_s]
        yield(entity, child_transform, child_path)
        walk_instances(entity.definition.entities, child_transform, child_path, &block)
      end
    end

    def each_edge_band_face(entities, transform, &block)
      entities.each do |entity|
        if entity.is_a?(Sketchup::Face)
          yield(entity, transform)
        elsif entity.respond_to?(:definition) && entity.respond_to?(:transformation)
          each_edge_band_face(entity.definition.entities, transform * entity.transformation, &block)
        end
      end
    end

    def edge_band_sides(entity, transform, edge_types = nil)
      sides = blank_edge_sides
      edge_types ||= parse_edge_types(abf_attr(entity, 'edge-band-types'))
      return sides if edge_types.empty?

      axes = board_plane_axes(entity, transform)

      grouped = Hash.new { |hash, side| hash[side] = [] }
      each_edge_band_face(entity.definition.entities, transform) do |face, face_transform|
        edge_id = abf_attr(face, 'edge-band-id')
        next if edge_id.nil?

        info = edge_types[edge_id.to_i]
        unless info
          sides[:missing_edge_types] += 1
          next
        end

        length_m = max_edge_length_m(face, face_transform)
        sides[:face_count] += 1
        material_key = [info[:name], info[:thickness_mm]]
        sides[:material_totals][material_key] += length_m.to_f
        next unless axes

        side = classify_edge_side(face.normal, face_transform, axes)
        next unless side

        grouped[side] << {
          value: edge_band_display(info),
          thickness_mm: info[:thickness_mm].to_f,
          length_m: length_m,
          material_key: material_key
        }
      end

      grouped.each do |side, values|
        side_length_mm = values.sum { |item| item[:length_m].to_f } * 1000.0
        sides[side] = edge_side_marker(side)
        sides[:"_#{side}_"] = join_edge_values(values.map { |item| item[:value] })
        sides[:edge_lengths][side] = side_length_mm
        sides[:edge_thicknesses][side] = values.map { |item| item[:thickness_mm].to_f }.max.to_f
        values.each do |item|
          next if item[:value].to_s.empty?

          sides[:edge_totals][item[:value]] += item[:length_m].to_f
        end
      end
      sides
    rescue StandardError => error
      warn_error(error)
      blank_edge_sides
    end

    def blank_edge_sides
      {
        top: '',
        right: '',
        bot: '',
        left: '',
        _top_: '',
        _right_: '',
        _bot_: '',
        _left_: '',
        edge_totals: Hash.new(0.0),
        material_totals: Hash.new(0.0),
        edge_lengths: Hash.new(0.0),
        edge_thicknesses: Hash.new(0.0),
        face_count: 0,
        missing_edge_types: 0
      }
    end

    def board_plane_axes(entity, transform)
      bounds = entity.definition.bounds
      min = bounds.min
      max = bounds.max
      origin = Geom::Point3d.new(min.x, min.y, min.z).transform(transform)
      axes = [
        axis_info(origin, Geom::Point3d.new(max.x, min.y, min.z).transform(transform)),
        axis_info(origin, Geom::Point3d.new(min.x, max.y, min.z).transform(transform)),
        axis_info(origin, Geom::Point3d.new(min.x, min.y, max.z).transform(transform))
      ].compact.sort_by { |axis| axis[:length] }
      return nil if axes.length < 3

      plane_axes = axes[1..2].sort_by { |axis| axis[:length] }
      {
        width_axis: plane_axes[0][:vector],
        length_axis: plane_axes[1][:vector]
      }
    end

    def axis_info(origin, point)
      vector = point - origin
      length = vector.length
      return nil if length <= 0.001

      vector.normalize!
      { vector: vector, length: length }
    rescue StandardError
      nil
    end

    def classify_edge_side(local_normal, transform, axes)
      normal = local_normal.transform(transform)
      return nil if normal.length <= 0.001

      normal.normalize!
      scores = {
        top: normal.dot(axes[:width_axis]),
        bot: -normal.dot(axes[:width_axis]),
        right: normal.dot(axes[:length_axis]),
        left: -normal.dot(axes[:length_axis])
      }
      side, score = scores.max_by { |_key, value| value.to_f }
      score.to_f >= 0.65 ? side : nil
    rescue StandardError
      nil
    end

    def edge_band_display(info)
      name = info[:raw_name].to_s
      name = info[:name].to_s if name.empty?
      name = 'NEP' if name.strip.empty?
      "#{name} - #{format_edge_thickness(info[:thickness_mm])}mm"
    end

    def edge_side_marker(side)
      { top: '˄', right: '˃', bot: '˅', left: '˂' }[side].to_s
    end

    def format_edge_thickness(value)
      number = numeric_or_nil(value).to_f
      rounded = number.round(3)
      (rounded - rounded.round).abs < 0.001 ? rounded.round : rounded
    end

    def format_edge_total(value)
      return 0 if value.to_f <= 0

      value.round(4)
    end

    def join_edge_values(values)
      values.map { |value| value.to_s.strip }.reject(&:empty?).uniq.join('; ')
    end

    def board_entity?(entity)
      return false unless entity.respond_to?(:definition)

      !!abf_attr(entity, 'edge-band-types') &&
        (!!abf_attr(entity, 'is-board') || !abf_attr(entity, 'board-index').nil?)
    end

    def board_index_entity?(entity)
      entity.respond_to?(:definition) && !abf_attr(entity, 'board-index').nil?
    end

    def nesting_path?(path_names)
      path_names.any? { |name| name.to_s.include?('__ABF_Nesting') }
    end

    def parse_edge_types(raw)
      types = {}
      return types unless raw.is_a?(Array)

      raw.each_slice(5) do |id, name, thickness, color, flag|
        next if id.nil?

        types[id.to_i] = {
          raw_name: name.to_s,
          name: name.to_s.strip,
          thickness_mm: thickness.to_f,
          color: color,
          flag: flag
        }
      end
      types
    end

    def max_edge_length_m(face, transform)
      face.edges.map do |edge|
        a, b = edge.vertices.map { |vertex| vertex.position.transform(transform) }
        a.distance(b) * MM_PER_INCH / 1000.0
      end.max.to_f
    end

    def abf_attr(entity, key)
      dict = entity.attribute_dictionary('ABF', false)
      dict && dict[key]
    rescue StandardError
      nil
    end

    def numeric_or_nil(value)
      return nil if value.nil?

      Float(value)
    rescue StandardError
      nil
    end

    def normalize_hash(value)
      return value if value.is_a?(Hash)

      if value.respond_to?(:to_h)
        value.to_h
      else
        {}
      end
    rescue StandardError
      {}
    end

    def format_mm(value)
      number = numeric_or_nil(value)
      return '' unless number

      if (number - number.round).abs < 0.001
        "#{number.round}mm"
      else
        "#{number.round(2)}mm"
      end
    end

    def edge_row_name(name)
      clean = name.to_s.strip
      clean = clean.sub(/\A(?:NEP|NẸP|Nẹp)\s*/i, '').strip
      clean.empty? ? 'Nẹp' : "Nẹp #{clean}"
    end

    def default_output_name(model)
      base = model.path.to_s.empty? ? model.title.to_s : File.basename(model.path, '.*')
      base = 'MH_EXPORT' if base.to_s.strip.empty?
      "#{base}_DMVT-VAN.xlsx"
    end

    def python_command
      configured = Sketchup.read_default(PREF_KEY, 'python_path', nil).to_s.strip
      return [configured] unless configured.empty?

      ENV['PATH'].to_s.split(File::PATH_SEPARATOR).each do |dir|
        path = File.join(dir, 'python.exe')
        return [path] if File.exist?(path)
      end

      ['py', '-3']
    end

    def open_file(path)
      UI.openURL(path.tr('\\', '/'))
    rescue StandardError
      system('cmd', '/c', 'start', '', path)
    end

    def summary_message(summary)
      return '' unless summary

      [
        "Mã vật liệu: #{summary[:material_count]}",
        "Số tấm: #{summary[:sheet_count]}",
        "Mét nẹp: #{summary[:edge_band_m]}",
        "Dòng Excel: #{summary[:row_count]}"
      ].join("\n")
    end

    def warn_error(error)
      warn "[MH_EXPORT] #{error.class}: #{error.message}"
      warn error.backtrace.join("\n") if error.backtrace
    end

    unless file_loaded?(__FILE__)
      UI.menu('Extensions').add_item('MH Export - DMVT ván/nẹp') { export_dmvt }
      file_loaded(__FILE__)
    end
  end
end

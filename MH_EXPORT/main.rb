# encoding: UTF-8

require 'sketchup.rb'
require 'json'
require 'tmpdir'
require 'open3'
require_relative '../MH_shared/material_item_names'
require_relative '../MH_shared/material_code'

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
    DEFAULT_ASSUMED_EDGE_THICKNESS_MM = 1.0
    DEFAULT_EDGE_OPTIONS = {
      nep22_multiplier: 2.0,
      nep44_multiplier: 3.0,
      nep60_multiplier: 1.0,
      min_thickness_mm: 12.0
    }.freeze
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
        refresh_dialog(!!options['show_paint_code'], truthy?(options['assume_full_edging']), edge_options_from_dialog(options))
      end
      dialog.add_action_callback('export_excel') do |_ctx, payload|
        options = parse_json(payload)
        export_from_dialog(
          !!options['show_paint_code'],
          truthy?(options['assume_full_edging']),
          edge_options_from_dialog(options)
        )
      end
      dialog.add_action_callback('export') do |_ctx, payload|
        options = parse_json(payload)
        export_from_dialog(
          !!options['show_paint_code'],
          truthy?(options['assume_full_edging']),
          edge_options_from_dialog(options)
        )
      end
      dialog
    end

    def refresh_dialog(show_paint_code = false, assume_full_edging = true, edge_options = nil)
      return unless @dialog

      payload = preview_payload(show_paint_code, assume_full_edging, edge_options)
      @last_preview_payload = payload
      @dialog.execute_script("window.mhExportLoad(#{payload.to_json})")
    rescue StandardError => error
      warn_error(error)
      @dialog.execute_script("window.mhExportError(#{error.message.to_json})") if @dialog
    end

    def export_from_dialog(show_paint_code = false, assume_full_edging = true, edge_options = nil)
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
      normalized_edge_options = normalize_edge_options(edge_options)
      payload = @last_preview_payload
      payload = preview_payload(show_paint_code, assume_full_edging, normalized_edge_options) unless payload &&
        payload[:show_paint_code] == show_paint_code &&
        payload[:assume_full_edging] == assume_full_edging &&
        payload[:edge_options] == normalized_edge_options
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

    def truthy?(value)
      value == true || value.to_s == 'true' || value.to_s == '1'
    end

    def edge_options_from_dialog(options)
      normalize_edge_options(options)
    end

    def normalize_edge_options(options = nil)
      values = normalize_hash(options)
      normalized = {}
      DEFAULT_EDGE_OPTIONS.each do |key, default_value|
        raw_value = values[key] || values[key.to_s]
        value = numeric_or_nil(raw_value.to_s.tr(',', '.'))
        normalized[key] = value.nil? ? default_value : value
      end
      normalized[:nep22_multiplier] = 0.0 if normalized[:nep22_multiplier].negative?
      normalized[:nep44_multiplier] = 0.0 if normalized[:nep44_multiplier].negative?
      normalized[:nep60_multiplier] = 0.0 if normalized[:nep60_multiplier].negative?
      normalized[:min_thickness_mm] = 0.0 if normalized[:min_thickness_mm].negative?
      normalized
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

    def preview_payload(show_paint_code = false, assume_full_edging = true, edge_options = nil)
      edge_options = normalize_edge_options(edge_options)
      raw = collect_payload(assume_full_edging, edge_options)
      raw[:show_paint_code] = show_paint_code
      raw[:assume_full_edging] = assume_full_edging
      raw[:edge_options] = edge_options
      raw[:rows] = regroup_preview_rows(raw[:rows], show_paint_code)
      raw[:summary] = raw[:summary].merge(
        material_count: raw[:rows].map { |row| row[:material_code].to_s }.uniq.size,
        row_count: raw[:rows].size,
        show_paint_code: show_paint_code,
        assume_full_edging: assume_full_edging,
        edge_options: edge_options
      )
      raw
    end

    def collect_payload(assume_full_edging = true, edge_options = nil)
      edge_options = normalize_edge_options(edge_options)
      model = Sketchup.active_model
      cache_key = export_payload_cache_key(model)
      # The ABF worksheet displays assumed sides, so its cached base must also
      # change when the minimum thickness for estimate mode changes.
      base_cache_key = [cache_key, assume_full_edging, edge_options[:min_thickness_mm]]
      if cache_key && @edge_base_cache_key == base_cache_key && @edge_base_cache
        return build_payload_from_edge_base(deep_dup_data(@edge_base_cache), edge_options)
      end

      instance_records = collect_instance_records(model)
      sheet_id_to_material, material_stats = collect_sheet_stats(model, instance_records)
      board_rows = build_board_rows(material_stats)
      material_candidates = material_stats.values
        .select { |stat| numeric_or_nil(stat[:thickness_mm]) }
        .map { |stat| { material_code: stat[:material_code], thickness_mm: numeric_or_nil(stat[:thickness_mm]) } }
      board_to_sheet = collect_board_sheet_ids
      edge_summary = {
        boards: 0,
        faces: 0,
        missing_material_boards: 0,
        inferred_material_boards: 0,
        missing_edge_types: 0,
        missing_edge_material_boards: 0
      }

      instance_records.each do |record|
        entity = record[:entity]
        transform = record[:transform]
        path_names = record[:path_names]
        next if nesting_path?(path_names)
        next unless panel_entity?(entity, assume_full_edging)

        edge_types = parse_edge_types(abf_attr(entity, 'edge-band-types'))
        next if edge_types.empty? && !assume_full_edging

        board_index = abf_attr(entity, 'board-index')
        sheet_id = board_to_sheet[board_index.to_i]
        material_code = material_from_board(entity, sheet_id, sheet_id_to_material)
        inferred = false
        unless material_code
          material_code = infer_material_by_thickness(entity, transform, material_candidates)
          inferred = !material_code.nil?
        end
        material_code ||= UNKNOWN_MATERIAL
        material_stat = material_stats[material_code]

        edge_summary[:boards] += 1
        edge_summary[:inferred_material_boards] += 1 if inferred
        edge_summary[:missing_material_boards] += 1 if material_code == UNKNOWN_MATERIAL
        # Nẹp is reported under the panel material code, not under the edge
        # band's own code (for example, MDFCA.18... / PLY.17...).  In estimate
        # mode, only sides without an ABF edge band receive the assumed band.
        actual_edge_sides = record[:actual_edge_sides] ||= edge_band_sides(entity, transform, edge_types)
        assumed_edge_sides = if assume_full_edging
          record[:assumed_edge_sides] ||= assumed_edge_band_sides(
            entity, transform, edge_types, material_code, actual_edge_sides
          )
        end
        edge_sides = [actual_edge_sides, assumed_edge_sides].compact
        edge_summary[:faces] += edge_sides.sum { |sides| sides[:face_count].to_i }
        edge_summary[:missing_edge_types] += actual_edge_sides[:missing_edge_types].to_i
        if edge_sides.all? { |sides| sides[:material_totals].empty? }
          edge_summary[:missing_edge_material_boards] += 1
        end
        append_edge_totals(material_stat, actual_edge_sides, :actual)
        append_edge_totals(material_stat, assumed_edge_sides, :assumed) if assumed_edge_sides
      end

      abf_excel_data = collect_abf_excel_data(
        model,
        board_to_sheet,
        sheet_id_to_material,
        instance_records,
        assume_full_edging,
        edge_options
      )
      sheet_count = material_stats.values.sum { |s| s[:sheet_ids].size }
      base = {
        generated_at: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        source_model: model.path.to_s,
        content: model.path.to_s.empty? ? model.title.to_s : File.basename(model.path, '.*'),
        board_rows: board_rows,
        material_stats: deep_dup_data(material_stats),
        abf_excel_data: abf_excel_data,
        assume_full_edging: assume_full_edging,
        summary: {
          abf_data_rows: Array(abf_excel_data[:rows]).length,
          sheet_count: sheet_count,
          edge_boards: edge_summary[:boards],
          edge_faces: edge_summary[:faces],
          inferred_material_boards: edge_summary[:inferred_material_boards],
          missing_material_boards: edge_summary[:missing_material_boards],
          missing_edge_types: edge_summary[:missing_edge_types],
          missing_edge_material_boards: edge_summary[:missing_edge_material_boards]
        }
      }
      if cache_key
        @edge_base_cache_key = base_cache_key
        @edge_base_cache = deep_dup_data(base)
      end
      build_payload_from_edge_base(base, edge_options)
    end

    def build_payload_from_edge_base(base, edge_options)
      material_stats = deep_dup_data(base[:material_stats])
      edge_rows = build_edge_rows(material_stats, edge_options)
      rows = Array(base[:board_rows]) + edge_rows
      summary = deep_dup_data(base[:summary]).merge(
        material_count: rows.map { |row| row[:material_code] }.uniq.size,
        row_count: rows.size,
        edge_band_m: edge_rows.sum { |row| row[:quantity].to_f }.round,
        assume_full_edging: !!base[:assume_full_edging],
        edge_options: edge_options
      )
      {
        generated_at: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        source_model: base[:source_model],
        content: base[:content],
        rows: rows,
        abf_excel_data: deep_dup_data(base[:abf_excel_data]),
        summary: summary
      }
    end

    def collect_abf_excel_data(model, board_to_sheet, sheet_id_to_material, instance_records = nil, assume_full_edging = true, edge_options = nil)
      edge_options = normalize_edge_options(edge_options)
      edge_columns = []
      pending_rows = []
      records = instance_records || collect_instance_records(model)
      records.each do |record|
        entity = record[:entity]
        transform = record[:transform]
        path_names = record[:path_names]
        next if nesting_path?(path_names)
        next unless panel_entity?(entity, assume_full_edging) && board_index_entity?(entity)

        board_index = abf_attr(entity, 'board-index').to_i
        dimensions = board_dimensions_mm(entity, transform)
        material_code = entity_material_code(entity)
        sheet_id = board_to_sheet[board_index]
        material_code = material_from_board(entity, sheet_id, sheet_id_to_material).to_s if material_code.empty?
        product = product_code_from_text((path_names + [entity.name.to_s]).join(' '))
        label = clean_abf_label(entity.name.to_s)
        edge_types = parse_edge_types(abf_attr(entity, 'edge-band-types'))
        next if edge_types.empty? && !assume_full_edging
        actual_edge_sides = record[:actual_edge_sides] ||= edge_band_sides(entity, transform, edge_types)
        edge_sides = if assume_full_edging && edge_band_allowed?(entity, transform, nil, edge_options)
          assumed_edge_sides = record[:assumed_edge_sides] ||= assumed_edge_band_sides(
            entity, transform, edge_types, material_code, actual_edge_sides
          )
          merge_edge_sides(actual_edge_sides, assumed_edge_sides)
        else
          # Actual ABF bands are always reported, including on thin panels.
          # The thickness rule applies only to extra, estimated bands.
          actual_edge_sides
        end
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
          actual_edge_bands: Hash.new(0.0),
          assumed_edge_bands: Hash.new(0.0)
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

    def export_payload_cache_key(model, _assume_full_edging = nil)
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

    def empty_edge_material_stats
      Hash.new do |hash, code|
        hash[code] = {
          material_code: code.to_s,
          edge_bands: Hash.new(0.0)
        }
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

    def build_rows(material_stats, _edge_material_stats = nil)
      build_board_rows(material_stats) + build_edge_rows(material_stats)
    end

    def build_board_rows(material_stats)
      rows = []
      material_stats.values
        .select { |stat| stat[:sheet_ids].any? }
        .sort_by { |stat| stat[:material_code].to_s }
        .each do |stat|
          material_code = stat[:material_code].to_s
          sheet_qty = stat[:sheet_ids].size
          if sheet_qty.positive?
            rows << {
              name: 'Ván',
              size: MH::MaterialCode.export_size(material_code, fallback: format_mm(stat[:thickness_mm])),
              material_code: material_code,
              unit: 'tấm',
              quantity: sheet_qty,
              note: ''
            }
          end

        end
      rows
    end

    def build_edge_rows(material_stats, edge_options = nil)
      edge_options = normalize_edge_options(edge_options)
      rows = []
      material_stats.values
        .sort_by { |stat| stat[:material_code].to_s }
        .each do |stat|
          # Recorded ABF bands are valid regardless of panel thickness. The
          # minimum-thickness option only controls estimate-only additions.
          edge_bands = Hash.new(0.0)
          actual_edge_bands = stat[:actual_edge_bands] || stat[:edge_bands] || {}
          assumed_edge_bands = stat[:assumed_edge_bands] || {}
          actual_edge_bands.each { |key, meters| edge_bands[key] += meters.to_f }
          if material_edge_band_allowed?(stat, edge_options)
            assumed_edge_bands.each { |key, meters| edge_bands[key] += meters.to_f }
          end
          next if edge_bands.empty?

          # Multiple ABF labels may share one purchasing name (for example,
          # "Nẹp chém vát" and "Nẹp 36" both become "Nẹp 44"). Nẹp 44 is
          # also purchased as one item, so its 0mm/1mm variants are combined.
          purchase_bands = Hash.new(0.0)
          edge_bands.each do |(name, thickness), meters|
            purchase_name = edge_row_name(name)
            purchase_thickness = purchase_name == 'Nẹp 44' ? nil : thickness
            purchase_bands[[purchase_name, purchase_thickness]] += meters.to_f * edge_multiplier_for(purchase_name, edge_options)
          end
          purchase_bands
            .sort_by { |(name, thickness), _m| [name.to_s, thickness.to_f] }
            .each do |(name, thickness), meters|
              next if meters <= 0

              rows << {
                name: name,
                size: thickness.nil? ? '' : format_mm(thickness),
                material_code: stat[:material_code].to_s,
                unit: 'md',
                quantity: meters.round,
                note: edge_factor_note(name, edge_options)
              }
            end
        end
      rows
    end

    def append_edge_totals(material_stat, edge_sides, source = :actual)
      return unless material_stat && edge_sides

      bucket_key = source == :assumed ? :assumed_edge_bands : :actual_edge_bands
      material_stat[bucket_key] ||= Hash.new(0.0)
      edge_sides[:material_totals].each do |(_edge_code, edge_name, thickness), length_m|
        name = edge_name.to_s.strip
        next if name.empty? || length_m.to_f <= 0

        material_stat[bucket_key][[name, thickness.to_f]] += length_m.to_f
      end
    end

    def edge_multiplier_for(edge_name, edge_options)
      case edge_row_name(edge_name)
      when 'Nẹp 22' then edge_options[:nep22_multiplier].to_f
      when 'Nẹp 44' then edge_options[:nep44_multiplier].to_f
      when 'Nẹp 60' then edge_options[:nep60_multiplier].to_f
      else 1.0
      end
    end

    def edge_factor_note(edge_name, edge_options)
      factor = edge_multiplier_for(edge_name, edge_options)
      factor == 1.0 ? '' : "Hệ số ×#{format_number(factor)}"
    end

    def edge_band_allowed?(entity, transform, material_stat, edge_options)
      thickness = material_stat && numeric_or_nil(material_stat[:thickness_mm])
      thickness ||= board_dimensions_mm(entity, transform)[:thickness]
      thickness.to_f >= edge_options[:min_thickness_mm].to_f
    rescue StandardError
      true
    end

    def material_edge_band_allowed?(material_stat, edge_options)
      thickness = numeric_or_nil(material_stat[:thickness_mm])
      return true unless thickness

      thickness >= edge_options[:min_thickness_mm].to_f
    end

    def cached_board_rows(payload)
      return [] unless payload.is_a?(Hash)

      Array(payload[:rows]).select { |row| row[:unit].to_s.downcase == 'tấm' }
    rescue StandardError
      []
    end

    def regroup_preview_rows(rows, show_paint_code)
      # One Python call per batch; repeated previews reuse names until the
      # shared workbook or engine changes. Never spawn Python for each row.
      codes = rows.select { |row| export_item_name(row[:name]) == 'VÁN' }
                  .map { |row| export_material_code(row[:material_code], show_paint_code) }
      MH::MaterialItemNames.names(codes, python: python_command) unless codes.empty?
      grouped = {}
      rows.each do |row|
        export_code = export_material_code(row[:material_code], show_paint_code)
        item_name = export_item_name(row[:name])
        size = row[:unit].to_s == 'tấm' ? MH::MaterialCode.export_size(export_code, fallback: row[:size]) : row[:size]
        key = [item_name, size.to_s, export_code.to_s, row[:unit].to_s]
        target = grouped[key] ||= row.merge(
          name: item_name,
          size: size,
          material_code: export_code,
          quantity: 0.0,
          note: row[:note].to_s
        )
        target[:quantity] = target[:quantity].to_f + row[:quantity].to_f
      end

      grouped.values
        .sort_by { |row| [row[:material_code].to_s, row[:unit].to_s == 'tấm' ? 0 : 1, row[:name].to_s] }
        .each do |row|
          row[:quantity] = row[:quantity].round
          item_name = row[:name].to_s.strip == 'VÁN' ? board_row_name(row[:material_code]) : row[:name]
          row[:name] = export_item_name(item_name)
        end
    end

    # "Tên hàng" is an export-facing purchase name. Normalize it before
    # grouping as well as display so names that differ only by letter case are
    # kept in a single row.
    def export_item_name(value)
      value.to_s.strip.upcase
    end

    def board_row_name(material_code)
      code = material_code.to_s.strip
      MH::MaterialItemNames.names([code], python: python_command).fetch(code)
    end

    # Kept as a compatibility entry point; the rules live in the shared engine.
    def material_item_name_qualifiers(material_code)
      MH::MaterialItemNames.qualifiers(material_code, python: python_command)
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

        side = classify_edge_side(face.normal, face_transform, axes) if axes
        sides[:banded_sides][side] = true if side

        info = edge_types[edge_id.to_i]
        unless info
          sides[:missing_edge_types] += 1
          next
        end

        length_m = max_edge_length_m(face, face_transform)
        sides[:face_count] += 1
        material_key = edge_material_key(info)
        sides[:material_totals][material_key] += length_m.to_f
        next unless axes

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

    # MH_nep stores the selected edge band as an EdgeBandType. This export-only
    # path fills only the small panel edges that are not already banded in ABF,
    # without changing the model or writing ABF EdgeBandData back to it.
    def assumed_edge_band_sides(entity, transform, edge_types = nil, fallback_material_code = nil, actual_sides = nil)
      sides = blank_edge_sides
      config = assumed_edge_band_config(edge_types || {}, fallback_material_code)
      return sides unless config[:primary]

      axes = board_plane_axes(entity, transform)
      return sides unless axes
      config[:primary_side] = primary_side_for_direction(config[:direction], axes)

      side_lengths = {
        top: axes[:length_length].to_f * MM_PER_INCH / 1000.0,
        bot: axes[:length_length].to_f * MM_PER_INCH / 1000.0,
        right: axes[:width_length].to_f * MM_PER_INCH / 1000.0,
        left: axes[:width_length].to_f * MM_PER_INCH / 1000.0
      }

      side_lengths.each do |side, length_m|
        next if edge_side_banded?(actual_sides, side)

        source = assumed_source_for_side(side, config, entity)
        next unless source && length_m.positive?

        info = edge_info_from_source(source)
        next if edge_material_code(info).empty?

        value = edge_band_display(info)
        material_key = edge_material_key(info)
        sides[side] = edge_side_marker(side)
        sides[:"_#{side}_"] = value
        sides[:edge_lengths][side] = length_m * 1000.0
        sides[:edge_thicknesses][side] = info[:thickness_mm].to_f
        sides[:edge_totals][value] += length_m
        sides[:material_totals][material_key] += length_m
        sides[:face_count] += 1
      end
      sides
    rescue StandardError => error
      warn_error(error)
      blank_edge_sides
    end

    def edge_side_banded?(edge_sides, side)
      return false unless edge_sides.is_a?(Hash)

      edge_sides.dig(:banded_sides, side) ||
        edge_sides[side].to_s.strip != '' ||
        edge_sides.dig(:edge_lengths, side).to_f.positive?
    rescue StandardError
      false
    end

    # Combines actual ABF bands with the estimate-only bands added on missing
    # sides. The actual side keeps its label and thickness, while totals from
    # both sources remain available to the ABF worksheet and material summary.
    def merge_edge_sides(*sources)
      result = blank_edge_sides
      side_names = %i[top right bot left]

      Array(sources).compact.each do |source|
        result[:face_count] += source[:face_count].to_i
        result[:missing_edge_types] += source[:missing_edge_types].to_i
        source[:edge_totals].to_h.each { |name, length| result[:edge_totals][name] += length.to_f }
        source[:material_totals].to_h.each { |key, length| result[:material_totals][key] += length.to_f }

        side_names.each do |side|
          next unless edge_side_banded?(source, side)

          result[:banded_sides][side] = true
          result[side] = edge_side_marker(side)
          result[:"_#{side}_"] = join_edge_values([result[:"_#{side}_"], source[:"_#{side}_"]])
          result[:edge_lengths][side] = [result[:edge_lengths][side].to_f, source.dig(:edge_lengths, side).to_f].max
          result[:edge_thicknesses][side] = [result[:edge_thicknesses][side].to_f, source.dig(:edge_thicknesses, side).to_f].max
        end
      end
      result
    rescue StandardError => error
      warn_error(error)
      blank_edge_sides
    end

    def assumed_edge_band_config(edge_types, _fallback_material_code = nil)
      fallback = edge_types.values.first
      fallback_source = fallback && edge_source_from_info(fallback)
      library = []
      options = {}

      if defined?(MH::Nep)
        library = mh_nep_edge_band_library
        options = MH::Nep.load_defaults if MH::Nep.respond_to?(:load_defaults)
      end

      primary = library_item_by_id(library, options['primary_id'])
      other = library_item_by_id(library, options['other_id'])
      veneer = library_item_by_id(library, options['veneer_id'])
      primary ||= fallback_source
      # Some ABF models have no edge-band settings instantiated yet. Keep
      # estimate mode usable with the generic band (normalized to Nẹp 22),
      # but never fall back to the panel material code as if it were a band.
      primary ||= {
        name: 'Nẹp',
        display_name: 'Nẹp',
        thickness: DEFAULT_ASSUMED_EDGE_THICKNESS_MM,
        width: 0.0,
        color: ''
      }
      other ||= primary

      config = {
        mode: options['mode'].to_s == 'view' ? 'view' : 'plain',
        direction: options['direction'].to_s,
        primary: primary,
        other: other,
        veneer: veneer,
        material_rule_enabled: truthy?(options['material_rule_enabled']),
        material_prefix: options['material_prefix'].to_s.strip
      }
      config
    rescue StandardError => error
      warn_error(error)
      { mode: 'plain', direction: '', primary: fallback_source, other: fallback_source,
        veneer: nil, material_rule_enabled: false, material_prefix: '', primary_side: nil }
    end

    def mh_nep_edge_band_library
      return [] unless defined?(MH::Nep) && MH::Nep.respond_to?(:edge_band_library)

      library = Array(MH::Nep.edge_band_library)
      return library unless library.empty?

      # ABF may finish creating EdgeBandSetting objects only after the first
      # edge-band editor request. Allow one bounded retry rather than caching
      # that temporary empty state for the entire export session.
      @mh_nep_bootstrap_attempts = @mh_nep_bootstrap_attempts.to_i + 1
      return [] if @mh_nep_bootstrap_attempts > 2

      if defined?(ABF::Menu) && ABF::Menu.respond_to?(:instance)
        ABF::Menu.instance.on_click_edit_edge_band
      end
      Array(MH::Nep.edge_band_library)
    rescue StandardError => error
      warn_error(error)
      []
    end

    def library_item_by_id(library, id)
      return nil if id.to_s.strip.empty?

      item = Array(library).find { |candidate| candidate[:id].to_i == id.to_i }
      item && edge_source_from_library_item(item)
    end

    def edge_source_from_library_item(item)
      {
        name: item[:name].to_s.strip,
        display_name: item[:display_name].to_s.strip,
        thickness: item[:thickness].to_f,
        width: item[:width].to_f,
        color: item[:color].to_s
      }
    end

    def edge_source_from_info(info)
      {
        name: edge_material_code(info),
        display_name: info[:display_name].to_s.strip,
        thickness: info[:thickness_mm].to_f,
        width: info[:width].to_f,
        color: info[:color].to_s
      }
    end

    def edge_info_from_source(source)
      {
        raw_name: source[:display_name].to_s.strip,
        name: source[:name].to_s.strip,
        display_name: source[:display_name].to_s.strip,
        material_code: source[:name].to_s.strip,
        thickness_mm: source[:thickness].to_f,
        width: source[:width].to_f,
        color: source[:color].to_s
      }
    end

    def edge_material_key(info)
      code = edge_material_code(info)
      label = info[:display_name].to_s.strip
      label = info[:raw_name].to_s.strip if label.empty?
      label = info[:name].to_s.strip if label.empty?
      [code, label, info[:thickness_mm].to_f]
    end

    def edge_material_code(info)
      code = info[:material_code].to_s.strip
      code = info[:name].to_s.strip if code.empty?
      code = info[:raw_name].to_s.strip if code.empty?
      code = info[:display_name].to_s.strip if code.empty?
      code
    end

    def assumed_source_for_side(side, config, entity)
      if config[:veneer] && config[:material_rule_enabled] && veneer_material_for_export?(entity, config)
        return config[:veneer]
      end
      return config[:primary] unless config[:mode] == 'view'

      side == config[:primary_side] ? config[:primary] : (config[:other] || config[:primary])
    end

    def veneer_material_for_export?(entity, config)
      prefix = config[:material_prefix].to_s.strip
      return false if prefix.empty?

      names = [entity_material_code(entity), abf_attr(entity, 'sheet-type')]
      names.any? { |name| name.to_s.downcase.include?(prefix.downcase) }
    end

    def primary_side_for_direction(direction, axes)
      target = {
        'x-' => X_AXIS.reverse,
        'x+' => X_AXIS,
        'y-' => Y_AXIS.reverse,
        'y+' => Y_AXIS,
        'z-' => Z_AXIS.reverse,
        'z+' => Z_AXIS
      }[direction.to_s]
      return nil unless target && axes

      normals = {
        top: axes[:width_axis],
        bot: axes[:width_axis].reverse,
        right: axes[:length_axis],
        left: axes[:length_axis].reverse
      }
      side, score = normals
        .map { |name, normal| [name, normal.dot(target)] }
        .max_by { |_name, value| value.to_f }
      score.to_f >= 0.65 ? side : nil
    rescue StandardError
      nil
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
        banded_sides: Hash.new(false),
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
        length_axis: plane_axes[1][:vector],
        width_length: plane_axes[0][:length],
        length_length: plane_axes[1][:length]
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
      name = info[:display_name].to_s
      name = info[:raw_name].to_s if name.empty?
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

    def panel_entity?(entity, assume_full_edging = false)
      return board_entity?(entity) unless assume_full_edging
      return false unless entity.respond_to?(:definition)

      board_index = abf_attr(entity, 'board-index')
      is_board = abf_attr(entity, 'is-board')
      sheet_type = abf_attr(entity, 'sheet-type').to_s.strip
      sheet_id = abf_attr(entity, 'sheet-id')
      !!is_board || !board_index.nil? || !sheet_id.nil? || !sheet_type.empty?
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
          material_code: name.to_s.strip,
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
      clean = clean.tr("–—", '--')
      # ABF's generic "Nẹp" label is the same purchasing item as Nẹp 22.
      # Normalize it before aggregation so their meters are combined and the
      # Nẹp 22 multiplier is applied to the complete total.
      return 'Nẹp 22' if clean.empty?
      return 'Nẹp 22' if clean.match?(/\A-?\s*1(?:[.,]0+)?\s*mm\b/i)
      return 'Nẹp 44' if clean.match?(/\A(?:chém\s+vát|chem\s+vat)\b/i)
      return 'Nẹp 44' if clean.match?(/\A36(?:\b|\s*-)/i)

      "Nẹp #{clean}"
    end

    def default_output_name(model)
      base = model.path.to_s.empty? ? model.title.to_s : File.basename(model.path, '.*')
      base = 'MH_EXPORT' if base.to_s.strip.empty?
      # Keep the project code first and move the customer name after the
      # document type; the nesting stage is not part of the purchase filename.
      base = base.strip.sub(/_NESTING\d*(?=\s|\z)/i, '')
      project_code, customer_name = base.split(/\s+/, 2)
      customer_suffix = customer_name.to_s.empty? ? '' : " #{customer_name}"
      "#{project_code}__DMVT-VAN#{customer_suffix}.xlsx"
    end

    def python_command
      configured = defined?(Sketchup) ? Sketchup.read_default(PREF_KEY, 'python_path', nil).to_s.strip : ''
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

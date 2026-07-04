# encoding: UTF-8

require 'sketchup.rb'
require 'json'

module MH
  module Nep
    extend self

    PLUGIN_NAME = 'MH Nep'.freeze
    PREF_KEY = 'MH_Nep'.freeze
    EPSILON = 1.0e-6
    PARALLEL_COSINE = Math.cos(8.0 * Math::PI / 180.0)
    FINISH_GROUP_PREFIXES = [
      ['VERKTSOI', 'VERKTSOI'],
      ['VERSOI', 'VERSOI'],
      ['VERKT', 'VERKT'],
      ['VENE', 'VER'],
      ['VER', 'VER'],
      ['LK', 'LK'],
      ['MS', 'MS'],
      ['KL', 'KL']
    ].freeze

    DIRECTIONS = {
      'y-' => { label: 'Trước (Y- => Y+)', axis: Y_AXIS.reverse },
      'y+' => { label: 'Sau (Y+ => Y-)', axis: Y_AXIS },
      'x-' => { label: 'Trái (X- => X+)', axis: X_AXIS.reverse },
      'x+' => { label: 'Phải (X+ => X-)', axis: X_AXIS },
      'z+' => { label: 'Trên (Z+ => Z-)', axis: Z_AXIS },
      'z-' => { label: 'Dưới (Z- => Z+)', axis: Z_AXIS.reverse }
    }.freeze

    def show
      activate_abf_bridge
    end

    def show_settings
      @dialog ||= build_dialog
      @dialog.visible? ? @dialog.bring_to_front : @dialog.show
      UI.start_timer(0.1, false) { refresh_dialog }
    end

    def activate_hud
      return status_payload(false, 'ABF chưa load, hãy bật ABF rồi thử lại.') unless abf_ready?

      options = load_defaults
      library = edge_band_library
      active_tool = Sketchup.active_model.tools.active_tool
      if active_tool.is_a?(ManualTool)
        active_tool.refresh_state(options, library, false)
        Sketchup.active_model.active_view.invalidate
      else
        Sketchup.active_model.select_tool(ManualTool.new(options, library, false))
      end
      status_payload(true, 'Đã bật HUD MH Nep.')
    rescue StandardError => error
      warn_error(error)
      status_payload(false, error.message)
    end

    def activate_abf_bridge
      return activate_hud unless defined?(ABF::Menu) && defined?(ABF::EditEdgeBandTool)

      install_abf_bridge!
      unless Sketchup.active_model.tools.active_tool.is_a?(ABF::EditEdgeBandTool)
        ABF::Menu.instance.on_click_edit_edge_band
      end
      Sketchup.active_model.active_view.invalidate
      status_payload(true, 'Đã bật chế độ dán nẹp ABF + HUD MH Nep.')
    rescue StandardError => error
      warn_error(error)
      activate_hud
    end

    def install_abf_bridge!
      return if ABF::EditEdgeBandTool.instance_variable_get(:@mh_nep_bridge_installed)

      ABF::EditEdgeBandTool.class_eval do
        alias_method :mh_nep_original_draw, :draw
        alias_method :mh_nep_original_on_lbutton_down, :onLButtonDown
        alias_method :mh_nep_original_on_key_down, :onKeyDown

        def draw(view)
          mh_nep_original_draw(view)
          @mh_nep_buttons = MH::Nep.draw_abf_bridge_hud(view, @mh_nep_status)
        rescue StandardError => error
          MH::Nep.warn_error(error)
        end

        def onLButtonDown(flags, x, y, view)
          hit = MH::Nep.hud_hit(@mh_nep_buttons || {}, x, y)
          if hit
            @mh_nep_status = MH::Nep.handle_abf_bridge_action(hit)
            view.invalidate
            return true
          end

          mh_nep_original_on_lbutton_down(flags, x, y, view)
        end

        def onKeyDown(key, repeat, flags, view)
          mh_nep_original_on_key_down(key, repeat, flags, view)
        end
      end

      ABF::EditEdgeBandTool.instance_variable_set(:@mh_nep_bridge_installed, true)
    rescue StandardError => error
      warn_error(error)
    end

    def build_dialog
      dialog = UI::HtmlDialog.new(
        dialog_title: "#{PLUGIN_NAME} Setting",
        preferences_key: PREF_KEY,
        width: 500,
        height: 720,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      dialog.set_file(File.join(__dir__, 'ui.html'))

      dialog.add_action_callback('ready') { refresh_dialog }
      dialog.add_action_callback('refresh_library') { refresh_dialog }
      dialog.add_action_callback('save_settings') do |_ctx, payload|
        save_defaults(default_options.merge(parse_payload(payload)))
      end
      dialog.add_action_callback('hud') do |_ctx, payload|
        save_defaults(default_options.merge(parse_payload(payload)))
        respond_to_dialog(dialog, activate_abf_bridge)
      end
      dialog.add_action_callback('apply') { |_ctx, payload| respond_to_dialog(dialog, apply_from_options(parse_payload(payload))) }
      dialog.add_action_callback('apply_all') do |_ctx, payload|
        options = parse_payload(payload).merge('scope' => 'model')
        respond_to_dialog(dialog, apply_from_options(options))
      end
      dialog.add_action_callback('manual') do |_ctx, payload|
        save_defaults(default_options.merge(parse_payload(payload)))
        result = activate_abf_bridge
        respond_to_dialog(dialog, result)
      end
      dialog.add_action_callback('clear') { |_ctx, payload| respond_to_dialog(dialog, clear_from_options(parse_payload(payload))) }

      dialog
    end

    def respond_to_dialog(dialog, result)
      dialog.execute_script("window.mhNepSetStatus(#{result.to_json})")
    rescue StandardError => error
      warn_error(error)
    end

    def parse_payload(payload)
      JSON.parse(payload.to_s)
    rescue StandardError
      {}
    end

    def refresh_dialog
      return unless @dialog

      payload = {
        ok: abf_ready?,
        abf_ready: abf_ready?,
        directions: DIRECTIONS.map { |key, data| { key: key, label: data[:label] } },
        library: edge_band_library,
        defaults: load_defaults
      }
      @dialog.execute_script("window.mhNepLoad(#{payload.to_json})")
    rescue StandardError => error
      warn_error(error)
    end

    def abf_ready?
      !!(defined?(ABF::EditEdgeBand) &&
        defined?(ABF::EditEdgeBand::EdgeBandData) &&
        defined?(ABF::EdgeBandType) &&
        defined?(ABF::EdgeBandSetting))
    end

    def edge_band_library
      return [] unless abf_ready?

      settings = {}
      ObjectSpace.each_object(ABF::EdgeBandSetting) do |setting|
        id = safe_call(setting, :id)
        next unless id
        next if (setting.instance_variable_get(:@is_divider) rescue false)
        next if (setting.instance_variable_get(:@is_hidden) rescue false)

        name = safe_call(setting, :name).to_s.strip
        next if name.empty?

        item = {
          id: id.to_i,
          name: name,
          display_name: safe_call(setting, :display_name).to_s,
          thickness: safe_call(setting, :_thickness).to_f,
          width: safe_call(setting, :_width).to_f,
          color: safe_call(setting, :_color).to_s,
          index: setting.instance_variable_get(:@index)
        }
        old = settings[id.to_i]
        settings[id.to_i] = item if old.nil? || (old[:index].nil? && !item[:index].nil?)
      end

      settings.values.sort_by { |item| [item[:index] || 999_999, item[:display_name]] }
    rescue StandardError => error
      warn_error(error)
      []
    end

    def safe_call(object, method_name)
      object.respond_to?(method_name) ? object.public_send(method_name) : nil
    rescue StandardError
      nil
    end

    def load_defaults
      path = File.join(__dir__, 'options.json')
      return default_options unless File.exist?(path)

      raw = File.read(path, mode: 'r:BOM|UTF-8')
      default_options.merge(JSON.parse(raw))
    rescue StandardError
      default_options
    end

    def save_defaults(options)
      path = File.join(__dir__, 'options.json')
      File.write(path, JSON.pretty_generate(options), mode: 'w:UTF-8')
    rescue StandardError => error
      warn_error(error)
    end

    def default_options
      {
        'mode' => 'view',
        'direction' => 'y-',
        'scope' => 'selection',
        'primary_id' => nil,
        'other_id' => nil,
        'min_thickness_mm' => '',
        'max_thickness_mm' => '',
        'min_edge_length_mm' => '',
        'material_rule_enabled' => false,
        'material_prefix' => 'ver',
        'veneer_id' => nil,
        'ignore_names' => ''
      }
    end

    def apply_from_options(options)
      return status_payload(false, 'ABF chưa load, hãy bật ABF rồi thử lại.') unless abf_ready?

      options = default_options.merge(options || {})
      save_defaults(options)

      library = edge_band_library
      primary = find_library_item(library, options['primary_id'])
      other = find_library_item(library, options['other_id'])
      veneer = find_library_item(library, options['veneer_id']) || library.find { |item| (item[:thickness].to_f - 0.5).abs < 0.001 }

      return status_payload(false, 'Chọn nẹp chính trước khi dán.') unless primary

      targets = target_entities(options['scope'])
      return status_payload(false, 'Không tìm thấy tấm để dán.') if targets.empty?

      context = apply_context(options, primary, other, veneer)
      model = Sketchup.active_model
      stats = empty_stats
      model.start_operation('MH Nep Apply', true)
      targets.each { |entity| apply_to_entity(entity, context, stats) }
      model.commit_operation
      model.active_view.invalidate

      status_payload(stats[:errors].empty?, stats_message(stats), stats)
    rescue StandardError => error
      Sketchup.active_model.abort_operation rescue nil
      warn_error(error)
      status_payload(false, error.message)
    end

    def clear_from_options(options)
      return status_payload(false, 'ABF chưa load, hãy bật ABF rồi thử lại.') unless abf_ready?

      targets = target_entities((options || {})['scope'])
      return status_payload(false, 'Không tìm thấy tấm để xóa nẹp.') if targets.empty?

      model = Sketchup.active_model
      cleared = 0
      model.start_operation('MH Nep Clear', true)
      targets.each do |entity|
        next unless container?(entity)

        ABF::EditEdgeBand.clear_data(entity)
        cleared += 1
      end
      model.commit_operation
      model.active_view.invalidate
      status_payload(true, "Đã xóa nẹp #{cleared} tấm", { processed: cleared, skipped: 0, filtered: 0, errors: [] })
    rescue StandardError => error
      Sketchup.active_model.abort_operation rescue nil
      warn_error(error)
      status_payload(false, error.message)
    end

    def activate_manual(options)
      return status_payload(false, 'ABF chưa load, hãy bật ABF rồi thử lại.') unless abf_ready?

      active_tool = Sketchup.active_model.tools.active_tool
      if active_tool.is_a?(ManualTool)
        active_tool.refresh_state(default_options.merge(options || {}), edge_band_library, true)
        Sketchup.active_model.active_view.invalidate
        return status_payload(true, 'Đã bật dán tay MH Nep.')
      end

      options = default_options.merge(options || {})
      save_defaults(options)
      library = edge_band_library
      return status_payload(false, 'Thư viện ABF chưa có nẹp để dán tay.') if library.empty?

      Sketchup.active_model.select_tool(ManualTool.new(options, library))
      status_payload(true, 'Đã bật dán tay MH Nep: Tab đổi nẹp, click mặt cạnh để dán.')
    rescue StandardError => error
      warn_error(error)
      status_payload(false, error.message)
    end

    def apply_context(options, primary, other, veneer)
      mode = options['mode'].to_s == 'plain' ? 'plain' : 'view'
      direction_key = DIRECTIONS.key?(options['direction'].to_s) ? options['direction'].to_s : 'y-'
      {
        mode: mode,
        direction_key: direction_key,
        primary: primary,
        other: other,
        veneer: veneer,
        min_thickness_mm: number_or_nil(options['min_thickness_mm']),
        max_thickness_mm: number_or_nil(options['max_thickness_mm']),
        min_edge_length_mm: number_or_nil(options['min_edge_length_mm']),
        material_rule_enabled: truthy?(options['material_rule_enabled']) || options['material_prefix'].to_s.strip.downcase == 'ver',
        material_prefix: options['material_prefix'].to_s.strip.downcase,
        ignore_tokens: ignore_tokens(options['ignore_names'])
      }
    end

    def ignore_tokens(value)
      value.to_s.split(/[\n,;|]+/).map { |text| text.strip.downcase }.reject(&:empty?).uniq
    end

    def ignored_entity?(entity, context_or_tokens)
      tokens = context_or_tokens.is_a?(Hash) ? context_or_tokens[:ignore_tokens] : context_or_tokens
      tokens = Array(tokens).map { |token| token.to_s.downcase }.reject(&:empty?)
      return false if tokens.empty?

      names = [entity_label(entity)]
      names << entity.name if entity.respond_to?(:name)
      names << entity.definition.name if entity.respond_to?(:definition) && entity.definition
      names << entity.layer.name if entity.respond_to?(:layer) && entity.layer
      haystack = names.compact.map(&:to_s).map(&:downcase).reject(&:empty?)
      tokens.any? { |token| haystack.any? { |name| name.include?(token) } }
    rescue StandardError
      false
    end

    def number_or_nil(value)
      text = value.to_s.strip.tr(',', '.')
      return nil if text.empty?

      text.to_f
    end

    def truthy?(value)
      value == true || value.to_s == 'true' || value.to_s == '1'
    end

    def empty_stats
      { processed: 0, skipped: 0, filtered: 0, banded_faces: 0, errors: [] }
    end

    def stats_message(stats)
      message = "Đã dán #{stats[:processed]} tấm"
      message += ", #{stats[:banded_faces]} cạnh"
      message += ", lọc #{stats[:filtered]} tấm/cạnh" if stats[:filtered] > 0
      message += ", bỏ qua #{stats[:skipped]} tấm" if stats[:skipped] > 0
      message += ", lỗi #{stats[:errors].length}" if stats[:errors].any?
      message
    end

    def find_library_item(library, id)
      id = id.to_i
      library.find { |item| item[:id].to_i == id }
    end

    def target_entities(scope)
      model = Sketchup.active_model
      selected = model.selection.to_a.select { |entity| container?(entity) }
      return selected unless scope.to_s == 'model'

      model.active_entities.grep(Sketchup::Group) +
        model.active_entities.grep(Sketchup::ComponentInstance)
    end

    def model_selection_targets
      Sketchup.active_model.selection.to_a.select { |entity| container?(entity) }
    rescue StandardError
      []
    end

    def container?(entity)
      (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) &&
        entity.valid?
    end

    def apply_to_entity(entity, context, stats)
      if ignored_entity?(entity, context)
        stats[:skipped] += 1
        return
      end

      face_infos = build_face_infos(entity)
      if face_infos.length < 6
        stats[:skipped] += 1
        return
      end

      thickness_mm = board_thickness_mm(face_infos)
      unless pass_thickness_filter?(thickness_mm, context)
        stats[:filtered] += 1
        return
      end

      largest_two = face_infos.max_by(2) { |info| info[:area] }.map { |info| info[:face] }
      candidates = face_infos.reject { |info| largest_two.include?(info[:face]) }
      before_edge_filter = candidates.length
      candidates = candidates.select { |info| pass_edge_length_filter?(info[:edge_length_mm], context) }
      stats[:filtered] += before_edge_filter - candidates.length

      assignments, type_sources = build_assignments(entity, candidates, context)
      if assignments.empty?
        stats[:skipped] += 1
        return
      end

      set_entity_edge_data(entity, direct_faces(entity), assignments, type_sources)
      stats[:processed] += 1
      stats[:banded_faces] += assignments.length
    rescue StandardError => error
      stats[:errors] << "#{entity_label(entity)}: #{error.class}: #{error.message}"
      warn_error(error)
    end

    def build_assignments(entity, face_infos, context)
      type_sources = []
      assignments = {}
      veneer_entity = veneer_material_entity?(entity, context)

      face_infos.each do |info|
        source = source_for_face(info, context, veneer_entity)
        next unless source

        type_id = type_sources.index { |item| same_type_source?(item, source) }
        unless type_id
          type_sources << source
          type_id = type_sources.length - 1
        end
        assignments[info[:face]] = type_id
      end

      [assignments, type_sources]
    end

    def source_for_face(info, context, veneer_entity)
      return context[:veneer] || context[:primary] if veneer_entity

      if context[:mode] == 'view'
        info[:direction] == context[:direction_key] ? context[:primary] : context[:other]
      else
        context[:primary]
      end
    end

    def veneer_material_entity?(entity, context)
      return false unless context[:material_rule_enabled]

      target_group = context[:material_prefix].to_s.strip.upcase
      target_group = 'VER' if target_group.empty?

      material_names(entity).any? do |name|
        group = finish_group_for_material_code(name)
        group == target_group || (target_group == 'VER' && group.start_with?('VER'))
      end
    end

    def material_names(entity)
      names = []
      names << entity.material.display_name if entity.respond_to?(:material) && entity.material
      names << entity.material.name if entity.respond_to?(:material) && entity.material
      direct_faces(entity).each do |face|
        names << face.material.display_name if face.material
        names << face.material.name if face.material
        names << face.back_material.display_name if face.back_material
        names << face.back_material.name if face.back_material
      end
      if entity.respond_to?(:definition) && entity.definition.respond_to?(:material) && entity.definition.material
        names << entity.definition.material.display_name
        names << entity.definition.material.name
      end
      names.compact.map(&:to_s).reject(&:empty?).uniq
    rescue StandardError
      []
    end

    def finish_group_for_material_code(material_code)
      parts = normalize_logical_material_code(material_code).upcase.split('.').reject(&:empty?)
      FINISH_GROUP_PREFIXES.each do |token_prefix, group_name|
        token = token_prefix.to_s.upcase
        return group_name if parts.any? { |part| part == token || part.start_with?(token) }
      end
      ''
    rescue StandardError
      ''
    end

    def normalize_logical_material_code(value)
      code = value.to_s.strip.gsub(/\s+/, '')
      return '' if code.empty?

      code.split('.').map(&:strip).reject(&:empty?).join('.')
    rescue StandardError
      value.to_s.strip
    end

    def pass_thickness_filter?(thickness_mm, context)
      return true unless thickness_mm

      min = context[:min_thickness_mm]
      max = context[:max_thickness_mm]
      return false if min && thickness_mm <= min
      return false if max && thickness_mm >= max

      true
    end

    def pass_edge_length_filter?(edge_length_mm, context)
      min = context[:min_edge_length_mm]
      return true unless min

      edge_length_mm && edge_length_mm >= min
    end

    def build_face_infos(entity)
      transformation = Sketchup.active_model.edit_transform * entity.transformation
      direct_faces(entity).map do |face|
        points = face.outer_loop.vertices.map { |vertex| vertex.position.transform(transformation) }
        normal = face_world_normal_from_points(points)
        {
          face: face,
          points: points,
          normal: normal,
          area: transformed_area(face, transformation),
          direction: dominant_direction(normal),
          edge_length_mm: inches_to_mm(max_boundary_edge_length(points))
        }
      end
    end

    def direct_faces(entity)
      entities = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
      entities.grep(Sketchup::Face)
    end

    def transformed_area(face, transformation)
      area = 0.0
      mesh = face.mesh
      mesh.polygons.each do |polygon|
        points = polygon.map { |index| mesh.point_at(index.abs).transform(transformation) }
        next if points.length < 3

        anchor = points.first
        (1...(points.length - 1)).each do |index|
          vector1 = anchor.vector_to(points[index])
          vector2 = anchor.vector_to(points[index + 1])
          area += vector1.cross(vector2).length * 0.5
        end
      end
      area
    rescue StandardError
      face.area(transformation)
    end

    def face_world_normal_from_points(points)
      anchor = points.first
      (1...(points.length - 1)).each do |index|
        normal = anchor.vector_to(points[index]).cross(anchor.vector_to(points[index + 1]))
        next if normal.length <= EPSILON

        normal.normalize!
        return normal
      end
      nil
    end

    def max_boundary_edge_length(points)
      return 0.0 if points.length < 2

      lengths = []
      points.each_with_index do |point, index|
        lengths << point.distance(points[(index + 1) % points.length])
      end
      lengths.max || 0.0
    end

    def board_thickness_mm(face_infos)
      points = face_infos.flat_map { |info| info[:points] }
      directions = direction_clusters(face_infos.map { |info| info[:normal] }.compact)
      directions = [X_AXIS, Y_AXIS, Z_AXIS] if directions.length < 3
      spans = directions.map { |direction| span_along(points, direction) }.select { |span| span > EPSILON }
      inches_to_mm(spans.min) if spans.any?
    end

    def direction_clusters(vectors)
      clusters = []
      vectors.each do |vector|
        next unless vector && vector.length > EPSILON

        direction = canonical_direction(vector)
        cluster = clusters.find { |candidate| candidate.dot(direction).abs >= PARALLEL_COSINE }
        clusters << direction unless cluster
      end
      clusters
    end

    def canonical_direction(vector)
      direction = vector.normalize
      first = [direction.x, direction.y, direction.z].find { |value| value.abs > EPSILON }
      first && first < 0.0 ? direction.reverse : direction
    end

    def span_along(points, direction)
      values = points.map { |point| point.x * direction.x + point.y * direction.y + point.z * direction.z }
      values.max - values.min
    end

    def inches_to_mm(value)
      value.to_f * 25.4
    end

    def dominant_direction(normal)
      return nil unless normal

      candidates = {
        'x+' => normal.dot(X_AXIS),
        'x-' => normal.dot(X_AXIS.reverse),
        'y+' => normal.dot(Y_AXIS),
        'y-' => normal.dot(Y_AXIS.reverse),
        'z+' => normal.dot(Z_AXIS),
        'z-' => normal.dot(Z_AXIS.reverse)
      }
      candidates.max_by { |_key, score| score }&.first
    end

    def set_entity_edge_data(entity, all_faces, assignments, type_sources)
      data = ABF::EditEdgeBand::EdgeBandData.new
      data.types = {}
      type_sources.each_with_index do |source, type_id|
        data.types[type_id] = edge_band_type_from_setting(source, type_id)
      end
      data.faces = assignments
      data.empty_faces = all_faces - assignments.keys
      ABF::EditEdgeBand.set_data(entity, data)
    end

    def edge_band_type_from_setting(source, type_id)
      ABF::EdgeBandType.new(
        type_id,
        source[:name].to_s,
        source[:thickness].to_f,
        source[:color].to_s,
        source[:width].to_f
      )
    end

    def same_type_source?(left, right)
      left[:name].to_s == right[:name].to_s &&
        left[:thickness].to_f == right[:thickness].to_f &&
        left[:width].to_f == right[:width].to_f &&
        left[:color].to_s.downcase == right[:color].to_s.downcase
    end

    def ensure_edge_data(entity)
      data = ABF::EditEdgeBand.get_data(entity)
      data = ABF::EditEdgeBand::EdgeBandData.new unless data
      data.types = {} unless data.types.is_a?(Hash)
      data.faces = {} unless data.faces.is_a?(Hash)
      data.empty_faces = [] unless data.empty_faces.is_a?(Array)
      data
    end

    def assign_manual_face(entity, face, source)
      return false if large_panel_face?(entity, face)

      data = ensure_edge_data(entity)
      type_id = data.types.find { |_id, type| type_matches_source?(type, source) }&.first
      unless type_id
        type_id = next_type_id(data.types)
        data.types[type_id] = edge_band_type_from_setting(source, type_id)
      end

      data.faces.delete(face)
      data.faces[face] = type_id
      data.empty_faces = direct_faces(entity) - data.faces.keys
      ABF::EditEdgeBand.set_data(entity, data)
      true
    end

    def large_panel_face?(entity, face)
      infos = build_face_infos(entity)
      return false if infos.length < 3

      infos.max_by(2) { |info| info[:area] }.any? { |info| info[:face] == face }
    rescue StandardError => error
      warn_error(error)
      false
    end

    def type_matches_source?(type, source)
      type.name.to_s == source[:name].to_s &&
        type.thickness.to_f == source[:thickness].to_f &&
        type.width.to_f == source[:width].to_f &&
        type.color.to_s.downcase == source[:color].to_s.downcase
    rescue StandardError
      false
    end

    def next_type_id(types)
      id = 0
      id += 1 while types.key?(id)
      id
    end

    def hex_color(value, alpha = 255)
      hex = value.to_s.strip.sub(/\A#/, '')
      if hex.length == 6
        color = Sketchup::Color.new(hex[0, 2].to_i(16), hex[2, 2].to_i(16), hex[4, 2].to_i(16))
      else
        color = Sketchup::Color.new(30, 120, 110)
      end
      color.alpha = alpha if color.respond_to?(:alpha=)
      color
    rescue StandardError
      Sketchup::Color.new(30, 120, 110)
    end

    def entity_label(entity)
      name = entity.name.to_s.strip
      name = entity.definition.name.to_s.strip if name.empty? && entity.respond_to?(:definition)
      name.empty? ? "Entity ##{entity.entityID}" : name
    rescue StandardError
      'Entity'
    end

    def status_payload(ok, message, stats = nil)
      { ok: ok, message: message, stats: stats }
    end

    def warn_error(error)
      warn("[MH Nep] #{error.class}: #{error.message}")
      warn(error.backtrace.join("\n")) if error.backtrace
    end

    def draw_hud_overlay(view, library, index, mode, status = nil)
      buttons = {}
      width = view.vpwidth
      x = [(width - 344) / 2, 300].max
      y = 14

      buttons[:auto] = draw_hud_button(view, x, y, 128, 32, 'Dán tự động', mode == :auto, false)
      buttons[:manual] = draw_hud_button(view, x + 136, y, 92, 32, 'Dán tay', mode == :manual, false)
      buttons[:clear] = draw_hud_button(view, x + 236, y, 108, 32, 'Xóa nẹp', false, true)
      buttons[:settings] = draw_hud_button(view, width - 104, 14, 88, 32, 'Setting', false, false)

      draw_library_hud(view, buttons, library, index)
      draw_hud_text(view, 306, 56, status.to_s, Sketchup::Color.new(32, 38, 44)) unless status.to_s.empty?
      buttons
    rescue StandardError => error
      warn_error(error)
      buttons || {}
    end

    def draw_abf_bridge_hud(view, status = nil)
      buttons = {}
      width = view.vpwidth
      height = view.vpheight
      panel_width = 164
      x = [width - panel_width - 18, 12].max
      y = [height - 178, 12].max

      buttons[:mh_auto] = draw_hud_button(view, x, y, panel_width, 32, 'Dán tự động', false, false)
      buttons[:mh_manual] = draw_hud_button(view, x, y + 38, panel_width, 32, 'Dán tay ABF', true, false)
      buttons[:mh_clear] = draw_hud_button(view, x, y + 76, panel_width, 32, 'Xóa nẹp', false, true)
      buttons[:mh_settings] = draw_hud_button(view, x, y + 114, panel_width, 32, 'Setting', false, false)
      draw_hud_text(view, x, y - 22, truncate_text(status.to_s, 28), Sketchup::Color.new(32, 38, 44)) unless status.to_s.empty?
      buttons
    rescue StandardError => error
      warn_error(error)
      buttons || {}
    end

    def handle_abf_bridge_action(hit)
      case hit
      when :mh_settings
        show_settings
        'Đã mở setting MH Nep.'
      when :mh_manual
        'Đang dùng chế độ dán tay gốc của ABF.'
      when :mh_auto
        result = apply_from_options(load_defaults.merge('scope' => 'model'))
        refresh_abf_edge_band_tool
        result[:message]
      when :mh_clear
        result = clear_from_options(load_defaults.merge('scope' => 'model'))
        refresh_abf_edge_band_tool
        result[:message]
      else
        ''
      end
    rescue StandardError => error
      warn_error(error)
      error.message
    end

    def refresh_abf_edge_band_tool
      UI.start_timer(0.05, false) do
        model = Sketchup.active_model
        view = model.active_view
        tool = model.tools.active_tool
        if defined?(ABF::EditEdgeBandTool) && tool.is_a?(ABF::EditEdgeBandTool)
          tool.deactivate(view) if tool.respond_to?(:deactivate)
          tool.activate if tool.respond_to?(:activate)
          view.invalidate
        else
          activate_abf_bridge
        end
      rescue StandardError => error
        warn_error(error)
      end
    rescue StandardError => error
      warn_error(error)
    end

    def draw_library_hud(view, buttons, library, index)
      panel_x = 14
      panel_y = 14
      panel_w = 270
      row_h = 23
      rows = [library.length, 8].min
      panel_h = 34 + rows * row_h
      draw_hud_rect(view, panel_x, panel_y, panel_w, panel_h, Sketchup::Color.new(252, 252, 252, 235))
      draw_hud_outline(view, panel_x, panel_y, panel_w, panel_h, Sketchup::Color.new(38, 44, 50), 1)
      draw_hud_text(view, panel_x + 10, panel_y + 9, 'Thư viện nẹp', Sketchup::Color.new(28, 32, 36), true)
      return if library.empty?

      start_index = [[index - 3, 0].max, [library.length - rows, 0].max].min
      visible = library.each_with_index.to_a[start_index, rows] || []
      visible.each_with_index do |pair, row|
        item, item_index = pair
        y = panel_y + 32 + row * row_h
        selected = item_index == index
        draw_hud_rect(view, panel_x + 6, y - 2, panel_w - 12, row_h, Sketchup::Color.new(221, 237, 255, 245)) if selected
        draw_hud_rect(view, panel_x + 12, y + 4, 13, 13, hex_color(item[:color], 255))
        label = item[:display_name].to_s.empty? ? "#{item[:name]} #{item[:thickness]}mm" : item[:display_name]
        draw_hud_text(view, panel_x + 32, y + 3, truncate_text(label, 31), Sketchup::Color.new(32, 38, 44))
        buttons[[:band, item_index]] = [panel_x + 6, y - 2, panel_w - 12, row_h]
      end
    end

    def draw_hud_button(view, x, y, width, height, label, active, danger)
      fill = if danger
               Sketchup::Color.new(180, 54, 54, 238)
             elsif active
               Sketchup::Color.new(37, 112, 179, 242)
             else
               Sketchup::Color.new(252, 252, 252, 238)
             end
      text = (active || danger) ? Sketchup::Color.new(255, 255, 255) : Sketchup::Color.new(26, 30, 34)
      draw_hud_rect(view, x, y, width, height, fill)
      draw_hud_outline(view, x, y, width, height, Sketchup::Color.new(38, 44, 50), 1)
      draw_hud_text(view, x + 12, y + 8, label, text, true)
      [x, y, width, height]
    end

    def draw_hud_rect(view, x, y, width, height, color)
      view.drawing_color = color
      view.draw2d(GL_QUADS, [
        Geom::Point3d.new(x, y, 0),
        Geom::Point3d.new(x + width, y, 0),
        Geom::Point3d.new(x + width, y + height, 0),
        Geom::Point3d.new(x, y + height, 0)
      ])
    end

    def draw_hud_outline(view, x, y, width, height, color, line_width)
      view.drawing_color = color
      view.line_width = line_width if view.respond_to?(:line_width=)
      view.draw2d(GL_LINE_LOOP, [
        Geom::Point3d.new(x, y, 0),
        Geom::Point3d.new(x + width, y, 0),
        Geom::Point3d.new(x + width, y + height, 0),
        Geom::Point3d.new(x, y + height, 0)
      ])
    end

    def draw_hud_text(view, x, y, text, color, bold = false)
      options = { size: 12, color: color, bold: bold }
      view.draw_text(Geom::Point3d.new(x, y, 0), text.to_s, options)
    rescue ArgumentError
      view.drawing_color = color
      view.draw_text(Geom::Point3d.new(x, y, 0), text.to_s)
    end

    def truncate_text(text, length)
      text = text.to_s
      text.length > length ? "#{text[0, length - 3]}..." : text
    end

    def hud_hit(buttons, x, y)
      buttons.find do |_key, rect|
        rx, ry, rw, rh = rect
        x >= rx && x <= rx + rw && y >= ry && y <= ry + rh
      end&.first
    end

    class HudTool
      def initialize(options, library)
        @options = MH::Nep.default_options.merge(options || {})
        @library = library
        @index = selected_index
        @buttons = {}
        @status = 'HUD MH Nep: chọn lệnh trên màn hình'
      end

      def activate
        update_status
        Sketchup.active_model.active_view.invalidate
      end

      def resume(view)
        view.invalidate if view
      end

      def deactivate(view)
        Sketchup.status_text = ''
        view.invalidate if view
      end

      def onCancel(_reason, view)
        Sketchup.active_model.select_tool(nil)
        view.invalidate if view
      end

      def onKeyDown(key, _repeat, _flags, view)
        return false unless tab_key?(key)

        cycle_band
        @status = "Nẹp dán tay: #{current_label}"
        update_status
        view.invalidate
        true
      end

      def onLButtonDown(_flags, x, y, view)
        hit = MH::Nep.hud_hit(@buttons, x, y)
        return unless hit

        handle_hud_action(hit, view)
      end

      def draw(view)
        @buttons = MH::Nep.draw_hud_overlay(view, @library, @index, :hud, @status)
      end

      def getExtents
        Sketchup.active_model.bounds
      end

      private

      def selected_index
        selected_id = @options['primary_id'].to_i
        @library.index { |item| item[:id].to_i == selected_id } || 0
      end

      def current_source
        @library[@index]
      end

      def current_label
        source = current_source
        return 'Chưa có nẹp' unless source

        source[:display_name].to_s.empty? ? "#{source[:name]} - #{source[:thickness]}mm" : source[:display_name]
      end

      def cycle_band
        return if @library.empty?

        @index = (@index + 1) % @library.length
        sync_selected_band
      end

      def sync_selected_band
        return unless current_source

        @options['primary_id'] = current_source[:id]
        MH::Nep.save_defaults(@options)
      end

      def handle_hud_action(hit, view)
        if hit.is_a?(Array) && hit.first == :band
          @index = hit[1]
          sync_selected_band
          @status = "Nẹp dán tay: #{current_label}"
          update_status
          view.invalidate
          return
        end

        case hit
        when :settings
          MH::Nep.show_settings
        when :manual
          sync_selected_band
          Sketchup.active_model.select_tool(ManualTool.new(@options, @library))
          return
        when :auto
          result = MH::Nep.apply_from_options(@options.merge('scope' => 'model'))
          @status = result[:message]
        when :clear
          result = MH::Nep.clear_from_options(@options.merge('scope' => 'model'))
          @status = result[:message]
        end
        update_status
        view.invalidate
      end

      def tab_key?(key)
        key == (defined?(VK_TAB) ? VK_TAB : 9)
      end

      def update_status
        Sketchup.status_text = "#{@status} | Tab đổi nẹp, Esc thoát"
      end
    end

    class ManualTool
      def initialize(options, library, manual_enabled = true)
        @options = options
        @library = library
        @manual_enabled = manual_enabled
        selected_id = options['primary_id'].to_i
        @index = @library.index { |item| item[:id].to_i == selected_id } || 0
        @hover = nil
        @material_snapshots = {}
        @entity_material_snapshots = {}
        @tag_visibility_snapshots = {}
        @render_options_backup = nil
        @display_entities = []
        @display_faces = []
        @band_faces = []
        @display_queue = []
        @restore_entity_queue = []
        @restore_face_queue = []
        @active = false
        @hud_buttons = {}
        @status_message = nil
        @ignore_tokens = MH::Nep.ignore_tokens(@options['ignore_names'])
      end

      def activate
        @active = true
        setup_display
        update_status
      end

      def refresh_state(options, library, manual_enabled = nil)
        @options = MH::Nep.default_options.merge(options || {})
        @library = library unless library.empty?
        @manual_enabled = manual_enabled unless manual_enabled.nil?
        @ignore_tokens = MH::Nep.ignore_tokens(@options['ignore_names'])
        selected_id = @options['primary_id'].to_i
        @index = @library.index { |item| item[:id].to_i == selected_id } || @index || 0
        ensure_display_mode
        update_status(@manual_enabled ? "Đã bật dán tay: #{current_label}" : 'HUD MH Nep: chọn lệnh trên màn hình')
      end

      def deactivate(view)
        @active = false
        restore_display
        Sketchup.status_text = ''
        view.invalidate if view
      end

      def onCancel(_reason, view)
        Sketchup.active_model.select_tool(nil)
        view.invalidate if view
      end

      def onKeyDown(key, _repeat, _flags, view)
        tab_key = defined?(VK_TAB) ? VK_TAB : 9
        return false unless key == tab_key

        @index = (@index + 1) % @library.length
        sync_selected_band
        update_status
        view.invalidate
        true
      end

      def onMouseMove(_flags, x, y, view)
        false
      end

      def onLButtonDown(_flags, x, y, view)
        hud_hit = MH::Nep.hud_hit(@hud_buttons, x, y)
        if hud_hit
          handle_hud_action(hud_hit, view)
          return
        end

        return false unless @manual_enabled

        hit = pick_face(view, x, y)
        return unless hit
        if MH::Nep.ignored_entity?(hit[:entity], @ignore_tokens)
          update_status("Bỏ qua theo setting: #{MH::Nep.entity_label(hit[:entity])}")
          view.invalidate
          return
        end

        model = Sketchup.active_model
        model.start_operation('MH Nep Manual Apply', true)
        applied = MH::Nep.assign_manual_face(hit[:entity], hit[:face], current_source)
        model.commit_operation
        unless applied
          update_status("Không dán vào 2 mặt lớn nhất: #{MH::Nep.entity_label(hit[:entity])}")
          view.invalidate
          return
        end
        cache_display_entities([hit[:entity]])
        @hover = hit
        update_status("Đã dán #{MH::Nep.entity_label(hit[:entity])}: #{current_label}")
        view.invalidate
      rescue StandardError => error
        model.abort_operation rescue nil
        MH::Nep.warn_error(error)
        UI.messagebox("MH Nep: #{error.message}")
      end

      def draw(view)
        mode = @manual_enabled ? :manual : :hud
        text = @status_message || (@manual_enabled ? "Dán tay: #{current_label}" : 'HUD MH Nep: chọn lệnh trên màn hình')
        @hud_buttons = MH::Nep.draw_hud_overlay(view, @library, @index, mode, text)
      rescue StandardError => error
        MH::Nep.warn_error(error)
      end

      def getExtents
        Sketchup.active_model.bounds
      end

      private

      def setup_display
        ensure_display_mode
        @display_entities = display_targets
        @display_queue = @display_entities.dup
        @display_faces = []
        @band_faces = []
        update_status('MH Nep dán tay: đã bật chế độ nhẹ')
        schedule_display_batch
        Sketchup.active_model.active_view.invalidate
      end

      def ensure_display_mode
        save_render_options
        hide_abf_tags
        apply_abf_like_render_options
      end

      def schedule_display_batch
        UI.start_timer(0.08, false) { process_display_batch }
      rescue StandardError => error
        MH::Nep.warn_error(error)
      end

      def process_display_batch
        return unless @active

        batch = @display_queue.shift(16)
        cache_display_entities(batch) if batch && !batch.empty?

        if @display_queue.any?
          schedule_display_batch
        else
          update_status("MH Nep dán tay: đã bật hiển thị #{@display_entities.length} tấm")
        end
        Sketchup.active_model.active_view.invalidate
      rescue StandardError => error
        MH::Nep.warn_error(error)
      end

      def save_render_options
        return if @render_options_backup

        rops = Sketchup.active_model.rendering_options
        @render_options_backup = {}
        render_option_keys.each { |key| @render_options_backup[key] = rops[key] rescue nil }
      end

      def apply_abf_like_render_options
        rops = Sketchup.active_model.rendering_options
        set_render_option(rops, 'MaterialTransparency', true)
        set_render_option(rops, 'RenderMode', 2)
        set_render_option(rops, 'DrawSilhouettes', false)
        set_render_option(rops, 'DrawBackEdges', false)
      rescue StandardError => error
        MH::Nep.warn_error(error)
      end

      def restore_render_options
        return unless @render_options_backup

        rops = Sketchup.active_model.rendering_options
        @render_options_backup.each { |key, value| set_render_option(rops, key, value) }
        @render_options_backup = nil
      rescue StandardError => error
        MH::Nep.warn_error(error)
      end

      def set_render_option(rops, key, value)
        return unless rops.respond_to?(:[]=)

        current = rops[key] rescue nil
        rops[key] = value unless current == value
      end

      def render_option_keys
        %w[MaterialTransparency RenderMode DrawSilhouettes DrawBackEdges]
      end

      def hide_abf_tags
        layers = Sketchup.active_model.layers
        layers.each do |layer|
          next unless abf_tag_layer?(layer)
          @tag_visibility_snapshots[layer] = layer.visible? unless @tag_visibility_snapshots.key?(layer)
          layer.visible = false if layer.visible?
        rescue StandardError => error
          MH::Nep.warn_error(error)
        end
      end

      def abf_tag_layer?(layer)
        name = layer.name.to_s.upcase
        name.start_with?('ABF_', 'ABF-')
      end

      def restore_abf_tags
        @tag_visibility_snapshots.each do |layer, visible|
          next unless layer.valid?

          layer.visible = visible unless layer.visible? == visible
        rescue StandardError => error
          MH::Nep.warn_error(error)
        end
        @tag_visibility_snapshots.clear
      end

      def save_materials(entities = display_targets)
        entities.uniq.each do |entity|
          next unless MH::Nep.container?(entity)
          @entity_material_snapshots[entity] = entity.material unless @entity_material_snapshots.key?(entity)
        end
      end

      def restore_display
        @display_queue = []
        @display_faces = []
        @band_faces = []
        restore_abf_tags
        restore_render_options

        if @entity_material_snapshots.empty? && @material_snapshots.empty?
          Sketchup.active_model.active_view.invalidate
          return
        end

        @restore_entity_queue = @entity_material_snapshots.to_a
        @restore_face_queue = @material_snapshots.to_a
        schedule_restore_batch
      end

      def schedule_restore_batch
        UI.start_timer(0.01, false) { process_restore_batch }
      rescue StandardError => error
        MH::Nep.warn_error(error)
      end

      def process_restore_batch
        @restore_entity_queue.shift(48).each do |entity, material|
          entity.material = material if entity.valid?
        rescue StandardError => error
          MH::Nep.warn_error(error)
        end

        @restore_face_queue.shift(96).each do |face, pair|
          next unless face.valid?

          face.material = pair[0]
          face.back_material = pair[1]
        rescue StandardError => error
          MH::Nep.warn_error(error)
        end

        if @restore_entity_queue.any? || @restore_face_queue.any?
          schedule_restore_batch
        else
          @entity_material_snapshots.clear
          @material_snapshots.clear
          restore_abf_tags
          restore_render_options
          Sketchup.active_model.active_view.invalidate
        end
      end

      def rebuild_display_cache
        @display_faces = []
        @band_faces = []
        cache_display_entities(@display_entities.uniq)
      rescue StandardError => error
        MH::Nep.warn_error(error)
      end

      def cache_display_entities(entities)
        entities = entities.uniq.select { |entity| MH::Nep.container?(entity) }
        @band_faces.reject! { |info| entities.include?(info[:entity]) }
        @display_faces.reject! { |info| entities.include?(info[:entity]) }

        entities.each do |entity|
          next unless MH::Nep.container?(entity)

          transformation = Sketchup.active_model.edit_transform * entity.transformation
          data = ABF::EditEdgeBand.get_data(entity) rescue nil
          edge_faces = data && data.faces.is_a?(Hash) ? data.faces : {}
          types = data && data.types.is_a?(Hash) ? data.types : {}

          MH::Nep.direct_faces(entity).each do |face|
            next unless face.valid?

            points = face.outer_loop.vertices.map { |vertex| vertex.position.transform(transformation) }
            type_id = edge_faces[face]
            type = types[type_id] if type_id
            if type
              @band_faces << {
                entity: entity,
                face: face,
                points: points,
                color: type.color
              }
            else
              @display_faces << {
                entity: entity,
                face: face,
                points: points
              }
            end
          end
        end
      rescue StandardError => error
        MH::Nep.warn_error(error)
      end

      def apply_display_materials(entities = display_targets)
        entities = entities.uniq.select { |entity| MH::Nep.container?(entity) }
        transparent = transparent_material

        entities.each do |entity|
          data = ABF::EditEdgeBand.get_data(entity) rescue nil
          faces = MH::Nep.direct_faces(entity)
          next if faces.empty?

          edge_faces = data && data.faces.is_a?(Hash) ? data.faces : {}
          types = data && data.types.is_a?(Hash) ? data.types : {}

          faces.each do |face|
            next unless face.valid?
            @material_snapshots[face] = [face.material, face.back_material] unless @material_snapshots.key?(face)

            type_id = edge_faces[face]
            type = types[type_id] if type_id
            material = type ? edge_band_display_material(type.color) : transparent
            face.material = material unless face.material == material
            face.back_material = material unless face.back_material == material
          end
        end
      end

      def transparent_material
        model = Sketchup.active_model
        material = model.materials['Transparent1'] || model.materials.add('Transparent1')
        material.color = Sketchup::Color.new(255, 255, 255)
        material.alpha = 0.0
        material
      end

      def edge_band_display_material(color_hex)
        model = Sketchup.active_model
        name = "ABF_#{color_hex}"
        material = model.materials[name] || model.materials.add(name)
        material.color = MH::Nep.hex_color(color_hex, 255)
        material.alpha = 1.0
        material
      end

      def current_source
        @library[@index]
      end

      def current_label
        current_source[:display_name].to_s.empty? ? "#{current_source[:name]} - #{current_source[:thickness]}mm" : current_source[:display_name]
      end

      def sync_selected_band
        @options['primary_id'] = current_source[:id] if current_source
        MH::Nep.save_defaults(@options)
      end

      def handle_hud_action(hit, view)
        if hit.is_a?(Array) && hit.first == :band
          @index = hit[1]
          sync_selected_band
          update_status("Nẹp dán tay: #{current_label}")
          view.invalidate
          return
        end

        case hit
        when :settings
          MH::Nep.show_settings
        when :manual
          @manual_enabled = !@manual_enabled
          update_status(@manual_enabled ? "Đã bật dán tay: #{current_label}" : 'Đã tắt dán tay, vẫn giữ HUD')
        when :auto
          result = MH::Nep.apply_from_options(@options.merge('scope' => 'model'))
          update_status(result[:message])
          refresh_display_materials(display_targets)
        when :clear
          result = MH::Nep.clear_from_options(@options.merge('scope' => 'model'))
          update_status(result[:message])
          clear_display_materials
        end
        view.invalidate
      end

      def refresh_display_materials(entities)
        clear_display_materials
        @display_entities = entities.uniq.select { |entity| MH::Nep.container?(entity) }
        @display_queue = @display_entities.dup
        schedule_display_batch
      end

      def clear_display_materials
        @display_queue = []
        @display_faces = []
        @band_faces = []
        @material_snapshots.each do |face, pair|
          next unless face.valid?

          face.material = pair[0] unless face.material == pair[0]
          face.back_material = pair[1] unless face.back_material == pair[1]
        rescue StandardError => error
          MH::Nep.warn_error(error)
        end
        @material_snapshots.clear
      end

      def update_status(prefix = nil)
        @status_message = prefix || "MH Nep dán tay: #{current_label}"
        text = @status_message
        Sketchup.status_text = "#{text} | Tab đổi nẹp, click mặt cạnh để dán, Esc thoát"
      end

      def pick_face(view, x, y)
        helper = view.pick_helper
        helper.do_pick(x, y)
        paths = []
        if helper.respond_to?(:count) && helper.respond_to?(:path_at)
          helper.count.times do |index|
            path = helper.path_at(index) rescue nil
            paths << path if path
          end
        end
        best = helper.best_picked rescue nil
        paths << [best] if best

        paths.each do |path|
          entity = nil
          face = nil
          path.each do |item|
            entity = item if MH::Nep.container?(item)
            face = item if item.is_a?(Sketchup::Face)
          end
          next unless entity && face
          next unless MH::Nep.direct_faces(entity).include?(face)

          return { entity: entity, face: face }
        end
        nil
      end

      def draw_existing_bands(view)
        wash = Sketchup::Color.new(255, 255, 255)
        wash.alpha = 210 if wash.respond_to?(:alpha=)
        @display_faces.each do |info|
          next unless info[:face].valid?

          draw_points_fill(view, info[:points], wash)
        end

        @band_faces.each do |info|
          next unless info[:face].valid?

          draw_points_fill(view, info[:points], MH::Nep.hex_color(info[:color], 255))
          draw_points_outline(view, info[:points], Sketchup::Color.new(20, 20, 20), 2)
        end
      end

      def draw_hover(view)
        return unless @hover && @hover[:entity].valid? && @hover[:face].valid?

        transformation = Sketchup.active_model.edit_transform * @hover[:entity].transformation
        draw_face_outline(view, @hover[:face], transformation, MH::Nep.hex_color(current_source[:color], 255), 6)
      end

      def draw_face_outline(view, face, transformation, color, width)
        points = face.outer_loop.vertices.map { |vertex| vertex.position.transform(transformation) }
        return if points.length < 3

        draw_points_outline(view, points, color, width)
      end

      def draw_points_outline(view, points, color, width)
        return if points.length < 3

        view.drawing_color = color
        view.line_width = width if view.respond_to?(:line_width=)
        view.draw(GL_LINE_LOOP, points)
      end

      def draw_face_fill(view, face, transformation, color)
        points = face.outer_loop.vertices.map { |vertex| vertex.position.transform(transformation) }
        return if points.length < 3

        draw_points_fill(view, points, color)
      end

      def draw_points_fill(view, points, color)
        return if points.length < 3

        view.drawing_color = color
        view.draw(GL_POLYGON, points)
      end

      def display_targets
        model = Sketchup.active_model
        model.active_entities.grep(Sketchup::Group) +
          model.active_entities.grep(Sketchup::ComponentInstance)
      end
    end

    unless file_loaded?(__FILE__)
      command = UI::Command.new(PLUGIN_NAME) { show }
      command.tooltip = 'Dán nẹp ABF theo hướng nhìn'
      command.status_bar_text = 'Chọn nẹp ABF và dán vào các mặt cạnh của tấm'

      UI.menu('Extensions').add_item(command)
      UI.add_context_menu_handler do |menu|
        menu.add_item(command) unless Sketchup.active_model.selection.empty?
      end

      file_loaded(__FILE__)
    end
  end
end

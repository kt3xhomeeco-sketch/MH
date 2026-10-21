# encoding: UTF-8
#
# Product context nhe dung chung cho MH_*.
# Chi doc name/definition/selection khi duoc hoi, khong scan viewport lien tuc.

require 'json'
require_relative 'product_x_cluster'

module MH
  module ProductContext
    remove_const(:CODE_CAPTURE) if const_defined?(:CODE_CAPTURE)
    remove_const(:CODE_SCAN) if const_defined?(:CODE_SCAN)
    remove_const(:CODE_STRICT) if const_defined?(:CODE_STRICT)
    CODE_CAPTURE = MH::NameGrammar.capture_regex
    CODE_SCAN = MH::NameGrammar.capture_regex
    CODE_STRICT = MH::NameGrammar.strict_regex

    @codes_cache_key = nil
    @codes_cache = nil
    @last_selected_code_by_model = {}
    @observed_selection_by_model = {}
    @spatial_marker_cache = {}
    @world_x_cache = {}

    module_function

    def refresh_grammar
      remove_const(:CODE_CAPTURE) if const_defined?(:CODE_CAPTURE)
      remove_const(:CODE_SCAN) if const_defined?(:CODE_SCAN)
      remove_const(:CODE_STRICT) if const_defined?(:CODE_STRICT)
      const_set(:CODE_CAPTURE, MH::NameGrammar.capture_regex)
      const_set(:CODE_SCAN, MH::NameGrammar.capture_regex)
      const_set(:CODE_STRICT, MH::NameGrammar.strict_regex)
      @codes_cache_key = nil
      @codes_cache = nil
      true
    rescue => e
      MH::Shared.dbg("[MH::ProductContext] refresh_grammar error: #{e.class}: #{e.message}") if defined?(MH::Shared)
      false
    end

    def base(code)
      source = exact(code)
      parsed = defined?(MH::NameGrammar) ? MH::NameGrammar.parse(source) : nil
      return parsed[:product].to_s.upcase if parsed && parsed[:recognized] && !parsed[:product].to_s.empty?

      seps = ['.']
      if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:module_separator)
        sep = MH::NameGrammar.module_separator.to_s
        seps << sep unless sep.empty? || seps.include?(sep)
      end
      first_sep = seps.map { |sep| [sep, source.index(sep)] }.select { |_, idx| idx }.min_by { |_, idx| idx }
      first_sep ? source[0...first_sep[1]].to_s.upcase : source
    rescue
      code.to_s.strip.upcase.split('.').first.to_s
    end

    def active_family
      if defined?(MH::NameGrammar)
        if MH::NameGrammar.respond_to?(:product_families)
          family = Array(MH::NameGrammar.product_families(active: true)).map(&:to_s).map(&:strip).find { |v| v =~ /\A[A-Za-z]+\z/ }
          return family.upcase if family && !family.empty?
        end
        family = Array(MH::NameGrammar.prefixes(active: true)).map(&:to_s).map(&:strip).find { |v| v =~ /\A[A-Za-z]+\z/ }
        return family.upcase if family && !family.empty?
        default = MH::NameGrammar.default_prefix.to_s.strip
        return default.upcase unless default.empty?
      end
      'SP'
    rescue
      'SP'
    end

    def format_code(number, family: nil, width: 2)
      fam = family.to_s.strip
      fam = active_family if fam.empty?
      raw = number.to_s.strip
      return fam.upcase if raw.empty?

      if raw =~ /\A(\d+)([A-Za-z]?)\z/
        digits = format("%0#{width.to_i <= 0 ? 1 : width.to_i}d", $1.to_i)
        "#{fam}#{digits}#{$2}".upcase
      else
        "#{fam}#{raw}".upcase
      end
    end

    def exact(code)
      code.to_s.strip.upcase
    end

    def number(code)
      parsed = defined?(MH::NameGrammar) ? MH::NameGrammar.parse(base(code)) : nil
      return parsed[:product_no].to_i if parsed && parsed[:recognized] && parsed[:product_no]

      match = base(code).match(/\A[A-Za-z]+(\d+)/)
      match ? match[1].to_i : nil
    rescue
      nil
    end

    def with_number(code, number_value)
      source = exact(code)
      parsed = defined?(MH::NameGrammar) ? MH::NameGrammar.parse(source) : nil
      family = if parsed && parsed[:recognized] && parsed[:prefix].to_s =~ /\A[A-Za-z]+\z/
        parsed[:prefix].to_s
      else
        source[/\A([A-Za-z]+)/, 1].to_s
      end
      family = active_family if family.empty?
      suffix = source.sub(/\A#{Regexp.escape(base(source))}/i, '')
      "#{format_code(number_value, family: family)}#{suffix}".upcase
    rescue
      format_code(number_value)
    end

    def module?(code)
      source = exact(code)
      parsed = defined?(MH::NameGrammar) ? MH::NameGrammar.parse(source) : nil
      return !!parsed[:has_modul] if parsed && parsed[:recognized]

      sep = defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:module_separator) ? MH::NameGrammar.module_separator.to_s : '.'
      source.include?('.') || (!sep.empty? && source.include?(sep))
    rescue
      exact(code).include?('.')
    end

    def valid?(code)
      value = exact(code)
      !value.empty? && value != '--' && MH::NameGrammar.valid_product?(value)
    end

    def sort_key(code)
      code.to_s.split(/(\d+)/).map { |part| part =~ /\d/ ? [1, part.to_i] : [0, part.downcase] }
    end

    def match?(value, target, mode = 'product')
      v = exact(value)
      t = exact(target)
      return false if v.empty? || t.empty? || v == '--'
      return base(v) == base(t) if mode.to_s == 'product' || !module?(t)

      v == t || (!module?(v) && base(v) == base(t))
    end

    def text_for_entity(entity)
      text = entity.respond_to?(:name) ? entity.name.to_s : ''
      text += " #{entity.definition.name}" if entity.respond_to?(:definition) && entity.definition
      text
    rescue
      ''
    end

    def code_from_entity(entity, resolve_selection: true)
      if resolve_selection && defined?(Sketchup) && Sketchup.respond_to?(:active_model)
        model = Sketchup.active_model
        selected = model.selection.to_a if model && model.respond_to?(:selection)
        selected_match = Array(selected).any? do |candidate|
          candidate.equal?(entity) || (candidate.respond_to?(:entityID) && entity.respond_to?(:entityID) && candidate.entityID == entity.entityID)
        end
        if selected_match
          resolved = codes_from_selection(model, allow_slow_scan: false).first
          return exact(resolved) unless resolved.to_s.empty?
        end
      end
      codes_for_entity(entity).first
    rescue
      nil
    end

    def codes_for_entity(entity)
      # Dynamic component imports often keep SP ownership in attributes while
      # the visible instance/definition name is only a detail label (for
      # example "Tấm Đứng Trước#155"). Prefer that authoritative metadata,
      # then fall back to the conventional name grammar.
      metadata_codes = attribute_product_values(entity).flat_map do |value|
        MH::NameGrammar.scan_products(value.to_s)
      end
      name_codes = MH::NameGrammar.scan_products(text_for_entity(entity))
      (metadata_codes + name_codes).map { |code| exact(code) }.reject(&:empty?).uniq
    rescue
      []
    end

    def attribute_product_values(entity)
      return [] unless entity && entity.respond_to?(:get_attribute)

      keys = %w[dc_product_code product_code position_product_code actual_product Ma_SP ma_sp product]
      dictionaries = %w[MH_Registry MH_ProductContext dynamic_attributes]
      # Most imported/nesting details have none of these dictionaries. Three
      # non-creating dictionary lookups avoid 21 individual SketchUp API calls.
      values = dictionaries.flat_map do |dictionary|
        if entity.respond_to?(:attribute_dictionary)
          data = entity.attribute_dictionary(dictionary, false)
          data ? keys.map { |key| data[key] } : []
        else
          keys.map { |key| entity.get_attribute(dictionary, key, nil) }
        end
      end
      values.map { |value| value.to_s.strip }.reject(&:empty?).uniq
    rescue
      []
    end

    # A position stamp is intentionally separate from dc_product_code. The
    # latter is copied with a Dynamic Component and describes the source DC;
    # this stamp records the product marker that the user last confirmed for
    # this particular occurrence. It therefore stays stable while the camera
    # changes and can be refreshed explicitly after a copy/move.
    def position_product_code(entity)
      return '' unless entity && entity.respond_to?(:get_attribute)

      code = exact(entity.get_attribute('MH_ProductContext', 'position_product_code', ''))
      valid?(code) ? code : ''
    rescue
      ''
    end

    def stamp_position_product(entity, code)
      return '' unless entity && entity.respond_to?(:set_attribute)

      value = exact(code)
      return '' unless valid?(value)

      entity.set_attribute('MH_ProductContext', 'position_product_code', value)
      @codes_cache_key = nil
      @codes_cache = nil
      value
    rescue
      ''
    end

    def clear_spatial_marker_cache
      @spatial_marker_cache.clear
      @world_x_cache.clear
      @codes_cache_key = nil
      true
    rescue
      false
    end

    # Shared product-owner inference. All MH apps that ask ProductContext for
    # the current selection use the same name/attribute, ancestor, and named
    # spatial-marker rules instead of keeping app-specific copies.
    def codes_for_instance_path(path, model: nil, view: nil, parent_transform: nil)
      owner, = resolve_instance_path(path, model: model, view: view, parent_transform: parent_transform)
      spatial_product_codes(owner)
    rescue
      []
    end

    def resolve_instance_path(path, model: nil, view: nil, parent_transform: nil)
      model ||= Sketchup.active_model if defined?(Sketchup)
      view ||= model.active_view if model && model.respond_to?(:active_view)
      transform = parent_transform || Geom::Transformation.new
      owner = ''
      last_spatial = ''

      Array(path).each do |entity|
        next unless product_instance?(entity)
        next if entity.respond_to?(:valid?) && !entity.valid?

        world = transform * entity.transformation
        spatial = if spatial_annotation_entity?(entity)
          ''
        else
          infer_spatial_product(world_points_for_entity(entity, world), model: model, view: view, entity: entity)
        end
        owner = spatial.to_s
        last_spatial = spatial unless spatial.to_s.empty?
        transform = world
      end

      [owner, transform, last_spatial]
    rescue
      ['', transform, last_spatial]
    end

    def resolve_instance_product(entity, inherited_product: '', world_transform: nil, parent_transform: nil, model: nil, view: nil, markers: nil, spatial_product: nil)
      model ||= Sketchup.active_model if defined?(Sketchup)
      view ||= model.active_view if model && model.respond_to?(:active_view)
      parent_transform ||= Geom::Transformation.new
      world = world_transform || parent_transform * entity.transformation
      # Batch readers may supply a spatial result proved against the same
      # marker set, avoiding another nearest-marker search for every detail.
      spatial = if spatial_annotation_entity?(entity)
        ''
      elsif !spatial_product.nil?
        exact(spatial_product)
      else
        infer_spatial_product(world_points_for_entity(entity, world), model: model, view: view, markers: markers, entity: entity)
      end
      [exact(spatial), world, spatial]
    rescue
      ['', world_transform, '']
    end

    def resolve_selection_paths(model = nil)
      model ||= Sketchup.active_model if defined?(Sketchup)
      return [] unless model && model.respond_to?(:selection)

      contexts = if defined?(MH::MaterialHUD) && MH::MaterialHUD.respond_to?(:selection_target_contexts)
        MH::MaterialHUD.selection_target_contexts(model)
      else
        []
      end
      paths = Array(contexts).filter_map do |context|
        path = Array(context[:instance_path])
        path unless path.empty?
      end
      return paths unless paths.empty?

      Array(model.selection).filter_map do |entity|
        next unless product_instance?(entity)
        Array(model.active_path) + [entity]
      end
    rescue
      []
    end

    def resolve_selection_products(model = nil, view: nil)
      model ||= Sketchup.active_model if defined?(Sketchup)
      return [] unless model

      resolve_selection_paths(model).flat_map do |path|
        codes_for_instance_path(path, model: model, view: view)
      end.map { |code| exact(code) }.reject(&:empty?).uniq.sort_by { |code| sort_key(code) }
    rescue
      []
    end

    def product_instance?(entity)
      return false unless defined?(Sketchup)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    rescue
      false
    end

    def instance_name_product_code(entity)
      name = entity.respond_to?(:name) ? entity.name.to_s : ''
      values = MH::NameGrammar.scan_products(name)
      Array(values).map { |value| exact(value) }.find { |value| valid?(value) }.to_s
    rescue
      ''
    end

    def code_from_entity_sources(entity)
      codes_for_entity(entity).map { |value| exact(value) }.find { |value| valid?(value) }.to_s
    rescue
      ''
    end

    def definition_name(entity)
      entity.respond_to?(:definition) && entity.definition ? entity.definition.name.to_s : ''
    rescue
      ''
    end

    def spatial_marker_entity?(entity)
      definition_name(entity) =~ /\AText(?:#|\z)/i
    rescue
      false
    end

    def spatial_annotation_entity?(entity)
      spatial_marker_entity?(entity) ||
        [entity.respond_to?(:name) ? entity.name.to_s : '', definition_name(entity)].any? { |name| name =~ /\A_*ABF[_ -]Label(?:#|\z)/i }
    end

    def instance_name_product_codes(entity)
      return [] unless entity.respond_to?(:name)
      MH::NameGrammar.scan_products(entity.name.to_s).map { |code| base(code) }.reject(&:empty?).uniq
    end

    def physical_product_bounds?(bounds, world)
      return false unless bounds && !bounds.empty?
      values = world.to_a
      axes = [0, 4, 8].map { |offset| values[offset, 3] }
      lengths = axes.map { |axis| Math.sqrt(axis.sum { |v| v * v }) }
      dimensions = [bounds.width.to_f, bounds.height.to_f, bounds.depth.to_f]
      return false unless dimensions.each_with_index.all? { |size, i| size * lengths[i] > ProductXCluster::EPS }
      a, b, c = axes
      determinant = a[0] * (b[1] * c[2] - b[2] * c[1]) - a[1] * (b[0] * c[2] - b[2] * c[0]) + a[2] * (b[0] * c[1] - b[1] * c[0])
      determinant.abs > lengths.inject(1.0, :*) * 1e-10
    end

    def world_points_for_entity(entity, transform)
      bounds = if entity.respond_to?(:definition) && entity.definition
        entity.definition.bounds
      elsif entity.respond_to?(:bounds)
        entity.bounds
      end
      return [] unless bounds && !(bounds.respond_to?(:empty?) && bounds.empty?)

      (0..7).map { |index| bounds.corner(index).transform(transform) }
    rescue
      []
    end

    # Nhận SP theo X đỏ của model; không dùng camera hoặc mã Registry.
    def infer_spatial_product(points, model: nil, view: nil, markers: nil, entity: nil)
      model ||= Sketchup.active_model if defined?(Sketchup)
      return '' unless model && !Array(points).empty?
      context = world_x_context(model)
      lo, hi = points.map { |point| point.x.to_f }.minmax
      key = x_interval_key(lo, hi)
      # A flat annotation can share the exact X range of its 3D parent.
      # Resolve the occurrence itself instead of merging those two records.
      if entity && product_instance?(entity)
        return context.fetch(:entity_ranges, {})[[entity, *key]].to_s
      end
      entry = context[:ranges][key]
      return entry.to_s unless entry.nil?
      # Face/pick không trùng bounding box container: chỉ nhận khi các
      # interval gần nhất đều thuộc một SP đã chứng minh từ nhãn.
      best = Float::INFINITY
      codes = []
      context[:units].each do |unit|
        distance = [unit[:lo] - hi, lo - unit[:hi], 0].max
        code = context[:result][:owners][unit[:id]].to_s
        if distance < best - ProductXCluster::EPS
          best, codes = distance, [code]
        elsif ProductXCluster.close(distance, best)
          codes << code
        end
      end
      codes.uniq.length == 1 ? codes.first.to_s : ''
    rescue => e
      MH::Shared.dbg("[ProductContext] world X: #{e.message}") if defined?(MH::Shared)
      ''
    end

    def x_interval_key(lo, hi)
      [lo.round(6), hi.round(6)]
    end

    def spatial_markers(model = nil, view = nil)
      model ||= Sketchup.active_model if defined?(Sketchup)
      return [] unless model && model.respond_to?(:entities)
      key = [model_key(model), spatial_model_revision(model), ProductXCluster::VERSION, spatial_settings[:label_group_gap_mm]]
      return @spatial_marker_cache[key] if @spatial_marker_cache.key?(key)
      markers = model.entities.to_a.filter_map do |entity|
        next unless product_instance?(entity) && spatial_entity_visible?(entity) && spatial_marker_entity?(entity)
        # Chỉ đọc tên nhãn. Attribute Registry của nhãn cũng không chọn SP.
        code = MH::NameGrammar.scan_products(text_for_entity(entity)).first.to_s
        next if code.empty?
        bounds = entity.bounds
        next if !bounds || bounds.empty?
        { code: base(code), x: bounds.center.x.to_f, lo: bounds.min.x.to_f, hi: bounds.max.x.to_f,
          y: bounds.center.y.to_f, z: bounds.center.z.to_f, entity: entity }
      end
      @spatial_marker_cache.clear if @spatial_marker_cache.size > 8
      @spatial_marker_cache[key] = ProductXCluster.group_markers(markers, spatial_settings[:label_group_gap_mm])
    rescue
      []
    end

    def spatial_settings
      path = File.join(__dir__, 'data', 'product_spatial.json')
      stamp = File.exist?(path) ? File.mtime(path).to_f : 0
      return @spatial_settings if @spatial_settings_stamp == stamp && @spatial_settings
      data = File.exist?(path) ? JSON.parse(File.read(path, encoding: 'UTF-8')) : {}
      gap = data['labelGroupGapMm']
      @spatial_settings_stamp = stamp
      @spatial_settings = { label_group_gap_mm: gap.is_a?(Numeric) && gap.finite? && gap >= 0 ? gap : 10 }
    rescue
      { label_group_gap_mm: 10 }
    end

    def spatial_product_codes(value)
      value.to_s.split('|').map { |code| exact(code) }.reject(&:empty?).uniq
    end

    def spatial_entity_visible?(entity)
      return false if entity.respond_to?(:valid?) && !entity.valid?
      return false if entity.respond_to?(:hidden?) && entity.hidden?
      layer = entity.layer if entity.respond_to?(:layer)
      !layer || !layer.respond_to?(:visible?) || layer.visible?
    end

    def world_x_context(model = nil)
      model ||= Sketchup.active_model
      key = [model_key(model), spatial_model_revision(model), ProductXCluster::VERSION, spatial_settings[:label_group_gap_mm]]
      return @world_x_cache[key] if @world_x_cache.key?(key)
      markers = spatial_markers(model)
      records, contents = [], {}
      walker = lambda do |entities, parent, ancestors, inherited_names|
        raise 'Cây group/component quá sâu hoặc có vòng lặp.' if ancestors.length > 256
        children = []
        entities.each do |entity|
          next unless product_instance?(entity) && spatial_entity_visible?(entity)
          next if spatial_annotation_entity?(entity)
          definition = entity.definition
          raise 'Cây group/component có vòng lặp.' if ancestors.include?(definition)
          raise 'Model vượt giới hạn 500.000 vị trí.' if records.length >= 500000
          data = contents[definition] ||= begin
            list = definition.entities.to_a
            { children: list.select { |e| product_instance?(e) }, geometry: list.any? { |e| e.is_a?(Sketchup::Face) } }
          end
          world = parent * entity.transformation
          own_names = instance_name_product_codes(entity)
          name_codes = own_names.empty? ? inherited_names : own_names
          xs = world_points_for_entity(entity, world).map { |point| point.x.to_f }
          lo, hi = xs.minmax
          item = { id: records.length, entity: entity, lo: lo || Float::INFINITY, hi: hi || -Float::INFINITY,
            geometry: data[:geometry] && physical_product_bounds?(definition.bounds, world), children: [], code: '', ambiguous: false,
            name_codes: name_codes, source: own_names.empty? ? 'parent-name' : 'object-name' }
          records << item
          children << item
          item[:children] = walker.call(data[:children], world, ancestors + [definition], name_codes)
          item[:descendant_geometry] = item[:children].any? { |c| c[:geometry] || c[:descendant_geometry] }
        end
        children
      end
      walker.call(model.entities, Geom::Transformation.new, [], [])
      units = records.select { |item| item[:geometry] && !item[:descendant_geometry] }
      result = ProductXCluster.resolve(units, markers)
      records.reverse_each do |item|
        if !item[:name_codes].empty? && (item[:geometry] || item[:descendant_geometry])
          item[:ambiguous] = item[:name_codes].length > 1
          item[:code] = item[:ambiguous] ? '' : item[:name_codes].first
          if item[:geometry] && !item[:descendant_geometry]
            result[:owners].delete(item[:id])
            result[:ambiguous].delete(item[:id])
            result[:owners][item[:id]] = item[:code] unless item[:code].empty?
            result[:ambiguous] << item[:id] if item[:ambiguous]
          end
        elsif !item[:descendant_geometry]
          item[:code] = result[:owners][item[:id]].to_s
          item[:ambiguous] = result[:ambiguous].include?(item[:id])
          item[:source] = 'label'
        else
          physical = item[:children].select { |c| c[:geometry] || c[:descendant_geometry] }
          codes = physical.map { |c| c[:code] }.uniq
          item[:ambiguous] = physical.any? { |c| c[:ambiguous] } || codes.reject(&:empty?).length > 1
          item[:code] = codes.length == 1 ? codes.first : ''
          item[:source] = physical.find { |c| !c[:code].empty? }&.dig(:source) || 'label'
        end
      end
      present_codes = result[:owners].values.uniq
      result[:empty_markers] = markers.map { |marker| marker[:code] }.uniq - present_codes
      ranges, entity_ranges = {}, {}
      records.each do |item|
        next unless item[:lo].finite? && item[:hi].finite?
        range = x_interval_key(item[:lo], item[:hi])
        entity_ranges[[item[:entity], *range]] = item[:code]
        next unless item[:geometry] || item[:descendant_geometry]
        ranges[range] = ranges.key?(range) && ranges[range] != item[:code] ? '' : item[:code]
      end
      @world_x_cache.clear if @world_x_cache.size > 4
      @world_x_cache[key] = { markers: markers, records: records, units: units, result: result, ranges: ranges, entity_ranges: entity_ranges }
    end

    def average_point(points)
      size = points.length.to_f
      Geom::Point3d.new(points.sum(&:x) / size, points.sum(&:y) / size, points.sum(&:z) / size)
    end

    def spatial_model_revision(model)
      if defined?(MH::ModelHub) && MH::ModelHub.respond_to?(:model_signature)
        MH::ModelHub.model_signature(model)
      else
        [model.entities.respond_to?(:length) ? model.entities.length : 0, model.respond_to?(:path) ? model.path.to_s : ''].hash
      end
    rescue
      0
    end

    def spatial_view_signature(view)
      camera = view.camera if view.respond_to?(:camera)
      values = []
      [:eye, :target, :direction, :up].each do |method|
        point = camera.public_send(method) if camera && camera.respond_to?(method)
        values.concat([point.x, point.y, point.z]) if point && point.respond_to?(:x)
      end
      [:fov, :height, :perspective].each do |method|
        values << camera.public_send(method) if camera && camera.respond_to?(method)
      end
      values.concat([view.vpwidth, view.vpheight]) if view.respond_to?(:vpwidth) && view.respond_to?(:vpheight)
      values.hash
    rescue
      0
    end

    # Parse 1 tên thành cấu trúc đầy đủ. Giữ nil cho caller cũ khi tên không nhận diện.
    # => { id:, prefix:, sp_no:, product:, modul:, modul_label:, module_code:, part:, raw: }
    def parse_full(name)
      parsed = MH::NameGrammar.parse(name)
      return nil unless parsed[:recognized]

      {
        id:           parsed[:sys_id],
        sys_id:       parsed[:sys_id],
        numbered:     parsed[:numbered],
        sub_prefix:   parsed[:sub_prefix],
        prefix:       parsed[:prefix],
        sp_no:        parsed[:sp_no],
        product_no:   parsed[:product_no],
        product:      parsed[:product],
        has_modul:    parsed[:has_modul],
        modul:        parsed[:modul],
        module_no:    parsed[:module_no],
        module_raw:   parsed[:module_raw],
        module_kind:  parsed[:module_kind],
        modul_label:  parsed[:modul_label],
        module_code:  parsed[:module_code],
        full_module_code: parsed[:full_module_code],
        part:         parsed[:part],
        suffix:       parsed[:suffix],
        recognized:   true,
        raw:          name.to_s
      }
    rescue
      nil
    end

    def selection_signature(model = Sketchup.active_model)
      model.selection.to_a.map { |entity| entity.entityID rescue nil }.compact.sort.join(',')
    rescue
      ''
    end

    def active_path_signature(model = Sketchup.active_model)
      Array(model.active_path).map { |entity| entity.entityID rescue nil }.compact.join('/')
    rescue
      ''
    end

    def codes_from_selection(model = Sketchup.active_model, allow_slow_scan: true)
      return [] unless model

      view_signature = spatial_model_revision(model)
      cache_key = [
        model.respond_to?(:guid) ? model.guid.to_s : model.object_id.to_s,
        allow_slow_scan ? '1' : '0',
        selection_signature(model),
        active_path_signature(model),
        view_signature,
        spatial_settings[:label_group_gap_mm]
      ].join('::')
      return @codes_cache.dup if @codes_cache_key.to_s == cache_key && @codes_cache.is_a?(Array)

      selection = model.selection.to_a
      return cache_result(cache_key, []) if selection.empty?

      # The product labels themselves are the one unambiguous manual choice.
      # When a drawing has spatial markers, the normal spatial branch ignores
      # annotation entities on purpose; that used to make selecting a label
      # such as "SP76" return no code. Superimp then clears the selection when
      # it starts and the HUD falls back to the previous product. Resolve a
      # selected marker before the spatial lookup so its code is remembered.
      selected_marker_codes = selection.flat_map do |entity|
        next [] unless spatial_marker_entity?(entity)
        MH::NameGrammar.scan_products(text_for_entity(entity)).map { |code| exact(code) }
      end.select { |code| valid?(code) }.uniq.sort_by { |code| sort_key(code) }
      return cache_result(cache_key, selected_marker_codes) unless selected_marker_codes.empty?

      spatial_products = resolve_selection_products(model)
      return cache_result(cache_key, spatial_products) unless spatial_products.empty?
      return cache_result(cache_key, []) unless spatial_markers(model).empty?

      products = []
      add_product = lambda do |value|
        code = exact(value)
        products << code if valid?(code) && !products.include?(code)
      end

      Array(model.active_path).reverse_each do |entity|
        codes_for_entity(entity).each { |code| add_product.call(code) }
      end

      selection.each do |entity|
        codes_for_entity(entity).each { |code| add_product.call(code) }
      end

      unless products.empty?
        return cache_result(cache_key, products.sort_by { |code| sort_key(code) })
      end

      if allow_slow_scan
        selected_ids = selection.map { |entity| entity.entityID rescue nil }.compact
        scan_entities_for_selected_products(model.entities, selected_ids, '', 0, add_product)
      end

      cache_result(cache_key, products.sort_by { |code| sort_key(code) })
    rescue
      []
    end

    def selected_code(model = Sketchup.active_model, allow_slow_scan: true)
      codes_from_selection(model, allow_slow_scan: allow_slow_scan).first.to_s
    rescue
      ''
    end

    def current_or_last_code(model = Sketchup.active_model, allow_slow_scan: true)
      install_observer(model)
      code = selected_code(model, allow_slow_scan: allow_slow_scan)
      return remember_code(code, model) unless code.to_s.empty?

      last_code(model)
    rescue
      ''
    end

    def refresh_from_selection(model = Sketchup.active_model, allow_slow_scan: false)
      code = selected_code(model, allow_slow_scan: allow_slow_scan)
      code.to_s.empty? ? last_code(model) : remember_code(code, model)
    rescue
      ''
    end

    def remember_code(code, model = Sketchup.active_model)
      value = exact(code)
      return '' unless valid?(value)

      key = model_key(model)
      @last_selected_code_by_model[key] = value
      model.set_attribute('MH_ProductContext', 'last_selected_product_code', value) if model && model.respond_to?(:set_attribute)
      value
    rescue
      value.to_s
    end

    def last_code(model = Sketchup.active_model)
      key = model_key(model)
      cached = @last_selected_code_by_model[key].to_s
      return cached if valid?(cached)

      stored = model.get_attribute('MH_ProductContext', 'last_selected_product_code').to_s if model && model.respond_to?(:get_attribute)
      valid?(stored) ? stored : ''
    rescue
      ''
    end

    def model_key(model = Sketchup.active_model)
      return 'nil' unless model
      model.respond_to?(:guid) ? model.guid.to_s : model.object_id.to_s
    rescue
      model.object_id.to_s
    end

    def install_observer(model = Sketchup.active_model)
      return false unless model && model.respond_to?(:selection)

      key = model_key(model)
      return true if @observed_selection_by_model[key]

      observer = MH::ModelHub.subscribe(
        :product_context,
        on_selection: ->(_kind) { MH::ProductContext.refresh_from_selection(Sketchup.active_model, allow_slow_scan: false) },
        visible: -> { true }
      )
      @observed_selection_by_model[key] = observer
      refresh_from_selection(model, allow_slow_scan: false)
      true
    rescue => e
      MH::Shared.dbg("[MH::ProductContext] selection observer error: #{e.class}: #{e.message}") if defined?(MH::Shared)
      false
    end

    def cache_result(cache_key, result)
      @codes_cache_key = cache_key
      @codes_cache = Array(result).dup
      @codes_cache.dup
    end

    def scan_entities_for_selected_products(entities, selected_ids, current_product, depth, add_product)
      return if depth > 2 || !entities

      entities.each do |entity|
        next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

        own_code = code_from_entity(entity, resolve_selection: false)
        product = own_code.to_s.empty? ? current_product : own_code
        add_product.call(product) if selected_ids.include?(entity.entityID) && !product.to_s.empty?

        child_entities = if entity.is_a?(Sketchup::Group)
                           entity.entities
                         elsif entity.respond_to?(:definition) && entity.definition
                           entity.definition.entities
                         end
        scan_entities_for_selected_products(child_entities, selected_ids, product, depth + 1, add_product) if child_entities
      end
      nil
    rescue
      nil
    end
  end
end

MH::ProductContext.install_observer if defined?(Sketchup)

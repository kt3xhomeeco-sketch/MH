# encoding: UTF-8
#
# MH::ModelReader -- đọc dữ liệu thô từ SketchUp model cho các app MH_*.
# Module này không phân loại nghiệp vụ PK/VL/Vật liệu/Spec; chỉ trả thông tin model.

module MH
  module ModelReader
    module_function

    @sp_index_cache = nil
    @sp_index_signature = nil

    def scan(model: nil, scope: :selection, roots: nil, max_depth: -1, include_hidden: false, types: %i[group component])
      model ||= Sketchup.active_model
      root_entities = roots_for_scope(model, scope, roots)
      records = []
      return records if root_entities.empty?

      if defined?(MH::TraverseModel)
        MH::TraverseModel.each(
          root: root_entities,
          max_depth: max_depth,
          include_hidden: include_hidden,
          types: types
        ) do |entity, ctx|
          records << record_for(entity, ctx)
        end
      else
        root_entities.each { |entity| records << record_for(entity, nil) }
      end
      records
    rescue
      []
    end

    def sp_index(model: nil, force: false, max_depth: -1, include_hidden: false)
      model ||= Sketchup.active_model
      signature = model_index_signature(model)
      if !force && @sp_index_cache.is_a?(Hash) && @sp_index_signature == signature
        return @sp_index_cache
      end

      @sp_index_cache = build_sp_index(model: model, max_depth: max_depth, include_hidden: include_hidden)
      @sp_index_signature = signature
      @sp_index_cache
    rescue
      @sp_index_cache ||= empty_sp_index
    end

    def invalidate_sp_index!
      @sp_index_cache = nil
      @sp_index_signature = nil
      true
    rescue
      false
    end

    def records_for_product(product_code, model: nil, mode: "product", force: false)
      index = sp_index(model: model, force: force)
      exact = product_code_exact(product_code)
      return [] unless product_code_valid?(exact)

      if mode.to_s == "module" && product_code_module?(exact)
        Array(index[:exact][exact])
      else
        Array(index[:base][product_code_base(exact)])
      end
    rescue
      []
    end

    def build_sp_index(model: nil, max_depth: -1, include_hidden: false)
      model ||= Sketchup.active_model
      records = scan(model: model, scope: :model, max_depth: max_depth, include_hidden: include_hidden, types: %i[group component])
      product_by_id = {}
      records.each do |record|
        codes = Array(record[:product_codes]).map { |code| product_code_exact(code) }.select { |code| product_code_valid?(code) }.uniq
        product_by_id[record[:entity_id]] = codes unless codes.empty?
      end

      index = empty_sp_index
      records.each do |record|
        own_codes = Array(record[:product_codes]).map { |code| product_code_exact(code) }.select { |code| product_code_valid?(code) }
        inherited_codes = Array(record[:path_ids]).reverse.flat_map { |id| Array(product_by_id[id]) }
        codes = (own_codes + inherited_codes).uniq
        next if codes.empty?

        indexed_record = record.merge(inherited_product_codes: inherited_codes.uniq, effective_product_codes: codes)
        codes.each do |code|
          exact = product_code_exact(code)
          base = product_code_base(exact)
          index[:exact][exact] << indexed_record
          index[:base][base] << indexed_record
        end
      end

      index[:exact].each_value { |list| list.uniq! { |record| record[:entity_id] || record.object_id } }
      index[:base].each_value { |list| list.uniq! { |record| record[:entity_id] || record.object_id } }
      index[:built_at] = Time.now.to_f
      index[:signature] = model_index_signature(model)
      index
    rescue
      empty_sp_index
    end

    def empty_sp_index
      { exact: Hash.new { |h, k| h[k] = [] }, base: Hash.new { |h, k| h[k] = [] }, built_at: nil, signature: nil }
    end

    def model_index_signature(model = nil)
      model ||= Sketchup.active_model
      if defined?(MH::ModelHub) && MH::ModelHub.respond_to?(:model_signature)
        return MH::ModelHub.model_signature(model)
      end

      entities = model && model.respond_to?(:entities) ? model.entities : nil
      [model.respond_to?(:guid) ? model.guid.to_s : "", entities.respond_to?(:length) ? entities.length : 0, model.respond_to?(:path) ? model.path.to_s : ""].hash
    rescue
      Time.now.to_i
    end

    def roots_for_scope(model, scope = :selection, roots = nil)
      case scope.to_sym
      when :roots
        Array(roots).compact
      when :model
        model && model.respond_to?(:entities) ? model.entities.to_a : []
      else
        selected_roots(model)
      end
    rescue
      []
    end

    def selected_roots(model = nil)
      model ||= Sketchup.active_model
      roots = []
      Array(model.active_path).reverse_each do |entity|
        roots << entity if container?(entity)
      end
      model.selection.to_a.each do |entity|
        roots << entity if container?(entity)
      end
      roots.compact.uniq.reject { |entity| deleted?(entity) }
    rescue
      []
    end

    def product_codes_from_selection(model = nil, allow_slow_scan: false)
      model ||= Sketchup.active_model
      if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:codes_from_selection)
        codes = MH::ProductContext.codes_from_selection(model, allow_slow_scan: allow_slow_scan)
        codes = Array(codes).map { |code| product_code_exact(code) }.select { |code| product_code_valid?(code) }.uniq
        return codes.sort_by { |code| product_code_sort_key(code) } unless codes.empty?
      end

      selected_roots(model).flat_map { |entity| entity_product_codes(entity) }
                           .select { |code| product_code_valid?(code) }
                           .uniq
                           .sort_by { |code| product_code_sort_key(code) }
    rescue
      []
    end

    def roots_matching_products(model_or_roots, products)
      roots = if model_or_roots.respond_to?(:selection)
        selected_roots(model_or_roots)
      else
        Array(model_or_roots)
      end
      targets = Array(products).map { |code| product_code_exact(code) }.select { |code| product_code_valid?(code) }.uniq
      bases = targets.map { |code| product_code_base(code) }.uniq
      matched = roots.select do |entity|
        entity_product_codes(entity).any? do |code|
          exact = product_code_exact(code)
          targets.include?(exact) || bases.include?(product_code_base(exact))
        end
      end
      matched.empty? ? roots : matched
    rescue
      []
    end

    def record_for(entity, ctx = nil)
      {
        entity: entity,
        entity_id: entity_id(entity),
        persistent_id: persistent_id(entity),
        type: entity_type(entity),
        name: entity_name(entity),
        definition_name: definition_name(entity),
        tag: tag_name(entity),
        material: material_name(entity),
        product_codes: entity_product_codes(entity),
        attrs: attributes_for(entity),
        definition_attrs: definition_attributes_for(entity),
        bounds: bounds_hash(entity),
        world_bounds: world_bounds_hash(entity, ctx),
        depth: ctx && ctx.respond_to?(:depth) ? ctx.depth : 0,
        parent_id: ctx && ctx.respond_to?(:parent) ? entity_id(ctx.parent) : nil,
        path_ids: ctx && ctx.respond_to?(:path) ? Array(ctx.path).map { |parent| entity_id(parent) }.compact : [],
        path_names: ctx && ctx.respond_to?(:path) ? Array(ctx.path).map { |parent| entity_name(parent) }.reject(&:empty?) : []
      }
    rescue
      {}
    end

    def attributes_for(entity)
      dictionaries_to_hash(entity.respond_to?(:attribute_dictionaries) ? entity.attribute_dictionaries : nil)
    rescue
      {}
    end

    def definition_attributes_for(entity)
      definition = entity.respond_to?(:definition) ? entity.definition : nil
      dictionaries_to_hash(definition && definition.respond_to?(:attribute_dictionaries) ? definition.attribute_dictionaries : nil)
    rescue
      {}
    end

    def dictionaries_to_hash(dictionaries)
      out = {}
      return out unless dictionaries

      dictionaries.each do |dict|
        dict_hash = {}
        if dict.respond_to?(:each_pair)
          dict.each_pair { |key, value| dict_hash[key.to_s] = raw_value(value) }
        else
          dict.each { |key, value| dict_hash[key.to_s] = raw_value(value) }
        end
        out[dict.name.to_s] = dict_hash unless dict_hash.empty?
      end
      out
    rescue
      {}
    end

    def raw_value(value)
      case value
      when String, Numeric, TrueClass, FalseClass, NilClass
        value
      else
        value.to_s
      end
    end

    def entity_product_codes(entity)
      text = "#{entity_name_raw(entity)} #{definition_name(entity)}"
      if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:scan_products)
        return MH::NameGrammar.scan_products(text).map { |code| product_code_exact(code) }.uniq
      end

      text.scan(/[A-Za-z]+\d+[A-Za-z]?(?:\.[A-Za-z0-9]+)?/i).map { |code| product_code_exact(code) }.uniq
    rescue
      []
    end

    def product_code_exact(code)
      if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:exact)
        MH::ProductContext.exact(code)
      else
        code.to_s.strip.upcase
      end
    end

    def product_code_base(code)
      if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:base)
        MH::ProductContext.base(code)
      else
        product_code_exact(code).split(".").first
      end
    end

    def product_code_valid?(code)
      if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:valid?)
        MH::ProductContext.valid?(code)
      else
        !!(product_code_exact(code) =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?\z/i)
      end
    end

    def product_code_module?(code)
      if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:module?)
        MH::ProductContext.module?(code)
      else
        product_code_exact(code).include?(".")
      end
    rescue
      false
    end

    def product_code_sort_key(code)
      if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:sort_key)
        MH::ProductContext.sort_key(code)
      else
        code.to_s.split(/(\d+)/).map { |part| part =~ /\d/ ? [1, part.to_i] : [0, part.downcase] }
      end
    end

    def bounds_hash(entity)
      bounds_to_hash(entity.respond_to?(:bounds) ? entity.bounds : nil)
    rescue
      nil
    end

    def world_bounds_hash(entity, ctx = nil)
      bounds = entity.respond_to?(:bounds) ? entity.bounds : nil
      return bounds_to_hash(bounds) unless ctx && ctx.respond_to?(:world_transform) && ctx.world_transform && bounds && !bounds.empty?

      bb = Geom::BoundingBox.new
      8.times { |index| bb.add(ctx.world_transform * bounds.corner(index)) }
      bounds_to_hash(bb)
    rescue
      bounds_hash(entity)
    end

    def bounds_to_hash(bounds)
      return nil unless bounds && !bounds.empty?

      {
        width: bounds.width.to_f,
        height: bounds.height.to_f,
        depth: bounds.depth.to_f,
        width_mm: bounds.width.to_f * 25.4,
        height_mm: bounds.height.to_f * 25.4,
        depth_mm: bounds.depth.to_f * 25.4
      }
    rescue
      nil
    end

    def container?(entity)
      (defined?(Sketchup::Group) && entity.is_a?(Sketchup::Group)) ||
        (defined?(Sketchup::ComponentInstance) && entity.is_a?(Sketchup::ComponentInstance))
    end

    def deleted?(entity)
      entity.respond_to?(:deleted?) && entity.deleted?
    rescue
      false
    end

    def entity_id(entity)
      entity.respond_to?(:entityID) ? entity.entityID : nil
    rescue
      nil
    end

    def persistent_id(entity)
      entity.respond_to?(:persistent_id) ? entity.persistent_id : nil
    rescue
      nil
    end

    def entity_type(entity)
      entity.class.name.to_s.split("::").last
    rescue
      ""
    end

    def entity_name(entity)
      value = entity_name_raw(entity)
      value.empty? ? definition_name(entity) : value
    end

    def entity_name_raw(entity)
      entity.respond_to?(:name) ? entity.name.to_s.strip : ""
    rescue
      ""
    end

    def definition_name(entity)
      entity.respond_to?(:definition) && entity.definition ? entity.definition.name.to_s.strip : ""
    rescue
      ""
    end

    def tag_name(entity)
      layer = entity.respond_to?(:layer) ? entity.layer : nil
      layer ? layer.name.to_s : ""
    rescue
      ""
    end

    def material_name(entity)
      material = entity.respond_to?(:material) ? entity.material : nil
      material ? material.display_name.to_s : ""
    rescue
      ""
    end
  end
end

# encoding: UTF-8

module MH
  module TraverseModel
    Context = Struct.new(:transform, :world_transform, :depth, :path, :parent, :name, :errors, keyword_init: true)

    module_function

    def each(root:, max_depth: -1, types: %i[group component], include_hidden: false, descend: nil, reject: nil, leaves_only: false, &block)
      return enum_for(__method__, root: root, max_depth: max_depth, types: types, include_hidden: include_hidden,
                                  descend: descend, reject: reject, leaves_only: leaves_only) unless block

      roots_for(root).each do |entity|
        walk(entity, Geom::Transformation.new, [], nil, 1, max_depth, normalize_types(types),
             include_hidden, descend, reject, leaves_only, [], &block)
      end
      nil
    end

    def collect(**opts)
      out = []
      each(**opts) { |entity, _ctx| out << entity }
      out
    end

    def count(**opts)
      n = 0
      each(**opts) { |_entity, _ctx| n += 1 }
      n
    end

    def walk_stateful(root:, max_depth: -1, types: %i[group component], include_hidden: false, reject_names: [], root_state: nil, &block)
      return 0 unless block

      errors = []
      count = 0
      roots_for(root).each do |entity|
        count += walk_stateful_entity(entity, Geom::Transformation.new, [], nil, 1, max_depth,
                                      normalize_types(types), include_hidden, normalize_reject_names(reject_names),
                                      root_state, errors, &block)
      end
      { count: count, errors: errors }
    end

    def roots_for(root)
      return [] unless root
      if defined?(Sketchup::Model) && root.is_a?(Sketchup::Model)
        root.entities.to_a
      elsif defined?(Sketchup::Entities) && root.is_a?(Sketchup::Entities)
        root.to_a
      elsif defined?(Sketchup::Selection) && root.is_a?(Sketchup::Selection)
        root.to_a
      elsif root.is_a?(Array)
        root
      elsif container?(root)
        children_of(root).to_a
      else
        [root]
      end
    rescue
      []
    end

    def walk(entity, parent_tr, path, parent, depth, max_depth, types, include_hidden, descend, reject, leaves_only, errors, &block)
      return unless valid_entity?(entity)
      return if max_depth >= 0 && depth > max_depth
      return if reject && safe_call(reject, entity, nil)
      return if hidden?(entity) && !include_hidden

      is_container = container?(entity)
      world_tr = entity.respond_to?(:transformation) ? parent_tr * entity.transformation : parent_tr
      ctx = Context.new(
        transform: parent_tr,
        world_transform: world_tr,
        depth: depth,
        path: path.dup.freeze,
        parent: parent,
        name: entity_name(entity),
        errors: errors
      ).freeze

      should_yield = type_match?(entity, types) && (!leaves_only || !is_container)
      block.call(entity, ctx) if should_yield

      return unless is_container
      return if descend && !safe_call(descend, entity, ctx)

      children_of(entity).each do |child|
        walk(child, world_tr, path + [entity], entity, depth + 1, max_depth, types,
             include_hidden, descend, reject, leaves_only, errors, &block)
      end
    rescue => e
      errors << [entity, e]
      nil
    end

    def walk_stateful_entity(entity, parent_tr, path, parent, depth, max_depth, types, include_hidden, reject_names, parent_state, errors, &block)
      return 0 unless valid_entity?(entity)
      return 0 if max_depth >= 0 && depth > max_depth
      return 0 if hidden?(entity) && !include_hidden

      name = entity_name(entity)
      return 0 if rejected_name?(name, reject_names)

      is_container = container?(entity)
      world_tr = entity.respond_to?(:transformation) ? parent_tr * entity.transformation : parent_tr
      ctx = Context.new(
        transform: parent_tr,
        world_transform: world_tr,
        depth: depth,
        path: path.dup.freeze,
        parent: parent,
        name: name,
        errors: errors
      ).freeze

      count = 0
      child_state = parent_state
      if type_match?(entity, types)
        maybe_state = block.call(entity, world_tr, parent_state, ctx)
        child_state = maybe_state unless maybe_state.nil?
        count += 1
      end

      if is_container
        children_of(entity).each do |child|
          count += walk_stateful_entity(child, world_tr, path + [entity], entity, depth + 1, max_depth,
                                        types, include_hidden, reject_names, child_state, errors, &block)
        end
      end
      count
    rescue => e
      errors << [entity, e]
      0
    end

    def normalize_types(types)
      Array(types).map(&:to_sym)
    end

    def normalize_reject_names(reject_names)
      Array(reject_names).compact.map { |value| value.is_a?(Regexp) ? value : value.to_s.strip }.reject { |value| value.respond_to?(:empty?) && value.empty? }
    end

    def rejected_name?(name, reject_names)
      reject_names.any? do |pattern|
        pattern.is_a?(Regexp) ? pattern.match?(name.to_s) : name.to_s == pattern.to_s
      end
    end

    def type_match?(entity, types)
      return true if types.empty?
      (types.include?(:group) && defined?(Sketchup::Group) && entity.is_a?(Sketchup::Group)) ||
        (types.include?(:component) && defined?(Sketchup::ComponentInstance) && entity.is_a?(Sketchup::ComponentInstance)) ||
        (types.include?(:face) && defined?(Sketchup::Face) && entity.is_a?(Sketchup::Face)) ||
        (types.include?(:edge) && defined?(Sketchup::Edge) && entity.is_a?(Sketchup::Edge))
    end

    def container?(entity)
      (defined?(Sketchup::Group) && entity.is_a?(Sketchup::Group)) ||
        (defined?(Sketchup::ComponentInstance) && entity.is_a?(Sketchup::ComponentInstance))
    end

    def children_of(entity)
      if defined?(Sketchup::Group) && entity.is_a?(Sketchup::Group)
        entity.entities
      elsif defined?(Sketchup::ComponentInstance) && entity.is_a?(Sketchup::ComponentInstance) && entity.definition
        entity.definition.entities
      else
        []
      end
    rescue
      []
    end

    def hidden?(entity)
      (entity.respond_to?(:hidden?) && entity.hidden?) ||
        (entity.respond_to?(:layer) && entity.layer && !entity.layer.visible?)
    rescue
      false
    end

    def valid_entity?(entity)
      entity && (!entity.respond_to?(:valid?) || entity.valid?)
    rescue
      false
    end

    def entity_name(entity)
      name = entity.respond_to?(:name) ? entity.name.to_s : ""
      name = entity.definition.name.to_s if name.strip.empty? && entity.respond_to?(:definition) && entity.definition
      name.strip
    rescue
      ""
    end

    def safe_call(callable, entity, ctx)
      callable.call(entity, ctx)
    rescue
      false
    end
  end
end

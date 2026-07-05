# encoding: UTF-8
#
# MH_Registry / connectors / dc_import / naming.rb
# ---------------------------------------------------------------------------
# Naming helpers for DCImportPipeline.
# ---------------------------------------------------------------------------

module MH
  module RegistryApp
    module Connectors
      module DCImportPipeline
        module_function

        # BUG FIX (xem MH_Registry/DC_COPIES_NAMING_BUG_PLAN.md):
        # Ghi ten dong (entity.name + dynamic_attributes name/_name_formula/
        # _name_error) vao cay DC lam HONG copy-tracking cua SketchUp khi DC dung
        # tinh nang `_copies` -> sinh them nhieu definition + bo copy "do day cu".
        # Theo quyet dinh: BO HAN viec truyen ten vao DC. Chi giu lai attribute
        # MH_Registry (metadata sidecar, KHONG anh huong DC redraw/copy).
        # Bat lai = doi tra ve true (nhung khi do bug copies se quay lai).
        def write_dc_dynamic_names?
          false
        end

        def resolve_dc_naming(instance, profile, context = {})
          product = context_value(context, :product_code, 'product_code').to_s.strip
          product = profile['product_code'].to_s.strip if product.empty? && profile
          product = resolve_product_code(instance, context) if product.empty?
          return {} if product.empty?

          project = registry_project
          binding = profile && (profile['_binding'] || profile[:_binding])

          rule = module_rule_for_product(project, product, context)
          import_name = context_value(context, :import_name, 'import_name').to_s.strip
          import_name = instance.definition.name.to_s.strip if import_name.empty? && instance && instance.respond_to?(:definition)
          import_name = strip_product_prefix(import_name, product)

          prefix = value_from_rule(rule, 'prefix').to_s.strip
          prefix = product_base_code(product) if prefix.empty?
          modul = value_from_rule(rule, 'modul', 'module', 'module_name').to_s.strip
          modul = import_name if modul.empty?
          modul = strip_product_prefix(modul, product)
          suffix = value_from_rule(rule, 'suffix').to_s.strip

          separators = project['name_separators'] || project[:name_separators] || {}
          sep_prefix = separators['sep_prefix'] || separators[:sep_prefix] || '.'
          sep_suffix = separators['sep_suffix'] || separators[:sep_suffix] || '_'

          auto_import = auto_module_import_context?(context)
          if auto_import && binding_modul_only?(binding)
            prefix = product_base_code(product)
            modul = next_module_code_for_product(prefix, instance)
          elsif auto_import
            prefix = product_base_code(product)
            modul = ''
          end

          full_name = module_full_name(prefix, modul, sep_prefix)
          full_name = [full_name, suffix].reject(&:empty?).join(sep_suffix.to_s) unless suffix.empty?

          {
            'product_code' => product,
            'prefix_name' => prefix,
            'modul_name' => modul,
            'module_name' => modul,
            'suffix_name' => suffix,
            'full_name' => full_name,
            'import_name' => import_name,
            'sep_prefix' => sep_prefix,
            'sep_suffix' => sep_suffix
          }
        rescue => e
          MH::RegistryApp.dbg("[DCImportPipeline] resolve naming error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          {}
        end

        def binding_modul_only?(binding)
          value = binding && (binding['modul_only'] || binding[:modul_only] ||
                              binding['module_only'] || binding[:module_only])
          %w[1 true yes y on x checked].include?(value.to_s.strip.downcase)
        rescue
          false
        end

        def auto_module_import_context?(context)
          source = context_value(context || {}, :source, 'source').to_s
          import_path = context_value(context || {}, :import_path, 'import_path').to_s
          source == 'MH_Superimp' || !import_path.empty?
        end

        def product_base_code(product_code)
          product_code.to_s.strip.upcase.split('.').first.to_s
        end

        def module_full_name(prefix, modul, sep_prefix = '.')
          pfx = prefix.to_s.strip
          mod = modul.to_s.strip
          return pfx if mod.empty?
          return mod if pfx.empty?
          return mod if mod.upcase.start_with?("#{pfx.upcase}.")

          [pfx, mod].reject(&:empty?).join(sep_prefix.to_s.empty? ? '.' : sep_prefix.to_s)
        end

        def next_module_code_for_product(product_code, exclude_entity = nil)
          product = product_base_code(product_code)
          return '' if product.empty?

          used = used_module_indexes(product, exclude_entity)
          idx = 1
          idx += 1 while used.include?(idx)
          "#{product}.#{idx}"
        end

        def used_module_indexes(product_code, exclude_entity = nil)
          product = product_base_code(product_code)
          return [] if product.empty?

          used = []
          pattern = /#{Regexp.escape(product)}\.(\d+)/i
          model = Sketchup.active_model
          entity_sets = [model.entities]
          entity_sets << model.active_entities if model.respond_to?(:active_entities) && model.active_entities != model.entities
          seen = {}
          entity_sets.each do |entities|
            walk_model_entities(entities, max_depth: 0, seen_entities: seen) do |entity|
              next if exclude_entity && same_entity?(entity, exclude_entity)

              entity_module_texts(entity).each do |text|
                text.to_s.scan(pattern) do |match|
                  idx = Array(match).first.to_i
                  used << idx if idx > 0
                end
              end
            end
          end
          used.uniq
        rescue => e
          MH::RegistryApp.dbg("[DCImportPipeline] used module indexes error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          []
        end

        def same_entity?(a, b)
          return true if a.equal?(b)
          a.respond_to?(:persistent_id) && b.respond_to?(:persistent_id) && a.persistent_id == b.persistent_id
        rescue
          false
        end

        def walk_model_entities(entities, max_depth: 0, depth: 0, seen_entities: {}, seen_definitions: {}, &block)
          return unless entities
          return if depth > max_depth

          entities.each do |entity|
            next unless entity && entity.valid?
            eid = entity.persistent_id rescue entity.entityID rescue entity.object_id
            next if seen_entities[eid]
            seen_entities[eid] = true

            yield entity
            if entity.is_a?(Sketchup::Group)
              walk_model_entities(
                entity.entities,
                max_depth: max_depth,
                depth: depth + 1,
                seen_entities: seen_entities,
                seen_definitions: seen_definitions,
                &block
              )
            elsif entity.is_a?(Sketchup::ComponentInstance) && entity.respond_to?(:definition) && entity.definition
              def_key = entity.definition.object_id
              next if seen_definitions[def_key]
              seen_definitions[def_key] = true
              walk_model_entities(
                entity.definition.entities,
                max_depth: max_depth,
                depth: depth + 1,
                seen_entities: seen_entities,
                seen_definitions: seen_definitions,
                &block
              )
            end
          end
          nil
        end

        def entity_module_texts(entity)
          attrs = []
          if entity.respond_to?(:get_attribute)
            attrs << entity.get_attribute('MH_Registry', 'dc_modul')
            attrs << entity.get_attribute('MH_Registry', 'dc_module')
            attrs << entity.get_attribute('MH_Registry', 'dc_module_name')
            attrs << entity.get_attribute('MH_Registry', 'dc_full_name')
            attrs << entity.get_attribute('MH_Registry', 'dc_child_full_name')
            attrs << entity.get_attribute('dynamic_attributes', 'name')
            attrs << entity.get_attribute('dynamic_attributes', '_name')
          end
          [
            entity.respond_to?(:name) ? entity.name : '',
            entity.respond_to?(:definition) && entity.definition ? entity.definition.name : '',
            attrs
          ].flatten.compact.map(&:to_s)
        rescue
          []
        end

        def strip_product_prefix(value, product_code)
          text = value.to_s.strip
          product = product_code.to_s.strip
          return text if text.empty? || product.empty?

          text.sub(/\A#{Regexp.escape(product)}[._\-\s]+/i, '')
        end

        def apply_dc_naming(instance, naming)
          return unless instance && instance.valid? && naming && !naming.empty?

          model = Sketchup.active_model
          started = false
          unless model.respond_to?(:operation_active?) && model.operation_active?
            model.start_operation('MH DC Naming', true)
            started = true
          end

          apply_registry_naming_attrs(instance, naming)
          cleanup_outer_instance_name(instance, naming)
          apply_inner_group_naming(instance, naming)

          model.commit_operation if started
        rescue => e
          model.abort_operation if started rescue nil
          MH::RegistryApp.dbg("[DCImportPipeline] apply naming error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
        end

        def apply_registry_naming_attrs(entity, naming, role = nil, detail_name = nil, full_name = nil)
          naming.each do |key, value|
            next if value.to_s.empty?
            entity.set_attribute('MH_Registry', "dc_#{key}", value)
          end
          entity.set_attribute('MH_Registry', 'dc_prefix', naming['prefix_name']) unless naming['prefix_name'].to_s.empty?
          entity.set_attribute('MH_Registry', 'dc_modul', naming['modul_name']) unless naming['modul_name'].to_s.empty?
          entity.set_attribute('MH_Registry', 'dc_module', naming['module_name']) unless naming['module_name'].to_s.empty?
          entity.set_attribute('MH_Registry', 'dc_role', role) if role
          entity.set_attribute('MH_Registry', 'dc_detail_name', detail_name) if detail_name
          entity.set_attribute('MH_Registry', 'dc_child_full_name', full_name) if full_name
        end

        def cleanup_outer_instance_name(instance, naming)
          # Bo han ghi ten dong vao DC (xem write_dc_dynamic_names?).
          return unless write_dc_dynamic_names?

          prefix = naming['prefix_name'].to_s.strip
          full_name = naming['full_name'].to_s.strip
          return if prefix.empty? && full_name.empty?

          unless full_name.empty?
            instance.name = full_name if instance.respond_to?(:name=)
            instance.set_attribute('dynamic_attributes', 'name', full_name)
            instance.set_attribute('dynamic_attributes', '_name_formula', "\"#{full_name}\"")
            instance.set_attribute('dynamic_attributes', '_name_error', full_name)
            return
          end

          sep = '.'
          current = instance.name.to_s
          marker = "#{prefix}#{sep}"
          if current.start_with?(marker)
            instance.name = current[marker.length..-1].to_s
          end
        end

        def apply_inner_group_naming(instance, naming)
          groups = visible_child_containers(instance)
          prefix = naming['prefix_name'].to_s.strip
          return if prefix.empty? || groups.empty?

          stats = { 'panel' => 0, 'back' => 0 }
          groups.each do |group|
            role = back_group?(group) ? 'back' : 'panel'
            detail = role == 'back' ? 'Hậu' : panel_detail_name(group, naming)
            full_name = child_full_name(naming, role, detail)

            apply_registry_naming_attrs(group, naming, role, detail, full_name)
            # Bo han ghi ten dong vao group con cua DC: chinh day la cho lam hong
            # copy-tracking khi DC dung _copies. Chi giu metadata MH_Registry o tren.
            set_entity_dynamic_name(group, full_name) if write_dc_dynamic_names?
            stats[role] += 1
          end
          MH::RegistryApp.dbg("[DCImportPipeline] naming inner panel=#{stats['panel']} back=#{stats['back']}") if MH::RegistryApp.respond_to?(:dbg)
          stats
        end

        def child_full_name(naming, role, detail)
          prefix = naming['prefix_name'].to_s.strip
          modul = naming['modul_name'].to_s.strip
          detail = detail.to_s.strip
          sep_suffix = naming['sep_suffix'].to_s.empty? ? '_' : naming['sep_suffix'].to_s
          return detail if prefix.empty?

          head = modul.empty? ? prefix : modul
          [head, detail].reject(&:empty?).join(sep_suffix)
        end

        def panel_detail_name(group, naming)
          product = naming['product_code'].to_s.strip
          candidates = [
            group.name,
            group.get_attribute('dynamic_attributes', 'name'),
            group.get_attribute('dynamic_attributes', '_name'),
            group.definition.name,
            naming['modul_name'],
            naming['import_name']
          ]

          candidates.each do |value|
            detail = clean_child_detail_name(value, product)
            return detail unless detail.empty?
          end

          'Panel'
        end

        def clean_child_detail_name(value, product)
          text = value.to_s.strip
          return '' if text.empty?

          text = strip_product_prefix(text, product)
          text = text.sub(/\A(?:group|component)\s*#?\d*\z/i, '').strip
          text = text.sub(/\Adefinition\s*#?\d*\z/i, '').strip
          text = text.sub(/#\d+\z/, '').strip
          text
        end

        def set_entity_dynamic_name(entity, name)
          return if name.to_s.strip.empty?

          entity.name = name if entity.respond_to?(:name=)
          entity.set_attribute('dynamic_attributes', 'name', name)
          entity.set_attribute('dynamic_attributes', '_name_formula', "\"#{name}\"")
          entity.set_attribute('dynamic_attributes', '_name_error', name)
        end

        def registry_project
          if defined?(MH::Registry) && MH::Registry.respond_to?(:project)
            MH::Registry.project || {}
          else
            {}
          end
        rescue
          {}
        end

        def module_rule_for_product(project, product_code, context = {})
          modules = project['modules'] || project[:modules] || []
          product = product_code.to_s.strip.upcase
          import_name = context_value(context, :import_name, 'import_name').to_s.downcase
          candidates = Array(modules).select do |row|
            row_product = value_from_rule(row, 'sp', 'product', 'product_code').to_s.strip.upcase
            row_product.empty? || row_product == product
          end
          exact = candidates.find do |row|
            modul = value_from_rule(row, 'modul', 'module', 'module_name').to_s.downcase
            !modul.empty? && !import_name.empty? && import_name.include?(modul)
          end
          exact || candidates.find { |row| value_from_rule(row, 'sp', 'product', 'product_code').to_s.strip.upcase == product } || candidates.first
        end

        def value_from_rule(row, *keys)
          return '' unless row.respond_to?(:key?)
          keys.each do |key|
            return row[key] if row.key?(key)
            sym = key.to_sym
            return row[sym] if row.key?(sym)
          end
          ''
        end

      end
    end
  end
end

# encoding: UTF-8

require 'set'

module MH
  module RegistryApp
    module Connectors
      module SelectSimilar
        module_function

        def ensure_loaded
          return if defined?(MH::SelectSimilar)
          path = File.join(Sketchup.find_support_file('Plugins'), 'MH_SelectSimilar', 'main.rb')
          load path if File.exist?(path)
        end

        def available?
          ensure_loaded
          defined?(MH::SelectSimilar)
        rescue
          false
        end

        def isolate(entities = nil)
          ensure_loaded
          return false unless available?
          if entities && !Array(entities).empty?
            sel = Sketchup.active_model.selection
            sel.clear
            Array(entities).each { |entity| sel.add(entity) if entity && entity.valid? }
          end
          MH::SelectSimilar.isolate
          true
        end

        def unisolate
          ensure_loaded
          return false unless available?
          MH::SelectSimilar.unisolate
          true
        end

        def select_like(ref, criteria = nil)
          ensure_loaded
          return false unless available?

          refs = Array(ref).compact.select { |entity| entity && entity.valid? }
          return false if refs.empty?

          model = Sketchup.active_model
          settings = MH::SelectSimilar.settings.dup
          if criteria.respond_to?(:each)
            criteria.each { |key, value| settings[key.to_sym] = value }
          end

          all_entities = MH::SelectSimilar.collect_entities(
            settings[:scope_filter],
            settings[:nesting_filter],
            model
          )

          needs_bounds = settings[:bounding_size] || settings[:bounding_volume] || settings[:min_thickness]
          similarity_index = MH::SimilarityIndex.new(
            all_entities,
            dimensions: (needs_bounds ? ->(entity) { MH::SelectSimilar.bounds_dims(entity) } : nil),
            material: ->(entity) { MH::SelectSimilar.get_material(entity) },
            tag: ->(entity) { MH::SelectSimilar.get_tag(entity) }
          )
          ref_dims = {}
          refs.each { |entity| ref_dims[entity] = MH::SelectSimilar.bounds_dims(entity) } if needs_bounds
          ref_set = refs.to_set
          matches = refs.dup

          matched_set = ref_set.dup
          refs.each do |reference|
            similarity_index.candidates(reference, settings).each do |entity|
              next if matched_set.include?(entity)
              feature = similarity_index.feature(entity)
              target_dims = needs_bounds && feature ? feature.dimensions : nil
              if MH::SelectSimilar.matches_criteria?(reference, entity, settings, ref_dims: ref_dims[reference], target_dims: target_dims)
                matches << entity
                matched_set.add(entity)
              end
            end
          end

          model.start_operation('Select Similar', true)
          model.selection.clear
          model.selection.add(matches)
          model.commit_operation
          matches
        rescue => e
          model.abort_operation rescue nil
          MH::RegistryApp.dbg("[MH_Registry] select_similar.select_like error: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          false
        end

        def reload
          ensure_loaded
          MH::SelectSimilar.reload if available? && MH::SelectSimilar.respond_to?(:reload)
        end
      end
    end

    Connector.register('select_similar', Connectors::SelectSimilar) if defined?(Connector)
  end
end

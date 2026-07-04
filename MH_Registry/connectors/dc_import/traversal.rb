# encoding: UTF-8
#
# MH_Registry / connectors / dc_import / traversal.rb
# ---------------------------------------------------------------------------
# Entity traversal helpers for DCImportPipeline.
# ---------------------------------------------------------------------------

module MH
  module RegistryApp
    module Connectors
      module DCImportPipeline
        module_function

        def visible_child_containers(root)
          return [] unless root && root.respond_to?(:definition) && root.definition

          result = []
          walk_child_containers(root.definition.entities, result)
          result
        end

        def walk_child_containers(entities, result)
          entities.each do |entity|
            next unless visible_entity?(entity)
            next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

            result << entity
            child_entities =
              if entity.is_a?(Sketchup::Group)
                entity.entities
              elsif entity.respond_to?(:definition) && entity.definition
                entity.definition.entities
              end
            walk_child_containers(child_entities, result) if child_entities
          end
        end

        def visible_groups(root)
          result = []
          walk_entities(root.definition.entities, result)
          result
        end

        def direct_visible_groups(root)
          return [] unless root && root.respond_to?(:definition) && root.definition

          root.definition.entities.select do |entity|
            entity.is_a?(Sketchup::Group) && visible_entity?(entity)
          end
        end

        def walk_entities(entities, result)
          entities.each do |entity|
            next unless visible_entity?(entity)

            if entity.is_a?(Sketchup::Group)
              result << entity
              walk_entities(entity.entities, result)
            elsif entity.is_a?(Sketchup::ComponentInstance)
              walk_entities(entity.definition.entities, result)
            end
          end
        end

        def visible_entity?(entity)
          return false unless entity && entity.valid?
          return false if entity.hidden?
          return false if entity.respond_to?(:layer) && entity.layer && !entity.layer.visible?
          true
        end

        def back_group?(group)
          text = [
            group.name,
            group.definition.name,
            group.get_attribute('dynamic_attributes', 'name'),
            group.get_attribute('dynamic_attributes', '_name')
          ].compact.join(' ').downcase
          text.include?('hau') || text.include?('hậu') || text.include?('back')
        end
      end
    end
  end
end

# encoding: UTF-8

require 'json'
require 'set'

module MH
  module Isolate
    module State
      DICT = 'MH_isolate'.freeze
      STATE_KEY = 'isolation_state'.freeze
      TAG_MARKER_KEY = 'temporary_tag'.freeze
      FORMAT_VERSION = 1

      @runtime = {}

      class << self
        def model_key(model)
          model.object_id
        end

        def active?(model = Sketchup.active_model)
          data = fetch(model)
          data && data['active'] == true
        end

        def isolated_selection_set(model = Sketchup.active_model)
          data = fetch(model)
          Array(data && data['selected_pids']).map(&:to_i).to_set
        end

        def fetch(model, reload: false)
          return nil unless model
          key = model_key(model)
          return @runtime[key] if !reload && @runtime.key?(key)

          raw = model.get_attribute(DICT, STATE_KEY)
          data = parse(raw)
          @runtime[key] = data
        end

        def save(model, data)
          data['version'] = FORMAT_VERSION
          data['active'] = true
          @runtime[model_key(model)] = data
          model.set_attribute(DICT, STATE_KEY, JSON.generate(data))
          data
        end

        def clear(model)
          @runtime.delete(model_key(model))
          dictionary = model.attribute_dictionary(DICT, false)
          dictionary.delete_key(STATE_KEY) if dictionary
          nil
        end

        def sync(model)
          fetch(model, reload: true)
        end

        def release(model)
          @runtime.delete(model_key(model)) if model
        end

        # Entity deletion is safe even if the persisted record remains stale.
        # It is compacted during restore, while this callback keeps live state clean.
        def note_removed(model, entity_id)
          data = @runtime[model_key(model)]
          return unless data

          %w[objects loose].each do |key|
            next unless data[key].is_a?(Array)
            data[key].reject! { |record| record['entity_id'].to_i == entity_id.to_i }
          end
        end

        def entity(model, persistent_id)
          return nil unless persistent_id
          found = model.find_entity_by_persistent_id(persistent_id.to_i)
          found if found && found.valid?
        rescue StandardError
          nil
        end

        def layer(model, persistent_id, fallback_name = nil)
          found = entity(model, persistent_id)
          return found if found.is_a?(Sketchup::Layer)
          return model.layers[fallback_name] if fallback_name && model.layers[fallback_name]
          nil
        rescue StandardError
          nil
        end

        def temp_layer(model, data)
          layer(model, data['temp_tag_pid'], data['temp_tag_name'])
        end

        def marked_temp_layer?(layer)
          layer && layer.get_attribute(DICT, TAG_MARKER_KEY, false) == true
        rescue StandardError
          false
        end

        def orphan_temp_layers(model)
          model.layers.select { |layer| marked_temp_layer?(layer) }
        end

        def recovery_needed?(model)
          !active?(model) && !orphan_temp_layers(model).empty?
        end

        private

        def parse(raw)
          return nil unless raw.is_a?(String) && !raw.empty?
          data = JSON.parse(raw)
          data.is_a?(Hash) && data['active'] == true ? data : nil
        rescue JSON::ParserError, TypeError
          nil
        end
      end
    end
  end
end

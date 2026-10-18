# frozen_string_literal: true

require 'json'
require_relative 'ids'

module MH
  module CAD2Module
    # Product membership is model metadata; visible parts are independent Groups.
    class Assembly
      DICT = 'MH_CAD2Module_Assemblies'
      PART_DICT = 'MH_CAD2Module'
      attr_reader :model, :persistent_id

      def self.create(model)
        id = "assembly-#{Ids.uuid}"
        model.set_attribute(DICT, id, JSON.generate('transform' => Geom::Transformation.new.to_a, 'attributes' => {}, 'name' => '', 'members' => []))
        new(model, id)
      end

      def self.all(model)
        dictionary = model.attribute_dictionary(DICT)
        return [] unless dictionary
        dictionary.keys.filter_map do |id|
          product = new(model, id)
          product if product.valid?
        end
      end

      def initialize(model, id)
        @model = model
        @persistent_id = id
      end

      def data
        raw = model.get_attribute(DICT, persistent_id)
        if raw != @raw
          @data = raw ? JSON.parse(raw) : nil
          @raw = raw
        end
        @data
      end

      def write(values)
        @raw = JSON.generate(values)
        model.set_attribute(DICT, persistent_id, @raw)
        @data = values
      end

      def members
        Array(data && data['members']).filter_map do |id|
          entity = model.find_entity_by_persistent_id(id)
          entity if entity && entity.valid? && entity.parent == model && entity.get_attribute(PART_DICT, 'assembly_id') == persistent_id
        end
      end

      def add_member(entity)
        ids = members.map(&:persistent_id)
        entity.set_attribute(PART_DICT, 'assembly_id', persistent_id)
        values = data
        values['members'] = (ids + [entity.persistent_id]).uniq
        write(values)
      end

      def valid?
        !model.get_attribute(DICT, persistent_id).nil? && !members.empty?
      end

      def definition
        Definition.new(self)
      end

      def transformation
        Geom::Transformation.new(data.fetch('transform'))
      end

      def transformation=(value)
        delta = value * transformation.inverse
        members.each { |e| e.transform!(delta) }
        values = data
        values['transform'] = value.to_a
        write(values)
      end

      def name
        data['name']
      end

      def name=(value)
        values = data
        values['name'] = value
        write(values)
      end

      def get_attribute(dict, key, fallback = nil)
        data.fetch('attributes', {}).fetch(dict, {}).fetch(key, fallback)
      end

      def set_attribute(dict, key, value)
        values = data
        values['attributes'][dict] ||= {}
        values['attributes'][dict][key] = value
        write(values)
      end

      def hidden?
        parts = members
        !parts.empty? && parts.all?(&:hidden?)
      end

      def hidden=(value)
        values = data
        if value
          values['visibility'] ||= members.to_h { |e| [e.persistent_id.to_s, e.hidden?] }
          members.each { |e| e.hidden = true }
        else
          visibility = values.delete('visibility') || {}
          members.each { |e| e.hidden = visibility.fetch(e.persistent_id.to_s, false) }
        end
        write(values)
      end

      def bounds
        box = Geom::BoundingBox.new
        members.each { |e| box.add(e.bounds) }
        box
      end

      def make_unique
        self
      end

      def erase!
        members.each(&:erase!)
        model.delete_attribute(DICT, persistent_id)
      end

      def ==(other)
        other.is_a?(Assembly) && other.model == model && other.persistent_id == persistent_id
      end

      class Entities
        include Enumerable

        def initialize(product)
          @product = product
        end

        def each(&block)
          @product.members.each(&block)
        end

        def add_group
          group = @product.model.entities.add_group
          @product.add_member(group)
          group
        end

        def add_instance(definition, transform)
          instance = @product.model.entities.add_instance(definition, transform)
          @product.add_member(instance)
          instance
        end

        def place(instance)
          instance.transformation = @product.transformation * instance.transformation
        end
      end

      class Definition
        def initialize(product)
          @product = product
        end

        def entities
          Entities.new(@product)
        end

        def instances
          [@product]
        end

        def save_as(path)
          # Snapshots contain the whole product, without a live model container.
          model = @product.model
          definition = model.definitions.add('CAD2Module_Snapshot')
          inverse = @product.transformation.inverse
          @product.members.each do |part|
            group = definition.entities.add_group
            copy = group.entities.add_instance(part.definition, Geom::Transformation.new)
            copy.explode
            group.transformation = inverse * part.transformation
            group.name = part.name
            group.layer = part.layer
            group.material = part.material
            group.hidden = part.hidden?
            part.attribute_dictionaries&.each { |dict| dict.each_pair { |key, value| group.set_attribute(dict.name, key, value) } }
          end
          definition.save_as(path)
        ensure
          model.definitions.remove(definition) if definition&.valid?
        end
      end
    end
  end
end

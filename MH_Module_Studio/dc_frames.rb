# encoding: UTF-8
module MH
  module ModuleStudio
    module DCFrames
      extend self
      LENGTH_UNITS = %w[MILLIMETERS CENTIMETERS METERS INCHES FEET].freeze

      def merge_attributes(definition, instance, prefix: '')
        merged = definition.merge(instance)
        # COPY is an instance index. The original omits it; a cached index on
        # the shared definition belongs to another instance, not to the original.
        key = prefix+'copy'
        merged.delete(key) unless instance.key?(key) && !instance[key].nil?
        merged
      end

      # STRING is a DC display type. An explicit length formula unit still
      # describes a physical length, including hidden intermediate attributes.
      def typed_length?(attributes, key)
        attributes["_#{key}_units"].to_s.upcase=='STRING' &&
          LENGTH_UNITS.include?(attributes["_#{key}_formulaunits"].to_s.upcase)
      end

      # A constant zero on an already-flat axis describes a 2D guide, not a
      # request to collapse a solid. Keep metadata evaluation separate from mesh.
      def flat_axis?(node, axis)
        size = Core.dimensions(node['local_bounds'])[axis]*25.4*captured_scale(node,axis).abs
        formula = node['attributes']["_#{%w[lenx leny lenz][axis]}_formula"].to_s.strip
        size.abs<=0.001 && (formula.empty? || formula.match?(/\A[+\-]?0+(?:\.0*)?\z/))
      end

      def captured_scale(node, axis)
        node['transform'][[0,5,10][axis]]
      end
    end
  end
end

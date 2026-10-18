# encoding: UTF-8
module MH
  module ModuleStudio
    module EnvelopePolicy
      extend self

      def derive(snapshot,program)
        attrs = snapshot.fetch('dc_inputs',{})
        axes = 3.times.select do |axis|
          key = %w[lenx leny lenz][axis]
          declared = !attrs["_#{key}_formula"].to_s.strip.empty?
          access = attrs["_#{key}_access"].to_s.upcase
          # A dimension without an exposed input can be a geometry output even
          # when the DC author omitted access metadata. Independence from its
          # measured parent dimension is still proved from the entire ATT tree.
          eligible = access=='VIEW' || access=='NONE' || access.empty?
          eligible && !program.envelope_dependencies(axis).key?("@#{key}") &&
            (!declared || !program.declared_dimension_dependencies(axis).key?("@#{key}"))
        rescue Core::Error
          false
        end
        {'version'=>1,'axes'=>axes,'source'=>'readonly_att_independent_geometry'}
      end

      def reconcile(stored,derived)
        return derived if stored.nil? || stored==derived
        unless stored.is_a?(Hash) && stored.keys.sort==derived.keys.sort &&
               stored.merge('axes'=>derived['axes'])==derived && stored['axes'].is_a?(Array) &&
               stored['axes'].uniq==stored['axes'] && (stored['axes']-derived['axes']).empty?
          raise Core::Error,'Kích thước phụ thuộc không khớp thuộc tính chỉ đọc và công thức ATT.'
        end
        derived
      end

      # Unexposed parent lengths are construction inputs, not limits on the
      # resulting union. Retain them when a thicker perpendicular panel passes
      # an edge, otherwise the next redraw would feed that union back into ATT.
      def input_axes(snapshot,policy)
        attrs = snapshot.fetch('dc_inputs',{})
        3.times.select do |axis|
          key = %w[lenx leny lenz][axis]
          !Array(policy&.fetch('axes',[])).include?(axis) &&
            ['', 'NONE', 'VIEW'].include?(attrs["_#{key}_access"].to_s.upcase) && attrs["_#{key}_formula"].to_s.strip.empty?
        end
      end

      def inputs(current,snapshot,policy)
        result = Core.copy_data(current['envelope'])
        stored = current['formula_envelope'] || ConstructionFrame.inputs(current,snapshot)
        return result unless stored
        Core.bounds!(stored)
        return Core.copy_data(stored) if ConstructionFrame.metadata(snapshot)
        input_axes(snapshot,policy).each { |axis| 2.times { |side| result[side][axis] = stored[side][axis] } }
        result
      end

      def thickness_parts(bundle)
        result = Hash.new { |hash,axis| hash[axis] = [] }
        bundle.fetch('rules',{}).each_value do |rule|
          rule['parts'].each do |part|
            result[part['thickness_axis']] |= [part['key']] if part['driver'] && [0,1,2].include?(part['thickness_axis'])
          end
        end
        result
      end

      def target(current,bounds,policy,program,input_axes: [],inputs: current,drivers: {})
        result = Core.copy_data(current)
        return result unless policy
        unless policy.is_a?(Hash) && policy['version']==1 && policy['source']=='readonly_att_independent_geometry' &&
               policy['axes'].is_a?(Array) && policy['axes'].uniq==policy['axes'] && policy['axes'].all? { |axis| [0,1,2].include?(axis) }
          raise Core::Error,'Chính sách kích thước phụ thuộc không hợp lệ.'
        end
        union = Core.union(bounds)
        policy['axes'].each do |axis|
          declared = program.declared_dimension(axis)
          if declared && (!declared.finite? || declared<=0 || (Core.dimensions(union)[axis]-declared).abs>0.001)
            raise Core::Error,"Kích thước #{%w[X Y Z][axis]} không khớp công thức kích thước cha. Không áp dụng quy tắc."
          end
          2.times { |side| result[side][axis] = union[side][axis] }
        end
        return Core.bounds!(union) if program.construction_inputs
        input_axes.each do |axis|
          2.times do |side|
            boundary = inputs[side][axis]
            beyond = bounds.select { |part| (part['bounds'][side][axis]-boundary)*(side==1 ? 1 : -1)>Core::ENVELOPE_TOLERANCE }
            result[side][axis] = if !beyond.empty? && beyond.all? { |part| Array(drivers[axis]).include?(part['key']) }
                                  union[side][axis]
                                else
                                  boundary
                                end
          end
        end
        Core.bounds!(result)
      end
    end
  end
end

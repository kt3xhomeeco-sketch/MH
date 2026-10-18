# encoding: UTF-8
module MH
  module ModuleStudio
    # Native aggregate-envelope repair after parent Scale. Internal geometry
    # remains owned by ScaleRedraw; contact fitting remains AssemblyContacts.
    module AssemblyEnvelope
      extend self
      TARGET_KEY = 'assembly_envelope_target_v1'.freeze

      def bounds(component)
        component.definition.invalidate_bounds
        [component.definition.bounds.min.to_a,component.definition.bounds.max.to_a].map { |point| point.map { |value| value*25.4 } }
      end

      def target(component)
        raw = component.get_attribute(Reader::DICT,TARGET_KEY)
        raw ? Core.bounds!(JSON.parse(raw)) : bounds(component)
      end

      def remember(component,box)
        component.set_attribute(Reader::DICT,TARGET_KEY,JSON.generate(Core.bounds!(Core.copy_data(box))))
      end

      def candidates(component,normal)
        AssemblyContainers.members(component).select do |entity|
          axes = [entity.transformation.xaxis,entity.transformation.yaxis,entity.transformation.zaxis]
          axis = axes.each_index.max_by { |index| AssemblyMath.dot(axes[index].normalize.to_a,normal).abs }
          next false if AssemblyMath.dot(axes[axis].normalize.to_a,normal).abs<0.999999
          if entity.get_attribute(Reader::DICT,'trial',false)
            rule = Core.rule!(JSON.parse(entity.get_attribute(Reader::DICT,'rule_json')))
            !Array(rule.dig('formula_engine','envelope_policy','axes')).include?(axis)
          else
            !entity.attribute_dictionary('dynamic_attributes',false) && !entity.definition.attribute_dictionary('dynamic_attributes',false)
          end
        end
      end

      # Eligible fallback axes. Always try free member dimensions first.
      def changing_axes(entity,rule,before)
        after = Core.dimensions(bounds(entity))
        frames = [entity.transformation.xaxis,entity.transformation.yaxis,entity.transformation.zaxis]
        engine = rule['formula_engine']
        axes = Array(engine&.dig('envelope_policy','axes'))
        axes |= EnvelopePolicy.input_axes(engine['attribute_program'],engine['envelope_policy']) if engine
        axes.flat_map do |axis|
          next [] unless (after[axis]-before[axis]).abs>0.001
          3.times.select { |index| frames[axis].to_a[index].abs>0.000001 }
        end.uniq
      end

      def fit_axis(model,component,target,records,axis)
        error = Core.dimensions(target)[axis]-Core.dimensions(bounds(component))[axis]
        return if error.abs<=0.01
        normal = [0.0,0.0,0.0]; normal[axis] = 1.0
        choices = candidates(component,normal)
        sizes = choices.map { |entity| Assembly.projection(entity,normal).then { |low,high| high-low } }
        original_sizes = sizes.dup
        responses = choices.each_with_index.map do |entity,index|
          baseline = Core.dimensions(bounds(component))[axis]
          probe = [sizes[index]*0.001,0.5].max
          size = Assembly.projection(entity,normal).then { |low,high| high-low }
          Assembly.resize(entity,normal,size+probe)
          Assembly.solve_ordered(model,records)
          response = (Core.dimensions(bounds(component))[axis]-baseline)/probe
          if response.abs<0.00000001
            # An interior/non-driving probe has no part in the correction. Do
            # not leave its module enlarged when another freedom fits the frame.
            Assembly.resize(entity,normal,size)
            Assembly.solve_ordered(model,records)
            response = 0.0
          end
          response
        end
        error = Core.dimensions(target)[axis]-Core.dimensions(bounds(component))[axis]
        return if error.abs<=0.01
        sizes = choices.map { |entity| Assembly.projection(entity,normal).then { |low,high| high-low } }
        changes = AssemblyMath.envelope_correction(error,responses,sizes)
        choices.zip(sizes,changes).each do |entity,size,change|
          Assembly.resize(entity,normal,size+change) if change.abs>0.000001
        end
        Assembly.solve_ordered(model,records)
      rescue AssemblyMath::NoEnvelopeFreedom
        # Failed probes must not become the fallback geometry or the next input.
        choices.zip(original_sizes).each { |entity,size| Assembly.resize(entity,normal,size) }
        Assembly.solve_ordered(model,records)
        raise
      end

      def apply(model,targets,ordered,growth: {},fixed_scopes: [])
        targets.each do |scope,target|
          component = AssemblyContainers.wrapper(model,scope)
          construction = Core.copy_data(target)
          records = ordered.select { |record| record['scope']==scope }
          # Repeat copies are controlled by their source/layout, rather than
          # independent resize freedoms. Preserve that existing pipeline.
          next if records.any? { |record| record['mode']=='repeat' }
          4.times do
            break if Core.dimensions(bounds(component)).zip(Core.dimensions(target)).all? { |a,b| (a-b).abs<=0.01 }
            3.times do |axis|
              begin
                fit_axis(model,component,target,records,axis)
              rescue AssemblyMath::NoEnvelopeFreedom
                raise unless Array(growth[scope]).include?(axis) && !fixed_scopes.include?(scope)
                actual = bounds(component)
                2.times { |side| target[side][axis] = actual[side][axis] }
              end
            end
          end
          current = bounds(component)
          unless Core.dimensions(current).zip(Core.dimensions(target)).all? { |a,b| (a-b).abs<=0.02 }
            raise Core::Error,'Không thể giữ phủ bì cụm đồng thời với độ dày và các liên kết hiện tại.'
          end
          offset = AssemblyMath.sub(target[0],current[0])
          AssemblyContainers.members(component).each { |entity| Assembly.translate(entity,offset) }
          raise Core::Error,'Phủ bì cụm sau Scale không khớp yêu cầu.' unless Core.bounds_close?(bounds(component),target,0.02)
          remember(component,construction)
        end
      end
    end
  end
end

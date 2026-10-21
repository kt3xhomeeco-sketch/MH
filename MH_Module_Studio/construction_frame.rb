# encoding: UTF-8
require_relative 'plane_solver'
module MH
  module ModuleStudio
    # A DC's construction span can differ from its mesh union (overhanging tops,
    # inset backs). Accept cached spans only when every captured part verifies
    # them; fit explicit Scale targets through the same ATT, never guessed gaps.
    module ConstructionFrame
      extend self

      def metadata(snapshot)
        data=snapshot['construction_inputs'];return unless data
        unless data.is_a?(Hash) && data['version']==1 && data['axes']==[0,1,2] &&
               data['source']=='all_parts_verified_att_frame'
          raise Core::Error,'Khai báo hệ kích thước dựng ATT không hợp lệ.'
        end
        Core.bounds!(data['envelope'])
        raise Core::Error,'Kích thước dựng ATT phải dương.' unless Core.dimensions(data['envelope']).all?(&:positive?)
        data
      end

      def enable(snapshot)
        data=Core.copy_data(snapshot);return data if metadata(data)
        program=DCFormulas::Program.new(data)
        values=Core.formula_values(data,program.controls)
        original,=program.evaluate(values)
        return data if matches?(data,original)
        sizes=%w[lenx leny lenz].map { |key| Core.number(data.fetch('dc_inputs').fetch(key))*25.4 }
        return data unless sizes.all?(&:positive?)
        frame=[[0.0,0.0,0.0],sizes]
        candidate,=program.evaluate(values,frame)
        return data unless matches?(data,candidate)
        data['construction_inputs']={'version'=>1,'axes'=>[0,1,2],'envelope'=>frame,'source'=>'all_parts_verified_att_frame'}
        data
      rescue Core::Error,KeyError
        Core.copy_data(snapshot)
      end

      def matches?(snapshot,bounds)
        snapshot['parts'].all? { |part| Core.bounds_close?(part['bounds'],bounds.fetch(part['key'])) }
      end

      def inputs(current,snapshot)
        data=metadata(snapshot);return unless data
        return current['formula_envelope'] if current['formula_envelope']
        data['envelope'] if !current['parameter_values'] && matches?(current,snapshot['parts'].to_h { |part| [part['key'],part['bounds']] })
      end

      def fit(snapshot,current,values)
        data=metadata(snapshot);return unless data
        program=DCFormulas::Program.new(snapshot)
        frame=Core.copy_data(current['formula_envelope'] || data['envelope'])
        sizes=Core.dimensions(frame);wanted=Core.dimensions(current['envelope'])
        measure=lambda do |dimensions|
          box=[frame[0],3.times.map { |axis| frame[0][axis]+dimensions[axis] }]
          bounds,=program.evaluate(values,box,frozen_parts:current['parts'])
          Core.union(bounds.filter_map { |key,value| {'key'=>key,'bounds'=>value} if program.visibility[key]!=false })
        end
        6.times do
          actual=Core.dimensions(measure.call(sizes))
          break if actual.zip(wanted).all? { |a,b| (a-b).abs<=0.00001 }
          columns=3.times.map do |axis|
            probe=sizes.dup;probe[axis]+=1.0
            shifted=Core.dimensions(measure.call(probe))
            3.times.map { |other| shifted[other]-actual[other] }
          end
          equations=3.times.map do |axis|
            [3.times.to_h { |variable| [variable,columns[variable][axis]] },wanted[axis]-actual[axis],'Kích thước Scale từ công thức ATT']
          end
          delta=PlaneSolver.solve(equations,{0=>0.0,1=>0.0,2=>0.0})
          sizes=3.times.map { |axis| sizes[axis]+delta.fetch(axis) }
          raise Core::Error,'Kích thước Scale làm hệ dựng ATT không dương.' unless sizes.all?(&:positive?)
        end
        actual=measure.call(sizes)
        offset=3.times.map { |axis| current['envelope'][0][axis]-actual[0][axis] }
        result=[3.times.map { |axis| frame[0][axis]+offset[axis] },3.times.map { |axis| frame[0][axis]+offset[axis]+sizes[axis] }]
        bounds,=program.evaluate(values,result,frozen_parts:current['parts'])
        union=Core.union(bounds.map { |key,value| {'key'=>key,'bounds'=>value} })
        raise Core::Error,'Không khớp được phủ bì Scale với hệ dựng ATT.' unless Core.bounds_close?(union,current['envelope'],Core::ENVELOPE_TOLERANCE)
        result
      end
    end
  end
end

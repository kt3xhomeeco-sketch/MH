# encoding: UTF-8
module MH
  module ModuleStudio
    # Exact leaf-copy topology in data; native mutation belongs to CopyRuntime.
    module DCCopies
      extend self
      MAX_COPIES = 100

      def engine(bundle)
        bundle['kind']==RuleSystem::KIND ? bundle['formula_engine'] : bundle
      end

      def enabled?(bundle)
        engine(bundle)&.dig('attribute_program','copies_version')==1
      end

      def needed?(bundle,current,requested)
        return false unless enabled?(bundle)
        return false unless requested.is_a?(Hash)
        calculation = engine(bundle); snapshot = calculation['attribute_program']
        original = snapshot['parts'].map { |part| part['key'] }.sort
        return true unless current['parts'].map { |part| part['key'] }.sort==original
        inputs = values(calculation,current).merge(requested)
        expanded(snapshot,inputs,current['envelope'])[0]['parts'].map { |part| part['key'] }.sort!=original
      end

      def families(snapshot)
        nodes = snapshot.dig('dc_graph','nodes') || []
        parents = nodes.map { |node| DCVisibility.parent(node) }
        nodes.select { |node| node['part_key'] && !parents.include?(DCVisibility.id(node)) && !node['attributes']['_copies_formula'].to_s.strip.empty? }
             .group_by { |node| [DCVisibility.parent(node),node['attributes'].select { |key,_v| key.end_with?('_formula') }.sort] }.values.filter_map do |members|
          indices = members.map { |node| Core.number(node['attributes'].fetch('copy',0)) }
          next unless indices.uniq.length==indices.length && indices.sort==(0...members.length).to_a
          {'source'=>members[indices.index(0)],'members'=>members.sort_by { |node| Core.number(node['attributes'].fetch('copy',0)) }}
        end
      end

      def count!(value)
        value = Core.number(value)
        raise Core::Error,"Copies phải là số nguyên từ 0 đến #{MAX_COPIES} (không gồm bản gốc)." unless value==value.floor && value.between?(0,MAX_COPIES)
        value.to_i
      end

      def enable(snapshot)
        result = Core.copy_data(snapshot)
        groups = families(result)
        return result if groups.empty?
        program = DCFormulas::Program.new(result)
        program.evaluate(Core.formula_values(result,program.controls))
        return result unless groups.all? { |g| count!(program.attribute(DCVisibility.id(g['source']),'copies'))+1==g['members'].length }
        result['copies_version'] = 1
        result
      rescue Core::Error
        snapshot
      end

      def compatible!(snapshot,before,after)
        permitted = snapshot['copies_version']==1 ? families(snapshot).flat_map { |g| g['members'].map { |n| DCVisibility.id(n)+'!copies' } } : []
        permitted.each { |key| count!(after[key]) if after.key?(key) }
        DCVisibility.compatible_guards!(before.reject { |key,_v| permitted.include?(key) },after.reject { |key,_v| permitted.include?(key) },DCVisibility.enabled?(snapshot))
      end

      def input_keys(snapshot)
        DCFormulas::Program.new(snapshot).structural_dependencies('copies').keys
      end

      def count_keys(snapshot)
        keys = input_keys(snapshot)
        keys.length==1 ? keys : []
      end

      # Existing owned SKPs retain their ATT program, so upgrade in memory and
      # preserve the user's variable identity, symbols, values and display flags.
      def upgrade!(bundle)
        old = bundle['formula_engine']
        return unless old && old['attribute_program'] && !enabled?(bundle)
        return unless old['rules'].values.all? { |rule| rule['kind']=='dc_formula_rule' }
        snapshot = enable(old['attribute_program'])
        return unless snapshot['copies_version']==1
        fresh = Core.learn_module([snapshot])
        fresh['id'] = old['id']
        prior = bundle['parameters'].to_h { |row| [row['key'],row] }
        fresh['parameters'].each { |row| row['value'] = prior[row['key']]['value'] if prior[row['key']] }
        bundle['formula_engine'] = fresh
        bundle['parameters'] = Core.copy_data(fresh['parameters'])
        bundle['control_context'] = fresh['control_context']
        keys = count_keys(snapshot)
        bundle.fetch('parametric_variables',[]).each do |row|
          row['category'] = 'copies' if keys.include?(row['binding']) && row['unit'].empty? && %w[number information].include?(row['category'])
        end
      end

      def expanded(snapshot,values,envelope)
        data = Core.copy_data(snapshot)
        program = DCFormulas::Program.new(snapshot)
        program.prepare_values(values,envelope)
        source_parts = snapshot['parts'].to_h { |part| [part['key'],part] }
        sources = {}
        families(snapshot).each do |group|
          source = group['source']; count = count!(program.attribute(DCVisibility.id(source),'copies'))
          ids = group['members'].map { |node| DCVisibility.id(node) }
          keys = group['members'].map { |node| node['part_key'] }
          data['dc_graph']['nodes'].reject! { |node| ids.include?(DCVisibility.id(node)) }
          data['parts'].reject! { |part| keys.include?(part['key']) }
          (0..count).each do |index|
            node = Core.copy_data(group['members'][index] || source)
            part = Core.copy_data(source_parts.fetch(node['part_key']))
            if index>=group['members'].length
              node['id'] = "copies:#{DCVisibility.id(source)}:#{index}"
              node['parent_id'] = DCVisibility.parent(source)
              node['part_key'] = "copies:#{source['part_key']}:#{index}"
              node['name'] = source['name']+" · Copy #{index}"
              node['path'] = source['path'][0...-1]+[node['name']]
              part.merge!('key'=>node['part_key'],'name'=>node['name'])
            end
            node['attributes']['copy'] = index
            data['dc_graph']['nodes'] << node; data['parts'] << part
            sources[part['key']] = source['part_key']
          end
        end
        raise Core::Error,'Copies vượt giới hạn 600 chi tiết.' if data['parts'].length>Core::MAX_PARTS
        [data,sources]
      end

      def evaluated(snapshot,values,envelope,frozen: nil)
        data,sources = expanded(snapshot,values,envelope)
        program = DCFormulas::Program.new(data)
        frozen = (data['parts']+Array(frozen)).to_h { |part| [part['key'],part] }.values
        bounds,guards = program.evaluate(values,envelope,frozen_parts:frozen)
        parts = data['parts'].map { |part| part.merge('bounds'=>bounds.fetch(part['key']),'visible'=>program.visibility.fetch(part['key'])) }
        [parts,guards,program,data,sources]
      end

      def values(calculation,current)
        calculation['parameters'].select { |row| row['editable'] }.to_h do |row|
          key = row['key']; saved = current.fetch('parameter_values',{})
          value = if current.fetch('dc_inputs',{}).key?(key)
                    Core.number(current['dc_inputs'][key])*(row['unit']=='mm' ? 25.4 : 1.0)
                  elsif saved.key?(key)
                    saved[key]
                  else
                    row['value']
                  end
          [key,Core.number(value)]
        end
      end

      def plan(bundle,current,requested,absolute: false)
        Core.rule!(bundle); Core.snapshot!(current)
        own = bundle['kind']==RuleSystem::KIND
        if own && (bundle.fetch('constraints',[]).any? { |row| row['drive'] } || !bundle.fetch('part_formulas',{}).empty?)
          raise Core::Error,'Module Copies có quy tắc hình học sửa riêng; chưa kết hợp thay đổi số lượng với các quy tắc này.'
        end
        calculation = engine(bundle); snapshot = calculation.fetch('attribute_program')
        Core.check_dc_context!(calculation,current)
        previous = values(calculation,current)
        requested = Parametric.linked_requests(bundle,requested) if own
        raise Core::Error,'Có thông số không thuộc bộ quy tắc Copies.' unless requested.is_a?(Hash) && (requested.keys-previous.keys).empty?
        targets = previous.merge(requested.transform_values { |value| Core.number(value) })
        targets.each do |key,value|
          raise Core::Error,"#{key}: giá trị ngoài phạm vi." unless value.between?(*Core.parameter_range(calculation['rules'].fetch(key)))
        end
        base = Core.formula_values(snapshot,DCFormulas::Program.new(snapshot).controls)
        input_envelope = absolute ? current['envelope'] : EnvelopePolicy.inputs(current,snapshot,calculation['envelope_policy'])
        before,guards, = evaluated(snapshot,base.merge(previous),input_envelope,frozen:current['parts'])
        lookup = current['parts'].to_h { |part| [part['key'],part] }
        raise Core::Error,'Chi tiết Copies đã bị thay đổi; đọc lại module.' unless lookup.keys.sort==before.map { |part| part['key'] }.sort
        unless absolute
          before.each do |part|
            actual = lookup.fetch(part['key'])
            unless Core.bounds_close?(actual['bounds'],part['bounds']) && (actual['visible']!=false)==(part['visible']!=false)
              raise Core::Error,"#{actual['name']}: hình học hiện tại khác công thức Copies; đọc lại module."
            end
          end
        end
        after,new_guards,program,data,sources = evaluated(snapshot,base.merge(targets),input_envelope,frozen:current['parts'])
        shared = guards.keys & new_guards.keys
        compatible!(data,guards.slice(*shared),new_guards.slice(*shared))
        data['dc_graph']['nodes'].each do |node|
          next unless sources[node['part_key']] && !lookup.key?(node['part_key'])
          source_node = snapshot['dc_graph']['nodes'].find { |item| item['part_key']==sources[node['part_key']] }
          %w[rotx roty rotz].each do |key|
            next unless new_guards.key?(DCVisibility.id(node)+'!'+key)
            unless new_guards[DCVisibility.id(node)+'!'+key]==guards[DCVisibility.id(source_node)+'!'+key]
              raise Core::Error,'Copies mới có góc xoay khác mẫu; chưa hỗ trợ tạo bản sao xoay.'
            end
          end
        end
        changes = after.map do |part|
          old = lookup[part['key']]
          source = old || lookup.fetch(sources.fetch(part['key']))
          change = DCVisibility.part_change(source,part['bounds'],part['visible']!=false,[])
          change.merge(part).merge('old_bounds'=>source['bounds'],'old_visible'=>old ? old['visible']!=false : false,'changed'=>!old || change['changed'])
        end
        axes = EnvelopePolicy.input_axes(snapshot,calculation['envelope_policy'])
        drivers = EnvelopePolicy.thickness_parts(calculation)
        drivers.each_value { |keys| keys.concat(sources.filter_map { |key,source| key if keys.include?(source) }) }
        target_envelope = EnvelopePolicy.target(current['envelope'],changes,calculation['envelope_policy'],program,input_axes:axes,inputs:input_envelope,drivers:drivers)
        logical = Core.copy_data(target_envelope)
        axes.each { |axis| 2.times { |side| logical[side][axis] = input_envelope[side][axis] } }
        if absolute && axes.any? { |axis| 2.times.any? { |side| (target_envelope[side][axis]-current['envelope'][side][axis]).abs>Core::ENVELOPE_TOLERANCE } }
          raise Core::Error,'Kích thước Scale nhỏ hơn độ dày / chi tiết cố định. Đã hủy thao tác.'
        end
        Core.validate_geometry_plan!(changes,current,overlap_reference:snapshot['parts'],expected_envelope:target_envelope)
        added = changes.reject { |part| lookup.key?(part['key']) }.map { |part| {'key'=>part['key'],'source'=>sources.fetch(part['key']),'name'=>part['name']} }
        removed = lookup.keys-changes.map { |part| part['key'] }
        {'multi_parameter'=>true,'previous'=>previous,'target'=>targets,'parts'=>changes,'envelope'=>target_envelope,
          'formula_envelope'=>logical,
          'changed_count'=>changes.count { |part| part['changed'] }+removed.length,'visibility_capable'=>true,
          'visibility_updates'=>program.node_visibility,'copies_capable'=>true,'copy_add'=>added,'copy_remove'=>removed,
          'outside_sample_range'=>false,'combination_unverified'=>false,'copy_graph'=>data['dc_graph']}
      end
    end
  end
end

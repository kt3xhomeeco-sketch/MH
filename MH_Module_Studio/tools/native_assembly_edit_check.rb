# encoding: UTF-8
require_relative 'native_assembly_scale_check'

module MH
  module ModuleStudio
    module NativeAssemblyEditCheck
      extend self

      def valid(wrapper,expected)
        raise 'Aggregate envelope drifted' unless Core.bounds_close?(AssemblyEnvelope.bounds(wrapper),expected,0.02)
        Assembly.records(@model).select { |record| record['scope']==wrapper.persistent_id.to_s }.each { |record| Assembly.verify(@model,record) }
        AssemblyContainers.members(wrapper).each do |member|
          rule,values,current, = NativeDrawerCheck.current(member)
          raise 'Member geometry is not idempotent' unless Core.plan(rule,current,values)['changed_count'].zero?
        end
      end

      def compare_probes(wrapper,mirror: false,reverse: false)
        group = Assembly.records(@model).select { |record| record['scope']==wrapper.persistent_id.to_s }
        group.each { |record| record['a'],record['b'] = record['b'],record['a'] } if reverse
        entity = Assembly.root(@model,group.first['b'])
        if mirror
          @model.start_operation('MH QA mirror probe member',true)
          entity.transformation *= Geom::Transformation.scaling(-1,1,1)
          @model.commit_operation; @helper.reset
        end
        directions = AssemblyContacts.axes(@model,group,entity)
        raise 'Expected paired contact axes' if directions.empty?
        directions.each do |normal|
          baseline = AssemblyContacts.rows(@model,group)
          seed = AssemblyContacts.probe_seed(group,entity)
          raise 'Expected calculation-only probe support' unless seed
          size = Assembly.projection(entity,normal).then { |low,high| high-low }
          probe = [size*0.001,0.5].max
          predicted = AssemblyContacts.probe_rows(seed,normal,1+probe/size,baseline)
          @model.start_operation('MH QA verify virtual probe',true)
          Assembly.resize(entity,normal,size+probe)
          actual = AssemblyContacts.rows(@model,group)
          raise 'Virtual probe differs from native geometry' unless actual.zip(predicted).all? { |a,b| (a['delta']-b['delta']).abs<0.00001 }
          Assembly.resize(entity,normal,size)
          @model.commit_operation; @helper.reset
        end
      end

      def private_thickness(wrapper)
        member = AssemblyContainers.members(wrapper).find do |entity|
          rule, = NativeDrawerCheck.current(entity)
          Parametric.variables(rule).any? { |row| row['symbol']=='T2' }
        end
        raise 'Expected private T2' unless member
        expected = AssemblyEnvelope.bounds(wrapper)
        others = AssemblyContainers.members(wrapper).reject { |entity| entity==member }.to_h do |entity|
          [entity,entity.get_attribute(Reader::DICT,'parameter_values_json')]
        end
        [9,8].each do |value|
          rule,saved, = NativeDrawerCheck.current(member)
          rows = Parametric.variables(rule)
          rows.each { |row| row['value'] = saved.fetch(row['binding'],row['value']) if row['binding'] && row['formula'].empty? }
          rows.find { |row| row['symbol']=='T2' }['value'] = value
          edited = Parametric.edit_variables(rule,rows)
          Assembly.transact(@model,Assembly.records(@model),updates:[[
            {'root'=>member.persistent_id.to_s,'scope'=>wrapper.persistent_id.to_s},edited,Parametric.targets(edited)]])
          @helper.reset; valid(wrapper,expected)
          raise 'Private edit changed another member input' unless others.all? { |entity,values| entity.get_attribute(Reader::DICT,'parameter_values_json')==values }
        end
      end

      def run(expected_pid:,source_pid:)
        @model = Sketchup.active_model
        raise 'Pinned model 1 only' unless Process.pid==expected_pid && @model.title=='1' && !@model.active_path
        source = @model.find_entity_by_persistent_id(source_pid)
        raise 'Expected managed source' unless AssemblyContainers.managed?(source)
        @helper = NativeAssemblyScaleCheck; @helper.instance_variable_set(:@model,@model)
        roots = @model.entities.to_a; defs = @model.definitions.to_a; selected = @model.selection.to_a
        fingerprints = roots.select { |root| Assembly.container?(root) }.to_h { |root| [root,NativeDrawerCheck.fingerprint(root)] }
        report = {'checks'=>[],'ok'=>false}
        begin
          copy = @helper.clone_wrapper(source)
          expected = AssemblyEnvelope.bounds(copy)
          [20,18.6,17.6,30].each { |value| @helper.common(copy,value); valid(copy,expected) }
          report['checks'] << 'Repeated common T1 preserves all six aggregate bounds and contacts'
          private_thickness(copy)
          report['checks'] << 'Private T2 edits preserve the aggregate and other member values'
          @helper.failed_common_is_atomic(copy); valid(copy,expected)
          report['checks'] << 'Failed member edit rolls back the complete assembly'
          @helper.discard(copy)
          [[false,false],[true,false],[false,true],[true,true]].each do |mirror,reverse|
            copy = @helper.clone_wrapper(source)
            @model.start_operation('MH QA rotated probe wrapper',true)
            copy.transformation = Geom::Transformation.rotation(ORIGIN,Z_AXIS,30.degrees)*Geom::Transformation.scaling(-1,1,1)*copy.transformation
            @model.commit_operation; @helper.reset
            compare_probes(copy,mirror:mirror,reverse:reverse)
            report['checks'] << "Calculated face responses match native redraw on rotated wrapper; member mirror=#{mirror}, reverse=#{reverse}"
            @helper.discard(copy)
          end
          report['ok'] = true
        rescue StandardError => error
          report['error'] = [error.message,*error.backtrace.first(6)]
        ensure
          Assembly.instance_variable_set(:@busy,true)
          @model.start_operation('MH QA edit cleanup',true)
          added = @model.entities.to_a-roots; @model.entities.erase_entities(added) unless added.empty?
          loop do
            unused = (@model.definitions.to_a-defs).select { |definition| definition.instances.empty? }
            break if unused.empty?
            unused.each { |definition| @model.definitions.remove(definition) }
          end
          @model.selection.clear; @model.selection.add(selected.select(&:valid?)); @model.commit_operation
          Assembly.instance_variable_set(:@busy,false); @helper.reset
          report['originals_retained'] = roots==@model.entities.to_a && defs==@model.definitions.to_a && selected==@model.selection.to_a && fingerprints.all? { |root,sha| NativeDrawerCheck.fingerprint(root)==sha }
          report['ok'] &&= report['originals_retained']
          base = File.dirname(Panel.instance_method(:request).source_location.first)
          File.write(File.join(base,'outputs/assembly-edit-041/native.json'),JSON.pretty_generate(report))
        end
        report
      end
    end
  end
end

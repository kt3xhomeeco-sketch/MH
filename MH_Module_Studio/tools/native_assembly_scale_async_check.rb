# encoding: UTF-8
require_relative 'native_assembly_scale_check'

module MH
  module ModuleStudio
    module NativeAssemblyScaleAsyncCheck
      extend self

      def check(condition,message)
        raise message unless condition
        @report['checks'] << message
      end

      def later(&block)
        UI.start_timer(0.6,false) do
          begin
            raise 'Model changed during QA' unless Sketchup.active_model.equal?(@model) && !@model.active_path
            block.call
          rescue StandardError => error
            @report['error'] = [error.message,*error.backtrace.first(6)]
            finish
          end
        end
      end

      def start(expected_pid:,source_pid:)
        @model = Sketchup.active_model
        raise 'Pinned model 1 only' unless Process.pid==expected_pid && @model.title=='1' && !@model.active_path
        @base = File.dirname(Panel.instance_method(:request).source_location.first)
        @report = {'status'=>'running','ok'=>false,'checks'=>[]}; @finished = false
        @roots = @model.entities.to_a; @defs = @model.definitions.to_a; @selected = @model.selection.to_a
        @fingerprints = @roots.select { |root| Assembly.container?(root) }.to_h { |root| [root,NativeDrawerCheck.fingerprint(root)] }
        @helper = NativeAssemblyScaleCheck; @helper.instance_variable_set(:@model,@model)
        @copy = @helper.clone_wrapper(@model.find_entity_by_persistent_id(source_pid))
        @baseline = AssemblyEnvelope.bounds(@copy)
        @initial_values = AssemblyContainers.members(@copy).to_h { |member| [member.persistent_id,member.get_attribute(Reader::DICT,'parameter_values_json')] }
        write
        scale(0.8) do
          check(valid(@expected),'Actual observer shrinks aggregate to exact requested bounds and preserves all contacts')
          @scaled = AssemblyEnvelope.bounds(@copy)
          Sketchup.undo
          later do
            check(valid(@baseline),'One Undo restores pre-Scale aggregate and internal rules')
            Sketchup.send_action('editRedo:')
            later { after_redo_scale }
          end
        end
      rescue StandardError => error
        @report['error'] = [error.message,*error.backtrace.first(6)]
        finish
      end

      def scale(factor,&block)
        @model.start_operation('MH QA actual assembly Scale',true)
        @copy.transformation *= Geom::Transformation.scaling(factor,factor,factor)
        frame = Frames.scale_frame(@copy.transformation.to_a)
        @expected = Frames.box(Frames.corners(AssemblyEnvelope.bounds(@copy)).map { |point| 3.times.map { |axis| point[axis]*frame[axis*5] } })
        @model.commit_operation
        later(&block)
      end

      def valid(expected = nil,thickness: nil)
        return false if expected && !Core.bounds_close?(AssemblyEnvelope.bounds(@copy),expected,0.02)
        return false unless Assembly.records(@model).select { |record| record['scope']==@copy.persistent_id.to_s }.all? { |record| Assembly.verify(@model,record); true }
        AssemblyContainers.members(@copy).all? do |member|
          rule,values,current, = NativeDrawerCheck.current(member)
          row = Parametric.variables(rule).find { |variable| variable['symbol']=='T1' }
          Core.plan(rule,current,values)['changed_count'].zero? && (!thickness || (values.fetch(row['binding'])-thickness).abs<0.000001)
        end
      end

      def after_redo_scale
        check(valid(@scaled),'Queued Redo restores repaired Scale without another geometry change')
        @helper.common(@copy,20)
        check(valid(@scaled,thickness:20),'Common T1=20 updates both members while preserving the complete aggregate envelope')
        Sketchup.undo
        later do
          check(valid(@scaled) && AssemblyContainers.members(@copy).all? { |member| member.get_attribute(Reader::DICT,'parameter_values_json')==@initial_values[member.persistent_id] },'One Undo restores both shared thickness values, aggregate envelope and all dependent geometry')
          Sketchup.send_action('editRedo:')
          later do
            check(valid(@scaled,thickness:20),'Queued Redo restores both common thickness values, fixed aggregate envelope and valid contacts')
            scale(1.25) do
              check(valid(@expected,thickness:20),'Actual enlarged Scale after shared thickness edit preserves thickness and requested aggregate bounds')
              unrelated_scale
            end
          end
        end
      end

      def unrelated_scale
        member = AssemblyContainers.members(@copy).find { |item| item.name.include?('Tu Bep') }
        @model.start_operation('MH QA independent pending Scale',true)
        external = @model.entities.add_instance(member.definition,member.transformation)
        @helper.copy_attributes(member,external); Runtime.private_tree(external)
        external.transform!(Geom::Transformation.translation([5000,0,0]))
        @model.commit_operation
        rule,values,current, = NativeDrawerCheck.current(external)
        factors = [1.1,1.0,1.0]
        expected = ScalePlan.plan(rule,ScalePlan.scaled_snapshot(current,factors),values)['envelope']
        @model.start_operation('MH QA queue external Scale',true)
        external.transformation *= Geom::Transformation.scaling(*factors)
        @model.commit_operation
        jobs = AssemblyContainers.members(@copy).map do |entity|
          own,saved, = NativeDrawerCheck.current(entity)
          rows = Parametric.variables(own)
          rows.each { |row| row['value'] = saved.fetch(row['binding'],row['value']) if row['binding'] && row['formula'].empty? }
          rows.find { |row| row['symbol']=='T1' }['value'] = 21
          edited = Parametric.edit_variables(own,rows)
          [{'root'=>entity.persistent_id.to_s,'scope'=>@copy.persistent_id.to_s},edited,Parametric.targets(edited)]
        end
        aggregate = AssemblyEnvelope.bounds(@copy)
        Assembly.transact(@model,Assembly.records(@model),updates:jobs)
        later do
          loaded,saved,actual, = NativeDrawerCheck.current(external)
          check(Core.bounds_close?(actual['envelope'],expected,0.02) && Core.plan(loaded,actual,saved)['changed_count'].zero?,
            'Acknowledging repaired assembly members preserves unrelated pending native Scale reconstruction')
          check(valid(aggregate,thickness:21),'Assembly envelope and contacts remain valid after unrelated Scale completes')
          @report['ok'] = true
          finish
        end
      end

      def finish
        return if @finished
        @finished = true
        Assembly.instance_variable_set(:@busy,true)
        @model.start_operation('MH QA async assembly cleanup',true)
        added = @model.entities.to_a-@roots; @model.entities.erase_entities(added) unless added.empty?
        loop do
          unused = (@model.definitions.to_a-@defs).select { |definition| definition.instances.empty? }
          break if unused.empty?
          unused.each { |definition| @model.definitions.remove(definition) }
        end
        @model.selection.clear; @model.selection.add(@selected.select(&:valid?))
        @model.commit_operation
        Assembly.instance_variable_set(:@busy,false); @helper.reset
        @report['originals_retained'] = @roots==@model.entities.to_a && @defs==@model.definitions.to_a && @selected==@model.selection.to_a && @fingerprints.all? { |root,sha| NativeDrawerCheck.fingerprint(root)==sha }
        @report['ok'] &&= @report['originals_retained']; @report['status'] = 'complete'; write
      end

      def write
        File.write(File.join(@base,'outputs/assembly-scale-040/async.json'),JSON.pretty_generate(@report))
      end
    end
  end
end

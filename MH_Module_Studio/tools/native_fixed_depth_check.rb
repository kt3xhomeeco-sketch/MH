# encoding: UTF-8
require_relative 'native_assembly_scale_check'

module MH
  module ModuleStudio
    # Live regression on private copies of the selected cabinet/door/plinth.
    # Requiring this file never edits a model.
    module NativeFixedDepthCheck
      extend self

      def check(value,label)
        raise label unless value
        @report['checks'] << label
      end

      def reset
        Assembly.watch(@model).reset; ScaleRedraw.watch(@model).reset
      end

      def verify(root,value,expected)
        check(Core.bounds_close?(AssemblyEnvelope.bounds(root),expected,0.02),"T1 #{value}: aggregate bounds and anchor stay fixed")
        count = 0
        AssemblyContainers.members(root).each do |member|
          rule,saved,current, = NativeDrawerCheck.current(member)
          key = Parametric.variables(rule).find { |row| row['symbol']=='T1' }.fetch('binding')
          check((saved[key]-value).abs<0.000001,"#{member.name}: T1 remains #{value}")
          drivers = rule.fetch('rules').fetch(key).fetch('parts').select { |part| part['driver'] }
          drivers.each do |driver|
            part = current['parts'].find { |entry| entry['key']==driver['key'] }
            next unless part && part['visible']!=false
            physical = Core.dimensions(part['bounds'])[driver['thickness_axis']]
            raise "#{member.name} / #{part['name']}: actual T=#{physical}, expected #{value}" unless (physical-value).abs<0.001
            count += 1
          end
          check(Core.plan(rule,current,saved)['changed_count'].zero?,"#{member.name}: ATT remains idempotent")
        end
        check(count>=10,"T1 #{value}: at least ten real panel thicknesses measure correctly")
        links = Assembly.records(@model).select { |row| row['scope']==root.persistent_id.to_s }
        check(links.length==8,'All eight original assembly links retained')
        links.each { |row| Assembly.verify(@model,row) }
      end

      def options_change(root,value)
        window = ModuleOptions.new
        fake = Object.new
        fake.define_singleton_method(:execute_script) { |_code| nil }
        fake.define_singleton_method(:set_size) { |_width,_height| nil }
        window.instance_variable_set(:@dialog,fake)
        window.define_singleton_method(:thumbnail) { |_root| nil }
        @model.selection.clear; @model.selection.add(root)
        window.refresh
        row = window.instance_variable_get(:@display_rows).find { |entry| entry['id']=='common:T1' }
        check(row && row['editable'] && row['targets'].length==3,'Options common T1 targets cabinet, double door and plinth')
        window.request('action'=>'change','root_pid'=>root.persistent_id.to_s,'token'=>window.instance_variable_get(:@token),'variable_id'=>row['id'],'value'=>value)
      ensure
        window.instance_variable_set(:@dialog,nil) if window
        window&.detach
      end

      def fallback(source)
        member = AssemblyContainers.members(source).find { |entity| entity.name.include?('Canh doi') }
        @model.start_operation('MH QA046 Derived-only fallback',true)
        door = @model.entities.add_instance(member.definition,member.transformation)
        NativeAssemblyScaleCheck.copy_attributes(member,door)
        Runtime.private_tree(door)
        wrapper = @model.entities.add_group([door]).to_component
        wrapper.set_attribute(Reader::DICT,AssemblyContainers::FLAG,true)
        @owned << wrapper
        @model.commit_operation; reset
        door = AssemblyContainers.members(wrapper).first
        rule,saved, = NativeDrawerCheck.current(door)
        row = Parametric.variables(rule).find { |entry| entry['symbol']=='T1' }
        before = Core.dimensions(AssemblyEnvelope.bounds(wrapper))
        anchor = {'root'=>door.persistent_id.to_s,'scope'=>wrapper.persistent_id.to_s}
        Assembly.transact(@model,Assembly.records(@model),updates:[[anchor,rule,saved.merge(row['binding']=>80)]])
        current = Core.dimensions(AssemblyEnvelope.bounds(wrapper))
        check((current[1]-80).abs<0.001 && [0,2].all? { |axis| (current[axis]-before[axis]).abs<0.001 },'Derived-only assembly expands only its proven thickness axis when no depth freedom exists')
      end

      def cleanup
        @model.start_operation('MH QA046 Cleanup',true)
        @owned.reverse_each { |root| root.erase! if root.valid? }
        @raw ? @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,@raw) : @model.delete_attribute(Reader::DICT,AssemblyContainers::KEY)
        40.times do
          empty = (@model.definitions.to_a-@definitions).select { |definition| definition.instances.empty? }
          break if empty.empty?
          empty.each { |definition| @model.definitions.remove(definition) }
        end
        @model.selection.clear; @model.selection.add(@selection.select(&:valid?))
        @model.commit_operation; reset
        check(@originals.all? { |root,hash| root.valid? && NativeDrawerCheck.fingerprint(root)==hash },'Every original user module and assembly remains unchanged')
      end

      def setup(expected_pid:,source_pid:)
        @model = Sketchup.active_model
        raise 'Wrong session/context' unless Process.pid==expected_pid && @model.title.empty? && @model.active_path.nil?
        source = @model.find_entity_by_persistent_id(source_pid)
        raise 'Expected selected linked assembly' unless source==@model.selection.first && AssemblyContainers.managed?(source)
        @report = {'ok'=>false,'checks'=>[],'timings'=>[]}; @owned = []
        @raw = @model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        @selection = @model.selection.to_a; @definitions = @model.definitions.to_a
        @originals = @model.entities.select { |root| Assembly.container?(root) }.to_h { |root| [root,NativeDrawerCheck.fingerprint(root)] }
        NativeAssemblyScaleCheck.instance_variable_set(:@model,@model)
        source
      end

      def run(expected_pid:,source_pid:)
        source = setup(expected_pid:expected_pid,source_pid:source_pid)
        begin
          clone = NativeAssemblyScaleCheck.clone_wrapper(source); @owned << clone
          frame = AssemblyEnvelope.bounds(clone)
          @report['initial_bounds'] = frame
          [40,18.6,30,80,200,17.6,30].each do |value|
            start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            NativeAssemblyScaleCheck.common(clone,value)
            @report['timings'] << {'T1'=>value,'ms'=>((Process.clock_gettime(Process::CLOCK_MONOTONIC)-start)*1000).round}
            verify(clone,value,frame)
          end
          options_change(clone,40)
          verify(clone,40,frame)
          NativeAssemblyScaleCheck.failed_common_is_atomic(clone)
          verify(clone,40,frame)
          check(true,'Invalid later member update rolls back all earlier member changes')
          [[1,1.1,1],[1,0.9,1],[1.1,1,1]].each do |factors|
            NativeAssemblyScaleCheck.scale(clone,factors)
            scaled = AssemblyEnvelope.bounds(clone)
            NativeAssemblyScaleCheck.common(clone,30)
            verify(clone,30,scaled)
            check(true,"Explicit Scale #{factors.inspect} remains the new fixed target during later thickness edits")
          end
          fallback(source)
          @report['ok'] = true
        rescue StandardError => detail
          @report['error'] = [detail.message,*detail.backtrace.first(7)]
        ensure
          cleanup
        end
        @report
      end

      def finish_undo
        cleanup
        File.write(@undo_output,JSON.pretty_generate(@report))
      end

      def undo_stage
        Sketchup.undo
        UI.start_timer(0.25,false) do
          begin
            check(NativeDrawerCheck.fingerprint(@undo_root)==@undo_before,'One Undo restores every original panel, value, link and transform')
            verify(@undo_root,30,@undo_box)
            Sketchup.send_action('editRedo:')
            UI.start_timer(0.25,false) do
              begin
                check(NativeDrawerCheck.fingerprint(@undo_root)==@undo_after,'One Redo restores the exact fixed-depth edit and stable instance IDs')
                verify(@undo_root,40,@undo_box)
                @report['ok'] = true
              rescue StandardError => detail
                @report['error'] = detail.message
              ensure
                finish_undo
              end
            end
          rescue StandardError => detail
            @report['error'] = detail.message
            finish_undo
          end
        end
      end

      def start_undo(expected_pid:,source_pid:,output:)
        source = setup(expected_pid:expected_pid,source_pid:source_pid)
        @undo_output = output
        @undo_root = NativeAssemblyScaleCheck.clone_wrapper(source); @owned << @undo_root
        @undo_box = AssemblyEnvelope.bounds(@undo_root)
        @undo_before = NativeDrawerCheck.fingerprint(@undo_root)
        NativeAssemblyScaleCheck.common(@undo_root,40)
        @undo_after = NativeDrawerCheck.fingerprint(@undo_root)
        verify(@undo_root,40,@undo_box)
        UI.start_timer(0.25,false) { undo_stage }
        {'scheduled'=>true}
      end
    end
  end
end

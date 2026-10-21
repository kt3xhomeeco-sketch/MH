# encoding: UTF-8
require_relative 'native_external_stretch_check'

module MH
  module ModuleStudio
    # Developer-only: the existing private-fixture geometry suite plus event-loop
    # latency, asynchronous Options T edits, and cancellation by native Undo.
    module NativeResponsiveUpdateCheck
      extend self
      def start
        raise 'QA already running' if @running
        @running=true;@steps=[];@jobs=[];@beats=[];@last_beat=clock;@was_pending=false
        @advance=UpdateWork.method(:advance);@finish=UpdateWork.method(:finish)
        @edit=NativeExternalStretchCheck.method(:edit_door_T)
        UpdateWork.define_singleton_method(:advance) { |job| NativeResponsiveUpdateCheck.advance(job) }
        UpdateWork.define_singleton_method(:finish) { |*args| NativeResponsiveUpdateCheck.job_finished(*args) }
        NativeExternalStretchCheck.define_singleton_method(:edit_door_T) { NativeResponsiveUpdateCheck.edit_T }
        @timer=UI.start_timer(0.01,true) { heartbeat }
        NativeExternalStretchCheck.start
      rescue StandardError
        restore
        raise
      end

      def clock
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def advance(job)
        started=clock
        @advance.call(job)
      ensure
        @steps << (clock-started)*1000
      end

      def job_finished(job,status,error)
        @jobs << job.slice(:key,:steps,:max_step_ms,:bytes).merge(status:status,error:error&.message,calculations:job[:cache].length)
        @finish.call(job,status,error)
      end

      def heartbeat
        model=Sketchup.active_model;now=clock;pending=UpdateWork.pending?(model)
        @beats << (now-@last_beat)*1000 if @was_pending
        @last_beat=now;@was_pending=pending
        return if NativeExternalStretchCheck.instance_variable_get(:@running)
        report=NativeExternalStretchCheck.instance_variable_get(:@report)
        result={geometry:report,steps:@steps,jobs:@jobs,heartbeats:@beats,
          max_callback_ms:@steps.max,max_heartbeat_gap_ms:@beats.max,heartbeat_count:@beats.length}
        path=File.join(File.dirname(__dir__),'outputs/update089')
        FileUtils.mkdir_p(path);File.write(File.join(path,'native.json'),JSON.pretty_generate(result))
        restore
      end

      def edit_T
        qa=NativeExternalStretchCheck;model=qa.instance_variable_get(:@model);door=qa.instance_variable_get(:@door)
        rule=JSON.parse(door.get_attribute(Reader::DICT,'rule_json'))
        row=Parametric.variables(rule).find { |entry| entry['binding']=='a0van' };raise 'Missing T variable' unless row
        id=door.persistent_id.to_s;anchor={'root'=>id}
        window=ModuleOptions.allocate;window.instance_variable_set(:@model,model);window.instance_variable_set(:@root,door)
        window.instance_variable_set(:@display_rows,[{'id'=>row['id'],'editable'=>true}])
        window.instance_variable_set(:@members,{id=>{'anchor'=>anchor,'rule'=>rule,'raw'=>door.get_attribute(Reader::DICT,'rule_json'),
          'values_raw'=>door.get_attribute(Reader::DICT,'parameter_values_json')}})
        complete=lambda do |status,error|
          raise error if error
          raise "Options #{status}" unless status==:done
          qa.exact('T edit keeps stretched total',Core.dimensions(qa.total_box)[1],qa.instance_variable_get(:@depth)+100)
          qa.exact('Door T changes exactly',qa.mesh_sizes(door)[1],20)
          host=qa.instance_variable_get(:@host);width=qa.mesh_sizes(host)[0]
          qa.stretch([host],0,-80)
          qa.later do
            qa.exact('Host width shrinks',qa.mesh_sizes(host)[0],width-80)
            qa.exact('Linked door follows current host faces',qa.mesh_sizes(door)[0],width-80)
            Assembly.records(model).each { |record| Assembly.verify(model,record) }
            qa.finish
          end
        rescue StandardError=>detail
          qa.fail_check(detail)
        end
        UpdateWork.submit(model,key: :options,complete:complete) { window.apply_changes([{'variable_id'=>row['id'],'value'=>20}]) }
      end

      def restore
        UI.stop_timer(@timer) if @timer
        # Remove wrappers instead of leaving singleton shadows of module methods.
        UpdateWork.singleton_class.remove_method(:advance) if @advance
        UpdateWork.singleton_class.remove_method(:finish) if @finish
        NativeExternalStretchCheck.singleton_class.remove_method(:edit_door_T) if @edit
        @timer=nil;@running=false
      end
    end
  end
end

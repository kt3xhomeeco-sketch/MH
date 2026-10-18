# encoding: UTF-8
require 'tmpdir'

module MH
  module ModuleStudio
    module NativeLibraryRefreshCheck
      extend self

      def start(output:)
        model=Sketchup.active_model
        before=signature(model)
        folder=Dir.mktmpdir('mh-library-refresh-')
        File.write(File.join(folder,'Old.skp'),'metadata fixture')
        File.write(File.join(folder,'Delete.skp'),'metadata fixture')
        own=Library.new
        own.config['root']=folder;own.refresh
        old_thumbnails=own.thumbnails
        original=own.catalog['entries'].to_h { |item| [item['id'],item['fingerprint']] }
        state={started:clock,changed:nil,gaps:[],last:clock,own:own,output:output,folder:folder,model:model,before:before,original:original,thumbnails:old_thumbnails}
        root=MH::ModuleStudio.library.config['root']
        started=clock
        catalog=File.directory?(root) ? LibraryCatalog.scan(root) : {'entries'=>[]}
        state[:benchmark]={entries:catalog['entries'].length,metadata_ms:(clock-started)*1000}
        state[:tick_ms]=[]
        state[:real_monitor]=LibraryMonitor.new
        state[:real_monitor].reset(root,catalog)
        state[:real_started]=clock
        original_poll=own.method(:poll_catalog)
        own.define_singleton_method(:poll_catalog) do
          started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
          original_poll.call
          state[:tick_ms] << (Process.clock_gettime(Process::CLOCK_MONOTONIC)-started)*1000
        end
        own.browser_visible=true
        state[:change_timer]=UI.start_timer(0.2,false) do
          File.rename(File.join(folder,'Old.skp'),File.join(folder,'Renamed.skp'))
          File.delete(File.join(folder,'Delete.skp'))
          FileUtils.mkdir_p(File.join(folder,'Sub'))
          File.write(File.join(folder,'Sub','Added.skp'),'metadata fixture')
          state[:changed]=clock
        end
        state[:heartbeat]=UI.start_timer(0.1,true) { tick(state) }
        {scheduled:true,pid:Process.pid,output:output}
      end

      def clock
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def signature(model)
        [model.guid,model.modified?,model.entities.length,model.selection.map { |entity| [entity.persistent_id,entity.bounds.min.to_a,entity.bounds.max.to_a] }]
      end

      def tick(state)
        now=clock;state[:gaps] << (now-state[:last])*1000;state[:last]=now
        unless state[:real_scan_ms]
          started=clock;state[:real_monitor].poll
          state[:tick_ms] << (clock-started)*1000
          state[:real_scan_ms]=(clock-state[:real_started])*1000 unless state[:real_monitor].instance_variable_get(:@scan)
        end
        own=state[:own]
        ids=own.catalog['entries'].map { |item| item['id'] }
        return unless (ids==['Renamed.skp','Sub/Added.skp'] && state[:real_scan_ms]) || now-state[:started]>12
        report={ok:ids==['Renamed.skp','Sub/Added.skp'],ids:ids,refresh_ms:state[:changed] && (now-state[:changed])*1000,max_ui_heartbeat_gap_ms:state[:gaps].max,benchmark:state[:benchmark]}
        report[:thumbnail_cache_retained]=own.thumbnails.equal?(state[:thumbnails])
        report[:real_incremental_scan_ms]=state[:real_scan_ms]
        report[:max_monitor_tick_ms]=state[:tick_ms].max
        report[:model_untouched]=signature(state[:model])==state[:before]
        report[:before]=state[:before];report[:after]=signature(state[:model])
        report[:ok] &&= report[:thumbnail_cache_retained] && report[:model_untouched]
        own.browser_visible=false
        report[:monitor_stopped]=own.instance_variable_get(:@monitor_timer).nil?
        report[:ok] &&= report[:monitor_stopped]
        UI.stop_timer(state[:heartbeat]);UI.stop_timer(state[:change_timer])
        File.write(state[:output],JSON.pretty_generate(report))
      rescue StandardError=>error
        state[:own].browser_visible=false
        UI.stop_timer(state[:heartbeat])
        File.write(state[:output],JSON.pretty_generate({ok:false,error:[error.message,*error.backtrace.first(6)]}))
      end
    end
  end
end

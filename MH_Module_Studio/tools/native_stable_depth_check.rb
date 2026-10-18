# encoding: UTF-8
require_relative 'native_fixed_depth_check'

module MH
  module ModuleStudio
    # Opt-in live QA. Always uses private copies of the selected assembly.
    module NativeStableDepthCheck
      extend self

      def run(expected_pid:,source_pid:)
        qa = NativeFixedDepthCheck
        source = qa.setup(expected_pid:expected_pid,source_pid:source_pid)
        report = qa.instance_variable_get(:@report)
        owned = qa.instance_variable_get(:@owned)
        begin
          clone = NativeAssemblyScaleCheck.clone_wrapper(source); owned << clone
          frame = AssemblyEnvelope.bounds(clone)
          frame[0][1] = frame[1][1]-600
          report['requested_bounds'] = Core.copy_data(frame)
          NativeAssemblyScaleCheck.common(clone,20,envelope_requests:{clone.persistent_id.to_s=>frame})
          qa.verify(clone,20,frame)
          [17.6,200,17.6,20,80,40,17.6].each do |value|
            started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            NativeAssemblyScaleCheck.common(clone,value)
            report['timings'] << {'T'=>value,'ms'=>((Process.clock_gettime(Process::CLOCK_MONOTONIC)-started)*1000).round,'depth'=>Core.dimensions(AssemblyEnvelope.bounds(clone))[1]}
            qa.verify(clone,value,frame)
          end
          qa.options_change(clone,20); qa.verify(clone,20,frame)
          NativeAssemblyScaleCheck.failed_common_is_atomic(clone)
          qa.verify(clone,20,frame)
          directory = Dir.mktmpdir('qa049-',File.join(File.dirname(Panel.instance_method(:request).source_location.first),'outputs'))
          report['directory'] = directory
          library = Library.new; library.config['root'] = directory; library.config['folder'] = ''
          path = File.join(directory,'Cụm 600 QA049.skp')
          library.export(clone,path); library.refresh
          imported = library.place(library.prepare(File.basename(path)),Geom::Point3d.new(0,0,0)); owned << imported
          qa.check(Core.bounds_close?(AssemblyEnvelope.target(imported),frame,0.02),'SKP roundtrip retains the independent 600 mm construction target')
          [200,17.6,20].each do |value|
            NativeAssemblyScaleCheck.common(imported,value); qa.verify(imported,value,frame)
          end
          NativeAssemblyScaleCheck.scale(clone,[1,1.1,1])
          scaled = AssemblyEnvelope.bounds(clone)
          qa.check((Core.dimensions(scaled)[1]-660).abs<0.02,'Explicit native Scale establishes a new 660 mm target')
          [200,17.6,20].each do |value|
            NativeAssemblyScaleCheck.common(clone,value); qa.verify(clone,value,scaled)
          end
          qa.fallback(source)
          door_cluster = owned.last
          remembered = AssemblyEnvelope.target(door_cluster)
          [200,17.6,20].each do |value|
            member = AssemblyContainers.members(door_cluster).first
            rule,values, = NativeDrawerCheck.current(member)
            row = Parametric.variables(rule).find { |entry| entry['symbol']=='T1' }
            anchor = {'root'=>member.persistent_id.to_s,'scope'=>door_cluster.persistent_id.to_s}
            Assembly.transact(member.model,Assembly.records(member.model),updates:[[anchor,rule,values.merge(row['binding']=>value)]])
            qa.check((Core.dimensions(AssemblyEnvelope.bounds(door_cluster))[1]-value).abs<0.02,'Derived-only cluster follows physical T='+value.to_s+' when no resize freedom exists')
            qa.check(Core.bounds_close?(AssemblyEnvelope.target(door_cluster),remembered,0.001),'Fallback does not overwrite the construction target')
            next unless value==200
            fallback_path = File.join(directory,'Tấm 200 QA049.skp')
            library.export(door_cluster,fallback_path); library.refresh
            returned = library.place(library.prepare(File.basename(fallback_path)),Geom::Point3d.new(0,0,0)); owned << returned
            qa.check(Core.bounds_close?(AssemblyEnvelope.target(returned),remembered,0.001),'Oversized fallback SKP retains the smaller construction target')
            child = AssemblyContainers.members(returned).first
            rr,vv, = NativeDrawerCheck.current(child)
            binding = Parametric.variables(rr).find { |entry| entry['symbol']=='T1' }['binding']
            ref = {'root'=>child.persistent_id.to_s,'scope'=>returned.persistent_id.to_s}
            Assembly.transact(child.model,Assembly.records(child.model),updates:[[ref,rr,vv.merge(binding=>17.6)]])
            qa.check((Core.dimensions(AssemblyEnvelope.bounds(returned))[1]-17.6).abs<0.001,'Reimported fallback can shrink back to T17.6')
          end
          report['ok'] = true
        rescue StandardError=>detail
          report['error'] = [detail.message,*detail.backtrace.first(8)]
        ensure
          qa.cleanup
        end
        report
      end
    end
  end
end

# encoding: UTF-8
require_relative 'convert_dc_library'
require_relative 'native_drawer_check'

module MH
  module ModuleStudio
    module UpgradeConditionalLibrary
      extend self

      def start(expected_pid:,paths: nil,output: 'conditional-038')
        raise 'Pinned Untitled only' unless Process.pid==expected_pid && Sketchup.active_model.title.empty?
        @base = File.dirname(Panel.instance_method(:request).source_location.first)
        raise 'Unknown audit directory' unless %w[conditional-038 cabinet-039].include?(output)
        @output = File.join(@base,'outputs',output)
        FileUtils.mkdir_p(@output)
        @model = Sketchup.active_model
        @roots = @model.entities.to_a; @defs = @model.definitions.to_a; @selection = @model.selection.to_a
        @originals = @roots.select { |root| Assembly.container?(root) }.to_h { |root| [root,NativeDrawerCheck.fingerprint(root)] }
        @prior = JSON.parse(File.read(File.join(LibraryConversion::DESTINATION,'.conversion/report.json'),encoding:'UTF-8'))
        @tasks = paths ? @prior['files'].select { |row| paths.include?(row['relative']) } : @prior['files']
        File.write(File.join(@output,'report-before.json'),JSON.pretty_generate(@prior))
        @hashes = @prior['files'].to_h { |row| [row['relative'],row['source_sha256']] }
        @entries = LibraryCatalog.scan(LibraryConversion::DESTINATION)['entries']
        @by_hash = @entries.group_by { |entry| Digest::SHA256.file(entry['path']).hexdigest }
        @backup = File.join(LibraryConversion::DESTINATION,'.conversion',"upgrade-038-#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}")
        FileUtils.mkdir_p(@backup)
        @converter = LibraryConversion.new(allow_current_model:true)
        @report = {'status'=>'running','total'=>@tasks.length,'files'=>[],'backup'=>@backup}
        write
        @timer = UI.start_timer(0.15,true) { tick }
      end

      def verify(path,row)
        library = Library.new
        library.instance_variable_get(:@config)['root'] = File.dirname(path); library.refresh
        data = library.prepare(File.basename(path))
        @model.start_operation('MH Verify upgraded library SKP',true)
        operation = true
        root = library.build_instance(data,Geom::Transformation.new)
        rule,values,snapshot, = NativeDrawerCheck.current(root)
        raise 'Fresh import is not idempotent' unless Core.plan(rule,snapshot,values)['changed_count'].zero?
        candidates = Parametric.variables(rule).select { |variable| variable['binding'] }.map { |variable| variable['binding'] }
        verified = nil
        candidates.each do |key|
          next unless rule['parameters'].any? { |p| p['key']==key && p['editable'] }
          [values[key]+0.1,values[key]-0.1,rule.dig('formula_engine','rules',key,'probe_value')].compact.uniq.each do |value|
            begin
              plan = Core.plan(rule,snapshot,{key=>value})
              next if plan['changed_count'].zero?
            rescue Core::Error
              next
            end
            Runtime.apply_trial_update(root,rule,{key=>value})
            verified = {'key'=>key,'value'=>value}
            break
          end
          break if verified
        end
        raise 'No native parameter edit could be verified' unless verified
        row.merge!('native_reimport_verified'=>true,'native_parameter_edit'=>verified)
      ensure
        @model.abort_operation if operation
      end

      def resume(expected_pid:)
        raise 'No stopped upgrade in pinned model' unless Process.pid==expected_pid && @report['status']=='stopped' && Sketchup.active_model.equal?(@model)
        @report['resumed_errors'] ||= []
        @report['resumed_errors'] << @report.delete('error')
        @report['status'] = 'running'
        write
        @timer = UI.start_timer(0.15,true) { tick }
      end

      def upgrade(prior)
        name = prior['relative']
        if prior['error'].to_s.match?(/dadx/i) || name.match?(/(?:tấm|tam).*cong/i)
          return {'relative'=>name,'action'=>'skipped_curved','result'=>prior}
        end
        source = File.join(LibraryConversion::SOURCE,name)
        raise 'Source changed since report' unless Digest::SHA256.file(source).hexdigest==@hashes.fetch(name)
        target = File.join(LibraryConversion::DESTINATION,name)
        saved = nil
        if prior['status']=='converted'
          matches = @by_hash.fetch(prior['output_sha256'],[])
          return {'relative'=>name,'action'=>'skipped_modified','result'=>prior} unless matches.length==1
          target = matches.first['path']
          raise 'Target outside Library' unless LibraryCatalog.inside?(LibraryConversion::DESTINATION,target)
          saved = File.join(@backup,matches.first['id'])
          FileUtils.mkdir_p(File.dirname(saved))
          FileUtils.cp(target,saved)
          raise 'Backup hash mismatch' unless Digest::SHA256.file(saved).hexdigest==prior['output_sha256']
          File.delete(target)
        end
        @report['phase'] = 'convert'; write
        row = saved ? @converter.convert(source,target_path:target) : @converter.convert(source)
        if row['status']=='converted'
          begin
            @report['phase'] = 'native_reimport_edit'; write
            verify(target,row)
            return {'relative'=>name,'action'=>saved ? 'upgraded' : 'converted_new','target'=>target,'result'=>row}
          rescue StandardError => error
            row = row.merge('status'=>'failed','error'=>"Native verification: #{error.message}")
          end
        end
        if saved
          quarantine(target,name) if File.file?(target)
          FileUtils.cp(saved,target)
          raise 'Restore hash mismatch' unless Digest::SHA256.file(target).hexdigest==prior['output_sha256']
          {'relative'=>name,'action'=>'retained_old','diagnostic'=>row['error'],'result'=>prior}
        else
          quarantine(target,name) if row['status']=='failed' && File.file?(target)
          {'relative'=>name,'action'=>'failed','result'=>row}
        end
      rescue StandardError
        FileUtils.cp(saved,target) if saved && File.file?(saved)
        raise
      end

      def quarantine(target,name)
        rejected = File.join(@backup,'rejected',name)
        FileUtils.mkdir_p(File.dirname(rejected))
        File.rename(target,rejected)
      end

      def tick
        return if @busy
        @busy = true
        raise 'Model context changed' unless Sketchup.active_model.equal?(@model) && !@model.active_path
        prior = @tasks[@report['files'].length]
        unless prior
          UI.stop_timer(@timer)
          @report['status'] = 'complete'
          @report['source_hashes_verified'] = @hashes.all? { |name,sha| Digest::SHA256.file(File.join(LibraryConversion::SOURCE,name)).hexdigest==sha }
          @report['originals_retained'] = @originals.all? { |root,sha| NativeDrawerCheck.fingerprint(root)==sha }
          write
          return
        end
        @report['current'] = prior['relative']; @report['current_started'] = Time.now.utc.iso8601; write
        @report['files'] << upgrade(prior)
        raise 'User model changed during upgrade' unless @roots==@model.entities.to_a && @defs==@model.definitions.to_a && @selection==@model.selection.to_a
        write
      rescue StandardError => error
        UI.stop_timer(@timer)
        @report['status'] = 'stopped'; @report['error'] = [error.message,*error.backtrace.first(4)]
        write
      ensure
        @busy = false
      end

      def write
        @report['counts'] = @report['files'].map { |row| row['action'] }.tally
        File.write(File.join(@output,'library-upgrade.json'),JSON.pretty_generate(@report))
      end
    end
  end
end

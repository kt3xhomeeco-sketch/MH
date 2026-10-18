# encoding: UTF-8
require_relative 'convert_dc_library'

module MH
  module ModuleStudio
    module RetryDrawerLibrary
      extend self

      def start(expected_pid:, paths: nil)
        raise 'Pinned process only' unless Process.pid==expected_pid
        @base = File.dirname(Panel.instance_method(:request).source_location.first)
        @model = Sketchup.active_model
        old_path = File.join(LibraryConversion::DESTINATION,'.conversion','report.json')
        @previous = JSON.parse(File.read(old_path,encoding:'UTF-8'))
        @paths = @previous['files'].select do |row|
          row['status']=='failed' && row['relative'].match?(/QQ|ngăn kéo|ngan keo/i) && row['relative']!='1.QQ Ngan keo 1 tang 550.skp'
        end.map { |row| row['relative'] }
        @paths &= paths if paths
        @converter = LibraryConversion.new(paths:@paths,allow_current_model:true)
        @report = {'status'=>'running','total'=>@paths.length,'files'=>[],'pid'=>Process.pid}
        write
        @timer = UI.start_timer(0.2,true) { tick }
      end

      def write
        @report['converted'] = @report['files'].count { |row| row['status']=='converted' }
        @report['failed'] = @report['files'].count { |row| row['status']=='failed' }
        File.write(File.join(@base,'outputs/drawer-036/retry.json'),JSON.pretty_generate(@report))
      end

      def tick
        return if @working
        @working = true
        raise 'Model changed during conversion' unless Sketchup.active_model.equal?(@model) && @model.active_path.nil?
        name = @paths[@report['files'].length]
        unless name
          UI.stop_timer(@timer)
          @report['status'] = 'complete'
          write
          return
        end
        row = @converter.convert(File.join(LibraryConversion::SOURCE,name))
        @report['files'] << row
        write
        Sketchup.status_text = "MH ngăn kéo: #{@report['files'].length}/#{@paths.length} · #{@report['converted']} chuyển được"
      rescue StandardError => error
        UI.stop_timer(@timer)
        @report['status'] = 'stopped'; @report['error'] = error.message
        write
      ensure
        @working = false
      end
    end
  end
end

# encoding: UTF-8
require_relative 'dc_library_conversion'

module MH
  module ModuleStudio
    module LibraryConversionUI
      def conversion_setup
        @conversion_setup ||= {'source'=>'','destination'=>@config['root'],'update'=>false}
      end

      def conversion_state(message=nil,error:false)
        report=@conversion&.report
        {'setup'=>conversion_setup,'running'=>@conversion&.running? == true,
         'report'=>report && report.reject { |key,_| %w[files known_outputs].include?(key) }.merge('files'=>report['files'].last(100)),
         'message'=>message,'error'=>error}
      end

      def publish_conversion(message=nil,error:false)
        @publisher&.call('receiveLibraryConversion',conversion_state(message,error:error))
      end

      def conversion_request(data)
        action=data['action']
        if action=='library_conversion_cancel'
          @conversion&.cancel
          return publish_conversion
        end
        raise Core::Error,'Đợi chuyển đổi xong hoặc bấm Dừng.' if @conversion&.running?
        case action
        when 'library_conversion_ready'
          nil
        when 'library_conversion_update'
          conversion_setup['update']=data['update']==true
        when 'library_conversion_source','library_conversion_destination'
          key=action.end_with?('source') ? 'source' : 'destination'
          path=UI.select_directory(title:key=='source' ? 'Chọn folder DC nguồn' : 'Chọn folder Library đích',directory:conversion_setup[key])
          conversion_setup[key]=File.realpath(path).tr('\\','/') if path
        when 'library_conversion_start'
          conversion_setup['update']=data['update']==true
          @conversion=DCLibraryConversion.new(source:conversion_setup['source'],destination:conversion_setup['destination'],update:conversion_setup['update']) do |report|
            publish_conversion
            if %w[complete cancelled stopped].include?(report['status']) && !@config['root'].empty?
              refresh
              publish(nil,background:true)
            end
          end
          @conversion.start
          return
        when 'library_conversion_open'
          root=@conversion&.report&.fetch('destination',nil)
          raise Core::Error,'Chưa có kết quả chuyển đổi.' unless root && File.directory?(root)
          @config['root']=root;refresh;persist;update_monitor;publish
        else
          raise Core::Error,'Thao tác chuyển đổi không hỗ trợ.'
        end
        publish_conversion
      rescue StandardError=>error
        publish_conversion(error.message,error:true)
      end
    end
  end
end

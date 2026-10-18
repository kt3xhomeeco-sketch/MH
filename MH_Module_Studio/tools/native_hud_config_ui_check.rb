# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeHUDConfigUICheck
      extend self

      def run
        @report={'ok'=>false,'checks'=>[]}
        # Exercise the actual callback/controller/CEF loop without opening a
        # modal OS file picker or changing the user's saved configuration.
        test_library=Library.new
        test_library.define_singleton_method(:transfer_hud_config) do |action|
          raise Core::Error,'Config kiểm tra không hợp lệ.' if action=='import_config'
          nil
        end
        tool=LibraryHUD.new(test_library)
        tool.show_settings
        dialog=tool.instance_variable_get(:@settings)
        dialog.add_action_callback('qa_config') do |_context,raw|
          data=JSON.parse(raw)
          begin
            raise 'Settings buttons disabled after cancel/error' unless data['enabled']
            if data['step']=='cancel'
              @report['checks'] << 'Export cancel acknowledges and reenables both CEF buttons'
              dialog.execute_script("document.getElementById('import-config').click();setTimeout(()=>sketchup.qa_config(JSON.stringify({step:'error',enabled:!document.getElementById('import-config').disabled&&!document.getElementById('export-config').disabled,message:document.getElementById('status').textContent})),150);")
            else
              raise 'Error acknowledgement missing' unless data['message']=='Config kiểm tra không hợp lệ.'
              @report['checks'] << 'Import error acknowledges and reenables both CEF buttons'
              @report['ok']=true
              dialog.close
              save_report
            end
          rescue StandardError => error
            @report['error']=error.message
            dialog.close
            save_report
          end
        end
        UI.start_timer(0.5,false) do
          dialog.execute_script("document.getElementById('export-config').click();setTimeout(()=>sketchup.qa_config(JSON.stringify({step:'cancel',enabled:!document.getElementById('import-config').disabled&&!document.getElementById('export-config').disabled})),150);")
        end
        puts 'Native HUD Settings callback check scheduled.'
      end

      def save_report
        File.write(File.join(File.dirname(Panel.instance_method(:show).source_location.first),'outputs/native-ui-064.json'),JSON.pretty_generate(@report))
      end
    end
  end
end

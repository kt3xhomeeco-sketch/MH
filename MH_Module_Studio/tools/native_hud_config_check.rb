# encoding: UTF-8
require 'tmpdir'

module MH
  module ModuleStudio
    module NativeHUDConfigCheck
      extend self

      def run
        report={'checks'=>[],'ok'=>false}
        prefs=%w[library_v1 hud_catalog_v1].to_h { |key| [key,Sketchup.read_default('MH_Module_Studio',key,'')] }
        original=Sketchup.active_model.entities.map(&:persistent_id)
        selected=Sketchup.active_model.selection.map(&:persistent_id)
        begin
          Dir.mktmpdir('hud064-') do |base|
            root=File.join(base,'Library');FileUtils.mkdir_p(File.join(root,'Tấm'))
            File.write(File.join(root,'Tấm/Đứng.skp'),'standing fixture');File.write(File.join(root,'Tấm/Ngang.skp'),'horizontal fixture')
            lib=Library.new;lib.config['root']=root;lib.refresh
            lib.save_settings('folder'=>'Tấm','folder_keys'=>{'Tấm'=>'D'},'hud_orders'=>{'Tấm'=>['Tấm/Đứng.skp','Tấm/Ngang.skp']},'hud_size'=>24,'hud_image_zoom'=>220)
            File.rename(File.join(root,'Tấm'),File.join(root,'Đổi tên tùy ý'))
            reopened=Library.new;reopened.refresh
            raise 'Folder rename lost selection/hotkey/order' unless reopened.config['folder']=='Đổi tên tùy ý' && reopened.config['folder_keys']=={'Đổi tên tùy ý'=>'D'} && reopened.config['hud_orders']['Đổi tên tùy ý'].first=='Đổi tên tùy ý/Đứng.skp'
            report['checks'] << 'Restart and folder rename retain slot 1 and assigned folder key'
            exported=File.join(base,'HUD.json');reopened.export_hud_config(exported)
            dest=File.join(base,'Other machine');FileUtils.cp_r(root,dest)
            File.rename(File.join(dest,'Đổi tên tùy ý'),File.join(dest,'Another name'))
            File.rename(File.join(dest,'Another name/Đứng.skp'),File.join(dest,'Another name/Standing.skp'))
            imported=Library.new;imported.config['root']=dest;imported.refresh;imported.import_hud_config(exported)
            raise 'Portable import mapping failed' unless imported.config['folder']=='Another name' && imported.config['folder_keys']=={'Another name'=>'D'} && imported.config['hud_orders']['Another name'].first=='Another name/Standing.skp'
            raise 'Display values lost' unless imported.config['hud_size']==24 && imported.config['hud_image_zoom']==220
            report['checks'] << 'JSON export/import finds renamed files in a copied library and restores display values'
            report['filesystem_identity']=LibraryCatalog.identity(File.stat(root))
          end
          raise 'Native entity selection changed' unless original==Sketchup.active_model.entities.map(&:persistent_id) && selected==Sketchup.active_model.selection.map(&:persistent_id)
          report['checks'] << 'Current model and selection unchanged'
          raise 'Parametric command missing' unless MH::ModuleStudio.instance_variable_get(:@parametric_command)
          report['checks'] << 'Parametric UI::Command registered for Preferences Shortcuts'
          report['ok']=true
        ensure
          prefs.each { |key,value| Sketchup.write_default('MH_Module_Studio',key,value) }
          File.write(File.join(File.dirname(Panel.instance_method(:show).source_location.first),'outputs/native-064.json'),JSON.pretty_generate(report))
        end
        puts JSON.generate(report)
      end
    end
  end
end

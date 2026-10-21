# encoding: UTF-8
require_relative 'native_assembly_scale_check'

module MH
  module ModuleStudio
    module NativeNamesCheck
      extend self

      def check(value,message)
        raise message unless value
        @report['checks'] << message
      end

      def rename(panel,name,key:nil)
        snapshot = panel.instance_variable_get(:@snapshots).last
        panel.request('action'=>'rename_model','name'=>name,'part_key'=>key,'rule_id'=>panel.instance_variable_get(:@rule)['id'],
          'snapshot_id'=>snapshot['id'],'revision'=>panel.instance_variable_get(:@parametric_revision))
      end

      def save(panel)
        panel.request('action'=>'save_skp','rule_id'=>panel.instance_variable_get(:@rule)['id'],
          'snapshot_id'=>panel.instance_variable_get(:@snapshots).last['id'],'revision'=>panel.instance_variable_get(:@parametric_revision))
      end

      # Method-local closures deliberately avoid VBO's reused top-level eval
      # locals. The old developer reload relay must not survive on the new page.
      def reload_live(panel)
        old = panel.instance_variable_get(:@parametric_dialog)
        raise 'Parametric is closed' unless old&.visible?
        base = File.dirname(Panel.instance_method(:request).source_location.first)
        old.add_action_callback('request') do |_context,raw|
          data = JSON.parse(raw)
          if data['action']=='mh_names_capture'
            restore = data['payload']
            File.write(File.join(base,'outputs/draft-before-reload-050.json'),JSON.pretty_generate(restore))
            old.close
            fresh = UI::HtmlDialog.new(dialog_title:'MH Module Studio · Parametric',preferences_key:'MH_Module_Studio_Parametric',
              width:1200,height:850,min_width:850,min_height:600,resizable:true,style:UI::HtmlDialog::STYLE_DIALOG)
            panel.instance_variable_set(:@parametric_dialog,fresh)
            panel.instance_variable_set(:@parametric_ready,false)
            audit = {'ok'=>true,'pid'=>Process.pid,'dirty_captured'=>restore['dirty'],'names_captured'=>restore['names'].count { |row| row['value']!=row['original'] }}
            fresh.set_file(File.join(base,'ui/parametric.html'))
            fresh.add_action_callback('request') do |_ctx,packet_json|
              begin
                raise Core::Error,'Yêu cầu quá lớn.' if packet_json.to_s.bytesize>1024*1024
                packet = JSON.parse(packet_json)
                if packet['action']=='mh_names_verified'
                  audit['ui'] = packet['payload']
                  audit['ok'] = packet['payload']['title_editable'] && packet['payload']['save_enabled'] && packet['payload']['pending']==false
                  File.write(File.join(base,'outputs/reload-final-050.json'),JSON.pretty_generate(audit))
                  next
                end
                panel.request(packet)
                if packet['action']=='ready' && packet['surface']=='parametric' && restore
                  encoded = JSON.generate(JSON.generate(restore))
                  fresh.execute_script("(()=>{const old=JSON.parse(#{encoded});const same=old.ruleId===ruleId&&old.snapshotId===snapshotId;if(same){if(old.dirty){draft=old.draft;markDirty();renderVariables();}if(old.cellEdit){cellEdit=old.cellEdit;renderParts();}refreshButtons();for(const row of old.names){if(row.value===row.original)continue;const input=row.key===null?byId('module-title'):Array.from(document.querySelectorAll('[data-part-name]')).find(n=>n.dataset.partName===row.key);if(input)input.value=row.value;}}window.sketchup.request(JSON.stringify({action:'mh_names_verified',payload:{context_retained:same,dirty,title_editable:!byId('module-title').disabled,part_editors:document.querySelectorAll('[data-part-name]:not(:disabled)').length,save_enabled:!byId('save-skp').disabled,pending,notice:byId('notice').textContent}}));})();")
                  restore = nil
                end
              rescue StandardError=>error
                panel.instance_variable_set(:@message,error.message); panel.publish(error:true)
              end
            end
            fresh.set_on_closed { panel.instance_variable_set(:@parametric_dialog,nil) if panel.instance_variable_get(:@parametric_dialog).equal?(fresh) }
            panel.instance_variable_set(:@message,'Đã cập nhật đổi tên: Enter hoặc click ra ngoài để ghi tên; Lưu SKP để lưu vào file.')
            fresh.show
          else
            panel.request(data)
          end
        rescue StandardError=>error
          panel.instance_variable_set(:@message,error.message); panel.publish(error:true)
        end
        old.execute_script("(()=>{const source=state.snapshots?.at(-1);window.sketchup.request(JSON.stringify({action:'mh_names_capture',payload:{dirty,draft,ruleId,snapshotId,revision,cellEdit,names:[{key:null,value:byId('module-title').value,original:state.module_name||state.rule?.module_name||source?.dc_inputs?._name||source?.label||''},...Array.from(document.querySelectorAll('[data-part-name]')).map(n=>({key:n.dataset.partName,value:n.value,original:state.parametric_sheet?.parts.find(p=>p.key===n.dataset.partName)?.name}))]}}));})();")
        {'scheduled'=>true}
      end

      def run(expected_pid:,source_pid:)
        model = Sketchup.active_model
        source = Runtime.selected_root
        raise 'Wrong source/session' unless Process.pid==expected_pid && source.persistent_id==source_pid && model.active_path.nil?
        before = model.entities.select { |entity| Assembly.container?(entity) }.to_h { |entity| [entity,[NativeDrawerCheck.fingerprint(entity),entity.name,entity.definition.name]] }
        definitions = model.definitions.to_a; selected = model.selection.to_a; owned = []
        @report = {'ok'=>false,'checks'=>[]}
        base = File.dirname(Panel.instance_method(:request).source_location.first)
        directory = Dir.mktmpdir('qa050-',File.join(base,'outputs')); @report['directory'] = directory
        begin
          original_path = File.join(directory,'Nguồn DC QA050.skp')
          check(source.definition.save_copy(original_path),'Private source DC file written for the file-only editing case')
          original_hash = ModuleFile.signature(original_path)
          snapshot = ModuleFile.with_root(original_path) { |root| Reader.live(root,label:'File đang sửa',parameter:nil).first }
          rule = StudioCalculation.build_system([snapshot])
          panel = Panel.new
          panel.instance_variable_set(:@rule,rule); panel.instance_variable_set(:@snapshots,[snapshot]); panel.instance_variable_set(:@module_name,'File đang sửa')
          panel.instance_variable_set(:@source_file,original_path); panel.instance_variable_set(:@source_signature,original_hash)
          fake = Object.new; states = []
          fake.define_singleton_method(:execute_script) { |code| states << JSON.parse(JSON.parse(code[/JSON.parse\((.*)\)\);/,1])) }
          panel.instance_variable_set(:@parametric_dialog,fake)
          key = snapshot['parts'].first['key']; snapshot_id = snapshot['id']
          rename(panel,'Chi tiết từ file',key:key)
          check(states.last['module_name']=='File đang sửa' && states.last.dig('parametric_sheet','parts').first['name']=='Chi tiết từ file','File-only detail rename keeps its module title and a usable sheet')
          check(panel.instance_variable_get(:@snapshots).last['id']==snapshot_id,'Rename preserves snapshot identity instead of replacing the document')
          rename(panel,'Module từ file QA050')
          save(panel)
          saved_path = File.join(directory,'Module từ file QA050.skp')
          check(File.file?(saved_path) && ModuleFile.signature(original_path)==original_hash,'Renamed file saves under its module name and retains the original DC file')
          data = ModuleFile.read(saved_path)
          check(data['name']=='Module từ file QA050' && data['snapshot']['parts'].any? { |part| part['name']=='Chi tiết từ file' },'Reopened SKP retains both module and detail names')
          check(Core.plan(data['rule'],data['snapshot'],data['values'])['changed_count'].zero?,'Renamed file formulas remain usable after save')
          stale = File.join(directory,'Must not exist.skp')
          begin
            ModuleFile.save(stale,data['rule'],data['snapshot'],source_path:original_path,source_expected:'stale')
            raise 'Changed source signature accepted'
          rescue Core::Error
            check(!File.file?(stale),'Stale source signature rejects before creating a renamed file')
          end
          Runtime.create_model(snapshot,rule,Parametric.targets(rule)); root = Runtime.selected_root; owned << root
          panel = Panel.new; panel.capture_parametric_root(root); panel.instance_variable_set(:@parametric_dialog,fake)
          title = panel.instance_variable_get(:@module_name)
          rename(panel,'Chi tiết model QA050',key:key)
          check(states.last['module_name']==title,'Owned detail rename preserves the displayed parent name')
          rename(panel,'Module model QA050')
          panel.instance_variable_set(:@source_file,File.join(directory,'Module model QA050.skp'))
          save(panel)
          owned_path = panel.instance_variable_get(:@source_file)
          check(File.file?(owned_path) && root.name=='Module model QA050','Owned module title changes and saves directly through the Parametric controller')
          library = Library.new; library.config['root']=directory; library.config['folder']=''; library.refresh
          returned = library.place(library.prepare(File.basename(owned_path)),Geom::Point3d.new(0,0,0)); owned << returned
          rr,vv,ss, = NativeDrawerCheck.current(returned)
          check(returned.name=='Module model QA050' && ss['parts'].any? { |part| part['name']=='Chi tiết model QA050' },'Owned SKP reimport keeps the edited names')
          binding = rr['parameters'].find { |param| param['editable'] }['key']
          Runtime.update_trial(returned,rr,vv.merge(binding=>80))
          rr,vv,ss, = NativeDrawerCheck.current(returned)
          check(Core.plan(rr,ss,vv)['changed_count'].zero?,'Parameter editing at T80 works after rename, save and import')
          @report['ok'] = true
        rescue StandardError=>error
          @report['error'] = [error.message,*error.backtrace.first(8)]
        ensure
          model.start_operation('MH QA050 Cleanup',true)
          owned.reverse_each { |root| root.erase! if root.valid? }
          40.times do
            empty=(model.definitions.to_a-definitions).select { |definition| definition.instances.empty? }; break if empty.empty?
            empty.each { |definition| model.definitions.remove(definition) }
          end
          model.selection.clear; model.selection.add(selected.select(&:valid?)); model.commit_operation
          Assembly.watch(model).reset; ScaleRedraw.watch(model).reset
          check(before.all? { |root,data| root.valid? && [NativeDrawerCheck.fingerprint(root),root.name,root.definition.name]==data },'Every user object and original name remains unchanged')
        end
        @report
      end
    end
  end
end

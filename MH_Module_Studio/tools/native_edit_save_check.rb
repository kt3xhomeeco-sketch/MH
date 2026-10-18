# encoding: UTF-8
require 'tmpdir'
require_relative 'native_assembly_scale_check'

module MH
  module ModuleStudio
    module NativeEditSaveCheck
      extend self

      def check(value,label)
        raise label unless value
        @report['checks'] << label
      end

      def reset
        Assembly.watch(@model).reset; ScaleRedraw.watch(@model).reset
      end

      def filler(root,t)
        rule,values,_snapshot, = NativeDrawerCheck.current(root)
        Runtime.update_trial(root,rule,values.merge('dodaytam'=>t))
        loaded,saved,current, = NativeDrawerCheck.current(root)
        parts=current['parts'].to_h { |part| [part['key'],part] }
        check((Core.dimensions(parts['sp14_xương nẹp']['bounds'])[1]-50).abs<0.001,"Filler T=#{t}: fixed backing length remains 50 mm")
        check((Core.dimensions(parts['sp14_xương nẹp']['bounds'])[0]-t).abs<0.001 && (Core.dimensions(parts['sp14_nẹp bù']['bounds'])[1]-t).abs<0.001,"Filler T=#{t}: both actual thickness axes match")
        check((Core.dimensions(current['envelope'])[1]-50-t).abs<0.001 && Core.plan(loaded,current,saved)['changed_count'].zero?,"Filler T=#{t}: output depth follows T+50 and remains editable")
        check((Core.dimensions(parts['sp14_nẹp bù']['bounds'])[0]-50).abs<0.001 && (Core.dimensions(current['envelope'])[0]-[50,t].max).abs<0.001,"Filler T=#{t}: fixed front width remains 50 mm while the thicker backing can pass its edge")
      end

      def run(expected_pid:,filler_pid:,assembly_pid:)
        @model=Sketchup.active_model
        raise 'Wrong native session' unless Process.pid==expected_pid && @model.title.empty? && @model.active_path.nil?
        source=@model.find_entity_by_persistent_id(filler_pid); assembly=@model.find_entity_by_persistent_id(assembly_pid)
        raise 'Pinned sources missing' unless source && AssemblyContainers.managed?(assembly)
        @report={'ok'=>false,'checks'=>[]}; @owned=[]
        originals=@model.entities.select { |root| Assembly.container?(root) }.to_h { |root| [root,NativeDrawerCheck.fingerprint(root)] }
        definitions=@model.definitions.to_a; selected=@model.selection.to_a
        raw=@model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        base=File.dirname(Panel.instance_method(:request).source_location.first)
        directory=Dir.mktmpdir('qa047-',File.join(base,'outputs')); @report['directory']=directory
        begin
          @model.start_operation('MH QA047 Private filler',true)
          copy=@model.entities.add_instance(source.definition,source.transformation)
          NativeAssemblyScaleCheck.copy_attributes(source,copy); Runtime.private_tree(copy)
          @owned << copy; @model.commit_operation; reset
          [20,80,200,18.6,80,20].each { |t| filler(copy,t) }
          rule,_values,_current,=NativeDrawerCheck.current(copy)
          anchor={'root'=>copy.persistent_id.to_s}
          rule=ParametricModel.rename(@model,anchor,rule,'Nẹp QA047')
          ParametricModel.rename(@model,anchor,rule,'Xương QA047',part_key:'sp14_xương nẹp')
          filler(copy,80)
          rule,values,current,=NativeDrawerCheck.current(copy)
          rule=Parametric.with_values(rule,values)
          path=File.join(directory,Parametric.filename(copy.name))
          result=ModuleFile.save(path,rule,current,source_root:copy)
          check(File.basename(result['path'])=='Nẹp QA047.skp','Module file uses the renamed module as its filename')
          library=Library.new; library.config['root']=directory; library.config['folder']=''; library.refresh
          imported=library.place(library.prepare('Nẹp QA047.skp'),Geom::Point3d.new(0,0,0)); @owned << imported
          _irule,ivalues,isnapshot,=NativeDrawerCheck.current(imported)
          check(imported.name=='Nẹp QA047' && isnapshot['parts'].any? { |p| p['name']=='Xương QA047' },'Saved/imported SKP retains module and detail names')
          check((ivalues['dodaytam']-80).abs<0.000001,'Library import retains the current saved T rather than old defaults')
          filler(imported,80)
          rr,vv,ss,=NativeDrawerCheck.current(imported)
          saved_again=ModuleFile.save(path,Parametric.with_values(rr,vv),ss,expected:ModuleFile.signature(path),source_root:imported)
          check(File.file?(saved_again['backup']),'Saving an existing module at T=80 retains the logical input frame and a backup')
          @model.start_operation('MH QA048 Scale filler copy',true)
          scaled=@model.entities.add_instance(imported.definition,imported.transformation)
          NativeAssemblyScaleCheck.copy_attributes(imported,scaled); Runtime.private_tree(scaled); @owned << scaled
          scaled.transformation *= Geom::Transformation.scaling(2,1,1)
          ScaleRedraw.apply(@model,[ScaleRedraw.prepare(scaled)])
          @model.commit_operation; reset
          rr,vv,ss,=NativeDrawerCheck.current(scaled)
          check((Core.dimensions(ss['envelope'])[0]-160).abs<0.001 && Core.plan(rr,ss,vv)['changed_count'].zero?,'Native Scale after thickness overflow establishes a new explicit 160 mm construction width')
          Runtime.update_trial(scaled,rr,vv.merge('dodaytam'=>20))
          rr,vv,ss,=NativeDrawerCheck.current(scaled)
          check((Core.dimensions(ss['envelope'])[0]-160).abs<0.001 && (Core.dimensions(ss['envelope'])[1]-70).abs<0.001 && Core.plan(rr,ss,vv)['changed_count'].zero?,'Thickness remains editable after overflow, SKP roundtrip and Scale')
          filler(imported,20)
          # Read an untouched source DC, generate a fresh own model and save/import it.
          dc=@model.find_entity_by_persistent_id(466528)
          if dc && !dc.get_attribute(Reader::DICT,'trial',false)
            snapshot,=Reader.live(dc,label:'Nẹp DC QA047',parameter:nil)
            converted=StudioCalculation.build_system([snapshot])
            Runtime.create_model(snapshot,converted,Parametric.targets(converted))
            generated=Runtime.selected_root; @owned << generated
            converted_path=File.join(directory,'Nẹp DC QA047.skp')
            library.export(generated,converted_path); library.refresh
            returned=library.place(library.prepare(File.basename(converted_path)),Geom::Point3d.new(0,0,0)); @owned << returned
            [80,200,20,80,18.6].each do |thickness|
              rr,vv,=NativeDrawerCheck.current(returned)
              Runtime.update_trial(returned,rr,vv.merge('dodaytam'=>thickness))
              rr,vv,ss,=NativeDrawerCheck.current(returned)
              check((Core.dimensions(ss['envelope'])[1]-50-thickness).abs<0.001 && Core.plan(rr,ss,vv)['changed_count'].zero?,"Untouched DC -> own model -> SKP -> import: T=#{thickness} retains fixed 50 mm and correct depth")
            end
          end
          # Exercise actual Parametric actions on private objects, never user's files.
          imported.set_attribute(Reader::DICT,'library_source_path',path)
          imported.set_attribute(Reader::DICT,'library_source_signature',ModuleFile.signature(path))
          @model.selection.clear; @model.selection.add(imported)
          panel=Panel.new; panel.capture_parametric_root(imported)
          panel.request('action'=>'rename_model','snapshot_id'=>panel.instance_variable_get(:@snapshots).last['id'],'revision'=>panel.instance_variable_get(:@parametric_revision),'name'=>'Nẹp tên mới QA047')
          panel.request('action'=>'save_skp','rule_id'=>panel.instance_variable_get(:@rule)['id'],'snapshot_id'=>panel.instance_variable_get(:@snapshots).last['id'],'revision'=>panel.instance_variable_get(:@parametric_revision))
          check(File.file?(File.join(directory,'Nẹp tên mới QA047.skp')) && File.file?(path),'Parametric Save SKP follows renamed filename while retaining the previous file')
          # Assembly roundtrip must preserve independent programs and eight contacts.
          cluster_path=File.join(directory,'Cụm QA047.skp')
          library.export(assembly,cluster_path); library.refresh
          library.export(assembly,cluster_path)
          check(!Dir[File.join(directory,'.mh-backups','Cụm QA047-*.skp')].empty?,'Explicit assembly SKP overwrite retains a backup')
          library.refresh
          data=library.prepare('Cụm QA047.skp')
          cluster=library.place(data,Geom::Point3d.new(0,0,0)); @owned << cluster
          check(AssemblyContainers.managed?(cluster) && AssemblyContainers.members(cluster).length==3,'Saved assembly imports as a managed parent component with three members')
          links=Assembly.records(@model).select { |row| row['scope']==cluster.persistent_id.to_s }
          check(links.length==8,'All eight links survive SKP roundtrip with new native PIDs')
          links.each { |row| Assembly.verify(@model,row) }
          @model.selection.clear; @model.selection.add(cluster)
          window=ModuleOptions.new; fake=Object.new
          fake.define_singleton_method(:execute_script) { |_code| nil }; fake.define_singleton_method(:set_size) { |_w,_h| nil }
          window.instance_variable_set(:@dialog,fake); window.define_singleton_method(:thumbnail) { |_root| nil }; window.refresh
          rows=window.instance_variable_get(:@display_rows)
          common=rows.find { |row| row['id']=='common:T1' }
          private_row=rows.find { |row| row['symbol']=='iwc3l3ib0g' }
          check(common && private_row,'Imported assembly exposes common T and private module parameters')
          before=Core.dimensions(AssemblyEnvelope.bounds(cluster))
          window.apply_changes([{'variable_id'=>common['id'],'value'=>20},{'variable_id'=>private_row['id'],'value'=>20}]); window.refresh
          after=Core.dimensions(AssemblyEnvelope.bounds(cluster))
          @report['batch']={'before'=>before,'after'=>after,'common_before'=>common['value'],'members'=>AssemblyContainers.members(cluster).map { |member| rr,vv,ss,=NativeDrawerCheck.current(member); {'name'=>member.name,'values'=>vv,'dims'=>Core.dimensions(ss['envelope']),'policy'=>rr.dig('formula_engine','envelope_policy')} }}
          check((after[1]-before[1]).abs<0.02,'Assembly uses free member dimensions before changing its construction depth')
          AssemblyContainers.members(cluster).each do |member|
            rr,vv,ss,=NativeDrawerCheck.current(member)
            binding=Parametric.variables(rr).find { |row| row['symbol']=='T1' }['binding']
            check((vv[binding]-20).abs<0.001 && Core.plan(rr,ss,vv)['changed_count'].zero?,member.name+': batched values and geometry survive assembly import')
          end
          window.instance_variable_set(:@dialog,nil); window.detach; window=nil
          panel.capture_parametric_root(cluster)
          check(ParametricModel.assembly_sheet(cluster)['parts'].length==3,'Parametric lists assembly members without flattening their programs')
          panel.request('action'=>'rename_model','snapshot_id'=>panel.instance_variable_get(:@snapshots).last['id'],'revision'=>panel.instance_variable_get(:@parametric_revision),'name'=>'Cụm đổi tên QA047')
          AssemblyFile.save(cluster,File.join(directory,Parametric.filename(cluster.name)))
          library.refresh
          again=library.place(library.prepare('Cụm đổi tên QA047.skp'),Geom::Point3d.new(0,0,0)); @owned << again
          check(again.name=='Cụm đổi tên QA047','Renamed assembly re-exports and imports with the new name')
          NativeAssemblyScaleCheck.instance_variable_set(:@model,@model)
          NativeAssemblyScaleCheck.scale(again,[1.1,1.1,0.9])
          check(true,'Reimported assembly supports native Scale and redraw with its saved contacts')
          @report['ok']=true
        rescue StandardError=>detail
          @report['error']=[detail.message,*detail.backtrace.first(8)]
        ensure
          window.instance_variable_set(:@dialog,nil) if window
          window&.detach
          @model.start_operation('MH QA047 Cleanup',true)
          @owned.reverse_each { |root| root.erase! if root.valid? }
          raw ? @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,raw) : @model.delete_attribute(Reader::DICT,AssemblyContainers::KEY)
          40.times do
            empty=(@model.definitions.to_a-definitions).select { |definition| definition.instances.empty? }
            break if empty.empty?
            empty.each { |definition| @model.definitions.remove(definition) }
          end
          @model.selection.clear; @model.selection.add(selected.select(&:valid?)); @model.commit_operation; reset
          check(originals.all? { |root,hash| root.valid? && NativeDrawerCheck.fingerprint(root)==hash },'All user objects, source files and current selection remain unchanged')
        end
        @report
      end
    end
  end
end

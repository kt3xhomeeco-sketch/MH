# encoding: UTF-8
require_relative 'native_coplanar_links_check'

module MH
  module ModuleStudio
    module NativeEnvelopeLinksCheck
      include NativeCoplanarLinksCheck
      extend self

      def hollow_pair
        a=module_root('MH QA060 Khung',60000)
        [[[0,0,0],[18,500,800]],[[582,0,0],[600,500,800]],[[18,0,0],[582,500,18]],
         [[18,0,782],[582,500,800]],[[18,492,18],[582,500,782]]].each_with_index do |(low,high),i|
          box(a.definition.entities,"Panel #{i}",low,high)
        end
        b=module_root('MH QA060 Lọt',60000)
        box(b.definition.entities,'Lọt',[21,10,21],[579,489,779])
        [a,b]
      end

      def old_links(a,b)
        left=a.definition.entities.find { |child| child.name=='Panel 0' }
        inner=b.definition.entities.find { |child| child.name=='Lọt' }
        ar={'root'=>a.persistent_id.to_s,'axis'=>0,'side'=>1,'path'=>[left.persistent_id.to_s]}
        br={'root'=>b.persistent_id.to_s,'axis'=>0,'side'=>0,'path'=>[inner.persistent_id.to_s]}
        legacy=AssemblyInference.record(ar,br,3)
        manual=Core.copy_data(legacy);manual['id']=Core::Ids.uuid;manual.delete('inferred')
        [legacy,manual]
      end

      def all_envelopes?(rows)
        rows.all? do |row|
          %w[a b].all? do |key|
            ref=row.fetch(key)
            ref['level']=='module' && ref.fetch('path',[]).empty? && !ref['part'] && !ref['panel']
          end
        end
      end

      def run(expected_pid:,output:)
        @model=Sketchup.active_model
        raise 'Wrong native session/context' unless Process.pid==expected_pid && @model.title.empty? && @model.active_path.nil?
        @report={'ok'=>false,'checks'=>[]};@owned=[]
        originals=@model.entities.select { |entity| Assembly.container?(entity) }
        fingerprints=originals.to_h { |entity| [entity.persistent_id,NativeDrawerCheck.fingerprint(entity)] }
        definitions=@model.definitions.to_a;selection=@model.selection.to_a;camera=@model.active_view.camera
        original_links=@model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        begin
          @model.start_operation('MH QA060 fixtures',true)
          # Isolate fixture transactions from pre-existing orphan links in the
          # user's model. Restore their exact original JSON in cleanup.
          @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,'[]')
          a,b=hollow_pair
          c=module_root('MH QA060 Kề',60603)
          box(c.definition.entities,'Kề',[0,0,0],[600,500,800])
          @model.commit_operation;reset
          captured=AssemblyAutoLinks.capture(@model,[[a,nil],[b,nil]])
          check(captured.all? { |mod| mod['faces'].length==6 },'Hollow nested modules expose exactly six virtual envelope faces')
          check(captured.flat_map { |mod| mod['faces'] }.all? { |face| all_envelopes?([{'a'=>face['anchor'],'b'=>face['anchor']}]) },'Captured anchors never contain panel identities or child paths')
          picking(a,b)
          select(a,b);before=[geometry(a),geometry(b)]
          check(AssemblyAutoLinks.create(@model,max_gap:3)['links'].empty?,'Inner 3 mm panel contacts are not inferred when module envelopes do not qualify')
          check(before==[geometry(a),geometry(b)],'Empty envelope discovery leaves source geometry unchanged')
          select(a,c)
          links=AssemblyAutoLinks.create(@model,max_gap:3)['links']
          check(links.length==5 && all_envelopes?(links),'Hollow module pairs use one opposed envelope contact and four coplanar envelope links')
          @model.start_operation('MH QA060 rotate reflected envelopes',true)
          origin=Geom::Point3d.new(60000/25.4,60000/25.4,0)
          common=Geom::Transformation.rotation(origin,Z_AXIS,30.degrees)*Geom::Transformation.scaling(origin,-1,1,1)
          frames=[a,c].map(&:transformation)
          [a,c].each { |root| root.transformation=common*root.transformation }
          @model.commit_operation;reset
          links.each { |row| Assembly.verify(@model,row) }
          check(AssemblyAutoLinks.create(@model,max_gap:3)['links'].empty?,'Rotated/reflected envelope inference keeps six local planes and stable references')
          @model.start_operation('MH QA060 restore envelope frames',true)
          [a,c].zip(frames).each { |root,frame| root.transformation=frame }
          @model.commit_operation;reset
          Assembly.store_contacts(@model,Assembly.records(@model)-links,[],removed:links)
          @model.start_operation('MH QA060 offset planes',true)
          c.transform!(Geom::Transformation.translation([0,7/25.4,0]));@model.commit_operation;reset
          links=AssemblyAutoLinks.create(@model,max_gap:20)['links']
          parallel=links.select { |row| row['relation']=='parallel' }
          check(parallel.length==2 && parallel.all? { |row| (row['gap'].abs-7).abs<0.000001 },'Noncoplanar front/back envelopes produce signed 7 mm parallel offsets')
          links.each { |row| Assembly.verify(@model,row) }
          original=geometry(c);leader=geometry(a)
          front=parallel.find { |row| row.dig('a','side')==0 }
          Assembly.save(@model,front.merge('gap'=>front['gap'].negative? ? -10 : 10))
          Assembly.save(@model,Core.copy_data(front))
          check(original==geometry(c) && leader==geometry(a),'Parallel offset edits restore exact geometry while keeping the leader fixed')
          # Save/restore the new relationship metadata before moving on to migration.
          seed=Assembly.group(@model,links.first);wrapper=AssemblyContainers.wrapper(@model,seed['scope']);@owned << wrapper
          path=File.join(File.dirname(output),'parallel-envelope.skp');AssemblyFile.save(wrapper,path)
          @model.start_operation('MH QA060 reread parallel SKP',true)
          begin
            definition=@model.definitions.load(path)
            data=LibraryCatalog.payload(definition.get_attribute(Reader::DICT,LibraryCatalog::PAYLOAD_KEY))
            probe=@model.entities.add_instance(definition,Geom::Transformation.new);Runtime.private_tree(probe);AssemblyFile.restore(probe,data)
            check(data['links'].count { |row| row['relation']=='parallel' }==2 && all_envelopes?(data['links']),'Actual SKP roundtrip retains parallel metadata and envelope-only anchors')
          ensure
            @model.abort_operation
          end
          # Separate hollow fixtures allow a removal-only migration, including a shared scope.
          @model.start_operation('MH QA060 migration fixtures',true)
          a,b=hollow_pair
          [a,b].each { |root| root.transform!(Geom::Transformation.translation([0,5000/25.4,0])) }
          @model.commit_operation;reset
          legacy,manual=old_links(a,b)
          Assembly.store_contacts(@model,Assembly.records(@model),[legacy,manual])
          select(a,b);before=[geometry(a),geometry(b)]
          result=AssemblyAutoLinks.create(@model,max_gap:3)
          check(result['removed']==1 && result['links'].empty?,'Rerun removes a selected legacy inferred panel link without inventing an envelope link')
          check(Assembly.records(@model).any? { |row| row['id']==manual['id'] } && before==[geometry(a),geometry(b)],'Manual panel link and native geometry survive migration')
          seed=Assembly.group(@model,manual);owner=AssemblyContainers.wrapper(@model,seed['scope']);@owned << owner
          manual=Assembly.records(@model).find { |row| row['id']==seed['id'] }
          scoped=Core.copy_data(manual).merge('id'=>seed['scope']+':'+Core::Ids.uuid,'inferred'=>true)
          Assembly.store_contacts(@model,Assembly.records(@model),[scoped])
          @model.start_operation('MH QA060 copy shared assembly',true)
          clone=@model.entities.add_instance(owner.definition,owner.transformation*Geom::Transformation.translation([3000/25.4,0,0]))
          owner.attribute_dictionaries.each { |dict| dict.each_pair { |key,value| clone.set_attribute(dict.name,key,value) } }
          @owned << clone;@model.commit_operation;reset
          clone_before=NativeDrawerCheck.fingerprint(clone)
          select(owner)
          result=AssemblyAutoLinks.create(@model,max_gap:3)
          check(result['removed']==1 && result['links'].empty? && AssemblyContainers.read(owner).none? { |row| row['inferred'] },'Removal-only migration is persisted inside the selected grouped assembly')
          check(owner.definition!=clone.definition && NativeDrawerCheck.fingerprint(clone)==clone_before,'Unselected shared assembly retains its definitions and old links')
          check(AssemblyContainers.read(owner).length==1,'Selected grouped manual relation remains saved')
          @report['ok']=true
        rescue StandardError => detail
          @report['error']=[detail.message,*detail.backtrace.first(8)]
        ensure
          @model.start_operation('MH QA060 cleanup',true)
          @owned.reverse_each { |entity| entity.erase! if entity.valid? }
          original_links ? @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,original_links) : @model.delete_attribute(Reader::DICT,AssemblyContainers::KEY)
          40.times do
            empty=(@model.definitions.to_a-definitions).select { |definition| definition.instances.empty? }
            break if empty.empty?
            empty.each { |definition| @model.definitions.remove(definition) }
          end
          @model.selection.clear;@model.selection.add(selection.select(&:valid?));@model.commit_operation
          @model.active_view.camera=camera;@model.active_view.refresh;reset
          check(originals.all? { |entity| entity.valid? && NativeDrawerCheck.fingerprint(entity)==fingerprints[entity.persistent_id] },'All original user modules and names remain unchanged')
          File.write(output,JSON.pretty_generate(@report))
        end
        @report
      end

      def start_migration_undo(expected_pid:,output:)
        @model=Sketchup.active_model
        raise 'Wrong native session/context' unless Process.pid==expected_pid && @model.title.empty? && @model.active_path.nil?
        @report={'ok'=>false,'checks'=>[]};@owned=[];@undo_output=output
        @undo_raw=@model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        @undo_definitions=@model.definitions.to_a;@undo_selection=@model.selection.to_a
        @undo_originals=@model.entities.select { |root| Assembly.container?(root) }.to_h { |root| [root,NativeDrawerCheck.fingerprint(root)] }
        @model.start_operation('MH QA060 Undo fixtures',true)
        @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,'[]')
        a,b=pair
        @model.commit_operation;reset
        refs=[a,b].each_with_index.map do |root,i|
          child=root.definition.entities.find { |entry| Assembly.container?(entry) }
          {'root'=>root.persistent_id.to_s,'path'=>[child.persistent_id.to_s],'axis'=>0,'side'=>1-i}
        end
        @migration_legacy=AssemblyInference.record(*refs,3)
        @migration_manual=Core.copy_data(@migration_legacy).merge('id'=>Core::Ids.uuid);@migration_manual.delete('inferred')
        Assembly.store_contacts(@model,[],[@migration_legacy,@migration_manual])
        select(a,b);@undo_geometry=@owned.map { |root| geometry(root) }
        result=AssemblyAutoLinks.create(@model,max_gap:3)
        @migration_ids=result['links'].map { |row| row['id'] }
        check(result['removed']==1 && @migration_ids.length==5,'One batch replaces a legacy panel link with five envelope links and retains manual input')
        UI.start_timer(0.2,false) { migration_undo_stage }
        {'scheduled'=>true}
      rescue StandardError => detail
        @report['error']=detail.message
        undo_cleanup
      end

      def migration_undo_stage
        Sketchup.undo
        UI.start_timer(0.2,false) do
          begin
            ids=Assembly.records(@model).map { |row| row['id'] }
            check(ids.include?(@migration_legacy['id']) && ids.include?(@migration_manual['id']) && (ids & @migration_ids).empty?,'One Undo restores the removed panel link and removes all new envelope links')
            check(@undo_geometry==@owned.map { |root| geometry(root) },'Migration Undo preserves geometry')
            Sketchup.send_action('editRedo:')
            UI.start_timer(0.2,false) do
              begin
                rows=Assembly.records(@model);ids=rows.map { |row| row['id'] }
                check(!ids.include?(@migration_legacy['id']) && ids.include?(@migration_manual['id']) && (@migration_ids-ids).empty?,'One Redo restores the whole envelope migration with manual link retained')
                rows.each { |row| Assembly.verify(@model,row) }
                check(@undo_geometry==@owned.map { |root| geometry(root) },'Migration Redo preserves geometry')
                @report['ok']=true
              rescue StandardError => detail
                @report['error']=detail.message
              ensure
                undo_cleanup
              end
            end
          rescue StandardError => detail
            @report['error']=detail.message;undo_cleanup
          end
        end
      end
    end
  end
end

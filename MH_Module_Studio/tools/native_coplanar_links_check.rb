# encoding: UTF-8
require_relative 'native_auto_contacts_check'

module MH
  module ModuleStudio
    module NativeCoplanarLinksCheck
      include NativeAutoContactsCheck
      extend self

      # The inherited asynchronous Undo/Redo check exercises this mixed fixture.
      def pair
        a=module_root('MH QA059 Undo A',60000);b=module_root('MH QA059 Undo B',60603)
        [a,b].each { |root| box(root.definition.entities,'Panel',[0,0,0],[600,500,800]) }
        [a,b]
      end

      def run(expected_pid:,output:)
        @model=Sketchup.active_model
        raise 'Wrong native session/context' unless Process.pid==expected_pid && @model.title.empty? && @model.active_path.nil?
        @report={'ok'=>false,'checks'=>[]};@owned=[]
        originals=@model.entities.to_a.select { |entity| Assembly.container?(entity) }
        fingerprints=originals.to_h { |entity| [entity.persistent_id,NativeDrawerCheck.fingerprint(entity)] }
        definitions=@model.definitions.to_a;selection=@model.selection.to_a
        original_links=@model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        begin
          @model.start_operation('MH QA059 fixtures',true)
          a=module_root('MH QA059 Khung',60000);b=module_root('MH QA059 Cánh',60603);c=module_root('MH QA059 Nẹp',61206)
          [a,b,c].each { |root| box(root.definition.entities,'Panel',[0,0,0],[600,500,800]) }
          @model.commit_operation;reset
          select(a,b)
          before=[geometry(a),geometry(b)]
          links=AssemblyAutoLinks.create(@model,max_gap:3)['links']
          aligned=links.select { |row| row['relation']=='coplanar' }
          check(links.length==5 && aligned.length==4,'Infer one 3 mm opposed contact and four coplanar front/back/top/bottom faces')
          check(links.reject { |row| row['relation']=='coplanar' }.all? { |row| (row['gap']-3).abs<0.000001 },'Opposed contact retains its measured gap')
          check(before==[geometry(a),geometry(b)],'Coplanar discovery leaves both native modules unchanged')
          check(AssemblyAutoLinks.create(@model,max_gap:3)['links'].empty?,'Repeated mixed inference has no duplicates')
          links.each { |row| Assembly.verify(@model,row) }
          chosen=aligned.find { |row| row.dig('a','axis')==1 && row.dig('a','side')==0 }
          check(chosen,'Front coplanar face is an editable saved link')
          changed=Core.copy_data(chosen).merge('gap'=>3)
          a_before=geometry(a)
          Assembly.save(@model,changed)
          Assembly.records(@model).each { |row| Assembly.verify(@model,row) }
          check(geometry(a)==a_before && geometry(b)!=before[1],'Editing a coplanar gap fits B against the other saved planes and retains A')
          Assembly.save(@model,Core.copy_data(chosen))
          check(before==[geometry(a),geometry(b)],'Returning coplanar offset to zero restores the original geometry')
          @model.start_operation('MH QA059 rotated reflection',true)
          origin=Geom::Point3d.new(60000/25.4,60000/25.4,0)
          common=Geom::Transformation.rotation(origin,Z_AXIS,30.degrees)*Geom::Transformation.scaling(origin,-1,1,1)
          frames=[a,b,c].map(&:transformation)
          [a,b,c].each { |root| root.transformation=common*root.transformation }
          @model.commit_operation;reset
          Assembly.records(@model).each { |row| Assembly.verify(@model,row) }
          check(AssemblyAutoLinks.create(@model,max_gap:3)['links'].empty?,'Rotated/reflected planes retain links and duplicate filtering')
          @model.start_operation('MH QA059 restore frame',true)
          [a,b,c].zip(frames).each { |root,frame| root.transformation=frame }
          @model.commit_operation;reset
          select(a,b,c)
          extra=AssemblyAutoLinks.create(@model,max_gap:3)['links']
          check(extra.length==5,'Third adjacent module adds its own five relations')
          seed=Assembly.group(@model,Assembly.records(@model).find { |row| links.any? { |link| link['id']==row['id'] } })
          wrapper=AssemblyContainers.wrapper(@model,seed['scope']);@owned << wrapper
          groups=Assembly.presentation_groups(@model,Assembly.records(@model).select { |row| row['scope']==seed['scope'] })
          names=groups.first['modules'].map { |member| member['name'] }
          check(groups.length==1 && names.sort==['MH QA059 Khung','MH QA059 Cánh','MH QA059 Nẹp'].sort,'Grouped three-module presentation lists every member separately')
          check(groups.first['links'].length==10 && groups.first['links'].any? { |row| row['label'].include?('Đồng phẳng') },'Group relationships follow member rows with explicit types')
          actions=[];tool=AssemblyTool.new
          tool.define_singleton_method(:action) { |*args| actions << args }
          tree=AssemblyTree.new(@model,tool)
          tree.links(Assembly.records(@model),seed['scope'],0)
          rows=tree.rows
          check(rows.select { |row| row['kind']=='module' }.map { |row| row['name'] }.sort==names.sort,'Native tree uses separate module rows beneath Links')
          check(rows.index { |row| row['kind']=='link' }>rows.rindex { |row| row['kind']=='module' },'Native tree places types below all linked module names')
          rect=tree.layout(@model.active_view)['rect']
          tree.click(rect[0]+15,rect[1]+40,@model.active_view)
          check(actions==[[:auto_links,20]],'Visible native tree button invokes selected-module inference')
          select(wrapper)
          check(AssemblyAutoLinks.create(@model,max_gap:3)['links'].empty?,'Grouped selected members preserve equivalent-plane duplicate filtering')
          path=File.join(File.dirname(output),'coplanar-fixture.skp')
          AssemblyFile.save(wrapper,path)
          @model.start_operation('MH QA059 reread SKP',true)
          begin
            definition=@model.definitions.load(path)
            data=LibraryCatalog.payload(definition.get_attribute(Reader::DICT,LibraryCatalog::PAYLOAD_KEY))
            copy=@model.entities.add_instance(definition,Geom::Transformation.new)
            Runtime.private_tree(copy);AssemblyFile.restore(copy,data)
            check(data['links'].count { |row| row['relation']=='coplanar' }==8,'Actual SKP roundtrip retains every coplanar relationship')
          ensure
            @model.abort_operation
          end
          @report['ok']=true
        rescue StandardError => detail
          @report['error']=[detail.message,*detail.backtrace.first(8)]
        ensure
          @model.start_operation('MH QA059 cleanup',true)
          @owned.reverse_each { |entity| entity.erase! if entity.valid? }
          original_links ? @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,original_links) : @model.delete_attribute(Reader::DICT,AssemblyContainers::KEY)
          40.times do
            empty=(@model.definitions.to_a-definitions).select { |definition| definition.instances.empty? }
            break if empty.empty?
            empty.each { |definition| @model.definitions.remove(definition) }
          end
          @model.selection.clear;@model.selection.add(selection.select(&:valid?))
          @model.commit_operation;reset
          check(originals.all? { |entity| entity.valid? && NativeDrawerCheck.fingerprint(entity)==fingerprints[entity.persistent_id] },'All original user modules remain unchanged')
          File.write(output,JSON.pretty_generate(@report))
        end
        @report
      end
    end
  end
end

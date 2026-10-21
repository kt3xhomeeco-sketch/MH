# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeDisplayDoorCheck
      extend self
      class Overlay < AssemblyOverlay
        def initialize(hud) # rubocop:disable Lint/MissingSuper -- Unique QA overlay ID; initialize the native base without the production overlay ID.
          Sketchup::Overlay.instance_method(:initialize).bind(self).call('mh.module_studio.qa085','MH QA 085')
          @hud=hud
        end
      end
      def run(baseline: false, locked: false)
        model=Sketchup.active_model;Runtime.ensure_top_level(model)
        active=ModuleStudio.instance_variable_get(:@library)&.tool
        raise 'User placement active' if active&.pending
        before=model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] }
        definitions=model.definitions.to_a;selection=model.selection.to_a;camera=model.active_view.camera
        preferences=Sketchup.read_default('MH_Module_Studio','library_v1','')
        links=model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        library=Library.new;library.instance_variable_set(:@catalog,LibraryCatalog.scan(library.config['root']))
        if locked
          data=locked_payload
          library.define_singleton_method(:build_instance) do |sample,transform,entities: Sketchup.active_model.active_entities|
            NativeDisplayDoorCheck.build_locked(sample,transform,entities)
          end
        else
          data=library.preview('Canh/Canh trai.skp')
        end
        raise 'Source has no door role' unless data.dig('import_template','role')=='door'
        library.define_singleton_method(:resolve_fit) { |sample,placement,**_options| [sample,placement] } if baseline
        previous_busy=Assembly.instance_variable_get(:@busy);Assembly.instance_variable_set(:@busy,true)
        model.start_operation('MH QA door Replace and link display',true);operation=true
        result={'checks'=>[],'source'=>data['entry_id']};replaced=[]
        2.times do |index|
          definition=model.definitions.add('MH QA 085 placeholder')
          box=[[10,20,30],[610,520,830]]
          vertices=Frames.corners(box).map { |p| p.map { |v| v/25.4 } }
          [[0,1,2,3],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]].each { |ids| definition.entities.add_face(ids.map { |id| vertices[id] }) }
          frame=Geom::Transformation.translation([(100_000+index*3000)/25.4,0,0])
          frame*=Geom::Transformation.rotation(ORIGIN,Z_AXIS,0.3)*Geom::Transformation.scaling(-1.3,2,0.8) if index==1
          root=model.entities.add_instance(definition,frame);anchor={'root'=>root.persistent_id.to_s}
          if baseline
            begin
              current=LibraryPlacement.replace!(library,data,anchor,[])
              return {'status'=>'baseline allowed','source_dimensions'=>Core.dimensions(data['snapshot']['envelope']),'actual_dimensions'=>Core.dimensions(Frames.box(Frames.corners(AssemblyEnvelope.bounds(current)).map { |p| Geom::Point3d.new(p.map { |v| v/25.4 }).transform(frame.inverse*current.transformation).to_a.map { |v| v*25.4 } })),'rule_kind'=>data['format']}
            rescue Core::Error=>error
              return {'status'=>'reproduced','error'=>error.message}
            end
          end
          placement={'mode'=>'replace','frame'=>frame.to_a,'bounds'=>box,'anchor'=>anchor}
          effective,preview=library.resolve_fit(data,placement)
          root=LibraryPlacement.replace!(library,effective,anchor,[])
          actual=Frames.box(Frames.corners(AssemblyEnvelope.bounds(root)).map { |p| Geom::Point3d.new(p.map { |v| v/25.4 }).transform(frame.inverse*root.transformation).to_a.map { |v| v*25.4 } })
          raise 'Actual door differs from preview' unless Core.bounds_close?(actual,preview['bounds'],0.02)
          scales=Frames.scale_frame(frame.to_a).values_at(0,5,10)
          physical=Core.dimensions(actual).zip(scales).map { |size,scale| size*scale }
          nominal=Core.dimensions(data['snapshot']['envelope'])[1]
          raise 'Door thickness was stretched' unless (physical[1]-nominal).abs<0.02
          raise 'Width/height failed target' unless [0,2].all? { |axis| (physical[axis]-Core.dimensions(box)[axis]*scales[axis]).abs<0.02 }
          raise 'Front datum moved' unless 3.times.all? { |axis| (actual[0][axis]-box[0][axis]).abs<0.02 }
          replaced << root
          result['checks'] << {kind:index.zero? ? 'unit' : 'rotated_mirrored_scaled',dimensions:physical,front:actual[0]}
        end
        raise 'Replace instances share identity' unless replaced.map { |r| r.get_attribute(Reader::DICT,'instance_id') }.uniq.length==2
        result['checks'] << 'Different replacements have independent identities'
        a,b=replaced
        record={'id'=>'qa085','mode'=>'contact','a'=>{'root'=>a.persistent_id.to_s,'path'=>[],'axis'=>0,'side'=>1},'b'=>{'root'=>b.persistent_id.to_s,'path'=>[],'axis'=>0,'side'=>0},'gap'=>20.0}
        # Use parallel local-X planes in a separate pair for overlay verification.
        b.transformation=Geom::Transformation.translation([101_000/25.4,0,0])
        tool=AssemblyTool.new;tool.load_record(record);tool.instance_variable_set(:@active,true)
        hud=AssemblyHUD.allocate;hud.instance_variable_set(:@model,model);hud.instance_variable_set(:@tool,tool);hud.instance_variable_set(:@closed,false)
        contacts=ContactView.new(model,tool);contacts.define_singleton_method(:rows) { [record] }
        original=contacts.method(:draw);draws=0;contacts.define_singleton_method(:draw) { |view| draws+=1;original.call(view) }
        hud.instance_variable_set(:@contacts,contacts)
        overlay=Overlay.new(hud);model.overlays.add(overlay);overlay.enabled=true
        view=model.active_view;center=a.bounds.center;view.camera=Sketchup::Camera.new(center+Geom::Vector3d.new(1000/25.4,-1800/25.4,900/25.4),center,Z_AXIS)
        view.refresh
        raise 'Active contact dimensions missing' unless draws.positive? && !contacts.last_error && contacts.items.any?
        raise 'Active overlay bounds empty' if overlay.getExtents.empty?
        prior_draws=draws;tool.instance_variable_set(:@active,false);view.refresh
        raise 'Inactive HUD still drawing' unless draws==prior_draws && !hud.visible?
        raise 'Inactive overlay extends model' unless overlay.getExtents.empty?
        tool.instance_variable_set(:@active,true);view.refresh
        raise 'Returning to linking did not restore dimensions' unless draws>prior_draws
        hud.instance_variable_set(:@closed,true);prior_draws=draws;view.refresh
        raise 'Closed HUD drew' unless draws==prior_draws && overlay.getExtents.empty?
        result['checks'] << 'Active native overlay draws dimensions, inactive/closed draws nothing and has empty extents, return restores it'
        result.merge('status'=>'passed','pid'=>Process.pid,'model_retained'=>true)
      ensure
        model.overlays.remove(overlay) if overlay && overlay.valid?
        model.abort_operation if operation
        Assembly.instance_variable_set(:@busy,previous_busy) if operation
        if camera
          model.active_view.camera=camera;model.active_view.refresh
        end
        if before
          raise 'Geometry changed' unless before==model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] }
          raise 'Definitions changed' unless definitions==model.definitions.to_a
          raise 'Selection changed' unless selection==model.selection.to_a
          raise 'Preferences changed' unless preferences==Sketchup.read_default('MH_Module_Studio','library_v1','')
          raise 'Links changed' unless links==model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        end
      end
      def locked_payload
        bounds=[[0,0,0],[400,18.6,700]]
        snapshot=Core.snapshot!({'id'=>'qa085','label'=>'QA locked door','source'=>{'kind'=>'native-qa'},'parameter'=>18.6,
          'dc_inputs'=>{},'envelope'=>bounds,'parts'=>[{'key'=>'panel','name'=>'Panel','bounds'=>bounds,'visible'=>true,
          'box_verified'=>true,'face_count'=>6,'edge_count'=>12,'thickness_axis'=>1,'dc_attributes'=>{}}]})
        rule=ThicknessSymbols.normalize(RuleSystem.build(snapshot))
        rule=ImportTemplate.edit(rule,ImportTemplate.defaults.merge('enabled'=>true,'role'=>'door'))
        {'entry_id'=>'qa-locked-door','format'=>'mh_module_library','name'=>'QA locked door','rule'=>rule,
          'values'=>Parametric.targets(rule),'snapshot'=>snapshot,'import_template'=>rule['import_template']}
      end
      def build_locked(data,transform,entities)
        definition=entities.model.definitions.add('MH QA locked door')
        plan=Core.plan(data['rule'],data['snapshot'],data['values'])
        Runtime.populate_parts(definition,plan)
        root=entities.add_instance(definition,Geom::Transformation.new)
        _snapshot,bindings=Reader.live(root,label:'QA',parameter:18.6)
        Runtime.stamp(root,data['rule'],bindings,data['values']);Runtime.verify_result(root,plan)
        root.transformation=transform;root
      end
    end
  end
end

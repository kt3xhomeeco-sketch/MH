# encoding: UTF-8
# Developer QA: run through the pinned, already-open VBO session. All geometry
# changes are inside one aborted operation; no file or camera is changed.
module MH
  module ModuleStudio
    module NativeImportContactCheck
      extend self

      def with_assembly_busy(value)
        previous=Assembly.instance_variable_get(:@busy)
        Assembly.instance_variable_set(:@busy,value)
        yield
      ensure
        Assembly.instance_variable_set(:@busy,previous)
      end

      def definition_ids(model)
        model.definitions.to_a.map(&:persistent_id)
      end

      def update_watcher_open?(model)
        watcher=UpdateWork.instance_variable_get(:@watchers)&.fetch(model,nil)
        raise 'No UpdateWork watcher; observation unavailable' unless watcher.respond_to?(:open?)
        !!watcher.open?
      end

      def new_definition_ids(model,before)
        definition_ids(model)-before
      end

      def remove_owned_definitions(model,ids)
        owned=Array(ids)
        loop do
          removed=false
          owned.each do |id|
            definition=model.definitions.find { |item| item.persistent_id==id }
            next unless definition&.valid? && definition.instances.empty?
            model.definitions.remove(definition)
            removed=true
          end
          break unless removed
        end
      end

      def clone_root(model, source)
        root=model.entities.add_instance(source.definition,source.transformation)
        source.attribute_dictionaries&.each do |dictionary|
          dictionary.each_pair { |key,value| root.set_attribute(dictionary.name,key,value) }
        end
        root.name=source.name+' QA'
        Runtime.private_tree(root)
        if (owned=AssemblyParameters.data(root))
          rule,values=owned
          _snapshot,bindings=Reader.live(root,label:'QA copy',parameter:Runtime.read_parameter(rule,values))
          Runtime.stamp(root,rule,bindings,values)
        end
        root
      end

      # Native faces/rays/transforms, with a deterministic cursor on a chosen
      # face. This tests the adapter path without moving the user's camera.
      def detection_view(model,host,target)
        panel,frame=Assembly.panel(model,target['anchor'])
        axis=target['anchor']['axis'];side=target['anchor']['side']
        boundary=side.zero? ? panel.definition.bounds.min.to_a[axis] : panel.definition.bounds.max.to_a[axis]
        face=panel.definition.entities.grep(Sketchup::Face).find do |item|
          item.normal.to_a[axis].abs>0.999999 && (item.vertices.first.position.to_a[axis]-boundary).abs<0.00001
        end
        point=Geom::Point3d.new(3.times.map { |a| target['points'].sum { |p| p[a] }/target['points'].length/25.4 }).transform(Geom::Transformation.new(host['frame']))
        normal=Geom::Vector3d.new(3.times.map { |a| a==target['axis'] ? (target['side'].zero? ? -1 : 1) : 0 }).transform(Geom::Transformation.new(host['frame'])).normalize
        offset=normal.clone;offset.length=20.0/25.4
        helper=Object.new
        helper.define_singleton_method(:do_pick) { |*| }
        helper.define_singleton_method(:count) { 1 }
        helper.define_singleton_method(:picked_face) { face }
        helper.define_singleton_method(:leaf_at) { |_| face }
        helper.define_singleton_method(:path_at) { |_| [host['root'],panel,face].uniq }
        helper.define_singleton_method(:transformation_at) { |_| frame }
        view=Object.new
        view.define_singleton_method(:pick_helper) { helper }
        view.define_singleton_method(:model) { model }
        view.define_singleton_method(:camera) { model.active_view.camera }
        view.define_singleton_method(:pickray) { |*| [point+offset,normal.reverse] }
        view.define_singleton_method(:screen_coords) { |p| model.active_view.screen_coords(p) }
        screen=model.active_view.screen_coords(point)
        [view,screen.x,screen.y]
      end

      def require_isolated!(isolated:)
        return if isolated
        raise 'Native QA requires an isolated idle SketchUp session (pass isolated: true)'
      end

      def run(host_id:, door_id:, library_entry: nil, isolated: false)
        require_isolated!(isolated:isolated)
        model=Sketchup.active_model
        raise 'Placement or update active' if ModuleStudio.instance_variable_get(:@library)&.tool&.pending || UpdateWork.pending?(model)
        sources=[host_id,door_id].map { |id| model.find_entity_by_persistent_id(id) }
        raise 'Expected host and door components' unless sources.all? { |root| Assembly.container?(root) }
        library=ModuleStudio.instance_variable_get(:@library)
        preview=library.preview(library_entry) if library_entry
        before=model.entities.map { |entity| [entity.persistent_id,entity.bounds.min.to_a,entity.bounds.max.to_a] }
        selection=model.selection.to_a;definitions=model.definitions.to_a
        previous_busy=Assembly.instance_variable_get(:@busy)
        Assembly.instance_variable_set(:@busy,true)
        model.start_operation('MH QA import contact',true);operation=true
        host,door=sources.map { |root| clone_root(model,root) }
        if preview
          door.erase!
          door=library.build_instance(preview,Geom::Transformation.new)
        end
        shift=Geom::Transformation.translation([100_000/25.4,0,0])
        [host,door].each { |root| root.transform!(shift) }
        anchor={'root'=>host.persistent_id.to_s}
        geometry=ImportLinks.host_geometry(model,anchor,{})
        frame=Geom::Transformation.new(geometry['frame'])
        box=geometry['envelope'];center=3.times.map { |axis| (box[0][axis]+box[1][axis])/2 }
        inner=geometry['faces'].find { |face| face['axis']==0 && face['side']==1 && face['coordinate']<center[0] }
        raise 'No left inner panel' unless inner
        center[0]=inner['coordinate']
        point=Geom::Point3d.new(center.map { |value| value/25.4 }).transform(frame)
        normal=Geom::Vector3d.new(1,0,0).transform(frame).normalize
        cavity,seed=ImportLinks.ray_cavity(model,geometry,point,normal)
        raise 'No ray cavity' unless cavity
        rule,values=AssemblyParameters.data(door)
        snapshot,=Reader.live(door,label:'QA',parameter:Runtime.read_parameter(rule,values))
        data=preview || {'snapshot'=>snapshot,'rule'=>rule,'values'=>values}
        placement={'mode'=>'cavity','anchor'=>anchor,'bounds'=>cavity,'frame'=>frame.to_a}
        report={'cavity_mm'=>cavity,'seed_mm'=>seed,'source_mm'=>snapshot['envelope']}
        automatic=Core.copy_data(data)
        automatic['import_template']=ImportTemplate.defaults.merge('enabled'=>true,'role'=>'door','mode'=>'auto')
        inset=ImportLinks.detect(automatic,*detection_view(model,geometry,inner))
        raise 'Inside panel pick was not inset' unless inset && inset['kind']=='inside'
        report['inset_matches']=inset['matches'].length
        door.transformation=LibraryPlacement.fit_built(door,inset)
        LibraryPlacement.resize(door,inset)
        report['inset_fit']='passed'
        front=geometry['faces'].find { |f| f['axis']==1 && f['side']==0 }
        exterior=ImportLinks.detect(automatic,*detection_view(model,geometry,front))
        raise 'Front pick was not outside' unless exterior && exterior['kind']=='outside'
        raise 'Full front highlight missing' unless exterior['highlight_faces']&.length==1 && exterior['highlight_faces'].first['triangles'].length==6
        raise 'Door is not linked to host module' unless exterior['matches'].all? { |match| match.dig('target','anchor','level')=='module' }
        report['outside_highlight_vertices']=exterior['highlight_faces'].first['points'].length
        begin
          placement=LibraryPlacement.fitted_placement(door,data,placement)
          door.transformation=LibraryPlacement.fit_built(door,placement)
          LibraryPlacement.resize(door,placement)
          report['fit']='passed'
        rescue StandardError=>error
          report['fit_error']=error.message
        end
        transform=frame.inverse*door.transformation
        report['measured_mm']=Frames.box(8.times.map { |index| door.definition.bounds.corner(index).transform(transform).to_a.map { |value| value*25.4 } })
        raise 'Native fit failed' if report['fit_error']
        raise 'Native target mismatch' unless Core.bounds_close?(report['measured_mm'],placement['bounds'],0.02)
        sizes=Core.dimensions(report['measured_mm'])
        scale=Frames.scale_frame(frame.to_a).values_at(0,5,10)
        report['physical_mm']=sizes.each_with_index.map { |value,axis| value*scale[axis] }
        report['transform']=door.transformation.to_a
        links=Assembly.records(model)
        original=links.select { |row| row.dig('a','root')==host_id.to_s && row.dig('b','root')==door_id.to_s }
        copies=Core.copy_data(original)
        copies.each do |row|
          row['id']='qa-'+row['id'];row['a']['root']=host.persistent_id.to_s;row['b']['root']=door.persistent_id.to_s
        end
        AssemblyContainers.store(model,links+copies)
        door.erase!
        dangling=AssemblyContainers.dangling_door_links(model)
        surviving=Assembly.records(model)
        targets=ImportLinks.release_targets(model,dangling,surviving)
        started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ImportLinks.apply_reservations(model,surviving,external_geometry:true,targets:targets)
        report['restore_ms']=((Process.clock_gettime(Process::CLOCK_MONOTONIC)-started)*1000).round(2)
        report['restored_depth_mm']=Assembly.projection(host,[0,1,0]).then { |low,high| high-low }
        expected=original.first&.dig('import_link','host_target_mm')
        raise 'Deleted door host did not restore' if expected && (report['restored_depth_mm']-expected).abs>0.02
        report
      ensure
        model.abort_operation if operation
        Assembly.instance_variable_set(:@busy,previous_busy) if operation
        if before
          raise 'Model geometry changed by QA' unless before==model.entities.map { |entity| [entity.persistent_id,entity.bounds.min.to_a,entity.bounds.max.to_a] }
          raise 'Selection changed by QA' unless selection==model.selection.to_a
          raise 'Definitions changed by QA' unless definitions==model.definitions.to_a
        end
      end

      # Exercise the actual observer/worker/timer path. Only owned copies and
      # their temporary records are committed; finish removes them again.
      def start_deletion(host_id:,door_id:,isolated: false)
        require_isolated!(isolated:isolated)
        raise 'QA already running' if @deletion && !@deletion['finished']
        model=Sketchup.active_model
        raise 'Update active' if UpdateWork.pending?(model)
        raise 'QA update observation unavailable' unless UpdateWork.instance_variable_get(:@watchers)&.key?(model)
        raise 'QA update observation active' if update_watcher_open?(model)
        source_host=model.find_entity_by_persistent_id(host_id);source_door=model.find_entity_by_persistent_id(door_id)
        job=nil;operation=false;setup_committed=false;host=door=nil
        begin
          with_assembly_busy(true) do
            job={'model'=>model,'owned'=>true,'finished'=>false,
                 'before'=>model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] },
                 'definitions'=>definition_ids(model),'selection'=>model.selection.to_a,'samples'=>[],
                 'link_ids'=>[],'definition_ids'=>[],'observations'=>[]}
            @deletion=job
            model.start_operation('MH QA create deletion copies',true);operation=true
            host=clone_root(model,source_host)
            job['samples'] << host
            door=clone_root(model,source_door)
            job['samples'] << door
            shift=Geom::Transformation.translation([100_000/25.4,0,0]);[host,door].each { |e| e.transform!(shift) }
            links=Assembly.records(model)
            rows=Core.copy_data(links.select { |r| r.dig('a','root')==host_id.to_s && r.dig('b','root')==door_id.to_s })
            raise 'Expected original door links' if rows.empty?
            rows.each { |r| r['id']='qa-'+r['id'];r['a']['root']=host.persistent_id.to_s;r['b']['root']=door.persistent_id.to_s }
            job['link_ids']=rows.map { |row| row['id'] }
            AssemblyContainers.store(model,links+rows)
            job['definition_ids']=new_definition_ids(model,job['definitions'])
            model.commit_operation;operation=false
            setup_committed=true
            job.merge!('target'=>rows.first.dig('import_link','host_target_mm'),'host'=>host,'door_id'=>door.persistent_id,
                       'rows'=>rows,'started'=>Process.clock_gettime(Process::CLOCK_MONOTONIC))
            # The production observer must see this transaction, not our setup.
            model.start_operation('MH QA erase copied door',true);operation=true
            door.erase!;model.commit_operation;operation=false
          end
          UI.start_timer(0.05,false) { poll_deletion }
          {'started'=>true,'door_id'=>job['door_id']}
        rescue StandardError=>error
          model.abort_operation if operation
          operation=false
          raise unless job
          if setup_committed
            cleanup_deletion(job,error.message)
          else
            job['finished']=true
            job['error']=error.message
          end
        end
      end

      def poll_deletion
        job=@deletion;return unless job && !job['finished']
        model=job['model'];elapsed=Process.clock_gettime(Process::CLOCK_MONOTONIC)-job['started']
        previous=job['last_poll'] || job['started']
        job['max_poll_gap_ms']=[job['max_poll_gap_ms'] || 0,(Process.clock_gettime(Process::CLOCK_MONOTONIC)-previous)*1000].max
        job['last_poll']=Process.clock_gettime(Process::CLOCK_MONOTONIC)
        depth=Assembly.projection(job['host'],[0,1,0]).then { |low,high| high-low }
        alive=AssemblyContainers.reference_present?(model,{'root'=>job['door_id'].to_s})
        job['observer_error']=Assembly.last_error if Assembly.last_error
        entry={'ms'=>(elapsed*1000).round(1),'depth'=>depth,'door_present'=>!!alive,'pending'=>UpdateWork.pending?(model)}
        job['observations'] << entry if job['observations'].empty? || job['observations'].last.values_at('depth','door_present','pending')!=entry.values_at('depth','door_present','pending')
        if (depth-job['target']).abs<0.02 && !UpdateWork.pending?(model)
          job['restored_ms']||=(elapsed*1000).round(1)
          return finish_deletion if elapsed*1000-job['restored_ms']>3000
        end
        return finish_deletion('Restore timed out') if elapsed>20
        UI.start_timer(0.05,false) { poll_deletion }
      rescue StandardError=>error
        finish_deletion(error.message)
      end

      def finish_deletion(error=nil)
        job=@deletion;return unless job
        cleanup_deletion(job,error)
      end

      def cleanup_deletion(job,error=nil)
        return if job['finished']
        model=job['model']
        begin
          busy=UpdateWork.pending?(model) || update_watcher_open?(model)
        rescue StandardError
          busy=true
        end
        if busy
          job['cleanup_deferred']=true
          job['error']=error if error
          UI.start_timer(0.1,false) { cleanup_deletion(job,error) }
          return
        end
        job['cleanup_deferred']=false
        operation=false
        begin
          with_assembly_busy(true) do
            model.start_operation('MH QA remove owned copies',true);operation=true
            owned=Array(job['samples']).filter_map { |e| e.persistent_id.to_s if e.valid? }
            link_ids=Array(job['link_ids'])
            records=Assembly.records(model).reject { |row| link_ids.include?(row['id']) ||
              Array(row['copies']).any? { |id| owned.include?(id.to_s) } }
            Array(job['samples']).each { |e| e.erase! if e.valid? }
            AssemblyContainers.store(model,records)
            remove_owned_definitions(model,Array(job['definition_ids']))
            model.commit_operation;operation=false
          end
          job['error']=error if error
          job['finished']=true
          job['geometry_preserved']=job['before']==model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] }
          job['selection_changed']=job['selection']!=model.selection.to_a
          job['preserved']=job['geometry_preserved'] && !job['selection_changed']
          job['reappearances']=job['observations'].count { |row| row['door_present'] }
        rescue StandardError=>cleanup_error
          model.abort_operation if operation
          operation=false
          job['error']=cleanup_error.message
          job['finished']=true
        end
      end

      def deletion_result
        @deletion&.slice('finished','error','observer_error','cleanup_deferred','target','restored_ms','max_poll_gap_ms',
                         'preserved','geometry_preserved','selection_changed','reappearances','observations')
      end
    end
  end
end

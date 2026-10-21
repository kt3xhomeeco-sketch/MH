# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeDoorPickCheck
      extend self
      def run(verify: false, transformed: false)
        model=Sketchup.active_model;Runtime.ensure_top_level(model)
        library=ModuleStudio.instance_variable_get(:@library)
        raise 'Placement active; leave it intact' if library&.tool&.pending
        before=model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] }
        definitions=model.definitions.to_a;selection=model.selection.to_a;camera=model.active_view.camera
        links=model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        previous_busy=Assembly.instance_variable_get(:@busy);Assembly.instance_variable_set(:@busy,true)
        model.start_operation('MH QA door edge picking',true);operation=true
        definition=model.definitions.add('MH QA 084 door host')
        [[[0,0,0],[18,500,800]],[[582,0,0],[600,500,800]],[[18,0,0],[582,500,18]],[[18,0,782],[582,500,800]],[[18,482,18],[582,500,782]]].each do |low,high|
          panel=definition.entities.add_group
          points=[[low[0],low[1],low[2]],[high[0],low[1],low[2]],[high[0],high[1],low[2]],[low[0],high[1],low[2]]]
          face=panel.entities.add_face(points.map { |p| p.map { |v| v/25.4 } });face.reverse! if face.normal.z<0;face.pushpull((high[2]-low[2])/25.4)
        end
        frame=Geom::Transformation.translation([100_000/25.4,0,0])
        frame*=Geom::Transformation.rotation(ORIGIN,Z_AXIS,0.4)*Geom::Transformation.scaling(-1.4,0.8,1.2) if transformed
        root=model.entities.add_instance(definition,frame);root.name='QA cabinet'
        world=lambda { |p| Geom::Point3d.new(p.map { |v| v/25.4 }).transform(root.transformation) }
        view=model.active_view;view.camera=Sketchup::Camera.new(world.call([300,-1200,400]),world.call([300,0,400]),Z_AXIS)
        view.refresh
        template=ImportTemplate.defaults.merge('enabled'=>true,'role'=>'door')
        data={'snapshot'=>{'envelope'=>[[0,0,0],[400,18,700]]},'import_template'=>template,'door_thickness'=>18}
        rows={}
        {'edge18'=>[9,0,400],'near_inside_edge'=>[24,0,400],'cavity_center'=>[300,0,400],'near_outer_edge'=>[-6,0,400],'far_from_edge'=>[90,0,400]}.each do |name,p|
          screen=view.screen_coords(world.call(p))
          if %w[near_inside_edge near_outer_edge].include?(name)
            edge=view.screen_coords(world.call([name=='near_inside_edge' ? 18 : 0,0,400]));center=view.screen_coords(world.call([300,0,400]))
            dx=center.x-edge.x;dy=center.y-edge.y;length=Math.hypot(dx,dy);sign=name=='near_inside_edge' ? 1 : -1
            screen=Geom::Point3d.new(edge.x+sign*6*dx/length,edge.y+sign*6*dy/length,0)
          end
          host=ImportLinks.capture(view,screen.x,screen.y,{})
          result=ImportLinks.detect(data,view,screen.x,screen.y,cache:{})
          rows[name]={screen:[screen.x,screen.y],capture:host && {mount:host['mount'],cavity:host['cavity']},kind:result && result['kind'],matches:result && result['matches'].length,roots:result && result['matches'].map { |m| m['target']['anchor']['root'] }.uniq}
        end
        if verify
          %w[edge18 near_inside_edge near_outer_edge].each { |name| raise "No outside door at #{name}: #{rows[name]}" unless rows[name][:kind]=='outside' && rows[name][:matches]==5 && rows[name][:roots]==[root.persistent_id.to_s] }
          %w[cavity_center far_from_edge].each { |name| raise "Lost inset at #{name}" unless rows[name][:kind]=='inside' }
        end
        if verify
          inside=Core.copy_data(data);inside['import_template']['mode']='inside'
          point=rows['near_inside_edge'][:screen]
          raise 'Explicit Inside overridden' unless ImportLinks.detect(inside,view,*point,cache:{})['kind']=='inside'
          disabled=Core.copy_data(data);disabled['import_template']['faces'].find { |slot| slot['axis']==1 && slot['side']==1 }['enabled']=false
          point=rows['near_outer_edge'][:screen]
          raise 'Disabled mount selected' if ImportLinks.detect(disabled,view,*point,cache:{})
          root.definition.entities.grep(Sketchup::Group).first.hidden=true;view.refresh
          point=rows['near_inside_edge'][:screen]
          hidden=ImportLinks.detect(data,view,*point,cache:{})
          raise 'Hidden rim used as outside mount' if hidden && hidden['kind']=='outside'
          root.definition.entities.grep(Sketchup::Group).first.hidden=false
          view.camera=Sketchup::Camera.new(world.call([300,1200,400]),world.call([300,0,400]),Z_AXIS);view.refresh
          screen=view.screen_coords(world.call([9,500,400]))
          rear=ImportLinks.detect(data,view,screen.x,screen.y,cache:{})
          raise 'Rear face used as front mounting plane' if rear && rear['kind']=='outside'
        end
        {status:verify ? 'passed' : 'baseline',pid:Process.pid,transformed:transformed,rows:rows}
      ensure
        if view && camera
          view.camera=camera;view.refresh
        end
        model.abort_operation if operation
        Assembly.instance_variable_set(:@busy,previous_busy) if model
        if before
          raise 'Geometry changed' unless before==model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] }
          raise 'Definitions changed' unless definitions==model.definitions.to_a
          raise 'Selection changed' unless selection==model.selection.to_a
          raise 'Links changed' unless links==model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        end
      end
    end
  end
end

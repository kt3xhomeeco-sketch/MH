# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeFrontDatumCheck
      extend self
      def run(host_pid:,child_pid:)
        model=Sketchup.active_model;Runtime.ensure_top_level(model)
        roots=[host_pid,child_pid].map { |pid| model.find_entity_by_persistent_id(pid) }
        raise 'Selected source modules are missing' unless roots.all? { |root| root && root.valid? }
        original=model.entities.map { |r| [r.persistent_id,r.bounds.min.to_a,r.bounds.max.to_a] };defs=model.definitions.to_a
        raw=model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        @report={'checks'=>[],'status'=>'running'}
        rows=Assembly.records(model).select { |row| row.dig('a','root')==host_pid.to_s && row.dig('b','root')==child_pid.to_s }
        model.start_operation('MH QA front datum copies',true);operation=true
        copies=roots.map do |source|
          copy=model.entities.add_instance(source.definition,Geom::Transformation.translation([100000/25.4,0,0])*source.transformation)
          source.attribute_dictionaries&.each { |dict| dict.each_pair { |key,value| copy.set_attribute(dict.name,key,value) } };copy.name=source.name;Runtime.private_tree(copy);copy
        end
        mapping=roots.zip(copies).to_h { |a,b| [a.persistent_id.to_s,b.persistent_id.to_s] }
        local=Core.copy_data(rows)
        local.each do |row|
          row['id']='qa079:'+row['id']
          AssemblyContainers::REFS.each { |key| row[key]['root']=mapping.fetch(row[key]['root']) if row[key] }
        end
        front=local.find { |row| row.dig('import_link','slot')==[1,0] };raise 'No legacy front link' unless front
        @report['before_mm']=clearance(model,front)
        check((@report['before_mm']-100.614041353).abs<0.0001,'Reproduces the selected module: displayed 100, physical front clearance 100.614041353 mm')
        prior=thicknesses(copies.last);repaired=ImportLinks.normalize_front_datums(model,local)
        check(repaired==[front] && front.dig('a','level')=='module' && front['gap']==-100,'Only the legacy front datum changes; displayed 100 mm is preserved')
        [80,100,200,100].each do |value|
          front['gap']=-value
          Assembly.solve_ordered(model,AssemblyMath.ordered(local));local.each { |row| Assembly.verify(model,row) }
          check((clearance(model,front)-value).abs<0.0001,"Actual front clearance equals #{value} mm after solve")
          check(prior==thicknesses(copies.last),'Every drawer panel retains its original physical thickness')
        end
        turn=Geom::Transformation.rotation(ORIGIN,Z_AXIS,0.47)*Geom::Transformation.scaling(-1,1,1)
        copies.each { |copy| copy.transformation=turn*copy.transformation }
        front['gap']=-80;Assembly.solve_ordered(model,AssemblyMath.ordered(local));local.each { |row| Assembly.verify(model,row) }
        check((clearance(model,front)-80).abs<0.0001,'Rotated mirrored nonuniformly scaled hosts retain actual 80 mm clearance')
        @report['final_mm']=clearance(model,front)
      rescue StandardError=>error
        @report||={};@report['error']=[error.message,*error.backtrace.first(8)]
      ensure
        model.abort_operation if operation
        ScaleRedraw.watch(model).reset;Assembly.watch(model).reset
        @report['model_retained']=model.entities.map { |r| [r.persistent_id,r.bounds.min.to_a,r.bounds.max.to_a] }==original && model.definitions.to_a==defs && model.get_attribute(Reader::DICT,AssemblyContainers::KEY)==raw
        @report['status']=@report['error'] || !@report['model_retained'] ? 'failed' : 'passed'
        folder=File.join(File.dirname(Panel.instance_method(:show).source_location.first),'outputs/front-079');FileUtils.mkdir_p(folder);File.write(File.join(folder,'native.json'),JSON.pretty_generate(@report));puts JSON.generate(@report)
      end
      def clearance(model,row)
        host=row.fetch('a').slice('root','scope').merge('path'=>[],'axis'=>1,'side'=>0)
        a=Assembly.world_plane(model,host);b=Assembly.world_plane(model,row['b'])
        -AssemblyMath.dot(AssemblyMath.sub(b['point'],a['point']),a['normal'])
      end
      def thicknesses(root)
        Reader.live(root,label:'QA thickness',parameter:nil).first['parts'].to_h do |part|
          [part['key'],Core.dimensions(part['bounds']).min.round(6)]
        end
      end
      def check(condition,label)
        raise label unless condition
        @report['checks'] << label
      end
    end
  end
end

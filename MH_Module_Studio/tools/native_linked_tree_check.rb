# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeLinkedTreeCheck
      extend self
      def run
        model=Sketchup.active_model;Runtime.ensure_top_level(model)
        original=model.entities.to_a;definitions=model.definitions.to_a
        links=Assembly.records(model)
        report={'checks'=>[],'model'=>model.title}
        model.start_operation('MH QA Linked tree',true)
        begin
          a=model.entities.add_group;a.name='QA Linked A'
          b=model.entities.add_group;b.name='QA Linked B'
          raw=model.entities.add_group;raw.name='QA Unlinked'
          [a,b,raw].each_with_index do |group,index|
            face=group.entities.add_face([0,0,0],[100,0,0],[100,100,0],[0,100,0]);face.pushpull(100)
            group.transformation=Geom::Transformation.translation([index*100,10000,0])
          end
          proposed=links+[{'id'=>'qa-tree','mode'=>'contact','gap'=>0,
            'a'=>{'root'=>a.persistent_id.to_s,'axis'=>0,'side'=>1},'b'=>{'root'=>b.persistent_id.to_s,'axis'=>0,'side'=>0}}]
          AssemblyContainers.store(model,proposed)
          tree=AssemblyTree.new(model,nil);tree.rebuild
          refs=tree.rows.filter_map { |row| row.dig('ref','root') }
          raise 'Linked roots absent' unless [a,b].all? { |e| refs.include?(e.persistent_id.to_s) }
          raise 'Unlinked root leaked' if refs.include?(raw.persistent_id.to_s)
          report['checks'] << 'Real linked groups appear; unrelated group stays absent'
          before=JSON.generate(Assembly.records(model));tree.rebuild
          raise 'Tree mutated saved links' unless before==JSON.generate(Assembly.records(model))
          report['checks'] << 'Repeated tree rebuild leaves saved links unchanged'
          a_id=a.persistent_id.to_s;b.erase!;tree.rebuild
          raise 'Deleted pair is still visible' if tree.rows.any? { |row| row['record']=='qa-tree' || row.dig('ref','root')==a_id }
          report['checks'] << 'Deleting a linked root removes the dead link and its isolated partner'
        ensure
          model.abort_operation
          ScaleRedraw.watch(model).reset;Assembly.watch(model).reset
        end
        report['model_retained']=original==model.entities.to_a && definitions==model.definitions.to_a && links==Assembly.records(model)
        raise 'Model was changed' unless report['model_retained']
        report['status']='passed'
        path=File.join(File.dirname(Panel.instance_method(:show).source_location.first),'outputs/linked-tree-075/native.json')
        FileUtils.mkdir_p(File.dirname(path));File.write(path,JSON.pretty_generate(report));report
      end
    end
  end
end

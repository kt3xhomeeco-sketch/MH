# encoding: UTF-8
require 'tmpdir'

module MH
  module ModuleStudio
    module NativeCustomInputsCheck
      extend self

      def state(root)
        rule=Core.rule!(JSON.parse(root.get_attribute(Reader::DICT,'rule_json')))
        values=JSON.parse(root.get_attribute(Reader::DICT,'parameter_values_json'))
        snapshot,=Reader.live(root,label:root.name,parameter:18.6)
        [rule,values,snapshot]
      end

      def verify(root,xuong,t)
        rule,values,snapshot=state(root)
        part=snapshot['parts'].find { |p| p['key']=='sp14_xương nẹp' }
        size=Core.dimensions(part['bounds'])
        raise 'Custom constant/thickness mismatch' unless (size[1]-xuong).abs<0.001 && (size[0]-t).abs<0.001
        raise 'Repeated plan mismatch' unless Core.plan(rule,snapshot,values)['changed_count'].zero?
      end

      def run(source_pid:)
        model=Sketchup.active_model
        source=model.find_entity_by_persistent_id(source_pid)
        raise 'Pinned source DC missing' unless source && source.definition.name=='Nẹp Bù Phải 50 #4'
        original,=Reader.live(source,label:'QA source',parameter:nil)
        original_ids=model.entities.map(&:persistent_id)
        selected=model.selection.to_a
        report={'ok'=>false,'checks'=>[]};owned=[]
        begin
          rule=StudioCalculation.build_system([original])
          sheet=Parametric.sheet(rule,original)
          row=sheet['variables'].find { |r| r['binding']=='xuong' }
          raise 'Custom variable absent/not mm' unless row && row['value']==50 && row['unit']=='mm'
          raise 'Named cell absent' unless sheet['parts'].find { |p| p['key']=='sp14_xương nẹp' }['expressions'][1]['text'].downcase.include?('xuong')
          report['checks'] << 'Fresh actual DC read displays Xuong=50 mm and a named backing formula'
          Runtime.create_model(original,rule,Parametric.targets(rule))
          root=Runtime.selected_root;owned << root
          verify(root,50,18.6)
          rows=Parametric.variables(rule)
          custom=rows.find { |r| r['binding']=='xuong' };custom['symbol']='XUONG';custom['exported']=true;custom['value']=70
          rule=Parametric.edit_variables(rule,rows)
          Runtime.update_trial(root,rule,Parametric.targets(rule))
          verify(root,70,18.6)
          [200,20,18.6].each do |t|
            Runtime.update_trial(root,rule,Parametric.targets(rule).merge('dodaytam'=>t))
            verify(root,70,t)
          end
          model.start_operation('MH QA065 Scale',true);operation=true
          root.transformation *= Geom::Transformation.scaling(1,2,1)
          ScaleRedraw.apply(model,[ScaleRedraw.prepare(root)])
          model.commit_operation;operation=false
          verify(root,70,18.6)
          report['checks'] << 'Create model, rename/edit Xuong=70, T200/20/18.6 and native Scale retain exact backing'
          Dir.mktmpdir('mh065-') do |directory|
            path=File.join(directory,'Filler.skp')
            library=Library.new
            library.export(root,path)
            data=ModuleFile.read(path)
            saved=Parametric.variables(data['rule']).find { |r| r['binding']=='xuong' }
            raise 'Saved SKP lost custom symbol/value' unless saved['symbol']=='XUONG' && data['values']['xuong']==70
            library.config['root']=directory
            library.instance_variable_set(:@catalog,LibraryCatalog.scan(directory))
            loaded=library.place(library.prepare('Filler.skp'),Geom::Point3d.new(0,0,0));owned << loaded
            verify(loaded,70,18.6)
            report['checks'] << 'SKP export/reopen/import retains custom symbol, current value and independent geometry'
          end
          report['ok']=true
        ensure
          model.abort_operation if operation
          model.start_operation('MH QA065 Cleanup',true)
          owned.reverse_each { |root| root.erase! if root.valid? }
          model.selection.clear;selected.each { |entity| model.selection.add(entity) if entity.valid? }
          model.commit_operation
          ScaleRedraw.watch(model).reset;Assembly.watch(model).reset
          after,=Reader.live(source,label:'QA source',parameter:nil)
          report['source_unchanged']=original['parts']==after['parts'] && original['dc_inputs']==after['dc_inputs'] && original_ids==model.entities.map(&:persistent_id) && selected==model.selection.to_a
          report['ok']=false unless report['source_unchanged']
          File.write(File.join(File.dirname(Panel.instance_method(:show).source_location.first),'outputs/native-065.json'),JSON.pretty_generate(report))
        end
        puts JSON.generate(report)
      end
    end
  end
end

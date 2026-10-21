# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeFillerScaleCheck
      extend self

      def spans(root)
        snapshot,=Reader.live(root,label:'QA064 scale comparison',parameter:18.6)
        snapshot['parts'].to_h { |p| [p['name'],Core.dimensions(p['bounds'])] }
      end

      def run(source_pid:)
        model=Sketchup.active_model
        source=model.find_entity_by_persistent_id(source_pid)
        raise 'Wrong pinned DC' unless source && source.definition.name=='Nẹp Bù Phải 50 #4'
        snapshot,=Reader.live(source,label:source.definition.name,parameter:nil)
        rule=StudioCalculation.build_system([snapshot])
        before=JSON.generate(snapshot)
        selected=model.selection.map(&:persistent_id)
        entity_ids=model.entities.map(&:persistent_id)
        report={'ok'=>false,'source'=>source.definition.name,'checks'=>[],'scale'=>[]}
        begin
          [[2,1,1],[1,2,1]].each do |factors|
            begin
              model.start_operation('MH QA064 Compare DC scale',true)
              dc=model.entities.add_instance(source.definition,source.transformation)
              source.attribute_dictionaries&.each { |dict| dict.each_pair { |k,v| dc.set_attribute(dict.name,k,v) } }
              dc.make_unique
              dc.definition.entities.grep(Sketchup::Group).each(&:make_unique)
              dc.transformation *= Geom::Transformation.scaling(*factors)
              $dc_observers.get_latest_class.redraw(dc)
              expected=spans(dc)
            ensure
              model.abort_operation
            end
            begin
              model.start_operation('MH QA064 Compare own scale',true)
              plan=Core.plan(rule,snapshot,'dodaytam'=>18.6)
              definition=model.definitions.add('MH QA064 Filler')
              root=model.entities.add_instance(definition,Geom::Transformation.new)
              bindings=Runtime.populate_parts(definition,plan)
              Runtime.stamp(root,rule,bindings,plan['target'])
              root.transformation *= Geom::Transformation.scaling(*factors)
              ScaleRedraw.apply(model,[ScaleRedraw.prepare(root)])
              actual=spans(root)
              raise 'Own Scale differs from source DC' unless expected.all? { |name,dims| dims.zip(actual.fetch(name)).all? { |a,b| (a-b).abs<0.001 } }
              raise 'Fixed backing 50 changed' unless (actual.fetch('SP14_Xương Nẹp')[1]-50).abs<0.001
              report['scale'] << {'factors'=>factors,'dc'=>expected,'module'=>actual}
              [200,20,18.6].each do |t|
                Runtime.apply_trial_update(root,rule,{'dodaytam'=>t})
                measured=spans(root)
                raise 'T or fixed backing changed' unless (measured.fetch('SP14_Xương Nẹp')[1]-50).abs<0.001 && (measured.fetch('SP14_Xương Nẹp')[0]-t).abs<0.001
              end
            ensure
              model.abort_operation
            end
          end
          after,=Reader.live(source,label:source.definition.name,parameter:nil)
          # Capture IDs/timestamps vary per read; the part geometry and ATT must not.
          parsed=JSON.parse(before)
          raise 'Source changed' unless parsed['parts']==after['parts'] && parsed['dc_inputs']==after['dc_inputs'] && entity_ids==model.entities.map(&:persistent_id) && selected==model.selection.map(&:persistent_id)
          report['checks'] << 'Own module matches DC redraw for X/Y Scale on independent aborted copies'
          report['checks'] << 'Backing stays 50 mm after Scale and T200/20/18.6; front follows parent LenX in both systems'
          report['checks'] << 'Source geometry, attributes, model entities and selection unchanged'
          report['ok']=true
        ensure
          ScaleRedraw.watch(model).reset;Assembly.watch(model).reset
          File.write(File.join(File.dirname(Panel.instance_method(:show).source_location.first),'outputs/native-filler-064.json'),JSON.pretty_generate(report))
        end
        puts JSON.generate(report)
      end
    end
  end
end

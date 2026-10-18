# encoding: UTF-8
require_relative 'native_replace_recovery_check'

module MH
  module ModuleStudio
    module NativeEnvelopeReplaceCheck
      include NativeReplaceRecoveryCheck
      extend self

      def recovery_fixture(library,saved)
        super
        data=library.prepare('Khung/Khung noc lot.skp')
        @model.start_operation('MH QA063 broken targets',true)
        bad=module_root('MH QA063 bad ATT',80000)
        box(bad.definition.entities,'Panel',[0,0,0],[500,400,700])
        bad.set_attribute(Reader::DICT,'trial',true)
        bad.set_attribute(Reader::DICT,'rule_json','{broken')
        bad.set_attribute(Reader::DICT,'parameter_values_json','{broken')
        bad.set_attribute('dynamic_attributes','_lenx_formula','unsupported(1/0)')
        wrapper=module_root('MH QA063 malformed wrapper',82000)
        child=box(wrapper.definition.entities,'Invalid child',[0,0,0],[500,400,700])
        child.set_attribute(Reader::DICT,'trial',true);child.set_attribute(Reader::DICT,'rule_json','{broken')
        wrapper.set_attribute(Reader::DICT,AssemblyContainers::FLAG,true)
        wrapper.set_attribute(Reader::DICT,AssemblyContainers::KEY,'{broken')
        wrapper.transformation*=Geom::Transformation.scaling(1.2,0.85,1.1)
        open=module_root('MH QA063 open shell',84000)
        shell=box(open.definition.entities,'Open',[0,0,0],[450,350,650])
        shell.definition.entities.grep(Sketchup::Face).first.erase!
        @model.commit_operation;reset
        [bad,wrapper,open].each do |old|
          desired=descriptor(old);frame=Geom::Transformation.new(desired['frame'])
          fresh=library.place(data,ORIGIN,placement:desired);@owned << fresh
          check(Core.bounds_close?(world_bounds(fresh,frame),desired['bounds'],0.02),'Envelope-only replacement ignores malformed target ATT/assembly JSON and open target geometry')
        end
        @model.start_operation('MH QA063 stale global links',true)
        orphan=module_root('MH QA063 stale global target',86000)
        box(orphan.definition.entities,'Panel',[0,0,0],[500,400,700])
        @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,'{stale-global')
        @model.commit_operation;reset
        desired=descriptor(orphan);frame=Geom::Transformation.new(desired['frame'])
        fresh=library.place(data,ORIGIN,placement:desired);@owned << fresh
        check(Core.bounds_close?(world_bounds(fresh,frame),desired['bounds'],0.02) && @model.get_attribute(Reader::DICT,AssemblyContainers::KEY)=='{stale-global','Stale global metadata is retained verbatim and cannot block detached replacement')
        @model.start_operation('MH QA063 rollback target',true)
        @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,'[]')
        tiny=module_root('MH QA063 impossible source fit',88000);box(tiny.definition.entities,'Panel',[0,0,0],[1,1,1])
        tiny.set_attribute(Reader::DICT,'trial',true);tiny.set_attribute(Reader::DICT,'rule_json','{broken')
        @model.commit_operation;reset
        before=NativeDrawerCheck.fingerprint(tiny)
        begin
          library.place(data,ORIGIN,placement:descriptor(tiny))
          raise 'Impossible source fit was accepted'
        rescue Core::Error
          check(tiny.valid? && NativeDrawerCheck.fingerprint(tiny)==before,'Failed source fit rolls back old geometry and corrupt target metadata intact')
        end
        linked_bad_target(library,data)
      end

      def linked_bad_target(library,data)
        @model.start_operation('MH QA063 linked broken target',true)
        parent=module_root('MH QA063 linked parent',90000)
        a=box(parent.definition.entities,'Fixed',[0,0,0],[200,400,700])
        definition=@model.definitions.add('MH QA063 bad linked child')
        b=parent.definition.entities.add_instance(definition,Geom::Transformation.new)
        box(definition.entities,'Old',[200,0,0],[800,400,700])
        b.set_attribute(Reader::DICT,'trial',true);b.set_attribute(Reader::DICT,'rule_json','{broken')
        parent.set_attribute(Reader::DICT,AssemblyContainers::FLAG,true)
        link={'id'=>'qa063-contact','mode'=>'contact','gap'=>0,'a'=>{'root'=>a.persistent_id.to_s,'axis'=>0,'side'=>1,'level'=>'module'},'b'=>{'root'=>b.persistent_id.to_s,'axis'=>0,'side'=>0,'level'=>'module'}}
        parent.set_attribute(Reader::DICT,AssemblyContainers::KEY,JSON.generate([link]))
        parent.transformation*=Geom::Transformation.scaling(1.1,0.9,1.2)
        @model.commit_operation;reset
        frame=parent.transformation*b.transformation
        bounds=[b.definition.bounds.min.to_a,b.definition.bounds.max.to_a].map { |point| point.map { |v| v*25.4 } }
        desired=descriptor(b);desired['anchor']['scope']=parent.persistent_id.to_s
        fresh=library.place(data,ORIGIN,placement:desired)
        check(Core.bounds_close?(world_bounds(fresh,parent.transformation.inverse*frame),bounds,0.02),'Linked scaled target with corrupt own formula is replaced without pre-redrawing the discarded module')
        Assembly.records(@model).select { |row| row['scope']==parent.persistent_id.to_s }.each { |row| Assembly.verify(@model,row) }
        check(true,'Existing valid contact survives scoped replacement of a broken target')
      end
    end
  end
end

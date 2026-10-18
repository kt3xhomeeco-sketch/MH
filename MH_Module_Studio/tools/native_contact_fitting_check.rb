# encoding: UTF-8
require_relative 'native_component_drag_check'

module MH
  module ModuleStudio
    module NativeContactFittingCheck
      include NativeComponentDragCheck
      extend self

      class DrawRecorder
        attr_reader :fills

        def initialize(view)
          @view = view
          @fills = []
        end

        def draw(mode, points)
          @fills << points if mode==GL_TRIANGLES
          @view.draw(mode,points)
        end

        def method_missing(name, *args, **kwargs, &block)
          @view.public_send(name,*args,**kwargs,&block)
        end

        def respond_to_missing?(name, include_private = false)
          @view.respond_to?(name,include_private) || super
        end
      end

      def width(entity, normal = [1,0,0])
        Assembly.projection(entity,normal).then { |low,high| high-low }
      end

      def all_valid(scope)
        Assembly.records(@model).select { |row| row['scope']==scope }.each { |row| Assembly.verify(@model,row) }
      end

      def check_live_module_copies
        sources = [450372,450864].map { |pid| @model.find_entity_by_persistent_id(pid) }
        return unless sources.all? { |entity| entity&.valid? && entity.get_attribute(Reader::DICT,'trial',false) }
        @model.start_operation('MH QA copies of current library modules',true)
        clones = sources.each_with_index.map do |source,index|
          copy = @model.active_entities.add_instance(source.definition,source.transformation)
          source.attribute_dictionaries.each { |dict| dict.each_pair { |key,value| copy.set_attribute(dict.name,key,value) } }
          copy.name = "MH QA live copy #{index}"
          Runtime.private_tree(copy)
          copy
        end
        host,target = clones
        desired = width(host)
        Assembly.resize(target,[1,0,0],desired*0.8)
        @model.commit_operation
        a = {'root'=>host.persistent_id.to_s,'path'=>[],'axis'=>0,'side'=>0}
        b = {'root'=>target.persistent_id.to_s,'path'=>[],'axis'=>0,'side'=>0}
        first = Assembly.save(@model,{'mode'=>'contact','a'=>a,'b'=>b,'gap'=>0})
        second = Assembly.save(@model,{'mode'=>'contact','a'=>first['a'].merge('side'=>1),'b'=>first['b'].merge('side'=>1),'gap'=>0})
        target = Assembly.root(@model,second['b'])
        check((width(target)-desired).abs<0.02,'Copies of the actual two library modules in the user model fit by two contact links')
        rule = Core.rule!(JSON.parse(target.get_attribute(Reader::DICT,'rule_json')))
        saved = JSON.parse(target.get_attribute(Reader::DICT,'parameter_values_json','{}'))
        snapshot, = Reader.live(target,label:'QA actual library copy',parameter:Runtime.read_parameter(rule,saved))
        check(Core.plan(rule,snapshot,saved)['changed_count'].zero?,'Actual library module remains parametrically editable after automatic fitting')
      end

      def additional_checks
        @model.start_operation('MH QA opposing contacts',true)
        host = box('MH QA Contact host',[16000,0,0],[600,500,800])
        target = box('MH QA Contact insert',[16150,100,0],[200,100,60])
        @model.commit_operation
        left = Assembly.save(@model,{'mode'=>'contact','a'=>anchor(host,0,0),'b'=>anchor(target,0,0),'gap'=>-10})
        target = Assembly.root(@model,left['b'])
        check((width(target)-200).abs<0.02,'One contact only translates and preserves target width')
        host = Assembly.root(@model,left['a'])
        host_before = state([host])
        right = Assembly.save(@model,{'mode'=>'contact','a'=>left['a'].merge('side'=>1),'b'=>left['b'].merge('side'=>1),'gap'=>-20})
        check((width(target)-570).abs<0.02,'Second opposing contact automatically expands raw target to satisfy both offsets')
        all_valid(right['scope'])
        right['gap'] = -35
        right = Assembly.save(@model,right)
        check((width(target)-555).abs<0.02,'Editing the second contact contracts target and keeps first contact')
        right['gap'] = -5
        right = Assembly.save(@model,right)
        check((width(target)-585).abs<0.02,'Repeated opposing offset edits expand target without accumulated error')
        front = Assembly.save(@model,{'mode'=>'contact','a'=>left['a'].merge('axis'=>1,'side'=>0),'b'=>left['b'].merge('axis'=>1,'side'=>0),'gap'=>-15})
        back = Assembly.save(@model,{'mode'=>'contact','a'=>left['a'].merge('axis'=>1,'side'=>1),'b'=>left['b'].merge('axis'=>1,'side'=>1),'gap'=>-25})
        check((width(target,[0,1,0])-460).abs<0.02 && (width(target)-585).abs<0.02,'Four contacts fit two axes together while preserving previously solved size')
        all_valid(back['scope'])
        check(host_before==state([host]),'Contact fitting leaves reference module geometry and transform unchanged')
        wrapper = AssemblyContainers.wrapper(@model,right['scope'])
        @model.start_operation('MH QA copy contact fit',true)
        copy = @model.active_entities.add_instance(wrapper.definition,Geom::Transformation.rotation(ORIGIN,Z_AXIS,Math::PI/6))
        wrapper.attribute_dictionaries.each { |dict| dict.each_pair { |key,value| copy.set_attribute(dict.name,key,value) } }
        @model.commit_operation
        copied = Assembly.records(@model).find { |row| row['scope']==copy.persistent_id.to_s && AssemblyContainers.local_id(row['id'])==AssemblyContainers.local_id(right['id']) }
        copied['gap'] = -45
        copied = Assembly.save(@model,copied)
        copied_target = Assembly.root(@model,copied['b'])
        check((width(copied_target)-545).abs<0.02 && (width(target)-585).abs<0.02,'Rotated copied assembly refits independently and preserves original target size')
        all_valid(copied['scope'])
        @model.start_operation('MH QA new link on a shared copied component',true)
        fresh = @model.active_entities.add_instance(wrapper.definition,Geom::Transformation.translation([0,4000.0/25.4,0]))
        wrapper.attribute_dictionaries.each { |dict| dict.each_pair { |key,value| fresh.set_attribute(dict.name,key,value) } }
        @model.commit_operation
        shared = Assembly.records(@model).find { |row| row['scope']==fresh.persistent_id.to_s && AssemblyContainers.local_id(row['id'])==AssemblyContainers.local_id(right['id']) }
        added = Assembly.save(@model,{'mode'=>'contact','a'=>shared['a'].merge('axis'=>2,'side'=>0),'b'=>shared['b'].merge('axis'=>2,'side'=>0),'gap'=>-7})
        check(added['scope']==fresh.persistent_id.to_s && fresh.definition!=wrapper.definition,'New contact on a shared copied component remaps references and persists in that copy')
        all_valid(added['scope'])
        before = [state([target]),JSON.generate(Assembly.records(@model))]
        begin
          Assembly.save(@model,front.reject { |key,_value| key=='id' }.merge('gap'=>-75))
          raise 'Incompatible duplicate face accepted'
        rescue Core::Error => detail
          check(!detail.message.include?('Quy tắc xung đột:') && before==[state([target]),JSON.generate(Assembly.records(@model))],'Genuine same-face conflict gives readable error and rolls back geometry and rules')
        end
        impossible = right.merge('gap'=>-900)
        begin
          Assembly.save(@model,impossible)
          raise 'Negative fitted size accepted'
        rescue Core::Error
          check(before==[state([target]),JSON.generate(Assembly.records(@model))],'Impossible opposing-face span aborts without corrupting the placed module')
        end
        view = DrawRecorder.new(@model.active_view)
        tool = AssemblyTool.new
        tool.load_record(right)
        tool.draw(view)
        check(tool.error.nil? && view.fills.length==2 && view.fills.all? { |points| points.length==6 },'Native A and B draw translucent face triangles as well as outlines')
        cabinet = own('MH QA Contact ATT host')
        insert = own('MH QA Contact ATT insert')
        first = Assembly.save(@model,{'mode'=>'contact','a'=>own_anchor(cabinet,'Hông Trái',1),'b'=>own_anchor(insert,'Hông Trái',0),'gap'=>3})
        second = Assembly.save(@model,{'mode'=>'contact','a'=>first['a'].merge('part'=>own_anchor(Assembly.root(@model,first['a']),'Hông Phải',0)['part'],'side'=>0),
          'b'=>first['b'].merge('part'=>own_anchor(Assembly.root(@model,first['b']),'Hông Phải',1)['part'],'side'=>1),'gap'=>3})
        insert = Assembly.root(@model,second['b'])
        cabinet = Assembly.root(@model,second['a'])
        check((width(insert)-556.8).abs<0.02,'Two contact links fit an owned ATT target without an explicit Fit mode')
        outer = Assembly.plane(@model,first['b'].merge('side'=>0))
        inner = Assembly.plane(@model,first['b'].merge('side'=>1))
        thickness = AssemblyMath.dot(AssemblyMath.sub(inner['point'],outer['point']),inner['normal']).abs
        check((thickness-18.6).abs<0.02,'Automatic opposing contact fit preserves the 18.6 mm panel thickness')
        host_rule = Core.rule!(JSON.parse(cabinet.get_attribute(Reader::DICT,'rule_json')))
        Runtime.update_trial(cabinet,host_rule,{'dayvan'=>25})
        Assembly.transact(@model,Assembly.records(@model))
        check((width(insert)-544).abs<0.02,'Changing reference panel thickness refits both persistent contacts')
        all_valid(second['scope'])
        # Target anchors on inner faces have fixed thickness offsets. A naive
        # ratio of the two face distances would scale those offsets incorrectly.
        current = Assembly.records(@model).find { |row| row['id']==first['id'] }
        current['b']['side'] = 1
        Assembly.save(@model,current)
        second['b']['side'] = 0
        second = Assembly.save(@model,second)
        check((width(insert)-581.2).abs<0.02,'Inset target faces use measured ATT response rather than raw bounding-box scale')
        all_valid(second['scope'])
        check_live_module_copies
      end
    end
  end
end

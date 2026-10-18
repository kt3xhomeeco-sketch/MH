# encoding: UTF-8
require_relative 'native_contact_fitting_check'

module MH
  module ModuleStudio
    module NativeGroupOptionsCheck
      include NativeContactFittingCheck
      extend self

      def option_change(options, id, value)
        options.request('action'=>'change','root_pid'=>@model.selection.first.persistent_id.to_s,
          'token'=>options.instance_variable_get(:@token),'variable_id'=>id,'value'=>value)
      end

      def member_values(wrapper)
        AssemblyContainers.members(wrapper).select { |entity| entity.get_attribute(Reader::DICT,'trial',false) }.map do |entity|
          JSON.parse(entity.get_attribute(Reader::DICT,'parameter_values_json'))
        end
      end

      def additional_checks
        super
        a = own('MH QA Options A'); b = own('MH QA Options B')
        rule = Core.rule!(JSON.parse(b.get_attribute(Reader::DICT,'rule_json')))
        Runtime.update_trial(b,rule,{'dayvan'=>20})
        fit = Assembly.save(@model,{'mode'=>'fit','a'=>own_anchor(a,'Hông Trái',1),'c'=>own_anchor(a,'Hông Phải',0),'b'=>own_anchor(b,'Hông Trái',0),'gap'=>3})
        wrapper = AssemblyContainers.wrapper(@model,fit['scope'])
        options = ModuleOptions.new
        options.show
        options.refresh
        rows = options.instance_variable_get(:@display_rows)
        check(rows.find { |row| row['id']=='common:T1' }&.fetch('mixed'),'Selecting linked parent exposes common T1 and mixed member values')
        check(rows.any? { |row| row['section']=='MH QA Options A' } && rows.any? { |row| row['section']=='MH QA Options B' },'Linked parent options include private parameters under each module name')
        option_change(options,'common:T1',18)
        check(member_values(wrapper).all? { |values| values['dayvan']==18 },'Common T1 edits all linked members directly from compact options')
        all_valid(fit['scope'])
        check((width(Assembly.root(@model,fit['b']))-558).abs<0.02,'Common thickness edit solves fitted dimensions in the same transaction')
        rows = options.instance_variable_get(:@display_rows)
        private_row = rows.find { |row| row['section']=='MH QA Options A' && row['targets'].first['variable_id']=='input:giang' }
        option_change(options,private_row['id'],90)
        values = member_values(wrapper)
        check(values.any? { |item| item['giang']==90 } && values.any? { |item| item['giang']==70 },'Private parameter changes only its own module while retaining assembly fit')
        @model.start_operation('MH QA copy options assembly',true)
        copy = @model.active_entities.add_instance(wrapper.definition,Geom::Transformation.translation([0,6000.0/25.4,0]))
        wrapper.attribute_dictionaries.each { |dict| dict.each_pair { |key,value| copy.set_attribute(dict.name,key,value) } }
        @model.selection.clear; @model.selection.add(copy)
        @model.commit_operation
        options.refresh
        option_change(options,'common:T1',19)
        check(member_values(copy).all? { |item| item['dayvan']==19 } && member_values(wrapper).all? { |item| item['dayvan']==18 },'Common edit on copied assembly isolates definitions and preserves original')
        Sketchup.undo
        check(member_values(copy).all? { |item| item['dayvan']==18 },'One Undo restores all member parameters and fitted geometry together')
        options.refresh
        option_change(options,'common:T1',19)
        stale = options.instance_variable_get(:@token)
        options.refresh
        begin
          options.request('action'=>'change','root_pid'=>copy.persistent_id.to_s,'token'=>stale,'variable_id'=>'common:T1','value'=>17)
          raise 'Stale option packet accepted'
        rescue Core::Error
          check(member_values(copy).all? { |item| item['dayvan']==19 },'Stale option token cannot change a copied assembly')
        end
        members = options.instance_variable_get(:@members).values
        jobs = members.each_with_index.map do |item,index|
          [Core.copy_data(item['anchor']),item['rule'],{'dayvan'=>index.zero? ? 18 : -5}]
        end
        begin
          Assembly.transact(@model,Assembly.records(@model),updates:jobs)
          raise 'Invalid second member update accepted'
        rescue Core::Error
          check(member_values(copy).all? { |item| item['dayvan']==19 },'Failed second-member geometry update rolls back the first member too')
        end
        @model.active_path = [wrapper]
        member = AssemblyContainers.members(wrapper).find { |entity| entity.get_attribute(Reader::DICT,'trial',false) }
        @model.selection.clear; @model.selection.add(member)
        options.refresh
        option_change(options,'input:dayvan',17.6)
        check((JSON.parse(member.get_attribute(Reader::DICT,'parameter_values_json'))['dayvan']-17.6).abs<0.000001,'Single member remains editable from options inside its linked component')
        @model.active_path = nil
        @model.start_operation('MH QA merged layered library module',true)
        definition = @model.definitions.load('D:/Cong viec/Sketchup/DC/Modul_studio/Canh/1.CA Cánh Viền Nẹp.skp')
        layered = @model.active_entities.add_instance(definition,Geom::Transformation.new)
        layered.name = 'MH QA Merged T2'
        Runtime.private_tree(layered)
        data = LibraryCatalog.payload(layered.definition.get_attribute(Reader::DICT,LibraryCatalog::PAYLOAD_KEY))
        _snapshot,bindings = Library.new.validate_geometry(layered,data)
        Runtime.stamp(layered,data['rule'],bindings,data['values'])
        @model.selection.clear; @model.selection.add(layered)
        @model.commit_operation
        options.refresh
        t2 = options.instance_variable_get(:@display_rows).find { |row| row['symbol']=='T2' }
        check(options.instance_variable_get(:@display_rows).count { |row| row['symbol']=='T2' }==1,'Merged layered library module exposes one T2 variable for both original thickness inputs')
        option_change(options,t2['id'],12)
        option_change(options,t2['id'],14)
        values = JSON.parse(layered.get_attribute(Reader::DICT,'parameter_values_json'))
        check(values['a0van']==14 && values['c1']==14 && (width(layered,[0,1,0])-24).abs<0.02,'Merged T2 edits both panel inputs repeatedly while preserving original envelope and source joint')
      ensure
        options&.instance_variable_get(:@dialog)&.close
      end
    end
  end
end

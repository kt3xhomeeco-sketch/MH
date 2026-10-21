# encoding: UTF-8
module MH
  module ModuleStudio
    # Group master identity and parameter propagation. No geometry algebra.
    module AssemblyParameters
      extend self
      KEY='assembly_master_key_v1'.freeze

      def set_master(model,component,seed)
        return if component.get_attribute(Reader::DICT,KEY)
        anchor=seed['a'] || seed['b']
        member=Assembly.root(model,anchor)
        return unless AssemblyContainers.members(component).include?(member)
        component.set_attribute(Reader::DICT,KEY,AssemblyContainers.member_key(member))
      end

      def data(entity)
        return unless entity.get_attribute(Reader::DICT,'trial',false)
        [UpdateWork.rule(entity.get_attribute(Reader::DICT,'rule_json')),JSON.parse(entity.get_attribute(Reader::DICT,'parameter_values_json','{}'))]
      end

      def synchronize(model)
        growth={}
        AssemblyContainers.containers(model).each do |component|
          key=component.get_attribute(Reader::DICT,KEY)
          next unless key
          members=AssemblyContainers.members(component)
          master=members.find { |entity| entity.get_attribute(Reader::DICT,AssemblyContainers::MEMBER)==key }
          source=master && data(master)
          next unless source
          values=ImportTemplate.thickness_values(*source)
          members.each do |member|
            next if member==master
            own=data(member);next unless own
            edited=ImportTemplate.synchronize(*own,values)
            next unless edited
            before=Core.dimensions(AssemblyEnvelope.bounds(member))
            Runtime.apply_trial_update(member,edited,Parametric.targets(edited))
            scope=component.persistent_id.to_s
            growth[scope]=Array(growth[scope]) | AssemblyEnvelope.changing_axes(member,edited,before)
          end
        end
        growth
      end
    end
  end
end

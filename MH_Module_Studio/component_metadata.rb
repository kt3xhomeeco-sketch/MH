# encoding: UTF-8
require 'digest'
module MH
  module ModuleStudio
    # A definition carries a reusable seed; live instance identity stays on its root.
    module ComponentMetadata
      extend self
      KEY='component_seed_v1'.freeze
      # `seed_json` is prepared by an active UpdateWork worker. It is metadata
      # only; the definition remains the native owner of the committed value.
      def store(root,seed_json: nil)
        return unless root.respond_to?(:definition) && root.definition.respond_to?(:set_attribute)
        return unless root.get_attribute(Reader::DICT,'trial',false)
        job=UpdateWork.context if defined?(UpdateWork)
        seed_json=job[:seeds][root.persistent_id] if job && seed_json.nil?
        unless seed_json
          seed=%w[rule_json parameter_values_json formula_envelope_json].to_h { |key| [key,root.get_attribute(Reader::DICT,key)] }.compact
          return unless seed['rule_json'].is_a?(String) && seed['parameter_values_json'].is_a?(String)
          seed_json=JSON.generate(seed)
        end
        root.definition.set_attribute(Reader::DICT,KEY,seed_json) unless root.definition.get_attribute(Reader::DICT,KEY)==seed_json
        job[:seeds][root.persistent_id]=seed_json if job
        pid=root.definition.persistent_id.to_s
        root.set_attribute(Reader::DICT,'definition_pid',pid) unless root.get_attribute(Reader::DICT,'definition_pid')==pid
      end
      def source(root)
        raw=root.definition.get_attribute(Reader::DICT,KEY)
        if raw.is_a?(String) && raw.bytesize<=16*1024*1024
          seed=JSON.parse(raw);rule=JSON.parse(seed.fetch('rule_json'));values=JSON.parse(seed.fetch('parameter_values_json'))
          return [rule,values,seed['formula_envelope_json']]
        end
        raw=root.definition.get_attribute(Reader::DICT,LibraryCatalog::PAYLOAD_KEY)
        return unless raw.is_a?(String)
        data=LibraryCatalog.payload(raw)
        return unless data['format']=='mh_module_library'
        [data['rule'],data['values'],nil]
      end
      def pending?(root)
        definition=root.definition
        return false unless definition.get_attribute(Reader::DICT,KEY) || definition.get_attribute(Reader::DICT,LibraryCatalog::PAYLOAD_KEY)
        unless root.get_attribute(Reader::DICT,'trial',false)
          owner=UpdateWork.context if defined?(UpdateWork)
          seed=owner && owner[:seeds]&.fetch(root.persistent_id,nil)
          return false if seed
          return !source(root).nil?
        end
        previous=root.get_attribute(Reader::DICT,'definition_pid')
        return previous!=definition.persistent_id.to_s if previous
        legacy_rule_id(definition)!=root.get_attribute(Reader::DICT,'rule_id')
      end
      def legacy_rule_id(definition)
        raw=definition.get_attribute(Reader::DICT,KEY) || definition.get_attribute(Reader::DICT,LibraryCatalog::PAYLOAD_KEY)
        return unless raw.is_a?(String) && raw.bytesize<=16*1024*1024
        key=Digest::SHA256.hexdigest(raw);@legacy_ids||={}
        return @legacy_ids[key] if @legacy_ids.key?(key)
        data=JSON.parse(raw)
        id=data['rule_json'] ? JSON.parse(data['rule_json'])['id'] : data.dig('rule','id')
        @legacy_ids.shift while @legacy_ids.length>=256
        @legacy_ids[key]=id
      end
    end
  end
end

# encoding: UTF-8
module MH
  module ModuleStudio
    # Materialize a portable leaf-copy plan inside the caller's transaction.
    module CopyRuntime
      extend self

      def prepare(bindings,plan)
        Array(plan['copy_add']).each do |entry|
          source = bindings.fetch(entry['source']); original = source.fetch(:entity)
          raise Core::Error,'Copies hiện hỗ trợ chi tiết không có nhóm lồng.' if original.definition.entities.any? { |entity| Assembly.container?(entity) }
          copy = original.is_a?(Sketchup::Group) ? original.copy : original.parent.entities.add_instance(original.definition,original.transformation)
          original.attribute_dictionaries&.each { |dict| dict.each_pair { |key,value| copy.set_attribute(dict.name,key,value) } }
          copy.make_unique
          copy.name = entry['name']; copy.material = original.material; copy.layer = original.layer
          copy.set_attribute(Reader::DICT,'part_key',entry['key']); copy.hidden = original.hidden?
          bindings[entry['key']] = source.merge(entity:copy,visibility_path:Array(source[:visibility_path])[0...-1]+[copy])
        end
      end

      def finish(bindings,plan)
        Array(plan['copy_remove']).each do |key|
          bindings.fetch(key).fetch(:entity).erase!
          bindings.delete(key)
        end
      end
    end
  end
end

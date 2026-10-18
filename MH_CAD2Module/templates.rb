# frozen_string_literal: true

require 'digest'

module MH
  module CAD2Module
    module Templates
      module_function

      def replace(path)
        product, old = Corrections.selected_module
        root = Settings.library('library' => product.get_attribute(Model::DICT, 'library'))
        hash = Digest::SHA256.file(path).hexdigest
        stored = File.join(root, 'templates', "#{hash}.skp")
        FileUtils.mkdir_p(File.dirname(stored))
        FileUtils.cp(path, stored) unless File.file?(stored)
        mod = Model.state(product)['modules'].find { |row| row['entity_id'] == old.persistent_id }
        Corrections.transact('thay module mẫu') do
          definition = product.model.definitions.load(stored)
          candidate = product.definition.entities.add_instance(definition, Geom::Transformation.new)
          candidate.make_unique
          parametric = restore_studio(candidate)
          fit(candidate, mod, parametric)
          group = product.definition.entities.add_group
          group.entities.add_instance(candidate.definition, Geom::Transformation.new)
          group.transformation = candidate.transformation
          candidate.erase!
          candidate = group
          product.definition.entities.place(candidate) if product.is_a?(Assembly)
          candidate.name = old.name
          candidate.set_attribute(Model::DICT, 'role', 'module')
          candidate.set_attribute(Model::DICT, 'module_id', mod['id'])
          candidate.set_attribute(Model::DICT, 'template_hash', hash)
          candidate.set_attribute(Model::DICT, 'source_module', old.get_attribute(Model::DICT, 'source_module', '{}'))
          old.erase!
        end
      end

      def restore_studio(instance)
        return false unless defined?(MH::ModuleStudio::LibraryImport) && defined?(MH::ModuleStudio::ScaleRedraw)
        studio = MH::ModuleStudio
        raw = instance.definition.get_attribute(studio::Reader::DICT, studio::LibraryCatalog::PAYLOAD_KEY)
        return false unless raw
        data = studio::LibraryImport.new.payload(raw)
        raise ArgumentError, 'Mẫu assembly cần được mở và chỉnh trong MH Module Studio trước.' unless data['format'] == 'mh_module_library'
        studio::Runtime.private_tree(instance)
        library = studio::Library.new
        _snapshot, bindings, normalization = library.validate_geometry(instance, data, recover: true)
        studio::Runtime.apply_plan(bindings, normalization)
        studio::Runtime.stamp(instance, data['rule'], bindings, normalization['target'])
        studio::Runtime.verify_result(instance, normalization)
        true
      end

      def fit(instance, mod, parametric)
        bounds = instance.definition.bounds
        size = [bounds.width, bounds.height, bounds.depth].map(&:to_mm)
        raise ArgumentError, 'Module mẫu có chiều kích thước bằng 0.' if size.any? { |v| v < 0.1 }
        factors = 3.times.map { |i| mod['size'][i] / size[i] }
        different = factors.any? { |v| (v - 1).abs > 0.0001 }
        if different && !parametric
          raise ArgumentError, 'Mẫu SKP tĩnh khác kích thước khối. Dùng mẫu parametric đã chuyển bằng MH Module Studio để giữ độ dày ván.'
        end
        if different
          instance.transformation = Geom::Transformation.scaling(*factors)
          studio = MH::ModuleStudio
          studio::ScaleRedraw.apply(instance.model, [studio::ScaleRedraw.prepare(instance)])
        end
        local = instance.definition.bounds
        actual = Geom::BoundingBox.new
        8.times { |i| actual.add(local.corner(i).transform(instance.transformation)) }
        measured = [actual.width, actual.height, actual.depth].map(&:to_mm)
        raise ArgumentError, 'Quy tắc của mẫu chưa dựng được đúng kích thước yêu cầu.' unless 3.times.all? { |i| (measured[i] - mod['size'][i]).abs <= 0.1 }
        target = Geom::Point3d.new(mod['origin'].map(&:mm))
        instance.transform!(Geom::Transformation.translation(target - actual.min))
      end
    end
  end
end

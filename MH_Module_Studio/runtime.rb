# encoding: UTF-8
require_relative 'reader'
require_relative 'copy_runtime'
require_relative 'component_metadata'
require_relative 'guide_geometry'
require_relative 'update_work'

module MH
  module ModuleStudio
    module Runtime
      extend self

      def selected_root
        selected = Sketchup.active_model.selection.to_a
        unless selected.length == 1 && (selected.first.is_a?(Sketchup::Group) || selected.first.is_a?(Sketchup::ComponentInstance))
          raise Core::Error, 'Chọn đúng một group/component cha trong SketchUp.'
        end
        root = selected.first
        raise Core::Error, 'Module đang bị khóa.' if root.locked?
        root
      end

      def private_tree(root, depth = 0)
        raise Core::Error, 'Cấu trúc quá sâu.' if depth > 30
        raise Core::Error, 'Chi tiết bị khóa.' if root.locked?
        # Keep the readable DC name before removing DC metadata on this owned copy.
        stable_name = root.name.to_s
        if stable_name.strip.empty?
          attrs = Reader.dynamic_attributes(root.definition).merge(Reader.dynamic_attributes(root))
          stable_name = attrs['_name'].to_s
          stable_name = root.definition.name.to_s if stable_name.empty?
        end
        root.make_unique
        # The owned formula program places each child explicitly. Native glue
        # would otherwise move attached child faces again with a resized shell.
        root.glued_to = nil if root.respond_to?(:glued_to) && root.glued_to
        root.name = stable_name if root.name.to_s.strip.empty?
        root.delete_attribute('dynamic_attributes') if root.attribute_dictionary('dynamic_attributes', false)
        root.delete_attribute('abf_object_data') if root.attribute_dictionary('abf_object_data', false)
        definition = root.definition
        definition.delete_attribute('dynamic_attributes') if definition.attribute_dictionary('dynamic_attributes', false)
        definition.delete_attribute('abf_object_data') if definition.attribute_dictionary('abf_object_data', false)
        definition.entities.to_a.each do |entity|
          if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
            private_tree(entity, depth + 1)
          end
        end
      end

      def preview(root, rule, target)
        snapshot, = Reader.live(root, label: 'Module đang chọn', parameter: read_parameter(rule, target))
        UpdateWork.calculate(:plan,rule,UpdateWork.snapshot(snapshot),target)
      end

      def read_parameter(rule, target)
        return target unless %w[module_parameter_set module_rule_system].include?(rule['kind'])
        parameter = rule['parameters'].find { |entry| entry['editable'] } || rule['parameters'].find { |entry| entry['value'].is_a?(Numeric) }
        parameter && parameter['value']
      end

      def make_trial(root, rule, target)
        # Preflight first. Source DC and shared definitions are never changed.
        ensure_top_level(root.model)
        initial_plan = preview(root, rule, target)
        model = root.model
        operation = false
        model.start_operation('MH Tạo Bản Thử', true)
        operation = true
        copy = model.active_entities.add_instance(root.definition, root.transformation)
        copy.name = root.name.to_s.empty? ? 'MH Module — Bản thử' : root.name.to_s + ' — Bản thử'
        copy.material = root.material
        copy.layer = root.layer
        private_tree(copy)
        if initial_plan['multi_parameter']
          copy.set_attribute(Reader::DICT, 'parameter_values_json', JSON.generate(initial_plan['previous']))
        end
        snapshot, bindings = Reader.live(copy, label: 'Bản thử', parameter: read_parameter(rule, target))
        plan = Core.plan(rule, snapshot, target)
        apply_plan(bindings, plan,rule:rule)
        # Put the trial beside the source along its own X axis, in current editing coordinates.
        width = Core.dimensions(snapshot['envelope'])[0] / 25.4
        axis = root.transformation.xaxis
        offset = axis.clone
        offset.length = width * 1.2 / axis.normalize.transform(model.edit_transform).length
        copy.transform!(Geom::Transformation.translation(offset))
        stamp(copy, rule, bindings, plan['target'])
        verify_result(copy, plan)
        model.selection.clear
        model.selection.add(copy)
        model.commit_operation
        operation = false
        model.active_view.invalidate
        plan
      rescue StandardError
        model.abort_operation if operation
        raise
      end

      def update_trial(root, rule, target, source: nil)
        ensure_assembly_context(root.model)
        unless root.get_attribute(Reader::DICT, 'trial', false)
          raise Core::Error, 'Đây chưa phải bản thử. Dùng Tạo bản thử để giữ nguyên module/DC nguồn.'
        end
        preview(root, rule, target)
        model = root.model
        operation = false
        model.start_operation('MH Đổi Độ Dày', true)
        operation = true
        plan = apply_trial_update(root,rule,target,source:source)
        UpdateWork.commit(model)
        operation = false
        model.active_view.invalidate
        plan
      rescue UpdateWork::Deferred,UpdateWork::Prepared
        model.abort_operation if operation
        raise
      rescue StandardError
        model.abort_operation if operation
        raise
      end

      # Caller owns the transaction (single module or an entire linked assembly).
      def apply_trial_update(root, rule, target, source: nil)
        raise Core::Error,'Module chưa có bộ quy tắc riêng.' unless root.get_attribute(Reader::DICT,'trial',false)
        private_tree(root)
        snapshot, bindings = Reader.live(root, label: 'Bản thử', parameter: read_parameter(rule, target))
        plan = UpdateWork.calculate(:plan,rule,UpdateWork.snapshot(snapshot),target)
        apply_plan(bindings, plan,rule:rule)
        stamp(root, rule, bindings, plan['target'])
        verify_result(root, plan)
        if source
          root.set_attribute(Reader::DICT,'library_source_path',source.fetch('path'))
          root.set_attribute(Reader::DICT,'library_source_signature',source.fetch('signature'))
        end
        plan
      end

      def create_model(snapshot, rule, target)
        model = Sketchup.active_model
        ensure_top_level(model)
        calculation = Marshal.load(Marshal.dump(rule))
        if %w[module_parameter_set module_rule_system].include?(calculation['kind'])
          Core.set_exposed_parameters!(calculation, calculation['parameters'].select { |param| param['editable'] }.map { |param| param['key'] })
        end
        plan = Core.plan(calculation, snapshot, target)
        unless plan['parts'].all? { |part| part['box_verified'] }
          raise Core::Error, 'Tạo model hiện hỗ trợ tấm hộp đã xác minh. Module có chi tiết khác dạng hộp; dùng bản nguồn để tạo bản thử.'
        end
        selection = model.selection.to_a
        operation = false
        model.start_operation('MH Tạo Model', true)
        operation = true
        name = Core.dc_label(snapshot.fetch('dc_inputs', {})['_name'])
        name = snapshot['label'].to_s if name.empty?
        name = 'MH Module' if name.empty?
        definition = model.definitions.add(name)
        root = model.active_entities.add_instance(definition, Geom::Transformation.new)
        root.name = name
        bindings = populate_parts(definition, plan)
        stamp(root, rule, bindings, plan['target'])
        root.set_attribute(Reader::DICT, 'generated', true)
        verify_result(root, plan)
        model.selection.clear
        model.selection.add(root)
        model.commit_operation
        operation = false
        model.active_view.invalidate
        plan
      rescue StandardError
        if operation
          model.abort_operation
          model.selection.clear
          selection.each { |entity| model.selection.add(entity) if entity.valid? }
        end
        raise
      end

      def populate_parts(definition, plan)
        plan['parts'].to_h do |part|
          group = definition.entities.add_group
          group.name = part['name'].to_s
          group.hidden = part['visible'] == false
          low, high = part['bounds'].map { |point| point.map { |value| value / 25.4 } }
          x, y, z = low; a, b, c = high
          points = [[x,y,z],[a,y,z],[a,b,z],[x,b,z],[x,y,c],[a,y,c],[a,b,c],[x,b,c]]
          [[3,2,1,0],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]].each do |indices|
            face = group.entities.add_face(indices.map { |index| points[index] })
            raise Core::Error, "#{part['name']}: không dựng được mặt tấm." unless face
          end
          group.set_attribute(Reader::DICT,'part_key',part['key'])
          group.set_attribute(Reader::DICT,'visibility_flattened',true) if plan['visibility_capable']
          [part['key'], { entity: group }]
        end
      end

      def apply_plan(bindings, plan, rule: nil)
        CopyRuntime.prepare(bindings,plan)
        GuideGeometry.recover(bindings,rule,plan)
        plan['parts'].select { |part| part['changed'] }.each do |part|
          binding = bindings.fetch(part['key'])
          old = part['old_bounds']
          target = part['bounds']
          affine = Geom::Transformation.new(GeometryMotion.matrix(old, target))
          frame = Geom::Transformation.new(binding[:frame])
          local_delta = frame.inverse * affine * frame
          entities = binding[:entity].definition.entities
          # A part is its direct mesh. Descendant parts have their own absolute
          # plans; transforming their instances here would apply the move twice.
          mesh = entities.to_a.select { |entity| entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge) || defined?(Sketchup::ConstructionPoint) && entity.is_a?(Sketchup::ConstructionPoint) }
          entities.transform_entities(local_delta, mesh)
          binding[:entity].definition.invalidate_bounds
        end
        Array(plan['visibility_updates']).each do |entry|
          binding = bindings.fetch(entry['part'])
          next if binding[:visibility_flattened]
          entity = Array(binding[:visibility_path])[-1-entry['depth']]
          raise Core::Error,'Không tìm được group điều khiển ẩn/hiện; đọc lại module.' unless entity
          entity.hidden = entry['hidden']
        end
        if plan['visibility_capable']
          plan['parts'].each do |part|
            binding = bindings.fetch(part['key'])
            binding[:entity].hidden = part['visible']==false if binding[:visibility_flattened]
          end
        end
        CopyRuntime.finish(bindings,plan)
      end

      def stamp(root, rule, bindings, target)
        stamp_prepared(root,bindings,UpdateWork.calculate(:stamp,rule,target))
      end

      # Internal recipe from stamp_metadata; no cached native object or identity.
      def stamp_prepared(root,bindings,metadata)
        rule=metadata.fetch('rule');target=metadata.fetch('target')
        root.name = rule['module_name'] if rule['module_name']
        # A manually copied instance inherits attributes: PID mismatch starts a fresh instance identity.
        saved_pid = root.get_attribute(Reader::DICT, 'root_pid').to_s
        instance_id = root.get_attribute(Reader::DICT, 'instance_id').to_s
        instance_id = Core::Ids.uuid if instance_id.empty? || saved_pid != root.persistent_id.to_s
        root.set_attribute(Reader::DICT, 'trial', true)
        root.set_attribute(Reader::DICT, 'instance_id', instance_id)
        root.set_attribute(Reader::DICT, 'root_pid', root.persistent_id.to_s)
        root.set_attribute(Reader::DICT, 'rule_id', rule['id'])
        root.set_attribute(Reader::DICT, 'rule_json', metadata.fetch('rule_json'))
        if target.is_a?(Hash)
          root.set_attribute(Reader::DICT, 'parameter_values_json', metadata.fetch('values_json'))
          root.set_attribute(Reader::DICT, 'exposed_parameters_json', metadata.fetch('exposed_json'))
          root.delete_attribute(Reader::DICT, 'thickness_mm')
        else
          root.set_attribute(Reader::DICT, 'thickness_mm', target.to_f)
        end
        bindings.each do |key, binding|
          binding[:entity].name = rule['part_names'][key] if rule.dig('part_names',key)
          binding[:entity].set_attribute(Reader::DICT, 'part_key', key)
          binding[:entity].set_attribute(Reader::DICT, 'instance_id', instance_id)
        end
        ComponentMetadata.store(root,seed_json:metadata['seed_json'])
        ScaleRedraw.acknowledge(root) if defined?(ScaleRedraw)
      end

      # ScaleRedraw.prepare has validated this rule and plan. Geometry-only
      # redraw can keep identical metadata; copied instances and changed input
      # or part identities must still pass the ordinary full stamp path.
      def stamp_redraw(root, rule, bindings, target)
        id = root.get_attribute(Reader::DICT,'instance_id').to_s
        rule_json=UpdateWork.canonical_rule(rule) || JSON.generate(rule)
        values_json=target.is_a?(Hash) ? JSON.generate(target) : nil
        unchanged = !id.empty? && root.get_attribute(Reader::DICT,'trial',false) &&
          root.get_attribute(Reader::DICT,'root_pid').to_s == root.persistent_id.to_s &&
          root.get_attribute(Reader::DICT,'rule_id') == rule['id'] &&
          root.get_attribute(Reader::DICT,'rule_json') == rule_json &&
          target.is_a?(Hash) && root.get_attribute(Reader::DICT,'parameter_values_json') == values_json &&
          root.get_attribute(Reader::DICT,'exposed_parameters_json').is_a?(String) &&
          (!rule['module_name'] || root.name == rule['module_name']) && bindings.all? do |key,binding|
            entity = binding[:entity]
            entity.get_attribute(Reader::DICT,'part_key') == key && entity.get_attribute(Reader::DICT,'instance_id') == id &&
              (!rule.dig('part_names',key) || entity.name == rule['part_names'][key])
          end
        stamp(root,rule,bindings,target) unless unchanged
        ComponentMetadata.store(root,seed_json:UpdateWork.seed_json(
          'rule_json'=>rule_json,'parameter_values_json'=>values_json,
          'formula_envelope_json'=>root.get_attribute(Reader::DICT,'formula_envelope_json')
        )) if unchanged
      end

      def verify_result(root, plan)
        root.definition.invalidate_bounds
        parameter = plan['multi_parameter'] ? plan['target'].values.first : plan['target']
        actual, = Reader.live(root, label: 'Kiểm tra kết quả', parameter: parameter)
        unless DCVisibility.pending(actual,Array(plan['visibility_updates'])).empty?
          raise Core::Error,'Cờ ẩn/hiện của group sau cập nhật không khớp. Đã hủy thao tác.'
        end
        rows = actual['parts'].to_h { |part| [part['key'], part] }
        if plan['copies_capable'] && rows.keys.sort!=plan['parts'].map { |part| part['key'] }.sort
          raise Core::Error,'Số chi tiết sau Copies không khớp; đã hủy thao tác.'
        end
        plan['parts'].each do |expected|
          found = rows.fetch(expected['key'])
          unless (found['visible']!=false)==(expected['visible']!=false)
            raise Core::Error,"#{expected['name']}: ẩn/hiện sau cập nhật không khớp. Đã hủy thao tác."
          end
          unless 2.times.all? { |side| 3.times.all? { |axis| (found['bounds'][side][axis] - expected['bounds'][side][axis]).abs <= Core::TOLERANCE } }
            raise Core::Error, "#{expected['name']}: hình học sau cập nhật không khớp. Đã hủy thao tác."
          end
        end
        store_formula_envelope(root,plan['formula_envelope']) if plan['formula_envelope']
        ComponentMetadata.store(root)
      end

      def store_formula_envelope(root,bounds)
        Core.bounds!(bounds)
        frame = Frames.scale_frame((root.model.edit_transform*root.transformation).to_a)
        local = bounds.map { |point| 3.times.map { |axis| point[axis]/frame[[0,5,10][axis]] } }
        root.set_attribute(Reader::DICT,'formula_envelope_json',JSON.generate(local))
      end

      def ensure_top_level(model)
        if model.active_path && !model.active_path.empty?
          raise Core::Error, 'Để thử an toàn, thoát chế độ sửa nhóm/component rồi chọn module ở cấp model.'
        end
      end

      def ensure_assembly_context(model)
        path = model.active_path || []
        return if path.empty?
        if path.length==1 && path.first.get_attribute(Reader::DICT,'assembly_component',false) && path.first.definition.instances.length==1
          return
        end
        raise Core::Error,'Thoát nhóm đang sửa, hoặc mở đúng component liên kết riêng để chỉnh module.'
      end
    end
  end
end

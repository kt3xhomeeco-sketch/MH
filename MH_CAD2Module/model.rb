# frozen_string_literal: true

require_relative 'placement'
require_relative 'plan_profile'
require_relative 'assembly'

module MH
  module CAD2Module
    module Model
      DICT = 'MH_CAD2Module'
      module_function

      def container?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end

      def normalise(value)
        value.to_s.upcase.gsub(/SP\s*[-_]?\s*(\d+)/) { "SP#{Regexp.last_match(1).rjust(2, '0')}" }.strip
      end

      def labels(model = Sketchup.active_model)
        found = []
        walk = lambda do |entities, transform, depth|
          return if depth > 10
          entities.each do |entity|
            next unless container?(entity)
            next if entity.get_attribute(DICT, 'role')
            curic = entity.get_attribute('Curic Single-Line Text', 'text')
            name = curic || entity.name
            code = normalise(name)
            if code.match?(/\ASP\d+\z/)
              # bounds already includes this instance's own transform, but not its ancestors.
              centre = entity.bounds.center.transform(transform)
              found << { 'code' => code, 'name' => name, 'center_x' => centre.x.to_mm,
                         'id' => entity.persistent_id, 'curic' => !curic.nil? }
            else
              walk.call(entity.definition.entities, transform * entity.transformation, depth + 1)
            end
          end
        end
        walk.call(model.entities, Geom::Transformation.new, 0) # rubocop:disable SketchupSuggestions/ModelEntities -- Labels are world-level even during group editing.
        found.group_by { |label| label['code'] }.values.flat_map do |rows|
          rows.any? { |row| row['curic'] } ? rows.select { |row| row['curic'] } : rows
        end
      end

      def products(model = Sketchup.active_model)
        roots = model.entities.select { |e| container?(e) && e.get_attribute(DICT, 'role') == 'product' } # rubocop:disable SketchupSuggestions/ModelEntities -- Find owned roots outside the current edit path.
        roots + Assembly.all(model)
      end

      def product_by_id(model, id)
        products(model).find { |product| product.persistent_id.to_s == id.to_s }
      end

      def selection_entities(product)
        product.is_a?(Assembly) ? product.members : [product]
      end

      def local_transform(product, entity)
        product.is_a?(Assembly) ? product.transformation.inverse * entity.transformation : entity.transformation
      end

      def selected_product(model = Sketchup.active_model)
        roots = products(model)
        selection = model.selection.to_a
        path = Array(model.active_path)
        roots.find do |root|
          selection.include?(root) || path.include?(root) ||
            root.definition.entities.any? { |e| selection.include?(e) || path.include?(e) }
        end
      end

      def cube(entities, mod)
        Placement.validate_module(mod)
        instance = entities.add_group
        definition = instance.definition
        w, d, h = mod['size'].map(&:mm)
        face = if mod['plan_profile']
                 PlanProfile.face(definition.entities, mod['plan_profile'])
               else
                 definition.entities.add_face([0, 0, 0], [w, 0, 0], [w, d, 0], [0, d, 0])
               end
        raise ArgumentError, 'Không tạo được mặt đáy module.' unless face
        face.reverse! if face.normal.z.negative?
        face.pushpull(h)
        instance.transformation = Geom::Transformation.translation(mod['origin'].map(&:mm))
        entities.place(instance) if entities.respond_to?(:place)
        raise ArgumentError, 'Khối cong chưa kín sau khi dựng.' if mod['plan_profile'] && !instance.manifold?
        instance.name = mod.fetch('name', mod['id'])
        instance.material = Sketchup::Color.new(255, 180, 70) if mod['envelope_preview']
        instance.set_attribute(DICT, 'role', 'module')
        instance.set_attribute(DICT, 'module_id', mod['id'])
        instance.set_attribute(DICT, 'source_module', JSON.generate(mod))
        instance
      end

      def build(product, root, job_id, model = Sketchup.active_model)
        preview = Placement.validate_envelope_preview(product)
        raise ArgumentError, product['error'] || 'Phân tích chưa đủ dữ liệu để dựng.' unless product['status'] == 'ready' || preview
        product = product.merge('build_auxiliary' => Settings.read(model)['build_auxiliary'] != false,
                                'activity_id' => product['activity_id'] || Ids.uuid)
        code = normalise(product.fetch('code'))
        on_source = product.dig('placement', 'mode') == 'source_plan'
        matched = on_source ? [] : labels(model).select { |label| label['code'] == code }
        unless on_source
          raise ArgumentError, "Không có nhãn #{code} trong model. Thêm nhãn đúng mã rồi dựng lại." if matched.empty?
          raise ArgumentError, "Có #{matched.length} nhãn #{code}; cần phân biệt vị trí trước khi dựng." if matched.length > 1
        end
        raise ArgumentError, "#{code} đã được dựng. Chọn khối để sửa; không tự ghi đè kết quả cũ." if products(model).any? { |e| e.get_attribute(DICT, 'code') == code }
        raise ArgumentError, 'Thoát chế độ sửa group/component trước khi dựng.' if model.active_path
        product.fetch('modules').each { |mod| Placement.validate_module(mod) }
        (Array(product['trim_parts']) + Array(product['panel_parts'])).each { |part| Placement.validate_module(part) }
        if product['modules'].combination(2).any? { |a, b| Placement.overlap?(a, b) }
          raise ArgumentError, 'Các khối nhận dạng đang chồng nhau; cần kiểm tra trước khi dựng.'
        end
        Placement.validate_ai_product(product) unless preview
        if product['source_watch']
          begin
            SelectionSource.validate_watch(product['source_watch'], model)
          rescue StandardError => error
            checked = { 'passed' => false, 'error' => error.message }
            product['source_preflight'] = checked
            product['local_ai']['native_preflight'] = checked if product['local_ai']
            product['envelope_preview']['native_preflight'] = checked if product['envelope_preview']
            raise
          end
        end
        model.start_operation("CAD2Module: dựng #{code}", true)
        operation = true
        instance = Assembly.create(model)
        definition = instance.definition
        product['modules'].each { |mod| module_instance(definition.entities, mod) }
        if product['build_auxiliary']
          Array(product['trim_parts']).each { |part| reference_part(definition.entities, part) }
        end
        Array(product['panel_parts']).each { |part| panel_part(definition.entities, part) }
        transform = if on_source
                      Geom::Transformation.new(Placement.source_matrix(product.fetch('placement')))
                    else
                      x = Placement.base_x(matched.first['center_x'], product.fetch('bounds')[0])
                      Geom::Transformation.translation([x.mm, 0, 0])
                    end
        instance.transformation = transform
        instance.name = product['automatic_scan'] ? product['name'] : "#{code} — #{product['name']}"
        instance.set_attribute(DICT, 'role', 'product')
        instance.set_attribute(DICT, 'code', code)
        instance.set_attribute(DICT, 'analysis', JSON.generate(product))
        instance.set_attribute(DICT, 'library', root)
        instance.set_attribute(DICT, 'job_id', job_id)
        instance.set_attribute(DICT, 'activity_id', product['activity_id'])
        instance.set_attribute(DICT, 'label_id', matched.first['id']) unless on_source
        snapshot = Storage.snapshot(root, instance, "build-#{Ids.uuid}")
        Storage.event(root, 'kind' => 'build', 'code' => code, 'job_id' => job_id, 'product_id' => instance.persistent_id,
                            'analysis' => product, 'skp' => snapshot, 'model_path' => model.path)
        model.commit_operation
        operation = false
        instance
      rescue StandardError
        model.abort_operation if operation
        raise
      end

      def reference_part(entities, part)
        if part['solid_proxy'] || %w[plan_auxiliary manual_auxiliary module_side_trim edge_trim end_panel].include?(part['role'])
          part = part.merge('solid_proxy' => true)
          instance = panel_part(entities, part)
          instance.set_attribute(DICT, 'role', 'trim_reference')
          return instance
        end
        group = entities.add_group
        w, d, h = part.fetch('size').map(&:mm)
        points = [[0, 0, 0], [w, 0, 0], [w, d, 0], [0, d, 0],
                  [0, 0, h], [w, 0, h], [w, d, h], [0, d, h]]
        [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
         [0, 4], [1, 5], [2, 6], [3, 7]].each { |a, b| group.entities.add_line(points[a], points[b]) }
        group.transformation = Geom::Transformation.translation(part.fetch('origin').map(&:mm))
        entities.place(group) if entities.respond_to?(:place)
        group.name = "Nẹp đối chiếu #{part['face_width_mm']} / ván #{part['stock_thickness_mm']}"
        group.name = part['name'] if part['name']
        group.name += " — phụ #{part['owner_module_id']} #{part['side']}" if part['owner_module_id']
        group.set_attribute(DICT, 'role', 'trim_reference')
        group.set_attribute(DICT, 'owner_module_id', part['owner_module_id']) if part['owner_module_id']
        group.set_attribute(DICT, 'source_part', JSON.generate(part))
        group
      end

      def module_instance(entities, mod)
        return cube(entities, mod) unless mod['panel_parts']
        Placement.validate_module(mod)
        instance = entities.add_group
        definition = instance.definition
        mod['panel_parts'].each { |part| panel_part(definition.entities, part) }
        instance.transformation = Geom::Transformation.translation(mod['origin'].map(&:mm))
        entities.place(instance) if entities.respond_to?(:place)
        instance.name = mod.fetch('name', mod['id'])
        instance.set_attribute(DICT, 'role', 'module')
        instance.set_attribute(DICT, 'module_id', mod['id'])
        instance.set_attribute(DICT, 'source_module', JSON.generate(mod))
        instance
      end

      def panel_part(entities, part)
        if part['profile']
          Placement.validate_module(part)
          instance = entities.add_group
          definition = instance.definition
          face = definition.entities.add_face(part['profile'].map { |x, z| [x.mm, 0, z.mm] })
          raise ArgumentError, 'Không tạo được mặt tấm từ đường bao CAD.' unless face
          face.reverse! if face.normal.y.negative?
          face.pushpull(part['size'][1].mm)
          instance.transformation = Geom::Transformation.translation(part['origin'].map(&:mm))
          entities.place(instance) if entities.respond_to?(:place)
          instance.name = part.fetch('name')
        else
          instance = cube(entities, part)
        end
        instance.set_attribute(DICT, 'role', 'panel_part')
        instance.delete_attribute(DICT, 'module_id')
        instance.set_attribute(DICT, 'source_part', JSON.generate(part))
        instance.set_attribute(DICT, 'owner_part_id', part['owner_part_id']) if part['owner_part_id']
        instance.set_attribute(DICT, 'owner_module_id', part['owner_module_id']) if part['owner_module_id']
        instance
      end

      def state(product)
        transform = product.transformation
        modules = product.definition.entities.select { |e| container?(e) && e.get_attribute(DICT, 'role') == 'module' }.map do |entity|
          bounds = Geom::BoundingBox.new
          local = entity.definition.bounds
          relative = local_transform(product, entity)
          8.times { |i| bounds.add(local.corner(i).transform(relative)) }
          provenance = JSON.parse(entity.get_attribute(DICT, 'source_module', '{}'))
          if provenance['plan_profile']
            measured = PlanProfile.measured(entity, relative)
            measured ? provenance['plan_profile'] = measured['plan_profile'] : provenance.delete('plan_profile')
          end
          provenance['panel_parts'] = panel_state(entity.definition.entities) if provenance['panel_parts']
          provenance.merge('id' => entity.get_attribute(DICT, 'module_id'), 'name' => entity.name,
            'origin' => bounds.min.to_a.map { |v| v.to_mm.round(4) },
            'size' => [bounds.width, bounds.height, bounds.depth].map { |v| v.to_mm.round(4) },
            'entity_id' => entity.persistent_id, 'transform' => relative.to_a)
        end
        analysis = JSON.parse(product.get_attribute(DICT, 'analysis'))
        trims = product.definition.entities.filter_map do |entity|
          next unless container?(entity) && entity.get_attribute(DICT, 'role') == 'trim_reference'
          bounds = Geom::BoundingBox.new
          relative = local_transform(product, entity)
          8.times { |i| bounds.add(entity.definition.bounds.corner(i).transform(relative)) }
          provenance = JSON.parse(entity.get_attribute(DICT, 'source_part'))
          if provenance['plan_profile']
            measured = PlanProfile.measured(entity, relative)
            measured ? provenance['plan_profile'] = measured['plan_profile'] : provenance.delete('plan_profile')
          end
          provenance.merge(
            'origin' => bounds.min.to_a.map { |v| v.to_mm.round(4) },
            'size' => [bounds.width, bounds.height, bounds.depth].map { |v| v.to_mm.round(4) },
            'entity_id' => entity.persistent_id)
        end
        panels = panel_state(product.definition.entities, product)
        { 'modules' => modules, 'trim_parts' => trims, 'panel_parts' => panels,
          'bounds' => analysis['bounds'], 'product_transform' => transform.to_a }
      end

      def panel_state(entities, product = nil)
        entities.filter_map do |entity|
          next unless container?(entity) && entity.get_attribute(DICT, 'role') == 'panel_part'
          bounds = Geom::BoundingBox.new
          relative = product ? local_transform(product, entity) : entity.transformation
          8.times { |i| bounds.add(entity.definition.bounds.corner(i).transform(relative)) }
          JSON.parse(entity.get_attribute(DICT, 'source_part')).merge(
            'origin' => bounds.min.to_a.map { |v| v.to_mm.round(4) },
            'size' => [bounds.width, bounds.height, bounds.depth].map { |v| v.to_mm.round(4) },
            'entity_id' => entity.persistent_id)
        end
      end
    end
  end
end

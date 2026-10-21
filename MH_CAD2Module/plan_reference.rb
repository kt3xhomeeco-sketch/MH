# frozen_string_literal: true

require_relative 'cad_views'
require 'digest'

module MH
  module CAD2Module
    # A CAD reference is a separate root Group, never a correction/training box.
    module PlanReference
      module_function

      def validate(product)
        data = product.fetch('plan_reference')
        raise ArgumentError, 'Mặt bằng CAD chưa có vùng được xác nhận.' unless data['schema'] == 1 && data['view_id'] == product.dig('view_analysis', 'selected_view_id') && data['view_id']
        origin = data.fetch('source_origin_mm')
        raise ArgumentError, 'Gốc mặt bằng CAD không hợp lệ.' unless point?(origin)
        segments = data.fetch('segments')
        raise ArgumentError, 'Mặt bằng CAD rỗng hoặc quá nhiều cạnh.' unless segments.is_a?(Array) && !segments.empty? && segments.length <= 50_000
        segments.each do |segment|
          a = segment.fetch('start'); b = segment.fetch('end')
          raise ArgumentError, 'Tọa độ nét mặt bằng CAD không hợp lệ.' unless point?(a) && point?(b)
          next if segment['type'] == 'line'
          raise ArgumentError, 'Loại nét mặt bằng CAD chưa hỗ trợ.' unless segment['type'] == 'arc'
          center = segment.fetch('center'); radius = segment.fetch('radius'); sweep = segment.fetch('sweep')
          unless point?(center) && radius.is_a?(Numeric) && radius.finite? && radius.positive? && radius < 100_000 &&
                 sweep.is_a?(Numeric) && sweep.finite? && sweep.abs.positive? && sweep.abs <= 2 * Math::PI + 0.00001
            raise ArgumentError, 'Cung mặt bằng CAD không hợp lệ.'
          end
          angle = Math.atan2(a[1] - center[1], a[0] - center[0]) + sweep
          expected = [center[0] + radius * Math.cos(angle), center[1] + radius * Math.sin(angle)]
          unless (Math.hypot(a[0] - center[0], a[1] - center[1]) - radius).abs <= 0.02 && Math.hypot(b[0] - expected[0], b[1] - expected[1]) <= 0.02
            raise ArgumentError, 'Cung không khớp các điểm CAD đo được.'
          end
        end
        if data['scope'] == 'all_views'
          bounds = data.fetch('bounds_mm')
          unless product.dig('build_stages', 'plan') && product.dig('build_stages', 'elevation') &&
                 bounds.is_a?(Array) && bounds.length == 4 && point?(bounds.first(2)) && point?(bounds.last(2)) &&
                 bounds[2] > bounds[0] && bounds[3] > bounds[1] && segments.all? { |s|
                   [s['start'], s['end']].all? { |p| p[0] >= bounds[0] - 0.02 && p[0] <= bounds[2] + 0.02 && p[1] >= bounds[1] - 0.02 && p[1] <= bounds[3] + 0.02 }
                 }
            raise ArgumentError, 'Bộ CAD đủ hình chiếu chưa có phạm vi nguồn hợp lệ.'
          end
          CadViews.validate(data)
        elsif data['scope']
          raise ArgumentError, 'Phạm vi CAD đi kèm chưa được hỗ trợ.'
        end
        CadViews.validate_level(data)
        true
      end

      def point?(value)
        value.is_a?(Array) && value.length == 2 && value.all? { |v| v.is_a?(Numeric) && v.finite? && v.abs < 100_000_000 }
      end

      def view_tag(view)
        return 'MH_DWG2' if view['role'] == 'section_vertical'
        view['role'] == 'front_check' ? 'MH_DWG1' : 'MH_DWG'
      end

      def draw(entities, segments)
        segments.each do |segment|
          a = segment.fetch('start'); b = segment.fetch('end')
          if segment['type'] == 'arc'
            center = segment.fetch('center'); sweep = segment.fetch('sweep')
            point = Geom::Point3d.new(center[0].mm, center[1].mm, 0)
            axis = Geom::Vector3d.new(a[0] - center[0], a[1] - center[1], 0)
            normal = Geom::Vector3d.new(0, 0, sweep.negative? ? -1 : 1)
            entities.add_arc(point, axis, normal, segment.fetch('radius').mm, 0, sweep.abs, PlanProfile.segment_count(segment))
          else
            entities.add_line([a[0].mm, a[1].mm, 0], [b[0].mm, b[1].mm, 0])
          end
        end
        entities.grep(Sketchup::Face).each(&:erase!)
      end

      def create_view(model, product, assembly, data, view)
        child = model.entities.add_group # rubocop:disable SketchupSuggestions/ModelEntities -- Each CAD view is an independent root Group.
        draw(child.entities, view['segment_indices'].map { |i| data['segments'][i] })
        child.set_attribute(Model::DICT, 'cad_geometry_signature', geometry_signature(child))
        child.name = "#{product['code']} · #{view['id']} · #{view['title']} · #{view['plane']}"
        child.layer = model.layers.add(view_tag(view))
        child.transformation = assembly.transformation * CadViews.transform(view, data['plan_bounds_mm'])
        child.set_attribute(Model::DICT, 'role', 'plan_reference')
        child.set_attribute(Model::DICT, 'product_id', assembly.persistent_id)
        %w[code source_hash source_path activity_id plan_view_id plan_title].each { |key| child.set_attribute(Model::DICT, key, product[key]) if product[key] }
        child.set_attribute(Model::DICT, 'view_id', view['id'])
        child.set_attribute(Model::DICT, 'source_view_id', view['source_view_id']) if view['source_view_id']
        child.set_attribute(Model::DICT, 'reference_scope', 'all_views')
        child.set_attribute(Model::DICT, 'job_id', assembly.get_attribute(Model::DICT, 'job_id'))
        child.set_attribute(Model::DICT, 'plane', view['plane'])
        child.set_attribute(Model::DICT, 'alignment', view['alignment'])
        child.set_attribute(Model::DICT, 'view_role', view['role']) if view['role']
        level = view['level']
        child.set_attribute(Model::DICT, 'level_status', level['status']) if level
        child.set_attribute(Model::DICT, 'source_level_mm', level['level_mm']) if level && level['status'] == 'measured'
        child.set_attribute(Model::DICT, 'level_mm', view['z_mm']) if level && %w[measured provisional].include?(level['status'])
        child
      end

      def geometry_signature(group)
        return nil unless group.entities.all? { |e| e.is_a?(Sketchup::Edge) }
        edges = group.entities.grep(Sketchup::Edge).map do |edge|
          edge.vertices.map { |v| v.position.to_a.map { |n| n.to_mm.round(3) } }.sort
        end.sort
        Digest::SHA256.hexdigest(JSON.generate(edges))
      end

      def drawings(data)
        originals = data.fetch('views', [])
        originals + data.fetch('display_copies', []).map { |v| v.merge('segment_indices' => originals.find { |s| s['id'] == v['source_view_id'] }.fetch('segment_indices')) }
      end

      def same_transform?(a, b)
        a.to_a.zip(b.to_a).all? { |x, y| (x - y).abs < 0.000001 }
      end

      def relayout_candidates(data, old_data, assembly, existing)
        return [] unless data['display_mode'] == 'front_overlay' && old_data['scope'] == 'all_views'
        previous = drawings(old_data).to_h { |v| [v['id'], v] }
        drawings(data).filter_map do |view|
          old = previous[view['id']]; group = existing[view['id']]&.first
          next unless old && group && old['segment_indices'].map { |i| old_data['segments'][i] } == view['segment_indices'].map { |i| data['segments'][i] }
          target = assembly.transformation * CadViews.transform(view, data['plan_bounds_mm'])
          next if same_transform?(group.transformation, target)
          before = assembly.transformation * CadViews.transform(old, old_data['plan_bounds_mm'])
          { group: group, view: view, previous: old, before: before, target: target }
        end
      end

      def apply_relayout(model, changes, old_data)
        cache = {}; moved = []; skipped = []
        changes.each do |change|
          group = change[:group]
          unless !group.locked? && same_transform?(group.transformation, change[:before])
            skipped << group.persistent_id; next
          end
          actual = geometry_signature(group)
          expected = group.get_attribute(Model::DICT, 'cad_geometry_signature')
          unless expected
            segments = change[:previous]['segment_indices'].map { |i| old_data['segments'][i] }
            key = Digest::SHA256.hexdigest(JSON.generate(segments))
            expected = cache[key]
            unless expected
              scratch = model.entities.add_group # rubocop:disable SketchupSuggestions/ModelEntities -- Temporary source check inside the undoable restore operation.
              begin
                draw(scratch.entities, segments)
                expected = geometry_signature(scratch); cache[key] = expected
              ensure
                scratch.erase! if scratch&.valid?
              end
            end
          end
          unless actual && actual == expected
            skipped << group.persistent_id; next
          end
          moved << { 'id' => group.persistent_id, 'view_id' => change[:view]['id'], 'before_transform' => group.transformation.to_a, 'after_transform' => change[:target].to_a }
          group.transformation = change[:target]
          group.set_attribute(Model::DICT, 'cad_geometry_signature', expected)
          group.set_attribute(Model::DICT, 'plane', change[:view]['plane'])
          group.set_attribute(Model::DICT, 'alignment', change[:view]['alignment'])
        end
        [moved, skipped]
      end

      def create(model, product, assembly)
        validate(product)
        data = product.fetch('plan_reference')
        if data['scope'] == 'all_views'
          originals = data.fetch('views')
          drawings = originals + data.fetch('display_copies', []).map { |copy| copy.merge('segment_indices' => originals.find { |v| v['id'] == copy['source_view_id'] }.fetch('segment_indices')) }
          groups = drawings.map { |view| create_view(model, product, assembly, data, view) }
          primary = groups.find { |g| g.get_attribute(Model::DICT, 'view_id') == data['view_id'] }
          assembly.set_attribute(Model::DICT, 'plan_reference_id', primary.persistent_id)
          assembly.set_attribute(Model::DICT, 'cad_reference_ids', groups.map(&:persistent_id))
          return primary
        end
        if data['shared']
          if product['cad_reference_owner_id']
            owner = Assembly.new(model, product['cad_reference_owner_id'])
            group = shared_group(model, product, owner)
            assembly.set_attribute(Model::DICT, 'plan_reference_id', group.persistent_id)
            return group
          end
          matches = model.entities.grep(Sketchup::Group).select do |item| # rubocop:disable SketchupSuggestions/ModelEntities -- Shared CAD views are root Groups from the same build job.
            item.get_attribute(Model::DICT, 'role') == 'plan_reference' && item.get_attribute(Model::DICT, 'view_id') == data['view_id'] &&
              %w[code source_hash job_id].all? { |key| item.get_attribute(Model::DICT, key) == assembly.get_attribute(Model::DICT, key, product[key]) }
          end
          if matches.length == 1
            assembly.set_attribute(Model::DICT, 'plan_reference_id', matches.first.persistent_id)
            return matches.first
          end
          raise ArgumentError, 'Thiếu bộ CAD đủ hình chiếu của SP; không tạo riêng một mặt bằng thay thế.'
        end
        group = model.entities.add_group # rubocop:disable SketchupSuggestions/ModelEntities -- Independent reference at the same world placement as modules.
        draw(group.entities, data.fetch('segments'))
        suffix = product['plan_title'] ? " · #{product['plan_title']}" : ''
        title = product.dig('plan_reference', 'scope') == 'all_views' ? 'CAD đủ hình chiếu' : 'Mặt bằng CAD'
        group.name = "#{product['code']}_#{title}#{suffix}"
        group.layer = model.layers.add('MH_DWG')
        group.transformation = assembly.transformation * CadViews.transform(data.merge('plane' => 'XY'), [])
        group.set_attribute(Model::DICT, 'role', 'plan_reference')
        group.set_attribute(Model::DICT, 'product_id', assembly.persistent_id)
        %w[code source_hash source_path activity_id plan_view_id plan_title].each { |key| group.set_attribute(Model::DICT, key, product[key]) if product[key] }
        group.set_attribute(Model::DICT, 'view_id', product.dig('view_analysis', 'selected_view_id'))
        group.set_attribute(Model::DICT, 'reference_scope', product.dig('plan_reference', 'scope') || 'plan')
        if data['level']
          group.set_attribute(Model::DICT, 'level_status', data['level']['status'])
          group.set_attribute(Model::DICT, 'source_level_mm', data['level']['level_mm']) if data['level']['status'] == 'measured'
          group.set_attribute(Model::DICT, 'level_mm', data['z_mm']) if %w[measured provisional].include?(data['level']['status'])
        end
        assembly.set_attribute(Model::DICT, 'plan_reference_id', group.persistent_id)
        group
      end

      def shared_group(model, product, owner)
        raise ArgumentError, 'Bộ CAD dùng chung không còn sản phẩm gốc.' unless owner.valid?
        analysis = JSON.parse(owner.get_attribute(Model::DICT, 'analysis'))
        unless analysis['code'] == product['code'] && analysis['source_hash'] == product['source_hash'] && analysis.dig('plan_reference', 'scope') == 'all_views'
          raise ArgumentError, 'Bộ CAD dùng chung khác sản phẩm/phiên bản nguồn.'
        end
        matches = Array(owner.get_attribute(Model::DICT, 'cad_reference_ids')).filter_map { |id| model.find_entity_by_persistent_id(id) }.select do |g|
          g.is_a?(Sketchup::Group) && g.parent == model && g.get_attribute(Model::DICT, 'product_id') == owner.persistent_id &&
            g.get_attribute(Model::DICT, 'view_id') == product.dig('plan_reference', 'view_id') && g.get_attribute(Model::DICT, 'source_hash') == product['source_hash']
        end
        raise ArgumentError, 'Thiếu/lặp hình chiếu trong bộ CAD dùng chung; khôi phục bộ CAD trước.' unless matches.length == 1
        matches.first
      end

      def restore_missing(model, product, assembly, root)
        validate(product)
        data = product.fetch('plan_reference'); old = JSON.parse(assembly.get_attribute(Model::DICT, 'analysis'))
        unless data['scope'] == 'all_views' && old['source_hash'] == product['source_hash'] && old.dig('plan_reference', 'source_origin_mm') == data['source_origin_mm']
          raise ArgumentError, 'Mốc/phiên bản CAD đã đổi; giữ các box hiện tại, chưa tự căn bộ CAD mới.'
        end
        originals = data['views']
        drawings = originals + data.fetch('display_copies', []).map { |copy| copy.merge('segment_indices' => originals.find { |v| v['id'] == copy['source_view_id'] }['segment_indices']) }
        existing = model.entities.grep(Sketchup::Group).select do |g| # rubocop:disable SketchupSuggestions/ModelEntities -- Restore only independent CAD groups owned by this assembly.
          g.get_attribute(Model::DICT, 'role') == 'plan_reference' && g.get_attribute(Model::DICT, 'product_id') == assembly.persistent_id &&
            g.get_attribute(Model::DICT, 'source_hash') == product['source_hash']
        end.group_by { |g| g.get_attribute(Model::DICT, 'view_id') }
        raise ArgumentError, 'Có hình CAD trùng trong cùng bộ SP; chưa tự sửa.' if drawings.any? { |v| existing.fetch(v['id'], []).length > 1 }
        missing = drawings.reject { |v| existing.key?(v['id']) }
        current_ids = drawings.filter_map { |v| existing[v['id']]&.first&.persistent_id }
        primary = existing[data['view_id']]&.first
        changes = relayout_candidates(data, old.fetch('plan_reference'), assembly, existing)
        unmodified_placement = changes.any? { |c| !c[:group].locked? && same_transform?(c[:group].transformation, c[:before]) }
        return 0 if missing.empty? && !unmodified_placement && old['plan_reference'] == data && assembly.get_attribute(Model::DICT, 'cad_reference_ids') == current_ids && assembly.get_attribute(Model::DICT, 'plan_reference_id') == primary&.persistent_id
        model.start_operation("CAD2Module: khôi phục CAD #{product['code']}", true)
        operation = true
        moved, skipped = apply_relayout(model, changes, old.fetch('plan_reference'))
        packet = product.merge('activity_id' => assembly.get_attribute(Model::DICT, 'activity_id'))
        created = missing.map { |v| create_view(model, packet, assembly, data, v) }
        created.each { |g| existing[g.get_attribute(Model::DICT, 'view_id')] = [g] }
        groups = drawings.map { |v| existing.fetch(v['id']).first }
        assembly.set_attribute(Model::DICT, 'cad_reference_ids', groups.map(&:persistent_id))
        assembly.set_attribute(Model::DICT, 'plan_reference_id', groups.find { |g| g.get_attribute(Model::DICT, 'view_id') == data['view_id'] }.persistent_id)
        updated = old.merge('plan_reference' => data, 'view_analysis' => product['view_analysis'])
        assembly.set_attribute(Model::DICT, 'analysis', JSON.generate(updated))
        model.commit_operation
        operation = false
        Storage.event(root, 'kind' => 'cad_reference_restore', 'code' => product['code'], 'product_id' => assembly.persistent_id,
                            'created_ids' => created.map(&:persistent_id), 'restored_views' => missing.map { |v| v['id'] },
                            'moved_views' => moved, 'preserved_edited_ids' => skipped,
                            'before_reference' => old['plan_reference'], 'reason' => 'Restore missing CAD independently of existing module boxes.')
        created.length
      rescue StandardError
        model.abort_operation if operation
        raise
      end
    end
  end
end

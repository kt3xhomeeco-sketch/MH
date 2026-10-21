# frozen_string_literal: true

module MH
  module CAD2Module
    # A measured SP envelope does not prove the module tier arrangement.
    module ProductHeight
      module_function

      def validate(part, product)
        proof = product.fetch('product_height')
        ev = part.fetch('elevation_evidence')
        supports = proof.fetch('supports')
        low = proof.fetch('low_mm'); high = proof.fetch('high_mm')
        residual = product['unified_partial_plan'] && part['unresolved'] && part['envelope_preview'] && part['rule'] == 'partial-source-envelope-v1'
        part_low = residual ? ev['low_mm'] : low; part_high = residual ? ev['high_mm'] : high
        unless proof['status'] == 'measured' && proof['basis'] == 'linked_front_stock_envelope' &&
               proof['scope'] == 'product_envelope_only' && proof['module_tiers_measured'] == false &&
               proof['plan_view_id'] == product['plan_view_id'] && part['elevation_pending'] &&
               proof['source_signature'].to_s.match?(/\A[0-9a-f]{64}\z/) && ev['source_signature'] == proof['source_signature'] &&
               [low, high, ev['low_mm'], ev['high_mm']].all? { |v| v.is_a?(Numeric) && v.finite? } &&
               low >= -0.15 && high - low > 100 && high - low < 100_000 &&
               part_low >= low - 0.01 && part_high <= high + 0.01 && part_high > part_low &&
               RegisteredElevation.near(ev['low_mm'], part_low) && RegisteredElevation.near(ev['high_mm'], part_high) &&
               RegisteredElevation.near(part['origin'][2], part_low) && RegisteredElevation.near(part['size'][2], part_high - part_low) && !supports.empty?
          raise ArgumentError, 'Chiều cao box chưa khớp cao độ SP đo được.'
        end
        spans = supports.map do |support|
          box = support.fetch('view_box'); panels = support.fetch('panels')
          unless RegisteredElevation.box?(box) && !panels.empty? && %w[proven exact_plan_width].include?(support.dig('registration', 'status'))
            raise ArgumentError, 'Thiếu mặt đứng liên kết để đo chiều cao SP.'
          end
          panels.each do |panel|
            q = panel.fetch('box')
            unless RegisteredElevation.box?(q) && !panel['handle'].to_s.empty? && RegisteredElevation.stock?([q[2] - q[0], q[3] - q[1]].min)
              raise ArgumentError, 'Cao độ SP thiếu cặp cạnh tấm ván tiêu chuẩn.'
            end
          end
          lo = panels.map { |p| p['box'][1] }.min - box[1]
          hi = panels.map { |p| p['box'][3] }.max - box[1]
          unless panels.any? { |p| q = p['box']; q[3] - q[1] > [100, 4 * (q[2] - q[0])].max } &&
                 hi - lo >= 0.5 * (box[3] - box[1]) && RegisteredElevation.near(support['low_mm'], lo) && RegisteredElevation.near(support['high_mm'], hi)
            raise ArgumentError, 'Các tấm chưa phủ đủ chiều cao mặt đứng.'
          end
          [lo, hi, box[3] - box[1]]
        end
        unless RegisteredElevation.near(low, spans.map(&:first).min) && RegisteredElevation.near(high, spans.map { |s| s[1] }.max) &&
               spans.map(&:last).max - spans.map(&:last).min <= 0.15
          raise ArgumentError, 'Các mặt đứng chưa thống nhất cao độ SP.'
        end
        true
      end

      def refresh_preview(model, instance, product, root)
        return false unless instance.is_a?(Assembly) && product['envelope_preview'] && product['height_source'] == 'product_elevation_bounds'
        old = JSON.parse(instance.get_attribute(Model::DICT, 'analysis'))
        return false unless old['envelope_preview'] && !old['manual_boxes'] && old['height_source'] == 'provisional_default' &&
                            old['source_hash'] == product['source_hash'] && !Corrections.active? && !model.active_path
        before = Array(old['modules']).first; after = Array(product['modules']).first
        return false unless Array(old['modules']).length == 1 && Array(product['modules']).length == 1 && before['id'] == after['id'] &&
                            before['source_box'] == after['source_box'] && before['size'].first(2) == after['size'].first(2) &&
                            before['origin'].first(2) == after['origin'].first(2) && before['origin'][2].abs < 0.01 &&
                            (before['size'][2] - 1600).abs < 0.01 && !before['plan_profile'] && !before['panel_parts']
        Placement.validate_envelope_preview(product)
        group = untouched_preview_group(instance, before)
        return false unless group
        update = JSON.parse(JSON.generate(old))
        %w[modules product_height height_source height_pending bounds default_height_mm explanation warnings geometry_pipeline envelope_preview].each do |key|
          product.key?(key) ? update[key] = product[key] : update.delete(key)
        end
        model.start_operation('CAD2Module: Cao Độ Box', true)
        begin
          scale = Geom::Transformation.scaling(1, 1, after['size'][2] / before['size'][2].to_f)
          group.entities.transform_entities(scale, group.entities.to_a)
          group.definition.invalidate_bounds
          group.transformation = instance.transformation * Geom::Transformation.translation(after['origin'].map(&:mm))
          group.set_attribute(Model::DICT, 'source_module', JSON.generate(after))
          instance.set_attribute(Model::DICT, 'analysis', JSON.generate(update))
          Storage.event(root, 'kind' => 'product_height_refresh', 'code' => old['code'], 'product_id' => instance.persistent_id,
                        'activity_id' => old['activity_id'], 'before' => before, 'after' => after, 'proof' => product['product_height'])
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        true
      end

      def untouched_preview_group(instance, before, member = nil, read_only: false)
        members = instance.members
        return unless member ? members.include?(member) : members.length == 1
        group = member || members.first
        return if !read_only && (group.locked? || group.definition.instances.length != 1)
        expected = instance.transformation * Geom::Transformation.translation(before['origin'].map(&:mm))
        return unless expected.to_a.zip(group.transformation.to_a).all? { |a, b| (a - b).abs < 0.000001 }
        edges = group.entities.grep(Sketchup::Edge); faces = group.entities.grep(Sketchup::Face)
        vertices = edges.flat_map(&:vertices).uniq
        return unless edges.length == 12 && faces.length == 6 && group.entities.length == 18 && vertices.length == 8 && group.manifold?
        corners = [0, before['size'][0]].product([0, before['size'][1]], [0, before['size'][2]]).sort
        actual = vertices.map { |v| v.position.to_a.map(&:to_mm) }.sort
        return unless actual.zip(corners).all? { |a, b| a.zip(b).all? { |x, y| (x - y).abs < 0.01 } }
        group
      end
    end
  end
end

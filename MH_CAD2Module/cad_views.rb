# frozen_string_literal: true

module MH
  module CAD2Module
    # CAD inspection alignment does not grant a measured module-height proof.
    module CadViews
      module_function

      def bounds?(value)
        value.is_a?(Array) && value.length == 4 && value.all? { |v| v.is_a?(Numeric) && v.finite? && v.abs < 100_000_000 } && value[2] >= value[0] && value[3] >= value[1]
      end

      def validate_level(data)
        offset = data.fetch('xy_offset_mm', [0, 0]); z = data.fetch('z_mm', 0); level = data['level']
        unless offset.is_a?(Array) && offset.length == 2 && (offset + [z]).all? { |v| v.is_a?(Numeric) && v.finite? && v.abs < 100_000_000 }
          raise ArgumentError, 'Vị trí/cao độ CAD đi kèm không hợp lệ.'
        end
        return true if !level && z.zero?
        raise ArgumentError, 'Cao độ CAD chưa có chứng cứ.' unless level && level['view_id'] == (data['view_id'] || data['id'])
        if level['placement_basis'] == 'single_plan_zero'
          unless z.zero? && level['placement_z_mm'] == 0 && level['plan_count'] == 1
            raise ArgumentError, 'Mặt bằng duy nhất phải đặt Z=0.'
          end
          z = level.fetch('level_mm', 0) # Validate the source measurement independently of placement.
          raise ArgumentError, 'Cao độ nguồn không hợp lệ.' unless z.is_a?(Numeric) && z.finite? && z.abs < 100_000_000
        elsif level.key?('placement_basis') || level.key?('placement_z_mm')
          raise ArgumentError, 'Quy tắc đặt cao độ CAD chưa được hỗ trợ.'
        end
        if level['status'] == 'pending'
          raise ArgumentError, 'Cao độ chưa rõ phải giữ Z tạm bằng 0.' unless z.zero?
          return true
        end
        if level['status'] == 'provisional'
          base = level['base_mm']; slot = level['slot_index']
          unless level['basis'] == 'inspection_spacing' && level['spacing_mm'] == 1000 && base.is_a?(Numeric) && base.finite? && base >= 0 &&
                 slot.is_a?(Integer) && slot >= 0 && level['level_mm'] == z && (base + slot * 1000 - z).abs <= 0.01 && !level['issue'].to_s.empty?
            raise ArgumentError, 'Cao độ tạm chưa đúng quy tắc xếp cách 1000 mm.'
          end
          return true
        end
        links = level['links']
        unless level['status'] == 'measured' && level['basis'] == 'horizontal_cut_geometry' && level['level_mm'] == z && z >= -0.15 && links.is_a?(Array) && !links.empty?
          raise ArgumentError, 'Thiếu liên kết dấu cắt ngang/cao độ CAD.'
        end
        links.each do |link|
          box = link['front_box']; cut = link['cut_line']
          unless bounds?(box) && cut.is_a?(Array) && cut.length == 2 && cut.all? { |p| p.is_a?(Array) && p.length == 2 && p.all? { |v| v.is_a?(Numeric) && v.finite? } } &&
                 !link['marker_handle'].to_s.empty? && !link['front_id'].to_s.empty? && (cut[0][1] - cut[1][1]).abs <= 0.15 && (cut[0][0] - cut[1][0]).abs > 0.15 &&
                 ((cut[0][1] + cut[1][1]) / 2 - box[1] - z).abs <= 0.01 && z <= box[3] - box[1] + 0.15 && (link['level_mm'] - z).abs <= 0.01
            raise ArgumentError, 'Cao độ không khớp đường cắt ngang/mốc mặt đứng.'
          end
        end
        true
      end

      def validate(data)
        plan = data.fetch('plan_bounds_mm'); views = data.fetch('views'); segments = data.fetch('segments')
        raise ArgumentError, 'Thiếu bộ mặt bằng/hình chiếu CAD.' unless bounds?(plan) && views.is_a?(Array) && !views.empty? && views.map { |v| v['id'] }.uniq.length == views.length
        indices = []
        views.each do |view|
          validate_level(view)
          box = view.fetch('box_mm'); ids = view.fetch('segment_indices')
          raise ArgumentError, 'Phạm vi/nét hình chiếu CAD không hợp lệ.' unless bounds?(box) && ids.is_a?(Array) && !ids.empty? && ids.all? { |i| i.is_a?(Integer) && i >= 0 && i < segments.length }
          indices.concat(ids)
          ids.each do |i|
            unless [segments[i]['start'], segments[i]['end']].all? { |p| p[0] >= box[0] - 0.02 && p[0] <= box[2] + 0.02 && p[1] >= box[1] - 0.02 && p[1] <= box[3] + 0.02 }
              raise ArgumentError, 'Nét CAD nằm ngoài hình chiếu được căn.'
            end
          end
          anchor = view['anchor_box_mm']
          valid = case view['plane']
                  when 'XY' then %w[source_plan registered_plan_level provisional_plan_level unresolved].include?(view['alignment'])
                  when 'XZ', 'YZ'
                    if view['role'] == 'section_vertical'
                      bounds?(anchor) && view['alignment'] == 'section_inspection' && [true, false].include?(view['reversed_depth']) &&
                        validate_section(view, plan)
                    else
                      view['plane'] == 'XZ' && bounds?(anchor) && %w[front_check front_open front_unspecified].include?(view['role']) &&
                        %w[matched_front front_pending_alignment].include?(view['alignment']) && view['x_offset_mm'].is_a?(Numeric) &&
                        view['x_offset_mm'].finite? && view['x_offset_mm'].abs < 100_000_000
                    end
                  end
          raise ArgumentError, 'Chưa có căn cứ đặt hình chiếu vào mặt phẳng này.' unless valid
          validate_registration(view, views, data['source_origin_mm'], segments)
          raise ArgumentError, 'Mốc Y mặt cắt chưa khớp cặp ván của mặt bằng.' unless validate_depth(view, views, data['source_origin_mm'])
          if view.dig('section_position', 'basis') == 'cut_marker'
            proof = view['section_position']; front = views.find { |v| v['id'] == proof['front_id'] }
            unless front && front['plane'] == 'XZ' && front['x_offset_mm'] == proof['front_x_offset_mm'] && front['reference_family'] == view['reference_family']
              raise ArgumentError, 'Dấu cắt chưa ghép đúng mặt đứng/bộ hình.'
            end
          end
        end
        validate_display(data)
        selected = views.find { |v| v['id'] == data['view_id'] }
        if ([data] + views).any? { |v| v.dig('level', 'placement_basis') == 'single_plan_zero' } && views.count { |v| v['role'] == 'plan' } != 1
          raise ArgumentError, 'Quy tắc Z=0 chỉ áp dụng khi có một mặt bằng.'
        end
        unless indices.sort == (0...segments.length).to_a && selected && selected['plane'] == 'XY' && selected['alignment'] == 'source_plan' && selected['anchor_box_mm'] == plan
          raise ArgumentError, 'Bộ hình chiếu CAD bị thiếu/lặp nét hoặc mất mặt bằng gốc.'
        end
        true
      end

      def axis_number?(n)
        n.is_a?(Numeric) && n.finite? && n.abs < 100_000_000
      end

      def interval_present?(pair, view, axis, origin, reverse = false, segments = nil, strokes = false, slice_at = nil)
        return false unless pair.is_a?(Array) && pair.length == 2 && pair.all? { |v| axis_number?(v) }
        if strokes
          return false unless segments && (pair[0] - pair[1]).abs <= 0.15 && !reverse
          return view['segment_indices'].any? do |i|
            s = segments[i]; a = s['start']; b = s['end']
            s['type'] == 'line' && (a[axis] + origin[axis] - pair[0]).abs <= 0.15 &&
              (b[axis] + origin[axis] - pair[1]).abs <= 0.15 && (a[1 - axis] - b[1 - axis]).abs > 40
          end
        end
        panels = view.dig('cabinet_datum', 'panels') || []
        panels.any? do |panel|
          b = panel['box_mm']
          next false unless bounds?(b)
          next false if slice_at && !(b[1 - axis] + origin[1 - axis] - 0.15 <= slice_at && slice_at <= b[3 - axis] + origin[1 - axis] + 0.15)
          a, z = b[axis] + origin[axis], b[axis + 2] + origin[axis]
          a, z = -z, -a if reverse
          (pair[0] - a).abs <= 0.15 && (pair[1] - z).abs <= 0.15 &&
            [3, 6, 8, 9, 12, 15, 18, 25, 36].any? { |s| (z - a - s).abs <= 0.15 }
        end
      end

      def validate_axis_link(link, views, origin, segments = nil)
        target = views.find { |v| v['id'] == link['target_id'] }; source = views.find { |v| v['id'] == link['source_id'] }
        axes = { 'W' => [0, 0], 'D' => [1, 0], 'H' => [1, 1] }
        unless target && source && target['reference_family'] == source['reference_family'] &&
               axes[link['axis']] == [link['target_axis'], link['source_axis']] &&
               (link['basis'] != 'long_edge_chain' || link['axis'] == 'W') &&
               [1, -1].include?(link['scale']) && (link['axis'] == 'D' || link['scale'] == 1) &&
               axis_number?(link['offset_mm']) && origin.is_a?(Array) && origin.length == 2 && origin.all? { |v| axis_number?(v) }
          raise ArgumentError, 'Chuỗi ván chưa ghép đúng trục vật lý/bộ hình.'
        end
        candidates = link['candidates']; count = link['matched_pairs']; best = candidates&.first
        unless link['status'] == 'proven' && count.is_a?(Integer) && count >= 2 && best && best['matched_pairs'] == count &&
               (best['offset_mm'] - link['offset_mm']).abs <= 0.001 && best['scale'] == link['scale'] &&
               candidates.count { |c| c['matched_pairs'] == count && c['coverage'] == best['coverage'] } == 1 &&
               best['matches'].is_a?(Array) && best['matches'].length == count
          raise ArgumentError, 'Chuỗi ván còn nhiều phương án hoặc thiếu vị trí đối chiếu.'
        end
        matches = best['matches']
        validate_changed_gap(link) if link['changed_gap']
        validate_height_checks(link, views, origin, segments) if link['height_checks'] && link['height_support']
        unless matches.map { |m| m['target'] }.uniq.length == count && matches.map { |m| m['source'] }.uniq.length == count &&
               matches.all? do |m|
                 a, b = m.values_at('target', 'source')
                 interval_present?(a, target, link['target_axis'], origin, false, segments, link['basis'] == 'long_edge_chain', link['target_slice']) &&
                   interval_present?(b, source, link['source_axis'], origin, link['scale'] == -1, segments, link['basis'] == 'long_edge_chain', link['source_slice']) &&
                   2.times.all? { |i| (a[i] - b[i] - link['offset_mm']).abs <= 0.151 }
               end
          raise ArgumentError, 'Cặp cạnh không khớp độ dày/tọa độ phép ghép.'
        end
        true
      end

      def validate_height_checks(link, views, origin, segments)
        checks = link['height_checks']
        unless checks.is_a?(Array) && (2..3).cover?(checks.length) &&
               checks.all? { |c| %w[height_mm target_slice source_slice].all? { |k| axis_number?(c[k]) } && c['candidates'].is_a?(Array) } &&
               checks.map { |c| c['height_mm'] }.uniq.length == checks.length
          raise ArgumentError, 'Thiếu hai/ba cao độ đối chiếu mặt đứng.'
        end
        floors = checks.first.values_at('target_slice', 'source_slice').map { |v| v - checks.first['height_mm'] }
        unless checks.all? { |c| (c['target_slice'] - c['height_mm'] - floors[0]).abs <= 0.001 && (c['source_slice'] - c['height_mm'] - floors[1]).abs <= 0.001 }
          raise ArgumentError, 'Các lát ngang không cùng mốc cao độ hai mặt.'
        end
        offsets = []
        checks.each do |check|
          check['candidates'].each do |c|
            raise ArgumentError, 'Tọa độ phương án lát ngang không hợp lệ.' unless axis_number?(c['offset_mm']) && axis_number?(c['coverage'])
            offsets << c['offset_mm'] unless offsets.any? { |n| (n - c['offset_mm']).abs <= 0.15 }
          end
        end
        scores = offsets.map do |offset|
          votes = checks.filter_map { |c| c['candidates'].find { |p| (p['offset_mm'] - offset).abs <= 0.15 } }
          [votes.sum { |v| v['coverage'] } / checks.length, votes.length, offset]
        end.sort_by { |ratio, count, _offset| [-ratio, -count] }
        best = scores.first
        unless best && best[1] >= 2 && link['height_support'] == best[1] && (best[2] - link['offset_mm']).abs <= 0.15 &&
               scores.count { |s| (s[0] - best[0]).abs < 0.000001 && s[1] == best[1] } == 1
          raise ArgumentError, 'Các cao độ cho nhiều vị trí khớp hoặc chưa cùng xác nhận phép ghép.'
        end
        checks.each do |check|
          c = check['candidates'].find { |v| (v['offset_mm'] - link['offset_mm']).abs <= 0.15 }
          next unless c
          local = link.reject { |key, _| %w[height_checks height_support].include?(key) }.merge(check).merge(c.reject { |k, _| k == 'matches' })
          local['candidates'] = [c]; local['status'] = 'proven'
          validate_axis_link(local, views, origin, segments)
        end
        true
      end

      def validate_changed_gap(link)
        g = link['changed_gap']; a = g['target_stations']; b = g['source_stations']; i = g['break_after']
        unless a.is_a?(Array) && b.is_a?(Array) && a.length == b.length && a.length >= 4 && i.is_a?(Integer) && i >= 1 && i <= a.length - 3 &&
               (a + b).all? { |p| p.is_a?(Array) && p.length == 2 && p.all? { |v| axis_number?(v) } && p[1] >= p[0] } &&
               g['sequence_coverage'] == 1 && %w[left right].include?(g['anchor_side'])
          raise ArgumentError, 'Thiếu chuỗi hai phía của khoảng stretch.'
        end
        offsets = a.zip(b).map do |x, y|
          raise ArgumentError, 'Độ dày hai chuỗi không khớp.' unless ((x[1] - x[0]) - (y[1] - y[0])).abs <= 0.15
          ((x[0] - y[0]) + (x[1] - y[1])) / 2
        end
        changes = (0...offsets.length - 1).select { |n| (offsets[n] - offsets[n + 1]).abs > 0.15 }
        left = offsets.first(i + 1).sum / (i + 1); right = offsets.drop(i + 1).sum / (offsets.length - i - 1)
        side = i + 1 >= offsets.length - i - 1 ? 'left' : 'right'
        unless changes == [i] && (g['left_offset_mm'] - left).abs <= 0.001 && (g['right_offset_mm'] - right).abs <= 0.001 &&
               (g['gap_difference_mm'] - right + left).abs <= 0.001 && g['anchor_side'] == side &&
               (link['offset_mm'] - (side == 'left' ? left : right)).abs <= 0.001
          raise ArgumentError, 'Sai lệch không tập trung tại một khoảng nối tiếp; không tự nhận stretch.'
        end
        true
      end

      def validate_registration(view, views, origin, segments)
        axes = view['axis_registration'] || {}
        w = axes['W']
        if w && w['status'] == 'proven'
          path = w['path']; root = views.find { |v| v['id'] == w['root_id'] }
          unless root && root['role'] == 'plan' && root['reference_family'] == view['reference_family'] && w['view_id'] == view['id'] &&
                 path.is_a?(Array) && path.length <= 3 && axis_number?(w['offset_mm']) && w['scale'] == 1
            raise ArgumentError, 'Thiếu gốc mặt bằng của chuỗi ghép.'
          end
          current = root['id']; offset = 0
          path.each do |link|
            validate_axis_link(link, views, origin, segments)
            raise ArgumentError, 'Chuỗi ghép bị đứt liên kết.' unless link['target_id'] == current && link['axis'] == 'W'
            current = link['source_id']; offset += link['offset_mm']
          end
          actual = view['plane'] == 'XY' ? view['xy_offset_mm'][0] : view['x_offset_mm']
          unless current == view['id'] && (offset - w['offset_mm']).abs <= 0.001 &&
                 axis_number?(actual) && (actual - root['xy_offset_mm'][0] - offset).abs <= 0.001
            raise ArgumentError, 'Vị trí CAD không khớp chuỗi ván; không dùng vị trí hàng xem để ghép.'
          end
        end
        %w[H D].each do |axis|
          link = axes[axis]
          next unless link && link['status'] == 'proven'
          validate_axis_link(link, views, origin, segments)
          raise ArgumentError, 'Sai nguồn mặt cắt của chuỗi ghép.' unless link['source_id'] == view['id'] && link['axis'] == axis
          next unless axis == 'H'
          front = views.find { |v| v['id'] == link['target_id'] }
          unless (view['anchor_box_mm'][1] + link['offset_mm'] - front['anchor_box_mm'][1]).abs <= 0.001
            raise ArgumentError, 'Mốc sàn không khớp chuỗi ván theo chiều cao.'
          end
        end
        true
      end

      def validate_display(data)
        return true unless data.key?('display_copies') # Retain archived placements.
        views = data['views']; copies = data['display_copies']
        raise ArgumentError, 'Danh sách bản mặt cắt XOZ không hợp lệ.' unless copies.is_a?(Array)
        overlay = data['display_mode'] == 'front_overlay'
        raise ArgumentError, 'Chế độ đặt mặt đứng chưa được hỗ trợ.' if data.key?('display_mode') && !overlay
        roles = overlay ? %w[front_check front_unspecified front_open] : %w[front_check front_unspecified]
        fronts = views.select { |v| roles.include?(v['role']) && !v['parent_view_id'] }
        opened = views.select { |v| v['role'] == 'front_open' && !v['parent_view_id'] }.sort_by { |v| v['box_mm'][0] }
        if overlay
          unless views.select { |v| roles.include?(v['role']) }.all? { |v| !v.key?('drawing_x_offset_mm') && !v.key?('display_placement') }
            raise ArgumentError, 'Mặt đứng phải giữ tọa độ ghép XOZ; không tách theo hàng xem.'
          end
          opened = []
        end
        fronts = [opened.shift] if fronts.empty? && !opened.empty?
        if fronts.empty?
          raise ArgumentError, 'Bản mặt cắt XOZ thiếu mặt đứng làm mốc.' unless copies.empty?
          return true
        end
        unless copies.all? { |v| bounds?(v['box_mm']) && bounds?(v['anchor_box_mm']) }
          raise ArgumentError, 'Phạm vi bản mặt cắt XOZ không hợp lệ.'
        end
        previous = fronts.max_by { |v| v['box_mm'][2] + v['x_offset_mm'] }
        right = previous['box_mm'][2] + previous['x_offset_mm']
        sides = views.select { |v| v['role'] == 'section_vertical' && v['plane'] == 'YZ' }.sort_by { |v| v['box_mm'][0] }
        unless copies.map { |v| v['source_view_id'] } == sides.map { |v| v['id'] } && (views + copies).map { |v| v['id'] }.uniq.length == views.length + copies.length
          raise ArgumentError, 'Thiếu/lặp bản mặt cắt XOZ hoặc sai nguồn YOZ.'
        end
        (opened + copies).each do |view|
          placement = view['display_placement']; offset = view.fetch('drawing_x_offset_mm', view['x_offset_mm'])
          unless placement && placement['basis'] == 'standing_inspection_row' && placement['spacing_mm'] == 500 && placement['after_view_id'] == previous['id'] &&
                 offset.is_a?(Numeric) && offset.finite? && placement['min_x_mm'].is_a?(Numeric) && placement['min_x_mm'].finite? &&
                 (view['box_mm'][0] + offset - right - 500).abs < 0.01 && (placement['min_x_mm'] - right - 500).abs < 0.01
            raise ArgumentError, 'Các mặt đứng/bản mặt cắt XOZ phải cách nhau 500 mm.'
          end
          if view['source_view_id']
            source = sides.find { |v| v['id'] == view['source_view_id'] }
            unless view['plane'] == 'XZ' && view['role'] == 'section_vertical' && view['alignment'] == 'section_display_copy' &&
                   view['box_mm'] == source['box_mm'] && view['anchor_box_mm'] == source['anchor_box_mm']
              raise ArgumentError, 'Bản mặt cắt XOZ phải giữ nét/gốc cao độ của nguồn YOZ.'
            end
          end
          right = view['box_mm'][2] + offset; previous = view
        end
        views.each do |view|
          parent = views.find { |v| v['id'] == view['parent_view_id'] }
          next unless parent && parent.key?('drawing_x_offset_mm')
          raise ArgumentError, 'Chi tiết mặt đứng bỏ cánh bị tách sai vị trí.' unless view['drawing_x_offset_mm'] == parent['drawing_x_offset_mm']
        end
        true
      end

      def validate_depth(view, views, origin = nil)
        proof = view['depth_alignment']
        return true unless proof # Archived results retain their original registration.
        y = proof['plan_y_mm']
        return false unless y.is_a?(Numeric) && y.finite? && view['display_y_mm'].is_a?(Numeric) && (view['display_y_mm'] - y).abs < 0.01
        return !view['registration_issue'].to_s.empty? if proof['basis'] == 'provisional_source_min_y'
        plan = views.find { |v| v['id'] == proof['plan_id'] }
        return false unless plan && plan['role'] == 'plan' && plan['reference_family'] == view['reference_family']
        side = view.dig('cabinet_datum', 'box_mm'); anchor = view['anchor_box_mm']; datum = plan['cabinet_datum']
        shift = proof['plan_shift_mm']; x = proof['plan_x_mm']
        return false unless bounds?(side) && side == proof['side_box_mm'] && bounds?(anchor) && datum && bounds?(datum['box_mm']) &&
                            (side[0] - anchor[0]).abs < 0.01 && (side[2] - anchor[2]).abs < 0.01 &&
                            shift.is_a?(Array) && shift == plan['xy_offset_mm'] && shift.length == 2 && shift.all? { |v| v.is_a?(Numeric) && v.finite? } &&
                            x.is_a?(Numeric) && x.finite? && (view['display_x_mm'] - shift[0] - x).abs < 0.01
        if proof['basis'] == 'stock_axis_chain'
          link = view.dig('axis_registration', 'D')
          return false unless link && link['status'] == 'proven' && link['target_id'] == plan['id'] && origin
          validate_axis_link(link, views, origin)
          reverse = view['reversed_depth']; edge = reverse ? -anchor[2] - origin[0] : anchor[0] + origin[0]
          return link['scale'] == (reverse ? -1 : 1) && (y - link['offset_mm'] - shift[1] + origin[1] - edge).abs <= 0.001
        end
        panels = datum['panels']; bays = datum['bays_mm']
        return false unless panels.is_a?(Array) && panels.length >= 2 && panels.all? { |p| bounds?(p['box_mm']) } && bays.is_a?(Array) && bays.all? { |b| bounds?(b) }
        cells = bays.select { |b| b[0] - 0.15 <= x && x <= b[2] + 0.15 }
        faces = panels.map { |p| p['box_mm'] }.select { |b| b[0] - 0.15 <= x && x <= b[2] + 0.15 }
        expected, basis = if !cells.empty?
                            [(cells + faces).map { |b| b[1] }.min, 'cut_footprint']
                          elsif faces.length >= 2 && faces.map { |b| b[3] }.max - faces.map { |b| b[1] }.min > 100
                            [faces.map { |b| b[1] }.min, 'cut_panel_faces']
                          else
                            [datum['box_mm'][1], 'cabinet_min_y']
                          end
        proof['basis'] == basis && (y - shift[1] - expected).abs < 0.01
      end

      def validate_section(view, plan)
        x = view['display_x_mm']; y = view.fetch('display_y_mm', plan[1]); proof = view['section_position']
        return false unless [x, y].all? { |v| v.is_a?(Numeric) && v.finite? && v.abs < 100_000_000 }
        return x >= plan[2] + 999.99 unless proof # Archived inspection rows retain their original proof format.
        case proof['basis']
        when 'box_edge'
          box = proof['box_mm']; edge = proof['edge']
          return false unless bounds?(box) && %w[left right].include?(edge) && (x - box[edge == 'left' ? 0 : 2]).abs < 0.01
        when 'cut_marker'
          line = proof['cut_line']; origin = proof['source_origin_mm']; offset = proof['front_x_offset_mm']
          return false unless line.is_a?(Array) && line.length == 2 && (line + [origin]).all? { |p| p.is_a?(Array) && p.length == 2 && p.all? { |v| v.is_a?(Numeric) && v.finite? } } && offset.is_a?(Numeric) && offset.finite? &&
                              !proof['front_id'].to_s.empty? && !proof['marker_handle'].to_s.empty? && (line[0][0] - line[1][0]).abs < 0.15 && (line[0][1] - line[1][1]).abs > 0.15 &&
                              ((line[0][0] + line[1][0]) / 2 - origin[0] + offset - x).abs < 0.01
        else return false
        end
        return true unless view['direction_basis'] == 'symbol_arrows'
        direction = view['view_direction']; heads = view['arrow_heads']
        return false unless [[1, 0], [-1, 0]].include?(direction) && view['reversed_depth'] == direction[0].positive? && heads.is_a?(Array) && !heads.empty?
        heads.all? do |head|
          tip, a, b = head.values_at('tip', 'tail_a', 'tail_b')
          [tip, a, b].all? { |p| p.is_a?(Array) && p.length == 2 && p.all? { |v| v.is_a?(Numeric) && v.finite? } } &&
            (a[0] - b[0]).abs < 0.15 && (tip[1] - (a[1] + b[1]) / 2).abs < 0.15 &&
            (tip[0] - (a[0] + b[0]) / 2) * direction[0] > 0.15 && (a[1] - tip[1]) * (b[1] - tip[1]) < 0
        end
      end

      def transform(view, plan)
        box = view.fetch('anchor_box_mm', view['box_mm'])
        case view.fetch('plane')
        when 'YZ'
          reverse = view['reversed_depth']
          y = view.fetch('display_y_mm', plan[1]) + (reverse ? box[2] : -box[0])
          Geom::Transformation.axes([view['display_x_mm'], y, -box[1]].map(&:mm), [0, reverse ? -1 : 1, 0], [0, 0, 1], [reverse ? -1 : 1, 0, 0])
        when 'XZ'
          section = view['role'] == 'section_vertical' && view['alignment'] != 'section_display_copy'
          reverse = section && view['reversed_depth']
          x = if section
                view['display_x_mm'] + (reverse ? box[2] : -box[0])
              else
                view.fetch('drawing_x_offset_mm', view.fetch('x_offset_mm'))
              end
          Geom::Transformation.axes([x, 0, -box[1]].map(&:mm), [reverse ? -1 : 1, 0, 0], [0, 0, 1], [0, reverse ? 1 : -1, 0])
        else Geom::Transformation.translation([*view.fetch('xy_offset_mm', [0, 0]), view.fetch('z_mm', 0)].map(&:mm))
        end
      end
    end
  end
end

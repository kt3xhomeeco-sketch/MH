# frozen_string_literal: true

require_relative 'registered_elevation'
require_relative 'product_height'
require_relative 'partial_plan'
require_relative 'plan_components'

module MH
  module CAD2Module
    # Portable checks shared by host construction and unit tests.
    module Placement
      module_function

      def base_x(label_center_x, width)
        Float(label_center_x) - Float(width) / 2.0
      end

      def named_origin(product, label_center_x)
        layout = product['display_layout']
        return [base_x(label_center_x, product.fetch('bounds')[0]), 0] unless layout
        offset = layout.fetch('offset_mm')
        width = layout.fetch('total_width_mm')
        unless offset.is_a?(Array) && offset.length == 2 && (offset + [width]).all? { |v| v.is_a?(Numeric) && v.finite? && v >= 0 } && width.positive?
          raise ArgumentError, 'Vị trí xếp mặt bằng không hợp lệ.'
        end
        [base_x(label_center_x, width) + offset[0], offset[1]]
      end

      def next_label_x(occupied, width)
        raise ArgumentError, 'Chiều dài SP để đặt nhãn không hợp lệ.' unless width.is_a?(Numeric) && width.finite? && width.positive?
        return 1000.0 if occupied.empty?
        [1000.0, occupied.map { |x, _w| x }.max + 8000,
         occupied.map { |x, w| x + w / 2.0 }.max + width / 2.0 + 1000].max
      end

      def source_matrix(placement)
        unless placement['origin_mm'].is_a?(Array) && placement['origin_mm'].length == 2
          raise ArgumentError, 'Gốc nguồn quét phải có đúng hai tọa độ mặt phẳng.'
        end
        u, v = placement.fetch('origin_mm')
        offset = placement.fetch('plane_offset_mm', 0)
        raise ArgumentError, 'Gốc nguồn quét không hợp lệ.' unless [u, v, offset].all? { |n| n.is_a?(Numeric) && n.finite? }
        axes, origin = case placement.fetch('plane')
                       when 'XY' then [[[1, 0, 0], [0, 1, 0], [0, 0, 1]], [u, v, offset]]
                       when 'XZ' then [[[1, 0, 0], [0, 0, 1], [0, -1, 0]], [u, offset, v]]
                       when 'YZ' then [[[0, 1, 0], [0, 0, 1], [1, 0, 0]], [offset, u, v]]
                       else raise ArgumentError, 'Mặt phẳng nguồn quét không hợp lệ.'
                       end
        axes.flat_map { |axis| axis + [0] } + origin.map { |n| n / 25.4 } + [1]
      end

      def validate_module(mod)
        size = mod.fetch('size')
        origin = mod.fetch('origin')
        valid = size.length == 3 && origin.length == 3 &&
                size.all? { |value| value.is_a?(Numeric) && value.finite? && value.positive? && value < 100_000 } &&
                origin.all? { |value| value.is_a?(Numeric) && value.finite? && value.abs < 100_000 }
        raise ArgumentError, 'Kích thước hoặc vị trí module không hợp lệ.' unless valid
        true
      end

      def overlap?(a, b)
        bounding = 3.times.all? do |axis|
          left = [a['origin'][axis], b['origin'][axis]].max
          right = [a['origin'][axis] + a['size'][axis], b['origin'][axis] + b['size'][axis]].min
          right - left > 0.1
        end
        return false unless bounding
        return true unless [a, b].any? { |p| p['plan_profile'] }
        polygons = [a, b].map { |part| convex_footprint(part) }
        return true if polygons.any?(&:nil?)
        polygons.each do |points|
          points.each_with_index do |start, index|
            finish = points[(index + 1) % points.length]
            dx = finish[0] - start[0]; dy = finish[1] - start[1]; length = Math.hypot(dx, dy)
            next if length < 0.001
            intervals = polygons.map { |poly| poly.map { |p| (-dy * p[0] + dx * p[1]) / length }.minmax }
            return false if [intervals[0][1], intervals[1][1]].min - [intervals[0][0], intervals[1][0]].max <= 0.1
          end
        end
        true
      end

      def convex_footprint(part)
        profile = part['plan_profile']
        return nil if profile && profile['segments'].any? { |s| s['type'] != 'line' }
        w, h = part['size']
        points = profile ? profile['segments'].map { |s| s['start'] } : [[0, 0], [w, 0], [w, h], [0, h]]
        turns = points.each_index.filter_map do |i|
          a = points[i]; b = points[(i + 1) % points.length]; c = points[(i + 2) % points.length]
          cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
          cross.positive? if cross.abs > 0.0001
        end
        return nil if turns.empty? || turns.uniq.length > 1
        points.map { |p| 2.times.map { |i| p[i] + part['origin'][i] } }
      end

      def board_rectangles(rectangles, axis)
        other = 1 - axis
        boards = rectangles.select do |b|
          thin = b[axis + 2] - b[axis]
          [3, 6, 8, 9, 12, 15, 18, 25, 36].any? { |s| (thin - s).abs <= 0.15 } && b[other + 2] - b[other] > [72, thin * 3].max
        end
        boards.reject do |box|
          fragments = boards.select do |b|
            !b.equal?(box) && (b[other] - box[other]).abs <= 0.15 && (b[other + 2] - box[other + 2]).abs <= 0.15 &&
              b[axis] >= box[axis] - 0.15 && b[axis + 2] <= box[axis + 2] + 0.15 &&
              b[axis + 2] - b[axis] < box[axis + 2] - box[axis] - 0.15
          end
          reach = box[axis]
          fragments.sort_by { |b| b[axis] }.each do |b|
            break if b[axis] > reach + 0.15
            reach = [reach, b[axis + 2]].max
          end
          fragments.length >= 2 && reach >= box[axis + 2] - 0.15
        end
      end

      def validate_oy_product(product)
        return unless product['plan_engine'] == 'oy-stock-sweep-v1'
        base = product.fetch('source_plan_envelope').first(2)
        offset = product.fetch('plan_origin_offset_mm', [0, 0])
        unless (base + offset).length == 4 && (base + offset).all? { |v| v.is_a?(Numeric) && v.finite? } && offset.all? { |v| v.abs <= 72.15 }
          raise ArgumentError, 'Gốc mặt bằng OY không hợp lệ.'
        end
        parts = %w[modules trim_parts panel_parts].flat_map { |key| Array(product[key]) }
        parts.each do |part|
          validate_module(part)
          if part['origin'][2].abs > 0.05 || (part['size'][2] - 1600).abs > 0.05
            raise ArgumentError, 'Mặt bằng OY phải giữ Z=0 và cao tạm 1600 mm.'
          end
        end
        raise ArgumentError, 'Các khối OY chồng nhau.' if parts.combination(2).any? { |a, b| overlap?(a, b) }
        if product.dig('placement', 'mode') == 'source_plan'
          source_matrix(product['placement'])
          unless 2.times.all? { |i| (product['placement']['origin_mm'][i] - base[i] - offset[i]).abs < 0.01 }
            raise ArgumentError, 'Vị trí dựng OY không khớp gốc CAD.'
          end
        end
        product.fetch('modules').each do |part|
          measured = part.fetch('source_box')
          expected = 2.times.map { |i| base[i] + offset[i] + part['origin'][i] }
          expected += 2.times.map { |i| expected[i] + part['size'][i] }
          unless measured.length == 4 && measured.zip(expected).all? { |a, b| a.is_a?(Numeric) && a.finite? && (a - b).abs < 0.01 }
            raise ArgumentError, 'Kích thước/vị trí khối OY không khớp biên đã đo.'
          end
        end
        validate_stepped_footprints(product, parts, 2.times.map { |i| base[i] + offset[i] })
        product['geometry_check'] = { 'passed' => true, 'engine' => 'oy-stock-sweep-v1' }
      end

      def validate_elevation_product(product)
        return unless product['plan_engine'] == 'section-first-v1'
        proof = product.fetch('geometry_pipeline').fetch('horizontal')
        unless product.dig('build_stages', 'plan') && product.dig('build_stages', 'elevation') &&
               %w[measured partial provisional user_confirmed].include?(proof['status'])
          raise ArgumentError, 'Chưa có trạng thái kiểm tra mặt cắt đứng.'
        end
        base = product.fetch('source_plan_envelope').first(2)
        offset = product.fetch('plan_origin_offset_mm', [0, 0])
        parts = %w[modules trim_parts panel_parts].flat_map { |key| Array(product[key]) }
        parts.each do |part|
          validate_module(part)
          if part['height_source'] == 'user_confirmed'
            unless product['manual_boxes'] && product.dig('learning', 'mode') == 'user_confirmed' && proof['status'] == 'user_confirmed'
              raise ArgumentError, 'Chưa có kết quả do người dùng xác nhận cho chiều cao này.'
            end
          elsif part['height_source'] == 'registered_view_geometry'
            RegisteredElevation.validate(part, product)
          elsif part['height_source'] == 'product_elevation_bounds'
            ProductHeight.validate(part, product)
          elsif part['height_source'] == 'front_stock_bounds'
            PartialPlan.validate(part, product)
          elsif part['height_source'] == 'front_section_band'
            PartialPlan.validate_band(part, product)
          elsif part['height_source'] == 'linked_vertical_section'
            evidence = part.fetch('elevation_evidence')
            low = evidence.fetch('low_mm'); high = evidence.fetch('high_mm')
            unless (part['origin'][2] - low).abs < 0.01 && (part['size'][2] - high + low).abs < 0.01 &&
                   low >= -0.15 && high > low && !Array(evidence['links']).empty?
              raise ArgumentError, 'Cao độ/kích thước khối không khớp mặt cắt đứng.'
            end
            evidence['links'].each do |link|
              cut = link.fetch('cut_line'); x = link.fetch('source_x_mm')
              located = cut.length == 2 && (cut[0][0] - cut[1][0]).abs <= 0.15 && (cut[0][1] - cut[1][1]).abs > 0.15
              matched = link.fetch('tiers').any? do |tier|
                (tier['low_mm'] - link['section_base_mm'] - low).abs < 0.01 &&
                  (tier['high_mm'] - link['section_base_mm'] - high).abs < 0.01 && !tier['handles'].empty?
              end
              box = part.fetch('source_box')
              unless located && matched && x >= box[0] - 0.15 && x <= box[2] + 0.15
                raise ArgumentError, 'Dấu cắt hoặc tầng đo không thuộc đúng module.'
              end
            end
          elsif !part['elevation_pending'] || part['origin'][2].abs > 0.01 || (part['size'][2] - 1600).abs > 0.01
            raise ArgumentError, 'Phần chưa đo chiều cao phải giữ khối tạm 1600 mm và ghi rõ đang chờ.'
          end
          next unless product['modules'].include?(part) && part['source_box']
          expected = 2.times.map { |i| base[i] + offset[i] + part['origin'][i] }
          expected += 2.times.map { |i| expected[i] + part['size'][i] }
          unless part['source_box'].zip(expected).all? { |a, b| (a - b).abs < 0.01 }
            raise ArgumentError, 'Khối mặt đứng bị đổi biên XY của mặt bằng.'
          end
        end
        raise ArgumentError, 'Các khối sau ghép mặt cắt đứng chồng nhau.' if parts.combination(2).any? { |a, b| overlap?(a, b) }
        PlanComponents.validate(product) if product['plan_components']
        if product.dig('placement', 'mode') == 'source_plan'
          source_matrix(product['placement'])
          unless 2.times.all? { |i| (product['placement']['origin_mm'][i] - base[i] - offset[i]).abs < 0.01 }
            raise ArgumentError, 'Khối kết hợp bị lệch gốc CAD nguồn.'
          end
        end
        product['geometry_check'] = { 'passed' => true, 'engine' => 'section-first-v1', 'status' => proof['status'] }
      end

      def validate_ai_product(product)
        return unless product.dig('local_ai', 'workflow') == 'ai_plan_search_v2'
        decided = product.dig('local_ai', 'status') == 'choose' ||
                  (product.dig('local_ai', 'status') == 'fallback' && product.dig('local_ai', 'fallback_to_cad'))
        unless decided && product.dig('local_ai', 'final_check', 'passed')
          raise ArgumentError, 'AI chưa có phương án vượt kiểm tra cuối để dựng.'
        end
        parts = %w[modules trim_parts panel_parts].flat_map { |key| Array(product[key]) }
        raise ArgumentError, 'Phương án AI chưa có module.' if Array(product['modules']).empty?
        parts.each do |part|
          validate_module(part)
          if part['origin'][2].abs > 0.05 || (part['size'][2] - 1600).abs > 0.05
            raise ArgumentError, 'Phương án AI mặt bằng phải giữ Z=0 và cao tạm 1600 mm.'
          end
        end
        raise ArgumentError, 'Phương án AI có khối đặc chồng nhau.' if parts.combination(2).any? { |a, b| overlap?(a, b) }
        source_matrix(product['placement']) if product.dig('placement', 'mode') == 'source_plan'
        selected = product.dig('geometry_pipeline', 'vertical', 'view_id')
        plans = Array(product['views']).select { |view| view['role'] == 'plan' && (!selected || view['id'] == selected) }
        raise ArgumentError, 'Chưa xác định được mặt bằng để kiểm tra trước khi dựng.' unless plans.length == 1
        envelope = product['source_plan_envelope'] || product['envelope']
        offset = product.fetch('plan_origin_offset_mm', [0, 0])
        unless envelope.is_a?(Array) && envelope.length == 4 && offset.is_a?(Array) && offset.length == 2 &&
               (envelope + offset).all? { |v| v.is_a?(Numeric) && v.finite? }
          raise ArgumentError, 'Gốc CAD của phương án AI không hợp lệ.'
        end
        validate_stepped_footprints(product, parts, 2.times.map { |i| envelope[i] + offset[i] })
        if product.dig('placement', 'mode') == 'source_plan' &&
           product['placement']['origin_mm'].each_with_index.any? { |v, i| (v - envelope[i] - offset[i]).abs > 0.05 }
          raise ArgumentError, 'Vị trí dựng AI không khớp gốc CAD đã kiểm tra.'
        end
        region = plans.first.fetch('region')
        rectangles = Array(product['rectangles']).map { |r| r.fetch('box') }.select do |box|
          box[0] >= region[0] - 0.15 && box[1] >= region[1] - 0.15 && box[2] <= region[2] + 0.15 && box[3] <= region[3] + 0.15
        end
        walls = 2.times.map { |axis| board_rectangles(rectangles, axis) }
        parts.each do |part|
          2.times do |axis|
            other = 1 - axis
            lo = envelope[axis] + offset[axis] + part['origin'][axis]
            hi = lo + part['size'][axis]
            start = envelope[other] + offset[other] + part['origin'][other]
            finish = start + part['size'][other]
            walls[axis].each do |box|
              next if [finish, box[other + 2]].min - [start, box[other]].max <= 0.15
              if [lo, hi].any? { |v| v > box[axis] + 0.15 && v < box[axis + 2] - 0.15 }
                raise ArgumentError, 'Đường chia AI xuyên vách/tấm liền trên CAD; chưa dựng.'
              end
            end
          end
        end
        product['local_ai']['native_preflight'] = { 'passed' => true }
      end

      def validate_envelope_preview(product)
        return false unless product['envelope_preview']
        provisional = product.dig('build_stages', 'elevation') == false ||
                      (product['plan_engine'] == 'section-first-v1' && product.dig('geometry_pipeline', 'horizontal', 'status') == 'provisional')
        unless product['status'] == 'needs_review' && provisional &&
               product.dig('envelope_preview', 'kind') == 'selected_cad_envelope'
          raise ArgumentError, 'Khối tạm phải được ghi rõ là khung bao CAD chưa phân tích.'
        end
        points = Array(product['outlines']).flat_map { |o| Array(o['points']) }
        if points.empty? || points.any? { |p| !p.is_a?(Array) || p.length != 2 || p.any? { |v| !v.is_a?(Numeric) || !v.finite? } }
          raise ArgumentError, 'Khối tạm thiếu tọa độ CAD nguồn hữu hạn.'
        end
        box = 2.times.map { |i| points.map { |p| p[i] }.min } + 2.times.map { |i| points.map { |p| p[i] }.max }
        parts = Array(product['modules'])
        raise ArgumentError, 'Khung bao tạm chỉ được có một khối, chưa chia module/phần phụ.' unless parts.length == 1 && Array(product['trim_parts']).empty? && Array(product['panel_parts']).empty?
        part = parts.first
        validate_module(part)
        measured = part['height_source'] == 'product_elevation_bounds'
        ProductHeight.validate(part, product) if measured
        depth = validate_preview_depth(product, box)
        span = depth && validate_depth_sections(depth, product)
        expected = [box[2] - box[0], span || (depth ? depth['high_mm'] - depth['low_mm'] : box[3] - box[1]), measured ? product['product_height']['high_mm'] - product['product_height']['low_mm'] : 1600]
        origin = [0, depth ? depth['low_mm'] - box[1] : 0, measured ? product['product_height']['low_mm'] : 0]
        unless part['rule'] == 'source-envelope-preview-v1' && part['origin'].zip(origin).all? { |a, b| (a - b).abs < 0.01 } &&
               part['size'].zip(expected).all? { |a, b| (a - b).abs < 0.01 } &&
               product['envelope'].zip(box).all? { |a, b| (a - b).abs < 0.01 }
          raise ArgumentError, 'Kích thước khối tạm không khớp khung bao CAD.'
        end
        placement = product.fetch('placement')
        source_matrix(placement)
        allowed = placement['mode'] == 'source_plan' || (placement['mode'] == 'label_plan' && product.dig('view_analysis', 'selected_view_id'))
        unless allowed && placement['origin_mm'].zip(box.first(2)).all? { |a, b| (a - b).abs < 0.01 }
          raise ArgumentError, 'Gốc khối tạm không khớp vị trí CAD nguồn.'
        end
        product['envelope_preview']['native_preflight'] = { 'passed' => true }
        true
      end

      def validate_preview_depth(product, box)
        return unless product.dig('envelope_preview', 'dimensions_from') == 'closed_stock_depth'
        proof = product.fetch('envelope_preview').fetch('depth_evidence')
        panels = proof.fetch('panels')
        handles = product.fetch('outlines').map { |row| row['handle'].to_s }
        unless proof['basis'] == 'closed_compatible_stock_pairs' && panels.length >= 2 && panels.all? { |panel|
          q = panel['box_mm']
          RegisteredElevation.box?(q) && RegisteredElevation.stock?([q[2] - q[0], q[3] - q[1]].min) &&
            !Array(panel['handles']).empty? && Array(panel['handles']).all? { |h| handles.include?(h.to_s) } &&
            2.times.all? { |i| q[i] >= box[i] - 0.15 && q[i + 2] <= box[i + 2] + 0.15 }
        } && RegisteredElevation.near(proof['low_mm'], panels.map { |p| p['box_mm'][1] }.min) &&
               RegisteredElevation.near(proof['high_mm'], panels.map { |p| p['box_mm'][3] }.max) && proof['high_mm'] - proof['low_mm'] >= 100
          raise ArgumentError, 'Chiều sâu box chưa có cặp ván kín tương ứng trong CAD nguồn.'
        end
        proof
      end

      def validate_depth_sections(proof, product)
        check = proof['section_check']
        return unless check && check['status'] == 'supported'
        sections = check.fetch('sections'); value = check.fetch('chosen_depth_mm')
        candidate = Array(product.dig('view_analysis', 'candidates')).find { |v| v['id'] == product['plan_view_id'] }
        family = candidate && candidate['reference_family']
        unless value.is_a?(Numeric) && value.finite? && check['tolerance_mm'] == 1 && !family.to_s.empty? &&
               check['reference_family'] == family && sections.map { |s| s['view_id'] }.uniq.length >= 2 &&
               (value - proof['high_mm'] + proof['low_mm']).abs <= 1 && sections.all? { |section|
          box = section['box_mm']
          view = Array(product.dig('view_analysis', 'candidates')).find { |v| v['id'] == section['view_id'] }
          panels = section['panels']
          view && view['role'] == 'section_vertical' && view['reference_family'] == family && RegisteredElevation.box?(box) &&
            RegisteredElevation.near(box[2] - box[0], section['depth_mm']) && (section['depth_mm'] - value).abs <= 0.15 &&
            Array(panels).length >= 2 && panels.all? { |p| RegisteredElevation.box?(p['box_mm']) && !Array(p['handles']).empty? } &&
            RegisteredElevation.near(box[0], panels.map { |p| p['box_mm'][0] }.min) &&
            RegisteredElevation.near(box[2], panels.map { |p| p['box_mm'][2] }.max)
        }
          raise ArgumentError, 'Chiều sâu đối chiếu mặt cắt chưa khớp cùng bộ hình/tấm ván.'
        end
        value
      end

      def polygon_contains?(point, polygon)
        x, y = point
        result = false
        (polygon + [polygon.first]).each_cons(2) do |a, b|
          result = !result if (a[1] > y) != (b[1] > y) && x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]
        end
        result
      end

      def validate_stepped_footprints(product, parts, base)
        Array(product.dig('geometry_pipeline', 'measured_stepped_footprints')).each do |measured|
          box = measured.fetch('box')
          expected = measured.fetch('profile').fetch('segments').map { |s| 2.times.map { |i| s['start'][i] + box[i] } }
          polygons = parts.filter_map do |part|
            origin = 2.times.map { |i| base[i] + part['origin'][i] }
            next if 2.times.any? { |i| [origin[i] + part['size'][i], box[i + 2]].min - [origin[i], box[i]].max <= 0.15 }
            profile = part['plan_profile']
            if profile && profile['segments'].any? { |s| s['type'] != 'line' }
              raise ArgumentError, 'Phương án đổi biên hậu giật cấp thành cung không có trên CAD.'
            end
            points = profile ? profile['segments'].map { |s| s['start'] } : [[0, 0], [part['size'][0], 0], part['size'][0, 2], [0, part['size'][1]]]
            points.map { |p| 2.times.map { |i| p[i] + origin[i] } }
          end
          axes = 2.times.map do |i|
            ([box[i], box[i + 2]] + ([expected] + polygons).flatten(1).map { |p| p[i] }.select { |v| v > box[i] && v < box[i + 2] }).uniq.sort
          end
          raise ArgumentError, 'Biên hậu giật cấp quá phức tạp để đối chiếu.' if axes[0].length * axes[1].length > 20_000
          axes[0].each_cons(2) do |x0, x1|
            axes[1].each_cons(2) do |y0, y1|
              next if [x1 - x0, y1 - y0].min <= 0.15
              point = [(x0 + x1) / 2.0, (y0 + y1) / 2.0]
              unless polygon_contains?(point, expected) == polygons.any? { |p| polygon_contains?(point, p) }
                raise ArgumentError, 'Phương án lấp phần lõm hoặc làm mất biên hậu giật cấp đã đo trên CAD.'
              end
            end
          end
        end
      end
    end
  end
end

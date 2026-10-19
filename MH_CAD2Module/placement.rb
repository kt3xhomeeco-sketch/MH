# frozen_string_literal: true

module MH
  module CAD2Module
    # Portable checks shared by host construction and unit tests.
    module Placement
      module_function

      def base_x(label_center_x, width)
        Float(label_center_x) - Float(width) / 2.0
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
        3.times.all? do |axis|
          left = [a['origin'][axis], b['origin'][axis]].max
          right = [a['origin'][axis] + a['size'][axis], b['origin'][axis] + b['size'][axis]].min
          right - left > 0.1
        end
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
        unless product['status'] == 'needs_review' && product.dig('build_stages', 'elevation') == false &&
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
        expected = [box[2] - box[0], box[3] - box[1], 1600]
        unless part['rule'] == 'source-envelope-preview-v1' && part['origin'].all? { |v| v.abs < 0.01 } &&
               part['size'].zip(expected).all? { |a, b| (a - b).abs < 0.01 } &&
               product['envelope'].zip(box).all? { |a, b| (a - b).abs < 0.01 }
          raise ArgumentError, 'Kích thước khối tạm không khớp khung bao CAD.'
        end
        placement = product.fetch('placement')
        source_matrix(placement)
        unless placement['mode'] == 'source_plan' && placement['origin_mm'].zip(box.first(2)).all? { |a, b| (a - b).abs < 0.01 }
          raise ArgumentError, 'Gốc khối tạm không khớp vị trí CAD nguồn.'
        end
        product['envelope_preview']['native_preflight'] = { 'passed' => true }
        true
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

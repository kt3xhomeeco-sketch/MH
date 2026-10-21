# frozen_string_literal: true

module MH
  module CAD2Module
    # Geometric registration carries real panel proofs, never invented cut IDs.
    module RegisteredElevation
      module_function

      def near(a, b)
        (a - b).abs <= 0.01
      end

      def box?(box)
        box.is_a?(Array) && box.length == 4 && box.all? { |v| v.is_a?(Numeric) && v.finite? } && box[2] > box[0] && box[3] > box[1]
      end

      def stock?(value)
        [3, 6, 8, 9, 12, 15, 18, 25, 36].any? { |v| (value - v).abs <= 0.15 }
      end

      def validate_trim_box(part, ev, sb)
        pieces = ev.fetch('section_parts')
        size = ev.fetch('confirmed_box_mm')
        raise ArgumentError, 'Thiếu xác nhận khối nẹp theo nguồn.' unless pieces.length == 2 && size == part['size'].last(2) && !ev['confirmation_event'].to_s.empty?
        rows = pieces.map do |piece|
          q = piece.fetch('box'); stock = piece.fetch('stock_mm')
          unless box?(q) && stock?(stock) && piece['parallel_proof'] == 'parallel_faces_and_closed_ends' &&
                 near([q[2] - q[0], q[3] - q[1]].min, stock)
            raise ArgumentError, 'Thiếu hai tấm chữ L đo từ cặp song song khép kín.'
          end
          [ev['reversed_depth'] ? sb[2] - q[2] : q[0] - sb[0], q[1] - sb[1], q[2] - q[0], q[3] - q[1]]
        end.sort_by(&:first)
        a, b = rows
        unless near(a[0] + a[2], b[0]) && near(a[1], b[1]) && a[2] < b[2] && a[3] > b[3] &&
               near(size[0], [a[2], b[2]].max) && near(size[1], [a[3], b[3]].max) &&
               near(part['origin'][1], a[0]) && near(part['origin'][2], a[1]) && near(part['origin'][0], 0) &&
               near(part['size'][0], ev['plan_frame'][2] - ev['plan_frame'][0])
          raise ArgumentError, 'Khối nẹp không khớp hai nhánh chữ L và kích thước xác nhận.'
        end
      end

      def validate(part, product)
        ev = part.fetch('elevation_evidence')
        low = ev.fetch('low_mm'); high = ev.fetch('high_mm')
        checks = ev.fetch('front_checks')
        unless ev['basis'] == 'registered_parallel_panels' && ev['source_signature'].to_s.match?(/\A[0-9a-f]{64}\z/) &&
               ev['source_signature'] == product.dig('geometry_pipeline', 'horizontal', 'registration', 'source_signature') &&
               box?(ev['front_box']) && box?(ev['section_box']) && box?(ev['plan_frame']) &&
               checks.map { |v| v['id'] }.uniq.length >= 2 && checks.all? { |v| box?(v['box']) } &&
               near(part['origin'][2], low) && near(part['size'][2], high - low) && low >= -0.15 && high > low
          raise ArgumentError, 'Thiếu chứng cứ/cao độ ghép hình học mặt đứng.'
        end
        fb = ev['front_box']; sb = ev['section_box']; frame = ev['plan_frame']
        base = product.fetch('source_plan_envelope').first(2).zip(product.fetch('plan_origin_offset_mm', [0, 0])).map { |a, b| a + b }
        expected = 2.times.map { |i| base[i] + part['origin'][i] }
        expected += 2.times.map { |i| expected[i] + part['size'][i] }
        unless frame.zip(product.fetch('source_plan_envelope')).all? { |a, b| near(a, b) } &&
               box?(part['source_box']) && expected.zip(part['source_box']).all? { |a, b| near(a, b) }
          raise ArgumentError, 'Khối ghép hình học bị đổi vị trí/kích thước mặt bằng.'
        end
        raise ArgumentError, 'Các mặt đứng đối chiếu khác kích thước.' unless checks.all? { |v| near(v['box'][2] - v['box'][0], frame[2] - frame[0]) && near(v['box'][3] - v['box'][1], fb[3] - fb[1]) }
        case ev.fetch('kind')
        when 'module'
          a, b = ev.fetch('front_walls')
          unless [a, b].all? { |q| box?(q) && stock?(q[2] - q[0]) && near(q[1] - fb[1], low) && near(q[3] - fb[1], high) } &&
                 near(a[0] - fb[0], part['source_box'][0] - frame[0]) && near(b[2] - fb[0], part['source_box'][2] - frame[0]) &&
                 near(sb[2] - sb[0], part['size'][1])
            raise ArgumentError, 'Cặp vách/chiều sâu không thuộc đúng khoang ghép.'
          end
          raise ArgumentError, 'Thiếu tấm ngang tại hai đầu tầng.' unless ev.fetch('section_caps').length == 2
          ev.fetch('section_caps').zip([low, high]).each do |q, level|
            unless box?(q) && stock?(q[3] - q[1]) && q[2] - q[0] >= part['size'][1] - 72.15 &&
                   (near(q[1] - sb[1], level) || near(q[3] - sb[1], level))
              raise ArgumentError, 'Cao độ chưa có cặp tấm ngang trên mặt cắt.'
            end
          end
        when 'end_panel'
          evidence = ev.fetch('front_panels')
          unless evidence.map { |v| v['view_id'] }.uniq.length >= 2 && evidence.all? { |v|
            q = v['box']; base = v['view_box']
            box?(q) && box?(base) && stock?(q[2] - q[0]) && near(q[2] - q[0], part['size'][0]) &&
              near(q[1] - base[1], low) && near(q[3] - base[1], high) && near(q[0] - base[0], part['source_box'][0] - frame[0])
          }
            raise ArgumentError, 'Tấm ngoài chưa khớp hai mặt đứng.'
          end
        when 'top_trim_proxy'
          validate_trim_box(part, ev, sb)
        when 'top_trim'
          q = ev.fetch('section_panel')
          y = ev['reversed_depth'] ? sb[2] - q[2] : q[0] - sb[0]
          unless box?(q) && ev['parallel_proof'] == 'parallel_faces_and_closed_ends' && stock?(ev['stock_mm']) &&
                 (near(q[2] - q[0], ev['stock_mm']) || near(q[3] - q[1], ev['stock_mm'])) &&
                 near(q[1] - sb[1], low) && near(q[3] - sb[1], high) && near(part['size'][1], q[2] - q[0]) &&
                 near(part['origin'][1], y) && near(part['origin'][0], 0) && near(part['size'][0], frame[2] - frame[0])
            raise ArgumentError, 'Nẹp nóc chưa khớp cặp biên song song trên mặt cắt.'
          end
        else raise ArgumentError, 'Loại chứng cứ ghép hình học chưa được hỗ trợ.'
        end
        true
      end
    end
  end
end

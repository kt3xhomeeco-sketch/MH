# frozen_string_literal: true

module MH
  module CAD2Module
    # Plan closure, section-depth corroboration and tier heights are separate proofs.
    module PlanComponents
      module_function

      def validate(product)
        proof = product.fetch('plan_components')
        links = proof.fetch('cut_links')
        unless proof['engine'] == 'linked-horizontal-arms-v1' && proof['source_signature'] == product.dig('product_height', 'source_signature') &&
               !links.empty? && links.all? { |c| line = c['cut_line']; c['axis'] == 'horizontal' && line.length == 2 &&
                 (line[0][1] - line[1][1]).abs <= 0.15 && (line[0][0] - line[1][0]).abs > 100 }
          raise ArgumentError, 'Mặt bằng nhiều nhánh thiếu dấu cắt ngang/hình học nguồn tương ứng.'
        end
        base = product.fetch('source_plan_envelope').first(2)
        parts = Array(product['modules']) + Array(product['trim_parts'])
        parts.each do |part|
          box = part.fetch('source_box')
          expected = 2.times.map { |i| base[i] + part['origin'][i] }
          expected += 2.times.map { |i| expected[i] + part['size'][i] }
          unless RegisteredElevation.box?(box) && box.zip(expected).all? { |a, b| RegisteredElevation.near(a, b) }
            raise ArgumentError, 'Khoang/nẹp nhiều nhánh bị đổi biên hoặc vị trí CAD.'
          end
          next unless product['modules'].include?(part)
          ev = part.fetch('plan_component_evidence'); local = ev.fetch('local_box')
          converted = ev['axis'] == 0 ? local : [-local[3], local[0], -local[1], local[2]]
          stock = ev.fetch('walls')
          unless [0, 1].include?(ev['axis']) && converted.zip(box).all? { |a, b| RegisteredElevation.near(a, b) } &&
                 !Array(ev['handles']).empty? && stock.length >= 2 && stock.all? { |q|
                   RegisteredElevation.box?(q) && RegisteredElevation.stock?([q[2] - q[0], q[3] - q[1]].min)
                 }
            raise ArgumentError, 'Khoang thiếu cặp ván theo đúng hướng nhánh mặt bằng.'
          end
          if ev['closed']
            unless !Array(ev['caps']).empty? && ev['caps'].all? { |q| RegisteredElevation.box?(q) && RegisteredElevation.stock?(q[3] - q[1]) }
              raise ArgumentError, 'Khoang kín thiếu tấm đóng trong mặt bằng.'
            end
          elsif !part['unresolved'] || !part['envelope_preview'] || Array(ev['sections']).empty? ||
                !ev['sections'].all? { |s| (local[3] - local[1] - s['depth_mm']).abs <= 36.15 }
            raise ArgumentError, 'Khoang thiếu hậu phải giữ box tạm và đối chiếu chiều sâu mặt cắt.'
          end
        end
        true
      end
    end
  end
end

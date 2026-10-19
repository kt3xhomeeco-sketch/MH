# frozen_string_literal: true

require_relative 'model'

module MH
  module CAD2Module
    # Read actual transformed edges, never the instance's axis-dependent bounds.
    module ManualBoxes
      TOLERANCE = 0.1
      STOCK = [3, 6, 8, 9, 12, 15, 18, 25, 36].freeze
      module_function

      def collect_edges(entities, transform, result, depth = 0)
        raise ArgumentError, 'Box lồng quá nhiều cấp.' if depth > 15
        entities.each do |entity|
          if entity.is_a?(Sketchup::Edge)
            result << [entity.start.position.transform(transform), entity.end.position.transform(transform)]
          elsif Model.container?(entity)
            collect_edges(entity.definition.entities, transform * entity.transformation, result, depth + 1)
          end
        end
      end

      def cover?(intervals, low, high)
        reach = low
        intervals.sort.each do |a, b|
          return false if a > reach + TOLERANCE
          reach = [reach, b].max
          return true if reach >= high - TOLERANCE
        end
        false
      end

      def cuboid(edges)
        points = edges.flatten(1)
        low = 3.times.map { |i| points.map { |p| p[i] }.min }
        high = 3.times.map { |i| points.map { |p| p[i] }.max }
        return nil if 3.times.any? { |i| high[i] - low[i] < TOLERANCE }
        corners = 8.times.map { |bits| 3.times.map { |i| bits[i].zero? ? low[i] : high[i] } }
        unless corners.all? { |c| points.any? { |p| 3.times.all? { |i| (c[i] - p[i]).abs <= TOLERANCE } } }
          raise ArgumentError, 'Box đang xoay thật hoặc không phải hình hộp theo hướng CAD; chỉnh hình khối, không cần chỉnh trục group.'
        end
        unless points.all? { |p| 3.times.any? { |i| [(p[i] - low[i]).abs, (p[i] - high[i]).abs].min <= TOLERANCE } }
          raise ArgumentError, 'Chỉ chọn các box đại diện, không chọn khối có chi tiết bên trong.'
        end
        3.times do |axis|
          others = [0, 1, 2] - [axis]
          [low[others[0]], high[others[0]]].product([low[others[1]], high[others[1]]]).each do |limits|
            intervals = edges.filter_map do |a, b|
              next unless others.each_with_index.all? { |index, j| (a[index] - limits[j]).abs <= TOLERANCE && (b[index] - limits[j]).abs <= TOLERANCE }
              [a[axis], b[axis]].minmax
            end
            raise ArgumentError, 'Box chưa khép đủ các cạnh. Mỗi box cần một Group/Component riêng.' unless cover?(intervals, low[axis], high[axis])
          end
        end
        { 'origin' => low, 'size' => 3.times.map { |i| high[i] - low[i] } }
      end

      def capture(model, product, selected)
        raise ArgumentError, 'Thoát sửa group trước khi chọn các box đúng.' if model.active_path
        transform = product.transformation
        axes = [transform.xaxis.normalize, transform.yaxis.normalize, transform.zaxis.normalize]
        raise ArgumentError, 'Hệ trục sản phẩm bị xiên; cần khôi phục hướng CAD trước khi nhận box.' if axes.combination(2).any? { |a, b| a.dot(b).abs > 0.0001 }
        basis = Geom::Transformation.axes(transform.origin, *axes)
        inverse = basis.inverse
        root_ids = model.entities.map(&:persistent_id) # rubocop:disable SketchupSuggestions/ModelEntities -- Inputs are root-level manual boxes.
        roots = selected.select { |e| Model.container?(e) && e != product && root_ids.include?(e.persistent_id) }
        boxes = roots.filter_map do |entity|
          next if entity.get_attribute(Model::DICT, 'role') == 'product'
          next if product.is_a?(Assembly) && product.members.include?(entity)
          edges = []
          collect_edges(entity.definition.entities, entity.transformation, edges)
          next if edges.empty?
          local = edges.map { |edge| edge.map { |p| p.transform(inverse).to_a.map(&:to_mm) } }
          box = PlanProfile.prism(local) || cuboid(local)
          next unless box
          box.merge('source_entity_id' => entity.persistent_id)
        end
        raise ArgumentError, 'Chọn các box đúng trong SketchUp rồi bấm Kết quả đúng; mỗi box là một Group/Component riêng. Không cần đặt tên hoặc chỉnh trục.' if boxes.empty?
        minimum = 3.times.map { |i| boxes.map { |box| box['origin'][i] }.min }
        boxes.each do |box|
          box['origin'] = 3.times.map { |i| (box['origin'][i] - minimum[i]).round(4) }
          box['size'] = box['size'].map { |v| v.round(4) }
          Placement.validate_module(box)
        end
        boxes.sort_by! { |box| box['origin'] + box['size'] }
        raise ArgumentError, 'Các box đúng đang chồng lấn; kiểm tra trước khi xác nhận.' if boxes.combination(2).any? { |a, b| Placement.overlap?(a, b) }
        { 'boxes' => boxes, 'source_ids' => boxes.map { |b| b['source_entity_id'] }, 'normalised_from' => minimum,
          'basis_transform' => basis.to_a }
      end

      def parts(capture, analysis)
        modules = []; trims = []
        capture.fetch('boxes').each do |box|
          thin = PlanProfile.concentric_thickness(box['plan_profile']) || [box['size'][0], box['size'][1]].min
          stock = STOCK.find { |s| (s - thin).abs <= TOLERANCE }
          part = box.merge('rule' => 'user-drawn-box-v1', 'handles' => [],
                           'explanation' => 'Box do người dùng xác nhận; đo từ các đỉnh thực, bỏ qua gốc và trục riêng của group.')
          if stock
            part.merge!('id' => "T#{trims.length + 1}", 'name' => 'Phần phụ từ box đúng', 'role' => 'manual_auxiliary',
                        'solid_proxy' => true, 'stock_thickness_mm' => stock, 'face_width_mm' => box['size'][0])
            trims << part
          else
            part.merge!('id' => "M#{modules.length + 1}", 'name' => 'Module từ box đúng', 'scope' => 'carcass_and_doors')
            modules << part
          end
          if analysis.dig('build_stages', 'elevation') == false
            raise ArgumentError, 'Đang ở giai đoạn Mặt bằng: các box cần cùng mặt đáy, chưa chia tầng đứng.' if part['origin'][2] > TOLERANCE
            part['height_source'] = 'provisional_default'
            if analysis['envelope']
              x, y = analysis.fetch('source_plan_envelope', analysis['envelope'])
              part['source_box'] = [x + part['origin'][0], y + part['origin'][1],
                                    x + part['origin'][0] + part['size'][0], y + part['origin'][1] + part['size'][1]]
              part['plan_box'] = part['source_box'].dup
            end
          end
        end
        raise ArgumentError, 'Chưa có box module; vùng chọn chỉ có phần phụ mỏng.' if modules.empty?
        all = modules + trims
        bounds = 3.times.map { |i| all.map { |p| p['origin'][i] + p['size'][i] }.max.round(4) }
        if analysis.dig('build_stages', 'elevation') == false && analysis['envelope']
          envelope = analysis.fetch('source_plan_envelope', analysis['envelope'])
          measured = [envelope[2] - envelope[0], envelope[3] - envelope[1]]
          # Two exterior stock panels are the allowed auxiliary extent change.
          if 2.times.any? { |i| (bounds[i] - measured[i]).abs > 2 * STOCK.max + TOLERANCE }
            raise ArgumentError, "Box đúng rộng/sâu #{bounds[0, 2].join(' × ')} mm nhưng nguồn CAD đang sửa là #{measured.map { |v| v.round(2) }.join(' × ')} mm. Chênh quá hai tấm 36 mm; có thể đang sửa nhầm sản phẩm. Hủy sửa và chọn đúng khối SP trước."
          end
        end
        { 'modules' => modules, 'trim_parts' => trims, 'panel_parts' => [], 'bounds' => bounds }
      end

      def plan_offset(parts, analysis, capture = nil)
        previous = analysis.fetch('plan_origin_offset_mm', [0, 0])
        return previous unless analysis.dig('build_stages', 'elevation') == false
        base = analysis.fetch('source_plan_envelope', analysis.fetch('envelope', [0, 0]))
        # Box origins are normalised as a set. Put that measured minimum back
        # when the user drew on the source; changed module widths must not lose Y.
        if capture && analysis.dig('placement', 'mode') == 'source_plan'
          minimum = capture['normalised_from']
          origin = analysis.dig('placement', 'origin_mm')
          if minimum.is_a?(Array) && origin.is_a?(Array) && minimum.length == 3 && origin.length == 2
            measured = 2.times.map { |i| origin[i] + minimum[i] - base[i] }
            return measured.map { |v| v.round(4) } if measured.all? { |v| v.finite? && v.abs <= 2 * STOCK.max }
          end
        end
        shift = if analysis['plan_origin_basis'] == 'source_plan_envelope'
                  [0, 0]
                else
                  2.times.map { |i| analysis.fetch('envelope', base)[i] - base[i] }
                end
        offsets = parts['modules'].map do |part|
          matches = Array(analysis['modules']).select { |old| (old['size'][0] - part['size'][0]).abs <= TOLERANCE }
          return previous unless matches.length == 1
          old = matches.first
          [shift[0] + old['origin'][0] - part['origin'][0], shift[1] + old['origin'][1] + old['size'][1] - part['origin'][1] - part['size'][1]]
        end
        first = offsets.first
        return previous unless offsets.all? { |row| 2.times.all? { |i| (row[i] - first[i]).abs <= TOLERANCE && row[i].abs <= 2 * STOCK.max } }
        2.times.map { |i| (previous[i] + first[i]).round(4) }
      end
    end
  end
end

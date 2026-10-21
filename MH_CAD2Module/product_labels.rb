# frozen_string_literal: true

module MH
  module CAD2Module
    # Same Curic Text options as MH_Registry Tổng hợp; placement also reserves SP width.
    module ProductLabels
      DICT = 'MH_CAD2Module_Label'
      module_function

      def ensure_label(model, code, width)
        found = Model.labels(model)
        matched = found.select { |label| label['code'] == code }
        raise ArgumentError, "Có #{matched.length} nhãn #{code}; cần phân biệt vị trí trước khi dựng." if matched.length > 1
        return matched.first unless matched.empty?
        widths = Model.products(model).each_with_object({}) do |product, result|
          analysis = JSON.parse(product.get_attribute(Model::DICT, 'analysis', '{}'))
          size = analysis.dig('display_layout', 'total_width_mm') || analysis.dig('bounds', 0) || 0
          size = [size, analysis.fetch('cad_reference_reserved_width_mm', size)].max
          key = product.get_attribute(Model::DICT, 'code')
          result[key] = [result[key] || 0, size].max
        end
        # Root labels have a persisted reservation even if their modules were removed.
        root_labels = model.entities.grep(Sketchup::Group) + model.entities.grep(Sketchup::ComponentInstance) # rubocop:disable SketchupSuggestions/ModelEntities -- Labels are world-level.
        root_labels.each do |entity|
          key = entity.get_attribute(DICT, 'code')
          widths[key] = [widths[key] || 0, entity.get_attribute(DICT, 'reserved_width_mm', 0)].max if key
        end
        occupied = found.map { |label| [label['center_x'], widths[label['code']] || 0] }
        x = Placement.next_label_x(occupied, width)
        if defined?(CURIC::Text) && CURIC::Text.respond_to?(:place)
          options = CURIC::Text.default_text_options.dup
          options.merge!(size: 19.68503937007874, border: true, border_type: 'Rounded Rectangle',
                         border_radius: 11.811023622047244, border_padding: 0.1, align: 1, vertical_align: 1,
                         position: Geom::Point3d.new(x.mm, -1000.mm, 0))
          CURIC::Text.place(model.entities, code, **options) # rubocop:disable SketchupSuggestions/ModelEntities -- Match Registry world label placement.
        else
          fallback(model, code, x)
        end
        label = Model.labels(model).find { |item| item['code'] == code }
        raise ArgumentError, "Không tạo được nhãn #{code}." unless label
        entity = model.find_entity_by_persistent_id(label['id'])
        entity.set_attribute(DICT, 'code', code)
        entity.set_attribute(DICT, 'reserved_width_mm', width)
        label
      end

      def fallback(model, code, x)
        group = model.entities.add_group # rubocop:disable SketchupSuggestions/ModelEntities -- Independent world-level SP label.
        group.name = code
        group.set_attribute(DICT, 'code', code)
        group.entities.add_3d_text(code, TextAlignCenter, 'Arial', false, false, 500.mm, 0.0, 0.0, true, 0.0)
        box = group.bounds
        points = [[box.min.x - 50.mm, box.min.y - 50.mm, 0], [box.max.x + 50.mm, box.min.y - 50.mm, 0],
                  [box.max.x + 50.mm, box.max.y + 50.mm, 0], [box.min.x - 50.mm, box.max.y + 50.mm, 0]]
        points.each_with_index { |point, i| group.entities.add_line(point, points[(i + 1) % 4]) }
        center = group.bounds.center
        group.transformation = Geom::Transformation.translation([x.mm - center.x, -1000.mm - center.y, 0])
      end
    end
  end
end

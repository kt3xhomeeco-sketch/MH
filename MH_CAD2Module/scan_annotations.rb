# frozen_string_literal: true

require 'json'
require 'digest'

module MH
  module CAD2Module
    # Read semantic CAD labels only in the combined scan. Never OCR edge graphics.
    module ScanAnnotations
      module_function

      def fold(value)
        value.to_s.tr('đĐ_', 'dD ').unicode_normalize(:nfd).gsub(/\p{Mn}/, '').upcase
      end

      def title?(value)
        fold(value).match?(/\b(MAT (DUNG|BANG|CAT|BEN)|CAT BANG)\b/)
      end

      def metadata(entity)
        attributes = {}
        owners = [entity]
        owners.unshift(entity.definition) if Model.container?(entity)
        owners.each do |owner|
          owner.attribute_dictionaries&.each do |dictionary|
            dictionary.each_pair do |key, value|
              next unless value.is_a?(String) || value.is_a?(Numeric)
              text = value.to_s.strip
              next if text.empty? || text.length > 256 || key.to_s.start_with?('_')
              if key.to_s.match?(/\A[1245]\z|text|value|caption/i) || title?(text)
                attributes[key.to_s] = text
              end
            end
          end
        end
        names = Model.container?(entity) ? [entity.name, entity.definition.name].reject(&:empty?) : []
        { 'names' => names, 'attributes' => attributes }
      end

      def signature(entity, transform)
        value = metadata(entity)
        if entity.is_a?(Sketchup::Text)
          value = value.merge('text' => entity.text, 'point' => entity.point.transform(transform).to_a.map(&:to_mm))
        elsif Model.container?(entity)
          matrix = transform * entity.transformation
          value = value.merge('bounds' => 8.times.map { |i| entity.definition.bounds.corner(i).transform(matrix).to_a.map(&:to_mm) })
        end
        Digest::SHA256.hexdigest(JSON.generate(value))
      end

      def text_record(entity, transform, path)
        { 'handle' => (path + [entity.persistent_id]).join('/'), 'text' => entity.text,
          'point' => entity.point.transform(transform).to_a.map(&:to_mm), 'path' => path }
      end

      def container_record(entity, transform, path, lines)
        meta = metadata(entity)
        attributes = meta['attributes']
        named = meta['names'].any? { |name| fold(name).match?(/SECTION (MARK|SYMBOL)|KY HIEU (MAT CAT|MC)/) }
        paired = %w[1 2 4 5].all? { |key| attributes.key?(key) } && attributes['1'] == attributes['2'] && attributes['4'] == attributes['5']
        texts = attributes.values.select { |text| title?(text) }.uniq
        texts = meta['names'].select { |text| title?(text) }.uniq if texts.empty?
        return if !named && !paired && texts.empty?
        matrix = transform * entity.transformation
        corners = 8.times.map { |i| entity.definition.bounds.corner(i).transform(matrix).to_a.map(&:to_mm) }
        origin = Geom::Point3d.new.transform(matrix).to_a.map(&:to_mm)
        basis = [[1, 0, 0], [0, 1, 0]].map { |point| Geom::Point3d.new(point).transform(matrix).to_a.map(&:to_mm).zip(origin).map { |a, b| a - b } }
        meta.merge('handle' => path.join('/'), 'path' => path, 'texts' => texts,
                   'symbol' => named || paired, 'point' => 3.times.map { |i| corners.map { |p| p[i] }.min },
                   'center' => 3.times.map { |i| corners.sum { |p| p[i] } / 8.0 }, 'basis' => basis,
                   'segments' => lines.map { |line| line.slice('handle', 'path', 'a', 'b') })
      end

      def project(records, axes, offset, flat, window, model)
        included = lambda do |point|
          next false if (point[flat] - offset).abs > 0.1
          next true unless window
          screen = model.active_view.screen_coords(Geom::Point3d.new(point.map(&:mm)))
          screen.x >= window[0] && screen.x <= window[2] && screen.y >= window[1] && screen.y <= window[3]
        end
        output = []; issues = []
        records.each do |record|
          points = record['symbol'] ? record['segments'].flat_map { |line| [line['a'], line['b']] } : [record['point']]
          unless !points.empty? && points.all? { |point| included.call(point) }
            issues << 'Ký hiệu cắt nằm ngoài hoặc chỉ một phần trong vùng quét; không dùng gán chiều cao.' if record['symbol']
            next
          end
          row = record.merge('point' => axes.map { |i| record['point'][i] })
          row['center_x'] = record['center'][axes[0]] if record['center']
          row['basis'] = record['basis'].map { |p| axes.map { |i| p[i] } } if record['basis']
          row['segments'] = record['segments'].map { |line| line.merge('a' => axes.map { |i| line['a'][i] }, 'b' => axes.map { |i| line['b'][i] }) } if record['symbol']
          row.delete('segments') unless record['symbol']
          row.delete('center')
          output << row
        end
        { 'schema' => 1, 'objects' => output, 'issues' => issues.uniq }
      end

      def validate_watch(watch, model)
        Array(watch).each do |identity, path, expected|
          owner = model; transform = Geom::Transformation.new
          Array(path).each do |id|
            item = model.find_entity_by_persistent_id(id)
            raise ArgumentError, 'Nhóm ký hiệu CAD đã đổi; quét lại nguồn.' unless Model.container?(item) && item.parent == owner
            transform *= item.transformation
            owner = item.definition
          end
          entity = model.find_entity_by_persistent_id(identity)
          unless entity && entity.valid? && entity.parent == owner && signature(entity, transform) == expected
            raise ArgumentError, 'Chữ/ký hiệu mặt cắt đã đổi trong lúc đọc; quét lại nguồn.'
          end
        end
        true
      end
    end
  end
end

# frozen_string_literal: true

require 'digest'
require_relative 'scan_annotations'

module MH
  module CAD2Module
    # Read selected native edges in world coordinates; importing into SketchUp already converts units.
    module SelectionSource
      module_function

      def build_request(geometry)
        { 'action' => 'geometry', 'geometry' => geometry, 'code' => "SCAN-#{Ids.uuid.upcase}",
          'name' => 'Vùng quét CAD', 'automatic_scan' => true }
      end

      def stroke(edge, inherited = nil)
        layer = edge.layer
        layer = inherited if inherited && layer == edge.model.layers[0]
        line = layer.line_style&.name || 'CONTINUOUS'
        data = { 'layer' => layer.name, 'linetype' => line, 'continuous' => line.match?(/\A(?:CONTINUOUS|SOLID|DEFAULT)\z/i),
                 'color' => layer.color.to_i }
        data['true_color'] = edge.material.color.to_i if edge.material
        data
      end

      def capture(model = Sketchup.active_model, window: nil, include_views: nil)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        settings = Settings.read(model)
        include_views = settings['build_elevation'] if include_views.nil?
        selected = model.selection.to_a
        raise ArgumentError, 'Chọn group hoặc các nét CAD đã dán/import vào SketchUp trước.' if selected.empty?
        lines = []
        notes = []; watches = {}
        initial_path = Array(model.active_path).map(&:persistent_id)
        walk = lambda do |entities, transform, depth, path, inherited|
          raise ArgumentError, 'Nguồn CAD lồng quá 15 cấp.' if depth > 15
          entities.each do |entity|
            if entity.is_a?(Sketchup::Edge)
              a = entity.start.position.transform(transform).to_a.map(&:to_mm)
              b = entity.end.position.transform(transform).to_a.map(&:to_mm)
              lines << { 'a' => a, 'b' => b, 'handle' => entity.persistent_id.to_s, 'path' => path }.merge(stroke(entity, inherited))
            elsif Model.container?(entity)
              next if entity.get_attribute(Model::DICT, 'role') || entity.get_attribute('MH_CAD2Module_Label', 'code')
              text_group = entity.get_attribute('Curic Single-Line Text', 'text')
              next if text_group && !include_views
              index = lines.length
              child_path = path + [entity.persistent_id]
              layer = entity.layer == model.layers[0] ? inherited : entity.layer
              walk.call(entity.definition.entities, transform * entity.transformation, depth + 1, child_path, layer) unless text_group
              if include_views
                note = ScanAnnotations.container_record(entity, transform, child_path, lines[index..])
                if note
                  note['text_graphics'] = !!text_group || note['attributes'].any? { |key, value| key.match?(/text|caption/i) && ScanAnnotations.title?(value) }
                  notes << note
                  watches[note['handle']] = [entity.persistent_id, path, ScanAnnotations.signature(entity, transform)]
                end
              end
            elsif include_views && entity.is_a?(Sketchup::Text)
              note = ScanAnnotations.text_record(entity, transform, path)
              notes << note
              watches[note['handle']] = [entity.persistent_id, path, ScanAnnotations.signature(entity, transform)]
            elsif entity.is_a?(Sketchup::Face)
              entity.edges.each do |edge|
                a = edge.start.position.transform(transform).to_a.map(&:to_mm)
                b = edge.end.position.transform(transform).to_a.map(&:to_mm)
                lines << { 'a' => a, 'b' => b, 'handle' => edge.persistent_id.to_s, 'path' => path }.merge(stroke(edge, inherited))
              end
            end
          end
        end
        inherited = Array(model.active_path).reverse.find { |e| e.layer != model.layers[0] }&.layer
        walk.call(selected, model.edit_transform, 0, initial_path, inherited)
        lines.uniq! { |line| include_views ? [line['path'], [line['a'], line['b']].sort] : [line['a'], line['b']].sort }
        if window
          lines.select! do |line|
            [line['a'], line['b']].all? do |values|
              point = model.active_view.screen_coords(Geom::Point3d.new(values.map(&:mm)))
              point.x >= window[0] && point.x <= window[2] && point.y >= window[1] && point.y <= window[3]
            end
          end
        end
        raise ArgumentError, 'Vùng chọn chưa có cạnh CAD. Không chọn riêng nhãn sản phẩm.' if lines.empty?
        raise ArgumentError, 'Vùng chọn vượt 15.000 cạnh; chọn gọn một sản phẩm.' if lines.length > 15_000
        points = lines.flat_map { |line| [line['a'], line['b']] }
        ranges = 3.times.map { |i| points.map { |p| p[i] }.minmax }
        flat = 3.times.find { |i| ranges[i][1] - ranges[i][0] < 0.1 }
        raise ArgumentError, 'Nét CAD chưa nằm trên cùng mặt phẳng XY/XZ/YZ. Chọn đúng nhóm hình chiếu 2D.' unless flat
        axes = [0, 1, 2] - [flat]
        data = { 'lines' => lines.map { |line| line.merge('a' => axes.map { |i| line['a'][i] }, 'b' => axes.map { |i| line['b'][i] }) },
                 'plane' => %w[YZ XZ XY][flat], 'plane_offset_mm' => ranges[flat].sum / 2.0, 'model_path' => model.path,
                 'source_watch' => lines.map { |line| [line['handle'], line['path'], line['a'], line['b'], line.slice('layer', 'linetype', 'continuous', 'color', 'true_color')] } }
        if include_views
          data['scan_annotations'] = ScanAnnotations.project(notes, axes, data['plane_offset_mm'], flat, window, model)
          data['annotation_watch'] = data['scan_annotations']['objects'].map { |note| watches.fetch(note['handle']) }
        end
        root = Settings.library(settings)
        # Content-address the selected geometry, independent of model filename and native entity IDs.
        canonical = data['lines'].map { |line| [[line['a'], line['b']].sort, line.slice('layer', 'linetype', 'continuous', 'color', 'true_color')] }.sort_by { |row| JSON.generate(row) }
        identity = [data['plane'], data['plane_offset_mm'], canonical]
        identity << data['scan_annotations'] if include_views
        hash = Digest::SHA256.hexdigest(JSON.generate(identity))
        folder = File.join(root, 'sources', hash)
        FileUtils.mkdir_p(folder)
        data['hash'] = hash
        Storage.write_json(File.join(folder, 'source_geometry.json'), data) unless File.file?(File.join(folder, 'source_geometry.json'))
        path = File.join(folder, 'source_geometry.skp')
        unless File.file?(path)
          model.start_operation('CAD2Module: Lưu Nguồn CAD', true)
          operation = true
          definition = model.definitions.add('CAD2Module_Source_Snapshot')
          lines.each { |line| definition.entities.add_line(line['a'].map(&:mm), line['b'].map(&:mm)) }
          raise IOError, 'Không lưu được bản nét CAD độc lập.' unless definition.save_as(path)
          model.abort_operation
          operation = false
        end
        data['capture_seconds'] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        data
      ensure
        model.abort_operation if operation
      end

      def validate_watch(watch, model = Sketchup.active_model)
        transforms = {}
        owner_edges = {}
        Array(watch).each do |identity, path, a, b, style|
          transform, owner, inherited = transforms[path] ||= begin
            current = model
            matrix = Geom::Transformation.new
            layer = nil
            Array(path).each do |id|
              instance = model.find_entity_by_persistent_id(id)
              unless Model.container?(instance) && instance.parent == current
                raise ArgumentError, 'Nguồn CAD đã đổi/xóa nhóm trong lúc AI chạy; quét lại nguồn.'
              end
              matrix *= instance.transformation
              layer = instance.layer unless instance.layer == model.layers[0]
              current = instance.definition
            end
            [matrix, current, layer]
          end
          # Resolve the owner once, then index its direct edges once. A global
          # model lookup for every CAD segment is costly in a nesting drawing.
          edges = owner_edges[owner] ||= owner.entities.grep(Sketchup::Edge).to_h { |item| [item.persistent_id, item] }
          edge = edges[identity.to_i]
          unless edge.is_a?(Sketchup::Edge) && edge.valid? && edge.parent == owner
            raise ArgumentError, 'Cạnh CAD đã thay đổi trong lúc AI chạy; quét lại nguồn.'
          end
          now = [edge.start.position, edge.end.position].map { |point| point.transform(transform).to_a.map(&:to_mm) }
          same = [[a, b], [b, a]].any? { |points| now.zip(points).all? { |x, y| x.zip(y).all? { |u, v| (u - v).abs <= 0.05 } } }
          raise ArgumentError, 'Vị trí CAD đã thay đổi trong lúc AI chạy; quét lại nguồn.' unless same
          raise ArgumentError, 'Layer/màu/kiểu nét CAD đã thay đổi; quét lại nguồn.' if style && stroke(edge, inherited) != style
        end
        true
      end
    end
  end
end

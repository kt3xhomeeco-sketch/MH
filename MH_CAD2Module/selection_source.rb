# frozen_string_literal: true

require 'digest'

module MH
  module CAD2Module
    # Read selected native edges in world coordinates; importing into SketchUp already converts units.
    module SelectionSource
      module_function

      def build_request(geometry)
        { 'action' => 'geometry', 'geometry' => geometry, 'code' => "SCAN-#{Ids.uuid.upcase}",
          'name' => 'Vùng quét CAD', 'automatic_scan' => true }
      end

      def capture(model = Sketchup.active_model, window: nil)
        selected = model.selection.to_a
        raise ArgumentError, 'Chọn group hoặc các nét CAD đã dán/import vào SketchUp trước.' if selected.empty?
        lines = []
        initial_path = Array(model.active_path).map(&:persistent_id)
        walk = lambda do |entities, transform, depth, path|
          raise ArgumentError, 'Nguồn CAD lồng quá 15 cấp.' if depth > 15
          entities.each do |entity|
            if entity.is_a?(Sketchup::Edge)
              a = entity.start.position.transform(transform).to_a.map(&:to_mm)
              b = entity.end.position.transform(transform).to_a.map(&:to_mm)
              lines << { 'a' => a, 'b' => b, 'handle' => entity.persistent_id.to_s, 'layer' => entity.layer.name, 'path' => path }
            elsif Model.container?(entity)
              next if entity.get_attribute(Model::DICT, 'role') || entity.get_attribute('Curic Single-Line Text', 'text')
              walk.call(entity.definition.entities, transform * entity.transformation, depth + 1, path + [entity.persistent_id])
            elsif entity.is_a?(Sketchup::Face)
              entity.edges.each do |edge|
                a = edge.start.position.transform(transform).to_a.map(&:to_mm)
                b = edge.end.position.transform(transform).to_a.map(&:to_mm)
                lines << { 'a' => a, 'b' => b, 'handle' => edge.persistent_id.to_s, 'layer' => edge.layer.name, 'path' => path }
              end
            end
          end
        end
        walk.call(selected, model.edit_transform, 0, initial_path)
        lines.uniq! { |line| [line['a'], line['b']].sort }
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
                 'source_watch' => lines.map { |line| [line['handle'], line['path'], line['a'], line['b']] } }
        root = Settings.library
        # Content-address the selected geometry, independent of model filename and native entity IDs.
        canonical = data['lines'].map { |line| [line['a'], line['b']].sort }.sort
        hash = Digest::SHA256.hexdigest(JSON.generate([data['plane'], data['plane_offset_mm'], canonical]))
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
        data
      ensure
        model.abort_operation if operation
      end

      def validate_watch(watch, model = Sketchup.active_model)
        transforms = {}
        owner_edges = {}
        Array(watch).each do |identity, path, a, b|
          transform, owner = transforms[path] ||= begin
            current = model
            matrix = Geom::Transformation.new
            Array(path).each do |id|
              instance = model.find_entity_by_persistent_id(id)
              unless Model.container?(instance) && instance.parent == current
                raise ArgumentError, 'Nguồn CAD đã đổi/xóa nhóm trong lúc AI chạy; quét lại nguồn.'
              end
              matrix *= instance.transformation
              current = instance.definition
            end
            [matrix, current]
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
        end
        true
      end
    end
  end
end

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
        walk = lambda do |entities, transform, depth|
          raise ArgumentError, 'Nguồn CAD lồng quá 15 cấp.' if depth > 15
          entities.each do |entity|
            if entity.is_a?(Sketchup::Edge)
              a = entity.start.position.transform(transform).to_a.map(&:to_mm)
              b = entity.end.position.transform(transform).to_a.map(&:to_mm)
              lines << { 'a' => a, 'b' => b, 'handle' => entity.persistent_id.to_s, 'layer' => entity.layer.name }
            elsif Model.container?(entity)
              next if entity.get_attribute(Model::DICT, 'role') || entity.get_attribute('Curic Single-Line Text', 'text')
              walk.call(entity.definition.entities, transform * entity.transformation, depth + 1)
            elsif entity.is_a?(Sketchup::Face)
              entity.edges.each do |edge|
                a = edge.start.position.transform(transform).to_a.map(&:to_mm)
                b = edge.end.position.transform(transform).to_a.map(&:to_mm)
                lines << { 'a' => a, 'b' => b, 'handle' => edge.persistent_id.to_s, 'layer' => edge.layer.name }
              end
            end
          end
        end
        walk.call(selected, model.edit_transform, 0)
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
                 'plane' => %w[YZ XZ XY][flat], 'plane_offset_mm' => ranges[flat].sum / 2.0, 'model_path' => model.path }
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
    end
  end
end

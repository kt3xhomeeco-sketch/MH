# encoding: UTF-8
require 'json'
require 'tmpdir'
require 'timeout'
require_relative 'core'
require_relative 'dc_function_capture'

module MH
  module ModuleStudio
    module Reader
      extend self
      DICT = 'MH_Module_Studio'.freeze

      def definition_function_source(definition)
        DCFunctionCapture.definition_function_source(definition)
      end

      def capture_definition_aliases!(definition, snapshot)
        DCFunctionCapture.capture_definition_aliases!(definition, snapshot)
      end

      def enrich_file_functions!(snapshot, path)
        DCFunctionCapture.enrich_file_functions!(snapshot, path)
      end

      def semantic_name(name)
        text = name.to_s.strip
        text = text.unicode_normalize(:nfc) if text.respond_to?(:unicode_normalize)
        text.downcase.sub(/#\d+\z/, '').strip
      end

      def part_key(stored,path,counts)
        return stored unless stored.empty?
        base = path.join(' / ')
        counts[base] = counts.fetch(base,0)+1
        counts[base]==1 ? base : "#{base} [#{counts[base]}]"
      end

      def part(key, name, points, faces, edges, verified, visible, attributes = {})
        bounds = Frames.box(points.map { |point| point.map { |value| value * 25.4 } })
        { 'key' => key, 'name' => name, 'bounds' => bounds,
          'thickness_axis' => Core.thickness_axis(bounds), 'box_verified' => verified,
          'face_count' => faces, 'edge_count' => edges, 'visible' => visible,
          'dc_attributes' => attributes }
      end

      def make_snapshot(parts, label, parameter, source, dc_inputs = {})
        snapshot = { 'id' => Core::Ids.uuid, 'label' => label.to_s[0, 160],
                     'parameter' => parameter.nil? ? nil : Core.number(parameter), 'source' => source,
                     'parts' => parts, 'envelope' => Core.union(parts), 'dc_inputs' => dc_inputs,
                     'captured_at' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ') }
        Core.snapshot!(snapshot)
        # A nil input explicitly requests measurement instead of a typed value.
        if parameter.nil?
          begin
            Core.capture_parameter!(snapshot, multiple: true)
          rescue Core::Error=>error
            raise unless error.message=='Không tìm thấy tấm có độ dày để tạo tham số.'
            snapshot['parameter']=0.0
            snapshot['parameter_source']={'kind'=>'no_board_thickness'}
          end
        end
        snapshot
      end

      def dynamic_attributes(entity)
        dictionary = entity.attribute_dictionary('dynamic_attributes', false)
        attributes = {}
        dictionary.each_pair { |key, value| attributes[key] = value } if dictionary
        attributes
      end

      def live(root, label:, parameter:)
        model = root.model
        world = model.edit_transform * root.transformation
        frame = Frames.scale_frame(world.to_a)
        parts = []
        bindings = {}
        graph = []
        derived_keys = {}
        entity_paths = {''=>[]}
        walk = lambda do |entity, transform, names, ancestors, depth, visible, parent_id|
          raise Core::Error, 'Module lồng quá sâu.' if depth > 30
          definition = entity.definition
          raise Core::Error, 'Cấu trúc definition lặp vòng.' if ancestors.include?(definition)
          entries = definition.entities.to_a
          faces = entries.grep(Sketchup::Face)
          edges = entries.grep(Sketchup::Edge)
          children = entries.select { |entry| entry.is_a?(Sketchup::Group) || entry.is_a?(Sketchup::ComponentInstance) }
          attributes = DCFrames.merge_attributes(dynamic_attributes(definition),dynamic_attributes(entity))
          display_name = entity.name.to_s.strip
          display_name = attributes['_name'].to_s.strip if display_name.empty?
          display_name = definition.name.to_s if display_name.empty?
          display_name = 'Chi tiết không tên' if display_name.empty?
          path_names = names + [semantic_name(display_name)]
          key = entity.get_attribute(DICT, 'part_key').to_s
          key = part_key(key,path_names,derived_keys) if !faces.empty? || !edges.empty?
          graph_id = graph.length.to_s
          entity_paths[graph_id] = entity_paths.fetch(parent_id)+[entity]
          raise Core::Error, 'Cây module vượt 1200 group/component.' if graph.length >= 1200
          graph << { 'id' => graph_id, 'parent_id' => parent_id, 'path' => path_names, 'name' => display_name,
                     'attributes' => attributes, 'transform' => entity.transformation.to_a,
                     'local_bounds' => [definition.bounds.min.to_a, definition.bounds.max.to_a],
                     'hidden'=>entity.hidden?, 'tag_visible'=>entity.layer.visible?,
                     'visibility_flattened'=>entity.get_attribute(DICT,'visibility_flattened',false),
                     'part_key' => (!faces.empty? || !edges.empty?) ? key : nil }
          if !faces.empty? || !edges.empty?
            local_points = (faces.flat_map(&:vertices) + edges.flat_map(&:vertices)).uniq.map { |vertex| vertex.position.to_a }
            points = local_points.map { |point| Frames.point(transform, point) }
            verified = rectangular_box?(points, faces, edges, children)
            captured = part(key, display_name, points, faces.length, edges.length, verified, visible, attributes)
            captured['affine_verified'] = orthogonal_surfaces?(faces,transform)
            captured['linear_mesh_verified'] = !faces.empty? && children.empty? && edges.none? { |edge| edge.curve.is_a?(Sketchup::ArcCurve) }
            parts << captured
            bindings[key] = { entity: entity, frame: transform, visibility_path: entity_paths[graph_id], visibility_flattened: entity.get_attribute(DICT,'visibility_flattened',false) }
          end
          children.each do |child|
            walk.call(child, Frames.multiply(transform, child.transformation.to_a), path_names,
                      ancestors + [definition], depth + 1, visible && !child.hidden? && child.layer.visible?, graph_id)
          end
          raise Core::Error, 'Module vượt 600 chi tiết.' if parts.length > Core::MAX_PARTS
        end
        root_definition = root.definition
        children = root_definition.entities.to_a.select { |entry| entry.is_a?(Sketchup::Group) || entry.is_a?(Sketchup::ComponentInstance) }
        root_faces=root_definition.entities.grep(Sketchup::Face)
        root_edges=root_definition.entities.grep(Sketchup::Edge)
        unless root_faces.empty? && root_edges.empty?
          # Represent direct mesh as a virtual child. Its binding still owns
          # only the parent's direct mesh, never independently driven children.
          key=root.get_attribute(DICT,'part_key','root:mesh')
          points=(root_faces.flat_map(&:vertices)+root_edges.flat_map(&:vertices)).uniq.map { |v| v.position.to_a }
          transformed=points.map { |point| Frames.point(frame,point) }
          name=module_name(root)
          captured=part(key,name,transformed,root_faces.length,root_edges.length,rectangular_box?(transformed,root_faces,root_edges,children),!root.hidden?,{})
          captured['affine_verified']=orthogonal_surfaces?(root_faces,frame)
          captured['linear_mesh_verified']=!root_faces.empty? && children.empty? && root_edges.none? { |edge| edge.curve.is_a?(Sketchup::ArcCurve) }
          parts << captured
          local_box=Frames.box(points)
          whole=children.empty? || Core.bounds_close?(local_box,[root_definition.bounds.min.to_a,root_definition.bounds.max.to_a],0.000001)
          proxy=whole ? {'_lengthunits'=>'MILLIMETERS','_lenx_formula'=>'parent!LenX','_leny_formula'=>'parent!LenY','_lenz_formula'=>'parent!LenZ'} : {}
          graph << {'id'=>'root:mesh','parent_id'=>'','path'=>['root:mesh'],'name'=>name,'attributes'=>proxy,'virtual_root_mesh'=>whole,'transform'=>Frames::IDENTITY.dup,
                    'local_bounds'=>Frames.box(points),'hidden'=>root.hidden?,'tag_visible'=>root.layer.visible?,'part_key'=>key}
          bindings[key]={entity:root,frame:frame,visibility_path:[root],visibility_flattened:true}
        end
        children.each do |child|
          walk.call(child, Frames.multiply(frame, child.transformation.to_a), [], [root_definition], 1,
                    !child.hidden? && child.layer.visible?, '')
        end
        snapshot = make_snapshot(parts, label, parameter, { 'kind' => 'selection', 'root_pid' => root.persistent_id.to_s },
                                 DCFrames.merge_attributes(dynamic_attributes(root_definition),dynamic_attributes(root)))
        snapshot['dc_graph'] = { 'nodes' => graph, 'root_frame' => frame }
        snapshot['module_name'] = module_name(root)
        source_path=root.get_attribute(DICT,'library_source_path')
        snapshot['source']['path']=source_path if source_path.is_a?(String) && !source_path.empty?
        snapshot['visibility_version'] = 1
        snapshot['formula_frame_version'] = 2
        DCFunctionCapture.capture_function_aliases!(snapshot)
        capture_definition_aliases!(root_definition, snapshot)
        saved_values = root.get_attribute(DICT, 'parameter_values_json')
        snapshot['parameter_values'] = JSON.parse(saved_values) if saved_values.is_a?(String)
        read_formula_envelope(root,frame,snapshot)
        [snapshot, bindings]
      end

      def module_name(root)
        name=root.name.to_s.strip
        definition_name=root.definition.name.to_s.strip
        if Parametric.capture_label?(name) && !definition_name.empty? && !Parametric.capture_label?(definition_name)
          name=definition_name
        end
        attrs=DCFrames.merge_attributes(dynamic_attributes(root.definition),dynamic_attributes(root)) if name.empty?
        name=Core.dc_label(attrs['_name']) if attrs
        name=root.definition.name.to_s.strip if name.empty?
        name.empty? ? 'Module' : name[0,120]
      end

      def read_formula_envelope(root,frame,snapshot)
        raw = root.get_attribute(DICT,'formula_envelope_json')
        return unless raw.is_a?(String)
        local = Core.bounds!(JSON.parse(raw))
        snapshot['formula_envelope'] = Frames.box(Frames.corners(local).map { |point| Frames.point(frame,point) })
      end

      def rectangular_box?(points, faces, edges, children)
        return false unless children.empty? && faces.length == 6 && edges.length == 12
        return false unless faces.all? { |face| face.loops.length == 1 && face.vertices.length == 4 }
        bounds = Frames.box(points)
        return false unless Core.dimensions(bounds).all? { |dimension| dimension > 0.00001 }
        epsilon = 0.01 / 25.4
        unique = points.map { |point| point.map { |v| (v / epsilon).round } }.uniq
        return false unless unique.length == 8
        points.all? { |point| 3.times.all? { |axis| [0, 1].any? { |side| (point[axis] - bounds[side][axis]).abs <= epsilon } } }
      end

      # Fixed orthogonal surface meshes can resize by a positive diagonal map,
      # including partial shells with separately driven child faces. Curved or
      # oblique surfaces retain the rigid-only policy.
      def orthogonal_surfaces?(faces,frame)
        return false if faces.empty?
        faces.all? do |face|
          points = face.vertices.map { |vertex| Frames.point(frame,vertex.position.to_a) }
          Core.dimensions(Frames.box(points)).count { |size| size.abs<=0.000001 }==1
        end
      end

      def bridge_path
        candidates = [ENV['MH_MODULE_STUDIO_BRIDGE'],
                      File.join(ENV.fetch('USERPROFILE', ''), 'Documents', 'MH_Apps', 'MH_Thongke_Desktop', 'bin', 'MH_SkpBridge.exe'),
                      File.join(ENV.fetch('USERPROFILE', ''), 'Documents', 'MH_Apps', 'MH_SkpBridge', 'bin', 'MH_SkpBridge.exe')]
        candidates.compact.find { |path| !path.empty? && File.file?(path) }
      end

      def read_file(path, label:, parameter:)
        bridge = bridge_path
        raise Core::Error, 'Không tìm thấy bộ đọc SKP. Có thể dùng Đọc từ SketchUp, hoặc cấu hình MH_MODULE_STUDIO_BRIDGE.' unless bridge
        raise Core::Error, 'File SKP không tồn tại.' unless File.file?(path) && File.extname(path).downcase == '.skp'
        Dir.mktmpdir('mh-module-read-') do |directory|
          result_path = File.join(directory, 'result.json')
          error_path = File.join(directory, 'stderr.txt')
          pid = Process.spawn(bridge, 'scan-reader-context', '--input', path, '--result-file', result_path,
                              out: File::NULL, err: error_path)
          begin
            status = nil
            Timeout.timeout(60) { _finished, status = Process.waitpid2(pid) }
          rescue Timeout::Error
            Process.kill('KILL', pid) rescue nil
            Process.waitpid(pid) rescue nil
            raise Core::Error, 'Đọc SKP quá 60 giây. Thử đọc module trực tiếp từ SketchUp.'
          end
          stderr = File.file?(error_path) ? File.read(error_path, encoding: 'UTF-8')[0, 300] : ''
          raise Core::Error, "Bộ đọc SKP lỗi: #{stderr}" unless status.success? && File.file?(result_path)
          raise Core::Error, 'Dữ liệu SKP quá lớn.' if File.size(result_path) > 64 * 1024 * 1024
          response = JSON.parse(File.read(result_path, encoding: 'UTF-8').sub(/\A\uFEFF/, ''))
          raise Core::Error, response['error'].to_s unless response['ok']
          from_bridge(response.fetch('data'), label: label, parameter: parameter, path: path)
        end
      end

      def from_bridge(data, label:, parameter:, path: '')
        definitions = data.fetch('definitions')
        parts = []
        graph = []
        root_id = data.fetch('root', 'root')
        derived_keys = {}
        walk = lambda do |node, transform, names, ancestors, depth, visible, parent_id|
          raise Core::Error, 'Module lồng quá sâu hoặc lặp vòng.' if depth > 30 || ancestors.include?(node['definition'])
          definition = definitions.fetch(node['definition'])
          attrs = DCFrames.merge_attributes(definition['attributes'] || {},node['attributes'] || {},prefix:'dynamic_attributes/')
          dc = attrs.select { |key, _value| key.start_with?('dynamic_attributes/') }.to_h { |key, value| [key.delete_prefix('dynamic_attributes/'), value] }
          display_name = node['name'].to_s.strip
          display_name = dc['_name'].to_s.strip if display_name.empty?
          display_name = definition['name'].to_s if display_name.empty?
          display_name = 'Chi tiết không tên' if display_name.empty?
          path_names = names + [semantic_name(display_name)]
          key = attrs[DICT + '/part_key'].to_s
          key = part_key(key,path_names,derived_keys) if definition['hasGeometry']
          graph_id = graph.length.to_s
          raise Core::Error, 'Cây module vượt 1200 group/component.' if graph.length >= 1200
          graph << { 'id' => graph_id, 'parent_id' => parent_id, 'path' => path_names, 'name' => display_name,
                     'attributes' => dc, 'transform' => node['transform'] || Frames::IDENTITY,
                     'local_bounds' => definition['bounds'], 'part_key' => definition['hasGeometry'] ? key : nil }
          if definition['hasGeometry'] && definition['bounds']
            points = Frames.corners(definition['bounds']).map { |point| Frames.point(transform, point) }
            # SDK context contains bounds/counts, not vertices: never certify a solid from its bounds alone.
            parts << part(key, display_name, points, definition['faceCount'].to_i, definition['edgeCount'].to_i, false, visible, dc)
          end
          (definition['nodes'] || []).each do |child|
            child_transform = Frames.multiply(transform, child['transform'] || Frames::IDENTITY)
            walk.call(child, child_transform, path_names, ancestors + [node['definition']], depth + 1, visible && child['visible'] != false, graph_id)
          end
          raise Core::Error, 'Module vượt 600 chi tiết.' if parts.length > Core::MAX_PARTS
        end
        root = definitions.fetch(root_id)
        if root['hasGeometry']
          raise Core::Error, 'File chứa mặt/cạnh rời ở cấp gốc. Hãy đọc group cha trong SketchUp.'
        end
        roots = root['nodes'] || []
        # A whole-model SKP may contain one wrapper; read it like selecting that module in SketchUp.
        wrapper = roots.length == 1 ? roots.first : nil
        wrapper_definition = wrapper && definitions[wrapper['definition']]
        if wrapper_definition && !wrapper_definition['hasGeometry'] && !(wrapper_definition['nodes'] || []).empty?
          root_frame = Frames.scale_frame(wrapper['transform'] || Frames::IDENTITY)
          (wrapper_definition['nodes'] || []).each do |node|
            walk.call(node, Frames.multiply(root_frame, node['transform'] || Frames::IDENTITY), [],
                      [root_id, wrapper['definition']], 1, node['visible'] != false, '')
          end
        else
          roots.each { |node| walk.call(node, node['transform'] || Frames::IDENTITY, [], [root_id], 1, node['visible'] != false, '') }
        end
        dc_inputs = (data.dig('meta', 'model_attrs') || {}).select { |key, _value| key.start_with?('dynamic_attributes/') }
                   .to_h { |key, value| [key.delete_prefix('dynamic_attributes/'), value] }
        if wrapper_definition && !wrapper_definition['hasGeometry'] && !(wrapper_definition['nodes'] || []).empty?
          wrapper_attrs = DCFrames.merge_attributes(wrapper_definition['attributes'] || {},wrapper['attributes'] || {},prefix:'dynamic_attributes/')
          wrapper_attrs.each { |key, value| dc_inputs[key.delete_prefix('dynamic_attributes/')] = value if key.start_with?('dynamic_attributes/') }
        end
        snapshot = make_snapshot(parts, label, parameter, { 'kind' => 'skp', 'path' => path }, dc_inputs)
        snapshot['dc_graph'] = { 'nodes' => graph, 'root_frame' => root_frame || Frames::IDENTITY }
        DCFunctionCapture.capture_function_aliases!(snapshot)
        snapshot
      rescue KeyError, TypeError
        raise Core::Error, 'Dữ liệu bridge thiếu cấu trúc module.'
      end
    end
  end
end

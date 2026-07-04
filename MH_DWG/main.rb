# frozen_string_literal: true
# MH::DWG – Paste CAD Clipboard + Tag + Place Tool + Rotate

require "sketchup.rb"
require "json"

module MH
  module DWG

    TAG_NAME = "MH_DWG"
    LOG_FILE = File.join(__dir__, "mh_dwg_debug.log")

    def self.log_event(event, data = {})
      payload = {
        time: Time.now.strftime("%Y-%m-%d %H:%M:%S.%L"),
        event: event,
        pid: Process.pid,
        sketchup_version: (Sketchup.version rescue nil),
        ruby_version: RUBY_VERSION,
        data: data
      }

      File.open(LOG_FILE, "a:UTF-8") do |file|
        file.sync = true
        file.puts(JSON.generate(payload))
      end
    rescue => e
      puts "[MH_DWG LOG ERROR] #{e.class}: #{e.message}"
    end

    def self.point_log(pt)
      return nil unless pt
      [pt.x.to_f.round(4), pt.y.to_f.round(4), pt.z.to_f.round(4)]
    rescue
      nil
    end

    def self.transform_log(tr)
      return nil unless tr
      tr.to_a.map { |v| v.to_f.round(6) }
    rescue
      nil
    end

    def self.entity_log(ent)
      return nil unless ent
      {
        class: ent.class.name,
        valid: (ent.valid? rescue nil),
        persistent_id: (ent.persistent_id rescue nil),
        entity_id: (ent.entityID rescue nil),
        name: (ent.respond_to?(:name) ? ent.name.to_s : nil),
        definition: (ent.respond_to?(:definition) && ent.definition ? ent.definition.name.to_s : nil),
        visible: (ent.respond_to?(:visible?) ? ent.visible? : nil)
      }
    rescue => e
      { error: "#{e.class}: #{e.message}" }
    end

    def self.entities_summary(entities)
      counts = Hash.new(0)
      total = 0
      entities.each do |ent|
        total += 1
        counts[ent.class.name] += 1
      end
      { total: total, counts: counts }
    rescue => e
      { error: "#{e.class}: #{e.message}" }
    end

    def self.definition_summary(defn)
      return nil unless defn
      {
        name: defn.name.to_s,
        valid: (defn.valid? rescue nil),
        count_entities: (defn.entities.length rescue nil),
        bounds_empty: (defn.bounds.empty? rescue nil),
        bounds_min: (point_log(defn.bounds.min) rescue nil),
        bounds_max: (point_log(defn.bounds.max) rescue nil)
      }
    rescue => e
      { error: "#{e.class}: #{e.message}" }
    end

    def self.find_clipboard_dwg
      temp = ENV['TEMP'].tr('\\', '/')
      Dir.glob("#{temp}/A$C*.dwg").max_by { |f| File.mtime(f) }
    end

    def self.assign_tag(inst)
      return unless inst.is_a?(Sketchup::ComponentInstance)
      model = Sketchup.active_model
      tag = model.layers[TAG_NAME] || model.layers.add(TAG_NAME)
      inst.layer = tag
    end

    # Tìm vertex gần trục X nhất - CHỈ level 1 + bounding box cho nested
    def self.find_vertex_on_x_axis(entities)
      candidates = []
      tolerance = 0.1
      
      entities.each do |ent|
        case ent
        when Sketchup::Edge
          candidates << ent.start.position
          candidates << ent.end.position
        when Sketchup::Face
          ent.vertices.each { |v| candidates << v.position }
        when Sketchup::ComponentInstance, Sketchup::Group
          # Với nested - chỉ lấy corners của bounding box
          bounds = ent.bounds
          next if bounds.empty?
          8.times { |i| candidates << bounds.corner(i) }
        end
      end
      
      return ORIGIN if candidates.empty?
      
      # Lọc vertices nằm trên trục X (Y≈0, Z≈0)
      on_axis = candidates.select { |pt| pt.y.abs < tolerance && pt.z.abs < tolerance }
      
      if on_axis.any?
        on_axis.min_by { |pt| pt.x }
      else
        # Không có - lấy vertex gần trục X nhất
        candidates.min_by { |pt| pt.y.abs + pt.z.abs }
      end
    end

    # Tìm TẤT CẢ vertices nằm trên trục X (Y≈0, Z≈0) - sắp xếp theo X
    def self.find_all_vertices_on_x_axis(entities)
      candidates = []
      tolerance = 0.1
      
      entities.each do |ent|
        case ent
        when Sketchup::Edge
          candidates << ent.start.position
          candidates << ent.end.position
        when Sketchup::Face
          ent.vertices.each { |v| candidates << v.position }
        when Sketchup::ComponentInstance, Sketchup::Group
          bounds = ent.bounds
          next if bounds.empty?
          8.times { |i| candidates << bounds.corner(i) }
        end
      end
      
      return [ORIGIN] if candidates.empty?
      
      # Lọc vertices nằm trên trục X (Y≈0, Z≈0)
      on_axis = candidates.select { |pt| pt.y.abs < tolerance && pt.z.abs < tolerance }
      
      if on_axis.any?
        # Sắp xếp theo X tăng dần và loại bỏ trùng lặp
        on_axis.uniq { |pt| pt.x.round(2) }.sort_by { |pt| pt.x }
      else
        # Không có - trả về vertex gần trục X nhất
        [candidates.min_by { |pt| pt.y.abs + pt.z.abs }]
      end
    end

    # ============================================================
    #                   ROTATE PLACE TOOL  
    # ============================================================
    class RotatePlaceTool
      SNAP_RADIUS = 20

      def initialize(source, base_offset = ORIGIN, all_axis_vertices = nil)
        @inst = source if source.is_a?(Sketchup::ComponentInstance)
        @defn = @inst ? @inst.definition : source
        @all_axis_vertices = all_axis_vertices || [base_offset]
        @current_vertex_index = 0
        @base_offset = @all_axis_vertices[@current_vertex_index]
        @ip = Sketchup::InputPoint.new
        @rot = [0, 0, 0]
        @placed = false
        @op_open = false
        @current_pos = nil
        @snapped = false
        @last_pos = nil
        @last_rot = nil
        @finalizing = false
        @preview_transform = IDENTITY
        @preview_segments = []
        @log_id = "#{Time.now.to_i}-#{object_id}"
        @last_mouse_log_at = 0.0
        log_tool("init", source: MH::DWG.entity_log(source), defn: MH::DWG.definition_summary(@defn), base_offset: MH::DWG.point_log(@base_offset), axis_vertices: @all_axis_vertices.length)
      end

      def activate
        model = Sketchup.active_model
        log_tool("activate_start")
        unless @defn && @defn.valid?
          log_tool("activate_invalid_definition")
          UI.messagebox("Definition CAD không còn hợp lệ.")
          model.select_tool(nil)
          return
        end
        @inst.visible = false if @inst&.valid?
        @preview_segments = collect_preview_segments(@defn.entities)
        @preview_segments = bounds_preview_segments(@defn) if @preview_segments.empty?
        vertex_count = @all_axis_vertices.length
        log_tool("activate_ready", inst: MH::DWG.entity_log(@inst), preview_segments: @preview_segments.length, vertex_count: vertex_count)
        Sketchup.set_status_text("Click đặt | Tab: vertex tiếp (#{vertex_count} điểm) | Ctrl+Click: xoay Z | Shift: xoay Y | Alt: xoay X", SB_PROMPT)
      end

      def deactivate(view)
        log_tool("deactivate", placed: @placed, finalizing: @finalizing, op_open: @op_open)
        cleanup_unplaced_instance unless @placed || @finalizing
        view.invalidate
      end

      def onMouseMove(flags, x, y, view)
        @ip.pick(view, x, y)

        ray = view.pickray(x, y)
        ground = [ORIGIN, Z_AXIS]
        free_pos = Geom.intersect_line_plane(ray, ground)
        
        if @ip.valid? && @ip.vertex
          vertex_screen = view.screen_coords(@ip.position)
          dist = Math.sqrt((vertex_screen.x - x)**2 + (vertex_screen.y - y)**2)
          
          if dist < SNAP_RADIUS
            @current_pos = @ip.position
            @snapped = true
          else
            @current_pos = free_pos || @ip.position
            @snapped = false
          end
        else
          @current_pos = free_pos
          @snapped = false
        end

        update_transform
        maybe_log_mouse(flags, x, y)
        view.invalidate
      rescue => e
        log_tool("mouse_move_error", error: "#{e.class}: #{e.message}", backtrace: e.backtrace&.first(5))
        raise
      end

      def draw(view)
        return unless @current_pos

        draw_preview(view)
        
        if @snapped
          view.draw_points([@current_pos], 10, 2, "blue")
          @ip.draw(view)
        else
          view.draw_points([@current_pos], 8, 3, "green")
        end
      end

      def onLButtonDown(flags, x, y, view)
        log_tool("left_button_down", flags: flags, x: x, y: y, current_pos: MH::DWG.point_log(@current_pos), rot: @rot, finalizing: @finalizing)
        return if @finalizing || !@current_pos

        if (flags & COPY_MODIFIER_MASK) != 0 # Ctrl
          @rot[2] += 90 # Xoay trục Z
          @last_pos = nil  # Force update transform
          update_transform
          log_tool("rotate_z", rot: @rot, transform: MH::DWG.transform_log(@preview_transform))
          view.invalidate
          return
        end

        if (flags & CONSTRAIN_MODIFIER_MASK) != 0 # Shift
          @rot[1] += 90 # Xoay trục Y
          @last_pos = nil  # Force update transform
          update_transform
          log_tool("rotate_y", rot: @rot, transform: MH::DWG.transform_log(@preview_transform))
          view.invalidate
          return
        end

        if (flags & ALT_MODIFIER_MASK) != 0
          @rot[0] += 90
          @last_pos = nil  # Force update transform
          update_transform
          log_tool("rotate_x", rot: @rot, transform: MH::DWG.transform_log(@preview_transform))
          view.invalidate
          return
        end

        @finalizing = true
        log_tool("finalize_timer_scheduled", transform: MH::DWG.transform_log(@preview_transform), inst: MH::DWG.entity_log(@inst))
        Sketchup.set_status_text("Đang đặt CAD...", SB_PROMPT)

        # Đừng commit operation ngay trong callback chuột. Với DWG import lớn,
        # SketchUp 2025 rất dễ BugSplat khi đóng undo transaction trong lúc tool
        # event vẫn đang chạy, đặc biệt sau vài lần xoay/transform preview.
        UI.start_timer(0.0, false) { finalize_placement(view) }
      end

      def onKeyDown(key, repeat, flags, view)
        if key == 9 # Tab key
          return if @all_axis_vertices.length <= 1
          
          @current_vertex_index = (@current_vertex_index + 1) % @all_axis_vertices.length
          @base_offset = @all_axis_vertices[@current_vertex_index]
          
          @last_pos = nil  # Force update transform
          update_transform
          log_tool("tab_vertex", vertex_index: @current_vertex_index, base_offset: MH::DWG.point_log(@base_offset), transform: MH::DWG.transform_log(@preview_transform))
          view.invalidate
          
          Sketchup.set_status_text("Vertex #{@current_vertex_index + 1}/#{@all_axis_vertices.length}", SB_VCB_VALUE)
          return true
        end
        false
      end

      def onCancel(reason, view)
        log_tool("cancel", reason: reason, placed: @placed, finalizing: @finalizing)
        Sketchup.active_model.select_tool(nil)
      end

      private

      def log_tool(event, data = {})
        MH::DWG.log_event("tool.#{event}", data.merge(log_id: @log_id))
      end

      def maybe_log_mouse(flags, x, y)
        now = Time.now.to_f
        return if now - @last_mouse_log_at < 0.5
        @last_mouse_log_at = now
        log_tool("mouse_move", flags: flags, x: x, y: y, current_pos: MH::DWG.point_log(@current_pos), snapped: @snapped, rot: @rot, preview_segments: @preview_segments.length, transform: MH::DWG.transform_log(@preview_transform))
      end

      def collect_preview_segments(entities, transform = IDENTITY, segments = [], limit = 12_000)
        entities.each do |ent|
          break if segments.length >= limit

          case ent
          when Sketchup::Edge
            segments << [
              ent.start.position.transform(transform),
              ent.end.position.transform(transform)
            ]
          when Sketchup::ComponentInstance, Sketchup::Group
            next unless ent.valid?
            collect_preview_segments(ent.definition.entities, transform * ent.transformation, segments, limit)
          end
        end

        segments
      end

      def bounds_preview_segments(defn)
        bounds = definition_bounds(defn)
        return [] if bounds.empty?

        [
          [0, 1], [1, 3], [3, 2], [2, 0],
          [4, 5], [5, 7], [7, 6], [6, 4],
          [0, 4], [1, 5], [2, 6], [3, 7]
        ].map { |a, b| [bounds.corner(a), bounds.corner(b)] }
      end

      def definition_bounds(defn)
        bounds = Geom::BoundingBox.new

        if defn.respond_to?(:bounds)
          add_bounds(bounds, defn.bounds)
          return bounds unless bounds.empty?
        end

        defn.entities.each do |ent|
          next unless ent.respond_to?(:bounds)
          ent_bounds = ent.bounds
          next if ent_bounds.empty?
          add_bounds(bounds, ent_bounds)
        end

        bounds
      end

      def add_bounds(target, source)
        return if source.empty?
        8.times { |i| target.add(source.corner(i)) }
      end

      def draw_preview(view)
        return if @preview_segments.empty?

        points = []
        @preview_segments.each do |a, b|
          pa = a.transform(@preview_transform)
          pb = b.transform(@preview_transform)
          next unless drawable_point?(pa) && drawable_point?(pb)
          points << pa
          points << pb
        end

        return if points.empty?

        view.line_width = 1
        view.drawing_color = "black"
        view.draw(GL_LINES, points)
      end

      def drawable_point?(pt)
        [pt.x, pt.y, pt.z].all? do |value|
          number = value.to_f
          number.finite? && number.abs < 1.0e9
        end
      rescue
        false
      end

      def cleanup_unplaced_instance
        log_tool("cleanup_start", inst: MH::DWG.entity_log(@inst), op_open: @op_open)
        return unless @inst&.valid?

        model = Sketchup.active_model
        log_tool("cleanup_start_operation")
        model.start_operation("Hủy đặt CAD", true)
        @op_open = true
        log_tool("cleanup_before_erase", inst: MH::DWG.entity_log(@inst))
        @inst.erase!
        log_tool("cleanup_before_commit")
        model.commit_operation
        @op_open = false
        log_tool("cleanup_done")
      rescue
        log_tool("cleanup_error", op_open: @op_open)
        begin
          model.abort_operation if @op_open && model
        rescue
        end
        @op_open = false
      end

      def finalize_placement(view)
        model = Sketchup.active_model
        log_tool("finalize_start", inst: MH::DWG.entity_log(@inst), defn: MH::DWG.definition_summary(@defn), transform: MH::DWG.transform_log(@preview_transform))

        log_tool("finalize_before_start_operation")
        model.start_operation("Đặt CAD", true)
        @op_open = true
        log_tool("finalize_after_start_operation")
        if @inst&.valid?
          log_tool("finalize_before_transform_existing", inst: MH::DWG.entity_log(@inst))
          @inst.transformation = @preview_transform || IDENTITY
          log_tool("finalize_after_transform_existing", inst: MH::DWG.entity_log(@inst))
          log_tool("finalize_before_visible_true")
          @inst.visible = true
          log_tool("finalize_after_visible_true", inst: MH::DWG.entity_log(@inst))
        else
          log_tool("finalize_before_add_instance")
          @inst = model.active_entities.add_instance(@defn, @preview_transform || IDENTITY)
          log_tool("finalize_after_add_instance", inst: MH::DWG.entity_log(@inst))
        end
        log_tool("finalize_before_assign_tag")
        MH::DWG.assign_tag(@inst)
        log_tool("finalize_after_assign_tag", inst: MH::DWG.entity_log(@inst))
        log_tool("finalize_before_commit")
        model.commit_operation
        @op_open = false
        @placed = true
        log_tool("finalize_after_commit", inst: MH::DWG.entity_log(@inst))

        log_tool("finalize_before_select_tool_nil")
        model.select_tool(nil)
        log_tool("finalize_done")
        schedule_post_finalize_watchdog
      rescue => e
        log_tool("finalize_error", error: "#{e.class}: #{e.message}", backtrace: e.backtrace&.first(8), op_open: @op_open)
        begin
          if @op_open
            log_tool("finalize_before_abort")
            model.abort_operation
            @op_open = false
            log_tool("finalize_after_abort")
          end
        rescue
          # Ignore cleanup errors so the user still gets the real failure.
        end
        UI.messagebox("Lỗi đặt CAD: #{e.class}: #{e.message}")
        cleanup_unplaced_instance unless @placed
        model.select_tool(nil) if model
      ensure
        view.invalidate if view
      end

      def schedule_post_finalize_watchdog
        [0.2, 1.0, 3.0, 8.0].each do |delay|
          UI.start_timer(delay, false) do
            log_tool(
              "post_finalize_watchdog",
              delay: delay,
              active_tool: (Sketchup.active_model.tools.active_tool.class.name rescue nil),
              inst: MH::DWG.entity_log(@inst),
              model_entities: (Sketchup.active_model.active_entities.length rescue nil),
              selected_count: (Sketchup.active_model.selection.length rescue nil)
            )
          end
        end
      rescue => e
        log_tool("post_finalize_watchdog_error", error: "#{e.class}: #{e.message}", backtrace: e.backtrace&.first(5))
      end

      def update_transform
        return unless @current_pos

        pos_changed = @last_pos.nil? || @current_pos != @last_pos
        rot_changed = @last_rot.nil? || @rot != @last_rot

        return unless pos_changed || rot_changed

        rx = Geom::Transformation.rotation(ORIGIN, X_AXIS, @rot[0].degrees)
        ry = Geom::Transformation.rotation(ORIGIN, Y_AXIS, @rot[1].degrees)
        rz = Geom::Transformation.rotation(ORIGIN, Z_AXIS, @rot[2].degrees)
        rotation = rx * ry * rz

        rotated_offset = @base_offset.transform(rotation)
        pos = Geom::Point3d.new(
          @current_pos.x - rotated_offset.x,
          @current_pos.y - rotated_offset.y,
          @current_pos.z - rotated_offset.z
        )

        @preview_transform = Geom::Transformation.translation(pos) * rotation
        @last_pos = @current_pos.clone
        @last_rot = @rot.clone
      end
    end

    # ============================================================
    #                   IMPORT + PLACE
    # ============================================================
    def self.paste_from_clipboard
      model = Sketchup.active_model
      view = model.active_view
      log_event("paste.start", active_path: (model.path rescue nil), entities_before: (model.active_entities.length rescue nil))

      dwg = find_clipboard_dwg
      unless dwg
        log_event("paste.no_clipboard_dwg")
        return UI.messagebox("Không tìm thấy file DWG!")
      end

      log_event("paste.dwg_found", path: dwg, size: (File.size(dwg) rescue nil), mtime: (File.mtime(dwg).to_s rescue nil))

      # Deactivate tool đang chạy (nếu có) -> abort preview op cũ, tránh
      # import chạy trong khi 1 operation đang mở (nested op -> BugSplat).
      log_event("paste.before_select_tool_nil")
      model.select_tool(nil)
      log_event("paste.after_select_tool_nil")

      cam = view.camera
      eye, target, up = cam.eye.clone, cam.target.clone, cam.up.clone
      is_perspective = cam.perspective?
      fov_or_height = is_perspective ? cam.fov : cam.height

      before = model.active_entities.to_a
      log_event("paste.before_import", active_entities: before.length)

      # QUAN TRỌNG: KHÔNG bọc model.import trong start_operation.
      # import tự quản transaction riêng — lồng vào operation khác = nested
      # operation -> hỏng undo stack -> BugSplat (sập trễ vài giây sau).
      unless model.import(dwg, {})
        log_event("paste.import_failed")
        return UI.messagebox("Import DWG lỗi!")
      end
      log_event("paste.after_import", active_entities: (model.active_entities.length rescue nil))

      new_ents = model.active_entities.to_a - before
      log_event("paste.new_entities", summary: entities_summary(new_ents), sample: new_ents.first(10).map { |ent| entity_log(ent) })

      if new_ents.empty?
        log_event("paste.no_new_entities")
        return UI.messagebox("Không có gì import!")
      end

      # Gom + tạo definition trong 1 operation RIÊNG (sau khi import xong).
      defn = nil
      placement_inst = nil
      base_point = nil
      all_axis_vertices = nil
      log_event("paste.before_process_operation")
      model.start_operation("Xử lý CAD", true)
      log_event("paste.after_process_operation_start")
      begin
        if new_ents.length == 1 && (new_ents[0].is_a?(Sketchup::ComponentInstance) || new_ents[0].is_a?(Sketchup::Group))
          first_ent = new_ents[0]
          log_event("paste.single_import_entity", entity: entity_log(first_ent))
          inst = first_ent.is_a?(Sketchup::Group) ? first_ent.to_component : first_ent
        else
          log_event("paste.before_group_new_entities")
          group = model.active_entities.add_group(new_ents)
          log_event("paste.after_group_new_entities", group: entity_log(group))
          inst = group.to_component
        end
        log_event("paste.after_to_component", inst: entity_log(inst))

        defn = inst.definition
        base_point = find_vertex_on_x_axis(defn.entities)
        all_axis_vertices = find_all_vertices_on_x_axis(defn.entities)
        log_event("paste.definition_ready", defn: definition_summary(defn), base_point: point_log(base_point), axis_vertices: all_axis_vertices.length)

        log_event("paste.before_hide_import_instance", inst: entity_log(inst))
        inst.visible = false
        placement_inst = inst
        log_event("paste.before_process_commit")
        model.commit_operation
        log_event("paste.after_process_commit", placement_inst: entity_log(placement_inst))
      rescue => e
        log_event("paste.process_error", error: "#{e.class}: #{e.message}", backtrace: e.backtrace&.first(8))
        model.abort_operation
        return UI.messagebox("Lỗi xử lý CAD: #{e.message}")
      end

      log_event("paste.before_camera_restore")
      cam.set(eye, target, up)
      if is_perspective
        cam.perspective = true
        cam.fov = fov_or_height
      else
        cam.perspective = false
        cam.height = fov_or_height
      end
      log_event("paste.after_camera_restore")

      log_event("paste.before_select_rotate_tool", placement_inst: entity_log(placement_inst), defn: definition_summary(defn))
      model.select_tool(RotatePlaceTool.new(placement_inst || defn, base_point, all_axis_vertices))
      log_event("paste.after_select_rotate_tool")
    end

    unless file_loaded?(__FILE__)
      UI.menu("Plugins").add_item("Paste CAD From Clipboard") { paste_from_clipboard }
      file_loaded(__FILE__)
    end

  end
end

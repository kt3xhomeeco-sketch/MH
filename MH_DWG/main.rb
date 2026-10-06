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
      # AutoCAD uses A$C*.dwg. VinaCAD creates a regular .dwg (for example
      # 8f0.dwg) and a .tmp file with the same basename. Scan both sources,
      # then use the one copied most recently.
      temp = ENV.fetch("TEMP").tr("\\", "/")
      autocad_files = Dir.glob(File.join(temp, "A$C*.dwg"), File::FNM_CASEFOLD)
      vinacad_files = Dir.glob(File.join(temp, "*.dwg"), File::FNM_CASEFOLD)
                         .select { |file| vinacad_clipboard_temp_dwg?(file) }
      candidates = (autocad_files + vinacad_files).uniq
      newest = candidates.max_by { |file| File.mtime(file) }

      log_event(
        "clipboard.dwg_path_selected",
        autocad_files: autocad_files,
        vinacad_files: vinacad_files,
        selected_path: newest,
        selected_mtime: (File.mtime(newest).to_s if newest)
      )
      newest
    rescue => e
      log_event("clipboard.dwg_path_error", error: "#{e.class}: #{e.message}")
      nil
    end

    def self.vinacad_clipboard_temp_dwg?(file)
      return false if File.basename(file).match?(/\AA\$C.+\.dwg\z/i)
      basename = File.basename(file, ".dwg")
      File.file?(File.join(File.dirname(file), "#{basename}.tmp"))
    end

    def self.assign_tag(inst, model = inst.model)
      return unless inst.is_a?(Sketchup::ComponentInstance)
      tag = model.layers[TAG_NAME] || model.layers.add(TAG_NAME)
      inst.layer = tag
    end

    # Hot reload must not leave a previous session's observer/timer alive.
    @native_tagger.cancel! if @native_tagger
    @native_tagger = nil

    class NativePlacementTagger < Sketchup::ToolsObserver
      def initialize(model, definition)
        @model, @definition = model, definition
        @entities = model.active_entities
        @active_path = model.active_path&.dup
        @existing_instances = definition.instances.to_a.dup
        @tools = model.tools
        @active = true
        @armed = false
        @timer = nil
        @attached = @tools.add_observer(self)
        raise "Không theo dõi được công cụ đặt CAD." unless @attached
      end

      def arm!
        @armed = true
        DWG.log_event("paste.native_tag_armed", tool_id: @tools.active_tool_id)
      end

      def onActiveToolChanged(_tools, _name, _tool_id)
        return unless @active && @armed
        return if @timer
        # Notifications are read-only. Wait for the native callback to return.
        @timer = UI.start_timer(0.0, false) do
          @timer = nil
          finish_if_idle
        end
      rescue => e
        cancel!
        DWG.log_event("paste.native_tag_error", error: "#{e.class}: #{e.message}")
      end

      def cancel!
        @active = false
        UI.stop_timer(@timer) if @timer
        @timer = nil
        @tools.remove_observer(self) if @attached
        @attached = false
      rescue => e
        DWG.log_event("paste.native_tag_cleanup_error", error: "#{e.class}: #{e.message}")
      end

      def finish_if_idle
        return unless @active
        unless @model.valid? && Sketchup.active_model == @model && @definition.valid? &&
               @model.active_path == @active_path && @model.active_entities == @entities
          cancel!
          return
        end
        # Do not start an operation during placement, Orbit, Move or another
        # editing tool. If the user immediately presses M, wait until Select.
        return unless @tools.active_tool.nil? && [0, 21022].include?(@tools.active_tool_id)

        instances = @definition.instances.to_a.reject { |instance| @existing_instances.include?(instance) }
        instances.select! { |instance| instance.valid? && instance.parent == @entities.parent }
        cancel! # One-shot; detach before making any model changes.
        if instances.empty?
          DWG.log_event("paste.native_tag_cancelled", reason: "no_placed_instance")
          return
        end

        operation_open = false
        # Keep this separate from native placement's Undo. A delayed transparent
        # operation could otherwise merge into an unrelated user action.
        raise "Không mở được operation gán Tag CAD." unless @model.start_operation("Tag CAD MH_DWG", true)
        operation_open = true
        instances.each { |instance| DWG.assign_tag(instance, @model) }
        @model.commit_operation
        operation_open = false
        DWG.log_event("paste.native_tag_assigned", tag: TAG_NAME, instances: instances.map { |instance| DWG.entity_log(instance) })
      rescue => e
        @model.abort_operation if operation_open
        cancel!
        DWG.log_event("paste.native_tag_error", error: "#{e.class}: #{e.message}")
        UI.messagebox("CAD đã đặt nhưng chưa gán được Tag MH_DWG: #{e.message}")
      end
    end

    def self.import_options
      # Request recentering, but verify/fix the actual definition coordinates:
      # our SU 2025 DefinitionList#import results retained the CAD origin.
      { preserve_origin: false }
    end

    def self.normalize_definition_origin(defn, model)
      # Only an unused, newly imported root may be edited. Moving a child
      # definition would also alter other CAD blocks which share that child.
      raise "Không chuẩn hóa CAD đã có instance trong model." unless defn.instances.empty?
      bounds = defn.bounds
      raise "CAD không có bounds hợp lệ." if bounds.empty?
      offset = bounds.min
      coordinates = [offset.x.to_f, offset.y.to_f, offset.z.to_f]
      raise "Tọa độ CAD không hợp lệ." unless coordinates.all?(&:finite?)
      if coordinates.all? { |value| value.abs <= 1.0e-6 }
        log_event("paste.origin_already_normalized", bounds_min: point_log(offset))
        return
      end

      operation_open = false
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      log_event("paste.before_normalize_origin", defn: definition_summary(defn))
      raise "Không mở được operation chuẩn hóa CAD." unless model.start_operation("Chuẩn hóa gốc CAD", true)
      operation_open = true
      shift = Geom::Transformation.translation(Geom::Point3d.new(-offset.x, -offset.y, -offset.z))
      # Transform all root geometry together; nested block definitions are not
      # edited. The unused definition is outside the active drawing context.
      result = defn.entities.transform_entities(shift, defn.entities.to_a)
      raise "Không dịch được hình học CAD về gốc." unless result
      defn.invalidate_bounds
      normalized_bounds = defn.bounds
      raise "Bounds CAD rỗng sau chuẩn hóa." if normalized_bounds.empty?
      minimum = normalized_bounds.min
      unless [minimum.x.to_f, minimum.y.to_f, minimum.z.to_f].all? { |value| value.finite? && value.abs <= 1.0e-6 }
        raise "Gốc CAD chưa chuẩn hóa; dừng đặt để tránh dùng tọa độ cũ."
      end
      model.commit_operation
      operation_open = false
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
      log_event("paste.after_normalize_origin", original_min: point_log(offset), defn: definition_summary(defn), duration_ms: duration_ms)
    rescue
      model.abort_operation if operation_open
      raise
    end

    def self.placement_anchor_points(defn)
      # Definition bounds include nested CAD blocks in definition coordinates.
      # Start at the whole drawing's min X/Y/Z corner, not near CAD's X axis.
      bounds = defn.bounds
      base_point = bounds.empty? ? ORIGIN : bounds.min
      alternatives = find_all_vertices_on_x_axis(defn.entities)
      [base_point] + alternatives.reject { |point| point == base_point }
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
        @model = Sketchup.active_model
        @entities = @model.active_entities
        @active_path = Array(@model.active_path).dup
        @context_inverse = @model.edit_transform.inverse
        @defn = source
        @inst = nil
        @active = false
        @handoff = false
        @placement_pending = false
        @placement_timer = nil
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
        model = @model
        log_tool("activate_start")
        unless @defn && @defn.valid?
          log_tool("activate_invalid_definition")
          UI.messagebox("Definition CAD không còn hợp lệ.")
          model.select_tool(nil)
          return
        end
        @active = true
        @preview_segments = collect_preview_segments(@defn.entities)
        @preview_segments = bounds_preview_segments(@defn) if @preview_segments.empty?
        vertex_count = @all_axis_vertices.length
        log_tool("activate_ready", inst: MH::DWG.entity_log(@inst), preview_segments: @preview_segments.length, vertex_count: vertex_count)
        Sketchup.set_status_text("Click đặt | Tab: vertex tiếp (#{vertex_count} điểm) | Ctrl+Click: xoay Z | Shift: xoay Y | Alt: xoay X", SB_PROMPT)
      end

      def deactivate(view)
        log_tool("deactivate", placed: @placed, finalizing: @finalizing, op_open: @op_open)
        @active = false
        cancel_pending! unless @handoff
        @preview_segments = []
        view.invalidate
      end

      def cancel_pending!
        UI.stop_timer(@placement_timer) if @placement_timer
        @placement_timer = nil
        @placement_pending = false
        @finalizing = false unless @placed
      end

      def onMouseMove(flags, x, y, view)
        return unless @active && !@finalizing && context_valid?
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
        return unless @active && @current_pos && context_valid?

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
        return if @finalizing || !@active || !@current_pos || !context_valid?

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
        @placement_pending = true
        @final_transform = @context_inverse * @preview_transform
        log_tool("finalize_timer_scheduled", transform: MH::DWG.transform_log(@preview_transform), inst: MH::DWG.entity_log(@inst))
        Sketchup.set_status_text("Đang đặt CAD...", SB_PROMPT)

        # Leave the Tool first, then create geometry in a separate UI callback.
        # During preview there is no imported instance to hide or transform.
        @placement_timer = UI.start_timer(0.0, false) do
          @placement_timer = nil
          if @placement_pending && context_valid?
            begin
              @handoff = true
              @model.select_tool(nil)
            ensure
              @handoff = false
            end
            @handoff_tool_id = @model.tools.active_tool_id
            if @placement_pending
              @placement_timer = UI.start_timer(0.05, false) do
                @placement_timer = nil
                finalize_placement(view)
              end
            end
          else
            cancel_pending!
            log_tool("finalize_cancelled_context_changed")
          end
        end
      end

      def onKeyDown(key, repeat, flags, view)
        return false unless @active && !@finalizing && context_valid?
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
        cancel_pending!
        @model.select_tool(nil) if Sketchup.active_model == @model
      end

      private

      def context_valid?
        Sketchup.active_model == @model && @model.valid? &&
          @model.active_entities == @entities &&
          Array(@model.active_path) == @active_path && @defn&.valid?
      rescue
        false
      end

      def log_tool(event, data = {})
        MH::DWG.log_event("tool.#{event}", data.merge(log_id: @log_id))
      end

      def maybe_log_mouse(flags, x, y)
        now = Time.now.to_f
        return if now - @last_mouse_log_at < 0.5
        @last_mouse_log_at = now
        log_tool("mouse_move", flags: flags, x: x, y: y, current_pos: MH::DWG.point_log(@current_pos), snapped: @snapped, rot: @rot, preview_segments: @preview_segments.length, transform: MH::DWG.transform_log(@preview_transform))
      end

      def collect_preview_segments(entities, transform = IDENTITY, segments = [], limit = 12_000, ancestors = [])
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
            definition = ent.definition
            next if ancestors.include?(definition) || ancestors.length >= 64
            collect_preview_segments(definition.entities, transform * ent.transformation, segments, limit, ancestors + [definition])
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

      def finalize_placement(view)
        unless @placement_pending && context_valid? && @model.tools.active_tool_id == @handoff_tool_id
          cancel_pending!
          log_tool("finalize_cancelled_context_changed")
          return
        end
        @placement_pending = false
        model = @model
        log_tool("finalize_start", inst: MH::DWG.entity_log(@inst), defn: MH::DWG.definition_summary(@defn), transform: MH::DWG.transform_log(@preview_transform))

        log_tool("finalize_before_start_operation")
        model.start_operation("Đặt CAD", true)
        @op_open = true
        log_tool("finalize_after_start_operation")
        log_tool("finalize_before_add_instance")
        @inst = @entities.add_instance(@defn, @final_transform)
        log_tool("finalize_after_add_instance", inst: MH::DWG.entity_log(@inst))
        log_tool("finalize_before_assign_tag")
        MH::DWG.assign_tag(@inst, model)
        log_tool("finalize_after_assign_tag", inst: MH::DWG.entity_log(@inst))
        log_tool("finalize_before_commit")
        model.commit_operation
        @op_open = false
        @placed = true
        log_tool("finalize_after_commit", inst: MH::DWG.entity_log(@inst))

        log_tool("finalize_done")
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
      ensure
        view.invalidate if view && Sketchup.active_model == @model && @model.valid?
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
    def self.paste_from_clipboard(placement_mode = :native)
      return if @importing
      raise ArgumentError, "Unknown CAD placement mode" unless [:native, :custom].include?(placement_mode)
      import_owned = true
      @importing = true
      model = Sketchup.active_model
      pipeline = placement_mode == :native ? "definition_native_placement" : "definition_preview_then_place"
      log_event("paste.start", pipeline: pipeline, active_path: (model.path rescue nil), entities_before: (model.active_entities.length rescue nil))

      dwg = find_clipboard_dwg
      unless dwg
        log_event("paste.no_clipboard_dwg")
        return UI.messagebox("Không tìm thấy file DWG!")
      end

      log_event("paste.dwg_found", path: dwg, size: (File.size(dwg) rescue nil), mtime: (File.mtime(dwg).to_s rescue nil))

      # Cancel even a placement timer whose Tool has already handed off.
      @placement_tool.cancel_pending! if @placement_tool
      @placement_tool = nil
      @native_tagger.cancel! if @native_tagger
      @native_tagger = nil
      log_event("paste.before_select_tool_nil")
      model.select_tool(nil)
      log_event("paste.after_select_tool_nil")

      # Import a definition only. Do not create a visible native-import instance,
      # hide it, or transform it while SketchUp is still updating import state.
      # The importer manages its own transaction; no operation encloses it.
      options = import_options
      log_event("paste.before_definition_import", options: options)
      import_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      defn = model.definitions.import(dwg, options)
      import_duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - import_started_at) * 1000).round(2)
      unless defn && defn.valid? && defn.entities.length > 0
        log_event("paste.definition_import_failed")
        return UI.messagebox("Import DWG lỗi!")
      end
      log_event("paste.after_definition_import", defn: definition_summary(defn), active_entities: model.active_entities.length, duration_ms: import_duration_ms)
      return unless Sketchup.active_model == model && model.valid?

      normalize_definition_origin(defn, model)
      return unless Sketchup.active_model == model && model.valid? && defn.valid?

      if placement_mode == :native
        # Normalization makes the whole drawing's min XYZ the definition origin.
        # SketchUp owns the mouse-follow preview, click, cancel and transaction.
        # A one-shot observer only queues Tag assignment after native placement
        # exits to Select. It never creates, hides or transforms an instance.
        log_event("paste.before_native_placement", defn: definition_summary(defn), anchor_mode: "bounds_min", repeat: false)
        @native_tagger = NativePlacementTagger.new(model, defn)
        raise "Không bật được công cụ đặt CAD native." unless model.place_component(defn, false)
        @native_tagger.arm!
        log_event("paste.native_placement_started")
        return
      end

      all_axis_vertices = placement_anchor_points(defn)
      base_point = all_axis_vertices.first
      log_event("paste.definition_ready", defn: definition_summary(defn), base_point: point_log(base_point), anchor_mode: "bounds_min", axis_vertices: all_axis_vertices.length)
      @placement_tool = RotatePlaceTool.new(defn, base_point, all_axis_vertices)
      log_event("paste.before_select_rotate_tool", defn: definition_summary(defn))
      model.select_tool(@placement_tool)
      log_event("paste.after_select_rotate_tool")
    rescue => e
      @native_tagger.cancel! if import_owned && @native_tagger
      log_event("paste.error", error: "#{e.class}: #{e.message}", backtrace: e.backtrace&.first(8))
      UI.messagebox("Lỗi import CAD: #{e.class}: #{e.message}")
    ensure
      @importing = false if import_owned
    end

    unless file_loaded?(__FILE__)
      UI.menu("Plugins").add_item("Paste CAD From Clipboard") { paste_from_clipboard }
      file_loaded(__FILE__)
    end

  end
end

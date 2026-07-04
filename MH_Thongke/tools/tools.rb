# encoding: utf-8
# MH_Thongke — SketchUp Tools
# PlaceOnFaceTool + HighlightTool
# Tách từ main.rb: dòng 249–423

module MH_Thongke

  class PlaceOnFaceTool
    def initialize(defn, dict, key, val, tag_name, label)
      @defn = defn
      @dict = dict
      @key = key
      @val = val
      @tag_name = tag_name
      @label = label
      @model = Sketchup.active_model
      @rot = { x: 0, y: 0, z: 0 }
      @preview_inst = nil
    end

    def activate
      ensure_preview
      Sketchup.status_text = "Gắn #{@val} | ↑:Xoay Z  ←:Xoay Y  →:Xoay X  (90°/lần) | Click để đặt | Esc:Hoàn tất"
    end

    def deactivate(view)
      @preview_inst.erase! if @preview_inst && !@preview_inst.deleted?
      @model.commit_operation
    end

    def ensure_preview
      if @preview_inst.nil? || @preview_inst.deleted?
        @model.start_operation("Gắn #{@val}", true)
        @preview_inst = @model.active_entities.add_instance(@defn, Geom::Transformation.new)
        @preview_inst.hidden = true
      end
    end

    def get_world_info
      return nil unless @ip && @ip.valid?
      pt_world = @ip.position
      path = @ip.instance_path
      tr_obj_to_world = (path && path.valid?) ? path.transformation : Geom::Transformation.new
      if @ip.face
        normal_world = @ip.face.normal.transform(tr_obj_to_world).normalize
      else
        normal_world = Geom::Vector3d.new(0, 0, 1)
      end
      [pt_world, normal_world, tr_obj_to_world]
    end

    def onMouseMove(flags, x, y, view)
      @ip ||= Sketchup::InputPoint.new
      @ip.pick(view, x, y)
      ensure_preview
      info = get_world_info
      if info
        pt_w, n_w, _ = info
        tr_world = compute_world_transform(pt_w, n_w)
        if @preview_inst && !@preview_inst.deleted?
          @preview_inst.transformation = @model.edit_transform.inverse * tr_world
          @preview_inst.hidden = false
        end
      else
        @preview_inst.hidden = true if @preview_inst && !@preview_inst.deleted?
      end
      view.tooltip = @ip.tooltip if @ip.valid?
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      ensure_preview
      info = get_world_info
      return unless info
      pt_w, n_w, tr_obj_to_world = info
      target_ents = @model.active_entities
      path = @ip.instance_path
      if path && path.valid? && !path.empty?
        leaf = path.to_a.last
        if leaf.is_a?(Sketchup::ComponentInstance) || leaf.is_a?(Sketchup::Group)
          target_ents = leaf.definition.entities
        elsif leaf.respond_to?(:parent)
          p = leaf.parent
          target_ents = p.is_a?(Sketchup::Model) ? @model.entities : p.entities
        end
      end
      tr_world = compute_world_transform(pt_w, n_w)
      world_to_local = tr_obj_to_world.inverse
      tr_local = world_to_local * tr_world
      MH_Thongke.detach_observers
      tag = @model.layers.add(@tag_name)
      inst = target_ents.add_instance(@defn, tr_local)
      inst.name = @label if @label && !@label.to_s.strip.empty?
      inst.set_attribute(@dict, @key, @val)
      inst.layer = tag
      MH_Thongke.attach_observers
      MH_Thongke.debounce_refresh
    end

    def onKeyDown(key, repeat, flags, view)
      step = Math::PI / 2
      case key
      when 38 then @rot[:z] += step
      when 37 then @rot[:y] += step
      when 39 then @rot[:x] += step
      end
      info = get_world_info
      if info && @preview_inst && !@preview_inst.deleted?
        pt_w, n_w, _ = info
        tr_world = compute_world_transform(pt_w, n_w)
        @preview_inst.transformation = @model.edit_transform.inverse * tr_world
      end
      view.invalidate
    end

    def onCancel(reason, view)
      @model.select_tool(nil)
    end

    private

    def compute_world_transform(pt, normal)
      z_axis = normal
      x_axis = z_axis.axes[0]
      y_axis = z_axis.axes[1]
      base_tr = Geom::Transformation.axes(pt, x_axis, y_axis, z_axis)
      rot_tr = Geom::Transformation.rotation(pt, x_axis, @rot[:x]) *
               Geom::Transformation.rotation(pt, y_axis, @rot[:y]) *
               Geom::Transformation.rotation(pt, z_axis, @rot[:z])
      rot_tr * base_tr
    end
  end

  # =======================================
  # HIGHLIGHT TOOL
  # =======================================
  class HighlightTool
    FILL_COLOR = Sketchup::Color.new(0, 200, 0, 50)
    EDGE_COLOR = Sketchup::Color.new(0, 255, 0, 220)

    def initialize(stat_entries)
      @boxes = []
      stat_entries.each do |entry|
        ent = entry[0]
        wt  = entry[2]
        next if ent.nil? || (ent.respond_to?(:deleted?) && ent.deleted?)
        next unless wt
        bb = ent.bounds
        pts = (0..7).map { |i| bb.corner(i).transform(wt) }
        @boxes << pts
      end
    end

    def activate; Sketchup.active_model.active_view.invalidate; end
    def deactivate(view); view.invalidate; end
    def resume(view); view.invalidate; end
    def suspend(view); view.invalidate; end

    def draw(view)
      @boxes.each do |pts|
        sc = pts.map { |p| view.screen_coords(p) }
        view.drawing_color = FILL_COLOR
        quads = [
          [sc[0], sc[2], sc[3], sc[1]], [sc[4], sc[5], sc[7], sc[6]],
          [sc[0], sc[1], sc[5], sc[4]], [sc[2], sc[3], sc[7], sc[6]],
          [sc[0], sc[4], sc[6], sc[2]], [sc[1], sc[5], sc[7], sc[3]],
        ]
        quads.each { |q| view.draw2d(GL_QUADS, q) }
        view.line_width = 3
        view.drawing_color = EDGE_COLOR
        edges = [
          sc[0], sc[1], sc[1], sc[3], sc[3], sc[2], sc[2], sc[0],
          sc[4], sc[5], sc[5], sc[7], sc[7], sc[6], sc[6], sc[4],
          sc[0], sc[4], sc[1], sc[5], sc[2], sc[6], sc[3], sc[7],
        ]
        view.draw2d(GL_LINES, edges)
      end
    end

    def onLButtonDown(flags, x, y, view); Sketchup.active_model.select_tool(nil); end
    def onCancel(reason, view); Sketchup.active_model.select_tool(nil); end
  end

end

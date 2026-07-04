# encoding: utf-8
# MH_Thongke - Info HUD viewport overlay for current SketchUp selection.

module MH_Thongke
  INFO_HUD_WIDTH = 360 unless const_defined?(:INFO_HUD_WIDTH)
  INFO_HUD_ROW_HEIGHT = 32 unless const_defined?(:INFO_HUD_ROW_HEIGHT)
  INFO_HUD_PADDING = 10 unless const_defined?(:INFO_HUD_PADDING)
  INFO_HUD_TITLE_HEIGHT = 24 unless const_defined?(:INFO_HUD_TITLE_HEIGHT)

  remove_const(:INFO_HUD_COLOR_PANEL) if const_defined?(:INFO_HUD_COLOR_PANEL)
  INFO_HUD_COLOR_PANEL = Sketchup::Color.new(188, 188, 194, 230)
  remove_const(:INFO_HUD_COLOR_HEADER) if const_defined?(:INFO_HUD_COLOR_HEADER)
  INFO_HUD_COLOR_HEADER = Sketchup::Color.new(38, 48, 58, 235)
  remove_const(:INFO_HUD_COLOR_ROW) if const_defined?(:INFO_HUD_COLOR_ROW)
  INFO_HUD_COLOR_ROW = Sketchup::Color.new(32, 36, 42, 222)
  remove_const(:INFO_HUD_COLOR_TITLE) if const_defined?(:INFO_HUD_COLOR_TITLE)
  INFO_HUD_COLOR_TITLE = Sketchup::Color.new(255, 255, 255)
  remove_const(:INFO_HUD_COLOR_LABEL) if const_defined?(:INFO_HUD_COLOR_LABEL)
  INFO_HUD_COLOR_LABEL = Sketchup::Color.new(176, 184, 195)
  remove_const(:INFO_HUD_COLOR_VALUE) if const_defined?(:INFO_HUD_COLOR_VALUE)
  INFO_HUD_COLOR_VALUE = Sketchup::Color.new(245, 158, 11)
  remove_const(:INFO_HUD_COLOR_SUB) if const_defined?(:INFO_HUD_COLOR_SUB)
  INFO_HUD_COLOR_SUB = Sketchup::Color.new(165, 174, 186)

  if defined?(Sketchup::Overlay)
    class InfoHudViewportOverlay < Sketchup::Overlay
      OVERLAY_ID = "mh.thongke.info_hud"
      OVERLAY_NAME = "info-HUD"

      def initialize
        super(OVERLAY_ID, OVERLAY_NAME)
      end

      def start
        Sketchup.active_model.active_view.invalidate rescue nil
      end

      def stop
        Sketchup.active_model.active_view.invalidate rescue nil
      end

      def draw(view)
        draw_panel(view, MH_Thongke.info_hud_overlay_data)
      rescue => e
        puts "InfoHudViewportOverlay draw error: #{e.message}"
      end

      private

      def draw_panel(view, data)
        rows = Array(data[:rows]).map { |row| row.is_a?(Hash) ? row : {} }
        panel_w = MH_Thongke::INFO_HUD_WIDTH
        pad = MH_Thongke::INFO_HUD_PADDING
        title_h = MH_Thongke::INFO_HUD_TITLE_HEIGHT
        row_h = MH_Thongke::INFO_HUD_ROW_HEIGHT
        panel_h = pad + title_h + [rows.size, 1].max * row_h + pad
        panel_h = [panel_h, view.vpheight.to_i].min
        x0, y0 = MH::OverlayEngine.panel_origin(view, panel_w, panel_h, anchor: :top_right)

        draw_rect(view, x0, y0, panel_w, panel_h, MH_Thongke::INFO_HUD_COLOR_PANEL)
        draw_rect(view, x0 + pad, y0 + pad, panel_w - pad * 2, title_h, MH_Thongke::INFO_HUD_COLOR_HEADER)

        MH::OverlayEngine.text(view, x0 + pad + 8, y0 + pad + 6, "INFO-HUD", color: MH_Thongke::INFO_HUD_COLOR_TITLE, size: 9, bold: true)

        y = y0 + pad + title_h
        if rows.empty?
          draw_rect(view, x0 + pad, y, panel_w - pad * 2, row_h, MH_Thongke::INFO_HUD_COLOR_ROW)
          MH::OverlayEngine.text(view, x0 + pad + 8, y + 10, data[:message].to_s.empty? ? "Chua chon target." : data[:message].to_s, color: MH_Thongke::INFO_HUD_COLOR_SUB, size: 9)
          return
        end

        rows.first(6).each do |row|
          draw_rect(view, x0 + pad, y, panel_w - pad * 2, row_h, MH_Thongke::INFO_HUD_COLOR_ROW)
          MH::OverlayEngine.text(view, x0 + pad + 8, y + 6, truncate_text(row[:label], 12).upcase, color: MH_Thongke::INFO_HUD_COLOR_LABEL, size: 7, bold: true)
          MH::OverlayEngine.text(view, x0 + pad + 94, y + 4, truncate_text(row[:value], 40), color: MH_Thongke::INFO_HUD_COLOR_VALUE, size: 8, bold: true)
          sub = row[:sub].to_s.strip
          unless sub.empty?
            MH::OverlayEngine.text(view, x0 + pad + 94, y + 18, truncate_text(sub, 46), color: MH_Thongke::INFO_HUD_COLOR_SUB, size: 6)
          end
          y += row_h
        end
      end

      def draw_rect(view, x, y, w, h, color)
        MH::OverlayEngine.rect(view, x, y, w, h, color, (@rect_points ||= [[0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0]]))
      end

      def truncate_text(value, max_chars)
        text = MH_Thongke.fix_vietnamese_mojibake(value).to_s
        text.length > max_chars ? "#{text[0, max_chars - 3]}..." : text
      end
    end

    class InfoHudEditTool
      EDITABLE_ROWS = {
        "Instance" => :instance,
        "Material" => :material,
        "Layer" => :layer
      }.freeze

      def activate
        Sketchup.status_text = "info-HUD: click Instance/Material/Layer de sua, click model de chon target, Esc de thoat tool."
        Sketchup.active_model.active_view.invalidate rescue nil
      end

      def deactivate(view)
        MH_Thongke.info_hud_clear_active_tool(self) if MH_Thongke.respond_to?(:info_hud_clear_active_tool)
        view.invalidate if view
        MH_Thongke.info_hud_restore_tool_soon if MH_Thongke.respond_to?(:info_hud_restore_tool_soon)
      end

      def resume(view)
        view.invalidate if view
      end

      def onLButtonDown(_flags, x, y, view)
        label = MH_Thongke.info_hud_row_at(view, x, y)
        if label
          action = EDITABLE_ROWS[label]
          action ? MH_Thongke.info_hud_edit(action) : Sketchup.beep
          view.invalidate
          return
        end

        pick_entity(x, y, view)
      rescue => e
        puts "InfoHudEditTool click error: #{e.class}: #{e.message}"
      end

      def onKeyDown(key, _repeat, _flags, view)
        if defined?(VK_ESCAPE) && key == VK_ESCAPE
          Sketchup.status_text = "info-HUD van bat. Tat/bat bang nut hoac menu trong extension."
          MH_Thongke.info_hud_restore_tool_soon if MH_Thongke.respond_to?(:info_hud_restore_tool_soon)
          view.invalidate if view
        end
      end

      def onCancel(_reason, view)
        Sketchup.status_text = "info-HUD van bat. Tat/bat bang nut hoac menu trong extension."
        MH_Thongke.info_hud_restore_tool_soon if MH_Thongke.respond_to?(:info_hud_restore_tool_soon)
        view.invalidate if view
      end

      def draw(_view); end

      private

      def pick_entity(x, y, view)
        ph = view.pick_helper
        ph.do_pick(x, y)
        ent = ph.best_picked
        return unless ent && ent.valid?

        model = Sketchup.active_model
        model.selection.clear
        model.selection.add(ent)
        MH_Thongke.refresh_info_hud(true) if MH_Thongke.respond_to?(:refresh_info_hud)
      rescue => e
        puts "InfoHudEditTool pick error: #{e.class}: #{e.message}"
      end
    end
  end

  def self.info_hud_visible?
    @info_hud_overlay && @info_hud_overlay.respond_to?(:enabled?) && @info_hud_overlay.enabled?
  rescue
    false
  end

  def self.cleanup_legacy_info_hud_dialog!
    if instance_variable_defined?(:@info_hud_dlg)
      dlg = @info_hud_dlg
      dlg.close if dlg && dlg.respond_to?(:close)
      remove_instance_variable(:@info_hud_dlg) if instance_variable_defined?(:@info_hud_dlg)
    end
    remove_instance_variable(:@info_hud_last_html) if instance_variable_defined?(:@info_hud_last_html)
  rescue
    nil
  end

  def self.register_info_hud_overlay
    return nil unless defined?(Sketchup::Overlay)

    model = Sketchup.active_model
    if @info_hud_overlay.nil? || @info_hud_overlay_model != model
      @info_hud_overlay = InfoHudViewportOverlay.new
      model.overlays.add(@info_hud_overlay)
      @info_hud_overlay_model = model
    end
    @info_hud_overlay
  rescue => e
    puts "register_info_hud_overlay error: #{e.message}"
    nil
  end

  def self.show_info_hud(force_enable = true)
    cleanup_legacy_info_hud_dialog!
    @model = Sketchup.active_model
    attach_observers if respond_to?(:attach_observers)

    overlay = register_info_hud_overlay
    unless overlay
      UI.messagebox("SketchUp nay khong ho tro Viewport Overlay.") rescue nil
      return false
    end

    overlay.enabled = force_enable.nil? ? !overlay.enabled? : !!force_enable
    overlay.enabled? ? activate_info_hud_tool(true) : deactivate_info_hud_tool
    @model.active_view.invalidate rescue nil
    detach_observers_if_idle if !overlay.enabled? && respond_to?(:detach_observers_if_idle)
    overlay.enabled?
  rescue => e
    puts "show_info_hud error: #{e.class}: #{e.message}"
    false
  end

  def self.toggle_info_hud
    show_info_hud(nil)
  end

  def self.close_info_hud
    show_info_hud(false)
  end

  def self.refresh_info_hud(_force = false)
    if info_hud_visible?
      Sketchup.active_model.active_view.invalidate
      info_hud_restore_tool_soon unless @info_hud_tool_active
    end
    true
  rescue
    false
  end

  def self.activate_info_hud_tool(force = false)
    return false unless defined?(InfoHudEditTool)
    return false unless info_hud_visible?
    return true if @info_hud_tool_active && !force

    @info_hud_tool ||= InfoHudEditTool.new
    @info_hud_tool_active = true
    Sketchup.active_model.select_tool(@info_hud_tool)
    true
  rescue => e
    @info_hud_tool_active = false
    puts "activate_info_hud_tool error: #{e.class}: #{e.message}"
    false
  end

  def self.deactivate_info_hud_tool
    @info_hud_disable_restore = true
    @info_hud_tool_active = false
    @info_hud_tool = nil
    Sketchup.active_model.select_tool(nil) rescue nil
    true
  rescue => e
    puts "deactivate_info_hud_tool error: #{e.class}: #{e.message}"
    false
  ensure
    @info_hud_disable_restore = false
  end

  def self.info_hud_clear_active_tool(tool)
    return unless @info_hud_tool.equal?(tool)
    @info_hud_tool_active = false
    @info_hud_tool = nil
  rescue
    nil
  end

  def self.info_hud_restore_tool_soon
    return false unless info_hud_visible?
    return false if @info_hud_disable_restore
    return false if @info_hud_restore_timer_pending

    @info_hud_restore_timer_pending = true
    UI.start_timer(0.15, false) do
      @info_hud_restore_timer_pending = false
      activate_info_hud_tool(true) if info_hud_visible? && !@info_hud_disable_restore
    end
    true
  rescue => e
    @info_hud_restore_timer_pending = false
    puts "info_hud_restore_tool_soon error: #{e.class}: #{e.message}"
    false
  end

  def self.info_hud_row_at(view, x, y)
    data = info_hud_overlay_data
    rows = Array(data[:rows])
    return nil if rows.empty?

    panel_w = INFO_HUD_WIDTH
    pad = INFO_HUD_PADDING
    row_h = INFO_HUD_ROW_HEIGHT
    x0 = [view.vpwidth.to_i - panel_w, 0].max
    y0 = 0
    row_x0 = x0 + pad
    row_x1 = x0 + panel_w - pad
    row_y0 = y0 + pad + INFO_HUD_TITLE_HEIGHT
    return nil if x < row_x0 || x > row_x1 || y < row_y0

    index = ((y - row_y0) / row_h).floor
    return nil if index < 0 || index >= rows.first(6).size

    row = rows[index]
    row.is_a?(Hash) ? row[:label].to_s : nil
  rescue => e
    puts "info_hud_row_at error: #{e.class}: #{e.message}"
    nil
  end

  def self.info_hud_edit(action)
    case action
    when :instance then info_hud_edit_instance
    when :material then info_hud_edit_material
    when :layer then info_hud_edit_layer
    else false
    end
  end

  def self.info_hud_current_target
    target = Sketchup.active_model.selection.first
    return nil unless target && target.valid?
    target
  rescue
    nil
  end

  def self.info_hud_edit_instance_target(target, model)
    return target if target && (target.is_a?(Sketchup::Group) || target.is_a?(Sketchup::ComponentInstance))

    Array(model.active_path).reverse_each do |item|
      return item if item && item.valid? && (item.is_a?(Sketchup::Group) || item.is_a?(Sketchup::ComponentInstance))
    end
    nil
  rescue
    nil
  end

  def self.info_hud_edit_instance
    model = Sketchup.active_model
    target = info_hud_edit_instance_target(info_hud_current_target, model)
    unless target
      UI.messagebox("Target nay khong co Instance name de sua.") rescue nil
      return false
    end

    current = target.name.to_s.strip
    current = target.definition.name.to_s.strip if current.empty? && target.respond_to?(:definition) && target.definition
    result = UI.inputbox(["Instance name"], [current], "info-HUD - Sua Instance")
    return false unless result

    value = result.first.to_s.strip
    return false if value.empty?

    model.start_operation("info-HUD Edit Instance", true)
    target.name = value
    model.commit_operation
    info_hud_after_edit
    true
  rescue => e
    model.abort_operation rescue nil
    puts "info_hud_edit_instance error: #{e.class}: #{e.message}"
    false
  end

  def self.info_hud_edit_material
    model = Sketchup.active_model
    target = info_hud_current_target
    unless target && target.respond_to?(:material=)
      UI.messagebox("Target nay khong gan duoc Material truc tiep.") rescue nil
      return false
    end

    current, sub = info_hud_material_text(target)
    default_value = current.to_s == "---" ? "" : current.to_s
    default_value = sub.to_s.sub(/\ABack:\s*/i, "") if default_value.empty? && !sub.to_s.empty?
    result = UI.inputbox(["Material"], [default_value], "info-HUD - Sua Material")
    return false unless result

    value = result.first.to_s.strip
    return false if value.empty?

    material = model.materials[value] || model.materials.add(value)
    model.start_operation("info-HUD Edit Material", true)
    target.material = material
    model.commit_operation
    info_hud_after_edit
    true
  rescue => e
    model.abort_operation rescue nil
    puts "info_hud_edit_material error: #{e.class}: #{e.message}"
    false
  end

  def self.info_hud_edit_layer
    model = Sketchup.active_model
    target = info_hud_current_target
    unless target && target.respond_to?(:layer=)
      UI.messagebox("Target nay khong gan duoc Layer/Tag.") rescue nil
      return false
    end

    current = target.layer.name.to_s rescue ""
    result = UI.inputbox(["Layer/Tag"], [current], "info-HUD - Sua Layer")
    return false unless result

    value = result.first.to_s.strip
    return false if value.empty?

    layer = model.layers[value] || model.layers.add(value)
    model.start_operation("info-HUD Edit Layer", true)
    target.layer = layer
    model.commit_operation
    info_hud_after_edit
    true
  rescue => e
    model.abort_operation rescue nil
    puts "info_hud_edit_layer error: #{e.class}: #{e.message}"
    false
  end

  def self.info_hud_after_edit
    clear_caches if respond_to?(:clear_caches)
    if respond_to?(:debounce_refresh)
      debounce_refresh(:model)
    elsif respond_to?(:refresh)
      refresh
    end
    refresh_info_hud(true)
    info_hud_restore_tool_soon
  rescue => e
    puts "info_hud_after_edit error: #{e.class}: #{e.message}"
    refresh_info_hud(true) rescue nil
    info_hud_restore_tool_soon rescue nil
  end

  def self.info_hud_overlay_data
    model = Sketchup.active_model
    selection = model.selection.to_a
    return { rows: [], message: "Chua chon target." } if selection.empty?

    target = selection.first
    rows = info_hud_target_rows(target, selection.length, model).map do |label, value, sub|
      { label: label.to_s, value: value.to_s, sub: sub.to_s }
    end
    { rows: rows, message: "" }
  rescue => e
    { rows: [], message: "Info HUD loi: #{e.message}" }
  end

  def self.info_hud_target_rows(entity, selection_count, model)
    type_text = info_hud_entity_type(entity)
    instance_name, instance_sub = info_hud_instance_name(entity, model)
    material_name, material_sub = info_hud_material_text(entity)
    layer_name = (entity.layer.name rescue "")
    entity_id = (entity.entityID rescue "")
    path_name = info_hud_active_path_name(model)

    rows = []
    rows << ["Target", type_text, selection_count.to_i > 1 ? "#{selection_count} targets dang chon" : ""]
    rows << ["Instance", instance_name, instance_sub]
    rows << ["Material", material_name, material_sub]
    rows << ["Layer", layer_name.to_s.empty? ? "---" : layer_name, "Entity ID: #{entity_id}"]
    rows << ["Context", path_name, ""] unless path_name.to_s.empty?
    rows
  end

  def self.info_hud_entity_type(entity)
    case entity
    when Sketchup::ComponentInstance then "ComponentInstance"
    when Sketchup::Group then "Group"
    when Sketchup::Face then "Face"
    when Sketchup::Edge then "Edge"
    else entity.class.to_s.split("::").last.to_s
    end
  rescue
    "Target"
  end

  def self.info_hud_instance_name(entity, model)
    if entity.respond_to?(:name) && !entity.name.to_s.strip.empty?
      name = entity.name.to_s.strip
      sub = entity.respond_to?(:definition) ? entity.definition.name.to_s : ""
      return [name, sub]
    end

    if entity.respond_to?(:definition) && entity.definition
      def_name = entity.definition.name.to_s.strip
      return [def_name, "Definition"] unless def_name.empty?
    end

    context = info_hud_active_path_name(model)
    return [context, "Active edit context"] unless context.empty?

    ["---", ""]
  rescue
    ["---", ""]
  end

  def self.info_hud_active_path_name(model)
    Array(model.active_path).reverse_each do |item|
      name = item.respond_to?(:name) ? item.name.to_s.strip : ""
      return name unless name.empty?
      if item.respond_to?(:definition) && item.definition
        def_name = item.definition.name.to_s.strip
        return def_name unless def_name.empty?
      end
    end
    ""
  rescue
    ""
  end

  def self.info_hud_material_text(entity)
    direct = info_hud_material_name(entity.material) if entity.respond_to?(:material)
    if entity.is_a?(Sketchup::Face)
      front = info_hud_material_name(entity.material)
      back = info_hud_material_name(entity.back_material)
      return [front, back.to_s.empty? ? "" : "Back: #{back}"] unless front.to_s.empty?
      return [back, "Back material"] unless back.to_s.empty?
    end
    return [direct, "Direct material"] unless direct.to_s.empty?

    nested = info_hud_nested_material_names(entity)
    return [nested.first, nested.size > 1 ? "Them: #{nested.drop(1).first(4).join(', ')}" : "Nested face material"] unless nested.empty?

    ["---", ""]
  rescue
    ["---", ""]
  end

  def self.info_hud_material_name(material)
    return "" unless material
    name = material.display_name.to_s rescue material.name.to_s
    name.to_s.strip
  rescue
    ""
  end

  def self.info_hud_nested_material_names(entity, limit = 8)
    entities = if entity.is_a?(Sketchup::ComponentInstance)
      entity.definition.entities
    elsif entity.is_a?(Sketchup::Group)
      entity.entities
    else
      nil
    end
    return [] unless entities

    names = []
    stack = [entities]
    until stack.empty? || names.size >= limit
      ents = stack.pop
      ents.each do |child|
        if child.is_a?(Sketchup::Face)
          [child.material, child.back_material].each do |mat|
            name = info_hud_material_name(mat)
            names << name unless name.empty? || names.include?(name)
            break if names.size >= limit
          end
        elsif child.is_a?(Sketchup::ComponentInstance)
          stack << child.definition.entities rescue nil
        elsif child.is_a?(Sketchup::Group)
          stack << child.entities rescue nil
        end
        break if names.size >= limit
      end
    end
    names
  rescue
    []
  end
end

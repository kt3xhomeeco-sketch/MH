module MH::Panel::Preset
  @_ds = nil
  def self.reload_display_cache
    fs = MH::Panel::Settings.read("co_chu_cai_dat_mau", 8, "cai_dat")
    face = MH::Panel::Settings.read("kieu_chu", "Arial", "cai_dat")
    font = MH::Panel::Settings.read("chu_dam", false, "cai_dat") ? "#{face} Bold" : face
    gap = MH::Panel::Settings.read("khoang_cach", 5, "cai_dat")
    v = MH::Panel::Settings.read("do_dam", 25, "cai_dat")
    base = (v * 2.55).round
    @_ds = {
      font_size: fs, font: font, gap: gap,
      opacity: { normal: base, hover: [base + 70, 255].min },
      hien_preset: MH::Panel::Settings.read("hien_thi_cai_dat_mau", true, "cai_dat"),
      hien_mode: MH::Panel::Settings.read("hien_thi_che_do", true, "cai_dat"),
      hien_setting: MH::Panel::Settings.read("hien_thi_thong_so", true, "cai_dat"),
      text_y: nil
    }
  end
  def self.ds
    reload_display_cache unless @_ds
    @_ds
  end
  def self.included(base)
    base.extend(ClassMethods)
    base.prepend(SbUserTextHandler)
  end
  module SbUserTextHandler
    def onUserText(text, view)
      return if handle_sb_user_text(text, view)
      super if defined?(super)
    end
    def onReturn(view)
      if @sb_selected_item
        @sb_selected_item = nil
        @sb_selected_vi = nil
        view.invalidate
      end
      super if defined?(super)
    end
    def update_status
      if @sb_selected_item
        item = @sb_selected_item
        val = instance_variable_get("@#{item[:key]}")
        display = case item[:fmt]
                  when :mm
                    mm = val.to_mm.round(2)
                    mm == mm.to_i ? mm.to_i.to_s : mm.to_s
                  else
                    val.is_a?(Integer) ? val.to_s : val.round(2).to_s
                  end
        MH::Panel.vcb(item[:title], display)
        return
      end
      super if defined?(super)
    end
  end
  module ClassMethods
    def settings_section(name = nil)
      name ? @_settings_section = name : @_settings_section
    end
  end
  def read(key, default, read_only = false)
    if read_only
      MH::Panel::Settings.read_only(key, default, self.class.settings_section)
    else
      MH::Panel::Settings.read(key, default, self.class.settings_section)
    end
  end
  def write(key, value)
    MH::Panel::Settings.write(key, value, self.class.settings_section)
    MH::Panel::Settings.notify_dialog(self.class.settings_section, key, value)
  end
  def init_preset(key, s, &converter)
    value = s[key.to_s]
    return if value.nil?
    value = converter.call(value) if converter
    instance_variable_set("@#{key}", value)
  end
  def init_preset_buttons(preset)
    return unless preset
    ungrouped = []
    groups = {}
    group_order = []
    preset.each_with_index do |p, i|
      next if p["disabled"]
      choice = { id: "preset_#{i}".to_sym, label: p["name"] }
      grp = p["group"]
      if grp && !grp.empty?
        unless groups[grp]
          groups[grp] = []
          group_order << grp
        end
        groups[grp] << choice
      else
        ungrouped << choice
      end
    end
    sections = []
    sections << { name: "Cài đặt mẫu", choices: ungrouped } if ungrouped.any?
    group_order.each { |g| sections << { name: g, choices: groups[g] } }
    all_choices = sections.flat_map { |s| s[:choices] }
    setup_buttons(x: 15, y: 15, choices: all_choices, sections: sections)
    load_section_collapsed
  end
  def setup_buttons(x:, y:, choices:, sections: nil, selected: nil)
    @button_config = { x: x, y: y, choices: choices, sections: sections, selected: selected }
    @hover_index = nil
    @edit_hover = nil
    @section_collapsed = {}
    @section_hover = nil
    @preset_layout_cache = nil
  end
  def draw_preset_buttons(view)
    return unless MH::Panel::Preset.ds[:hien_preset]
    return unless @button_config && @button_config[:sections]&.any?
    layout = preset_layout
    layout.each do |entry|
      if entry[:type] == :header
        draw_section_header(view, entry)
      else
        draw_preset_button(view, entry)
      end
    end
  end
  def handle_ui_mouse_move(x, y, view)
    handle_preset_mouse_move(x, y, view)
    handle_setting_mouse_move(x, y, view)
    handle_mode_mouse_move(x, y, view)
  end
  def handle_preset_mouse_move(x, y, view)
    return unless MH::Panel::Preset.ds[:hien_preset]
    return unless @button_config && @button_config[:sections]&.any?
    old_hover = @hover_index
    old_sh = @section_hover
    old_edit = @edit_hover
    @hover_index = nil
    @section_hover = nil
    @edit_hover = nil
    preset_layout.each do |entry|
      if entry[:type] == :header
        if point_in_rect?(x, y, entry[:rect])
          @section_hover = entry[:name]
          break
        end
      elsif entry[:type] == :button
        if point_in_rect?(x, y, edit_button_rect(entry[:rect]))
          @edit_hover = entry[:flat_index]
          @hover_index = entry[:flat_index]
          break
        elsif point_in_rect?(x, y, entry[:rect])
          @hover_index = entry[:flat_index]
          break
        end
      end
    end
    view.invalidate if old_hover != @hover_index || old_sh != @section_hover || old_edit != @edit_hover
  end
  def handle_preset_click(x, y)
    return unless MH::Panel::Preset.ds[:hien_preset]
    return unless @button_config
    layout = preset_layout
    layout.each do |entry|
      next unless entry[:type] == :button
      if point_in_rect?(x, y, edit_button_rect(entry[:rect]))
        choice = entry[:choice]
        index = choice[:id].to_s.split('_').last.to_i
        preset_name = @presets && @presets[index] ? @presets[index]["name"] : nil
        section = self.class.settings_section
        MH::Panel::Settings.open_settings(section, preset_name) if section
        return nil
      elsif point_in_rect?(x, y, entry[:rect])
        choice = entry[:choice]
        if @button_config[:selected] == choice[:id]
          @button_config[:selected] = nil
          @button_config[:modified] = false
          return :deselected
        end
        @button_config[:selected] = choice[:id]
        @button_config[:modified] = false
        return choice[:id]
      end
    end
    nil
  end
  def selected
    @button_config[:selected]
  end
  def save_active_preset
    if @button_config && @button_config[:selected] && @presets
      index = @button_config[:selected].to_s.split('_').last.to_i
      preset_name = @presets[index] && @presets[index]["name"]
      write("cai_dat_mau", preset_name)
    else
      write("cai_dat_mau", nil)
    end
  end
  def load_active_preset
    MH::Panel::Preset.reload_display_cache
    saved_name = read("cai_dat_mau", nil)
    return unless saved_name && @presets
    index = @presets.find_index { |p| p["name"] == saved_name }
    return unless index
    if @button_config
      @button_config[:selected] = "preset_#{index}".to_sym
      @button_config[:modified] = false
    end
    load_preset(@presets[index]["settings"])
  end
  private
  def load_section_collapsed
    tab_id = self.class.settings_section
    data = MH::Panel::Settings.read_all
    collapsed = (data[tab_id] && data[tab_id]["collapsed_groups"]) || {}
    collapsed.each { |name, val| @section_collapsed[name] = val if val }
  end
  def save_section_collapsed
    tab_id = self.class.settings_section
    data = MH::Panel::Settings.read_all
    data[tab_id] ||= {}
    data[tab_id]["collapsed_groups"] = @section_collapsed
    MH::Panel::Settings.write_all(data)
  end
  def font_size
    MH::Panel::Preset.ds[:font_size]
  end
  def button_font
    MH::Panel::Preset.ds[:font]
  end
  def text_y_offset(view)
    ds = MH::Panel::Preset.ds
    ds[:text_y] ||= begin
      opts = { size: ds[:font_size], font: ds[:font] }
      bounds = view.text_bounds(Geom::Point3d.new(0, 0, 0), "Ag", opts)
      bounds.height / 2.0
    end
  end
  def button_gap
    MH::Panel::Preset.ds[:gap]
  end
  def button_opacity
    MH::Panel::Preset.ds[:opacity]
  end
  def button_size
    { width: font_size * 22, height: font_size * 3 }
  end
  def preset_layout
    @preset_layout_cache ||= compute_preset_layout
  end
  private
  def compute_preset_layout
    return [] unless @button_config && @button_config[:sections]
    c = @button_config
    size = button_size
    gap = button_gap
    section_gap = font_size * 1.5
    y = c[:y]
    flat_i = 0
    entries = []
    @button_config[:sections].each_with_index do |section, si|
      y += section_gap if si > 0
      rect = { x: c[:x], y: y, **size }
      collapsed = @section_collapsed[section[:name]]
      entries << { type: :header, name: section[:name], rect: rect, collapsed: collapsed }
      y += size[:height] + gap
      unless collapsed
        section[:choices].each do |choice|
          rect = { x: c[:x], y: y, **size }
          entries << { type: :button, choice: choice, rect: rect, flat_index: flat_i }
          y += size[:height] + gap
          flat_i += 1
        end
      else
        flat_i += section[:choices].size
      end
    end
    entries
  end
  public
  def button_rect(flat_i)
    preset_layout.each do |entry|
      return entry[:rect] if entry[:type] == :button && entry[:flat_index] == flat_i
    end
    size = button_size
    { x: @button_config[:x], y: @button_config[:y], **size }
  end
  def draw_section_header(view, entry)
    frame = entry[:rect]
    is_hover = @section_hover == entry[:name]
    collapsed = entry[:collapsed]
    border, fill, text_c, lw = common_button_style(false, is_hover)
    op = button_opacity
    mid_alpha = ((op[:normal] + 255) / 2.0).round
    header_alpha = is_hover ? [mid_alpha + 35, 255].min : mid_alpha
    fill = [fill[0], fill[1], fill[2], header_alpha]
    draw_rounded_rect(view, frame, 5, border: border, fill: fill, line_width: lw)
    pad = font_size * 1.2
    text_y = frame[:y] + frame[:height] / 2.0 - text_y_offset(view)
    label_pt = Geom::Point3d.new(frame[:x] + pad, text_y, 0)
    view.draw_text(label_pt, entry[:name],
                   size: font_size, font: button_font,
                   color: Sketchup::Color.new(*text_c),
                   align: TextAlignLeft)
    ts = font_size * 1.0
    tri_cx = frame[:x] + frame[:width] - pad - ts * 0.5
    tri_cy = frame[:y] + frame[:height] / 2.0
    tri_color = is_hover ? [120, 120, 120] : [180, 180, 180]
    if collapsed
      tri = [
        Geom::Point3d.new(tri_cx - ts * 0.4, tri_cy - ts * 0.5, 0),
        Geom::Point3d.new(tri_cx + ts * 0.4, tri_cy, 0),
        Geom::Point3d.new(tri_cx - ts * 0.4, tri_cy + ts * 0.5, 0),
      ]
    else
      tri = [
        Geom::Point3d.new(tri_cx - ts * 0.5, tri_cy - ts * 0.35, 0),
        Geom::Point3d.new(tri_cx + ts * 0.5, tri_cy - ts * 0.35, 0),
        Geom::Point3d.new(tri_cx, tri_cy + ts * 0.45, 0),
      ]
    end
    view.drawing_color = Sketchup::Color.new(*tri_color)
    view.draw2d(GL_POLYGON, tri)
  end
  def draw_preset_button(view, entry)
    frame = entry[:rect]
    choice = entry[:choice]
    is_selected = @button_config[:selected] == choice[:id]
    fi = entry[:flat_index]
    is_hover = @hover_index == fi && @edit_hover != fi
    is_modified = is_selected && @button_config[:modified]
    border, fill, text_c, lw = common_button_style(is_selected, is_hover, is_modified)
    draw_rounded_rect(view, frame, 5, border: border, fill: fill, line_width: lw)
    pad = font_size * 1.2
    text_y = frame[:y] + frame[:height] / 2.0 - text_y_offset(view)
    label_pt = Geom::Point3d.new(frame[:x] + pad, text_y, 0)
    view.draw_text(label_pt, choice[:label],
                   size: font_size, font: button_font,
                   color: Sketchup::Color.new(*text_c),
                   align: TextAlignLeft)
    dot_r = font_size * 0.4
    dot_cx = frame[:x] + frame[:width] - pad - font_size * 0.5
    dot_cy = frame[:y] + frame[:height] / 2.0
    is_edit_hover = @edit_hover == fi
    dot_color = if is_edit_hover
                  [120, 120, 120]
                else
                  [180, 180, 180]
                end
    dot_pts = 16.times.map { |i|
      a = i * Math::PI * 2 / 16
      Geom::Point3d.new(dot_cx + Math.cos(a) * dot_r, dot_cy + Math.sin(a) * dot_r, 0)
    }
    view.drawing_color = Sketchup::Color.new(*dot_color)
    view.draw2d(GL_POLYGON, dot_pts)
    if is_selected
      border_r = dot_r + 1.5
      border_pts = 16.times.map { |i|
        a = i * Math::PI * 2 / 16
        Geom::Point3d.new(dot_cx + Math.cos(a) * border_r, dot_cy + Math.sin(a) * border_r, 0)
      }
      view.line_width = 1
      view.drawing_color = Sketchup::Color.new(210, 210, 210)
      view.draw2d(GL_LINE_LOOP, border_pts)
    end
  end
  def edit_button_rect(frame)
    pad = font_size * 1.2
    s = font_size * 2
    {
      x: frame[:x] + frame[:width] - pad - s,
      y: frame[:y],
      width: s + pad,
      height: frame[:height]
    }
  end
  def common_button_style(is_selected, is_hover, is_modified = false)
    op = button_opacity
    if is_selected && is_modified
      [[180, 180, 180], [255, 255, 255, op[:normal]], [100, 100, 100, op[:normal]], 2]
    elsif is_selected && is_hover
      [[140, 140, 140], [255, 255, 255], [100, 100, 100], 2]
    elsif is_selected
      [[180, 180, 180], [255, 255, 255], [100, 100, 100], 2]
    elsif is_hover
      [nil, [255, 255, 255, op[:hover]], [0, 0, 0], 1]
    else
      [nil, [255, 255, 255, op[:normal]], [100, 100, 100], 1]
    end
  end
  def draw_switch_pill(view, frame, on, is_hover)
    tx = frame[:x]
    ty = frame[:y]
    tw = frame[:width]
    th = frame[:height]
    r = th / 2.0
    track_color = if on
                    is_hover ? [55, 55, 110] : [73, 73, 140]
                  else
                    is_hover ? [140, 140, 140] : [180, 180, 180]
                  end
    draw_rounded_rect(view, frame, r, border: nil, fill: track_color)
    knob_r = th / 2.0 - 2
    knob_cx = on ? tx + tw - r : tx + r
    knob_cy = ty + th / 2.0
    knob_pts = 24.times.map { |i|
      a = i * Math::PI * 2 / 24
      Geom::Point3d.new(knob_cx + Math.cos(a) * knob_r, knob_cy + Math.sin(a) * knob_r, 0)
    }
    view.drawing_color = Sketchup::Color.new(255, 255, 255)
    view.draw2d(GL_POLYGON, knob_pts)
  end
  def draw_rounded_rect(view, r, radius, border:, fill:, line_width: 1)
    x, y, w, h = r[:x], r[:y], r[:width], r[:height]
    corners = [
      [x + radius, y + radius, Math::PI],
      [x + w - radius, y + radius, Math::PI * 1.5],
      [x + w - radius, y + h - radius, 0],
      [x + radius, y + h - radius, Math::PI / 2]
    ]
    pts = corners.flat_map { |cx, cy, start_angle|
      9.times.map { |i|
        a = start_angle + i * Math::PI / 16
        Geom::Point3d.new(cx + Math.cos(a) * radius, cy + Math.sin(a) * radius, 0)
      }
    }
    view.drawing_color = Sketchup::Color.new(*fill); view.draw2d(GL_POLYGON, pts) if fill
    if border
      view.line_width = line_width
      view.drawing_color = Sketchup::Color.new(*border)
      if line_width > 1
        off = line_width / 2.0
        br = {x: x - off, y: y - off, width: w + off * 2, height: h + off * 2}
        bx, by, bw, bh = br[:x], br[:y], br[:width], br[:height]
        br_corners = [
          [bx + radius, by + radius, Math::PI],
          [bx + bw - radius, by + radius, Math::PI * 1.5],
          [bx + bw - radius, by + bh - radius, 0],
          [bx + radius, by + bh - radius, Math::PI / 2]
        ]
        border_pts = br_corners.flat_map { |cx, cy, start_angle|
          9.times.map { |i|
            a = start_angle + i * Math::PI / 16
            Geom::Point3d.new(cx + Math.cos(a) * radius, cy + Math.sin(a) * radius, 0)
          }
        }
        view.draw2d(GL_LINE_LOOP, border_pts)
      else
        view.draw2d(GL_LINE_LOOP, pts)
      end
    end
  end
  def point_in_rect?(x, y, r)
    x.between?(r[:x], r[:x] + r[:width]) && y.between?(r[:y], r[:y] + r[:height])
  end
  public
  def handle_sb_user_text(text, view)
    return false unless @sb_selected_item
    item = @sb_selected_item
    var = "@#{item[:key]}"
    current = instance_variable_get(var)
    is_int = current.is_a?(Integer)
    begin
      stripped = text.strip
      if item[:fmt] == :mm
        new_val = stripped.to_l.to_mm.to_f
        raise if new_val == 0 && !stripped.match?(/\A[0\s]*\z/)
        new_val = item[:min] if item[:min] && new_val < item[:min]
        new_val = item[:max] if item[:max] && new_val > item[:max]
        instance_variable_set(var, new_val.mm)
      else
        if is_int
          raise unless stripped.match?(/\A-?\d+\z/)
          new_val = stripped.to_i
        else
          raise unless stripped.match?(/\A-?\d*\.?\d+\z/)
          new_val = stripped.to_f
        end
        new_val = item[:min] if item[:min] && new_val < item[:min]
        new_val = item[:max] if item[:max] && new_val > item[:max]
        instance_variable_set(var, new_val)
      end
      write(item[:key], new_val)
      @button_config[:modified] = true if @button_config&.dig(:selected)
    rescue
    end
    update_preview if respond_to?(:update_preview)
    if @sb_selected_item
      val = instance_variable_get(var)
      display = case item[:fmt]
                when :mm
                  mm = val.to_mm.round(2)
                  mm == mm.to_i ? mm.to_i.to_s : mm.to_s
                else
                  val.is_a?(Integer) ? val.to_s : val.round(2).to_s
                end
      MH::Panel.vcb(item[:title], display)
    end
    view.invalidate
    true
  end
  def init_setting_buttons(defs)
    @sb_defs = defs
    @sb_hover = nil
    @sb_selected_item = nil
    @sb_selected_vi = nil
  end
  def draw_setting_buttons(view)
    return unless MH::Panel::Preset.ds[:hien_setting]
    return unless @sb_defs
    @sb_view = view
    items = collect_setting_items
    return if items.empty?
    positions = calc_setting_positions(items, view)
    items.each_with_index do |item, vi|
      frame = positions[vi]
      is_hover = @sb_hover == vi
      is_selected = @sb_selected_vi == vi
      border, fill, _, lw = common_button_style(is_selected, is_hover)
      draw_rounded_rect(view, frame, 5, border: border, fill: fill, line_width: lw)
      pad = font_size * 1.2
      text_y = frame[:y] + frame[:height] / 2.0 - text_y_offset(view)
      title_color = [80, 80, 80]
      title_pt = Geom::Point3d.new(frame[:x] + pad, text_y, 0)
      view.draw_text(title_pt, item[:title],
                     size: font_size, font: button_font,
                     color: Sketchup::Color.new(*title_color),
                     align: TextAlignLeft)
      if item[:type] == :switch
        pill_w = font_size * 4
        pill_h = font_size * 2
        pill_frame = {
          x: frame[:x] + frame[:width] - pill_w - pad,
          y: frame[:y] + frame[:height] / 2.0 - pill_h / 2.0,
          width: pill_w, height: pill_h
        }
        draw_switch_pill(view, pill_frame, item[:on], is_hover)
      elsif item[:type] == :select
        pill_w = font_size * 7
        pill_h = font_size * 2
        pill_frame = {
          x: frame[:x] + frame[:width] - pill_w - pad,
          y: frame[:y] + frame[:height] / 2.0 - pill_h / 2.0,
          width: pill_w, height: pill_h
        }
        val_pt = Geom::Point3d.new(
          pill_frame[:x] + pill_frame[:width] / 2.0,
          text_y, 0
        )
        pill_border = is_selected ? [210, 210, 210] : nil
        draw_rounded_rect(view, pill_frame, pill_h / 2.0, border: pill_border, fill: [255, 255, 255], line_width: 1)
        _, _, text_color, _ = common_button_style(false, false)
        view.draw_text(val_pt, item[:label],
                       size: font_size, font: button_font,
                       color: Sketchup::Color.new(*text_color),
                       align: TextAlignCenter)
      else
        pill_w = font_size * 7
        pill_h = font_size * 2
        pill_frame = {
          x: frame[:x] + frame[:width] - pill_w - pad,
          y: frame[:y] + frame[:height] / 2.0 - pill_h / 2.0,
          width: pill_w, height: pill_h
        }
        val_pt = Geom::Point3d.new(
          pill_frame[:x] + pill_frame[:width] / 2.0,
          text_y, 0
        )
        pill_border = is_selected ? [210, 210, 210] : nil
        draw_rounded_rect(view, pill_frame, pill_h / 2.0, border: pill_border, fill: [255, 255, 255], line_width: 1)
        _, _, text_color, _ = common_button_style(false, false)
        val_color = is_selected ? [40, 40, 110] : text_color
        view.draw_text(val_pt, item[:label],
                       size: font_size, font: button_font,
                       color: Sketchup::Color.new(*val_color),
                       align: TextAlignCenter)
      end
    end
  end
  def handle_setting_mouse_move(x, y, view)
    return unless MH::Panel::Preset.ds[:hien_setting]
    return unless @sb_defs
    @sb_view = view
    old_v = @sb_hover
    @sb_hover = nil
    items = collect_setting_items
    positions = calc_setting_positions(items, view)
    items.each_with_index do |item, vi|
      if point_in_rect?(x, y, positions[vi])
        @sb_hover = vi
        break
      end
    end
    view.invalidate if old_v != @sb_hover
  end
  def handle_setting_click(x, y, view = nil)
    if @button_config && @button_config[:sections]&.any?
      preset_layout.each do |entry|
        next unless entry[:type] == :header
        if point_in_rect?(x, y, entry[:rect])
          name = entry[:name]
          @section_collapsed[name] = !@section_collapsed[name]
          @preset_layout_cache = nil
          save_section_collapsed
          (view || @sb_view)&.invalidate
          return true
        end
      end
    end
    return false unless MH::Panel::Preset.ds[:hien_setting]
    return false unless @sb_defs
    view ||= @sb_view
    return false unless view
    items = collect_setting_items
    positions = calc_setting_positions(items, view)
    items.each_with_index do |item, vi|
      if point_in_rect?(x, y, positions[vi])
        if item[:type] == :switch
          var = "@#{item[:key]}"
          new_val = !instance_variable_get(var)
          instance_variable_set(var, new_val)
          write(item[:key], new_val)
          @button_config[:modified] = true if @button_config&.dig(:selected)
          update_preview if respond_to?(:update_preview)
        elsif item[:type] == :select
          var = "@#{item[:key]}"
          keys = item[:options].keys
          idx = keys.index(instance_variable_get(var)) || 0
          new_val = keys[(idx + 1) % keys.length]
          instance_variable_set(var, new_val)
          write(item[:key], new_val)
          @button_config[:modified] = true if @button_config&.dig(:selected)
          update_preview if respond_to?(:update_preview)
        elsif @sb_selected_vi == vi
          @sb_selected_item = nil
          @sb_selected_vi = nil
          update_status if respond_to?(:update_status)
        else
          @sb_selected_item = item
          @sb_selected_vi = vi
          MH::Panel.vcb(item[:title], item[:label])
        end
        view.invalidate
        return true
      end
    end
    false
  end
  private
  def collect_setting_items
    return [] unless @sb_defs
    items = []
    @sb_defs.each do |cat_key, keys|
      if cat_key.is_a?(Array)
        cat_title, cat_cond = cat_key
        next unless check_setting_condition(cat_cond)
      else
        cat_title = cat_key
      end
      cat_values = []
      first_in_cat = true
      keys.each do |key, spec|
        fmt, title, cond, vmin, vmax = spec.is_a?(Array) ? spec : [spec, key.to_s.tr('_', ' ')]
        title = instance_exec(&title) if title.is_a?(Proc)
        var = "@#{key}"
        next unless instance_variable_defined?(var)
        val = instance_variable_get(var)
        if fmt == :select
          options = cond || {}
          next if vmin && !check_setting_condition(vmin)
          display = options[val] || val.to_s
          cat_values << { type: :select, key: key.to_s, title: title, label: display, fmt: fmt, options: options, group_start: first_in_cat }
          first_in_cat = false
          next
        end
        next if cond && !check_setting_condition(cond)
        if fmt == :switch
          display = val ? "ON" : "OFF"
          cat_values << { type: :switch, key: key.to_s, title: title, label: display, fmt: fmt, on: !!val, group_start: first_in_cat }
        else
          next unless val.is_a?(Numeric)
          display = case fmt
                    when :mm
                      mm = val.to_mm.round(2)
                      mm == mm.to_i ? mm.to_i.to_s : mm.to_s
                    else
                      val.is_a?(Integer) ? val.to_s : val.round(2).to_s
                    end
          cat_values << { type: :value, key: key.to_s, title: title, label: display, fmt: fmt, min: vmin, max: vmax, group_start: first_in_cat }
        end
        first_in_cat = false
      end
      items.concat(cat_values)
    end
    items
  end
  def check_setting_condition(cond)
    cond.is_a?(Proc) ? instance_exec(&cond) : !!instance_variable_get("@#{cond}")
  end
  def calc_setting_positions(items, view)
    size = button_size
    w = size[:width]
    h = size[:height]
    margin = 15
    section_gap = font_size * 1.5
    x = view.vpwidth - margin - w
    y = margin
    items.each_with_index.map do |item, i|
      y += section_gap if i > 0 && item[:group_start]
      pos = { x: x, y: y, width: w, height: h }
      y += h + button_gap
      pos
    end
  end
  public
  def init_mode_buttons(labels, active_proc:, on_click:)
    @mb_labels = labels
    @mb_active = active_proc
    @mb_on_click = on_click
    @mb_hover = nil
  end
  def init_mode_buttons2(labels, active_proc:, on_click:)
    @mb2_labels = labels
    @mb2_active = active_proc
    @mb2_on_click = on_click
    @mb2_hover = nil
  end
  def clear_mode_buttons2
    @mb2_labels = nil
    @mb2_active = nil
    @mb2_on_click = nil
    @mb2_hover = nil
  end
  def draw_mode_buttons(view)
    return unless MH::Panel::Preset.ds[:hien_mode]
    draw_mode_button_row(view, @mb_labels, @mb_active, @mb_hover, 0) if @mb_labels
    draw_mode_button_row(view, @mb2_labels, @mb2_active, @mb2_hover, 1) if @mb2_labels
  end
  def draw_mode_button_row(view, labels, active_proc, hover_idx, row)
    positions = calc_mode_positions(view, labels, row)
    active = active_proc.call
    labels.each_with_index do |label, i|
      frame = positions[i]
      is_active = active == i
      is_hover = hover_idx == i && !is_active
      border, fill, text_color, lw = common_button_style(is_active, is_hover)
      draw_rounded_rect(view, frame, 5, border: border, fill: fill, line_width: lw)
      text_y = frame[:y] + frame[:height] / 2.0 - text_y_offset(view)
      pt = Geom::Point3d.new(frame[:x] + frame[:width] / 2.0, text_y, 0)
      view.draw_text(pt, label,
                     size: font_size, font: button_font,
                     color: Sketchup::Color.new(*text_color),
                     align: TextAlignCenter)
    end
  end
  def handle_mode_mouse_move(x, y, view)
    return unless MH::Panel::Preset.ds[:hien_mode]
    changed = false
    if @mb_labels
      old = @mb_hover
      @mb_hover = hovered_mode_index(x, y, view, @mb_labels, 0)
      changed ||= old != @mb_hover
    end
    if @mb2_labels
      old2 = @mb2_hover
      @mb2_hover = hovered_mode_index(x, y, view, @mb2_labels, 1)
      changed ||= old2 != @mb2_hover
    end
    view.invalidate if changed
  end
  def hovered_mode_index(x, y, view, labels, row)
    calc_mode_positions(view, labels, row).each_with_index do |frame, i|
      return i if point_in_rect?(x, y, frame)
    end
    nil
  end
  def handle_mode_click(x, y, view)
    return false unless MH::Panel::Preset.ds[:hien_mode]
    if @mb_labels && (i = hovered_mode_index(x, y, view, @mb_labels, 0))
      @mb_on_click.call(i) if @mb_active.call != i
      return true
    end
    if @mb2_labels && (i = hovered_mode_index(x, y, view, @mb2_labels, 1))
      @mb2_on_click.call(i) if @mb2_active.call != i
      return true
    end
    false
  end
  private
  def calc_mode_positions(view, labels = @mb_labels, row = 0)
    h = font_size * 3.5
    gap = button_gap
    pad = font_size * 5
    opts = { size: font_size, font: button_font }
    origin = Geom::Point3d.new(0, 0, 0)
    max_w = labels.map { |l| view.text_bounds(origin, l, opts).width + pad }.max
    total_w = max_w * labels.size + gap * (labels.size - 1)
    sx = (view.vpwidth - total_w) / 2.0
    y = 15 + row * (h + gap)
    x = sx
    labels.each_with_index.map do |_, i|
      pos = { x: x, y: y, width: max_w, height: h }
      x += max_w + gap
      pos
    end
  end
end

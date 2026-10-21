# encoding: UTF-8
#
# MH_assemble — Phase 3 (bước 1): Renderer ảnh.
#   - Cô lập: ẩn mọi part KHÁC (kể cả part phẳng) -> chỉ còn cụm 3D mục tiêu.
#   - Style: Monochrome + Back Edges + nền trắng (lưu & khôi phục sau render).
#   - write_image PNG theo đúng tỉ lệ viewport (để Phase 4 chiếu toạ độ khớp).

module MH
  module Assemble
    RENDER_W = 1200 unless const_defined?(:RENDER_W) # mặc định; thực tế lấy render_width (config)
    MINI_W   = 700  unless const_defined?(:MINI_W)
    SHADED_MODE  = 2 unless const_defined?(:SHADED_MODE) # RenderMode "Shaded" (SU2025 user = 2)
    WIRE_MODE    = 0 unless const_defined?(:WIRE_MODE)    # RenderMode "Wireframe" (đoán 0; chỉnh nếu sai)
    HILITE_COLOR = Sketchup::Color.new(230, 40, 40) unless const_defined?(:HILITE_COLOR) # module = đỏ đặc

    module_function

    def render_cache_reset
      @mini_base_cache = {}
    end

    # Màu nền phần còn lại của tủ trong mini (độ mờ lấy từ config mini_alpha).
    def base_color
      Sketchup::Color.new(235, 235, 235, mini_alpha)
    end
    # View profiles + luật hiện/đánh số/liệt kê ở config.rb (config-driven, sửa được).

    module_function

    def out_dir
      model = Sketchup.active_model
      base = if model.path.to_s.empty?
               File.join(ENV['USERPROFILE'] || ENV['HOME'] || '.', 'Desktop')
             else
               File.dirname(model.path)
             end
      d = File.join(base, 'MH_assemble_out')
      Dir.mkdir(d) unless File.directory?(d)
      d
    end

    def back_edge_keys
      %w[BackEdges DrawBackEdges DisplayBackEdges]
    end

    # Áp style render, trả về hash để khôi phục.
    #   mono=true: Monochrome trắng-đen (ảnh chính).
    #   mono=false: Shaded (hiện material -> dùng cho mini-map tô màu).
    def push_style(mono: true, faces: true, wire: false, back_edges: true)
      ro = Sketchup.active_model.rendering_options
      saved = {}
      keys = ['RenderMode', 'BackgroundColor', 'DrawHorizon', 'DrawGround',
              'DisplayColorByLayer', 'DrawDepthQue', 'DrawHidden', 'ModelTransparency',
              'FaceFrontColor', 'FaceBackColor', 'EdgeColorMode'] + back_edge_keys
      keys.each { |k| saved[k] = (ro[k] rescue nil) }

      white     = Sketchup::Color.new(255, 255, 255)
      face_col  = faces ? white : Sketchup::Color.new(255, 255, 255, 0)
      begin; ro['ModelTransparency'] = false; rescue StandardError; end
      if wire
        ro['RenderMode'] = WIRE_MODE # Wireframe: chỉ đường, KHÔNG mặt -> đỏ dưới hiện hết
        back_edge_keys.each { |k| begin; ro[k] = false; break; rescue StandardError; end }
      elsif mono
        ro['RenderMode'] = 1 # Monochrome
        begin; ro['FaceFrontColor'] = face_col; rescue StandardError; end
        begin; ro['FaceBackColor']  = face_col; rescue StandardError; end
        back_edge_keys.each { |k| begin; ro[k] = back_edges; break; rescue StandardError; end }
      else
        ro['RenderMode'] = SHADED_MODE # Shaded (hiện material đỏ)
        back_edge_keys.each { |k| begin; ro[k] = false; break; rescue StandardError; end }
      end
      begin; ro['BackgroundColor'] = white; rescue StandardError; end
      begin; ro['EdgeColorMode']  = 1; rescue StandardError; end       # cạnh đen đồng nhất
      begin; ro['DisplayColorByLayer'] = false; rescue StandardError; end
      begin; ro['DrawHorizon'] = false; rescue StandardError; end
      begin; ro['DrawGround']  = false; rescue StandardError; end
      begin; ro['DrawHidden']  = false; rescue StandardError; end
      saved
    end

    # Tô material tạm cho các part, trả về danh sách để khôi phục.
    def tint_materials(parts, color)
      saved = []
      parts.each do |p|
        e = p[:entity]
        next unless e && e.valid?
        saved << [e, e.material]
        begin; e.material = color; rescue StandardError; end
      end
      saved
    end

    def restore_materials(saved)
      saved.each { |e, m| begin; e.material = m if e && e.valid?; rescue StandardError; end }
    end

    def pop_style(saved)
      ro = Sketchup.active_model.rendering_options
      saved.each { |k, v| begin; ro[k] = v unless v.nil?; rescue StandardError; end }
    end

    def container_children(e)
      if e.is_a?(Sketchup::Group)
        e.entities
      elsif e.respond_to?(:definition) && e.definition
        e.definition.entities
      end
    end

    # Áp isolation (ẩn tất cả trừ part mục tiêu + tổ tiên + ẩn tag hide_always). Trả [saved, saved_layers].
    def apply_isolation(show_parts)
      target = {}; ancestor = {}
      show_parts.each do |p|
        e = p[:entity]
        next unless e && e.valid?
        target[e.entityID] = true
        Array(p[:path]).each { |a| ancestor[a.entityID] = true if a && a.valid? }
      end
      saved = []
      saved_layers = []
      Sketchup.active_model.layers.each do |ly|
        next unless hide_always_match?(ly.name)
        saved_layers << [ly, ly.visible?]
        begin; ly.visible = false; rescue StandardError; end
      end
      hide_recur(Sketchup.active_model.entities, target, ancestor, saved, false)
      [saved, saved_layers]
    end

    def restore_isolation(s)
      return unless s
      Array(s[0]).each { |e, hid| e.hidden = hid if e && e.valid? }
      Array(s[1]).each { |ly, vis| begin; ly.visible = vis; rescue StandardError; end }
    end

    # Isolate tạm (cho render): gói trong 1 operation + abort để NHANH (tắt cập nhật UI, khôi phục tức thì).
    def isolate(show_parts)
      model = Sketchup.active_model
      op = !(model.respond_to?(:operation_active?) && model.operation_active?)
      model.start_operation('MH Isolate', true) if op
      s = apply_isolation(show_parts)
      yield
    ensure
      if op
        begin; model.abort_operation; rescue StandardError; restore_isolation(s); end
      else
        restore_isolation(s)
      end
    end

    # inside_target=true: đang ở trong 1 part được hiện -> giữ hiện mọi thứ, chỉ ẩn nhãn never_show.
    def hide_recur(entities, target, ancestor, saved, inside_target)
      entities.each do |e|
        next unless e.respond_to?(:hidden?) && e.respond_to?(:hidden=)
        if never_show?(e)
          saved << [e, e.hidden?]; e.hidden = true             # nhãn ABF_label... : luôn ẩn
          next
        end
        id = (e.entityID rescue nil)
        if inside_target
          saved << [e, e.hidden?]; e.hidden = false            # trong part: giữ hiện
          ch = container_children(e)
          hide_recur(ch, target, ancestor, saved, true) if ch  # đi sâu để bắt nhãn lồng trong
        elsif id && target[id]
          saved << [e, e.hidden?]; e.hidden = false            # part mục tiêu: hiện
          ch = container_children(e)
          hide_recur(ch, target, ancestor, saved, true) if ch  # vào trong để ẩn nhãn
        elsif id && ancestor[id]
          saved << [e, e.hidden?]; e.hidden = false            # tổ tiên: hiện rồi đi sâu
          ch = container_children(e)
          hide_recur(ch, target, ancestor, saved, false) if ch
        else
          saved << [e, e.hidden?]; e.hidden = true             # còn lại: ẩn
        end
      end
    end

    def write_png(path, width = render_width, transparent: false)
      abort_export_if_cancelled if respond_to?(:abort_export_if_cancelled)
      v = view
      h = (width.to_f * v.vpheight / v.vpwidth).round
      v.write_image(filename: path, width: width.to_i, height: h,
                    antialias: true, transparent: transparent)
      path
    end

    # Gom tất cả part (mọi tủ/module) — để biết cái gì cần ẩn.
    def all_parts(tree = scan)
      tree.values.flat_map { |mods| mods.values }.flatten
    end

    def screen_box_hash(bb, view_obj, scale)
      xs = []
      ys = []
      8.times do |i|
        sp = view_obj.screen_coords(bb.corner(i))
        xs << sp.x * scale
        ys << sp.y * scale
      end
      { 'x1' => xs.min.round, 'y1' => ys.min.round,
        'x2' => xs.max.round, 'y2' => ys.max.round }
    end

    # Bao lồi 2D của 8 góc bbox chiếu (ôm sát part hơn hình chữ nhật) -> leader bám đúng hơn.
    def screen_poly(bb, view_obj, scale)
      pts = (0..7).map do |i|
        sp = view_obj.screen_coords(bb.corner(i))
        [(sp.x * scale), (sp.y * scale)]
      end
      convex_hull(pts).map { |p| [p[0].round, p[1].round] }
    end

    def convex_hull(pts)
      pts = pts.uniq.sort_by { |p| [p[0], p[1]] }
      return pts if pts.size < 3
      cross = lambda { |o, a, b| (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]) }
      lower = []
      pts.each { |p| lower.pop while lower.size >= 2 && cross.call(lower[-2], lower[-1], p) <= 0; lower << p }
      upper = []
      pts.reverse_each { |p| upper.pop while upper.size >= 2 && cross.call(upper[-2], upper[-1], p) <= 0; upper << p }
      lower[0...-1] + upper[0...-1]
    end

    # Core: cô lập -> khung hình -> render PNG + tính bóng id + bảng -> ghi JSON.
    # all_solids: cụm 3D đầy đủ (để khung hình); show: phần hiện theo profile; listed: part có số.
    # Trả hash data (đã ghi <basename>.png + <basename>.json).
    def render_core(all_solids, show, listed, basename, meta, width)
      png = File.join(out_dir, "#{basename}.png")
      data = nil
      saved_style = nil
      begin
        isolate(show) do
          abort_export_if_cancelled if respond_to?(:abort_export_if_cancelled)
          _prod = meta['product'].to_s
          _lbl  = meta['module'].to_s
          _code = (_lbl.empty? || _lbl == '00') ? _prod : "#{_prod}.#{_lbl}"
          aim_for(all_solids, _code, meta['profile'].to_s)  # góc riêng (module×profile) nếu có, không thì mặc định
          saved_style = push_style(back_edges: main_back_edges?)
          write_png(png, width)
          v = view
          scale = width.to_f / v.vpwidth
          h = (width.to_f * v.vpheight / v.vpwidth).round
          balloons = listed.map do |p|
            sp = v.screen_coords(p[:wbb].center)
            { 'id' => p[:id], 'x' => (sp.x * scale).round, 'y' => (sp.y * scale).round,
              'box' => screen_box_hash(p[:wbb], v, scale),
              'poly' => screen_poly(p[:wbb], v, scale) }
          end
          table = listed.sort_by { |p| p[:id] || 0 }.map do |p|
            { 'id' => p[:id], 'name' => p[:part], 'qty' => 1, 'material' => p[:material] }
          end
          data = meta.merge(
            'image'    => { 'file' => File.basename(png), 'w' => width.to_i, 'h' => h },
            'balloons' => balloons,
            'obstacles' => show.map { |p| screen_box_hash(p[:wbb], v, scale) },
            'table'    => table
          )
          File.write(File.join(out_dir, "#{basename}.json"), JSON.pretty_generate(data))
        end
      ensure
        pop_style(saved_style) if saved_style
      end
      data
    end

    # Render 1 tủ (theo profile). Trả hash data.
    def render_product(product, profile: 'full', width: render_width)
      tree = scan
      mods = tree[product]
      unless mods
        puts "[#{PLUGIN_NAME}] Không có tủ #{product}"
        return nil
      end
      all_solids = mods.values.flatten.reject { |p| p[:flat] }
      if all_solids.empty?
        puts "[#{PLUGIN_NAME}] Tủ #{product} không có part 3D"
        return nil
      end
      show   = visible_parts(all_solids, profile)
      listed = listed_parts(all_solids, profile)
      data = render_core(all_solids, show, listed, "#{product}.#{profile}",
                         { 'product' => product, 'module' => nil, 'profile' => profile }, width)
      puts "[#{PLUGIN_NAME}] Render tủ #{product} [#{profile}]: #{listed.size} bóng -> #{data && data['image']['file']}"
      data
    end

    # Render 1 module (theo profile). Trả hash data.
    def render_module(product, mod, profile: 'full', width: render_width)
      label = (mod.to_s =~ /\A\d+\z/) ? format('%02d', mod.to_i) : mod.to_s
      tree  = scan
      parts = (tree[product] || {})[label] || []
      all_solids = parts.reject { |p| p[:flat] }
      if all_solids.empty?
        puts "[#{PLUGIN_NAME}] Module #{product}.#{label} không có part 3D"
        return nil
      end
      show   = visible_parts(all_solids, profile)
      listed = listed_parts(all_solids, profile)
      data = render_core(all_solids, show, listed, "#{product}.#{label}.#{profile}",
                         { 'product' => product, 'module' => label, 'profile' => profile }, width)
      puts "[#{PLUGIN_NAME}] Render module #{product}.#{label} [#{profile}]: #{listed.size} bóng -> #{data && data['image']['file']}"
      data
    end

    # Trang TỦ tổng quan: ảnh cả tủ + bóng = TỪNG MODULE (số = .y), bảng = danh sách module.
    def render_product_overview(product, profile: 'full', width: render_width)
      tree = scan
      mods = tree[product]
      return nil unless mods
      render_product_overview_from(product, mods, profile: profile, width: width,
                                   basename: "#{product}.overview.#{profile}")
    end

    # Trang tổng quan từ một cây module truyền vào. Dùng cho SELECTION để không kéo part ngoài selection.
    def render_product_overview_from(product, mods, profile: 'full', width: render_width, basename: nil)
      return nil unless mods
      all_solids = mods.values.flatten.reject { |p| p[:flat] }
      return nil if all_solids.empty?
      show = visible_parts(all_solids, profile)
      # tâm world của mỗi module (theo phần hiện)
      centers = {}
      boxes = {}
      mods.keys.sort.each do |label|
        msolids = visible_parts(mods[label], profile)
        next if msolids.empty?
        bb = world_bbox(msolids)
        centers[label] = bb.center
        boxes[label] = bb
      end
      base = basename || "#{product}.overview.#{profile}"
      png = File.join(out_dir, "#{base}.png")
      data = nil
      saved_style = nil
      begin
        isolate(show) do
          abort_export_if_cancelled if respond_to?(:abort_export_if_cancelled)
          aim_iso(all_solids)
          saved_style = push_style(back_edges: main_back_edges?)
          write_png(png, width)
          v = view
          scale = width.to_f / v.vpwidth
          h = (width.to_f * v.vpheight / v.vpwidth).round
          balloons = centers.map do |label, c|
            sp = v.screen_coords(c)
            { 'id' => label.to_i, 'x' => (sp.x * scale).round, 'y' => (sp.y * scale).round,
              'box' => screen_box_hash(boxes[label], v, scale),
              'poly' => screen_poly(boxes[label], v, scale) }
          end
          table = mods.keys.sort.map do |label|
            { 'id' => label.to_i, 'name' => "Module #{label}",
              'qty' => listed_parts(mods[label], profile).size, 'material' => '' }
          end
          data = { 'product' => product, 'module' => nil, 'profile' => profile, 'overview' => true,
                   'image' => { 'file' => File.basename(png), 'w' => width.to_i, 'h' => h },
                   'balloons' => balloons,
                   'obstacles' => boxes.values.map { |bb| screen_box_hash(bb, v, scale) },
                   'table' => table }
          File.write(File.join(out_dir, "#{base}.json"), JSON.pretty_generate(data))
        end
      ensure
        pop_style(saved_style) if saved_style
      end
      puts "[#{PLUGIN_NAME}] Tổng quan tủ #{product}: #{data && data['balloons'].size} module"
      data
    end

    # Mini-map cho 1 module: dùng chung ảnh nền cả tủ, mỗi module có overlay ĐỎ riêng.
    # Trả { 'base' => <png cả tủ B&W>, 'overlay' => <png chỉ module đỏ, nền trong suốt> } cùng góc.
    def render_minimap_module(product, label, all_solids, mods, width: mini_width, highlight: nil, over_tag: nil, base_parts: nil, base_tag: nil)
      # highlight:  nếu truyền vào -> CHỈ tô đỏ đúng các part này (vd xuất theo selection),
      #             không thì tô đỏ cả module mods[label].
      # base_parts: nếu truyền vào -> NỀN chỉ vẽ các part này (vd xuất selection: chỉ part đã chọn),
      #             không thì vẽ cả tủ (all_solids) làm ngữ cảnh.
      msolids = (highlight || mods[label] || []).reject { |p| p[:flat] }
      return nil if msolids.empty?
      bsolids = (base_parts || all_solids).reject { |p| p[:flat] }
      return nil if bsolids.empty?
      @mini_base_cache ||= {}
      btag = base_tag
      base_name = btag ? "#{product}.mini.base.#{btag}.#{width.to_i}.png" : "#{product}.mini.base.#{width.to_i}.png"
      base_key = [product.to_s, btag.to_s, width.to_i]
      base = File.join(out_dir, base_name)
      otag = over_tag || label
      over = File.join(out_dir, "#{product}.mini.#{otag}.red.png")

      # Lớp NỀN: trắng-đen ĐẶC, rõ nét (cả tủ, hoặc chỉ part đã chọn)
      unless @mini_base_cache[base_key] && File.exist?(base)
        abort_export_if_cancelled if respond_to?(:abort_export_if_cancelled)
        aim_iso(bsolids)
        st = nil
        begin
          st = push_style(mono: true, back_edges: true)
          isolate(bsolids) { write_png(base, width) }
        ensure
          pop_style(st) if st
        end
        @mini_base_cache[base_key] = true
      end

      # Lớp ĐÈ: phần tô đỏ, nền TRONG SUỐT (cùng góc nhìn với NỀN -> trùng khít)
      abort_export_if_cancelled if respond_to?(:abort_export_if_cancelled)
      aim_iso(bsolids)
      saved_mat = []
      st2 = nil
      begin
        saved_mat = tint_materials(msolids, HILITE_COLOR)
        st2 = push_style(mono: false)
        isolate(msolids) { write_png(over, width, transparent: true) }
      ensure
        pop_style(st2) if st2
        restore_materials(saved_mat)
      end

      { 'base' => base_name, 'overlay' => File.basename(over) }
    end

    # Render mini-map cho TẤT CẢ module của 1 tủ (mỗi module 1 ảnh đã tô đỏ).
    def render_minimaps(product, width: mini_width)
      tree = scan
      mods = tree[product]
      return nil unless mods
      all_solids = mods.values.flatten.reject { |p| p[:flat] }
      return nil if all_solids.empty?
      out = {}
      mods.keys.sort.each do |label|
        f = render_minimap_module(product, label, all_solids, mods, width: width)
        out[label] = f if f
      end
      puts "[#{PLUGIN_NAME}] Mini-map #{product}: #{out.size} ảnh (module tô đỏ)"
      out
    end
  end
end

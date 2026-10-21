# encoding: UTF-8
#
# MH_assemble — Phase 2: Camera.
#   - Scene (page) trùng tên (vd "SP47" / "SP47.06") -> dùng camera Scene đó.
#   - Không thì auto iso 3/4 PARALLEL, fit CHỈ quanh các part liên quan
#     (tự tính world-bbox, set camera.height — KHÔNG dùng view.zoom để khỏi fit cả model).

module MH
  module Assemble
    remove_const(:FIT_MARGIN) if const_defined?(:FIT_MARGIN)
    FIT_MARGIN = 1.30 # nới quanh đối tượng (lớn hơn -> ảnh nhỏ lại, chừa chỗ cho id)
    remove_const(:PREVIEW_FIT_MARGIN) if const_defined?(:PREVIEW_FIT_MARGIN)
    PREVIEW_FIT_MARGIN = 1.04 # ngắm viewport gần hơn, không cần chừa nhiều chỗ cho ID

    @iso_dir = Geom::Vector3d.new(0.27, -1.16, 0.35) # thấp hơn và xoay trái khoảng 20 độ

    module_function

    def view
      Sketchup.active_model.active_view
    end

    def iso_dir
      cfg = respond_to?(:camera_iso_config) ? camera_iso_config : nil
      if cfg
        @iso_dir = Geom::Vector3d.new(cfg['x'].to_f, cfg['y'].to_f, cfg['z'].to_f)
      end
      @iso_dir
    end

    # Đổi hướng iso nhanh khi đang test, vd: MH::Assemble.set_iso(-1, -1, 0.8)
    def set_iso(x, y, z)
      @iso_dir = Geom::Vector3d.new(x, y, z)
      if respond_to?(:config)
        config['camera_iso'] = { 'x' => x.to_f, 'y' => y.to_f, 'z' => z.to_f }
      end
      puts "[#{PLUGIN_NAME}] ISO_DIR = (#{x}, #{y}, #{z})"
      @iso_dir
    end

    def page_named(name)
      target = name.to_s.strip
      return nil if target.empty?
      Sketchup.active_model.pages.to_a.find { |p| p.name.to_s.strip.casecmp(target).zero? }
    end

    # Bỏ part phẳng (layout 2D), chỉ giữ part 3D lắp ráp.
    def solids(parts)
      arr = parts.reject { |p| p[:flat] }
      arr.empty? ? parts : arr   # nếu không có part 3D nào thì fallback dùng hết
    end

    # World bounding box CHỈ của các part truyền vào (ưu tiên wbb đã tính sẵn).
    def world_bbox(parts)
      bb = Geom::BoundingBox.new
      parts.each do |p|
        if p[:wbb]
          bb.add(p[:wbb].min); bb.add(p[:wbb].max)
        elsif p[:entity] && p[:entity].valid? && p[:tr]
          lb = p[:entity].bounds
          8.times { |i| bb.add(p[:tr] * lb.corner(i)) }
        end
      end
      bb
    end

    # Hướng nhìn cho 1 (mã × profile): override nếu có, không thì hướng mặc định.
    def aim_for(parts, code, profile, v = view, zoom: 1.0, margin: FIT_MARGIN)
      ov = (respond_to?(:camera_override) ? camera_override(code, profile) : nil)
      d  = ov ? Geom::Vector3d.new(ov['x'].to_f, ov['y'].to_f, ov['z'].to_f) : nil
      d  = nil if d && d.length < 1e-6
      aim_iso(parts, v, zoom: zoom, margin: margin, dir: d)
    end

    # Đặt camera iso parallel, fit KHÍT theo hình chiếu thật (giảm thừa trắng).
    # zoom > 1 -> phóng to đối tượng (chừa ít lề hơn). dir: nil -> dùng hướng mặc định.
    def aim_iso(parts, v = view, zoom: 1.0, margin: FIT_MARGIN, dir: nil)
      parts = solids(parts)
      bb = world_bbox(parts)
      return v if bb.empty?
      c    = bb.center
      diag = [bb.diagonal, 1.0].max
      dir  = (dir || iso_dir).clone
      dir.normalize!
      cam  = v.camera
      cam.perspective = false
      cam.set(c.offset(dir, diag * 3.0), c, Z_AXIS)
      cam.height = diag                  # tạm để đo hình chiếu
      xs = []; ys = []
      8.times do |i|
        sp = v.screen_coords(bb.corner(i))
        xs << sp.x; ys << sp.y
      end
      wpx = (xs.max - xs.min).to_f
      hpx = (ys.max - ys.min).to_f
      fit = [hpx / v.vpheight, wpx / v.vpwidth].max
      fit = 0.0001 if fit <= 0
      cam.height = diag * fit * margin / [zoom, 0.01].max  # /zoom -> phóng to
      v.invalidate
      v
    end

    # Bỏ isolate đang giữ (hiện lại tất cả).
    def unisolate
      restore_isolation(@iso_saved) if @iso_saved
      @iso_saved = nil
      v = Sketchup.active_model.active_view; v.invalidate if v
    end

    def frame_product(product, scene_first: true, isolate_view: true)
      tree = scan
      parts = (tree[product] || {}).values.flatten
      if parts.empty?
        puts "[#{PLUGIN_NAME}] Không thấy part nào của tủ #{product}"
        return nil
      end
      unisolate
      @iso_saved = apply_isolation(solids(parts)) if isolate_view   # giữ isolate chỉ khi thật sự cần
      if scene_first && (pg = page_named(product))
        Sketchup.active_model.pages.selected_page = pg
        puts "[#{PLUGIN_NAME}] Tủ #{product}: Scene \"#{pg.name}\"#{isolate_view ? ' (đã isolate)' : ''}"
        return pg
      end
      aim_iso(parts, margin: PREVIEW_FIT_MARGIN)
      puts "[#{PLUGIN_NAME}] Tủ #{product}: iso (#{parts.size} part)#{isolate_view ? ' + isolate' : ' không isolate'}."
      nil
    end

    def frame_module(product, mod, scene_first: true, isolate_view: true)
      label = (mod.to_s =~ /\A\d+\z/) ? format('%02d', mod.to_i) : mod.to_s
      tree = scan
      parts = (tree[product] || {})[label] || []
      if parts.empty?
        puts "[#{PLUGIN_NAME}] Không thấy part nào của module #{product}.#{label}"
        return nil
      end
      unisolate
      @iso_saved = apply_isolation(solids(parts)) if isolate_view
      if scene_first
        pg = page_named("#{product}.#{label}") || page_named("#{product}.#{mod.to_i}")
        if pg
          Sketchup.active_model.pages.selected_page = pg
          puts "[#{PLUGIN_NAME}] Module #{product}.#{label}: Scene \"#{pg.name}\"#{isolate_view ? ' (đã isolate)' : ''}"
          return pg
        end
      end
      aim_iso(parts, margin: PREVIEW_FIT_MARGIN)
      puts "[#{PLUGIN_NAME}] Module #{product}.#{label}: iso (#{parts.size} part)#{isolate_view ? ' + isolate' : ' không isolate'}."
      nil
    end

    # Ngắm theo selection hiện tại: lấy part parse được trong vùng chọn/path tổ tiên, không isolate.
    def frame_selection
      sids = selected_ids if respond_to?(:selected_ids)
      if !sids || sids.empty?
        Sketchup.status_text = "#{PLUGIN_NAME}: Chọn tủ/module/part trước khi Ngắm tủ."
        begin; UI.messagebox('Chọn tủ/module/part trước khi bấm Ngắm tủ.'); rescue StandardError; end
        return puts("[#{PLUGIN_NAME}] chưa chọn gì")
      end
      tree = scan
      parts = []
      tree.each_value do |mods|
        mods.each_value do |arr|
          arr.each { |p| parts << p if selected_part?(p, sids) }
        end
      end
      parts = solids(parts)
      if parts.empty?
        Sketchup.status_text = "#{PLUGIN_NAME}: Selection không có part SPxx."
        begin; UI.messagebox('Selection không có part SPxx để ngắm.'); rescue StandardError; end
        return puts("[#{PLUGIN_NAME}] selection không có part SPxx nào")
      end
      unisolate
      aim_iso(parts, margin: PREVIEW_FIT_MARGIN)
      puts "[#{PLUGIN_NAME}] Ngắm selection: iso (#{parts.size} part), không isolate."
      nil
    end
  end
end

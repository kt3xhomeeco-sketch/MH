# encoding: UTF-8
#
# MH_assemble — tạo bản vẽ tủ/module bằng viewer Three/HTML.
# Core scanner parse tên part theo MH::ProductContext.parse_full,
# dựng cây Tủ → Module → Part cho exporter Three.
#
# Quy ước tên part (parts rời rạc, không group container):
#   "__28. SP47.6_Đợt Cố Định"
#     __ cố định(bỏ) · id=28 · tủ=SP47 · module=06 (.6) · part="Đợt Cố Định"

require 'sketchup.rb'
require File.join(Sketchup.find_support_file('Plugins'), 'MH_shared.rb')
raise "[MH_assemble] requires MH_shared" unless defined?(MH::Shared) && defined?(MH::TraverseModel)

module MH
  module Assemble
    PLUGIN_NAME = 'MH_assemble'.freeze
    VERSION     = '0.1.0'.freeze
    ROOT        = File.dirname(__FILE__).freeze
    FLAT_EPS    = 0.01 unless const_defined?(:FLAT_EPS) # Z-extent <= EPS (inch) => part phẳng (layout 2D)
    @tree_cache = nil  # reset cache scan mỗi lần load (model có thể đã đổi)

    module_function

    # Đảm bảo parser shared (có parse_full) đã nạp đúng phiên bản mới.
    def ensure_parser
      shared_loader = File.join(File.dirname(ROOT), 'MH_shared.rb')
      require shared_loader if File.exist?(shared_loader)
      defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:parse_full)
    rescue => e
      puts "[#{PLUGIN_NAME}] ensure_parser error: #{e.class}: #{e.message}"
      false
    end

    def name_of(ent)
      nm = ent.name.to_s
      nm = ent.definition.name.to_s if nm.strip.empty? && ent.respond_to?(:definition)
      nm
    end

    # Duyệt đệ quy mọi Group/ComponentInstance.
    # yield (entity, name, parent_tr) — parent_tr = transform world của CONTAINER.
    # e.bounds nằm trong hệ toạ độ cha => world = parent_tr * e.bounds.corner(i).
    def walk(entities, tr = Geom::Transformation.new, path = [], &blk)
      MH::TraverseModel.each(root: entities, max_depth: -1, types: %i[group component]) do |ent, ctx|
        blk.call(ent, name_of(ent), tr * ctx.transform, path + ctx.path)
      end
    end

    # => { "SP47" => { products:.., modules: { "06" => [ part_hash, ... ] } } }
    # Xoá cache scan (gọi khi model đổi / bắt đầu thao tác mới).
    def scan_reset
      @tree_cache = nil
      render_cache_reset if respond_to?(:render_cache_reset)
    end

    # scan có CACHE: quét model 1 lần, dùng lại trong cùng thao tác (nhanh hơn nhiều).
    def scan(model = Sketchup.active_model)
      @tree_cache ||= scan!(model)
    end

    # part_hash: { id:, part:, material:, entity:, center:[x,y,z], module_code:, raw: }
    def scan!(model = Sketchup.active_model)
      return {} unless model
      ensure_parser
      tree = {}
      walk(model.entities) do |ent, nm, tr, path|
        info = MH::ProductContext.parse_full(nm)
        next unless info
        # world bbox của riêng part
        lb  = ent.bounds
        wbb = Geom::BoundingBox.new
        8.times { |i| wbb.add(tr * lb.corner(i)) }
        c    = wbb.center
        flat = wbb.depth.to_f <= FLAT_EPS   # nằm bẹp Z -> layout 2D, không phải lắp ráp
        prod = info[:product]
        mod  = info[:modul_label]
        tree[prod] ||= {}
        (tree[prod][mod] ||= []) << {
          id:          info[:id],
          numbered:    info[:numbered],
          part:        info[:part],
          material:    (ent.material ? ent.material.display_name : '—'),
          entity:      ent,
          tr:          tr,
          path:        path.dup,   # đường tổ tiên (để isolate)
          wbb:         wbb,
          flat:        flat,
          center:      [c.x.to_f.round(1), c.y.to_f.round(1), c.z.to_f.round(1)],
          module_code: info[:module_code],
          raw:         nm
        }
      end
      tree
    end

    # In cây ra console để kiểm.
    def report(model = Sketchup.active_model)
      scan_reset
      tree = scan(model)
      if tree.empty?
        puts "[#{PLUGIN_NAME}] Không parse được part nào."
        puts "  Kỳ vọng tên kiểu: \"__28. SP47.6_Đợt Cố Định\""
        return tree
      end
      total_parts = 0
      total_flat  = 0
      tree.keys.sort.each do |prod|
        mods = tree[prod]
        n_parts = mods.values.map(&:size).inject(0, :+)
        n_flat  = mods.values.flatten.count { |p| p[:flat] }
        total_parts += n_parts
        total_flat  += n_flat
        puts "TỦ #{prod}  — #{mods.size} module, #{n_parts} part (#{n_parts - n_flat} 3D / #{n_flat} phẳng)"
        mods.keys.sort.each do |mod|
          parts = mods[mod].sort_by { |p| [p[:id] || 0, p[:part]] }
          n3d = parts.count { |p| !p[:flat] }
          puts "  Module #{prod}.#{mod}  (#{n3d} 3D / #{parts.size - n3d} phẳng)"
          parts.each do |p|
            tag = []
            tag << 'phẳng' if p[:flat]
            tag << 'không số' unless p[:numbered]
            suffix = tag.empty? ? '' : " (#{tag.join(', ')})"
            puts "    [#{p[:numbered] ? p[:id] : '·'}] #{p[:part]}#{suffix}  | #{p[:material]}"
          end
        end
      end
      n_mod = tree.values.map(&:size).inject(0, :+)
      puts "----"
      puts "Tổng: #{tree.size} tủ, #{n_mod} module, #{total_parts} part (#{total_parts - total_flat} 3D / #{total_flat} phẳng)"
      tree
    end

    # ---- Nạp backend + exporter Three ------------------------------------
    load File.join(ROOT, 'config.rb')
    load File.join(ROOT, 'camera.rb')
    load File.join(ROOT, 'renderer.rb')
    load File.join(ROOT, 'three_export.rb')
    load File.join(ROOT, 'three_dashboard.rb')

    # ---- Menu + Toolbar (1 lần): chỉ MỞ bảng điều khiển ------------------
    unless file_loaded?(__FILE__)
      tb  = UI::Toolbar.new('MH Assemble')
      cmd = UI::Command.new('MH Assemble') { MH::Assemble.dashboard }
      cmd.tooltip = 'MH Assemble — xuất bản vẽ Three/HTML'
      cmd.status_bar_text = 'Mở bảng điều khiển MH Assemble'
      icon = File.join(ROOT, 'icons', 'assemble.svg')
      if File.exist?(icon)
        cmd.small_icon = icon
        cmd.large_icon = icon
      end
      tb.add_item(cmd)
      tb.restore
      file_loaded(__FILE__)
    end
  end
end

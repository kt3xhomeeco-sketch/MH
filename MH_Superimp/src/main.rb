# ==========================================================
# MH::Superimp – Live Box Preview + Edge Plane Selection
# 3-Click Workflow:
#   Click 1: Chọn cạnh
#   Click 2: Xác nhận plane 2D
#   Click 3: Import (trong plane = 2D, ngoài plane = 3D với depth)
# ==========================================================

require 'sketchup.rb'
require File.join(Sketchup.find_support_file('Plugins'), 'MH_shared.rb')
raise "[MH::Superimp] requires MH_shared" unless defined?(MH::Shared) && defined?(MH::ExcelBridge)

module MH
  module Superimp
    def self.reload
      load __FILE__
    end

    XLSX_FILE = File.join(__dir__, 'import_list.xlsx').freeze
    SWAP_TIMEOUT = 0.8 # giây - thời gian chờ giữa các lần nhấn số/số đo
    DEFAULTS_KEY = 'MH_Superimp'.freeze
    MATERIAL_SOURCE_MANUAL_KEY = 'material_source_manual'.freeze

    class << self
      attr_accessor :active_tool
    end

    def self.normalize_import_path(path)
      path.to_s.tr('\\', '/').downcase
    end

    def self.rebuild_import_indexes(rows = @import_list)
      @item_by_path = {}
      Array(rows).each do |item|
        @item_by_path[normalize_import_path(item[:path])] = item
      end
      @swap_map_cache = nil
      @swap_map_source_id = nil
      true
    end

    def self.swap_map
      rows = import_list
      if @swap_map_cache && @swap_map_source_id == rows.object_id
        return @swap_map_cache
      end

      map = {}
      rows.each do |item|
        group = item[:group].to_s
        swap_key = item[:swap_key].to_i
        if !group.empty? && swap_key > 0
          map[group] ||= {}
          map[group][swap_key.to_s] = { path: item[:path], name: item[:name] }
        end
      end
      @swap_map_cache = map
      @swap_map_source_id = rows.object_id
      map
    end

    def self.item_for_path(path)
      rows = import_list
      rebuild_import_indexes(rows) unless @item_by_path
      @item_by_path[normalize_import_path(path)]
    end

    def self.material_source_manual?
      value = Sketchup.read_default(DEFAULTS_KEY, MATERIAL_SOURCE_MANUAL_KEY, '0').to_s
      %w[1 true yes on manual].include?(value.strip.downcase)
    rescue
      false
    end

    def self.save_material_source_manual(value)
      Sketchup.write_default(DEFAULTS_KEY, MATERIAL_SOURCE_MANUAL_KEY, value ? '1' : '0')
    rescue => e
      puts "[MH::Superimp] save material source error: #{e.class}: #{e.message}"
      nil
    end

    def self.drawer_slide_info(item)
      return nil unless item

      group = item[:group].to_s.strip.upcase
      text = [item[:name], item[:path], group].join(' ').downcase
      kind = if group.start_with?('RA') || text.include?('ray âm') || text.include?('ray am')
               :ray_am
             elsif group.start_with?('RB') || text.include?('ray bi')
               :ray_bi
             end
      return nil unless kind

      size = text.scan(/\d+(?:[.,]\d+)?/).map { |n| n.tr(',', '.').to_f }.select { |n| n >= 200 && n <= 700 }.last
      return nil unless size

      {
        kind: kind,
        group: group,
        size_mm: size,
        offset_mm: kind == :ray_am ? 15.0 : 5.0
      }
    end

    def self.resolve_depth_based_import(path, depth_length)
      item = item_for_path(path)
      info = drawer_slide_info(item)
      return { path: path, item: item, changed: false } unless info && depth_length

      target_mm = depth_length.to_mm - info[:offset_mm]
      candidates = import_list.filter_map do |candidate|
        cinfo = drawer_slide_info(candidate)
        next unless cinfo && cinfo[:kind] == info[:kind] && cinfo[:group] == info[:group]
        next unless File.exist?(candidate[:path].to_s)

        candidate.merge(_drawer_size_mm: cinfo[:size_mm])
      end
      return { path: path, item: item, changed: false, target_mm: target_mm } if candidates.empty?

      tolerance_mm = 0.5
      chosen = candidates.select { |candidate| candidate[:_drawer_size_mm] <= target_mm + tolerance_mm }.max_by { |candidate| candidate[:_drawer_size_mm] }
      chosen ||= candidates.min_by { |candidate| candidate[:_drawer_size_mm] }

      {
        path: chosen[:path],
        item: chosen,
        changed: chosen[:path].to_s.tr('\\', '/').downcase != path.to_s.tr('\\', '/').downcase,
        target_mm: target_mm,
        size_mm: chosen[:_drawer_size_mm],
        kind: info[:kind]
      }
    end

    def self.notify_imported_dc(instance, context = {})
      return unless instance && instance.valid?
      ensure_registry_runtime
      return unless defined?(MH::RegistryApp::Connector)

      connector = MH::RegistryApp::Connector.get('dc_import_pipeline') rescue nil
      return unless connector && connector.respond_to?(:after_import_dc)

      connector.after_import_dc(instance, context)
    rescue => e
      puts "[MH::Superimp] dc_import_pipeline error: #{e.class}: #{e.message}"
    end

    def self.ensure_registry_runtime
      plugins = Sketchup.find_support_file('Plugins')
      load File.join(plugins, 'MH_Registry', 'main.rb') unless defined?(MH::RegistryApp)
      if defined?(MH::RegistryApp) && MH::RegistryApp.respond_to?(:ensure_runtime_ready)
        MH::RegistryApp.ensure_runtime_ready
      end
    rescue => e
      puts "[MH::Superimp] registry runtime bootstrap error: #{e.class}: #{e.message}"
      false
    end

    def self.watch_placed_instance(definition, context = {})
      return unless definition && definition.valid?

      attempts = 0
      timer_id = nil
      timer_id = UI.start_timer(0.25, true) do
        attempts += 1
        model = Sketchup.active_model
        instance = model.selection.to_a.find { |entity|
          entity.is_a?(Sketchup::ComponentInstance) &&
            entity.definition == definition &&
            entity.get_attribute('MH_Registry', 'dc_import_pipeline_seen') != true
        }

        if instance && instance.valid?
          instance.set_attribute('MH_Registry', 'dc_import_pipeline_seen', true)
          notify_imported_dc(instance, context)
          UI.stop_timer(timer_id) if timer_id
        elsif attempts >= 40
          UI.stop_timer(timer_id) if timer_id
        end
      end
    rescue => e
      puts "[MH::Superimp] watch_placed_instance error: #{e.class}: #{e.message}"
    end

    def self.registry_import_list
      ensure_registry_runtime
      return [] unless defined?(MH::RegistryApp::Connector)

      connector = MH::RegistryApp::Connector.get('superimp') rescue nil
      return [] unless connector && connector.respond_to?(:import_list)

      Array(connector.import_list).filter_map do |row|
        h = row.is_a?(Hash) ? row : {}
        name = (h['name'] || h[:name]).to_s.strip
        path = (h['path'] || h[:path]).to_s.strip
        next if name.empty? && path.empty?

        group = (h['group'] || h[:group]).to_s.strip
        group = group.sub(/\.0$/, '') if group.end_with?('.0')
        swap_key = (h['swap_key'] || h[:swap_key]).to_s.strip
        swap_key = swap_key.sub(/\.0$/, '') if swap_key.end_with?('.0')
        {
          name: name,
          path: path,
          shortcut: (h['shortcut'] || h[:shortcut]).to_s.strip,
          group: group,
          swap_key: swap_key.to_i > 0 ? swap_key.to_i : 0
        }
      end
    rescue => e
      puts "[MH::Superimp] Registry import list error: #{e.class}: #{e.message}"
      []
    end

    # ---- Đọc list: ưu tiên Registry, fallback xlsx cũ ----
    def self.load_import_list
      registry_rows = registry_import_list
      unless registry_rows.empty?
        puts "[MH::Superimp] Loaded #{registry_rows.length} items from MH_Registry."
        return registry_rows
      end

      load_import_list_xlsx
    end

    # ---- Fallback đọc xlsx cũ bằng ExcelBridge ----
    def self.load_import_list_xlsx
      list = []
      unless File.exist?(XLSX_FILE)
        puts "[MH::Superimp] XLSX not found: #{XLSX_FILE}"
        return list
      end
      
      begin
        data_rows = MH::ExcelBridge.read_sheet(XLSX_FILE, sheet: 'ImportList')
        
        data_rows.each_with_index do |row, i|
          next if i == 0 # Bỏ qua header
          next unless row.is_a?(Array)
          
          name     = row[0].to_s.strip
          path     = row[1].to_s.strip
          shortcut = row[2].to_s.strip
          group    = row[3].to_s.strip
          group    = group.sub(/\.0$/, '') if group.end_with?('.0')
          swap_key = row[4].to_s.strip.to_i

          next if name.empty? || path.empty?
          list << { 
            name: name, 
            path: path, 
            shortcut: shortcut, 
            group: group, 
            swap_key: swap_key > 0 ? swap_key : 0 
          }
        end
        puts "[MH::Superimp] Loaded #{list.length} items from Excel."
      rescue => e
        puts "[MH::Superimp] Error loading xlsx: #{e.message}"
      end
      list
    end

    def self.import_list
      unless @import_list
        @import_list = load_import_list
        rebuild_import_indexes(@import_list)
      end
      @import_list
    end

    def self.reload_import_list
      @import_list = nil
      @item_by_path = nil
      @swap_map_cache = nil
      @swap_map_source_id = nil
      rows = import_list
      sync_registry_menu!
      rows
    end

    def self.sync_registry_menu!
      return false unless defined?(MH::RegistryApp::Menu)

      import_list.each_with_index do |item, index|
        sk = item[:swap_key].to_i > 0 ? " [#{item[:swap_key]}]" : ''
        sc = item[:shortcut].to_s.empty? ? '' : " (#{item[:shortcut]})"
        label = "#{item[:name]}#{sk}#{sc}"
        key = "import_#{index}_#{MH::Text.slug(item[:name])}"
        path = item[:path].to_s
        MH::RegistryApp::Menu.add(app: 'Superimp', key: key, label: label) { MH::Superimp.import_or_replace(path) }
      end
      true
    rescue => e
      puts "[MH::Superimp] sync registry menu error: #{e.class}: #{e.message}"
      false
    end

    # Gọi sau khi Registry/Excel được reload để tool đang mở không giữ
    # material profile và các dòng HUD từ lần nạp trước.
    def self.refresh_material_runtime
      tool = @active_tool
      return false unless tool && tool.respond_to?(:refresh_material_runtime)

      tool.refresh_material_runtime
    end

    # ---- Ghi list: ưu tiên Registry, fallback xlsx cũ ----
    def self.write_import_list_xlsx(rows_data, reload_after: true)
      saved_to_registry = false
      begin
        ensure_registry_runtime
        connector = defined?(MH::RegistryApp::Connector) ? (MH::RegistryApp::Connector.get('superimp') rescue nil) : nil
        if connector && connector.respond_to?(:save_import_list)
          result = connector.save_import_list(rows_data, merge: true)
          if result && result['ok']
            saved_to_registry = true
            puts "[MH::Superimp] Saved #{result['count']} items to MH_Registry Config.xlsx"
          else
            puts "[MH::Superimp] Registry save failed: #{result && result['error']}"
          end
        end
      rescue => e
        puts "[MH::Superimp] Registry save error: #{e.class}: #{e.message}"
      end

      if saved_to_registry
        reload_import_list if reload_after
        return true
      end

      begin
        headers = ['Tên', 'Đường dẫn', 'Phím tắt menu', 'Nhóm', 'Swap Key (1-99)']
        rows = [headers]
        rows_data.each do |item|
          rows << [
            item[:name],
            item[:path],
            item[:shortcut],
            item[:group].to_s.empty? ? '' : item[:group],
            item[:swap_key].to_i > 0 ? item[:swap_key].to_i : ''
          ]
        end
        MH::ExcelBridge.write(XLSX_FILE, sheets: { 'ImportList' => rows })
        puts "[MH::Superimp] Saved fallback xlsx to #{XLSX_FILE}"
      rescue => e
        puts "[MH::Superimp] Error saving xlsx: #{e.message}"
        return false
      end
      reload_import_list if reload_after
      true
    end

    # ---- Dialog config ----
    def self.show_config_dialog
      rows = import_list
      rows_html = rows.each_with_index.map { |item, i|
        sk = item[:swap_key].to_i > 0 ? item[:swap_key].to_i : ''
        gr = item[:group].to_s
        "<tr><td class='idx'>#{i+1}.</td>" \
        "<td><input class='name' value=\"#{item[:name].gsub('"','&quot;')}\"></td>" \
        "<td><input class='path' value=\"#{item[:path].gsub('"','&quot;')}\"></td>" \
        "<td><input class='sc' value=\"#{item[:shortcut].gsub('"','&quot;')}\"></td>" \
        "<td><input class='gr' value=\"#{gr.gsub('"','&quot;')}\"></td>" \
        "<td><input class='sk' type='number' min='0' max='99' value=\"#{sk}\"></td></tr>"
      }.join
      if rows.empty?
        rows_html = ("<tr><td class='idx'>1.</td><td><input class='name'></td>" \
          "<td><input class='path'></td><td><input class='sc'></td>" \
          "<td><input class='gr'></td>" \
          "<td><input class='sk' type='number' min='0' max='99'></td></tr>") * 3
      end

      html = <<~HTML
        <!DOCTYPE html><html><head><meta charset="UTF-8"><style>
        body{background:#111;color:#eee;font-family:Arial;margin:12px}
        table{border-collapse:collapse;width:100%}
        th,td{border:1px solid #555;padding:4px}
        th{background:#222;font-size:12px}
        input{width:100%;box-sizing:border-box;background:#000;color:#eee;border:1px solid #666;padding:3px}
        input.sk{width:50px;text-align:center}
        input.gr{width:70px;text-align:center}
        button{padding:5px 12px;background:#333;color:#eee;border:1px solid #777;cursor:pointer;margin:2px}
        button:hover{background:#555}
        </style></head><body>
        <h2>MH::Superimp Import List (Registry)</h2>
        <p style="color:#888;font-size:11px">Nhóm: cùng tên nhóm = cùng bộ swap key. Ví dụ: nhóm "MH" key 1=Tấm đứng, nhóm "18" key 1=Tấm đứng 18</p>
        <table><thead><tr>
          <th></th><th>Tên</th><th>Đường dẫn</th><th>Phím tắt</th><th>Nhóm</th><th>Swap</th>
        </tr></thead>
        <tbody id="rows">#{rows_html}</tbody></table><br>
        <button onclick="addRow()">+ Thêm</button>
        <button onclick="save()">💾 Lưu</button>
        <button onclick="openXlsx()">📂 Mở Config</button>
        <script>
        function addRow(){
          document.getElementById('rows').insertAdjacentHTML('beforeend',
            '<tr><td class=idx></td><td><input class=name></td><td><input class=path></td>' +
            '<td><input class=sc></td><td><input class=gr></td><td><input class=sk type=number min=0 max=99></td></tr>');
          renum();
        }
        function renum(){
          document.querySelectorAll('#rows tr').forEach((r,i)=>{
            r.querySelector('.idx').textContent=(i+1)+'.';
          });
        }
        function save(){
          let data=[];
          document.querySelectorAll('#rows tr').forEach(r=>{
            let n=r.querySelector('.name').value.trim();
            let p=r.querySelector('.path').value.trim();
            let s=r.querySelector('.sc').value.trim();
            let g=r.querySelector('.gr').value.trim();
            let k=r.querySelector('.sk').value.trim();
            if(n||p) data.push(n+'|'+p+'|'+s+'|'+g+'|'+k);
          });
          window.sketchup.save_list(data.join('\\n'));
        }
        function openXlsx(){ window.sketchup.open_xlsx(); }
        renum();
        </script></body></html>
      HTML

      dlg = ::UI::HtmlDialog.new(dialog_title: "MH::Superimp", width: 1100, height: 500)
      dlg.set_html(html)
      dlg.add_action_callback('save_list') do |d, text|
        rows_data = []
        # JS gửi literal "\\n" (2 ký tự), Ruby cần split theo cả literal \\n lẫn newline thật
        text.to_s.split(/\\n|\n/).each do |line|
          parts = line.split('|', 5).map { |s| s ? s.strip : '' }
          next if parts[0].to_s.empty? && parts[1].to_s.empty?
          rows_data << { name: parts[0].to_s, path: parts[1].to_s, shortcut: parts[2].to_s, group: parts[3].to_s, swap_key: parts[4].to_i }
        end
        if write_import_list_xlsx(rows_data)
          ::UI.messagebox("Đã lưu danh sách Superimp vào MH_Registry/Config.xlsx!")
        else
          ::UI.messagebox("Lỗi khi lưu!")
        end
      end
      dlg.add_action_callback('open_xlsx') do |d|
        registry_config = if defined?(MH::RegistryApp) && MH::RegistryApp.respond_to?(:config_path)
                            MH::RegistryApp.config_path
                          else
                            File.join(Sketchup.find_support_file('Plugins'), 'MH_Registry', 'Config.xlsx')
                          end
        if File.exist?(registry_config)
          UI.openURL(registry_config)
        elsif File.exist?(XLSX_FILE)
          UI.openURL(XLSX_FILE)
        else
          ::UI.messagebox("File chưa tồn tại. Hãy lưu trước.")
        end
      end
      dlg.show
    end

    # Redraw Dynamic Component sau khi import + scale.
    #
    # QUAN TRỌNG: hàm này được gọi BÊN TRONG start_operation (trước commit) ở các
    # hàm import. Nếu gọi redraw_with_undo ngay lúc đó -> nó tự mở operation undo
    # riêng -> lồng operation -> redraw thất bại âm thầm -> hình học DC KHÔNG
    # regenerate theo kích thước mới -> bounding box (đã scale) to hơn hình học
    # = "khe hở" thấy khi import (kéo scale tay mới hết).
    #
    # Khắc phục: dời redraw ra sau commit bằng UI.start_timer(0). Timer fire ở
    # tick kế tiếp, tức SAU khi commit_operation và toàn bộ stack hiện tại kết
    # thúc, nên redraw chạy như một operation sạch, độc lập.
    def self.redraw_dc_deferred(inst)
      return unless defined?($dc_observers) && inst && inst.valid?
      UI.start_timer(0, false) do
        begin
          if inst && inst.valid?
            dc = $dc_observers.get_latest_class rescue nil
            dc.redraw_with_undo(inst) if dc && dc.respond_to?(:redraw_with_undo)
          end
        rescue => e
          puts "[MH::Superimp] redraw_dc error: #{e.class}: #{e.message}"
        end
      end
    end

    # Tương thích ngược: các call site cũ gọi safe_redraw_dc trước commit -> nay
    # tự động defer ra sau commit.
    def self.safe_redraw_dc(inst)
      redraw_dc_deferred(inst)
    end

    # ======================================================
    # HELPER FUNCTIONS
    # ======================================================
    def self.edges_are_collinear?(e1, e2)
      MH::Geo::Box.edges_are_collinear?(e1, e2)
    end

    def self.is_intersection_vertex?(v)
      MH::Geo::Box.intersection_vertex?(v)
    end

    def self.find_connected_collinear_edges(start_edge)
      MH::Geo::Box.connected_collinear_edges(start_edge)
    end

    def self.calculate_edges_length(edges, transform = IDENTITY)
      MH::Geo::Box.edges_length(edges, transform)
    end

    def self.get_edge_axis(edge, transform = IDENTITY)
      MH::Geo::Box.edge_axis(edge, transform)
    end

    def self.get_edge_endpoints(edges, transform)
      MH::Geo::Box.edge_endpoints(edges, transform)
    end

    def self.get_edge_line(edge, transform)
      MH::Geo::Box.edge_line(edge, transform)
    end

    # ==========================================================
    # TOOL: 3-Click Workflow
    # ==========================================================
    class LiveBoxPreviewTool
      EDGE_COLOR = Sketchup::Color.new(0, 255, 255, 255)
      SELECTED_COLOR = Sketchup::Color.new(0, 255, 0, 255)
      PLANE_COLOR = Sketchup::Color.new(255, 255, 0, 80)
      BOX_COLOR = Sketchup::Color.new(255, 255, 0, 120)
      FINAL_BOX_COLOR = Sketchup::Color.new(0, 255, 128, 100)
      LINE_WIDTH = 4
      REGISTRY_CONTEXT_CACHE_TTL = 5.0
      MATERIAL_ROWS_CACHE_TTL = 10.0
      HUD_TEXT_COLOR = Sketchup::Color.new(30, 30, 30).freeze
      HUD_MUTED_COLOR = Sketchup::Color.new(100, 100, 100).freeze
      HUD_GROUP_COLOR = Sketchup::Color.new(150, 150, 150).freeze
      HUD_DIVIDER_COLOR = Sketchup::Color.new(220, 220, 220).freeze
      HUD_STATUS_COLOR = Sketchup::Color.new(0, 150, 0).freeze
      HUD_BUTTON_BG = Sketchup::Color.new(235, 235, 235, 240).freeze
      HUD_BUTTON_BORDER = Sketchup::Color.new(210, 210, 210).freeze
      HUD_CHOICE_BG = Sketchup::Color.new(235, 235, 235, 230).freeze
      HUD_CHOICE_BORDER = Sketchup::Color.new(210, 210, 210, 235).freeze
      HUD_CHOICE_SELECTED_BG = Sketchup::Color.new(70, 75, 140, 235).freeze
      HUD_CHOICE_SELECTED_BORDER = Sketchup::Color.new(50, 55, 120, 245).freeze
      HUD_CHOICE_SELECTED_TEXT = Sketchup::Color.new(255, 255, 255).freeze
      HUD_LIST_BG = Sketchup::Color.new(245, 245, 247, 218).freeze
      HUD_LIST_BORDER = Sketchup::Color.new(210, 210, 214, 235).freeze

      def initialize(import_path)
        @import_path = import_path
        @mode = :hovering
        @ip = Sketchup::InputPoint.new
        
        @picked_face = nil
        @picked_path = nil
        @box_corners = nil
        
        @hover_edge = nil
        @hover_edges = []
        @hover_length = 0
        @hover_axis = :OTHER
        @hover_transform = IDENTITY
        
        @sel_edge = nil
        @sel_edges = []
        @sel_length = 0
        @sel_axis = :OTHER
        @sel_transform = IDENTITY
        @sel_line = nil
        @edge_start_pt = nil
        @edge_end_pt = nil
        
        @snap_pt = nil
        @distance = 0
        @distance_axis = :OTHER
        @distance_locked = false
        @plane_corners = nil
        
        @final_box = nil
        @box_depth = 0
        @plane_normal = nil
        @push_direction = 1
        @depth_locked = false
        
        @offset_y = 0
        @offset_z = 0
        @set_z = nil
        @offset_z_after_set = false
        
        @face_lock = :none
        @last_x = 0
        @last_y = 0
        
        # Missing dimension handling
        @missing_axis = nil
        @missing_axis_direction = nil
        @face_origin = nil
        @face_normal = nil
        @live_box_size_override = nil
        
        # Right-click lock for push distance
        @rbutton_held = false
        @locked_base_point = nil
        @locked_axis_info = nil
        @locked_origin = nil
        @locked_missing_axis = nil
        
        # Face push mode (2-click workflow)
        @push_base_point = nil
        @push_axis_info = nil

        # Swap shortcut (phím số 1-99)
        @swap_map = MH::Superimp.swap_map
        norm_path = @import_path.tr('\\', '/').downcase
        item = MH::Superimp.import_list.find { |it| it[:path].tr('\\', '/').downcase == norm_path }
        @group = item ? item[:group] : nil
        @swap_buffer = ""
        @swap_timer = nil
        @swap_last_msg = nil
        @swap_msg_timer = nil
        @material_profile = nil
        @material_profile_manual = false
        @material_source_manual = MH::Superimp.material_source_manual?  # false=Auto(Excel), true=Manual(danh sach tay)
        @mode_button_rect = nil          # vung bam nut gat (set trong draw)
        @reload_button_rect = nil        # ep nap lai Excel + cache HUD
        @last_imported_dc = nil          # DC vua import/replace - muc tieu uu tien khi go do day
        @material_profile_msg = nil
        @material_profile_msg_timer = nil
        @alt_key_down = false
        @thickness_input_buffer = ''
        @registry_context_cache = nil
        @registry_context_cache_key = nil
        @registry_context_cache_time = 0.0
        @material_rows_cache = nil
        @material_rows_cache_key = nil
        @material_rows_cache_time = 0.0
        @swap_hud_items_cache = nil
        @swap_hud_items_cache_key = nil
      end

      def activate
        MH::Superimp.active_tool = self
        @ip.clear
        remember_product_context_before_clear
        # Bat dau luot dat moi: bo chon de go do day + Enter di vao luong luu cho.
        Sketchup.active_model.selection.clear rescue nil
        load_current_material_profile
        Sketchup.active_model.active_view.invalidate
        update_status
      end

      def deactivate(view)
        MH::Superimp.active_tool = nil if MH::Superimp.active_tool == self
        UI.stop_timer(@swap_timer) if @swap_timer
        @swap_timer = nil
        UI.stop_timer(@swap_msg_timer) if @swap_msg_timer
        @swap_msg_timer = nil
        UI.stop_timer(@material_profile_msg_timer) if @material_profile_msg_timer
        @material_profile_msg_timer = nil
        view.invalidate
      end

      def set_import_path(new_path)
        @import_path = new_path
        
        # Chuẩn hóa đường dẫn để tìm kiếm chính xác hơn
        norm_path = @import_path.tr('\\', '/').downcase
        item = MH::Superimp.import_list.find { |it| it[:path].tr('\\', '/').downcase == norm_path }
        
        @group = item ? item[:group] : nil
        name = item ? item[:name] : File.basename(new_path, '.skp')
        # Chon DC moi tu thu vien = bat dau luot dat moi: bo chon DC cu de
        # go do day + Enter di vao luong LUU CHO (ap cho DC sap import),
        # khong ap nham vao DC import lan truoc con dang duoc chon.
        remember_product_context_before_clear
        Sketchup.active_model.selection.clear rescue nil
        @last_imported_dc = nil
        invalidate_registry_context_cache
        @swap_last_msg = "✓ [Shortcut] → #{name}"
        Sketchup.status_text = "Đã swap sang: #{name}"
        
        UI.stop_timer(@swap_msg_timer) if @swap_msg_timer
        @swap_msg_timer = UI.start_timer(3.0, false) do
          @swap_msg_timer = nil
          @swap_last_msg = nil
          Sketchup.active_model.active_view.invalidate if Sketchup.active_model && Sketchup.active_model.active_view
        end
        
        update_status
        Sketchup.active_model.active_view.invalidate if Sketchup.active_model && Sketchup.active_model.active_view
      end

      def remember_product_context_before_clear
        return unless defined?(MH::ProductContext)

        MH::ProductContext.refresh_from_selection(Sketchup.active_model, allow_slow_scan: true)
      rescue => e
        puts "[MH::Superimp] remember product context error: #{e.class}: #{e.message}"
      end

      def invalidate_registry_context_cache
        @registry_context_cache = nil
        @registry_context_cache_key = nil
        @registry_context_cache_time = 0.0
        @material_rows_cache = nil
        @material_rows_cache_key = nil
        @material_rows_cache_time = 0.0
      end

      def refresh_material_runtime
        @material_profile = nil
        @material_profile_msg = nil
        @material_profile_manual = false
        invalidate_registry_context_cache
        load_current_material_profile
        Sketchup.active_model.active_view.invalidate if Sketchup.active_model
        true
      rescue => e
        puts "[MH::Superimp] refresh material runtime error: #{e.class}: #{e.message}"
        false
      end

      def registry_context(allow_slow_scan: false)
        now = Time.now.to_f
        key = [
          @import_path.to_s,
          @group.to_s,
          @material_source_manual ? 'manual' : 'auto',
          allow_slow_scan ? 'slow' : 'fast'
        ].join("\u0001")
        if @registry_context_cache &&
           @registry_context_cache_key == key &&
           now - @registry_context_cache_time < REGISTRY_CONTEXT_CACHE_TTL
          return @registry_context_cache.dup
        end

        item = MH::Superimp.item_for_path(@import_path)
        context = {
          source: 'MH_Superimp',
          import_path: @import_path,
          import_name: item ? item[:name] : File.basename(@import_path.to_s, '.skp'),
          superimp_group: @group,
          product_code: current_registry_product_code(allow_slow_scan: allow_slow_scan),
          material_source: @material_source_manual ? 'manual' : 'auto'
        }
        @registry_context_cache = context.dup
        @registry_context_cache_key = key
        @registry_context_cache_time = now
        context
      end

      def current_registry_product_code(allow_slow_scan: false)
        if defined?(MH::ProductContext)
          code = MH::ProductContext.current_or_last_code(Sketchup.active_model, allow_slow_scan: allow_slow_scan)
          return code unless code.to_s.empty?
        end

        code = product_code_from_profile(@material_profile)
        return code unless code.to_s.empty?

        code = product_code_from_instance(@last_imported_dc)
        return code unless code.to_s.empty?

        return '' unless allow_slow_scan
        return '' unless defined?(MH::RegistryApp::Connector)

        connector = MH::RegistryApp::Connector.get('thongke') rescue nil
        return '' unless connector && connector.respond_to?(:selected_product_codes)

        Array(connector.selected_product_codes(false)).first.to_s
      rescue => e
        puts "[MH::Superimp] registry product error: #{e.class}: #{e.message}"
        ''
      end

      def product_code_from_profile(profile)
        return '' unless profile.is_a?(Hash)

        (profile[:product_code] || profile['product_code']).to_s.strip
      rescue
        ''
      end

      def product_code_from_instance(instance)
        return '' unless instance && instance.valid?

        dict = instance.attribute_dictionary('MH_Registry', false)
        code = dict['dc_product_code'].to_s.strip if dict
        return code unless code.to_s.empty?

        if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:code_from_entity)
          code = MH::ProductContext.code_from_entity(instance).to_s.strip
        end
        code.to_s
      rescue
        ''
      end

      def cycle_material_profile(view, mode = :material_row)
        result = nil
        invalidate_registry_context_cache
        MH::Superimp.ensure_registry_runtime
        if defined?(MH::RegistryApp::Connector)
          connector = MH::RegistryApp::Connector.get('dc_import_pipeline') rescue nil
          if connector
            result =
              if mode == :option_in_row && connector.respond_to?(:cycle_thickness_option_in_row)
                connector.cycle_thickness_option_in_row(registry_context(allow_slow_scan: true))
              elsif connector.respond_to?(:cycle_thickness_material_row)
                connector.cycle_thickness_material_row(registry_context(allow_slow_scan: true))
              elsif connector.respond_to?(:cycle_material_profile)
                connector.cycle_material_profile(registry_context(allow_slow_scan: true))
              end
          end
        end

        if profile_result_ok?(result)
          @material_profile = result
          @material_profile_manual = true
          label = result[:label] || result['label'] || result[:profile_name] || result['profile_name'] || result[:profile_id] || result['profile_id']
          invalidate_registry_context_cache
          applied = apply_current_material_profile_to_selected_dcs(view, result)
          @material_profile_msg = applied > 0 ? "VL: #{label} -> ap vao #{applied} DC" : "VL: #{label}"
        elsif result.is_a?(Hash)
          @material_profile_msg = "VL: #{profile_result_error(result)}"
        else
          @material_profile_msg = 'VL: Registry pipeline chua san sang'
        end

        Sketchup.status_text = @material_profile_msg
        UI.stop_timer(@material_profile_msg_timer) if @material_profile_msg_timer
        @material_profile_msg_timer = UI.start_timer(3.0, false) do
          @material_profile_msg_timer = nil
          @material_profile_msg = nil
          view.invalidate if Sketchup.active_model && Sketchup.active_model.active_view
        end
        view.invalidate
      rescue => e
        @material_profile_msg = "VL loi: #{e.message}"
        Sketchup.status_text = @material_profile_msg
        view.invalidate
      end

      def apply_current_material_profile_to_selected_dcs(view, profile)
        return 0 unless profile.is_a?(Hash)
        return 0 unless defined?(MH::RegistryApp::Connector)

        connector = MH::RegistryApp::Connector.get('dc_import_pipeline') rescue nil
        return 0 unless connector && connector.respond_to?(:apply_profile)

        targets = Sketchup.active_model.selection.to_a.grep(Sketchup::ComponentInstance).select(&:valid?)
        return 0 if targets.empty?

        context = registry_context(allow_slow_scan: true)
        applied = 0
        targets.each do |inst|
          next unless inst && inst.valid?

          row = stringify_profile_hash(profile)
          if connector.respond_to?(:normalize_profile)
            row = connector.normalize_profile(row)
          end
          row['_binding'] = connector.binding_for(context, inst) if connector.respond_to?(:binding_for)
          inst.set_attribute('MH_Registry', 'dc_material_profile_id', row['profile_id'].to_s) unless row['profile_id'].to_s.empty?
          inst.set_attribute('MH_Registry', 'dc_material_profile_name', (row['profile_name'] || row['label']).to_s)
          inst.set_attribute('MH_Registry', 'dc_material_code', row['material_code'].to_s) unless row['material_code'].to_s.empty?
          connector.apply_profile(inst, row)
          applied += 1
        end
        applied
      rescue => e
        puts "[MH::Superimp] apply selected profile error: #{e.class}: #{e.message}"
        0
      end

      def stringify_profile_hash(profile)
        profile.each_with_object({}) { |(key, value), memo| memo[key.to_s] = value }
      rescue
        {}
      end

      def profile_result_ok?(result)
        return false unless result.is_a?(Hash)

        ok = result.key?(:ok) ? result[:ok] : result['ok']
        ok != false
      rescue
        false
      end

      def profile_result_error(result)
        message = result[:error] || result['error'] || result[:message] || result['message']
        message = 'khong co du lieu vat lieu cho SP hien tai' if message.to_s.strip.empty?
        message.to_s
      rescue
        'khong co du lieu vat lieu cho SP hien tai'
      end

      def load_current_material_profile
        MH::Superimp.ensure_registry_runtime
        return unless defined?(MH::RegistryApp::Connector)

        connector = MH::RegistryApp::Connector.get('dc_import_pipeline') rescue nil
        return unless connector && connector.respond_to?(:selected_profile)

        result = connector.selected_profile(registry_context(allow_slow_scan: true))
        @material_profile = result if profile_result_ok?(result)
        @material_profile_manual = false
        invalidate_registry_context_cache
      rescue => e
        puts "[MH::Superimp] load material profile error: #{e.class}: #{e.message}"
      end

      def after_import_dc(instance)
        context = registry_context(allow_slow_scan: true)
        # HUD dang hien profile nao thi import dung profile do. Truoc day chi
        # truyen khi @material_profile_manual=true; profile auto da cycle Alt
        # co the bi hoi lai pipeline va roi ve option dau (17.6/11).
        context[:material_profile] = @material_profile if @material_profile
        MH::Superimp.notify_imported_dc(instance, context)
        @last_imported_dc = instance if instance && instance.valid?
        remember_imported_product_context(instance)
      end

      def remember_imported_product_context(instance)
        return unless defined?(MH::ProductContext)

        code = product_code_from_instance(instance)
        MH::ProductContext.remember_code(code, Sketchup.active_model) unless code.to_s.empty?
      rescue => e
        puts "[MH::Superimp] remember imported product error: #{e.class}: #{e.message}"
      end

      def resolve_import_path_for_depth(depth_length, view = nil)
        result = MH::Superimp.resolve_depth_based_import(@import_path, depth_length)
        return @import_path unless result.is_a?(Hash)

        if result[:path] && result[:path] != @import_path
          @import_path = result[:path]
          @group = result[:item] ? result[:item][:group] : @group
          invalidate_registry_context_cache
        end

        if result[:size_mm]
          target = result[:target_mm] ? result[:target_mm].round(1) : '?'
          @swap_last_msg = "Ray: #{target}mm -> #{result[:size_mm].round}mm"
          Sketchup.status_text = @swap_last_msg
          UI.stop_timer(@swap_msg_timer) if @swap_msg_timer
          @swap_msg_timer = UI.start_timer(3.0, false) do
            @swap_msg_timer = nil
            @swap_last_msg = nil
            view.invalidate if view
          end
          view.invalidate if view
        end

        @import_path
      rescue => e
        puts "[MH::Superimp] resolve drawer slide import error: #{e.class}: #{e.message}"
        @import_path
      end

      def update_status
        lock_text = case @face_lock
                    when :horizontal then " [←→]"
                    when :vertical then " [↑↓]"
                    else ""
                    end
        material_text = @material_profile ? " | Tab: doi VL" : ""
        
        case @mode
        when :hovering
          if @hover_edge
            Sketchup.status_text = "Edge: #{@hover_length.to_mm.round(1)}mm#{lock_text}#{material_text} | Click 1: chọn cạnh"
          elsif @box_corners
            if @missing_axis
              Sketchup.status_text = "Box 3D (#{@missing_axis}: 100mm)#{lock_text}#{material_text} | Click 1: khóa mặt và push | Nhập xx"
            else
              Sketchup.status_text = "Box 3D#{lock_text}#{material_text} | Click import"
            end
          else
            Sketchup.status_text = "Di chuột vào cạnh/mặt#{lock_text}#{material_text}"
          end
        when :edge_selected
          locked_text = @distance_locked ? " [KHÓA]" : ""
          Sketchup.status_text = "D: #{@distance.to_mm.round(1)}mm#{locked_text}#{lock_text}#{material_text} | Click 2: xác nhận plane | ESC"
        when :plane_confirmed
          locked_text = @depth_locked ? " [KHÓA]" : ""
          Sketchup.status_text = "Depth: #{@box_depth.to_mm.round(1)}mm#{locked_text}#{material_text} | Nhập xx để khóa | Click 3: trong=2D, ngoài=3D | ESC"
        when :face_push
          size = @live_box_size_override ? @live_box_size_override.to_mm.round(1) : "..."
          Sketchup.status_text = "Push: #{size}mm#{lock_text}#{material_text} | Click 2: xác nhận import | Nhập xx | ESC"
        end
      end

      # Point in polygon (ray casting)
      def point_in_polygon?(px, py, polygon)
        n = polygon.length
        inside = false
        j = n - 1
        n.times do |i|
          xi, yi = polygon[i]
          xj, yj = polygon[j]
          if ((yi > py) != (yj > py)) && (px < (xj - xi) * (py - yi) / (yj - yi + 0.0001) + xi)
            inside = !inside
          end
          j = i
        end
        inside
      end

      # Distance from point to line segment
      def point_to_segment_distance(px, py, x1, y1, x2, y2)
        dx, dy = x2 - x1, y2 - y1
        return Math.sqrt((px - x1)**2 + (py - y1)**2) if dx == 0 && dy == 0
        t = [[(((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)), 0].max, 1].min
        Math.sqrt((px - (x1 + t * dx))**2 + (py - (y1 + t * dy))**2)
      end

      def mouse_inside_plane?(view, x, y)
        return false unless @plane_corners && @plane_corners.length == 4
        screen_pts = @plane_corners.map { |pt| view.screen_coords(pt) }
        polygon_2d = screen_pts.map { |p| [p.x, p.y] }
        return true if point_in_polygon?(x, y, polygon_2d)
        # Check edge proximity (15px)
        4.times do |i|
          p1, p2 = polygon_2d[i], polygon_2d[(i + 1) % 4]
          return true if point_to_segment_distance(x, y, p1[0], p1[1], p2[0], p2[1]) < 15
        end
        false
      end

      def face_matches_lock?(face, path)
        return true if @face_lock == :none || !face || !face.valid?
        t = IDENTITY
        path.reverse_each { |e| t = e.transformation * t if e.respond_to?(:transformation) }
        normal = face.normal.transform(t)
        return true if normal.length == 0
        normal.normalize!
        case @face_lock
        when :horizontal then normal.parallel?(Z_AXIS) || normal.parallel?(Z_AXIS.reverse)
        when :vertical then !normal.parallel?(Z_AXIS) && !normal.parallel?(Z_AXIS.reverse)
        else true
        end
      end

      def pick_face(view, x, y)
        face, _transform, path = MH::Geo::Box.pick_face(view, x, y) do |candidate, candidate_path, _|
          face_matches_lock?(candidate, candidate_path)
        end
        [face, path]
      end

      def pick_edge(view, x, y)
        edge, transform = MH::Geo::Box.pick_edge(view, x, y)
        [edge, transform]
      end

      def pick_object(view, x, y)
        ph = view.pick_helper
        ph.do_pick(x, y, 10)
        (0...ph.count).each do |i|
          path = ph.path_at(i)
          obj = path.find { |e| e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group) }
          if obj && obj.valid?
            t = IDENTITY
            path.each { |el| break if el == obj; t = t * el.transformation if el.respond_to?(:transformation) }
            return [obj, t]
          end
        end
        [nil, IDENTITY]
      end

      def project_point_to_line(pt, line_pt, line_vec)
        return line_pt unless line_vec.length > 0
        v = line_pt.vector_to(pt)
        proj_len = v % line_vec.normalize
        line_pt.offset(line_vec.normalize, proj_len)
      end

      def onMouseMove(flags, x, y, view)
        @last_x = x
        @last_y = y

        case @mode
        when :hovering
          edge, transform = pick_edge(view, x, y)
          if edge && edge.valid?
            @box_corners = nil
            @picked_face = nil
            if edge != @hover_edge
              @hover_edge = edge
              @hover_transform = transform
              @hover_edges = MH::Superimp.find_connected_collinear_edges(edge)
              @hover_length = MH::Superimp.calculate_edges_length(@hover_edges, transform)
              @hover_axis = MH::Superimp.get_edge_axis(edge, transform)
            end
          else
            @hover_edge = nil
            @hover_edges = []
            face, path = pick_face(view, x, y)
            if face && face.valid?
              if face != @picked_face
                @live_box_size_override = nil # Reset when changing faces
              end
              @picked_face = face
              @picked_path = path
              # Use InputPoint to get actual 3D cursor position for missing dimension
              @ip.pick(view, x, y)
              compute_box_corners(view)
            else
              @picked_face = nil
              @box_corners = nil
              @live_box_size_override = nil
            end
          end

        when :edge_selected
          @ip.pick(view, x, y)
          if @ip.valid? && @sel_line
            @snap_pt = @ip.position
            line_pt, line_vec = @sel_line
            proj_pt = project_point_to_line(@snap_pt, line_pt, line_vec)
            @distance = proj_pt.distance(@snap_pt) unless @distance_locked
            
            if @distance > 0.001.mm
              dist_vec = proj_pt.vector_to(@snap_pt)
              if dist_vec.length > 0.001.mm
                dist_vec.normalize!
                if dist_vec.parallel?(X_AXIS) || dist_vec.parallel?(X_AXIS.reverse)
                  @distance_axis = :X
                elsif dist_vec.parallel?(Y_AXIS) || dist_vec.parallel?(Y_AXIS.reverse)
                  @distance_axis = :Y
                elsif dist_vec.parallel?(Z_AXIS) || dist_vec.parallel?(Z_AXIS.reverse)
                  @distance_axis = :Z
                else
                  @distance_axis = @sel_axis == :X ? :Y : (@sel_axis == :Y ? :X : :X)
                end
              end
            end
            compute_plane_corners(proj_pt)
          end

        when :plane_confirmed
          if @plane_corners && @plane_corners.length == 4
            ray = view.pickray(x, y)
            if ray
              v1 = @plane_corners[0].vector_to(@plane_corners[1])
              v2 = @plane_corners[0].vector_to(@plane_corners[3])
              @plane_normal = v1 * v2
              @plane_normal.normalize! if @plane_normal.length > 0
              
              if !mouse_inside_plane?(view, x, y) && !@depth_locked
                @ip.pick(view, x, y)
                if @ip.valid? && @plane_normal.length > 0
                  pt = @ip.position
                  dist_vec = @plane_corners[0].vector_to(pt)
                  signed_dist = dist_vec % @plane_normal
                  @box_depth = signed_dist.abs
                  @push_direction = signed_dist >= 0 ? 1 : -1
                end
              else
                @box_depth = 0
              end
              compute_final_box
            end
          end
        
        when :face_push
          # Enable InputPoint for snapping
          @ip.pick(view, x, y)
          
          # Calculate push distance from InputPoint 3D position to face
          if @push_base_point && @missing_axis_direction && @ip.valid?
            cursor_pt = @ip.position
            # Calculate distance from face origin to cursor along missing axis direction
            dist_vec = @push_base_point.vector_to(cursor_pt)
            if dist_vec.length > 0.001.mm
              # Project distance onto missing axis direction
              projected_dist = dist_vec % @missing_axis_direction
              @live_box_size_override = [projected_dist.abs, 10.mm].max
            end
            
            # Recalculate box with new push distance
            compute_box_corners_for_push(view)
          end
        end
        
        update_status
        view.invalidate
      end

      def compute_box_corners(view)
        @box_corners = nil
        @missing_axis = nil
        @missing_axis_direction = nil
        @face_origin = nil
        @face_normal = nil
        result = MH::Geo::Box.face_push_box(
          face: @picked_face,
          path: @picked_path,
          view: view,
          x: @last_x,
          y: @last_y,
          live_size: @live_box_size_override,
          locked_base_point: @locked_base_point,
          right_button_held: @rbutton_held
        )
        return unless result

        @box_corners = result[:corners]
        @missing_axis = result[:missing_axis]
        @missing_axis_direction = result[:missing_axis_direction]
        @face_origin = result[:origin]
        @face_normal = result[:normal]
        @live_box_size_override = result[:live_size_override]
      end

      def compute_box_corners_for_push(view)
        # Use saved axis_info and update only the missing axis
        return unless @push_axis_info && @push_base_point && @missing_axis && @live_box_size_override
        
        axis_info = @push_axis_info.dup
        axis_info[@missing_axis] = @live_box_size_override
        
        origin = @push_base_point
        @box_corners = MH::Geo::Box.corners_from_axis_info(origin, axis_info)
      end

      def save_axis_info_for_push(view)
        # Recalculate and save axis_info for face_push mode
        return unless @picked_face && @picked_face.valid? && @picked_path.is_a?(Array) && @face_origin

        @push_axis_info = MH::Geo::Box.axis_info_from_face(@picked_face, @picked_path, @face_origin, view.model)
      end

      def compute_plane_corners(proj_pt)
        return unless @edge_start_pt && @edge_end_pt && @distance > 0.001.mm
        
        @plane_corners = MH::Geo::Box.plane_corners(
          edge_start: @edge_start_pt,
          edge_end: @edge_end_pt,
          distance: @distance,
          projected_point: proj_pt,
          snap_point: @snap_pt,
          selected_axis: @sel_axis,
          face_lock: @face_lock
        )

        unless @snap_pt || !@plane_corners
          @distance_axis = case @sel_axis
                           when :X then :Y
                           when :Y then :X
                           when :Z then :X
                           else :Y
                           end
          @snap_pt = @plane_corners[3]
        end
      end

      def compute_final_box
        return unless @plane_corners && @plane_corners.length == 4 && @box_depth > 0.001.mm && @plane_normal && @plane_normal.length > 0
        
        offset = @plane_normal.clone
        offset.length = @box_depth
        offset.reverse! if @push_direction < 0
        
        top_corners = @plane_corners.map { |pt| pt.offset(offset) }
        @final_box = @plane_corners + top_corners
      end

      def draw(view)
        @ip.draw(view) if (@mode == :edge_selected || @mode == :plane_confirmed || @mode == :face_push) && @ip.valid?
        
        # Hover edges
        if @mode == :hovering && @hover_edges.any?
          view.line_width = LINE_WIDTH
          view.drawing_color = EDGE_COLOR
          @hover_edges.each do |e|
            next unless e.valid?
            view.draw(GL_LINES, [e.start.position.transform(@hover_transform), e.end.position.transform(@hover_transform)])
          end
        end
        
        # Box corners for face mode
        if @mode == :hovering && @box_corners && @box_corners.size == 8
          xs, ys, zs = @box_corners.map(&:x), @box_corners.map(&:y), @box_corners.map(&:z)
          xmin, xmax = xs.min, xs.max
          ymin, ymax = ys.min + @offset_y, ys.max
          zmin = zs.min + @offset_z
          original_z = (zs.max - zs.min).abs
          z_height = @set_z ? (@offset_z_after_set ? @set_z - @offset_z : @set_z) : original_z - @offset_z
          zmax = zmin + z_height
          
          pts = [
            Geom::Point3d.new(xmin, ymin, zmin), Geom::Point3d.new(xmax, ymin, zmin),
            Geom::Point3d.new(xmax, ymax, zmin), Geom::Point3d.new(xmin, ymax, zmin),
            Geom::Point3d.new(xmin, ymin, zmax), Geom::Point3d.new(xmax, ymin, zmax),
            Geom::Point3d.new(xmax, ymax, zmax), Geom::Point3d.new(xmin, ymax, zmax)
          ]
          
          faces = [[0,1,2,3], [4,5,6,7], [0,1,5,4], [1,2,6,5], [2,3,7,6], [3,0,4,7]]
          if @missing_axis
            # Missing dimension - red color
            view.drawing_color = Sketchup::Color.new(255, 0, 0, 80)
            faces.each { |f| view.draw(GL_POLYGON, f.map { |i| pts[i] }) }
            view.line_width = 2
            view.drawing_color = 'red'
          else
            # All dimensions available - yellow color
            view.drawing_color = BOX_COLOR
            faces.each { |f| view.draw(GL_POLYGON, f.map { |i| pts[i] }) }
            view.line_width = 2
            view.drawing_color = 'black'
          end
          faces.each { |f| view.draw(GL_LINE_LOOP, f.map { |i| pts[i] }) }
        end
        
        # Face push mode box
        if @mode == :face_push && @box_corners && @box_corners.size == 8
          faces = [[0,1,2,3], [4,5,6,7], [0,1,5,4], [1,2,6,5], [2,3,7,6], [3,0,4,7]]
          view.drawing_color = Sketchup::Color.new(255, 0, 0, 80)  # Semi-transparent red
          faces.each { |f| view.draw(GL_POLYGON, f.map { |i| @box_corners[i] }) }
          view.line_width = 2
          view.drawing_color = 'red'
          faces.each { |f| view.draw(GL_LINE_LOOP, f.map { |i| @box_corners[i] }) }
        end
        
        # Selected edges
        if (@mode == :edge_selected || @mode == :plane_confirmed) && @sel_edges.any?
          view.line_width = LINE_WIDTH
          view.drawing_color = SELECTED_COLOR
          @sel_edges.each do |e|
            next unless e.valid?
            view.draw(GL_LINES, [e.start.position.transform(@sel_transform), e.end.position.transform(@sel_transform)])
          end
        end
        
        # Plane preview
        if (@mode == :edge_selected || @mode == :plane_confirmed) && @plane_corners && @plane_corners.length == 4
          view.drawing_color = Sketchup::Color.new(0, 255, 255, 80)  # Semi-transparent cyan
          view.draw(GL_QUADS, @plane_corners)
          view.line_width = 2
          view.drawing_color = 'cyan'
          view.draw(GL_LINE_LOOP, @plane_corners)
        end
        
        # Final box (3D extrusion)
        if @mode == :plane_confirmed && @final_box && @final_box.size == 8
          faces = [[0,1,2,3], [4,5,6,7], [0,1,5,4], [1,2,6,5], [2,3,7,6], [3,0,4,7]]
          view.drawing_color = Sketchup::Color.new(0, 255, 255, 80)  # Semi-transparent cyan
          faces.each { |f| view.draw(GL_POLYGON, f.map { |i| @final_box[i] }) }
          view.line_width = 2
          view.drawing_color = 'cyan'
          faces.each { |f| view.draw(GL_LINE_LOOP, f.map { |i| @final_box[i] }) }
        end
        
        # Distance line
        if @mode == :edge_selected && @snap_pt && @sel_line
          proj_pt = project_point_to_line(@snap_pt, @sel_line[0], @sel_line[1])
          view.line_width = 2
          view.line_stipple = '_'
          view.drawing_color = 'magenta'
          view.draw(GL_LINES, [proj_pt, @snap_pt])
          view.line_stipple = ''
        end

        # ---- Swap HUD (góc trên trái) ----
        draw_swap_hud(view)
        draw_material_profile_hud(view)
        draw_material_source_toggle(view)
        draw_material_reload_button(view)
      end

      # Cong tac gat (toggle switch) nguon ma VL - bam de doi Auto <-> Thu cong.
      def draw_material_source_toggle(view)
        manual = @material_source_manual
        tw = 46          # track width
        th = 22          # track height
        margin = 14
        label = 'Manual'
        label_gap = 8
        label_w = 48
        x = view.vpwidth - label_w - label_gap - tw - margin           # label + track block left
        y = 14
        track_x = x + label_w + label_gap
        r = th / 2.0
        cy = y + r
        left_cx = track_x + r
        right_cx = track_x + tw - r

        # vung bam = ca track + label; toa do co dinh nen text khong nhay khi gat.
        @mode_button_rect = [x, y, tw + label_gap + label_w, th]

        # track (pill)
        track = capsule_points(track_x, y, tw, th)
        view.drawing_color = manual ? Sketchup::Color.new(45, 165, 95, 240) : Sketchup::Color.new(110, 110, 115, 225)
        view.draw2d(GL_POLYGON, track)
        view.line_width = 1
        view.drawing_color = Sketchup::Color.new(20, 20, 20)
        view.draw2d(GL_LINE_LOOP, track)

        # num truot (knob)
        knob = circle_points(manual ? right_cx : left_cx, cy, r - 3)
        view.drawing_color = Sketchup::Color.new(255, 255, 255, 255)
        view.draw2d(GL_POLYGON, knob)

        # nhan ben trai, luon chi hien "Manual"
        hud_draw_text(view, x, y + 6, label, size: 8, bold: true, color: HUD_TEXT_COLOR)
      rescue
        nil
      end

      def draw_material_reload_button(view)
        w = 28
        h = 22
        margin = 8
        mode_x = @mode_button_rect ? @mode_button_rect[0] : view.vpwidth - 116
        x = mode_x - w - margin
        y = 14
        @reload_button_rect = [x, y, w, h]

        shape = capsule_points(x, y, w, h)
        view.drawing_color = HUD_BUTTON_BG
        view.draw2d(GL_POLYGON, shape)
        view.line_width = 1
        view.drawing_color = HUD_BUTTON_BORDER
        view.draw2d(GL_LINE_LOOP, shape)
        hud_draw_text(view, x + 9, y + 5, '↻', size: 8, bold: true, color: HUD_TEXT_COLOR)
      rescue
        @reload_button_rect = nil
      end

      def capsule_points(x, y, w, h, seg = 8)
        r = h / 2.0
        cy = y + r
        right_cx = x + w - r
        left_cx = x + r
        pts = []
        (0..seg).each { |i| a = -Math::PI / 2 + Math::PI * i / seg; pts << Geom::Point3d.new(right_cx + r * Math.cos(a), cy + r * Math.sin(a), 0) }
        (0..seg).each { |i| a = Math::PI / 2 + Math::PI * i / seg; pts << Geom::Point3d.new(left_cx + r * Math.cos(a), cy + r * Math.sin(a), 0) }
        pts
      end

      def circle_points(cx, cy, r, seg = 18)
        (0...seg).map { |i| a = 2 * Math::PI * i / seg; Geom::Point3d.new(cx + r * Math.cos(a), cy + r * Math.sin(a), 0) }
      end

      def draw_swap_hud(view)
        x0 = 14
        y0 = 14
        pad = 6
        panel_w = 330
        y = y0 + pad
        # Tên component hiện tại
        current_name = File.basename(@import_path, '.skp') rescue 'N/A'
        swap_items = swap_hud_items
        panel_h = 12 + 24
        panel_h += 19 unless @thickness_input_buffer.to_s.empty?
        panel_h += 19 unless @swap_buffer.empty?
        panel_h += 19 if @swap_last_msg
        panel_h += 8 + 17 + swap_items.length * 16 unless swap_items.empty?
        hud_draw_panel_background(view, x0, y0, panel_w, panel_h)

        hud_draw_text(view, x0 + pad, y, "▶ #{hud_truncate_line_text(current_name, panel_w - pad * 2 - 12, 15)}", size: 15, bold: true, color: HUD_TEXT_COLOR)
        y += 24

        # Hiện buffer nếu đang nhập
        unless @thickness_input_buffer.to_s.empty?
          hud_draw_text(view, x0 + pad, y, "Dày: #{@thickness_input_buffer}_  (Enter)", size: 11, bold: true, color: HUD_STATUS_COLOR)
          y += 19
        end

        unless @swap_buffer.empty?
          hud_draw_text(view, x0 + pad, y, "Swap: #{@swap_buffer}_ ...", size: 11, bold: true, color: HUD_STATUS_COLOR)
          y += 19
        end

        # Hiện kết quả swap
        if @swap_last_msg
          hud_draw_text(view, x0 + pad, y, hud_truncate_line_text(@swap_last_msg, panel_w - pad * 2, 11), size: 11, bold: true, color: HUD_STATUS_COLOR)
          y += 19
        end

        # Danh sách swap keys (tối đa 10 dòng)
        unless swap_items.empty?
          y += 8
          hud_draw_group_header(view, x0 + pad, y, "LIST DC · Nhóm #{@group}", panel_w - pad * 2)
          y += 17
          swap_items.each do |k, v|
            label = v[:name]
            text = hud_truncate_line_text("#{k} → #{label}", panel_w - pad * 2, 9)
            hud_draw_text(view, x0 + pad, y, text, size: 9, color: HUD_TEXT_COLOR)
            y += 16
          end
        end
      end

      def swap_hud_items
        key = [@group.to_s, @swap_map[@group].hash].join("\u0001") rescue @group.to_s
        if @swap_hud_items_cache && @swap_hud_items_cache_key == key
          return @swap_hud_items_cache
        end

        items = @group && @swap_map[@group] ? @swap_map[@group].sort_by { |k, _| k.to_i }.first(15) : []
        @swap_hud_items_cache = items
        @swap_hud_items_cache_key = key
        items
      rescue
        []
      end

      def material_profile_tokens
        src = @material_profile_msg ? @material_profile : @material_profile
        return [] unless src

        base_tokens = src[:hud_tokens] || src['hud_tokens']
        base_tokens = base_tokens.map(&:to_s).reject(&:empty?) if base_tokens.is_a?(Array)
        base_tokens ||= []

        context = registry_context
        product = context[:product_code].to_s.strip
        material = src[:material_code] || src['material_code']
        material = hud_material_code_for_product(product) if material.to_s.strip.empty?
        material = material.to_s.strip.split(/\s*&\s*/).first.to_s
        material_base = material.split('.').first.to_s.upcase
        base_tokens = base_tokens.reject { |token| token.to_s.strip.upcase == material_base } unless material_base.empty?
        sub_text = hud_material_sub_text(product, material, context)

        tokens = []
        tokens << product unless product.empty?
        tokens << sub_text unless sub_text.empty?
        tokens << material unless material.empty?
        tokens.concat(base_tokens)
        return tokens.uniq unless tokens.empty?

        label = src[:label] || src['label'] ||
                src[:profile_name] || src['profile_name'] ||
                src[:profile_id] || src['profile_id']
        label.to_s.split(/\s+/).first(3)
      end

      def material_profile_rows
        context = registry_context
        product = context[:product_code].to_s.strip
        manual = @material_source_manual
        return [] if !manual && product.empty?
        return [] unless defined?(MH::RegistryApp::Connector)

        now = Time.now.to_f
        cache_key = [
          product,
          manual ? 'manual' : 'auto',
          @import_path.to_s,
          @group.to_s,
          material_profile_cache_key(@material_profile),
          current_hud_thickness_tokens.join('|')
        ].join("\u0001")
        if @material_rows_cache &&
           @material_rows_cache_key == cache_key &&
           now - @material_rows_cache_time < MATERIAL_ROWS_CACHE_TTL
          return @material_rows_cache.map(&:dup)
        end

        connector = MH::RegistryApp::Connector.get('dc_import_pipeline') rescue nil
        return [] unless connector && connector.respond_to?(:hud_material_rows_for_context)

        fallback_thickness = current_hud_thickness_tokens
        rows = Array(connector.hud_material_rows_for_context(context)).map do |row|
          code = (row['material_code'] || row[:material_code]).to_s.strip
          sub = (row['sub_text'] || row[:sub_text]).to_s.strip
          thick = Array(row['thickness_tokens'] || row[:thickness_tokens]).map(&:to_s)
          selected_option_index = (row['selected_option_index'] || row[:selected_option_index]).to_i
          selected_row = row['selected'] || row[:selected]
          thick = fallback_thickness if thick.all? { |value| value.to_s.empty? }
          [product, sub, code] + thick + [{ selected_option_index: selected_option_index, selected: selected_row ? true : false }]
        end
        if quick_thickness_profile?
          quick_row = quick_material_profile_row(product)
          quick_code = quick_row[2].to_s
          rows.reject! { |row| row[2].to_s == quick_code } unless quick_code.empty?
          rows.unshift(quick_row)
        end
        rows = rows.reject { |row| row.all? { |value| value.to_s.empty? } }
        @material_rows_cache = rows.map(&:dup)
        @material_rows_cache_key = cache_key
        @material_rows_cache_time = now
        rows
      rescue
        []
      end

      def material_profile_cache_key(profile)
        src = profile || {}
        [
          src[:profile_id] || src['profile_id'],
          src[:material_code] || src['material_code'],
          src[:panel_thickness_mm] || src['panel_thickness_mm'],
          src[:back_thickness_mm] || src['back_thickness_mm'],
          Array(src[:hud_tokens] || src['hud_tokens']).join('/')
        ].map { |value| value.to_s.strip }.join('|')
      rescue
        ''
      end

      def quick_thickness_profile?
        src = @material_profile || {}
        profile_id = (src[:profile_id] || src['profile_id']).to_s
        profile_id.start_with?('quick::')
      end

      def quick_material_profile_row(product)
        src = @material_profile || {}
        material = (src[:material_code] || src['material_code']).to_s.strip
        material = current_hud_material_code if material.empty?
        tokens = Array(src[:hud_tokens] || src['hud_tokens']).map(&:to_s)
        tokens = [format_hud_number(src[:panel_thickness_mm] || src['panel_thickness_mm'])] if tokens.empty?
        sub = hud_material_sub_text(product, material, registry_context)
        [product, sub, material] + tokens + [{ selected_option_index: 0, selected: true }]
      end

      def current_hud_material_code
        src = @material_profile_msg ? @material_profile : @material_profile
        material = src && (src[:material_code] || src['material_code'])
        product = registry_context[:product_code].to_s.strip
        material = hud_material_code_for_product(product) if material.to_s.strip.empty?
        material.to_s.strip.split(/\s*&\s*/).first.to_s
      rescue
        ''
      end

      def current_hud_thickness_tokens
        src = @material_profile_msg ? @material_profile : @material_profile
        tokens = src && (src[:hud_tokens] || src['hud_tokens'])
        Array(tokens).map(&:to_s)
      rescue
        []
      end

      def hud_material_code_for_product(product)
        return '' if product.to_s.strip.empty?
        return '' unless defined?(MH::RegistryApp::Connector)

        connector = MH::RegistryApp::Connector.get('dc_import_pipeline') rescue nil
        return '' unless connector && connector.respond_to?(:ordered_material_codes)

        Array(connector.ordered_material_codes(product)).first.to_s
      rescue
        ''
      end

      def hud_material_sub_text(product, material, context = nil)
        return '' if product.to_s.strip.empty? || material.to_s.strip.empty?
        return '' unless defined?(MH::RegistryApp::Connector)

        connector = MH::RegistryApp::Connector.get('dc_import_pipeline') rescue nil
        return '' unless connector && connector.respond_to?(:hud_detail_finish_for_context)

        result = connector.hud_detail_finish_for_context(context || registry_context, material)
        (result['text'] || result[:text]).to_s.strip
      rescue
        ''
      end

      def draw_material_profile_hud(view)
        rows = material_profile_rows
        rows = [material_profile_tokens] if rows.empty?
        return if rows.empty?

        view_w = view.vpwidth
        view_h = view.vpheight
        text_size = 8
        margin = 16
        gap = 14
        right_reserved = material_hud_right_reserved_width(view)
        usable_w = [[view_w - margin * 2 - right_reserved, 120].max, 1200].min
        fixed_sp_w = 30.0
        preferred_spec_w = 550.0
        fixed_material_w = 246.0
        fixed_option_w = 72.0
        option_count = hud_option_count(rows)
        content_w = [usable_w - gap * (2 + option_count), 80].max
        available_spec_w = content_w - fixed_sp_w - fixed_material_w - fixed_option_w * option_count
        small_w = [[available_spec_w, preferred_spec_w].min, 40].max
        columns = [fixed_sp_w, small_w, fixed_material_w] + ([fixed_option_w] * option_count)
        row_h = 15
        start_y = view_h - 64 - (rows.length - 1) * row_h
        start_x = margin
        selected_code = current_hud_material_code
        # Khi DA co dong duoc chon ro rang (meta[:selected]), CHI danh dau dong do.
        # Code-match (row_code == selected_code) chi la fallback khi khong dong nao
        # duoc chon — tranh gach chan/marker ca cac dong trung ma VL (vd dong 1 va
        # dong 2 cung mot ma nhung khac do day).
        any_selected = rows.any? { |t| hud_row_meta(t)[:selected] == true }

        rows.each_with_index do |tokens, row_index|
          meta = hud_row_meta(tokens)
          y = start_y + row_index * row_h
          x = start_x
          line_start_x = start_x
          line_end_x = start_x
          row_code = tokens[2].to_s.strip
          row_selected = meta[:selected] == true ||
                         (!any_selected && !selected_code.empty? && row_code.upcase == selected_code.upcase)
          (0...columns.length).each do |index|
            value = hud_row_value(tokens, index)
            width = columns[index]
            unless value.empty?
              text = hud_truncate_line_text(value, width, text_size)
              selected_cell = (index == 2 && row_selected) ||
                              (index >= 3 &&
                               row_selected &&
                               meta[:selected_option_index].to_i == index - 3)
              color = index == 1 || index >= 3 ? HUD_MUTED_COLOR : HUD_TEXT_COLOR
              if index == 2 || index >= 3
                hud_draw_choice_background(view, x - 5, y - 2, width - 4, row_h - 1, selected_cell)
                color = selected_cell ? HUD_CHOICE_SELECTED_TEXT : HUD_TEXT_COLOR
                hud_draw_text(view, x + 2, y, text, size: text_size, bold: selected_cell, color: color)
              else
                color = HUD_TEXT_COLOR if selected_cell
                hud_draw_text(view, x, y, text, size: text_size, bold: selected_cell, color: color)
              end
              line_end_x = x + width if index <= 2
            end
            x += width + gap
          end

          if row_selected
            y_line = y + text_size + 3
            view.line_width = 1
            view.drawing_color = HUD_TEXT_COLOR
            view.draw2d(GL_LINES, [[line_start_x, y_line], [line_end_x, y_line]])
          end
        end
      end

      def material_hud_right_reserved_width(view)
        return 0 unless defined?(::MH_Thongke)
        visible = ::MH_Thongke.respond_to?(:material_overlay_visible?) && ::MH_Thongke.material_overlay_visible?
        return 0 unless visible

        panel_w =
          if ::MH_Thongke.const_defined?(:HUD_PANEL_WIDTH)
            ::MH_Thongke::HUD_PANEL_WIDTH.to_i
          else
            460
          end
        reserve = panel_w + 32
        [reserve, (view.vpwidth * 0.55).to_i].min
      rescue
        0
      end

      def hud_draw_panel_background(view, x, y, w, h)
        pts = hud_rounded_rect_points(x, y, w, h, 7)
        view.drawing_color = HUD_LIST_BG
        view.draw2d(GL_POLYGON, pts)
        view.line_width = 1
        view.drawing_color = HUD_LIST_BORDER
        view.draw2d(GL_LINE_LOOP, pts)
      rescue
        nil
      end

      def hud_draw_choice_background(view, x, y, w, h, selected)
        bg = selected ? HUD_CHOICE_SELECTED_BG : HUD_CHOICE_BG
        border = selected ? HUD_CHOICE_SELECTED_BORDER : HUD_CHOICE_BORDER
        shape = hud_rect_points(x, y, [w, 18].max, h)
        view.drawing_color = bg
        view.draw2d(GL_QUADS, shape)
        view.line_width = selected ? 2 : 1
        view.drawing_color = border
        view.draw2d(GL_LINE_LOOP, shape)
      rescue
        nil
      end

      def hud_rect_points(x, y, w, h)
        [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]
      end

      def hud_rounded_rect_points(x, y, w, h, r, seg = 4)
        pts = []
        [[x + r, y + r, Math::PI, 1.5 * Math::PI],
         [x + w - r, y + r, 1.5 * Math::PI, 2.0 * Math::PI],
         [x + w - r, y + h - r, 0.0, 0.5 * Math::PI],
         [x + r, y + h - r, 0.5 * Math::PI, Math::PI]].each do |cx, cy, a0, a1|
          (0..seg).each do |i|
            a = a0 + (a1 - a0) * i / seg
            pts << [cx + r * Math.cos(a), cy + r * Math.sin(a)]
          end
        end
        pts
      end

      def hud_draw_text(view, x, y, text, size: 10, bold: false, color: HUD_TEXT_COLOR)
        return if text.to_s.empty?

        view.drawing_color = color
        view.draw_text([x, y, 0], text.to_s, size: size, bold: bold, color: color)
      end

      def hud_draw_group_header(view, x, y, label, width)
        hud_draw_text(view, x, y, label, size: 8, color: HUD_GROUP_COLOR)
        view.drawing_color = HUD_DIVIDER_COLOR
        view.line_width = 1
        view.draw2d(GL_LINES, [[x + 92, y + 6], [x + width, y + 6]])
      end

      def hud_option_count(rows)
        count = Array(rows).map do |row|
          values = Array(row)
          values = values[0...-1] if values.last.is_a?(Hash)
          [values.length - 3, 0].max
        end.max || 0
        [count, 2].max
      end

      def hud_row_meta(tokens)
        meta = Array(tokens).last
        return meta if meta.is_a?(Hash)

        {
          selected_option_index: tokens[5].to_i,
          selected: tokens[6] == true
        }
      rescue
        { selected_option_index: -1, selected: false }
      end

      def hud_row_value(tokens, index)
        values = Array(tokens)
        values = values[0...-1] if values.last.is_a?(Hash)
        value = values[index].to_s
        index >= 3 && value.empty? ? '--' : value
      end

      def hud_truncate_line_text(value, max_width, text_size)
        text = value.to_s.strip
        return text if text.empty?

        char_w = text_size.to_f * 0.82
        max_chars = (max_width.to_f / char_w).floor
        return text if max_chars <= 0 || text.length <= max_chars
        return text[0, max_chars] if max_chars <= 3

        "#{text[0, max_chars - 3]}..."
      end

      def onLButtonDown(flags, x, y, view)
        if @reload_button_rect
          bx, by, bw, bh = @reload_button_rect
          if x >= bx && x <= bx + bw && y >= by && y <= by + bh
            reload_material_hud_data(view)
            return
          end
        end

        # Bam nut gat nguon ma VL (Auto <-> Thu cong) - uu tien truoc workflow.
        if @mode_button_rect
          bx, by, bw, bh = @mode_button_rect
          if x >= bx && x <= bx + bw && y >= by && y <= by + bh
            @material_source_manual = !@material_source_manual
            MH::Superimp.save_material_source_manual(@material_source_manual)
            invalidate_registry_context_cache
            load_current_material_profile
            Sketchup.status_text = @material_source_manual ? 'Nguon VL: Thu cong (danh sach tay)' : 'Nguon VL: Auto (tra Excel)'
            view.invalidate
            return
          end
        end

        ctrl_held = (flags & COPY_MODIFIER_MASK) != 0
        shift_held = (flags & CONSTRAIN_MODIFIER_MASK) != 0

        # Dang go do day do ma click luon (quen Enter) -> tu chot thanh profile cho.
        commit_thickness_buffer_pending(view) if @thickness_input_buffer.to_s != ''

        if ctrl_held
          obj, transform = pick_object(view, x, y)
          replace_object(view, obj, transform) if obj && obj.valid?
          return
        end
        
        case @mode
        when :hovering
          if @hover_edge && @hover_edges.any? && @hover_length > 0
            @sel_edge = @hover_edge
            @sel_edges = @hover_edges.dup
            @sel_length = @hover_length
            @sel_axis = @hover_axis
            @sel_transform = @hover_transform
            @sel_line = MH::Superimp.get_edge_line(@sel_edge, @sel_transform)
            
            pts = MH::Superimp.get_edge_endpoints(@sel_edges, @sel_transform)
            if pts.any? && @sel_line
              line_pt, line_vec = @sel_line
              projections = pts.map { |p| line_pt.vector_to(p) % line_vec.normalize }
              @edge_start_pt = line_pt.offset(line_vec.normalize, projections.min)
              @edge_end_pt = line_pt.offset(line_vec.normalize, projections.max)
            end
            
            @mode = :edge_selected
            @hover_edge = nil
            @hover_edges = []
            @ip.clear
          elsif @box_corners && @box_corners.size == 8
            if @missing_axis && !@live_box_size_override
              # Click 1: Lock face and enter push mode
              @mode = :face_push
              @push_base_point = @face_origin
              # Save axis_info for push calculation - need to get it from compute_box_corners
              # We'll recalculate and save
              save_axis_info_for_push(view)
              @live_box_size_override = 100.mm  # Initial default
              update_status
              view.invalidate
            else
              import_to_box(view)
            end
          else
            import_direct(view)
          end
        
        when :face_push
          # Click 2: Confirm and import
          if @box_corners && @box_corners.size == 8 && @live_box_size_override
            import_to_box(view)
          else
            ::UI.beep
          end

        when :edge_selected
          if @distance > 0.001.mm && @plane_corners && @plane_corners.length == 4
            @mode = :plane_confirmed
            @final_box = nil
            @box_depth = 0
            
            v1 = @plane_corners[0].vector_to(@plane_corners[1])
            v2 = @plane_corners[0].vector_to(@plane_corners[3])
            @plane_normal = v1 * v2
            @plane_normal.normalize! if @plane_normal.length > 0
          else
            ::UI.beep
          end

        when :plane_confirmed
          if mouse_inside_plane?(view, x, y)
            import_with_plane(view)
          elsif @final_box && @final_box.size == 8 && @box_depth > 0.001.mm
            import_final_box(view)
          else
            ::UI.beep
          end
        end
        
        update_status
        view.invalidate
      end

      def reload_material_hud_data(view)
        Sketchup.status_text = 'Dang nap lai Excel va cache HUD...'
        MH::Superimp.ensure_registry_runtime
        registry = defined?(MH::RegistryApp) ? MH::RegistryApp : nil
        result = nil
        if registry && registry.respond_to?(:reload_mvl_excel_pipeline)
          result = registry.reload_mvl_excel_pipeline({})
        end
        if (!result.is_a?(Hash) || !(result['ok'] || result[:ok])) &&
           registry && registry.respond_to?(:reload_registry_excel_runtime)
          registry.reload_registry_excel_runtime
        end
        invalidate_registry_context_cache
        load_current_material_profile
        Sketchup.status_text = 'Da reload Excel + Registry + HUD.'
        view.invalidate
        true
      rescue => e
        Sketchup.status_text = "Reload HUD loi: #{e.message}"
        puts "[MH::Superimp] reload HUD data error: #{e.class}: #{e.message}"
        view.invalidate
        false
      end

      def onKeyDown(key, repeat, flags, view)
        if @thickness_input_buffer.to_s != ''
          if key == 27
            @thickness_input_buffer = ''
            Sketchup.status_text = 'Da huy nhap do day.'
            update_thickness_vcb
            view.invalidate
            return true
          elsif key == 13
            apply_thickness_input(view)
            return true
          elsif key == 8
            @thickness_input_buffer = @thickness_input_buffer[0...-1].to_s
            Sketchup.status_text = thickness_input_status
            update_thickness_vcb
            view.invalidate
            return true
          elsif append_thickness_input_key(key, view)
            return true
          end
        elsif numpad_digit_key?(key)
          @thickness_input_buffer = ''
          append_thickness_input_key(key, view)
          return true
        elsif @swap_buffer.to_s != ''
          if key == 27
            clear_swap_buffer(view, 'Da huy shortcut.')
            return true
          elsif key == 8
            @swap_buffer = @swap_buffer[0...-1].to_s
            if @swap_buffer.empty?
              clear_swap_buffer(view, 'Da huy shortcut.')
            else
              schedule_swap_timer(view)
              Sketchup.status_text = swap_status_text
              view.invalidate
            end
            return true
          elsif key == 13
            @thickness_input_buffer = @swap_buffer
            clear_swap_timer
            @swap_buffer = ''
            apply_thickness_input(view)
            return true
          elsif thickness_separator_key?(key)
            @thickness_input_buffer = @swap_buffer
            clear_swap_timer
            @swap_buffer = ''
            append_thickness_input_key(key, view)
            return true
          end
        end

        if key == 18 || ((flags & ALT_MODIFIER_MASK) != 0 && key != 9)
          return true if @alt_key_down

          @alt_key_down = true
          cycle_material_profile(view, :option_in_row)
          return true
        end

        if key == 27
          case @mode
          when :plane_confirmed
            @mode = :edge_selected
            @final_box = nil
            @box_depth = 0
          when :face_push
            @mode = :hovering
            @push_base_point = nil
            @push_axis_info = nil
            @live_box_size_override = nil
            @box_corners = nil
          when :edge_selected
            @mode = :hovering
            @sel_edge = nil
            @sel_edges = []
            @plane_corners = nil
            @distance = 0
            @distance_locked = false
            @snap_pt = nil
            @ip.clear
          else
            Sketchup.active_model.tools.pop_tool
          end
          update_status
          view.invalidate
          return true
        end

        if key == 9 # Tab: đổi dòng vật liệu, giữ nguyên option hiện tại.
          cycle_material_profile(view, :material_row)
          return true
        end
        
        case key
        when 38, 40
          @face_lock = (@face_lock == :vertical) ? :none : :vertical
          update_status
          view.invalidate
          return true
        when 37, 39
          @face_lock = (@face_lock == :horizontal) ? :none : :horizontal
          update_status
          view.invalidate
          return true
        end

        # Swap shortcut: phím số 0-9 (key 48-57)
        if key >= 48 && key <= 57
          digit = (key - 48).to_s
          # Không cho phép bắt đầu bằng 0
          return false if digit == "0" && @swap_buffer.empty?

          @swap_buffer += digit

          schedule_swap_timer(view)
          Sketchup.status_text = swap_status_text
          view.invalidate
          return true
        end

        false
      end

      def digit_char_for_key(key)
        if key >= 96 && key <= 105
          (key - 96).to_s
        elsif key >= 48 && key <= 57
          (key - 48).to_s
        end
      end

      def numpad_digit_key?(key)
        key >= 96 && key <= 105
      end

      def thickness_separator_key?(key)
        # 110 numpad '.', 190 '.', 188 ',', 108 VK_SEPARATOR,
        # + toan tu numpad lam dau phan cach panel/back: 109 '-', 111 '/', 107 '+', 106 '*'
        [110, 190, 188, 108, 109, 111, 107, 106].include?(key)
      end

      def append_thickness_input_key(key, view)
        digit = digit_char_for_key(key)
        last_seg = @thickness_input_buffer.split(',', 2).last.to_s
        char =
          if digit
            digit
          elsif key == 110 || key == 190
            # Dau thap phan numpad/'.': lan dau = '.'; neu segment da la so thap phan
            # hoan chinh (vd 17.6) => lan 2 thanh dau phan cach panel/back ','.
            last_seg =~ /\A\d+\.\d+\z/ ? ',' : '.'
          elsif key == 188 || key == 108 || key == 109 || key == 111 || key == 107 || key == 106
            ',' # ',' OEM hoac toan tu numpad (- / + *) = dau phan cach panel/back
          else
            nil
          end
        return false unless char
        return true if char == ',' && (@thickness_input_buffer.include?(',') || @thickness_input_buffer.empty?)
        return true if char == '.' && last_seg.include?('.')

        @thickness_input_buffer << char
        Sketchup.status_text = thickness_input_status
        update_thickness_vcb
        view.invalidate
        true
      end

      # Hien buffer do day xuong VCB (o do goc duoi-phai) cho de thay.
      def update_thickness_vcb
        Sketchup.vcb_label = 'Day VL'
        Sketchup.vcb_value = @thickness_input_buffer.to_s
      rescue
        nil
      end

      def clear_swap_timer
        UI.stop_timer(@swap_timer) if @swap_timer
        @swap_timer = nil
      end

      def schedule_swap_timer(view)
        clear_swap_timer
        @swap_timer = UI.start_timer(MH::Superimp::SWAP_TIMEOUT, false) do
          @swap_timer = nil
          try_swap(view)
        end
      end

      def clear_swap_buffer(view, message = nil)
        clear_swap_timer
        @swap_buffer = ''
        Sketchup.status_text = message if message
        view.invalidate
      end

      def swap_status_text
        "Swap: #{@swap_buffer}_  (. hoac , = nhap do day, Enter = panel)"
      end

      def thickness_input_status
        "Nhap do day: #{@thickness_input_buffer}_ (17.6 hoac 17.6,8)"
      end

      def parse_thickness_input(text)
        raw = text.to_s.strip
        return nil if raw.empty?

        parts = raw.split(',', 2).map { |part| part.strip }
        return nil if parts.empty? || parts[0].empty?
        return nil unless parts.all? { |part| part.empty? || part =~ /\A\d+(?:\.\d+)?\z/ }

        panel = parts[0].to_f
        back = parts.length > 1 && !parts[1].empty? ? parts[1].to_f : nil
        return nil if panel <= 0 || (back && back <= 0)

        { panel: panel, back: back }
      end

      def apply_thickness_input(view)
        parsed = parse_thickness_input(@thickness_input_buffer)
        unless parsed
          @thickness_input_buffer = ''
          update_thickness_vcb
          Sketchup.status_text = 'Do day khong hop le. Vi du: 17.6 hoac 17.6,8'
          UI.beep
          view.invalidate
          return false
        end

        @thickness_input_buffer = ''
        update_thickness_vcb
        label = parsed[:back] ? "#{format_hud_number(parsed[:panel])}/#{format_hud_number(parsed[:back])}" : format_hud_number(parsed[:panel])

        # UU TIEN: DC dang duoc CHON ro rang -> ap ngay vao no.
        # KHONG dung hover/last-imported (de ap nham vat chu duoi con tro khi
        # dang dat diem). Khong co selection -> luu CHO, ap khi import.
        connector = (MH::RegistryApp::Connector.get('dc_import_pipeline') rescue nil) if defined?(MH::RegistryApp::Connector)
        targets = Sketchup.active_model.selection.to_a.grep(Sketchup::ComponentInstance).select(&:valid?)
        if targets.any? && connector && connector.respond_to?(:apply_quick_thickness)
          done = 0
          context = registry_context(allow_slow_scan: true)
          targets.each do |inst|
            res = connector.apply_quick_thickness(inst, parsed[:panel], parsed[:back], context)
            done += 1 if res.is_a?(Hash) && (res['ok'] || res[:ok])
          end
          invalidate_registry_context_cache
          @material_profile_msg = "Da ap day #{label} vao #{done} DC dang chon"
          Sketchup.status_text = @material_profile_msg
          view.invalidate
          return true
        end

        # Khong chon DC -> nap vao profile cho, ap khi IMPORT ke tiep.
        set_pending_thickness_profile(parsed)
        @material_profile_msg = "Dày: #{label} (se ap khi import)"
        Sketchup.status_text = @material_profile_msg
        view.invalidate
        true
      rescue => e
        @thickness_input_buffer = ''
        Sketchup.status_text = "Nhap do day loi: #{e.message}"
        view.invalidate
        false
      end

      # Nap do day vao profile CHO - se ap vao DC o lan import ke tiep.
      def set_pending_thickness_profile(parsed)
        src = @material_profile || {}
        material = (src[:material_code] || src['material_code']).to_s.strip
        material = current_hud_material_code if material.empty?
        current_back = src[:back_thickness_mm] || src['back_thickness_mm']
        back = parsed[:back] || current_back.to_f
        back = parsed[:panel] if back <= 0

        @material_profile = {
          'profile_id' => "quick::#{material}::#{parsed[:panel]}::#{back}",
          'profile_name' => "#{material} #{parsed[:panel]}/#{back}",
          'material_code' => material,
          'panel_thickness_mm' => parsed[:panel],
          'back_thickness_mm' => back,
          'hud_tokens' => parsed[:back] ? [format_hud_number(parsed[:panel]), format_hud_number(back)] : [format_hud_number(parsed[:panel])]
        }
        @material_profile_manual = true
        invalidate_registry_context_cache
        @material_profile
      end

      # Dang go do day do ma click (quen Enter) -> tu chot buffer thanh profile cho.
      def commit_thickness_buffer_pending(view)
        parsed = parse_thickness_input(@thickness_input_buffer)
        @thickness_input_buffer = ''
        update_thickness_vcb
        return false unless parsed

        set_pending_thickness_profile(parsed)
        label = parsed[:back] ? "#{format_hud_number(parsed[:panel])}/#{format_hud_number(parsed[:back])}" : format_hud_number(parsed[:panel])
        @material_profile_msg = "Dày: #{label}"
        Sketchup.status_text = @material_profile_msg
        true
      rescue
        false
      end

      def format_hud_number(value)
        format('%.3f', value.to_f).sub(/0+$/, '').sub(/\.$/, '')
      end

      def onKeyUp(key, repeat, flags, view)
        @alt_key_down = false if key == 18 || (flags & ALT_MODIFIER_MASK) != 0
        false
      end

      # ---- Swap logic ----
      def try_swap(view)
        if @swap_buffer.empty?
          return
        end
        code = @swap_buffer
        @swap_buffer = ""

        if !@group || @group.empty? || !@swap_map[@group]
          @swap_last_msg = "✗ Lỗi: Cấu kiện này chưa được gán Nhóm!"
          Sketchup.status_text = "Không thể Swap vì cấu kiện gốc không có Nhóm."
        else
          new_item = @swap_map[@group][code]
          if new_item
            if File.exist?(new_item[:path])
              @import_path = new_item[:path]
              name = new_item[:name]
              invalidate_registry_context_cache
              @swap_last_msg = "✓ [#{code}] → #{name}"
              Sketchup.status_text = "Đã swap sang: #{name}"
            else
              # File không tồn tại nhưng vẫn set path (có thể user sẽ tạo file sau)
              @import_path = new_item[:path]
              name = new_item[:name]
              invalidate_registry_context_cache
              @swap_last_msg = "⚠ [#{code}] #{name} — file chưa tồn tại!"
              Sketchup.status_text = "Swap [#{code}]: file không tìm thấy tại #{new_item[:path]}"
            end
          else
            @swap_last_msg = "✗ [#{code}] key không có trong nhóm #{@group}"
            Sketchup.status_text = "Swap key #{code}: không có trong nhóm #{@group}!"
          end
        end

        # Tự xóa message sau 3 giây
        UI.stop_timer(@swap_msg_timer) if @swap_msg_timer
        @swap_msg_timer = UI.start_timer(3.0, false) do
          @swap_msg_timer = nil
          @swap_last_msg = nil
          view.invalidate if Sketchup.active_model && Sketchup.active_model.active_view
        end

        update_status
        view.invalidate if Sketchup.active_model && Sketchup.active_model.active_view
      end

      def onRButtonDown(flags, x, y, view)
        # When right button pressed with missing dimension, lock the face state
        if @mode == :hovering && @box_corners && @missing_axis && !@live_box_size_override
          @rbutton_held = true
          @locked_base_point = @face_origin
          @locked_missing_axis = @missing_axis
          update_status
          view.invalidate
        end
      end

      def onRButtonUp(flags, x, y, view)
        if @rbutton_held
          @rbutton_held = false
          # Keep the calculated distance as override
          if @box_corners && @missing_axis
            # Distance was already calculated, now it's locked
            update_status
            view.invalidate
          end
        end
      end

      def enableVCB?
        true
      end

      def onUserText(text, view)
        text = text.strip
        if text.start_with?('-')
          val = text[1..-1].to_l rescue nil
          @offset_y = val if val && val > 0
        elsif text.start_with?('+')
          val = text[1..-1].to_l rescue nil
          if val && val > 0
            @offset_z = val
            @offset_z_after_set = (@set_z != nil)
          end
        else
          val = text.to_l rescue nil
          if val && val > 0
            if @mode == :hovering && @box_corners && @missing_axis
              # Set dimension for Live Box with missing axis
              @live_box_size_override = val
              compute_box_corners(view)
            elsif @mode == :edge_selected
              @distance = val
              @distance_locked = true
              # Tính lại plane corners với distance mới
              if @sel_line && @edge_start_pt && @edge_end_pt
                line_pt, line_vec = @sel_line
                proj_pt = @snap_pt ? project_point_to_line(@snap_pt, line_pt, line_vec) : @edge_start_pt
                compute_plane_corners(proj_pt)
              end
            elsif @mode == :plane_confirmed
              @box_depth = val
              @depth_locked = true  # Lock depth after VCB input
              compute_final_box
            else
              @set_z = val
              @offset_z_after_set = false
            end
          end
        end
        update_status
        view.invalidate
      end

      # ==================== IMPORT METHODS ====================

      def replace_object(view, target_obj, target_transform)
        model = view.model
        ents = model.active_entities
        return unless File.exist?(@import_path) && target_obj.valid?

        bb = target_obj.bounds
        target_sx, target_sy, target_sz = (bb.max.x - bb.min.x).abs, (bb.max.y - bb.min.y).abs, (bb.max.z - bb.min.z).abs
        return if target_sx <= 0 || target_sy <= 0 || target_sz <= 0
        import_path = resolve_import_path_for_depth(target_sy, view)

        begin
          model.start_operation('MH Superimp - Replace', true)
          defn = model.definitions.load(import_path)
          return model.abort_operation unless defn && defn.valid?

          src_bb = defn.bounds
          transform = MH::Geo::Fit.scale_to_box(src_bb, bb.min, [target_sx, target_sy, target_sz])
          inst = ents.add_instance(defn, transform)
          MH::Superimp.safe_redraw_dc(inst)
          ents.erase_entities(target_obj) if target_obj.valid?
          
          model.commit_operation
          after_import_dc(inst) if inst.valid?
          # Keep Superimp tool active so Ctrl+Click replace can continue on next objects.
          @last_imported_dc = inst if inst.valid?
          model.selection.clear
          model.selection.add(inst) if inst.valid?
          update_status
          view.invalidate
        rescue
          model.abort_operation
        end
      end

      def import_direct(view)
        model = view.model
        return unless File.exist?(@import_path)
        defn = model.definitions.load(@import_path) rescue nil
        return unless defn && defn.valid?
        context = registry_context
        # QUAN TRONG: dem theo profile do day dang CHO (go so + Enter truoc do).
        # Luong nay dat bang place_component -> watch_placed_instance -> pipeline;
        # khong qua after_import_dc cua tool nen phai tu nhet profile vao context.
        context[:material_profile] = @material_profile if @material_profile
        model.tools.pop_tool
        model.place_component(defn)
        MH::Superimp.watch_placed_instance(defn, context)
      end

      # Sau import: GIU tool Superimp hoat dong (khong pop, khong sang Scale tool)
      # de go do day + Enter ap ngay vao DC vua import. Chon DC + reset ve hovering.
      def finish_import_keep_tool(inst)
        model = Sketchup.active_model
        @last_imported_dc = inst if inst && inst.valid?
        model.selection.clear
        model.selection.add(inst) if inst && inst.valid?
        @mode = :hovering
        @sel_edge = nil
        @sel_edges = []
        @plane_corners = nil
        @distance = 0
        @distance_locked = false
        @snap_pt = nil
        @final_box = nil
        @box_depth = 0
        @box_corners = nil
        @push_base_point = nil
        @push_axis_info = nil
        @live_box_size_override = nil
        @ip.clear
        update_status
      rescue => e
        puts "[MH::Superimp] finish_import_keep_tool error: #{e.class}: #{e.message}"
      end

      def import_to_box(view)
        model = view.model
        ents = model.active_entities
        return unless File.exist?(@import_path) && @box_corners && @box_corners.size == 8

        xs, ys, zs = @box_corners.map(&:x), @box_corners.map(&:y), @box_corners.map(&:z)
        box_min_x, box_max_x = xs.min, xs.max
        box_min_y, box_max_y = ys.min + @offset_y, ys.max
        box_min_z = zs.min + @offset_z
        
        box_sx = (box_max_x - box_min_x).abs
        box_sy = (box_max_y - box_min_y).abs
        original_z = (zs.max - zs.min).abs
        box_sz = @set_z ? (@offset_z_after_set ? @set_z - @offset_z : @set_z) : original_z - @offset_z
        box_min = Geom::Point3d.new(box_min_x, box_min_y, box_min_z)

        return if box_sx <= 0 || box_sy <= 0 || box_sz <= 0
        import_path = resolve_import_path_for_depth(box_sy, view)

        begin
          model.start_operation('MH Superimp - Import Box', true)
          defn = model.definitions.load(import_path)
          return model.abort_operation unless defn && defn.valid?

          bb = defn.bounds
          transform = MH::Geo::Fit.scale_to_box(bb, box_min, [box_sx, box_sy, box_sz])
          inst = ents.add_instance(defn, transform)
          MH::Superimp.safe_redraw_dc(inst)
          
          model.commit_operation
          after_import_dc(inst) if inst.valid?
          finish_import_keep_tool(inst)
        rescue
          model.abort_operation
        end
      end

      def import_with_plane(view)
        model = view.model
        ents = model.active_entities
        return unless File.exist?(@import_path)

        begin
          model.start_operation('MH Superimp - Import Plane 2D', true)
          defn = model.definitions.load(@import_path)
          return model.abort_operation unless defn && defn.valid?

          bb = defn.bounds
          dmin, dmax = bb.min, bb.max
          dx, dy, dz = (dmax.x - dmin.x).abs, (dmax.y - dmin.y).abs, (dmax.z - dmin.z).abs
          eps = 0.001.mm

          sx, sy, sz = 1.0, 1.0, 1.0
          case @sel_axis
          when :X then sx = dx > eps ? @sel_length / dx : 1.0
          when :Y then sy = dy > eps ? @sel_length / dy : 1.0
          when :Z then sz = dz > eps ? @sel_length / dz : 1.0
          end
          case @distance_axis
          when :X then sx = dx > eps ? @distance / dx : 1.0
          when :Y then sy = dy > eps ? @distance / dy : 1.0
          when :Z then sz = dz > eps ? @distance / dz : 1.0
          end

          target_pt = if @plane_corners && @plane_corners.length == 4
            pxs, pys, pzs = @plane_corners.map(&:x), @plane_corners.map(&:y), @plane_corners.map(&:z)
            Geom::Point3d.new(pxs.min, pys.min, pzs.min)
          else
            @edge_start_pt || ORIGIN
          end

          transform = MH::Geo::Fit.scale_from_min(bb, target_pt, sx, sy, sz)
          inst = ents.add_instance(defn, transform)
          MH::Superimp.safe_redraw_dc(inst)
          
          model.commit_operation
          after_import_dc(inst) if inst.valid?
          finish_import_keep_tool(inst)
        rescue
          model.abort_operation
        end
      end

      def import_final_box(view)
        model = view.model
        ents = model.active_entities
        return unless File.exist?(@import_path) && @final_box && @final_box.size == 8

        xs, ys, zs = @final_box.map(&:x), @final_box.map(&:y), @final_box.map(&:z)
        box_min = Geom::Point3d.new(xs.min, ys.min, zs.min)
        box_sx, box_sy, box_sz = (xs.max - xs.min).abs, (ys.max - ys.min).abs, (zs.max - zs.min).abs

        return if box_sx <= 0 || box_sy <= 0 || box_sz <= 0
        import_path = resolve_import_path_for_depth(box_sy, view)

        begin
          model.start_operation('MH Superimp - Import 3D Box', true)
          defn = model.definitions.load(import_path)
          return model.abort_operation unless defn && defn.valid?

          bb = defn.bounds
          transform = MH::Geo::Fit.scale_to_box(bb, box_min, [box_sx, box_sy, box_sz])
          inst = ents.add_instance(defn, transform)
          MH::Superimp.safe_redraw_dc(inst)
          
          model.commit_operation
          after_import_dc(inst) if inst.valid?
          finish_import_keep_tool(inst)
        rescue
          model.abort_operation
        end
      end
    end

    def self.import_or_replace(import_path)
      if @active_tool && @active_tool.is_a?(LiveBoxPreviewTool)
        @active_tool.set_import_path(import_path)
      else
        Sketchup.active_model.tools.push_tool(LiveBoxPreviewTool.new(import_path))
      end
    end

    module UI_Menu
      unless file_loaded?(__FILE__)
        if defined?(MH::RegistryApp::Menu)
          MH::Superimp.sync_registry_menu!
          MH::RegistryApp::Menu.add(app: 'Superimp', key: 'manager_runtime', label: 'Quản lý danh sách') { MH::Superimp.show_config_dialog }
          MH::RegistryApp::Menu.add(app: 'Superimp', key: 'reload_runtime', label: 'Reload xlsx') do
            MH::Superimp.reload_import_list
            ::UI.messagebox("Đã reload #{MH::Superimp.import_list.length} items!")
          end
        end
        file_loaded(__FILE__)
      end
    end

  end
end

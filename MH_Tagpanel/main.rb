# ====================================================================
# MH::Tagpanel – Toggle Tag + Folder Tag bằng phím tắt
# Không cần panel, tự động cập nhật khi có tag mới
# ====================================================================

require "sketchup.rb"

module MH
  module Tagpanel

    # Lưu command đã tạo để không tạo trùng
    @tag_commands = {}
    @folder_commands = {}
    @menu_built = false
    @observer_attached = false
    @settings = nil # Lưu danh sách tag được chọn


    # ===========================================================
    # HÀM BẬT / TẮT TAG – trả về "ON"/"OFF"
    # ===========================================================
    def self.toggle_tag(name)
      model = Sketchup.active_model
      return "ERR" unless model
      
      tag = model.layers[name]
      return "ERR" unless tag

      if tag.respond_to?(:hidden?)   # SketchUp 2021+
        tag.hidden = !tag.hidden?
        state = tag.hidden? ? "OFF" : "ON"
      else                           # SketchUp cũ hơn
        tag.visible = !tag.visible?
        state = tag.visible? ? "ON" : "OFF"
      end
      
      # puts "[MH Tagpanel] Tag '#{name}' → #{state}"
      state
    end

    # ===========================================================
    # HÀM BẬT / TẮT FOLDER TAG (sử dụng LayerFolder object)
    # ===========================================================
    def self.toggle_folder(folder)
      model = Sketchup.active_model
      return unless model

      # Lấy tất cả tags trong folder (bao gồm subfolder)
      matching_tags = get_tags_in_folder(folder)
      return if matching_tags.empty?

      # Xác định trạng thái hiện tại của folder
      # Nếu có bất kỳ tag nào đang hiện → ẩn tất cả
      # Nếu tất cả đã ẩn → hiện tất cả
      any_visible = matching_tags.any? do |t|
        if t.respond_to?(:hidden?)
          !t.hidden?
        else
          t.visible?
        end
      end

      new_hidden = any_visible # Nếu có tag hiện → ẩn tất cả
      
      matching_tags.each do |t|
        if t.respond_to?(:hidden?)
          t.hidden = new_hidden
        else
          t.visible = !new_hidden
        end
      end

      state = new_hidden ? "OFF" : "ON"
      state
    end

    # ===========================================================
    # LẤY DANH SÁCH TAG FOLDERS (SketchUp 2021+)
    # ===========================================================
    def self.get_tag_folders
      model = Sketchup.active_model
      return [] unless model

      # Kiểm tra nếu có LayerFolder API (SketchUp 2021+)
      return [] unless model.layers.respond_to?(:folders)
      
      folders = []
      collect_folders_recursive(model.layers.folders, folders)
      folders
    end

    # Thu thập tất cả folders đệ quy
    def self.collect_folders_recursive(folder_collection, result, parent_path = "")
      folder_collection.each do |folder|
        folder_path = parent_path.empty? ? folder.name : "#{parent_path}/#{folder.name}"
        result << { folder: folder, path: folder_path }
        
        # Đệ quy cho subfolder nếu có
        if folder.respond_to?(:folders)
          collect_folders_recursive(folder.folders, result, folder_path)
        end
      end
    end

    # Lấy tất cả tags trong một folder (bao gồm subfolder)
    def self.get_tags_in_folder(folder)
      tags = []
      
      # Tags trực tiếp trong folder
      folder.layers.each { |t| tags << t }
      
      # Tags trong subfolder (đệ quy)
      if folder.respond_to?(:folders)
        folder.folders.each do |subfolder|
          tags.concat(get_tags_in_folder(subfolder))
        end
      end
      
      tags
    end

    # ===========================================================
    # ĐĂNG KÝ COMMAND TỪNG TAG → DÙNG CHO SHORTCUT
    # ===========================================================
    def self.register_tag_commands
      model = Sketchup.active_model
      return unless model

      # Tạo submenu riêng (chỉ tạo 1 lần)
      @tag_menu ||= UI.menu("Plugins").add_submenu("MH Tagpanel – Toggle Tags")
      @folder_menu ||= UI.menu("Plugins").add_submenu("MH Tagpanel – Toggle Folders")

      new_tags_count = 0
      new_folders_count = 0

      # Đăng ký command cho từng tag
      included_tags = get_included_tags
      
      model.layers.each do |t|
        name = t.name
        next if @tag_commands[name]
        
        # Lọc: Chỉ đăng ký nếu tag nằm trong danh sách được chọn (hoặc nếu chưa có settings thì đăng ký hết)
        next if !included_tags.empty? && !included_tags.include?(name)

        label = "MH Tagpanel: Toggle #{name}"
        cmd = UI::Command.new(label) {
          MH::Tagpanel.toggle_tag(name)
        }

        @tag_menu.add_item(cmd)
        @tag_commands[name] = cmd
        new_tags_count += 1
      end

      # Lấy danh sách Tag Folders (SketchUp 2021+)
      tag_folders = get_tag_folders
      folder_names = tag_folders.map { |f| f[:path] }

      # Đăng ký command cho từng folder
      tag_folders.each do |folder_info|
        folder = folder_info[:folder]
        folder_path = folder_info[:path]
        
        next if @folder_commands[folder_path]

        label = "MH Tagpanel: Toggle Folder #{folder_path}"
        cmd = UI::Command.new(label) {
          MH::Tagpanel.toggle_folder(folder)
        }

        @folder_menu.add_item(cmd)
        @folder_commands[folder_path] = cmd
        new_folders_count += 1
      end
    end

    # ===========================================================
    # OBSERVER ĐỂ TỰ ĐỘNG CẬP NHẬT KHI CÓ TAG MỚI
    # ===========================================================
    class TagObserver < Sketchup::LayersObserver
      def onLayerAdded(layers, layer)
        # Delay để đảm bảo tag đã được thêm hoàn toàn
        UI.start_timer(0.1, false) {
          MH::Tagpanel.register_tag_commands
        }
      end
    end

    # ===========================================================
    # APP OBSERVER ĐỂ GẮN LAYER OBSERVER KHI MỞ FILE MỚI
    # ===========================================================
    class AppObserver < Sketchup::AppObserver
      def onNewModel(model)
        MH::Tagpanel.attach_observers(model)
        MH::Tagpanel.register_tag_commands
      end

      def onOpenModel(model)
        MH::Tagpanel.attach_observers(model)
        MH::Tagpanel.register_tag_commands
      end
    end

    # ===========================================================
    # QUẢN LÝ SETTINGS & UI
    # ===========================================================
    
    def self.get_included_tags
      return @settings if @settings
      data = Sketchup.read_default("MH_Tagpanel", "included_tags", "")
      @settings = data.empty? ? [] : data.split("|||")
      @settings
    end

    def self.save_settings(tags)
      @settings = tags
      Sketchup.write_default("MH_Tagpanel", "included_tags", tags.join("|||"))
      
      # Sau khi lưu, cần reload để cập nhật menu
      self.register_tag_commands
    end


    def self.show_settings
      model = Sketchup.active_model
      return unless model

      all_tags = model.layers.map(&:name).sort
      included_tags = get_included_tags

      @settings_dialog = UI::HtmlDialog.new({
        :dialog_title => "MH Tagpanel Settings",
        :preferences_key => "MH_Tagpanel_Settings",
        :scrollable => true,
        :resizable => true,
        :width => 400,
        :height => 600,
        :style => UI::HtmlDialog::STYLE_DIALOG
      })

      html = <<-HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <style>
          :root {
            --primary: #2196F3;
            --bg: #1e1e1e;
            --text: #ffffff;
            --surface: #2d2d2d;
            --border: #444;
          }
          body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            background: var(--bg); 
            color: var(--text);
            margin: 0; padding: 20px;
            display: flex; flex-direction: column; height: 100vh; box-sizing: border-box;
          }
          h2 { margin-top: 0; font-weight: 300; color: var(--primary); }
          .search-box {
            padding: 10px; border-radius: 4px; border: 1px solid var(--border);
            background: var(--surface); color: white; width: 100%; margin-bottom: 15px;
            box-sizing: border-box;
          }
          .tag-list {
            flex-grow: 1; overflow-y: auto;
            border: 1px solid var(--border); border-radius: 4px; background: var(--surface);
            margin-bottom: 15px; padding: 5px;
          }
          .tag-item {
            display: flex; align-items: center; padding: 8px;
            border-bottom: 1px solid #3d3d3d; cursor: pointer;
          }
          .tag-item:hover { background: #3d3d3d; }
          .tag-item label { flex-grow: 1; cursor: pointer; margin-left: 10px; }
          .actions { display: flex; gap: 10px; }
          button {
            padding: 10px 20px; border: none; border-radius: 4px;
            cursor: pointer; font-weight: bold; transition: 0.2s;
          }
          .btn-save { background: var(--primary); color: white; flex-grow: 2; }
          .btn-save:hover { background: #1976D2; }
          .btn-sec { background: #555; color: white; flex-grow: 1; }
          .btn-sec:hover { background: #666; }
          .stats { font-size: 12px; color: #aaa; margin-top: 5px; }
        </style>
      </head>
      <body>
        <h2>Tag Selection</h2>
        <input type="text" class="search-box" id="search" placeholder="Search tags..." onkeyup="filterTags()">
        
        <div class="actions" style="margin-bottom: 10px;">
          <button class="btn-sec" onclick="selectAll(true)">Select All</button>
          <button class="btn-sec" onclick="selectAll(false)">Clear All</button>
        </div>

        <div class="tag-list" id="tagList">
          #{all_tags.map { |name| 
            checked = (included_tags.empty? || included_tags.include?(name)) ? "checked" : ""
            "<div class='tag-item' data-name='#{name}'>
              <input type='checkbox' id='tag_#{name}' value='#{name}' #{checked}>
              <label for='tag_#{name}'>#{name}</label>
            </div>"
          }.join("\n")}
        </div>

        <div class="actions">
          <button class="btn-save" onclick="save()">SAVE & APPLY</button>
          <button class="btn-sec" onclick="window.close()">Cancel</button>
        </div>
        <div class="stats" id="stats"></div>

        <script>
          function filterTags() {
            let q = document.getElementById('search').value.toLowerCase();
            let items = document.querySelectorAll('.tag-item');
            items.forEach(item => {
              let name = item.getAttribute('data-name').toLowerCase();
              item.style.display = name.includes(q) ? 'flex' : 'none';
            });
          }

          function selectAll(val) {
            document.querySelectorAll('.tag-item:not([style*="display: none"]) input').forEach(cb => cb.checked = val);
            updateStats();
          }

          function updateStats() {
            let total = document.querySelectorAll('input[type="checkbox"]').length;
            let checked = document.querySelectorAll('input[type="checkbox"]:checked').length;
            document.getElementById('stats').innerText = checked + ' / ' + total + ' tags selected';
          }

          function save() {
            let selected = Array.from(document.querySelectorAll('input[type="checkbox"]:checked')).map(cb => cb.value);
            sketchup.save(selected);
            window.close();
          }

          updateStats();
        </script>
      </body>
      </html>
      HTML

      @settings_dialog.set_html(html)
      
      @settings_dialog.add_action_callback("save") { |action_context, selected_tags|
        self.save_settings(selected_tags)
        UI.messagebox("Đã cập nhật danh sách Tag!")
      }


      @settings_dialog.show
    end


    # ===========================================================
    # GẮN OBSERVERS VÀO MODEL
    # ===========================================================
    def self.attach_observers(model)
      return unless model
      
      @tag_observer ||= TagObserver.new
      
      model.layers.add_observer(@tag_observer)
    end

    # ===========================================================
    # RELOAD PLUGIN (dùng trong Ruby Console)
    # ===========================================================
    def self.reload
      # Reset trạng thái
      @tag_commands = {}
      @folder_commands = {}
      @menu_built = false # Cho phép tạo lại menu mới
      
      # Load lại file
      file_path = File.join(File.dirname(__FILE__), "main.rb")
      load file_path
      
      # register_tag_commands
    end


    # ===========================================================
    # KHỞI TẠO
    # ===========================================================
    def self.init
      return if @menu_built

      # Thêm menu item để refresh thủ công nếu cần
      main_menu = UI.menu("Plugins").add_submenu("MH Tagpanel")
      
      main_menu.add_item("Settings...") {
        MH::Tagpanel.show_settings
      }

      main_menu.add_item("Refresh Commands") {
        MH::Tagpanel.register_tag_commands
        UI.messagebox("Đã cập nhật danh sách commands!\n\nVào Window → Preferences → Shortcuts\nTìm 'MH Tagpanel' để gán phím tắt.", MB_OK)
      }


      # Đăng ký commands ban đầu
      register_tag_commands

      # Gắn observers
      @app_observer = AppObserver.new
      Sketchup.add_observer(@app_observer)
      
      model = Sketchup.active_model
      attach_observers(model) if model

      @menu_built = true
    end


    # Khởi tạo khi load
    MH::Tagpanel.init

  end
end

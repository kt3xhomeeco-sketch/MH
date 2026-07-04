# encoding: utf-8
# MH_Thongke — mini import dialog ui
# UI/render/dialog cho Mini Import. Không chứa logic xử lý thống kê lõi.
module MH_Thongke

  # === mini_import_position.rb ===
  # --- mini_import_position.rb ---
# MH_Thongke - mini import dialog position persistence.


  def self.safe_import_mini_dialog_position(x = nil, y = nil)
    dialog_w = 560
    dialog_h = 600
    default_x = 80
    default_y = 80
    screen_w, screen_h = import_material_hud_screen_size

    return [default_x, default_y, true] if x.nil? || y.nil?

    original_x = x.to_i
    original_y = y.to_i
    max_x = screen_w ? [screen_w.to_i - dialog_w - 40, default_x].max : nil
    max_y = screen_h ? [screen_h.to_i - dialog_h - 80, default_y].max : nil

    # HtmlDialog screenX can be saved from a secondary monitor. In practice this
    # makes the mini table look "lost", so keep startup position on the primary screen.
    if original_x < 0 || original_y < 0 ||
       (max_x && original_x > max_x) ||
       (max_y && original_y > max_y)
      return [default_x, default_y, true]
    end

    x = [original_x, 40].max
    y = [original_y, 40].max
    x = [x, max_x].min if max_x
    y = [y, max_y].min if max_y
    [x, y, x != original_x || y != original_y]
  rescue
    [80, 80, true]
  end

  def self.read_import_mini_dialog_position
    @model ||= Sketchup.active_model
    begin
      raw = @model.get_attribute("MH_Thongke", "mini_import_position").to_s
      data = raw.empty? ? nil : JSON.parse(raw)
      return data if data.is_a?(Hash) && data.key?("x") && data.key?("y")
    rescue
    end

    begin
      return nil unless File.exist?(MH_THONGKE_PREFS_JSON)
      prefs = JSON.parse(File.read(MH_THONGKE_PREFS_JSON))
      data = prefs["mini_import_position"] if prefs.is_a?(Hash)
      return data if data.is_a?(Hash) && data.key?("x") && data.key?("y")
    rescue
    end
    nil
  end

  def self.save_import_mini_dialog_position(x = nil, y = nil)
    if x.nil? || y.nil?
      if @mini_dlg && @mini_dlg.respond_to?(:get_position)
        pos = @mini_dlg.get_position rescue nil
        x, y =
          if pos.is_a?(Array)
            [pos[0], pos[1]]
          elsif pos.respond_to?(:x) && pos.respond_to?(:y)
            [pos.x, pos.y]
          end
      end
    end
    return if x.nil? || y.nil?

    x, y, = safe_import_mini_dialog_position(x, y)
    data = { "x" => x.to_i, "y" => y.to_i }
    @mini_import_position = data
    @model ||= Sketchup.active_model
    begin
      @model.set_attribute("MH_Thongke", "mini_import_position", JSON.generate(data))
    rescue
    end
    begin
      prefs = File.exist?(MH_THONGKE_PREFS_JSON) ? JSON.parse(File.read(MH_THONGKE_PREFS_JSON)) : {}
      prefs = {} unless prefs.is_a?(Hash)
      prefs["mini_import_position"] = data
      File.write(MH_THONGKE_PREFS_JSON, JSON.pretty_generate(prefs))
    rescue
    end
  end

  def self.restore_import_mini_dialog_position
    return unless @mini_dlg && @mini_dlg.respond_to?(:set_position)
    pos = @mini_import_position || read_import_mini_dialog_position
    x = nil
    y = nil
    if pos.is_a?(Hash)
      x = pos["x"] || pos[:x]
      y = pos["y"] || pos[:y]
    end
    if x.nil? || y.nil?
      x = 80
      y = 80
    else
      x, y, changed = safe_import_mini_dialog_position(x, y)
      save_import_mini_dialog_position(x, y) if changed
    end
    @mini_dlg.set_position(x.to_i, y.to_i)
  rescue
  end

  def self.reset_import_mini_dialog_position
    @mini_import_position = { "x" => 80, "y" => 80 }
    @model ||= Sketchup.active_model
    @model.set_attribute("MH_Thongke", "mini_import_position", JSON.generate(@mini_import_position)) rescue nil
    begin
      prefs = File.exist?(MH_THONGKE_PREFS_JSON) ? JSON.parse(File.read(MH_THONGKE_PREFS_JSON)) : {}
      prefs = {} unless prefs.is_a?(Hash)
      prefs["mini_import_position"] = @mini_import_position
      File.write(MH_THONGKE_PREFS_JSON, JSON.pretty_generate(prefs))
    rescue
    end
    restore_import_mini_dialog_position if @mini_dlg
  end

  # === mini_import_dialog_html.rb ===
  # --- mini_import_dialog_html.rb ---
# MH_Thongke - Mini Import dialog HTML.


  def self.mini_import_dialog_css
    css_path = File.join(MH_Thongke::UI_DIR, "shared_style.css")
    shared_css = File.exist?(css_path) ? File.read(css_path) : ""
    <<-CSS
      #{shared_css}
      /* Các CSS đặc thù cho Mini Import */
      .header{display:flex;justify-content:space-between;align-items:center;gap:8px;margin:0;padding:10px 12px;background:#1e1e24;border-bottom:1px solid #3a3f44;}
      .title{font-size:14px;font-weight:bold;color:#fff;}
      .title span{color:#e67e22;}
      .actions{display:flex;align-items:center;gap:5px;flex-shrink:0;}
      .mode-group{display:flex;gap:3px;}
      .source-group{display:flex;gap:3px;}
      .wrap{padding:10px;}
      .footer{display:flex;gap:6px;justify-content:flex-end;padding:0 10px 10px;}
      table{width:100%;border-collapse:separate;border-spacing:0;table-layout:fixed;border:1px solid #6b7580;border-radius:4px;overflow:hidden;background:#222529;margin-bottom:10px;}
      th{background:#343a40;color:#fff;padding:4px;text-align:left;font-size:9px;border-right:1px solid #6b7580;border-bottom:1px solid #6b7580;white-space:nowrap;}
      th:last-child,td:last-child{border-right:none;}
      td{border-bottom:1px solid #555d65;border-right:1px solid #555d65;padding:2px 4px;font-size:10px;line-height:14px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
      tr:last-child td{border-bottom:none;}
      tr:hover{background:#3d444b;}
      b{color:#e67e22;}
      .status-khop{color:#2ecc71;font-weight:bold;text-align:center;font-size:13px;}
      .status-missing{color:#e67e22;font-weight:bold;text-align:center;}
      .status-extra{color:#e74c3c;font-weight:bold;text-align:center;font-size:10px;}
      .btn-nospec{background:#c0392b;color:#fff;border:none;border-radius:3px;min-width:42px;height:20px;line-height:20px;padding:0 4px;font-size:9px;font-family:inherit;font-weight:bold;margin:0 auto;display:block;cursor:default;text-transform:uppercase;box-sizing:border-box;}
      .btn-spec{background:#f1c40f;color:#1f2933;border:none;border-radius:3px;min-width:42px;height:20px;line-height:20px;padding:0 4px;font-size:9px;font-family:inherit;font-weight:bold;margin:0 auto;display:block;cursor:default;text-transform:uppercase;box-sizing:border-box;}
      .btn{color:#fff;border:none;border-radius:3px;height:20px;line-height:20px;padding:0 4px;cursor:pointer;font-size:9px;font-family:inherit;font-weight:bold;text-transform:uppercase;box-sizing:border-box;}
      .btn-refresh{background:#2980b9;}.btn-refresh:hover{background:#3498db;}
      .btn-apply{background:#16a085;}
      .btn-cancel{background:#7f8c8d;}
      .btn-mode{background:#3a3f44;color:#cbd5e1;}
      .btn-mode.active{background:#e67e22;color:#fff;}
      .btn-update{background:#d35400;min-width:48px;margin:0 auto;display:block;}
      .btn-keep{background:#475569;min-width:48px;margin:0 auto;display:block;}
      .status-actions{display:flex;flex-direction:column;align-items:center;gap:2px;}
      .status-actions .btn{height:17px;line-height:17px;font-size:8px;padding:0 4px;}
      .btn-del{background:#c0392b;width:17px;height:18px;line-height:18px;padding:0;margin:0 auto;display:block;}
      .btn-unmatch{background:#c0392b;width:16px;height:16px;line-height:16px;min-width:16px;padding:0;margin:0 auto;display:block;border-radius:50%;font-size:0;}
      .btn-unmatch:hover{background:#e74c3c;}
      .mini-product-row td{background:#111827;color:#f8fafc;font-weight:bold;text-transform:uppercase;border-top:1px solid #6b7580;padding-top:5px;padding-bottom:5px;}
      .mini-product-head{display:flex;align-items:center;justify-content:space-between;gap:8px;width:100%;}
      .mini-product-title{display:block;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
      .mini-section-row td{background:#2f3740;color:#cbd5e1;font-weight:bold;font-size:10px;text-transform:uppercase;padding-top:3px;padding-bottom:3px;}
      #main-table tbody tr{cursor:pointer;}
      #main-table tbody tr.mini-product-row,#main-table tbody tr.mini-section-row{cursor:default;}
      #main-table tbody tr.selected{background:#1a5276!important;color:#fff;}
      .name-input{width:100%;box-sizing:border-box;border:1px solid transparent;background:transparent;color:#e67e22;font-weight:bold;outline:none;padding:1px 2px;font-family:inherit;font-size:10px;line-height:14px;}
      .name-input:focus{border-color:#454d55;background:#1e1e24;}
      .note-input{width:100%;box-sizing:border-box;border:1px solid transparent;background:transparent;color:#dcdcdc;outline:none;padding:1px 2px;font-family:inherit;font-size:10px;line-height:14px;}
      .note-input:focus{border-color:#454d55;background:#1e1e24;}
      .qty-input{width:100%;height:18px;box-sizing:border-box;border:none;background:transparent;color:#fff;padding:1px 0;font-family:inherit;font-size:10px;text-align:center;outline:none;pointer-events:none;}
      .qty-input:disabled{opacity:1;-webkit-text-fill-color:#fff;}
      .qty-input::-webkit-outer-spin-button,.qty-input::-webkit-inner-spin-button{-webkit-appearance:none;margin:0;}
      .spec-text{font-size:8px;color:#a1a1aa;display:block;margin-top:0;font-weight:normal;line-height:11px;}
      .empty{color:#a1a1aa;text-align:center;padding:18px;}
      ::-webkit-scrollbar{width:8px;height:8px;}::-webkit-scrollbar-track{background:#1e1e24;}::-webkit-scrollbar-thumb{background:#555;border-radius:4px;}
    CSS
  end

  def self.mini_import_dialog_script
    <<-JS
#{mini_import_dialog_script_core}
#{mini_import_dialog_script_keyboard}
#{mini_import_dialog_script_rows}
#{mini_import_dialog_script_actions}
    JS
  end

  def self.mini_import_dialog_script_core
    <<-JS
        function updateTable(html) { document.getElementById('table-body').innerHTML = html; }
        function setProduct(p) { document.getElementById('prod-title').innerText = p; }
        function setModeButtons(mode) {
          document.getElementById('mode-module').classList.toggle('active', mode !== 'product');
          document.getElementById('mode-product').classList.toggle('active', mode === 'product');
        }
        function setSourceButtons(mode) {
          document.getElementById('src-view').classList.toggle('active', mode !== 'select');
          document.getElementById('src-select').classList.toggle('active', mode === 'select');
        }
        function setMode(mode) { setModeButtons(mode); sketchup.set_mode(mode); }
        function setSourceMode(mode) { setSourceButtons(mode); sketchup.set_source_mode(mode); }
    JS
  end

  def self.mini_import_dialog_script_keyboard
    <<-JS
        document.addEventListener('keydown', function(e){
          if(e.key === 'Escape'){ e.preventDefault(); e.stopPropagation(); window.miniCloseAction='close'; sketchup.close_mini(); return; }
          if((e.ctrlKey || e.metaKey) && (e.key || '').toLowerCase() === 'z'){ e.preventDefault(); e.stopPropagation(); sketchup.undo_mini(); return; }
        });
        function saveMiniPosition() {
          if(window.sketchup && sketchup.save_position) {
            sketchup.save_position(Math.round(window.screenX || window.screenLeft || 0), Math.round(window.screenY || window.screenTop || 0));
          }
        }
        window.addEventListener('beforeunload', saveMiniPosition);
    JS
  end

  def self.mini_import_dialog_script_rows
    <<-JS
        function stopMiniEvent(){ if(window.event){ window.event.stopPropagation(); } }
        function selectImportRow(row) {
          if(!row.getAttribute('data-name')) return;
          document.querySelectorAll('#main-table tbody tr.selected').forEach(function(r){ r.classList.remove('selected'); });
          row.classList.add('selected');
          sketchup.select_item(row.getAttribute('data-product') || '', row.getAttribute('data-name') || '', row.getAttribute('data-ids') || '');
        }
        function rowProduct(el) { return el.getAttribute('data-product') || ''; }
        function rowSection(el) {
          if(el.getAttribute && el.getAttribute('data-section')) return el.getAttribute('data-section') || '';
          var row = el.closest ? el.closest('tr') : null;
          return row ? (row.getAttribute('data-section') || '') : '';
        }
    JS
  end

  def self.mini_import_dialog_script_actions
    <<-JS
        function acceptImportItem(btn) { stopMiniEvent(); sketchup.accept_item(rowProduct(btn), btn.getAttribute('data-kind') || 'PK', btn.getAttribute('data-old') || '', btn.getAttribute('data-name') || '', btn.getAttribute('data-spec') || ''); }
        function applyAllStatus() { sketchup.apply_all_status(); }
        function removeExcelItem(btn) {
          stopMiniEvent();
          sketchup.remove_excel_item(
            rowProduct(btn),
            btn.getAttribute('data-kind') || 'PK',
            btn.getAttribute('data-name') || '',
            btn.getAttribute('data-spec') || ''
          );
        }
        function updateImportItem(btn) { stopMiniEvent(); sketchup.update_item(rowProduct(btn), btn.getAttribute('data-old'), btn.getAttribute('data-name'), btn.getAttribute('data-spec') || ''); }
        function keepImportItem(btn) { stopMiniEvent(); sketchup.keep_item(rowProduct(btn), btn.getAttribute('data-kind') || 'PK', btn.getAttribute('data-old') || '', btn.getAttribute('data-name') || '', btn.getAttribute('data-spec') || ''); }
        function deleteImportItem(btn) { stopMiniEvent(); sketchup.delete_item(rowProduct(btn), btn.getAttribute('data-name'), btn.getAttribute('data-ids') || ''); }
        function renameImportItem(input) {
          sketchup.rename_item(
            rowProduct(input),
            input.getAttribute('data-old') || '',
            input.value || '',
            input.getAttribute('data-target') || '',
            input.getAttribute('data-spec') || '',
            input.getAttribute('data-kind') || 'PK'
          );
        }
        function setImportNote(input) { sketchup.set_note(rowProduct(input), input.getAttribute('data-kind') || 'PK', input.getAttribute('data-name') || '', input.getAttribute('data-spec') || '', input.value); }
    JS
  end

  def self.mini_import_dialog_html
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <style>
#{mini_import_dialog_css}
      </style>
    </head>
    <body>
#{mini_import_dialog_markup_header}
#{mini_import_dialog_markup_table}
#{mini_import_dialog_markup_footer}
      <script>
#{mini_import_dialog_script}
      </script>
    </body>
    </html>
    HTML
  end

  def self.mini_import_dialog_markup_header
    <<-HTML
      <div class="header">
        <div class="title"><span id="prod-title">#{html_escape(mini_product_display_title)}</span></div>
        <div class="actions">
          <div class="mode-group">
            <button id="mode-module" class="btn btn-mode #{mini_product_mode? ? '' : 'active'}" onclick="setMode('module')">MODUL</button>
            <button id="mode-product" class="btn btn-mode #{mini_product_mode? ? 'active' : ''}" onclick="setMode('product')">S&#7842;N PH&#7848;M</button>
          </div>
          <div class="source-group">
            <button id="src-view" class="btn btn-mode #{mini_product_source_mode == 'view' ? 'active' : ''}" onclick="setSourceMode('view')">VIEW</button>
            <button id="src-select" class="btn btn-mode #{mini_product_source_mode == 'select' ? 'active' : ''}" onclick="setSourceMode('select')">SELECT</button>
          </div>
          <button class="btn btn-refresh" onclick="sketchup.refresh()">REFRESH</button>
          <button class="btn btn-refresh" onclick="sketchup.refresh_excel()">EXCEL</button>
          <button class="btn btn-refresh" onclick="sketchup.open_hud()">HUD</button>
        </div>
      </div>
    HTML
  end

  def self.mini_import_dialog_markup_table
    <<-HTML
      <div class="wrap">
        <table id="main-table">
          <thead>
            <tr>
              <th>T&#234;n h&#224;ng</th>
              <th width="60">Ghi ch&#250;</th>
              <th width="60" style="text-align:center">Tr&#7841;ng th&#225;i</th>
              <th width="50" style="text-align:center">SL</th>
              <th width="25" style="text-align:center"></th>
            </tr>
          </thead>
          <tbody id="table-body"><tr><td colspan="5" class="empty">&#272;ang n&#7841;p d&#7919; li&#7879;u...</td></tr></tbody>
        </table>
      </div>
    HTML
  end

  def self.mini_import_dialog_markup_footer
    <<-HTML
      <div class="footer">
        <button class="btn btn-apply" onclick="applyAllStatus()">APPLY ALL</button>
        <button class="btn btn-apply" onmousedown="window.miniCloseAction='ok'" onclick="sketchup.ok_accepts()">OK</button>
        <button class="btn btn-cancel" onmousedown="window.miniCloseAction='cancel'" onclick="sketchup.cancel_accepts()">CANCEL</button>
      </div>
    HTML
  end

  # === mini_import_dialog_debug.rb ===
  # --- mini_import_dialog_debug.rb ---
# MH_Thongke - Mini Import dialog debug helpers.


  def self.mini_import_debug(message)
    path = File.join(LOG_DIR, "mini_import_debug.log")
    File.open(path, "a:utf-8") { |f| f.puts("#{Time.now.strftime('%Y-%m-%d %H:%M:%S')} #{message}") }
  rescue
  end

  # === mini_import_dialog_window.rb ===
  # --- mini_import_dialog_window.rb ---
# MH_Thongke - Mini Import dialog window/lifecycle helpers.


  def self.force_show_import_mini_dialog(product_code = nil, reset_position = false)
    @mini_close_requested = true
    @mini_dlg.close if @mini_dlg && @mini_dlg.respond_to?(:close)
  rescue
  ensure
    @mini_dlg = nil
    @mini_close_requested = false
    reset_import_mini_dialog_position if reset_position && respond_to?(:reset_import_mini_dialog_position)
    show_import_mini_dialog(product_code)
  end

  def self.bring_mini_import_to_front!
    return false unless @mini_dlg

    @mini_dlg.bring_to_front rescue nil
    begin
      pos = @mini_dlg.respond_to?(:get_position) ? @mini_dlg.get_position : nil
      x = pos.is_a?(Array) ? pos[0].to_i : 80
      y = pos.is_a?(Array) ? pos[1].to_i : 80
      safe_x, safe_y, moved = respond_to?(:safe_import_mini_dialog_position) ? safe_import_mini_dialog_position(x, y) : [x, y, false]
      if moved
        @mini_dlg.set_position(safe_x, safe_y)
        save_import_mini_dialog_position(safe_x, safe_y) if respond_to?(:save_import_mini_dialog_position)
      end
    rescue
    end
    begin
      require 'fiddle'
      require 'fiddle/import'
      user32 = Fiddle.dlopen('user32')
      title = "Mini Import Accessory\0".encode("UTF-16LE")
      find_window = Fiddle::Function.new(user32['FindWindowW'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      show_window = Fiddle::Function.new(user32['ShowWindow'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
      bring_top = Fiddle::Function.new(user32['BringWindowToTop'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      set_foreground = Fiddle::Function.new(user32['SetForegroundWindow'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      set_window_pos = Fiddle::Function.new(user32['SetWindowPos'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
      hwnd = find_window.call(0, Fiddle::Pointer[title])
      if hwnd.to_i != 0
        show_window.call(hwnd, 9) # SW_RESTORE
        flags = 0x0001 | 0x0002 | 0x0040 # NOSIZE | NOMOVE | SHOWWINDOW
        set_window_pos.call(hwnd, -1, 0, 0, 0, 0, flags) # HWND_TOPMOST
        set_window_pos.call(hwnd, -2, 0, 0, 0, 0, flags) # HWND_NOTOPMOST
        bring_top.call(hwnd)
        set_foreground.call(hwnd)
      end
    rescue => e
      mini_import_debug("bring front error #{e.class}: #{e.message}") if respond_to?(:mini_import_debug)
    end
    true
  rescue
    false
  end

  def self.reset_mini_import_dialog_render_state
    if respond_to?(:reset_mini_import_refresh_state)
      reset_mini_import_refresh_state(true)
    else
      @mini_last_table_html = nil
      @mini_last_table_key = nil
      @mini_last_refresh_state_sig = nil
    end
    @mini_last_product_title = nil
    @mini_last_group_mode = nil
    @mini_last_source_mode = nil
    @mini_last_light_refresh_at = nil
    if defined?(UI) && @mini_light_refresh_timer
      UI.stop_timer(@mini_light_refresh_timer)
    end
    @mini_light_refresh_timer = nil
  rescue
    nil
  end

  def self.refresh_mini_import_context_views(refresh_hud = false)
    live_simple = defined?(MINI_IMPORT_SIMPLE_LIST_MODE) && MINI_IMPORT_SIMPLE_LIST_MODE
    refresh_import_mini_dialog(live_simple, false)
    return unless refresh_hud

    hud_on = (respond_to?(:material_hud_visible?) && material_hud_visible?) ||
             (respond_to?(:material_overlay_visible?) && material_overlay_visible?)
    refresh_import_material_hud(false, false) if hud_on
  end

  # === mini_import_dialog_show.rb ===
  # --- mini_import_dialog_show.rb ---
# MH_Thongke - Mini Import dialog show/open workflow.


  def self.show_import_mini_dialog(product_code = nil)
    @model = Sketchup.active_model
    attach_observers
    mini_import_debug("open requested product=#{product_code.inspect}") if respond_to?(:mini_import_debug)
    set_mini_group_mode(@mini_group_mode)
    mini_product_source_mode
    @mini_session_accept_keys = []
    @mini_close_action = nil
    @mini_cancel_requested_at = nil

    if product_code
      set_mini_products([product_code])
    else
      # Keep dialog startup cheap. Actual source (VIEW/SELECT) is applied after the dialog is visible.
      set_mini_products(current_mini_products)
    end

    if respond_to?(:mini_dialog_visible?) && mini_dialog_visible?
      reset_mini_import_dialog_render_state
      restore_import_mini_dialog_position
      @mini_dlg.bring_to_front rescue nil
      UI.start_timer(0.05, false) {
        live_simple = defined?(MINI_IMPORT_SIMPLE_LIST_MODE) && MINI_IMPORT_SIMPLE_LIST_MODE
        refresh_import_mini_dialog(live_simple, false)
      }
      return
    end

    old_dlg = @mini_dlg
    @mini_dlg = nil
    old_dlg.close if old_dlg rescue nil
    reset_mini_import_dialog_render_state

    html = mini_import_dialog_html

    @mini_dlg = UI::HtmlDialog.new({
      :dialog_title => "Mini Import Accessory",
      :width => 560, :height => 600,
      :style => UI::HtmlDialog::STYLE_DIALOG
    })
    @mini_dlg.set_html(html)
    @mini_dialog_opened_at = Time.now.to_f
    @mini_close_requested = false
    @mini_reopen_attempts ||= 0
    if @mini_dlg.respond_to?(:set_on_closed)
      dlg_ref = @mini_dlg
      dlg_object_id = dlg_ref.object_id
      @mini_dlg.set_on_closed {
        age = @mini_dialog_opened_at ? (Time.now.to_f - @mini_dialog_opened_at.to_f) : -1
        mini_import_debug("closed requested=#{@mini_close_requested.inspect} age=#{age}") if respond_to?(:mini_import_debug)
        puts "MH_Thongke Mini Import closed at #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}" rescue nil
        unexpected = !@mini_close_requested && @mini_dialog_opened_at && (Time.now.to_f - @mini_dialog_opened_at.to_f < 2.0)
        save_import_mini_dialog_position
        @mini_dlg = nil if @mini_dlg && @mini_dlg.object_id == dlg_object_id
        reset_mini_import_refresh_state if respond_to?(:reset_mini_import_refresh_state)
        if unexpected && @mini_reopen_attempts.to_i < 1
          @mini_reopen_attempts = @mini_reopen_attempts.to_i + 1
          UI.start_timer(0.15, false) { show_import_mini_dialog if @mini_dlg.nil? } rescue nil
        else
          @mini_reopen_attempts = 0
          detach_observers_if_idle
        end
      }
    end
    register_mini_import_dialog_callbacks
    @mini_dlg.show
    restore_import_mini_dialog_position
    bring_mini_import_to_front! if respond_to?(:bring_mini_import_to_front!)
    visible_now = respond_to?(:mini_dialog_visible?) ? mini_dialog_visible? : (@mini_dlg.visible? rescue "err")
    mini_import_debug("show called visible=#{visible_now} object=#{@mini_dlg.object_id}") if respond_to?(:mini_import_debug)
    UI.start_timer(0.08, false) {
      restore_import_mini_dialog_position
      bring_mini_import_to_front! if respond_to?(:bring_mini_import_to_front!)
      live_simple = defined?(MINI_IMPORT_SIMPLE_LIST_MODE) && MINI_IMPORT_SIMPLE_LIST_MODE
      refresh_import_mini_dialog(live_simple, false)
    }
    UI.start_timer(0.35, false) { bring_mini_import_to_front! if respond_to?(:bring_mini_import_to_front!) }
    UI.start_timer(0.6, false) {
      visible = respond_to?(:mini_dialog_visible?) ? mini_dialog_visible? : (@mini_dlg && @mini_dlg.respond_to?(:visible?) && (@mini_dlg.visible? rescue false))
      mini_import_debug("visible check visible=#{visible.inspect} object=#{@mini_dlg.object_id rescue 'nil'}") if respond_to?(:mini_import_debug)
      if !visible && @mini_reopen_attempts.to_i < 1
        @mini_reopen_attempts = @mini_reopen_attempts.to_i + 1
        force_show_import_mini_dialog(product_code)
      end
    }
  rescue => e
    mini_import_debug("open error #{e.class}: #{e.message}") if respond_to?(:mini_import_debug)
    puts "MH_Thongke Mini Import open error: #{e.class}: #{e.message}"
    puts e.backtrace.first(20).join("\n") rescue nil
    UI.messagebox("Mini Import loi khi mo:\n#{e.class}: #{e.message}") rescue nil
  end

  # === mini_import_dialog.rb ===
  # --- mini_import_dialog.rb ---
# MH_Thongke - Mini Import dialog entrypoint.
#
# Logic is split into:
# - mini_import_dialog_debug.rb
# - mini_import_dialog_window.rb
# - mini_import_dialog_show.rb
end

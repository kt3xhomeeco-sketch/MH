# encoding: utf-8
# MH_PK_Addon — bang setting HUD (HtmlDialog): danh sach ten PK khong can hien leader.
# Luu vao model attribute, so khop theo ten normalize (bo dau, khong phan biet hoa thuong).

require 'json'

module MH_PK_Addon
  HUD_HIDDEN_FILE = File.join(ROOT_DIR, 'hud_hidden_names.json').freeze
  HUD_LABEL_COLOR_FILE = File.join(ROOT_DIR, 'hud_label_colors.json').freeze

  # Danh sach ten PK an: luu ra FILE (giu qua cac lan mo SketchUp/model khac).
  # Fallback doc tu model attr cu neu chua co file.
  def self.hud_hidden_names
    return @hud_hidden_cache if @hud_hidden_cache

    list =
      if File.file?(HUD_HIDDEN_FILE)
        JSON.parse(File.read(HUD_HIDDEN_FILE)) rescue []
      else
        raw = model.get_attribute(ACCESSORY_DICT, 'hud_hidden_names', '').to_s
        raw.empty? ? [] : (JSON.parse(raw) rescue [])
      end
    @hud_hidden_cache = Array(list).map(&:to_s).reject(&:empty?)
  rescue
    []
  end

  def self.save_hud_hidden_names(names)
    list = Array(names).map { |n| n.to_s.strip }.reject(&:empty?).uniq
    begin
      File.write(HUD_HIDDEN_FILE, JSON.pretty_generate(list))
    rescue => e
      dbg("MH_PK_Addon save hidden names error: #{e.message}") if respond_to?(:dbg)
    end
    model.set_attribute(ACCESSORY_DICT, 'hud_hidden_names', JSON.generate(list)) rescue nil
    @hud_hidden_cache = list
    @hud_hidden_norm_cache = nil
    list
  rescue
    []
  end

  def self.hud_hidden_norm_tokens
    @hud_hidden_norm_cache ||= hud_hidden_names.map { |n| search_text(n).strip }.reject(&:empty?)
  end

  def self.hud_hidden_label?(label)
    tokens = hud_hidden_norm_tokens
    return false if tokens.empty?

    norm = search_text(label).strip
    return false if norm.empty?

    tokens.any? { |token| norm.include?(token) }
  rescue
    false
  end

  def self.hud_label_color_rules
    return @hud_label_color_cache if @hud_label_color_cache

    list =
      if File.file?(HUD_LABEL_COLOR_FILE)
        JSON.parse(File.read(HUD_LABEL_COLOR_FILE)) rescue []
      else
        raw = model.get_attribute(ACCESSORY_DICT, 'hud_label_color_rules', '').to_s
        raw.empty? ? [] : (JSON.parse(raw) rescue [])
      end
    @hud_label_color_cache = Array(list).filter_map { |rule| normalize_hud_label_color_rule(rule) }
  rescue
    []
  end

  def self.normalize_hud_label_color_rule(rule)
    hash = rule.is_a?(Hash) ? rule : {}
    text = (hash['text'] || hash[:text]).to_s.strip
    color = (hash['color'] || hash[:color]).to_s.strip
    return nil if text.empty?

    color = "##{color}" unless color.start_with?('#')
    return nil unless color =~ /\A#[0-9a-fA-F]{6}\z/

    { 'color' => color.upcase, 'text' => text }
  rescue
    nil
  end

  def self.save_hud_label_color_rules(rules)
    list = Array(rules).filter_map { |rule| normalize_hud_label_color_rule(rule) }
    begin
      File.write(HUD_LABEL_COLOR_FILE, JSON.pretty_generate(list))
    rescue => e
      dbg("MH_PK_Addon save label colors error: #{e.message}") if respond_to?(:dbg)
    end
    model.set_attribute(ACCESSORY_DICT, 'hud_label_color_rules', JSON.generate(list)) rescue nil
    @hud_label_color_cache = list
    @hud_label_color_norm_cache = nil
    list
  rescue
    []
  end

  def self.hex_to_sketchup_color(hex, alpha = 255)
    value = hex.to_s.strip.sub(/\A#/, '')
    return nil unless value =~ /\A[0-9a-fA-F]{6}\z/

    Sketchup::Color.new(value[0, 2].to_i(16), value[2, 2].to_i(16), value[4, 2].to_i(16), alpha.to_i)
  rescue
    nil
  end

  def self.darker_hud_color(hex, factor = 0.62, alpha = 255)
    color = hex_to_sketchup_color(hex, alpha)
    return nil unless color

    Sketchup::Color.new((color.red * factor).to_i, (color.green * factor).to_i, (color.blue * factor).to_i, alpha.to_i)
  rescue
    nil
  end

  def self.hud_label_color_for(label)
    rules = hud_label_color_rules
    return nil if rules.empty?

    norm = search_text(label).strip
    return nil if norm.empty?

    rule = rules.find do |item|
      token = search_text(item['text']).strip
      !token.empty? && norm.include?(token)
    end
    return nil unless rule

    fill = hex_to_sketchup_color(rule['color'], 235)
    border = darker_hud_color(rule['color'], 0.58, 255)
    text = darker_hud_color(rule['color'], 0.22, 255)
    { fill: fill, border: border, text: text, rule: rule }
  rescue
    nil
  end

  # Cac label dang co trong model (PK + phu kien ABF) de tick chon nhanh.
  def self.hud_all_leader_labels
    Leaders.new.collect_markers.map { |m| m[:label].to_s.strip }.reject(&:empty?).uniq.sort
  rescue
    []
  end

  # O nhap ten nho (HtmlDialog) — bat tron ban phim de khong dinh shortcut SketchUp,
  # go duoc tieng Viet co dau. Live-sync tung phim ve tool de ve preview tren nhan.
  def self.show_edit_box(initial, on_change: nil, on_commit: nil, on_cancel: nil)
    begin
      @edit_box_dlg.close if @edit_box_dlg && @edit_box_dlg.visible?
    rescue
      nil
    end

    committed = false
    dlg = UI::HtmlDialog.new(
      dialog_title: 'Nhập tên phụ kiện',
      width: 400, height: 92,
      style: UI::HtmlDialog::STYLE_UTILITY,
      resizable: false
    )
    html = <<~HTML
      <!DOCTYPE html>
      <html><head><meta charset="utf-8">
      <style>
        body { font-family: Arial; font-size: 13px; margin: 0; padding: 10px; background: #fffbe8; }
        input { width: 100%; box-sizing: border-box; padding: 7px 8px; font-size: 13px;
                border: 2px solid #eb9620; border-radius: 4px; outline: none; }
        .hint { color: #999; font-size: 10px; margin-top: 5px; }
      </style></head>
      <body>
        <input id="t" type="text" value="#{html_escape(initial.to_s)}" autofocus>
        <div class="hint">Enter = áp dụng · Esc = hủy · "Tên - spec" để tách spec</div>
        <script>
          var inp = document.getElementById('t');
          inp.focus(); inp.select();
          inp.addEventListener('input', function() { sketchup.txt(inp.value); });
          inp.addEventListener('keydown', function(e) {
            if (e.key === 'Enter') { e.preventDefault(); sketchup.ok(inp.value); }
            else if (e.key === 'Escape') { e.preventDefault(); sketchup.cancel_edit(); }
          });
        </script>
      </body></html>
    HTML
    dlg.set_html(html)
    dlg.add_action_callback('txt') { |_ctx, value| on_change.call(value.to_s) if on_change }
    dlg.add_action_callback('ok') do |_ctx, value|
      committed = true
      on_commit.call(value.to_s) if on_commit
      dlg.close rescue nil
    end
    dlg.add_action_callback('cancel_edit') { |_ctx| dlg.close rescue nil }
    dlg.set_on_closed do
      @edit_box_dlg = nil
      on_cancel.call if on_cancel && !committed
    end
    dlg.center rescue nil
    dlg.show
    @edit_box_dlg = dlg
  rescue => e
    UI.messagebox("Khong mo duoc o nhap: #{e.message}")
    nil
  end

  def self.close_edit_box
    @edit_box_dlg.close if @edit_box_dlg && @edit_box_dlg.visible?
  rescue
    nil
  end

  def self.show_hud_settings_dialog(&on_change)
    if @hud_settings_dlg && @hud_settings_dlg.visible?
      @hud_settings_dlg.bring_to_front rescue nil
      return @hud_settings_dlg
    end

    hidden = hud_hidden_names
    color_rules = hud_label_color_rules
    labels = hud_all_leader_labels
    hidden_set = hidden.map { |n| search_text(n).strip }

    chips = labels.map do |label|
      norm = search_text(label).strip
      checked = hidden_set.any? { |token| norm.include?(token) } ? ' checked' : ''
      esc = html_escape(label)
      "<label class='chip'><input type='checkbox' value=\"#{esc}\"#{checked}><span>#{esc}</span></label>"
    end.join("\n")

    color_rows = color_rules.map do |rule|
      color = html_escape(rule['color'].to_s)
      text = html_escape(rule['text'].to_s)
      <<~ROW
        <tr class="color-rule">
          <td><input type="color" class="rule-color" value="#{color}"></td>
          <td><input type="text" class="rule-text" value="#{text}" placeholder="VD: bản lề, ray, tay nắm"></td>
          <td><button class="small danger" onclick="removeRule(this)">Xóa</button></td>
        </tr>
      ROW
    end.join("\n")

    html = <<~HTML
      <!DOCTYPE html>
      <html><head><meta charset="utf-8">
      <style>
        body { font-family: Arial, sans-serif; font-size: 12px; margin: 0; padding: 12px;
               background: #f5f6f8; color: #333; }
        h3 { margin: 0 0 4px 0; font-size: 13px; }
        p.hint { margin: 0 0 8px 0; color: #888; font-size: 11px; }
        .tabs { display: flex; gap: 6px; margin-bottom: 10px; }
        .tab-btn { flex: 1; border: 1px solid #b9bec8; background: #fff; color: #444; }
        .tab-btn.active { background: #49498c; color: #fff; border-color: #3a3a73; }
        .tab-panel { display: none; }
        .tab-panel.active { display: block; }
        .chips { max-height: 220px; overflow-y: auto; background: #fff; border: 1px solid #ccc;
                 border-radius: 4px; padding: 6px; margin-bottom: 10px; }
        .chip { display: block; padding: 3px 4px; border-radius: 3px; cursor: pointer; }
        .chip:hover { background: #e6eefb; }
        .chip input { vertical-align: middle; margin-right: 6px; }
        textarea { width: 100%; height: 90px; box-sizing: border-box; border: 1px solid #ccc;
                   border-radius: 4px; font-family: Arial; font-size: 12px; padding: 6px; resize: vertical; }
        .btns { margin-top: 10px; text-align: right; }
        button { padding: 6px 16px; border-radius: 4px; border: 1px solid #aaa; cursor: pointer;
                 background: #fff; font-size: 12px; margin-left: 6px; }
        button.primary { background: #49498c; border-color: #3a3a73; color: #fff; }
        button.small { padding: 4px 8px; margin-left: 0; font-size: 11px; }
        button.danger { color: #9a2f2f; border-color: #d8a0a0; }
        button:hover { filter: brightness(1.08); }
        table { width: 100%; border-collapse: collapse; background: #fff; border: 1px solid #ccc; }
        th, td { border-bottom: 1px solid #e2e2e2; padding: 5px; text-align: left; }
        th { background: #eceef4; font-weight: bold; }
        td:first-child { width: 58px; }
        td:last-child { width: 54px; }
        input.rule-color { width: 44px; height: 26px; padding: 0; border: 1px solid #aaa; }
        input.rule-text { width: 100%; box-sizing: border-box; padding: 5px 6px; border: 1px solid #ccc; border-radius: 3px; }
        .rule-actions { margin: 8px 0 10px; }
      </style></head>
      <body>
        <div class="tabs">
          <button class="tab-btn active" onclick="showTab('hidden', this)">Ẩn nhãn</button>
          <button class="tab-btn" onclick="showTab('colors', this)">Màu nhãn</button>
        </div>

        <div id="tab-hidden" class="tab-panel active">
          <h3>Ẩn phụ kiện khỏi leader</h3>
          <p class="hint">Tick phụ kiện cần ẩn, hoặc gõ thêm tên (mỗi dòng 1 tên, so khớp không dấu, chứa là ẩn).</p>
          <div class="chips">#{chips.empty? ? '<i>Chưa có phụ kiện nào trong model</i>' : chips}</div>
          <textarea id="extra" placeholder="Tên khác cần ẩn...">#{html_escape(hidden.join("\n"))}</textarea>
        </div>

        <div id="tab-colors" class="tab-panel">
          <h3>Màu nhãn theo tên</h3>
          <p class="hint">Cột 1 chọn màu. Cột 2 nhập text; nhãn nào chứa text này sẽ dùng màu đó.</p>
          <table>
            <thead><tr><th>Màu sắc</th><th>Text include</th><th></th></tr></thead>
            <tbody id="colorRules">
              #{color_rows.empty? ? '' : color_rows}
            </tbody>
          </table>
          <div class="rule-actions">
            <button onclick="addRule()">Thêm dòng</button>
          </div>
        </div>

        <div class="btns">
          <button onclick="sketchup.close_settings()">Đóng</button>
          <button class="primary" onclick="save()">Lưu</button>
        </div>
        <script>
          function showTab(name, btn) {
            document.querySelectorAll('.tab-panel').forEach(function(el) { el.classList.remove('active'); });
            document.querySelectorAll('.tab-btn').forEach(function(el) { el.classList.remove('active'); });
            document.getElementById('tab-' + name).classList.add('active');
            btn.classList.add('active');
          }
          function addRule(color, text) {
            var tbody = document.getElementById('colorRules');
            var tr = document.createElement('tr');
            tr.className = 'color-rule';
            tr.innerHTML =
              '<td><input type="color" class="rule-color" value="' + (color || '#FFE08A') + '"></td>' +
              '<td><input type="text" class="rule-text" value="' + (text || '') + '" placeholder="VD: bản lề, ray, tay nắm"></td>' +
              '<td><button class="small danger" onclick="removeRule(this)">Xóa</button></td>';
            tbody.appendChild(tr);
          }
          function removeRule(btn) {
            var tr = btn.closest('tr');
            if (tr) tr.remove();
          }
          function save() {
            var names = [];
            document.querySelectorAll('.chip input:checked').forEach(function(cb) { names.push(cb.value); });
            document.getElementById('extra').value.split('\\n').forEach(function(line) {
              line = line.trim();
              if (line && names.indexOf(line) < 0) names.push(line);
            });
            var colors = [];
            document.querySelectorAll('#colorRules tr').forEach(function(tr) {
              var color = tr.querySelector('.rule-color').value;
              var text = tr.querySelector('.rule-text').value.trim();
              if (text) colors.push({ color: color, text: text });
            });
            sketchup.save_settings(JSON.stringify({ hidden: names, colors: colors }));
          }
        </script>
      </body></html>
    HTML

    dlg = UI::HtmlDialog.new(
      dialog_title: 'MH PK HUD — Setting',
      width: 430, height: 520,
      style: UI::HtmlDialog::STYLE_DIALOG,
      resizable: true
    )
    dlg.set_html(html)
    dlg.add_action_callback('save_settings') do |_ctx, payload_json|
      payload = JSON.parse(payload_json.to_s) rescue {}
      if payload.is_a?(Array)
        save_hud_hidden_names(payload)
      else
        save_hud_hidden_names(payload['hidden'] || [])
        save_hud_label_color_rules(payload['colors'] || [])
      end
      on_change.call if on_change
      dlg.close rescue nil
    end
    dlg.add_action_callback('close_settings') do |_ctx|
      dlg.close rescue nil
    end
    dlg.set_on_closed { @hud_settings_dlg = nil }
    dlg.show
    @hud_settings_dlg = dlg
  rescue => e
    UI.messagebox("Khong mo duoc setting: #{e.message}")
    nil
  end
end

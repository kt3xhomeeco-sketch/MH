# encoding: utf-8

module MH_PK_Addon
  class << self
    remove_method :show_suggested_dialog if method_defined?(:show_suggested_dialog)
    remove_method :build_suggested_dialog_html if method_defined?(:build_suggested_dialog_html)
  end

  def self.show_dialog
    show_basic_input
  end

  def self.excel_choice_label(row, _index = nil)
    name = (row[:name] || row['name'] || row[:suggestion_name] || row['suggestion_name']).to_s.strip
    name.empty? ? 'Phu kien' : name
  rescue
    'Phu kien'
  end

  def self.excel_choices_for_target(target)
    product_code = target ? detect_product_code(target) : ''
    rows = product_code.to_s.empty? ? [] : thongke_all_excel_pk_rows(product_code)
    # Rieng dialog MH PK Addon: dong Excel da co marker trong model van hien,
    # nhung co dau tick de nhan biet da add.
    rows = Array(rows).map do |source|
      row = source.is_a?(Hash) ? source.dup : source
      next row unless row.is_a?(Hash)

      raw_value = row[:raw] || row['raw']
      raw = raw_value.is_a?(Hash) ? raw_value : row
      spec = row[:spec].to_s.strip
      spec = (raw[:spec] || raw['spec']).to_s.strip if spec.empty?
      section = (raw[:section] || raw['section']).to_s.strip
      row[:excel_key] = trace_build_excel_match_key(
        product_code: product_code, kind: 'PK',
        excel_name: excel_choice_label(row), spec: spec, section: section
      )
      row
    end
    apply_tick_state(rows, product_code)
    choices = []
    by_label = {}
    used_labels = Hash.new(0)
    rows.each_with_index do |row, index|
      label = excel_choice_label(row, index)
      next if label.to_s.empty?

      used_labels[label] += 1
      display_label = row[:ticked] ? "#{label} ✓" : label
      choice_label = display_label + (' ' * (used_labels[label] - 1))
      choices << choice_label
      by_label[choice_label] = row
    end
    { product_code: product_code, rows: rows, choices: choices, by_label: by_label }
  rescue
    { product_code: '', rows: [], choices: [], by_label: {} }
  end

  def self.inputbox_dropdown_list(values, preserve_duplicates = false)
    items =
      if preserve_duplicates
        Array(values).map(&:to_s).reject { |value| value.strip.empty? }
      else
        Array(values).map { |value| value.to_s.strip }.reject(&:empty?).uniq
      end
    items.empty? ? '' : ([''] + items).join('|')
  end

  def self.show_basic_input
    if @main_dialog && @main_dialog.visible?
      @main_dialog.bring_to_front rescue nil
      refresh_main_dialog_selection(true)
      return @main_dialog
    end

    library_json = JSON.generate(accessory_names_from_file(default_xlsx_path)).gsub('</', '<\\/')
    html = <<~HTML
      <!DOCTYPE html><html><head><meta charset="utf-8">
      <style>
        * { box-sizing: border-box; }
        body { margin: 0; padding: 7px; font: 10px Arial, sans-serif; color: #30333a; background: #f4f5f8; overflow-y: auto; }
        .field { margin-bottom: 4px; }
        label { display: block; margin-bottom: 1px; font-weight: bold; }
        input, select { width: 100%; height: 22px; padding: 2px 5px; border: 1px solid #bcc1cb;
                        border-radius: 3px; background: #fff; font: inherit; }
        .row { display: grid; grid-template-columns: 1fr 66px; gap: 5px; }
        .result { min-height: 22px; padding: 4px 6px; margin-top: 4px; border-radius: 3px; display: none; line-height: 12px; }
        .result.ok { display: block; color: #17652c; background: #eaf7ee; border: 1px solid #a8d6b4; }
        .result.error { display: block; color: #8b2727; background: #fff0f0; border: 1px solid #e1abab; }
        .footer { display: flex; justify-content: flex-end; gap: 5px; margin-top: 4px; }
        button { padding: 4px 10px; border: 1px solid #343573; border-radius: 3px; color: #fff;
                 background: #49498c; cursor: pointer; font: bold 10px Arial, sans-serif; }
        button.secondary { color: #343573; background: #fff; }
        button:disabled { opacity: .55; cursor: default; }
      </style></head><body>
        <div class="field"><label>Tên phụ kiện nhập tay</label><input id="manualName" type="text" placeholder="Ưu tiên cao nhất"></div>
        <div class="field"><label id="excelLabel">Phụ kiện Excel theo sản phẩm</label><select id="excelChoice"><option value="-1">— Chưa có —</option></select></div>
        <div class="field"><label>Chọn từ thư viện</label><select id="libraryChoice"><option value="">— Không chọn —</option></select></div>
        <div class="row">
          <div class="field"><label>Hình dạng hiện tại</label><input id="shapeInfo" value="#{html_escape(default_shape)}" disabled></div>
          <div class="field"><label>Số lượng</label><input id="qty" type="number" min="1" step="1" value="1"></div>
        </div>
        <div id="result" class="result"></div>
        <div class="footer">
          <button class="secondary" onclick="sketchup.open_settings()">SETTING</button>
          <button id="updateButton" class="secondary" onclick="updateSize()">UPDATE SIZE</button>
          <button id="addButton" onclick="submitForm()">ADD</button>
        </div>
        <script>
          const libraryNames = #{library_json};
          const lib = document.getElementById('libraryChoice');
          libraryNames.forEach(function(name) { const o=document.createElement('option'); o.value=name; o.textContent=name; lib.appendChild(o); });

          function updateSelection(data) {
            document.getElementById('excelLabel').textContent=data.product_code ?
              'Phụ kiện Excel ('+data.product_code+')' : 'Phụ kiện Excel theo sản phẩm';
            const select=document.getElementById('excelChoice');
            select.innerHTML='';
            const blank=document.createElement('option'); blank.value='-1'; blank.textContent='— Không chọn —'; select.appendChild(blank);
            data.excel_choices.forEach(function(name,index) { const o=document.createElement('option'); o.value=String(index); o.textContent=name; select.appendChild(o); });
            select.value='-1';
          }
          function submitForm() {
            const button=document.getElementById('addButton'); button.disabled=true; button.textContent='ĐANG XỬ LÝ...';
            sketchup.add_pk(JSON.stringify({
              action:'add',
              manual_name:document.getElementById('manualName').value,
              excel_index:parseInt(document.getElementById('excelChoice').value,10),
              library_name:document.getElementById('libraryChoice').value,
              qty:parseInt(document.getElementById('qty').value,10)
            }));
          }
          function updateSize() {
            const button=document.getElementById('updateButton'); button.disabled=true; button.textContent='ĐANG UPDATE...';
            sketchup.add_pk(JSON.stringify({ action:'update_size' }));
          }
          function setResult(message, ok) {
            const box=document.getElementById('result'); box.textContent=message; box.className='result '+(ok?'ok':'error');
            const button=document.getElementById('addButton'); button.disabled=false; button.textContent='ADD';
            const updateButton=document.getElementById('updateButton'); updateButton.disabled=false; updateButton.textContent='UPDATE SIZE';
          }
        </script>
      </body></html>
    HTML

    dlg = UI::HtmlDialog.new(
      dialog_title: 'MH PK Addon', width: 390, height: 275,
      style: UI::HtmlDialog::STYLE_DIALOG, resizable: true,
      preferences_key: 'MH_PK_Addon_MainDialog_CompactV3'
    )
    dlg.set_html(html)
    dlg.add_action_callback('add_pk') { |_ctx, payload| handle_main_dialog_action(dlg, payload) }
    dlg.add_action_callback('open_settings') do |_ctx|
      show_settings_input
      refresh_main_dialog_selection(true)
    end
    dlg.set_on_closed do
      UI.stop_timer(@main_dialog_timer) if @main_dialog_timer
      @main_dialog_timer = nil
      @main_dialog = nil
      @main_dialog_selection_sig = nil
      @main_dialog_raw_selection_sig = nil
    end
    @main_dialog = dlg
    dlg.show
    @main_dialog_timer = UI.start_timer(1.0, true) { refresh_main_dialog_selection }
    UI.start_timer(0.1, false) { refresh_main_dialog_selection(true) }
    dlg
  rescue => e
    UI.messagebox(e.message)
  end

  def self.main_dialog_raw_selection_signature
    mdl = model
    selected_ids = mdl.selection.to_a.select { |e|
      e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    }.map { |e| e.persistent_id rescue e.entityID }.sort
    path_ids = Array(mdl.active_path).select { |e|
      e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    }.map { |e| e.persistent_id rescue e.entityID }
    [selected_ids, path_ids]
  rescue
    [[], []]
  end

  def self.main_dialog_selection_payload
    targets = selected_targets
    target = selected_target
    excel_data = excel_choices_for_target(target)
    {
      ok: !!target, status: '',
      product_code: product_code_base(excel_data[:product_code]),
      excel_choices: excel_data[:choices],
      signature: targets.map { |item| item.persistent_id rescue item.entityID }.sort
    }
  rescue => e
    { ok: false, status: "Lỗi selection: #{e.message}", product_code: '', excel_choices: [], signature: [] }
  end

  def self.refresh_main_dialog_selection(force = false)
    return unless @main_dialog && @main_dialog.visible?

    raw_signature = main_dialog_raw_selection_signature
    return if !force && raw_signature == @main_dialog_raw_selection_sig

    @main_dialog_raw_selection_sig = raw_signature
    payload = main_dialog_selection_payload
    signature = [payload[:signature], payload[:product_code], payload[:excel_choices]]
    return if !force && signature == @main_dialog_selection_sig

    @main_dialog_selection_sig = signature
    @main_dialog.execute_script("updateSelection(#{JSON.generate(payload)})")
  rescue
    nil
  end

  def self.main_dialog_result(dialog, message, ok)
    dialog.execute_script("setResult(#{JSON.generate(message.to_s)}, #{ok ? 'true' : 'false'})") if dialog && dialog.visible?
  rescue
    nil
  end

  def self.handle_main_dialog_action(dialog, payload_json)
    input = JSON.parse(payload_json.to_s) rescue {}
    action = input['action'].to_s

    case action
    when 'settings'
      show_settings_input
      main_dialog_result(dialog, 'Đã đóng/mở bảng Setting. Bảng Add PK vẫn đang hoạt động.', true)
      refresh_main_dialog_selection(true)
      return
    when 'fix'
      count = fix_lost_abf_statistics
      main_dialog_result(dialog, "Đã fix #{count} PK bị mất thống kê ABF.", true)
      return
    when 'register'
      count = register_selected_as_pk_statistics
      main_dialog_result(dialog, "Đã đăng ký #{count} PK đang chọn để thống kê.", true)
      return
    when 'exclude'
      count = exclude_selected_accessories_from_nesting
      main_dialog_result(dialog, "Đã bỏ nesting cho #{count} phụ kiện đang chọn.", true)
      return
    when 'update_size'
      result = update_marker_sizes(default_size_mm)
      main_dialog_result(dialog, "Đã update kích thước #{result[:count]}/#{result[:total]} marker PK theo size #{result[:size_mm]} mm.", true)
      return
    end

    target = selected_target
    excel_data = excel_choices_for_target(target)
    excel_index = input['excel_index'].to_i
    excel_row = excel_index >= 0 ? excel_data[:rows][excel_index] : nil
    manual_name = input['manual_name'].to_s.strip
    library_name = input['library_name'].to_s.strip
    excel_name = excel_row ? (excel_row[:name] || excel_row['name'] || excel_row[:suggestion_name] || excel_row['suggestion_name']).to_s.strip : ''
    final_name = manual_name.empty? ? (excel_name.empty? ? library_name : excel_name) : manual_name
    raise 'Chưa nhập hoặc chọn phụ kiện.' if final_name.empty?

    qty = input['qty'].to_i
    qty = (excel_row[:qty] || excel_row['qty']).to_i if qty <= 0 && excel_row
    qty = 1 if qty <= 0
    data = {
      name: final_name, qty: qty,
      spec: excel_row ? (excel_row[:spec] || excel_row['spec']).to_s.strip : '',
      section: excel_row && (excel_row[:raw] || excel_row['raw']).is_a?(Hash) ?
        ((excel_row[:raw] || excel_row['raw'])[:section] || (excel_row[:raw] || excel_row['raw'])['section']).to_s.strip : '',
      excel_key: excel_row ? excel_row[:excel_key].to_s : '',
      note: excel_row ? (excel_row[:note] || excel_row['note']).to_s.strip : '',
      product_code: excel_row ? (excel_row[:product_code] || excel_row['product_code'] || excel_data[:product_code]).to_s.strip : excel_data[:product_code].to_s.strip,
      ten_sp: target ? detect_ten_sp(target) : '',
      shape: default_shape, size_mm: default_size_mm
    }

    if action == 'add_length'
      result = add_length_accessory_to_selection(data)
      message = "Đã thêm #{result[:count]} PK đo dài vào #{result[:targets]} object — tổng #{result[:length_mm].round(1)} mm."
    else
      result = add_accessory_to_selection(data)
      message = "Đã thêm #{result[:count]} PK vào #{result[:targets]} object. Bảng vẫn mở để add tiếp."
    end
    main_dialog_result(dialog, message, true)
    refresh_main_dialog_selection(true)
  rescue => e
    main_dialog_result(dialog, e.message, false)
  end

  def self.show_settings_input
    prompts = ['Duong dan thu vien (.xlsx/.xls/.csv)', 'Hinh dang PK (text = chu single-line)', 'Kich thuoc PK / chieu cao chu (mm)', 'Mat dat PK', 'Tag cho PK (de trong = Untagged)']
    face_mode_list = FACE_MODE_LABELS.values.join('|')
    defaults = [default_xlsx_path, default_shape, default_size_mm.to_s, face_mode_label, default_tag_name]
    lists = ['', 'square|circle|triangle|text', '', face_mode_list, '']

    input = UI.inputbox(prompts, defaults, lists, 'MH PK Addon - Setting')
    return unless input

    path = input[0].to_s.strip
    shape = input[1].to_s.strip.downcase
    size_mm = input[2].to_f
    face_mode = normalize_face_mode(input[3])
    tag_name = input[4].to_s.strip

    if !path.empty? && !File.file?(path)
      UI.messagebox('Duong dan thu vien khong ton tai.')
      return
    end

    save_settings(path: path, shape: shape, size_mm: size_mm, face_mode: face_mode, tag_name: tag_name)
    count = accessory_names_from_file(default_xlsx_path).length
    UI.messagebox("Da luu setting. Thu vien hien co #{count} phu kien.")
  rescue => e
    UI.messagebox(e.message)
  end
end

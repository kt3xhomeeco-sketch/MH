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
    choices = []
    by_label = {}
    used_labels = Hash.new(0)
    rows.each_with_index do |row, index|
      label = excel_choice_label(row, index)
      next if label.to_s.empty?

      used_labels[label] += 1
      choice_label = label + (' ' * (used_labels[label] - 1))
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
    target = selected_target
    excel_data = excel_choices_for_target(target)
    excel_list = inputbox_dropdown_list(excel_data[:choices], true)

    names = accessory_names_from_file(default_xlsx_path)
    name_list = inputbox_dropdown_list(names)
    product_label = product_code_base(excel_data[:product_code])
    excel_prompt = product_label.to_s.empty? ? 'Chon vat lieu/PK tu Excel theo SP' : "Chon vat lieu/PK tu Excel (#{product_label})"
    prompts = ['Tac vu', 'Ten phu kien (nhap tay)', excel_prompt, 'Chon ten tu thu vien', 'So luong']

    defaults = ['Add PK', '', '', '', '1']
    lists = ['Add PK|Add PK theo canh dai nhat|Dang ky PK dang chon de thong ke|Bo nesting PK dang chon|Fix PK mat thong ke ABF|Mo Setting', '', excel_list, name_list, '']

    input = UI.inputbox(prompts, defaults, lists, 'MH PK Addon - Input')
    return unless input

    action = input[0].to_s.strip
    @last_inputbox_values = nil

    if action == 'Mo Setting'
      show_settings_input
      return
    end
    if action == 'Fix PK mat thong ke ABF'
      count = fix_lost_abf_statistics
      UI.messagebox("Da fix #{count} PK bi mat thong ke ABF.")
      return
    end
    if action == 'Dang ky PK dang chon de thong ke'
      count = register_selected_as_pk_statistics
      UI.messagebox("Da dang ky #{count} PK dang chon de thong ke.")
      return
    end
    if action == 'Bo nesting PK dang chon'
      count = exclude_selected_accessories_from_nesting
      UI.messagebox("Da bo nesting cho #{count} phu kien dang chon.")
      return
    end

    status = target_status
    unless status[:ok]
      UI.messagebox(status[:text])
      return
    end

    manual_name = input[1].to_s.strip
    excel_choice = input[2].to_s
    library_name = input[3].to_s.strip
    excel_row = excel_data[:by_label][excel_choice] || excel_data[:by_label][excel_choice.strip]
    excel_name = excel_row ? (excel_row[:name] || excel_row['name'] || excel_row[:suggestion_name] || excel_row['suggestion_name']).to_s.strip : ''
    final_name =
      if !manual_name.empty?
        manual_name
      elsif !excel_name.empty?
        excel_name
      elsif !library_name.empty?
        library_name
      else
        ''
      end
    if final_name.empty?
      UI.messagebox('Chua nhap hoac chon phu kien.')
      return
    end

    qty = input[4].to_i
    qty = (excel_row[:qty] || excel_row['qty']).to_i if qty <= 0 && excel_row
    qty = 1 if qty <= 0

    data = {
      name: final_name,
      qty: qty,
      note: excel_row ? (excel_row[:note] || excel_row['note']).to_s.strip : '',
      product_code: excel_row ? (excel_row[:product_code] || excel_row['product_code'] || excel_data[:product_code]).to_s.strip : excel_data[:product_code].to_s.strip,
      ten_sp: target ? detect_ten_sp(target) : '',
      shape: default_shape,
      size_mm: default_size_mm
    }

    if action == 'Add PK theo canh dai nhat'
      result = add_length_accessory_to_selection(data)
      UI.messagebox("Da them #{result[:count]} PK do dai vao #{result[:targets]} object. Tong dai #{result[:length_mm].round(1)} mm.")
    else
      result = add_accessory_to_selection(data)
      UI.messagebox("Da them #{result[:count]} PK vao #{result[:targets]} object dang chon.")
    end
  rescue => e
    UI.messagebox(e.message)
  end

  def self.show_settings_input
    prompts = ['Duong dan thu vien (.xlsx/.xls/.csv)', 'Hinh dang PK', 'Kich thuoc PK (mm)', 'Mat dat PK']
    face_mode_list = FACE_MODE_LABELS.values.join('|')
    defaults = [default_xlsx_path, default_shape, default_size_mm.to_s, face_mode_label]
    lists = ['', 'square|circle|triangle', '', face_mode_list]

    input = UI.inputbox(prompts, defaults, lists, 'MH PK Addon - Setting')
    return unless input

    path = input[0].to_s.strip
    shape = input[1].to_s.strip.downcase
    size_mm = input[2].to_f
    face_mode = normalize_face_mode(input[3])

    if !path.empty? && !File.file?(path)
      UI.messagebox('Duong dan thu vien khong ton tai.')
      return
    end

    save_settings(path: path, shape: shape, size_mm: size_mm, face_mode: face_mode)
    count = accessory_names_from_file(default_xlsx_path).length
    UI.messagebox("Da luu setting. Thu vien hien co #{count} phu kien.")
  rescue => e
    UI.messagebox(e.message)
  end
end

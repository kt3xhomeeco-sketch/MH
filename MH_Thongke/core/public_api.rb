# encoding: utf-8
# MH_Thongke public API for other MH apps.

module MH_Thongke
  def self.public_dup_row(row)
    row.is_a?(Hash) ? row.dup : row
  rescue
    row
  end

  def self.public_rows(rows)
    Array(rows).select { |row| row.is_a?(Hash) }.map { |row| public_dup_row(row) }
  rescue
    []
  end

  def self.import_excel_data_snapshot(product_code = nil)
    rows = @imported_excel_data
    product_query = product_code && !product_code.to_s.strip.empty?

    # Product-specific consumers (notably SuperImp HUD) can run before the
    # Thongke dialogs are opened, or immediately after switching models.
    # Sync the lightweight JSON snapshot first so they neither see an empty
    # in-memory array nor stale rows from the previously active project.
    if respond_to?(:load_import_excel_snapshot_only) && ((!rows || rows.empty?) || product_query)
      load_import_excel_snapshot_only
      rows = @imported_excel_data
    end

    if product_query
      if respond_to?(:mini_excel_items)
        return public_rows(mini_excel_items(product_code, false))
      end

      return public_rows(rows).select do |row|
        public_product_match?(public_row_product(row), product_code)
      end
    end

    public_rows(rows)
  rescue => e
    puts "MH_Thongke import_excel_data_snapshot error: #{e.class}: #{e.message}" rescue nil
    []
  end

  def self.import_excel_cache_sources
    return [] unless respond_to?(:load_import_excel_cache_store)

    store = load_import_excel_cache_store
    entries = store.is_a?(Hash) ? store['entries'] : nil
    return [] unless entries.is_a?(Hash)

    sources = []
    entries.each_value do |entry|
      next unless entry.is_a?(Hash)

      rows = []
      rows.concat(Array(entry['rows']))
      rows.concat(Array(entry['data']))
      rows.concat(Array(entry['items']))
      rows = public_rows(rows)
      next if rows.empty?

      loaded_at = begin
        Time.parse(entry['loaded_at'].to_s).to_i
      rescue
        0
      end
      score = [loaded_at, entry['mtime'].to_f.to_i].max
      sources << { 'score' => score, 'rows' => rows }
    end
    sources.sort_by { |source| -source['score'].to_i }.map { |source| source['rows'] }
  rescue => e
    puts "MH_Thongke import_excel_cache_sources error: #{e.class}: #{e.message}" rescue nil
    []
  end

  def self.report_snapshot(force = false)
    process_selection_cached(true) if force && respond_to?(:process_selection_cached)

    accessory_rows = []
    accessory_rows.concat(public_rows(current_report_items)) if respond_to?(:current_report_items)
    accessory_rows.concat(public_rows(@current_report_items))
    accessory_rows.concat(public_rows(@report_items))
    accessory_rows.concat(public_rows(@pk_report_items))

    material_rows = []
    material_rows.concat(public_rows(current_mat_items)) if respond_to?(:current_mat_items)
    material_rows.concat(public_rows(@current_mat_items))

    data_rows = []
    if respond_to?(:data_map) && data_map.respond_to?(:values)
      data_rows.concat(public_rows(data_map.values))
    end

    mat_data_rows = []
    if respond_to?(:mat_data_map) && mat_data_map.respond_to?(:values)
      mat_data_rows.concat(public_rows(mat_data_map.values))
    end

    {
      'ok' => true,
      'accessories' => (accessory_rows + data_rows).uniq,
      'materials' => (material_rows + mat_data_rows).uniq,
      'import_excel' => import_excel_data_snapshot,
      'excel_cache_sources' => import_excel_cache_sources
    }
  rescue => e
    puts "MH_Thongke report_snapshot error: #{e.class}: #{e.message}" rescue nil
    { 'ok' => false, 'accessories' => [], 'materials' => [], 'import_excel' => [], 'excel_cache_sources' => [], 'error' => e.message }
  end

  def self.public_row_value(row, *keys)
    keys.each do |key|
      return row[key] if row.respond_to?(:key?) && row.key?(key)
    end
    ''
  rescue
    ''
  end

  def self.public_row_product(row)
    public_row_value(
      row,
      :actual_product, 'actual_product',
      :product, 'product',
      :ma_sp, 'ma_sp',
      :Ma_SP, 'Ma_SP'
    )
  end

  def self.public_product_match?(value, target, mode = nil)
    target_code = target.to_s.strip
    return true if target_code.empty?
    return false if value.to_s.strip.empty? || value.to_s.strip == '--'

    if respond_to?(:mini_product_code_match?)
      mini_product_code_match?(value, target_code, mode || (respond_to?(:mini_group_mode) ? mini_group_mode : 'product'))
    elsif respond_to?(:product_code_exact)
      product_code_exact(value).to_s == product_code_exact(target_code).to_s
    else
      value.to_s.strip.upcase == target_code.upcase
    end
  rescue
    value.to_s.strip.upcase == target_code.upcase
  end

  def self.bom_for_product(product_code, force: false, include_excel: true, mode: nil)
    code = product_code.to_s.strip
    snap = report_snapshot(force)
    accessories = public_rows(snap['accessories']).select { |row| public_product_match?(public_row_product(row), code, mode) }
    materials = public_rows(snap['materials']).select { |row| public_product_match?(public_row_product(row), code, mode) }
    excel_rows = include_excel ? import_excel_data_snapshot(code) : []
    {
      'ok' => snap['ok'] != false,
      'product_code' => code,
      'accessories' => accessories,
      'materials' => materials,
      'import_excel' => excel_rows,
      'counts' => {
        'accessories' => accessories.length,
        'materials' => materials.length,
        'import_excel' => excel_rows.length
      }
    }
  rescue => e
    puts "MH_Thongke bom_for_product error: #{e.class}: #{e.message}" rescue nil
    { 'ok' => false, 'product_code' => product_code.to_s, 'accessories' => [], 'materials' => [], 'import_excel' => [], 'counts' => { 'accessories' => 0, 'materials' => 0, 'import_excel' => 0 }, 'error' => e.message }
  end

  def self.import_excel_current_status
    path = @import_excel_loaded_path
    path = @import_excel_path if path.to_s.empty?
    {
      'ok' => true,
      'path' => path.to_s,
      'rows' => import_excel_data_snapshot.length,
      'material_rows' => Array(report_snapshot(false)['materials']).length
    }
  rescue => e
    { 'ok' => false, 'path' => '', 'rows' => 0, 'material_rows' => 0, 'error' => e.message }
  end

  def self.accept_registry_import_excel_path(path)
    clean_path = path.to_s.strip
    return { 'ok' => false, 'error' => 'File output khong ton tai.' } if clean_path.empty? || !File.exist?(clean_path)

    @fill_sp_output_path = clean_path
    @fill_sp_status = "Đã nhận từ MH Registry: #{clean_path}"
    fill_sp_sync_import_excel_path(clean_path, auto_reload: false) if respond_to?(:fill_sp_sync_import_excel_path)
    remember_import_excel_path(clean_path) if respond_to?(:remember_import_excel_path)
    save_preferences if respond_to?(:save_preferences)
    { 'ok' => true, 'path' => clean_path }
  rescue => e
    { 'ok' => false, 'error' => e.message }
  end

  def self.main_dialog_visible?
    @dlg && @dlg.respond_to?(:visible?) && @dlg.visible?
  rescue
    false
  end

  def self.mini_import_visible?
    if respond_to?(:mini_import_dialog_visible?)
      mini_import_dialog_visible?
    else
      @mini_dlg && @mini_dlg.respond_to?(:visible?) && @mini_dlg.visible?
    end
  rescue
    false
  end

  def self.begin_external_mutation(source = 'external')
    was_visible = mini_import_visible?
    if respond_to?(:pause_mini_import_refresh)
      pause_mini_import_refresh(source)
    else
      @mini_import_external_mutation = true
      @mini_import_external_mutation_source = source.to_s
      @mini_import_external_mutation_started_at = Time.now.to_f
    end
    was_visible
  rescue => e
    puts "MH_Thongke begin_external_mutation error: #{e.class}: #{e.message}" rescue nil
    false
  end

  def self.end_external_mutation(source = 'external', refresh = true)
    if respond_to?(:resume_mini_import_refresh)
      resume_mini_import_refresh(source, refresh)
    else
      @mini_import_external_mutation = false
      @mini_import_external_mutation_source = nil
      @mini_import_external_mutation_started_at = nil
      reset_mini_import_refresh_state if respond_to?(:reset_mini_import_refresh_state)
    end
    true
  rescue => e
    puts "MH_Thongke end_external_mutation error: #{e.class}: #{e.message}" rescue nil
    false
  end
end

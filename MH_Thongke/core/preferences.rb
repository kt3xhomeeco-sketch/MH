# encoding: utf-8
# MH_Thongke â€” Preferences, History, Match Rules
# LÆ°u/load preferences, history, match rules + export Excel
# TÃ¡ch tá»« main.rb: dÃ²ng 563â€“717

module MH_Thongke

  def self.save_preferences
    s = session
    s.hidden_list = normalize_hidden_names(s.hidden_list || []) if respond_to?(:normalize_hidden_names)
    existing = {}
    begin
      existing = JSON.parse(File.read(MH_THONGKE_PREFS_JSON)) if File.exist?(MH_THONGKE_PREFS_JSON)
      existing = {} unless existing.is_a?(Hash)
    rescue
      existing = {}
    end
    payload = {
      "hidden_list"             => (s.hidden_list || []),
      "known_pk_names"          => (s.known_pk_names || []),
      "project_total_view"      => s.project_total_view.to_s,
      "project_total_sort"      => s.project_total_sort.to_s,
      "pk_report_view_scope"    => s.pk_report_view_scope.to_s,
      "pk_report_cut_source"    => s.pk_report_cut_source.to_s,
      "unit_overrides"          => (s.unit_overrides || {}),
      "import_excel_path"       => s.import_excel_path.to_s,
      "import_excel_paths"      => (s.import_excel_paths || {}),
      "import_excel_model_paths" => (s.import_excel_model_paths || {}),
      "fill_sp_input_path"      => @fill_sp_input_path.to_s,
      "fill_sp_output_path"     => @fill_sp_output_path.to_s,
      "fill_sp_library_path"    => @fill_sp_library_path.to_s,
      "fill_sp_include_son_code" => @fill_sp_include_son_code.nil? ? true : !!@fill_sp_include_son_code
    }
    existing.keys.grep(/\Amanual_.*pk/i).each { |key| existing.delete(key) }
    payload = existing.merge(payload)
    File.write(MH_THONGKE_PREFS_JSON, JSON.pretty_generate(payload))
    # Sync backward-compat module ivars
    @hidden_list = s.hidden_list; @known_pk_names = s.known_pk_names
    @unit_overrides = s.unit_overrides; @import_excel_path = s.import_excel_path
    @import_excel_paths = s.import_excel_paths
  rescue => e
    puts "Save preferences error: #{e.message}"
  end

  def self.load_preferences
    s = session
    s.reset_prefs!

    return unless File.exist?(MH_THONGKE_PREFS_JSON)
    data = JSON.parse(File.read(MH_THONGKE_PREFS_JSON))
    return unless data.is_a?(Hash)

    s.hidden_list = data["hidden_list"].is_a?(Array) ? data["hidden_list"] : []
    s.hidden_list = normalize_hidden_names(s.hidden_list) if respond_to?(:normalize_hidden_names)
    @hidden_name_set_sig = nil
    s.known_pk_names = data["known_pk_names"].is_a?(Array) ? data["known_pk_names"] : []
    pt_view = data["project_total_view"].to_s.upcase
    s.project_total_view = ["DETAIL", "COMPACT"].include?(pt_view) ? pt_view : "COMPACT"
    pt_sort = data["project_total_sort"].to_s.upcase
    s.project_total_sort = ["CUT", "PRODUCT"].include?(pt_sort) ? pt_sort : "CUT"
    scope = data["pk_report_view_scope"].to_s.upcase
    s.pk_report_view_scope = ["PROJECT", "CUT"].include?(scope) ? scope : "PROJECT"
    s.pk_report_cut_source = data["pk_report_cut_source"].to_s
    s.unit_overrides = data["unit_overrides"].is_a?(Hash) ? data["unit_overrides"] : {}
    s.import_excel_paths = data["import_excel_paths"].is_a?(Hash) ? data["import_excel_paths"] : {}
    s.import_excel_model_paths = data["import_excel_model_paths"].is_a?(Hash) ? data["import_excel_model_paths"] : {}
    s.import_excel_path = data["import_excel_path"].to_s
    @fill_sp_input_path = data["fill_sp_input_path"].to_s
    @fill_sp_output_path = data["fill_sp_output_path"].to_s
    @fill_sp_library_path = data["fill_sp_library_path"].to_s
    @fill_sp_include_son_code = data.key?("fill_sp_include_son_code") ? !!data["fill_sp_include_son_code"] : true
    migrated_import_excel_path = false
    if !s.import_excel_path.empty? && s.import_excel_paths.empty?
      legacy_project = project_name_for_path(s.import_excel_path) rescue ""
      unless legacy_project.to_s.empty?
        s.import_excel_paths[legacy_project] = s.import_excel_path
        migrated_import_excel_path = true
      end
    end
    save_preferences if migrated_import_excel_path
    # Sync backward-compat module ivars
    @hidden_list = s.hidden_list; @known_pk_names = s.known_pk_names
    @unit_overrides = s.unit_overrides; @import_excel_path = s.import_excel_path
    @import_excel_paths = s.import_excel_paths
    @import_excel_model_paths = s.import_excel_model_paths
    @project_total_view = s.project_total_view; @project_total_sort = s.project_total_sort
    @pk_report_view_scope = s.pk_report_view_scope
  rescue => e
    puts "Load preferences error: #{e.message}"
    s.reset_prefs!
  end

  def self.record_known_pk_names(names, persist = true)
    s = session
    before = (s.known_pk_names || []).map { |n| fix_vietnamese_mojibake(n).to_s.strip }.reject(&:empty?).uniq
    incoming = Array(names).map { |n| fix_vietnamese_mojibake(n).to_s.strip }.reject(&:empty?)
    merged = (before + incoming).uniq.sort_by { |n| cached_norm(n) rescue n.downcase }
    s.known_pk_names = merged
    @known_pk_names = merged
    save_preferences if persist && merged != before
    merged
  rescue => e
    puts "record_known_pk_names error: #{e.message}"
    session.known_pk_names ||= []
  end

  # Auto-load preferences khi module Ä‘Æ°á»£c require
  begin
    load_preferences
  rescue Exception => e
    puts "MH_Thongke load_preferences fallback: #{e.message}"
    session.reset_prefs!
  end

  def self.save_history(action, details)
    entry = { time: Time.now.strftime("%Y-%m-%d %H:%M:%S"), action: action, details: details }
    session.change_history ||= []
    session.change_history << entry
    @change_history = session.change_history
    begin
      Sketchup.active_model.set_attribute("MH_Thongke", "history", session.change_history.to_json)
    rescue => e
      puts "Save history error: #{e.message}"
    end
  end

  def self.load_history
    session.change_history = []
    if Sketchup.active_model
      hist_str = Sketchup.active_model.get_attribute("MH_Thongke", "history")
      if hist_str && !hist_str.empty?
        begin
          session.change_history = JSON.parse(hist_str, symbolize_names: true)
        rescue => e
          puts "Load history error: #{e.message}"
        end
      end
    end
    @change_history = session.change_history
  end

  def self.save_match_rules
    @match_rules  ||= {}
    @general_rules ||= DEFAULT_GENERAL_RULES.dup
    begin
      existing = {}
      begin
        existing = JSON.parse(File.read(GLOBAL_RULES_FILE)) if File.exist?(GLOBAL_RULES_FILE)
        existing = {} unless existing.is_a?(Hash)
      rescue
        existing = {}
      end
      data = existing.merge({
        "general_rules" => @general_rules,
        "specific_rules" => @match_rules,
        "mini_accept_rules" => existing["mini_accept_rules"].is_a?(Hash) ? existing["mini_accept_rules"] : (@mini_accept_rules.is_a?(Hash) ? @mini_accept_rules : {})
      })
      File.write(GLOBAL_RULES_FILE, JSON.pretty_generate(data))
      Sketchup.active_model.set_attribute("MH_Thongke", "match_rules", @match_rules.to_json)
      queue_rules_excel_export rescue nil
    rescue => e
      puts "Save match_rules error: #{e.message}"
    end
  end

  def self.load_match_rules
    @match_rules   = {}
    @general_rules = DEFAULT_GENERAL_RULES.dup
    if File.exist?(GLOBAL_RULES_FILE)
      begin
        data = JSON.parse(File.read(GLOBAL_RULES_FILE))
        if data.is_a?(Hash) && data["general_rules"]
          @general_rules = data["general_rules"]
          @match_rules   = data["specific_rules"] || {}
        else
          @match_rules = data
        end
      rescue => e
        puts "Load global rules error: #{e.message}"
      end
    end
    if Sketchup.active_model
      str = Sketchup.active_model.get_attribute("MH_Thongke", "match_rules")
      if str && !str.empty?
        begin
          model_rules = JSON.parse(str)
          model_rules.each { |k, v| @match_rules[k] = v }
        rescue => e
          puts "Load model rules error: #{e.message}"
        end
      end
    end
    DEFAULT_GENERAL_RULES.each do |key, val|
      @general_rules[key] = val if @general_rules[key].nil?
    end
  end

  def self.queue_rules_excel_export
    @rules_excel_dirty = true
    return if @rules_excel_export_queued

    @rules_excel_export_queued = true
    if defined?(UI) && UI.respond_to?(:start_timer)
      UI.start_timer(3.0, false) do
        @rules_excel_export_queued = false
        if @rules_excel_dirty
          @rules_excel_dirty = false
          export_rules_to_excel
        end
      end
    else
      @rules_excel_dirty = false
      @rules_excel_export_queued = false
      export_rules_to_excel
    end
  rescue => e
    @rules_excel_export_queued = false
    puts "Queue rules excel export error: #{e.message}"
  end

  def self.export_rules_to_excel
    @match_rules ||= {}
    @general_rules ||= DEFAULT_GENERAL_RULES.dup
    @unit_overrides ||= {}

    general_rows = [["Loại", "Từ khóa / Pattern", "Mô tả"]]
    (@general_rules["ignore_keywords"] || []).each do |kw|
      general_rows << ["ignore_keyword", kw, "Tên Excel chứa '#{kw}' -> tự động Keep"]
    end
    (@general_rules["keep_numbers_patterns"] || []).each do |pt|
      general_rows << ["keep_numbers", pt, "Tên bắt đầu '#{pt}' -> giữ số từ tên cũ"]
    end
    (@general_rules["synonym_pairs"] || []).each do |pair|
      next unless pair.is_a?(Array) && pair.size >= 2
      general_rows << ["synonym_pair", "#{pair[0]} = #{pair[1]}", "Dong nhat ten tuong duong de so khop"]
    end
    (@general_rules["equivalent_pairs"] || []).each do |pair|
      next unless pair.is_a?(Array) && pair.size >= 2
      general_rows << ["equivalent_pair", "#{pair[0]} ~ #{pair[1]}", "Cho phep so khop de hien trang thai UPDATE khi ten khac nhau"]
    end
    (@general_rules["distinct_patterns"] || []).each do |pattern|
      general_rows << ["distinct_pattern", pattern.to_s, "Giu rieng, khong gom chung"]
    end

    private_rows = [["Mã SP","Tên SketchUp","Hành động","Tên Excel","Tên mới","Ngày"]]
    @match_rules.each do |key, val|
      parts = key.split("|", 2)
      private_rows << [
        parts[0], parts[1],
        val["action"] == "keep" ? "Giữ" : "Update",
        val["ex_name"].to_s, val["new_name"].to_s, val["date"].to_s
      ]
    end

    accept_rows = [["Ma SP","Loai","Ten model","Ten target","Spec","Hanh dong","Thoi gian","Rule key"]]
    mini_rules = respond_to?(:ensure_mini_accept_rules) ? ensure_mini_accept_rules : (@mini_accept_rules || {})
    mini_rules.each do |key, val|
      parts = key.to_s.split("|", 5)
      data = val.is_a?(Hash) ? val : {}
      t = data["time"]
      begin
        time_text = t.to_s.empty? ? "" : Time.at(t.to_i).strftime("%Y-%m-%d %H:%M:%S")
      rescue
        time_text = t.to_s
      end
      accept_rows << [
        data["product_code"].to_s.empty? ? parts[0].to_s : data["product_code"].to_s,
        data["kind"].to_s.empty? ? parts[1].to_s : data["kind"].to_s,
        data["model_name"].to_s.empty? ? parts[2].to_s : data["model_name"].to_s,
        data["target_name"].to_s.empty? ? parts[3].to_s : data["target_name"].to_s,
        data["spec"].to_s.empty? ? parts[4].to_s : data["spec"].to_s,
        data["action"].to_s.empty? ? val.to_s : data["action"].to_s,
        time_text,
        key.to_s
      ]
    end

    unit_rows = [["Data key","Don vi"]]
    @unit_overrides.each do |key, unit|
      unit_rows << [key.to_s, unit.to_s]
    end

    MH::ExcelBridge.write(
      RULES_EXCEL_FILE,
      sheets: {
        "Quy tắc chung" => general_rows,
        "Quy tắc riêng" => private_rows,
        "Accept rules" => accept_rows,
        "Doi don vi" => unit_rows
      }
    )
  rescue => e
    puts "Export rules excel error: #{e.message}"
  end

end

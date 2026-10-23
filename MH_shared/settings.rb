# encoding: UTF-8
#
# MH::Settings -- facade lưu cấu hình dùng chung cho hệ MH.
# JSON là nguồn chính; XLSX chỉ dùng để sao lưu/trao đổi.

require 'json'
require 'fileutils'
require 'digest'
require 'time'

module MH
  module Settings
    SCHEMA_VERSION = 1
    GLOBAL_FILENAME = 'mh_global_config.json'.freeze
    PROJECT_FILENAME = 'mh_project_config.json'.freeze
    MODEL_DICT = 'MH_Project_Config'.freeze
    MODEL_KEY = 'settings_json'.freeze

    @registry = {}
    @listeners = []
    @cache = {}

    module_function

    def register(app:, key:, scope:, default: nil)
      app_key = normalize_app(app)
      key = key.to_s
      scope = normalize_scope(scope)
      raise ArgumentError, "scope không hợp lệ: #{scope}" unless [:global, :project].include?(scope)
      @registry[[app_key, key]] = { scope: scope, default: deep_copy(default) }
      true
    end

    def registered?(app, key)
      @registry.key?([normalize_app(app), key.to_s])
    end

    def definition(app, key)
      @registry[[normalize_app(app), key.to_s]]
    end

    def read(app, key, default = nil, scope: :auto)
      app_key = normalize_app(app)
      key = key.to_s
      defn = definition(app_key, key)
      fallback = default.nil? && defn ? deep_copy(defn[:default]) : default
      scope = normalize_scope(scope)
      if scope == :auto
        if defn && defn[:scope] == :global
          return value_from(:global, app_key, key, fallback)
        end
        project_value = value_from(:project, app_key, key, :__mh_missing__)
        return project_value unless project_value == :__mh_missing__
        return value_from(:global, app_key, key, fallback)
      end
      validate_write_scope!(app_key, key, scope, read_only: true)
      value_from(scope, app_key, key, fallback)
    end

    def write(app, key, value, scope:, notify: true)
      app_key = normalize_app(app)
      key = key.to_s
      scope = normalize_scope(scope)
      validate_write_scope!(app_key, key, scope)
      data = load_scope(scope)
      data['apps'] ||= {}
      data['apps'][app_key] ||= {}
      data['apps'][app_key][key] = deep_copy(value)
      write_scope(scope, data)
      broadcast(app: app_key, keys: [key], scope: scope, source: :settings_write) if notify
      value
    end

    def section(app, scope:)
      app_key = normalize_app(app)
      data = load_scope(normalize_scope(scope))
      deep_copy((data['apps'] || {})[app_key] || {})
    end

    def replace_section(app, values, scope:)
      app_key = normalize_app(app)
      scope = normalize_scope(scope)
      data = load_scope(scope)
      data['apps'] ||= {}
      data['apps'][app_key] = deep_copy(values || {})
      write_scope(scope, data)
      broadcast(app: app_key, keys: data['apps'][app_key].keys, scope: scope, source: :settings_section)
      true
    end

    def all(scope:)
      deep_copy(load_scope(normalize_scope(scope)))
    end

    def on_change(&block)
      @listeners << block if block
      block
    end

    def broadcast(app:, keys:, scope:, source: nil)
      payload = {
        app: normalize_app(app),
        keys: Array(keys).map(&:to_s),
        scope: normalize_scope(scope),
        source: source
      }
      @listeners.each { |listener| listener.call(payload) }
      if defined?(MH::RegistryApp::Connector)
        config = defined?(MH::RegistryApp) && MH::RegistryApp.respond_to?(:load_config) ? MH::RegistryApp.load_config : nil
        MH::RegistryApp::Connector.notify_config_changed(config) rescue nil
      end
      payload
    rescue => e
      warn "[MH::Settings] broadcast lỗi: #{e.class}: #{e.message}"
      payload
    end

    def global_dir
      base = ENV['LOCALAPPDATA'].to_s
      base = File.expand_path(File.join(Dir.home, 'AppData', 'Local')) if base.empty? && Dir.respond_to?(:home)
      base = File.join(shared_dir, 'data') if base.empty?
      File.join(base, 'MH', 'config')
    end

    def global_path
      File.join(global_dir, GLOBAL_FILENAME)
    end

    def project_root(model = nil)
      model ||= active_model
      path = model && model.respond_to?(:path) ? model.path.to_s : ''
      return nil if path.empty?
      File.dirname(File.dirname(path))
    end

    def project_data_dir(model = nil)
      root = project_root(model)
      root ? File.join(root, 'SPEC', 'Data') : nil
    end

    def project_path(model = nil)
      dir = project_data_dir(model)
      dir ? File.join(dir, PROJECT_FILENAME) : nil
    end

    def project_storage_status(model = nil)
      project_path(model) ? 'file' : 'model_attribute'
    end

    def load_scope(scope)
      scope = normalize_scope(scope)
      path = scope == :global ? global_path : project_path
      return load_model_project if scope == :project && path.nil?
      load_json(path, scope)
    end

    def write_scope(scope, data)
      scope = normalize_scope(scope)
      stamped = default_data(scope).merge(data || {})
      stamped['schema_version'] = SCHEMA_VERSION
      stamped['updated_at'] = Time.now.utc.iso8601
      if scope == :project && project_path.nil?
        write_model_project(stamped)
      else
        write_json(scope == :global ? global_path : project_path, stamped)
      end
    end

    def export_backup_xlsx(path, source: :all)
      source = source.to_sym
      sheets = {}
      sheets['_meta'] = [
        %w[key value],
        ['schema_version', SCHEMA_VERSION],
        ['exported_at', Time.now.utc.iso8601],
        ['source', source.to_s],
        ['project_root', project_root.to_s],
        ['global_path', global_path.to_s],
        ['project_path', project_path.to_s]
      ]
      if source == :all || source == :global
        append_scope_sheets(sheets, :global, all(scope: :global))
      end
      if source == :all || source == :project
        append_scope_sheets(sheets, :project, all(scope: :project))
      end
      MH::ExcelBridge.write(path, sheets: sheets)
      path
    end

    def import_backup_preview(path)
      sheets = MH::ExcelBridge.read_all(path)
      {
        ok: true,
        meta: sheet_to_hash(sheets['_meta'] || []),
        sheets: sheets.keys.reject { |name| name.to_s == '_meta' }.map do |name|
          rows = sheets[name] || []
          { 'sheet' => name, 'rows' => [rows.length - 1, 0].max }
        end
      }
    rescue => e
      { ok: false, error: "#{e.class}: #{e.message}" }
    end

    def restore_backup_xlsx(path, scopes: [:global, :project])
      sheets = MH::ExcelBridge.read_all(path)
      restored = {}
      Array(scopes).map { |s| normalize_scope(s) }.each do |scope|
        data = default_data(scope)
        sheets.each do |sheet_name, rows|
          prefix = "#{scope}_"
          next unless sheet_name.to_s.start_with?(prefix)
          app = sheet_name.to_s.sub(/\A#{Regexp.escape(prefix)}/, '')
          data['apps'][app] = rows_to_settings(rows)
        end
        backup_current_scope(scope)
        write_scope(scope, data)
        restored[scope.to_s] = (data['apps'] || {}).keys
      end
      broadcast(app: 'all', keys: restored.keys, scope: :global, source: :restore_xlsx)
      { ok: true, restored: restored }
    rescue => e
      { ok: false, error: "#{e.class}: #{e.message}" }
    end

    def backup_current_scope(scope)
      scope = normalize_scope(scope)
      path = scope == :global ? global_path : project_path
      return nil unless path && File.exist?(path)
      backup = "#{path}.bak_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
      FileUtils.cp(path, backup)
      backup
    end

    def flush_model_project_to_file(model = nil)
      path = project_path(model)
      return nil unless path
      data = load_model_project(model)
      write_json(path, data)
      model ||= active_model
      model.delete_attribute(MODEL_DICT, MODEL_KEY) if model && model.respond_to?(:delete_attribute)
      path
    end

    def value_from(scope, app, key, fallback)
      data = load_scope(scope)
      apps = data['apps'] || {}
      app_data = apps[normalize_app(app)] || {}
      return deep_copy(app_data[key.to_s]) if app_data.key?(key.to_s)
      deep_copy(fallback)
    end

    def validate_write_scope!(app, key, scope, read_only: false)
      raise ArgumentError, 'scope :auto chỉ dùng để đọc' if scope == :auto && !read_only
      return true unless registered?(app, key)
      expected = definition(app, key)[:scope]
      return true if expected == scope || (read_only && scope == :auto)
      raise ArgumentError, "scope sai cho #{app}.#{key}: #{scope}, phải là #{expected}"
    end

    def normalize_app(app)
      app.to_s.strip.downcase.gsub(/\s+/, '_')
    end

    def normalize_scope(scope)
      scope.to_sym
    end

    def default_data(scope)
      {
        'schema_version' => SCHEMA_VERSION,
        'scope' => scope.to_s,
        'updated_at' => nil,
        'apps' => {}
      }
    end

    def load_json(path, scope)
      return default_data(scope) unless path && File.exist?(path)
      mtime = File.mtime(path).to_f
      cached = @cache[path]
      return deep_copy(cached[:data]) if cached && cached[:mtime] == mtime
      data = JSON.parse(File.read(path, encoding: 'UTF-8'))
      data = default_data(scope).merge(data || {})
      data['apps'] ||= {}
      @cache[path] = { mtime: mtime, data: data }
      deep_copy(data)
    rescue => e
      warn "[MH::Settings] đọc JSON lỗi #{path}: #{e.message}"
      default_data(scope)
    end

    def write_json(path, data)
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.tmp_#{$$}_#{rand(1_000_000)}"
      File.write(tmp, JSON.pretty_generate(data), encoding: 'UTF-8')
      FileUtils.mv(tmp, path)
      @cache.delete(path)
      path
    ensure
      FileUtils.rm_f(tmp) if tmp && File.exist?(tmp)
    end

    def load_model_project(model = nil)
      model ||= active_model
      raw = model && model.respond_to?(:get_attribute) ? model.get_attribute(MODEL_DICT, MODEL_KEY).to_s : ''
      return default_data(:project) if raw.empty?
      data = JSON.parse(raw)
      default_data(:project).merge(data || {})
    rescue => e
      warn "[MH::Settings] đọc model project lỗi: #{e.message}"
      default_data(:project)
    end

    def write_model_project(data, model = nil)
      model ||= active_model
      raise 'Không có active model để lưu project config tạm.' unless model
      model.set_attribute(MODEL_DICT, MODEL_KEY, JSON.generate(data))
      @cache.delete(:model_project)
      true
    end

    def append_scope_sheets(sheets, scope, data)
      (data['apps'] || {}).each do |app, values|
        sheet = "#{scope}_#{safe_sheet_name(app)}"[0, 31]
        rows = [%w[key value_json]]
        (values || {}).each { |key, value| rows << [key.to_s, JSON.generate(value)] }
        sheets[sheet] = rows
      end
    end

    def rows_to_settings(rows)
      out = {}
      Array(rows).drop(1).each do |row|
        key = row[0].to_s
        next if key.empty?
        raw = row[1].to_s
        out[key] = raw.empty? ? nil : JSON.parse(raw)
      rescue
        out[key] = row[1]
      end
      out
    end

    def sheet_to_hash(rows)
      Hash[Array(rows).drop(1).map { |row| [row[0].to_s, row[1].to_s] }]
    end

    def safe_sheet_name(value)
      value.to_s.gsub(/[\[\]\*\/\\\?:]/, '_')
    end

    def deep_copy(value)
      JSON.parse(JSON.generate(value))
    rescue
      value
    end

    def shared_dir
      defined?(MH::Shared::DIR) ? MH::Shared::DIR : __dir__
    end

    def active_model
      defined?(Sketchup) ? Sketchup.active_model : nil
    end
  end
end

if defined?(MH::Settings)
  begin
    MH::Settings.register(app: 'assemble', key: 'draw_ratio', scope: :global, default: 'auto')
    MH::Settings.register(app: 'assemble', key: 'draw_ratios', scope: :global, default: [5, 10, 15, 20, 25, 50, 100])
    MH::Settings.register(app: 'assemble', key: 'no_door_scope', scope: :project, default: { 'product' => [], 'module' => [] })
    MH::Settings.register(app: 'assemble', key: 'hide_common', scope: :project, default: [])
    MH::Settings.register(app: 'assemble', key: 'hidden_tags', scope: :project, default: [])
    MH::Settings.register(app: 'assemble', key: 'no_number', scope: :project, default: [])
    MH::Settings.register(app: 'assemble', key: 'sub_modules', scope: :project, default: [])

    MH::Settings.register(app: 'pk_addon', key: 'library_path', scope: :global, default: '')
    MH::Settings.register(app: 'pk_addon', key: 'shape', scope: :global, default: 'square')
    MH::Settings.register(app: 'pk_addon', key: 'size_mm', scope: :global, default: 8)
    MH::Settings.register(app: 'pk_addon', key: 'face_mode', scope: :global, default: 'largest')

    {
      'gap_threshold_mm' => 1000.0,
      'default_sp_start_num' => 1,
      'default_split_axis' => 'x',
      'split_all_default' => false,
      'auto_contact_split' => true,
      'cp_tolerance_mm' => 0.05,
      'cp_penetration_tolerance_mm' => 0.05,
      'cp_max_pass' => 20,
      'cp_separator_axes' => %w[x z],
      'exempt_keywords' => [
        'phào nóc', 'phao noc', 'len chân', 'len chan', 'xương nẹp', 'xuong nep',
        'chân bệ', 'chan be', 'len bệ chân', 'len be chan', 'len bệ', 'len be',
        'bệ chân', 'be chan', 'chặn cánh', 'chan canh'
      ],
      'sp_base_only_keywords' => [
        'xương nẹp', 'xuong nep', 'phào nóc', 'phao noc', 'len chân', 'len chan',
        'chân bệ', 'chan be', 'len bệ chân', 'len be chan', 'len bệ', 'len be',
        'bệ chân', 'be chan', 'chặn cánh', 'chan canh'
      ],
      'modul_contact_keywords' => [],
      'base_accessory_keywords' => [
        'len chân', 'len chan', 'len bệ chân', 'len be chan',
        'len bệ', 'len be', 'bệ chân', 'be chan'
      ],
      'named_contact_split_pairs' => [
        { 'a' => ['hông trái', 'hong trai'], 'b' => ['hông phải', 'hong phai'], 'axis' => 'x' },
        { 'a' => ['đáy', 'day'], 'b' => ['nóc', 'noc'], 'axis' => 'z' }
      ]
    }.each do |key, default|
      MH::Settings.register(app: 'fast_rename', key: key, scope: :global, default: default)
    end

    %w[
      partial_name name_group name_search bounding_size bounding_volume min_thickness
      same_material same_tag size_tolerance volume_tolerance thickness_tolerance
      type_filter scope_filter nesting_filter min_size_threshold min_all_size_threshold
      key_isolate key_settings quick_search_items
    ].each do |key|
      MH::Settings.register(app: 'select_similar', key: key, scope: :global, default: nil)
    end

    %w[
      line_spacing text_gap text_display_mode show_hidden_lines label_style
      show_part_id show_part_prefix show_part_suffix show_label_bg hidden_layers
    ].each do |key|
      MH::Settings.register(app: 'viewport_names', key: key, scope: :global, default: nil)
    end

    MH::Settings.register(app: 'thongke', key: 'hidden_list', scope: :project, default: [])
  rescue => e
    warn "[MH::Settings] register defaults lỗi: #{e.message}"
  end
end

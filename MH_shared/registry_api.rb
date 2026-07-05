# encoding: UTF-8
#
# MH::Registry -- API đọc/ghi "registry" dùng chung cho hệ sinh thái MH_*.
# ---------------------------------------------------------------------------
# Hai tầng dữ liệu:
#   * GLOBAL   (MH_shared/data/global_registry.json) -- dùng cho mọi dự án:
#       materials, thickness_mappings, invalid_materials, module_templates,
#       detail_aliases, column_aliases, header_columns
#   * PROJECT  (cạnh file .skp: MH_project_registry.json) -- riêng từng dự án:
#       products, modules, keywords, prefix/suffix/modul suggestions
#
# Đọc JSON trực tiếp (nhanh, không lock). Cache theo mtime: tự nạp lại khi
# file thay đổi (vd MH_Registry UI vừa lưu). Mọi accessor trả về default an
# toàn (mảng/hash rỗng) nếu file thiếu hoặc key vắng.
# ---------------------------------------------------------------------------

require 'json'

module MH
  module Registry
    SCHEMA_VERSION = '1.0'.freeze
    GLOBAL_FILENAME = 'global_registry.json'.freeze
    PROJECT_FILENAME = 'MH_project_registry.json'.freeze

    @cache = {} # path => { mtime:, data: }
    @unsaved_project_paths = {} # model.object_id => temp project registry path

    module_function

    # ---- Đường dẫn ---------------------------------------------------------

    # Thư mục MH_shared (chứa registry_api.rb này). Dùng MH::Shared::DIR nếu có,
    # nếu không thì suy ra từ __dir__ (cho phép nạp module độc lập).
    def shared_dir
      defined?(MH::Shared::DIR) ? MH::Shared::DIR : __dir__
    end

    def data_dir
      File.join(shared_dir, 'data')
    end

    def global_path
      File.join(data_dir, GLOBAL_FILENAME)
    end

    # Thư mục của model hiện tại (hoặc model truyền vào). "" nếu chưa lưu.
    def model_dir(model = nil)
      model ||= (defined?(Sketchup) ? Sketchup.active_model : nil)
      path = (model && model.path).to_s
      path.empty? ? '' : File.dirname(path)
    end

    # Đường dẫn project registry.
    # Model đã lưu -> cạnh file .skp.
    # Model chưa lưu -> file tạm riêng theo object_id của model, tránh các file
    # chưa lưu dùng chung một registry.
    def project_path(model = nil)
      model ||= (defined?(Sketchup) ? Sketchup.active_model : nil)
      dir = model_dir(model)
      return unsaved_project_path(model) if dir.empty?
      File.join(dir, PROJECT_FILENAME)
    end

    def unsaved_project_path(model = nil)
      key = model ? model.object_id : :default
      @unsaved_project_paths[key] ||= begin
        suffix = key == :default ? 'default' : key.to_s
        File.join(data_dir, "_unsaved_#{suffix}_#{PROJECT_FILENAME}")
      end
    end

    def previous_unsaved_project_path(model = nil)
      return nil unless model
      @unsaved_project_paths[model.object_id]
    end

    # ---- Nạp có cache theo mtime ------------------------------------------

    def load_json(path)
      return default_for(path) unless File.exist?(path)
      mtime = File.mtime(path).to_f
      cached = @cache[path]
      return cached[:data] if cached && cached[:mtime] == mtime
      raw = File.read(path, encoding: 'UTF-8')
      data = raw.strip.empty? ? default_for(path) : JSON.parse(raw)
      @cache[path] = { mtime: mtime, data: data }
      data
    rescue JSON::ParserError => e
      warn "[MH::Registry] JSON loi #{path}: #{e.message}"
      default_for(path)
    end

    def default_for(path)
      if path == global_path
        default_global
      else
        default_project
      end
    end

    def default_global
      {
        'schema_version' => SCHEMA_VERSION,
        'materials' => [],
        'thickness_mappings' => [],
        'invalid_materials' => [],
        'material_code_rules' => {},
        'product_code_rules' => {},
        'material_code_mappings' => [],
        'module_templates' => [],
        'detail_aliases' => {},
        'column_aliases' => {},
        'header_columns' => []
      }
    end

    def default_project
      {
        'schema_version' => SCHEMA_VERSION,
        'products' => [],
        'modules' => [],
        'keywords' => { 'exempt' => [], 'sp_base_only' => [], 'modul_contact' => [] },
        'material_code_rules' => {},
        'product_code_rules' => {},
        'sub_prefix_suggestions' => [],
        'prefix_suggestions' => [],
        'suffix_suggestions' => [],
        'modul_suggestions' => []
      }
    end

    def global
      load_json(global_path)
    end

    def project(model = nil)
      model ||= (defined?(Sketchup) ? Sketchup.active_model : nil)
      path = project_path(model)
      return load_json(path) if File.exist?(path)

      # Nếu người dùng cấu hình registry trước khi lưu model, sau khi Save As
      # lần đầu vẫn nạp lại dữ liệu tạm của đúng model đó để họ có thể Save
      # Project và ghi thành MH_project_registry.json cạnh file .skp.
      temp_path = previous_unsaved_project_path(model)
      if temp_path && temp_path != path && File.exist?(temp_path)
        return load_json(temp_path)
      end

      load_json(path)
    end

    def reload!
      @cache.clear
      true
    end

    # ---- Accessor GLOBAL ---------------------------------------------------

    def materials;          Array(global['materials']); end
    def thickness_mappings; Array(global['thickness_mappings']); end
    def invalid_materials;  Array(global['invalid_materials']); end
    def material_code_rules(model = nil)
      deep_merge_hash(Hash(global['material_code_rules'] || {}), Hash(project(model)['material_code_rules'] || {}))
    end
    def product_code_rules(model = nil)
      deep_merge_hash(Hash(global['product_code_rules'] || {}), Hash(project(model)['product_code_rules'] || {}))
    end
    def material_code_mappings; Array(global['material_code_mappings']); end
    def module_templates;   Array(global['module_templates']); end
    def detail_aliases;     Hash(global['detail_aliases'] || {}); end
    def column_aliases;     Hash(global['column_aliases'] || {}); end
    def header_columns;     Array(global['header_columns']); end

    # ---- Accessor PROJECT --------------------------------------------------

    def products(model = nil)
      Array(project(model)['products'])
    end

    # Tra cứu 1 sản phẩm theo mã (không phân biệt hoa/thường).
    def product(code, model = nil)
      c = code.to_s.strip.upcase
      products(model).detect { |p| p['code'].to_s.strip.upcase == c }
    end

    # Danh sách modul của 1 mã SP.
    def modules_for(sp_code, model = nil)
      c = sp_code.to_s.strip.upcase
      Array(project(model)['modules']).select { |m| m['sp'].to_s.strip.upcase == c }
    end

    def keywords(model = nil)
      kw = project(model)['keywords'] || {}
      {
        'exempt' => Array(kw['exempt']),
        'sp_base_only' => Array(kw['sp_base_only']),
        'modul_contact' => Array(kw['modul_contact'])
      }
    end

    def sub_prefix_suggestions(model = nil)
      Array(project(model)['sub_prefix_suggestions']).map { |s| s.is_a?(Hash) ? s['value'].to_s : s.to_s }
    end

    def prefix_suggestions(model = nil)
      rows = Array(project(model)['prefix_suggestions']).map { |s| s.is_a?(Hash) ? s['value'].to_s : s.to_s }
      rows.empty? ? product_code_rule_families(model) : rows
    end

    # Trả về Array<Hash{value, shortcut}> để giữ thông tin shortcut.
    def suffix_suggestions(model = nil)
      rows = Array(project(model)['suffix_suggestions'])
      rows = product_code_rule_suffixes(model) if rows.empty?
      rows.map do |s|
        if s.is_a?(Hash)
          { 'value' => s['value'].to_s, 'shortcut' => s['shortcut'] }
        else
          { 'value' => s.to_s, 'shortcut' => nil }
        end
      end
    end

    def modul_suggestions(model = nil)
      Array(project(model)['modul_suggestions']).map { |s| s.is_a?(Hash) ? s['value'].to_s : s.to_s }
    end

    def product_code_rule_layer(key, model = nil)
      layers = Array(product_code_rules(model)['layers'])
      layers.find { |row| row.is_a?(Hash) && row['key'].to_s == key.to_s }
    rescue
      nil
    end

    def product_code_rule_families(model = nil)
      layer = product_code_rule_layer('product_code', model)
      Array(layer && layer['values']).filter_map do |value|
        text = value.is_a?(Hash) ? value['value'].to_s : value.to_s
        match = text.strip.upcase.match(/\A([A-Z]+)(?:\d+[A-Z]?|\.\.\.|\*)?\z/)
        match && match[1]
      end.uniq
    end

    def product_code_rule_suffixes(model = nil)
      layer = product_code_rule_layer('suffix', model)
      Array(layer && layer['values'])
    end

    # { "1" => "_L", "2" => "_R" } từ suffix_suggestions có shortcut.
    def shortcut_map(model = nil)
      map = {}
      suffix_suggestions(model).each do |s|
        sc = s['shortcut']
        map[sc.to_s] = s['value'] if sc && sc.to_s.strip != ''
      end
      map
    end

    # ---- Ghi (MH_Registry UI dùng) ----------------------------------------

    def save_global!(data)
      path = write_json(global_path, merge_schema(data, default_global))
      refresh_name_grammar
      path
    end

    def save_project!(data, model = nil)
      path = write_json(project_path(model), merge_schema(data, default_project))
      refresh_name_grammar
      path
    end

    def refresh_name_grammar
      return false unless defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:configure)

      MH::NameGrammar.configure(MH::NameGrammar.respond_to?(:last_config) ? MH::NameGrammar.last_config : {})
      true
    rescue => e
      MH::Shared.dbg("[MH::Registry] refresh_name_grammar error: #{e.class}: #{e.message}") if defined?(MH::Shared)
      false
    end

    def merge_schema(data, defaults)
      d = defaults.merge(data || {})
      d['schema_version'] = SCHEMA_VERSION
      d
    end

    def write_json(path, data)
      FileUtils.mkdir_p(File.dirname(path)) if defined?(FileUtils)
      require 'fileutils' unless defined?(FileUtils)
      FileUtils.mkdir_p(File.dirname(path))
      tmp = path + '.tmp'
      File.write(tmp, JSON.pretty_generate(data), encoding: 'UTF-8')
      File.delete(path) if File.exist?(path)
      File.rename(tmp, path)
      @cache.delete(path) # buộc nạp lại lần sau
      path
    end

    def deep_merge_hash(left, right)
      left.merge(right) do |_key, old_val, new_val|
        old_val.is_a?(Hash) && new_val.is_a?(Hash) ? deep_merge_hash(old_val, new_val) : new_val
      end
    end
  end
end

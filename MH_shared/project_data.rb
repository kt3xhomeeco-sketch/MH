# encoding: UTF-8
#
# MH::ProjectData - in-memory cache for parsed project JSON rows.
# Registry owns workflow paths/export; this module only stores neutral data.

require 'json'

module MH
  module ProjectData
    @version = 0
    @snapshot = nil
    @last_error = nil

    module_function

    PRODUCT_KEYS = [
      'Ma_SP', 'Mã SP', 'MÃ SP', 'Ma SP', 'MASP',
      'ma_sp', 'product', 'product_code', 'actual_product'
    ].freeze

    NAME_KEYS = [
      'Ten_SP', 'Tên SP', 'TÊN SP', 'Ten SP',
      'ten_sp', 'product_name'
    ].freeze

    ATTR_DICT = 'MH_ProjectData'.freeze
    ATTR_JSON_PATH = 'json_path'.freeze
    ATTR_SOURCE_PATH = 'source_path'.freeze
    ATTR_MODEL_KEY = 'model_key'.freeze

    def load_json(json_path, source_path: nil, force: false, reason: nil, model_key: nil)
      json_path = json_path.to_s.strip
      return error_snapshot('json_error', 'json_path empty', json_path, source_path) if json_path.empty?
      return error_snapshot('json_error', 'json_path not found', json_path, source_path) unless File.exist?(json_path)

      json_mtime = file_mtime(json_path)
      source_mtime = file_mtime(source_path)
      model_key = model_key.to_s.strip.empty? ? current_model_key : model_key.to_s
      if !force && current_matches?(json_path, source_path, json_mtime, source_mtime, model_key)
        return snapshot
      end

      data = JSON.parse(File.read(json_path, encoding: 'UTF-8'))
      rows = data.is_a?(Array) ? data : []
      return error_snapshot('json_error', 'JSON root must be an Array', json_path, source_path) unless data.is_a?(Array)

      set_rows(rows, source_path: source_path, json_path: json_path, source_mtime: source_mtime,
        json_mtime: json_mtime, source: 'json', reason: reason || 'load_json', model_key: model_key)
    rescue => e
      error_snapshot('json_error', e.message, json_path, source_path)
    end

    def set_rows(rows, source_path: nil, json_path: nil, json_paths: nil, source_mtime: nil, json_mtime: nil, source: 'payload', reason: nil, model_key: nil)
      normalized = Array(rows).map { |row| normalize_row(row) }.select { |row| row.is_a?(Hash) && !row.empty? }
      model_key = model_key.to_s.strip.empty? ? current_model_key : model_key.to_s
      source_paths = Array(json_paths).map { |path| path.to_s.strip }.reject(&:empty?).uniq
      source_paths = [json_path.to_s.strip].reject(&:empty?) if source_paths.empty?
      @version = @version.to_i + 1
      @version = 1 if @version <= 0
      @last_error = nil
      @snapshot = {
        ok: true,
        mode: 'snapshot',
        version: @version,
        source: source.to_s,
        reason: reason.to_s,
        model_key: model_key,
        source_path: source_path.to_s,
        json_path: json_path.to_s,
        json_paths: source_paths,
        source_mtime: source_mtime.to_f,
        json_mtime: json_mtime.to_f,
        rows_count: normalized.length,
        rows: normalized,
        rows_by_product: build_rows_by_product(normalized),
        product_names: build_product_names(normalized),
        loaded_at: Time.now.to_f,
        error: nil
      }
      remember_source(@snapshot)
      snapshot
    rescue => e
      error_snapshot('payload_error', e.message, json_path, source_path)
    end

    def ensure_loaded(json_path = nil, source_path: nil, strategy: :current_or_latest)
      json_path = json_path.to_s.strip
      return load_json(json_path, source_path: source_path) unless json_path.empty?
      return snapshot if @snapshot && @snapshot[:ok] && @snapshot[:model_key].to_s == current_model_key

      if defined?(MH::RegistryApp) && MH::RegistryApp.respond_to?(:load_runtime_project_data)
        sources, project_snapshot = MH::RegistryApp.load_runtime_project_data([], reason: 'project_data_ensure_loaded')
        return project_snapshot if sources && sources['ok'] && project_snapshot && project_snapshot[:ok]
      end

      remembered = remembered_source
      if remembered && !remembered[:json_path].to_s.empty?
        return load_json(remembered[:json_path], source_path: remembered[:source_path], force: false, reason: 'remembered_source')
      end

      error_snapshot('json_error', "No project JSON path for #{strategy}", nil, source_path)
    end

    def snapshot
      @snapshot || empty_snapshot
    end

    def status
      snap = snapshot
      snap.reject { |key, _| key == :rows || key == :rows_by_product || key == :product_names }
    end

    def rows
      Array(snapshot[:rows])
    end

    def rows_for_product(product_code, mode: :exact_or_base)
      code = normalize_product_code(product_code)
      return [] if code.empty?

      by_product = snapshot[:rows_by_product] || {}
      exact = Array(by_product[code])
      return exact unless exact.empty?
      return exact if mode.to_s == 'exact'

      base = product_base(code)
      return [] if base.empty? || base == code
      Array(by_product[base])
    end

    def product_name_for(product_code)
      code = normalize_product_code(product_code)
      return '' if code.empty?

      names = snapshot[:product_names] || {}
      names[code].to_s.empty? ? names[product_base(code)].to_s : names[code].to_s
    end

    def invalidate!(reason: nil)
      @snapshot = nil
      @last_error = nil
      @version = @version.to_i + 1
      true
    end

    def normalize_row(row)
      return {} unless row.is_a?(Hash)
      out = row.each_with_object({}) { |(key, value), memo| memo[key.to_s] = value }
      product = product_value(out)
      name = product_name_value(out)
      out['ma_sp'] = product if out['ma_sp'].to_s.strip.empty? && !product.to_s.strip.empty?
      out['ten_sp'] = name if out['ten_sp'].to_s.strip.empty? && !name.to_s.strip.empty?
      out
    end

    def product_value(row)
      PRODUCT_KEYS.each do |key|
        value = row[key].to_s.strip
        return value unless value.empty?
      end
      ''
    end

    def product_name_value(row)
      NAME_KEYS.each do |key|
        value = row[key].to_s.strip
        return value unless value.empty?
      end
      ''
    end

    def normalize_product_code(value)
      text = value.to_s.strip.upcase
      if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:exact)
        text = MH::ProductContext.exact(text).to_s
      end
      text
    rescue
      value.to_s.strip.upcase
    end

    def product_base(value)
      if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:base)
        MH::ProductContext.base(value).to_s
      else
        value.to_s.strip.upcase.split('.').first.to_s
      end
    rescue
      value.to_s.strip.upcase.split('.').first.to_s
    end

    def build_rows_by_product(rows)
      out = {}
      rows.each do |row|
        code = normalize_product_code(product_value(row))
        next if code.empty?
        out[code] ||= []
        out[code] << row
        base = product_base(code)
        if !base.empty? && base != code
          out[base] ||= []
          out[base] << row
        end
      end
      out
    end

    def build_product_names(rows)
      out = {}
      rows.each do |row|
        code = normalize_product_code(product_value(row))
        name = product_name_value(row)
        next if code.empty? || name.empty?
        out[code] ||= name
        base = product_base(code)
        out[base] ||= name unless base.empty?
      end
      out
    end

    def file_mtime(path)
      path = path.to_s
      path.empty? || !File.exist?(path) ? 0.0 : File.mtime(path).to_f
    rescue
      0.0
    end

    def current_matches?(json_path, source_path, json_mtime, source_mtime, model_key)
      snap = @snapshot
      return false unless snap && snap[:ok]
      snap[:json_path].to_s == json_path.to_s &&
        snap[:source_path].to_s == source_path.to_s &&
        snap[:json_mtime].to_f == json_mtime.to_f &&
        snap[:source_mtime].to_f == source_mtime.to_f &&
        snap[:model_key].to_s == model_key.to_s
    end

    def current_model_key
      if defined?(Sketchup) && Sketchup.respond_to?(:active_model) && Sketchup.active_model
        model = Sketchup.active_model
        path = model.path.to_s.strip rescue ''
        return "path:#{File.expand_path(path).tr('\\', '/').downcase}" unless path.empty?
        guid = model.guid.to_s rescue ''
        return "guid:#{guid}" unless guid.empty?
        return "object:#{model.object_id}"
      end
      'model:unknown'
    rescue
      'model:unknown'
    end

    def active_model
      defined?(Sketchup) && Sketchup.respond_to?(:active_model) ? Sketchup.active_model : nil
    rescue
      nil
    end

    def remember_source(snap)
      model = active_model
      return false unless model && snap && snap[:ok]
      return false if snap[:json_path].to_s.strip.empty?

      model.set_attribute(ATTR_DICT, ATTR_JSON_PATH, snap[:json_path].to_s) rescue nil
      model.set_attribute(ATTR_DICT, ATTR_SOURCE_PATH, snap[:source_path].to_s) rescue nil
      model.set_attribute(ATTR_DICT, ATTR_MODEL_KEY, snap[:model_key].to_s) rescue nil
      true
    rescue
      false
    end

    def remembered_source
      model = active_model
      return nil unless model

      json_path = model.get_attribute(ATTR_DICT, ATTR_JSON_PATH).to_s rescue ''
      source_path = model.get_attribute(ATTR_DICT, ATTR_SOURCE_PATH).to_s rescue ''
      stored_model_key = model.get_attribute(ATTR_DICT, ATTR_MODEL_KEY).to_s rescue ''
      return nil if json_path.strip.empty?
      return nil if !stored_model_key.empty? && stored_model_key != current_model_key

      { json_path: json_path, source_path: source_path }
    rescue
      nil
    end

    def empty_snapshot
      {
        ok: false,
        mode: 'empty',
        version: @version.to_i,
        model_key: current_model_key,
        rows_count: 0,
        rows: [],
        rows_by_product: {},
        product_names: {},
        error: @last_error
      }
    end

    def error_snapshot(mode, message, json_path, source_path)
      @last_error = message.to_s
      @snapshot = {
        ok: false,
        mode: mode.to_s,
        version: @version.to_i,
        model_key: current_model_key,
        source_path: source_path.to_s,
        json_path: json_path.to_s,
        rows_count: 0,
        rows: [],
        rows_by_product: {},
        product_names: {},
        loaded_at: Time.now.to_f,
        fallback_used: false,
        error: @last_error
      }
      snapshot
    end
  end
end

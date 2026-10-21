# MH_fast_rename v93 - CPv5 Logic Integrated & Box Slicing

require 'sketchup.rb'
require File.join(Sketchup.find_support_file('Plugins'), 'MH_shared.rb')
raise "[MH_fast_rename] requires MH_shared" unless defined?(MH::Shared) && defined?(MH::Bounds)

module MH
  module FastRename
    class << self
      old_bounds_method = %w[split_bounds for_entity].join('_').to_sym
      remove_method(old_bounds_method) if method_defined?(old_bounds_method)
    end

    # ════════════════════════════════════════════════════════════════
    # CONSTANTS
    # ════════════════════════════════════════════════════════════════
    DEBUG = false unless const_defined?(:DEBUG, false)
    CP_TOL      = 0.05 / 25.4   unless defined?(CP_TOL)
    CP_PENE_TOL = 0.05 / 25.4   unless defined?(CP_PENE_TOL)

    # Force-refresh keyword constants on each load so Reload applies new rules.
    remove_const(:AUTO_SPLIT_FAST_LIMIT) if const_defined?(:AUTO_SPLIT_FAST_LIMIT, false)
    remove_const(:EXEMPT_KEYWORDS) if const_defined?(:EXEMPT_KEYWORDS, false)
    remove_const(:ABF_PREFIX) if const_defined?(:ABF_PREFIX, false)
    remove_const(:ABF_PREFIXES) if const_defined?(:ABF_PREFIXES, false)
    remove_const(:SP_BASE_ONLY_KEYWORDS) if const_defined?(:SP_BASE_ONLY_KEYWORDS, false)
    remove_const(:MODUL_CONTACT_KEYWORDS) if const_defined?(:MODUL_CONTACT_KEYWORDS, false)
    remove_const(:NAMED_CONTACT_SPLIT_PAIRS) if const_defined?(:NAMED_CONTACT_SPLIT_PAIRS, false)
    remove_const(:BASE_ACCESSORY_KEYWORDS) if const_defined?(:BASE_ACCESSORY_KEYWORDS, false)
    remove_const(:EXEMPT_KEYWORDS_NORM) if const_defined?(:EXEMPT_KEYWORDS_NORM, false)
    remove_const(:SP_BASE_ONLY_KEYWORDS_NORM) if const_defined?(:SP_BASE_ONLY_KEYWORDS_NORM, false)
    remove_const(:MODUL_CONTACT_KEYWORDS_NORM) if const_defined?(:MODUL_CONTACT_KEYWORDS_NORM, false)
    remove_const(:BASE_ACCESSORY_KEYWORDS_NORM) if const_defined?(:BASE_ACCESSORY_KEYWORDS_NORM, false)
    remove_const(:CP_SEPARATOR_AXES) if const_defined?(:CP_SEPARATOR_AXES, false)

    CP_MAX_PASS = 20             unless defined?(CP_MAX_PASS)
    CP_SEPARATOR_AXES = [
      Geom::Vector3d.new(1, 0, 0),
      Geom::Vector3d.new(0, 0, 1)
    ].freeze

    EXEMPT_KEYWORDS = [
      "phào nóc", "phao noc",
      "len chân", "len chan",
      "xương nẹp", "xuong nep",
      "chân bệ", "chan be",
      "len bệ chân", "len be chan",
      "len bệ", "len be",
      "bệ chân", "be chan",
      "chặn cánh", "chan canh"
    ].freeze
    ABF_PREFIX = "abf_".freeze
    ABF_PREFIXES = ["abf_", "_abf_"].freeze
    SP_BASE_ONLY_KEYWORDS = [
      "xương nẹp", "xuong nep",
      "phào nóc", "phao noc",
      "len chân", "len chan",
      "chân bệ", "chan be",
      "len bệ chân", "len be chan",
      "len bệ", "len be",
      "bệ chân", "be chan",
      "chặn cánh", "chan canh"
    ].freeze
    MODUL_CONTACT_KEYWORDS = [].freeze
    BASE_ACCESSORY_KEYWORDS = [
      "len chân", "len chan",
      "len bệ chân", "len be chan",
      "len bệ", "len be",
      "bệ chân", "be chan"
    ].freeze
    NAMED_CONTACT_SPLIT_PAIRS = [
      { a: ["hông trái", "hong trai"], b: ["hông phải", "hong phai"], axis: :x },
      { a: ["đáy", "day"], b: ["nóc", "noc"], axis: :z }
    ].freeze

    # ════════════════════════════════════════════════════════════════
    # UNICODE HELPERS
    # ════════════════════════════════════════════════════════════════
    def self.normalize_name_for_match(str)
      MH::Text.fold(str)
    end

    def self.normalized_keyword_list(keywords)
      @normalized_keyword_cache ||= {}
      cache_key = keywords.object_id
      @normalized_keyword_cache[cache_key] ||= Array(keywords).map { |kw| normalize_name_for_match(kw) }.reject(&:empty?).freeze
    end

    EXEMPT_KEYWORDS_NORM = EXEMPT_KEYWORDS.map { |kw| normalize_name_for_match(kw) }.freeze
    SP_BASE_ONLY_KEYWORDS_NORM = SP_BASE_ONLY_KEYWORDS.map { |kw| normalize_name_for_match(kw) }.freeze
    MODUL_CONTACT_KEYWORDS_NORM = MODUL_CONTACT_KEYWORDS.map { |kw| normalize_name_for_match(kw) }.freeze
    BASE_ACCESSORY_KEYWORDS_NORM = BASE_ACCESSORY_KEYWORDS.map { |kw| normalize_name_for_match(kw) }.freeze

    FAST_RENAME_SETTING_DEFAULTS = {
      'gap_threshold_mm' => 1000.0,
      'default_sp_start_num' => 1,
      'default_split_axis' => 'x',
      'split_all_default' => false,
      'auto_contact_split' => true,
      'cp_tolerance_mm' => 0.05,
      'cp_penetration_tolerance_mm' => 0.05,
      'cp_max_pass' => 20,
      'cp_separator_axes' => %w[x z],
      'exempt_keywords' => EXEMPT_KEYWORDS,
      'sp_base_only_keywords' => SP_BASE_ONLY_KEYWORDS,
      'modul_contact_keywords' => MODUL_CONTACT_KEYWORDS,
      'base_accessory_keywords' => BASE_ACCESSORY_KEYWORDS,
      'named_contact_split_pairs' => NAMED_CONTACT_SPLIT_PAIRS.map { |row|
        { 'a' => Array(row[:a]), 'b' => Array(row[:b]), 'axis' => row[:axis].to_s }
      }
    }.freeze

    def self.dbg(message)
      puts message if DEBUG
    end

    def self.invalidate_settings_cache
      @settings_cache = nil
      @setting_list_cache = nil
      @setting_norm_cache = nil
      @cp_tol = nil
      @cp_pene_tol = nil
      @cp_max_pass = nil
      @cp_separator_axes = nil
      @named_contact_split_pairs = nil
    end

    def self.settings_cache
      return @settings_cache if @settings_cache

      cache = {}
      FAST_RENAME_SETTING_DEFAULTS.each do |key, fallback|
        cache[key] = if defined?(MH::Settings) && MH::Settings.respond_to?(:read)
          MH::Settings.read('fast_rename', key, fallback, scope: :global)
        else
          fallback
        end
      end
      @settings_cache = cache
    rescue
      @settings_cache = FAST_RENAME_SETTING_DEFAULTS.dup
    end

    def self.setting_value(key, fallback = nil)
      k = key.to_s
      fallback = FAST_RENAME_SETTING_DEFAULTS[k] if fallback.nil? && FAST_RENAME_SETTING_DEFAULTS.key?(k)
      cache = settings_cache
      cache.key?(k) ? cache[k] : fallback
    rescue
      fallback
    end

    def self.setting_bool(key, fallback = false)
      value = setting_value(key, fallback)
      return value if value == true || value == false
      text = value.to_s.strip.downcase
      return true if %w[true 1 yes on].include?(text)
      return false if %w[false 0 no off].include?(text)
      fallback
    end

    def self.setting_float(key, fallback)
      value = setting_value(key, fallback)
      number = value.to_f
      number.positive? ? number : fallback
    rescue
      fallback
    end

    def self.setting_int(key, fallback)
      value = setting_value(key, fallback)
      number = value.to_i
      number.positive? ? number : fallback
    rescue
      fallback
    end

    def self.setting_list(key, fallback = [])
      @setting_list_cache ||= {}
      k = key.to_s
      @setting_list_cache[k] ||= begin
        value = setting_value(k, fallback)
        list = value.is_a?(Array) ? value : value.to_s.split(/\r?\n|,/)
        list.map(&:to_s).map(&:strip).reject(&:empty?).freeze
      end
    rescue
      Array(fallback)
    end

    def self.default_split_axis_index
      axes = [:x, :z, :y]
      axis = setting_value('default_split_axis', 'x').to_s.downcase.to_sym
      axes.index(axis) || 0
    end

    def self.auto_contact_split?
      setting_bool('auto_contact_split', true)
    end

    def self.cp_tol
      @cp_tol ||= setting_float('cp_tolerance_mm', 0.05) / 25.4
    end

    def self.cp_pene_tol
      @cp_pene_tol ||= setting_float('cp_penetration_tolerance_mm', 0.05) / 25.4
    end

    def self.cp_max_pass
      @cp_max_pass ||= [[setting_int('cp_max_pass', CP_MAX_PASS), 1].max, 200].min
    end

    def self.cp_separator_axes
      @cp_separator_axes ||= begin
        raw = setting_value('cp_separator_axes', %w[x z])
        axes = (raw.is_a?(Array) ? raw : raw.to_s.split(/[,;\s]+/)).map { |v| v.to_s.downcase.strip }
        vectors = axes.uniq.map do |axis|
          case axis
          when 'x' then Geom::Vector3d.new(1, 0, 0)
          when 'y' then Geom::Vector3d.new(0, 1, 0)
          when 'z' then Geom::Vector3d.new(0, 0, 1)
          end
        end.compact
        vectors.empty? ? CP_SEPARATOR_AXES : vectors.freeze
      end
    rescue
      CP_SEPARATOR_AXES
    end

    def self.exempt_keywords_norm
      @setting_norm_cache ||= {}
      @setting_norm_cache['exempt_keywords'] ||= normalized_keyword_list(setting_list('exempt_keywords', EXEMPT_KEYWORDS))
    end

    def self.sp_base_only_keywords_norm
      @setting_norm_cache ||= {}
      @setting_norm_cache['sp_base_only_keywords'] ||= normalized_keyword_list(setting_list('sp_base_only_keywords', SP_BASE_ONLY_KEYWORDS))
    end

    def self.modul_contact_keywords_norm
      @setting_norm_cache ||= {}
      @setting_norm_cache['modul_contact_keywords'] ||= normalized_keyword_list(setting_list('modul_contact_keywords', MODUL_CONTACT_KEYWORDS))
    end

    def self.base_accessory_keywords_norm
      @setting_norm_cache ||= {}
      @setting_norm_cache['base_accessory_keywords'] ||= normalized_keyword_list(setting_list('base_accessory_keywords', BASE_ACCESSORY_KEYWORDS))
    end

    def self.named_contact_split_pairs
      @named_contact_split_pairs ||= Array(setting_value('named_contact_split_pairs', FAST_RENAME_SETTING_DEFAULTS['named_contact_split_pairs'])).freeze
    end

    def self.name_has_keyword?(name, keywords, keywords_normalized = false)
      normalized = normalize_name_for_match(name)
      search_keywords = keywords_normalized ? keywords : normalized_keyword_list(keywords)
      search_keywords.any? do |kw|
        normalized.include?(kw)
      end
    end

    def self.entity_cache_entry(entity, entity_cache = nil)
      return nil unless entity_cache
      key = split_bounds_cache_key(entity)
      entity_cache[key] ||= {}
    end

    def self.entity_full_name_cached(entity, entity_cache = nil)
      entry = entity_cache_entry(entity, entity_cache)
      return entity_full_name(entity) unless entry
      entry[:full_name] ||= entity_full_name(entity)
    end

    def self.entity_normalized_name(entity, entity_cache = nil)
      entry = entity_cache_entry(entity, entity_cache)
      return normalize_name_for_match(entity_full_name(entity)) unless entry
      entry[:normalized_name] ||= normalize_name_for_match(entity_full_name_cached(entity, entity_cache))
    end

    def self.normalized_entity_has_keyword?(entity, keywords_norm, entity_cache = nil)
      normalized = entity_normalized_name(entity, entity_cache)
      keywords_norm.any? { |kw| normalized.include?(kw) }
    end

    def self.product_family
      if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:active_family)
        family = MH::ProductContext.active_family.to_s.strip
        return family.upcase unless family.empty?
      end
      'SP'
    end

    def self.format_product_code(number, family = nil)
      fam = family.to_s.strip
      fam = product_family if fam.empty?
      if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:format_code)
        return MH::ProductContext.format_code(number, family: fam)
      end
      "#{fam}%02d" % number.to_i
    end

    def self.product_base_label(label)
      text = label.to_s.strip
      if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:base) && MH::ProductContext.respond_to?(:valid?)
        base = MH::ProductContext.base(text)
        return base if MH::ProductContext.valid?(base)
      end
      if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:first_product)
        code = MH::NameGrammar.first_product(text).to_s
        unless code.empty?
          parsed = MH::NameGrammar.respond_to?(:parse) ? MH::NameGrammar.parse(code) : nil
          return parsed[:product].to_s.upcase if parsed && parsed[:recognized] && !parsed[:product].to_s.empty?
          return code.split('.').first.to_s.upcase
        end
      end
      family = product_family
      match = text.match(/\A(#{Regexp.escape(family)}\d+[A-Z]?)/i)
      match ? match[1].upcase : ''
    end

    def self.product_number(label)
      if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:number)
        num = MH::ProductContext.number(label)
        return num if num
      end
      base = product_base_label(label)
      match = base.match(/\d+/)
      match ? match[0].to_i : nil
    end

    def self.replace_product_number(label, new_number)
      if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:with_number)
        return MH::ProductContext.with_number(label, new_number)
      end
      base = product_base_label(label)
      return label.to_s if base.empty?
      label.to_s.sub(/\A#{Regexp.escape(base)}/i, format_product_code(new_number))
    end

    def self.sys_prefix(raw)
      match = raw.to_s.match(/\A(_+\d+)\.?\s*/)
      match ? "#{match[1]}. " : ''
    end

    def self.strip_sys_prefix(raw)
      raw.to_s.sub(/\A_+\d+\.?\s*/, '')
    end

    def self.strip_leading_module_tokens(text)
      value = text.to_s.strip
      separators = ['_', '.', '-', ' ']
      if defined?(MH::NameGrammar)
        separators << MH::NameGrammar.module_separator.to_s if MH::NameGrammar.respond_to?(:module_separator)
        separators << MH::NameGrammar.part_separator.to_s if MH::NameGrammar.respond_to?(:part_separator)
      end
      sep_class = Regexp.escape(separators.reject(&:empty?).uniq.join)

      loop do
        next_value = value.sub(/\A(?:MD)?\d+[\s#{sep_class}]+/i, '')
        break if next_value == value
        value = next_value.strip
      end
      value
    end

    def self.strip_product_module_prefix(raw)
      text = strip_sys_prefix(raw).to_s.strip
      if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:parse)
        parsed = MH::NameGrammar.parse(text)
        return strip_leading_module_tokens(parsed[:part].to_s) if parsed && parsed[:recognized]
      end

      code = defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:first_product) ? MH::NameGrammar.first_product(text).to_s : ''
      unless code.empty?
        text = text.sub(/\A#{Regexp.escape(code)}[\s._-]*/i, '')
        return strip_leading_module_tokens(text)
      end

      family = product_family
      text = text.sub(/\A#{Regexp.escape(family)}\d+[A-Z]?(?:[._-][A-Za-z0-9]+)*[\s._-]*/i, '')
      strip_leading_module_tokens(text)
    rescue
      strip_sys_prefix(raw).to_s.strip
    end

    def self.clear_product_module_prefixes(entities)
      renamed = 0
      Array(entities).compact.uniq.each do |entity|
        next unless entity && entity.valid? && entity.respond_to?(:name)
        raw = entity.name.to_s
        clean = strip_product_module_prefix(raw)
        final_name = "#{sys_prefix(raw)}#{clean}"
        next if final_name == raw
        entity.name = final_name
        renamed += 1
      end
      renamed
    end

    # Lấy tên đầy đủ: instance name + definition name (cả 2)
    def self.entity_full_name(obj)
      parts = []
      if obj.respond_to?(:definition)
        parts << obj.name.to_s if obj.respond_to?(:name)
        parts << obj.definition.name.to_s
      else
        parts << (obj.name || "").to_s
      end
      parts.join(" ")
    end

    def self.sp_base_only_entity?(entity)
      name_has_keyword?(entity_full_name(entity), sp_base_only_keywords_norm, true)
    rescue
      false
    end

    def self.sp_base_only_entity_cached?(entity, entity_cache = nil)
      entry = entity_cache_entry(entity, entity_cache)
      return sp_base_only_entity?(entity) unless entry
      return entry[:sp_base_only] if entry.key?(:sp_base_only)
      entry[:sp_base_only] = normalized_entity_has_keyword?(entity, sp_base_only_keywords_norm, entity_cache)
    rescue
      false
    end

    def self.modul_contact_entity?(entity)
      name_has_keyword?(entity_full_name(entity), modul_contact_keywords_norm, true)
    rescue
      false
    end

    def self.modul_contact_entity_cached?(entity, entity_cache = nil)
      entry = entity_cache_entry(entity, entity_cache)
      return modul_contact_entity?(entity) unless entry
      return entry[:modul_contact] if entry.key?(:modul_contact)
      entry[:modul_contact] = normalized_entity_has_keyword?(entity, modul_contact_keywords_norm, entity_cache)
    rescue
      false
    end

    def self.virtual_box_excluded_entity?(entity)
      sp_base_only_entity?(entity) || modul_contact_entity?(entity)
    end

    def self.virtual_box_excluded_entity_cached?(entity, entity_cache = nil)
      sp_base_only_entity_cached?(entity, entity_cache) || modul_contact_entity_cached?(entity, entity_cache)
    end

    def self.exempt_entity?(obj)
      return true if name_has_keyword?(entity_full_name(obj), exempt_keywords_norm, true)
      return true if virtual_box_excluded_entity?(obj)
      return true if abf_prefixed_entity?(obj)
      return true if split_container_entity?(obj) && content_bounds_for_entity(obj).nil?
      false
    end

    def self.abf_name?(name)
      n = name.to_s.strip
      !n.empty? && ABF_PREFIXES.any? { |prefix| n.downcase.start_with?(prefix) }
    end

    def self.abf_prefixed_entity?(entity)
      return false unless entity
      return true if entity.respond_to?(:name) && abf_name?(entity.name)
      return false unless entity.respond_to?(:definition) && entity.definition
      abf_name?(entity.definition.name)
    rescue
      false
    end

    def self.split_container_entity?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end

    def self.add_bounds_points(points, bounds, tr)
      mn = bounds.min
      mx = bounds.max
      corners = [
        Geom::Point3d.new(mn.x, mn.y, mn.z), Geom::Point3d.new(mx.x, mn.y, mn.z),
        Geom::Point3d.new(mx.x, mx.y, mn.z), Geom::Point3d.new(mn.x, mx.y, mn.z),
        Geom::Point3d.new(mn.x, mn.y, mx.z), Geom::Point3d.new(mx.x, mn.y, mx.z),
        Geom::Point3d.new(mx.x, mx.y, mx.z), Geom::Point3d.new(mn.x, mx.y, mx.z)
      ]
      corners.each { |pt| points << (tr * pt) }
    end

    def self.collect_non_abf_points(entity, tr, points, split_bounds_cache = nil)
      return unless entity
      return if split_excluded_entity_cached?(entity, split_bounds_cache)

      if split_container_entity?(entity)
        next_tr = tr * entity.transformation
        ents = entity.respond_to?(:definition) ? entity.definition.entities : entity.entities
        ents.each { |child| collect_non_abf_points(child, next_tr, points, split_bounds_cache) }
        return
      end

      return unless entity.respond_to?(:bounds)
      add_bounds_points(points, entity.bounds, tr)
    rescue
      nil
    end

    # Bounds dùng cho split: bỏ qua toàn bộ subtree có tên bắt đầu ABF_
    def self.split_bounds_cache_key(entity)
      return nil unless entity
      entity.respond_to?(:persistent_id) ? entity.persistent_id : entity.object_id
    rescue
      entity.object_id
    end

    def self.split_excluded_entity?(entity, split_bounds_cache = nil)
      return false unless split_container_entity?(entity)
      return true if abf_prefixed_entity?(entity)
      return true if virtual_box_excluded_entity?(entity)
      false
    end

    def self.split_excluded_entity_cached?(entity, split_bounds_cache = nil)
      return false unless split_container_entity?(entity)
      return split_excluded_entity?(entity) unless split_bounds_cache
      key = [:excluded, split_bounds_cache_key(entity)]
      return split_bounds_cache[key] if split_bounds_cache.key?(key)
      split_bounds_cache[key] = split_excluded_entity?(entity)
    rescue
      false
    end

    def self.content_bounds_for_entity(entity, split_bounds_cache = nil)
      return nil unless entity

      cache_key = split_bounds_cache ? split_bounds_cache_key(entity) : nil
      if split_bounds_cache && split_bounds_cache.key?(cache_key)
        return split_bounds_cache[cache_key]
      end

      return nil if split_excluded_entity_cached?(entity, split_bounds_cache)
      result = MH::Bounds.content_bounds(
        entity,
        reject: ->(child) { split_excluded_entity_cached?(child, split_bounds_cache) }
      )
      split_bounds_cache[cache_key] = result if split_bounds_cache
      result
    rescue
      result = entity.bounds
      split_bounds_cache[cache_key] = result if split_bounds_cache
      result
    end

    def self.bounds_from_entities(entities, split_bounds_cache = nil)
      return nil unless entities && !entities.empty?
      bb = Geom::BoundingBox.new
      has_any = false
      entities.each do |e|
        next unless e && e.valid?
        eb = content_bounds_for_entity(e, split_bounds_cache)
        next unless eb
        bb.add(eb)
        has_any = true
      end
      return nil unless has_any
      [Geom::Point3d.new(bb.min.x, bb.min.y, bb.min.z),
       Geom::Point3d.new(bb.max.x, bb.max.y, bb.max.z)]
    end

    # ════════════════════════════════════════════════════════════════
    # GEOMETRY HELPERS – dùng chung cho splitting
    # ════════════════════════════════════════════════════════════════

    def self.get_faces_world(entity)
      t    = entity.transformation
      ents = entity.respond_to?(:definition) ? entity.definition.entities : entity.entities
      faces = []
      ents.grep(Sketchup::Face) do |face|
        pts = face.vertices.map { |v| t * v.position }
        next if pts.length < 3
        v1 = Geom::Vector3d.new(pts[1].x-pts[0].x, pts[1].y-pts[0].y, pts[1].z-pts[0].z)
        v2 = Geom::Vector3d.new(pts[2].x-pts[0].x, pts[2].y-pts[0].y, pts[2].z-pts[0].z)
        normal = v1.cross(v2)
        next if normal.length < 1e-10
        normal = normal.normalize
        orig_n     = face.normal
        orig_world = t * Geom::Point3d.new(orig_n.x, orig_n.y, orig_n.z)
        orig_o     = t * Geom::Point3d.new(0,0,0)
        orig_dir   = Geom::Vector3d.new(orig_world.x-orig_o.x,
                                        orig_world.y-orig_o.y,
                                        orig_world.z-orig_o.z)
        normal = Geom::Vector3d.new(-normal.x,-normal.y,-normal.z) if normal.dot(orig_dir) < 0
        faces << { pts: pts, normal: normal, owner: entity }
      end
      faces
    end

    def self.cp_make_perp(n)
      axes = defined?(MH::Geo::Poly2D) ? MH::Geo::Poly2D.axes_for_normal(n) : nil
      return axes[0] if axes

      ref = n.x.abs < 0.9 ? Geom::Vector3d.new(1, 0, 0) : Geom::Vector3d.new(0, 1, 0)
      ref.cross(n).normalize
    end

    def self.cp_make_axes(normal)
      axes = defined?(MH::Geo::Poly2D) ? MH::Geo::Poly2D.axes_for_normal(normal) : nil
      return axes if axes

      u = cp_make_perp(normal)
      v = normal.cross(u).normalize
      [u, v]
    end

    def self.cp_signed_area_2d(poly)
      return MH::Geo::Poly2D.signed_area(poly) if defined?(MH::Geo::Poly2D)

      n = poly.length
      area = 0.0
      n.times { |i| j = (i + 1) % n; area += poly[i][0] * poly[j][1] - poly[j][0] * poly[i][1] }
      area / 2.0
    end

    def self.cp_ensure_ccw(poly)
      return MH::Geo::Poly2D.ensure_ccw(poly) if defined?(MH::Geo::Poly2D)

      cp_signed_area_2d(poly) >= 0 ? poly : poly.reverse
    end

    def self.cp_project_pts(pts, normal, d, u, v)
      return MH::Geo::Poly2D.project_points(pts, normal, d, u: u, v: v) if defined?(MH::Geo::Poly2D)

      pts.map { |p|
        vec   = Geom::Vector3d.new(p.x, p.y, p.z)
        t_val = d - vec.dot(normal)
        p2    = Geom::Point3d.new(p.x+t_val*normal.x,
                                   p.y+t_val*normal.y,
                                   p.z+t_val*normal.z)
        [Geom::Vector3d.new(p2.x,p2.y,p2.z).dot(u),
         Geom::Vector3d.new(p2.x,p2.y,p2.z).dot(v)]
      }
    end

    def self.cp_clip_polygon(poly, ex1, ey1, ex2, ey2)
      return MH::Geo::Poly2D.clip_polygon(poly, ex1, ey1, ex2, ey2) if defined?(MH::Geo::Poly2D)

      output = []
      return output if poly.empty?
      inside    = lambda { |x,y| (ex2-ex1)*(y-ey1)-(ey2-ey1)*(x-ex1) >= -1e-10 }
      intersect = lambda { |x1,y1,x2,y2|
        dx1=x2-x1; dy1=y2-y1; dx2=ex2-ex1; dy2=ey2-ey1
        denom=dx1*dy2-dy1*dx2
        return [x1,y1] if denom.abs < 1e-10
        t=((ex1-x1)*dy2-(ey1-y1)*dx2)/denom
        [x1+t*dx1, y1+t*dy1]
      }
      n = poly.length
      n.times do |i|
        cur=poly[i]; prev=poly[(i-1+n)%n]
        ci=inside.call(cur[0],cur[1]); pi=inside.call(prev[0],prev[1])
        if ci
          output << intersect.call(prev[0],prev[1],cur[0],cur[1]) unless pi
          output << cur
        elsif pi
          output << intersect.call(prev[0],prev[1],cur[0],cur[1])
        end
      end
      output
    end

    def self.cp_poly_intersect(polyA, polyB)
      return MH::Geo::Poly2D.intersection(polyA, polyB) if defined?(MH::Geo::Poly2D)

      a = cp_ensure_ccw(polyA); b = cp_ensure_ccw(polyB)
      result = a.dup
      b.length.times do |i|
        break if result.empty?
        ex1,ey1=b[i]; ex2,ey2=b[(i+1)%b.length]
        result = cp_clip_polygon(result, ex1, ey1, ex2, ey2)
      end
      result
    end

    def self.cp_faces_contact?(fa, fb)
      return false unless fa[:normal].dot(fb[:normal]) < -0.99
      tol = cp_tol
      pene_tol = cp_pene_tol
      d_a = Geom::Vector3d.new(fa[:pts][0].x,fa[:pts][0].y,fa[:pts][0].z).dot(fa[:normal])
      d_b = Geom::Vector3d.new(fb[:pts][0].x,fb[:pts][0].y,fb[:pts][0].z).dot(fa[:normal])
      gap = d_b - d_a
      return false if gap < -pene_tol || gap > tol
      u, v   = cp_make_axes(fa[:normal])
      poly_a = cp_project_pts(fa[:pts], fa[:normal], d_a, u, v)
      poly_b = cp_project_pts(fb[:pts], fa[:normal], d_a, u, v)
      inter  = cp_poly_intersect(poly_a, poly_b)
      return false if inter.length < 3 || cp_signed_area_2d(inter).abs < 1e-6
      true
    end

    def self.cp_plane_cuts_bb?(bb, normal, d)
      tol = cp_tol
      mn = bb.min
      mx = bb.max
      nx = normal.x
      ny = normal.y
      nz = normal.z
      eps = 1e-12
      if ny.abs < eps && nz.abs < eps
        min_val = nx >= 0 ? nx * mn.x : nx * mx.x
        max_val = nx >= 0 ? nx * mx.x : nx * mn.x
        return min_val - d < -tol && max_val - d > tol
      elsif nx.abs < eps && nz.abs < eps
        min_val = ny >= 0 ? ny * mn.y : ny * mx.y
        max_val = ny >= 0 ? ny * mx.y : ny * mn.y
        return min_val - d < -tol && max_val - d > tol
      elsif nx.abs < eps && ny.abs < eps
        min_val = nz >= 0 ? nz * mn.z : nz * mx.z
        max_val = nz >= 0 ? nz * mx.z : nz * mn.z
        return min_val - d < -tol && max_val - d > tol
      end
      min_sign = Float::INFINITY
      max_sign = -Float::INFINITY
      2.times do |xi|
        x = xi == 0 ? mn.x : mx.x
        2.times do |yi|
          y = yi == 0 ? mn.y : mx.y
          2.times do |zi|
            z = zi == 0 ? mn.z : mx.z
            sign = nx * x + ny * y + nz * z - d
            min_sign = sign if sign < min_sign
            max_sign = sign if sign > max_sign
          end
        end
      end
      min_sign < -tol && max_sign > tol
    end

    def self.cp_plane_cuts?(obj, normal, d)
      bb = content_bounds_for_entity(obj) || obj.bounds
      cp_plane_cuts_bb?(bb, normal, d)
    end

    def self.cp_obj_center(obj)
      bb = content_bounds_for_entity(obj) || obj.bounds
      Geom::Point3d.new((bb.min.x + bb.max.x) / 2.0,
                        (bb.min.y + bb.max.y) / 2.0,
                        (bb.min.z + bb.max.z) / 2.0)
    end

    # ════════════════════════════════════════════════════════════════
    # SEPARATOR SCORE – strict + miễn trừ EXEMPT_KEYWORDS
    # ════════════════════════════════════════════════════════════════
    def self.cp_separator_score_legacy(grp, normal, d_val)
      dots = []
      grp.each do |obj|
        next if exempt_entity?(obj)          # phào/nẹp → bỏ qua hoàn toàn
        return -1 if cp_plane_cuts?(obj, normal, d_val)  # cắt xuyên obj thường → loại
        c = cp_obj_center(obj)
        dots << (normal.x*c.x + normal.y*c.y + normal.z*c.z - d_val)
      end
      n_pos = dots.count { |s| s >= 0 }
      n_neg = dots.count { |s| s <  0 }
      return -1 if n_pos == 0 || n_neg == 0
      [n_pos, n_neg].min.to_f
    end

    def self.center_tuple_for_entity(entity, split_bounds_cache = nil, center_cache = nil)
      if center_cache
        key = split_bounds_cache_key(entity)
        cached = center_cache[key]
        return cached if cached
      end
      bb = content_bounds_for_entity(entity, split_bounds_cache) || entity.bounds
      return nil unless bb
      tuple = [
        (bb.min.x + bb.max.x) * 0.5,
        (bb.min.y + bb.max.y) * 0.5,
        (bb.min.z + bb.max.z) * 0.5
      ]
      center_cache[split_bounds_cache_key(entity)] = tuple if center_cache
      tuple
    end

    # ════════════════════════════════════════════════════════════════
    # TÌM TẤT CẢ SEPARATORS – 3 trục, không theo thứ tự
    # ════════════════════════════════════════════════════════════════
    def self.cp_separator_score(grp, normal, d_val, split_bounds_cache = nil, exempt_cache = nil, center_cache = nil)
      nx = normal.x
      ny = normal.y
      nz = normal.z
      n_pos = 0
      n_neg = 0
      grp.each do |obj|
        if exempt_cache
          cache_key = split_bounds_cache_key(obj)
          skip_obj = if exempt_cache.key?(cache_key)
            exempt_cache[cache_key]
          else
            exempt_cache[cache_key] = name_has_keyword?(entity_full_name(obj), exempt_keywords_norm, true) || abf_prefixed_entity?(obj)
          end
          next if skip_obj
        else
          next if name_has_keyword?(entity_full_name(obj), exempt_keywords_norm, true)
          next if abf_prefixed_entity?(obj)
        end

        bb = content_bounds_for_entity(obj, split_bounds_cache)
        next unless bb
        return -1 if cp_plane_cuts_bb?(bb, normal, d_val)

        c = center_tuple_for_entity(obj, split_bounds_cache, center_cache)
        next unless c
        if nx * c[0] + ny * c[1] + nz * c[2] - d_val >= 0
          n_pos += 1
        else
          n_neg += 1
        end
      end
      return -1 if (n_pos + n_neg) == 0 || n_pos == 0 || n_neg == 0
      [n_pos, n_neg].min.to_f
    end

    def self.entity_matches_keywords?(entity, keywords)
      name_has_keyword?(entity_full_name(entity), keywords)
    rescue
      false
    end

    def self.base_accessory_entity?(entity)
      name_has_keyword?(entity_full_name(entity), base_accessory_keywords_norm, true)
    rescue
      false
    end

    def self.named_contact_axis_plane(bounds_a, bounds_b, axis)
      axis_idx = [:x, :y, :z].index(axis)
      return nil unless axis_idx

      a_min, a_max = bounds_a.min.to_a[axis_idx], bounds_a.max.to_a[axis_idx]
      b_min, b_max = bounds_b.min.to_a[axis_idx], bounds_b.max.to_a[axis_idx]
      touch_tol = cp_tol * 20

      return (a_max + b_min) * 0.5 if (a_max - b_min).abs <= touch_tol
      return (b_max + a_min) * 0.5 if (b_max - a_min).abs <= touch_tol
      nil
    end

    def self.bounds_overlap_except_axis?(bounds_a, bounds_b, axis)
      axis_idx = [:x, :y, :z].index(axis)
      return false unless axis_idx

      overlap_tol = cp_tol * 20
      3.times.all? do |idx|
        next true if idx == axis_idx
        a_min, a_max = bounds_a.min.to_a[idx], bounds_a.max.to_a[idx]
        b_min, b_max = bounds_b.min.to_a[idx], bounds_b.max.to_a[idx]
        a_min <= b_max + overlap_tol && b_min <= a_max + overlap_tol
      end
    end

    def self.cp_named_contact_separators(entities, split_bounds_cache = nil)
      return [] if entities.length < 2

      candidates = []
      seen_planes = []
      entity_cache = {}
      exempt_cache = {}
      center_cache = {}

      tol = cp_tol
      named_contact_split_pairs.each do |raw_pair|
        pair = if raw_pair.is_a?(Hash)
          {
            a: Array(raw_pair[:a] || raw_pair['a']),
            b: Array(raw_pair[:b] || raw_pair['b']),
            axis: (raw_pair[:axis] || raw_pair['axis']).to_s.downcase.to_sym
          }
        else
          nil
        end
        next unless pair && !pair[:a].empty? && !pair[:b].empty? && [:x, :y, :z].include?(pair[:axis])
        keywords_a = normalized_keyword_list(pair[:a])
        keywords_b = normalized_keyword_list(pair[:b])
        group_a = entities.select { |entity| entity && entity.valid? && normalized_entity_has_keyword?(entity, keywords_a, entity_cache) }
        group_b = entities.select { |entity| entity && entity.valid? && normalized_entity_has_keyword?(entity, keywords_b, entity_cache) }
        next if group_a.empty? || group_b.empty?

        group_a.each do |entity_a|
          bounds_a = content_bounds_for_entity(entity_a, split_bounds_cache) || entity_a.bounds
          next unless bounds_a

          group_b.each do |entity_b|
            next if entity_a == entity_b
            bounds_b = content_bounds_for_entity(entity_b, split_bounds_cache) || entity_b.bounds
            next unless bounds_b

            axis = pair[:axis]
            next unless bounds_overlap_except_axis?(bounds_a, bounds_b, axis)
            d_val = named_contact_axis_plane(bounds_a, bounds_b, axis)
            next unless d_val

            normal = case axis
            when :x then Geom::Vector3d.new(1, 0, 0)
            when :z then Geom::Vector3d.new(0, 0, 1)
            else Geom::Vector3d.new(0, 1, 0)
            end

            duplicate = seen_planes.any? { |sp| sp[:normal].dot(normal) > 0.9999 && (sp[:d] - d_val).abs < tol }
            next if duplicate
            seen_planes << { normal: normal, d: d_val }

            score = cp_separator_score(entities, normal, d_val, split_bounds_cache, exempt_cache, center_cache)
            next if score < 0 && cp_split_group(entities, normal, d_val, split_bounds_cache, center_cache).length != 2

            u, v = cp_make_axes(normal)
            candidates << { normal: normal, d: d_val, u: u, v: v, score: [score, 1.0].max, named_contact: true }
          end
        end
      end

      candidates
    end

    def self.cp_find_separators(grp, split_bounds_cache = nil, face_cache = nil, exempt_cache = nil, center_cache = nil)
      return [] if grp.length < 2

      all_faces   = grp.map { |obj| cached_faces_world(obj, face_cache) }
      bounds_flat = grp.map do |obj|
        bb = obj.bounds
        [bb.min.x, bb.max.x, bb.min.y, bb.max.y, bb.min.z, bb.max.z]
      end
      seen_planes = []
      candidates  = []
      tol = cp_tol
      separator_axes = cp_separator_axes

      try_add = lambda { |normal, d_val|
        # Chuẩn hóa về nửa cầu dương để tránh trùng lặp đảo chiều
        if normal.z < -1e-6 ||
           (normal.z.abs < 1e-6 && normal.y < -1e-6) ||
           (normal.z.abs < 1e-6 && normal.y.abs < 1e-6 && normal.x < -1e-6)
          normal = Geom::Vector3d.new(-normal.x, -normal.y, -normal.z)
          d_val  = -d_val
        end
        dup = seen_planes.any? { |sp|
          sp[:normal].dot(normal) > 0.9999 && (sp[:d] - d_val).abs < tol
        }
        return if dup
        seen_planes << { normal: normal, d: d_val }

        score = cp_separator_score(grp, normal, d_val, split_bounds_cache, exempt_cache, center_cache)
        return if score < 0

        u, v = cp_make_axes(normal)
        candidates << { normal: normal, d: d_val, u: u, v: v, score: score }
      }

      order_by_min_x = (0...grp.length).sort_by { |idx| bounds_flat[idx][0] }
      (0...grp.length).each do |i|
        ai = bounds_flat[i]
        possible_js = []
        order_by_min_x.each do |j|
          next if j <= i
          bj = bounds_flat[j]
          break if bj[0] > ai[1] + tol
          possible_js << j
        end
        possible_js.sort!
        possible_js.each do |j|
          bj = bounds_flat[j]
          next unless ai[0] <= bj[1] + tol && bj[0] <= ai[1] + tol &&
                      ai[2] <= bj[3] + tol && bj[2] <= ai[3] + tol &&
                      ai[4] <= bj[5] + tol && bj[4] <= ai[5] + tol
          all_faces[i].each do |fa|
            all_faces[j].each do |fb|
              next unless cp_faces_contact?(fa, fb)
              contact_pt = fa[:pts][0]
              cp_vec = Geom::Vector3d.new(contact_pt.x, contact_pt.y, contact_pt.z)
              separator_axes.each do |n_ax|
                try_add.call(n_ax, cp_vec.dot(n_ax))
              end
            end
          end
        end
      end

      candidates.sort_by { |c| -c[:score] }
    end

    # Split nhóm obj theo plane, obj miễn trừ đi theo phía center
    def self.cp_split_group(grp, normal, d, split_bounds_cache = nil, center_cache = nil)
      nx = normal.x
      ny = normal.y
      nz = normal.z
      g_pos = grp.select { |obj|
        c = center_tuple_for_entity(obj, split_bounds_cache, center_cache)
        c && (nx*c[0] + ny*c[1] + nz*c[2] >= d)
      }
      g_neg = grp.select { |obj|
        c = center_tuple_for_entity(obj, split_bounds_cache, center_cache)
        c && (nx*c[0] + ny*c[1] + nz*c[2] < d)
      }
      [g_pos, g_neg].reject(&:empty?)
    end

    # ════════════════════════════════════════════════════════════════
    # PHÂN TÁCH NHÓM OBJ → DANH SÁCH CÁC SUB-NHÓM
    # Trả về: Array of Array of entities
    # ════════════════════════════════════════════════════════════════
    # Kích thước nhóm tối thiểu sau khi split

    def self.split_entities_into_groups(entities, init_bounds = nil, split_bounds_cache = nil, extra_separators = nil, face_cache = nil)
      split_bounds_cache ||= {}
      extra_separators ||= []
      exempt_cache = {}
      center_cache = {}
      separator_cache = {}
      if init_bounds.nil?
        init_bounds = bounds_from_entities(entities, split_bounds_cache)
      end
      return [] unless init_bounds

      groups    = [{ ents: entities.dup, bounds: init_bounds }]

      cp_max_pass.times do
        any_split  = false
        new_groups = []

        groups.each do |grp_data|
          grp_ents = grp_data[:ents]
          if grp_ents.length < 2
            new_groups << grp_data
            next
          end

          separator_key = grp_ents.map { |ent| split_bounds_cache_key(ent) }.sort.join('|')
          found_separators = separator_cache[separator_key]
          unless found_separators
            found_separators = cp_find_separators(grp_ents, split_bounds_cache, face_cache, exempt_cache, center_cache)
            separator_cache[separator_key] = found_separators
          end

          separators = extra_separators.dup
          separators.concat(found_separators)

          if separators.empty?
            new_groups << grp_data
            next
          end

          sub_groups = [grp_data]

          # Áp dụng TẤT CẢ separators như contact_planes_v5.rb
          separators.each do |sep|
            next_subs = []
            sub_groups.each do |sg|
              score = cp_separator_score(sg[:ents], sep[:normal], sep[:d], split_bounds_cache, exempt_cache, center_cache)
              if score > 0 || sep[:named_contact]
                parts_ents = cp_split_group(sg[:ents], sep[:normal], sep[:d], split_bounds_cache, center_cache)
                if parts_ents.length == 2
                  # Slice bounds từ plane để tạo các box chia nhỏ
                  b_pos = bounds_from_entities(parts_ents[0], split_bounds_cache)
                  b_neg = bounds_from_entities(parts_ents[1], split_bounds_cache)
                  if b_pos && b_neg
                    any_split = true
                    next_subs << { ents: parts_ents[0], bounds: b_pos }
                    next_subs << { ents: parts_ents[1], bounds: b_neg }
                  else
                    next_subs << sg
                  end
                else
                  next_subs << sg
                end
              else
                next_subs << sg
              end
            end
            sub_groups = next_subs
          end
          new_groups.concat(sub_groups)
        end

        groups = new_groups
        break unless any_split
      end

      groups.map do |grp|
        precise_bounds = bounds_from_entities(grp[:ents], split_bounds_cache) || grp[:bounds]
        { ents: grp[:ents], bounds: precise_bounds }
      end
    end

    # ════════════════════════════════════════════════════════════════
    # GỘP CHI TIẾT ĐƠN LẺ VÀO NHÓM TIẾP XÚC
    #
    # Ưu tiên:
    #   1. Nhóm tạo thành bounding box vuông vức nhất khi gộp
    #      (tỉ lệ W:D:H gần 1:1:1, hoặc tổng diện tích bbox nhỏ nhất)
    #   2. Nhóm có diện tích tiếp xúc với chi tiết đơn lẻ lớn nhất
    # ════════════════════════════════════════════════════════════════

    # Tính diện tích tiếp xúc giữa obj đơn lẻ và 1 nhóm
    def self.bounds_pair_to_tuple(bounds)
      return nil unless bounds
      mn, mx = bounds
      [mn.x, mx.x, mn.y, mx.y, mn.z, mx.z]
    end

    def self.bounds_tuple_for_entity(entity, split_bounds_cache = nil)
      bb = content_bounds_for_entity(entity, split_bounds_cache) || entity.bounds
      [bb.min.x, bb.max.x, bb.min.y, bb.max.y, bb.min.z, bb.max.z]
    end

    def self.bounds_tuple_touch?(a, b, tol = nil)
      tol ||= cp_tol * 10
      a[0] <= b[1] + tol && b[0] <= a[1] + tol &&
        a[2] <= b[3] + tol && b[2] <= a[3] + tol &&
        a[4] <= b[5] + tol && b[4] <= a[5] + tol
    end

    def self.bounds_tuple_union(a, b)
      [[a[0], b[0]].min, [a[1], b[1]].max,
       [a[2], b[2]].min, [a[3], b[3]].max,
       [a[4], b[4]].min, [a[5], b[5]].max]
    end

    def self.bounds_tuple_to_pair(tuple)
      [Geom::Point3d.new(tuple[0], tuple[2], tuple[4]),
       Geom::Point3d.new(tuple[1], tuple[3], tuple[5])]
    end

    def self.squareness_score_for_tuple(tuple)
      w = (tuple[1] - tuple[0]).abs
      d = (tuple[3] - tuple[2]).abs
      h = (tuple[5] - tuple[4]).abs
      max_dim = [w, d, h].max
      return 0.0 if max_dim < 1e-6
      [w, d, h].min / max_dim.to_f
    end

    def self.cached_faces_world(entity, face_cache = nil)
      return get_faces_world(entity) unless face_cache
      key = split_bounds_cache_key(entity)
      face_cache[key] ||= get_faces_world(entity)
    end

    def self.contact_area_with_group(obj, grp, face_cache = nil, split_bounds_cache = nil)
      faces_a = cached_faces_world(obj, face_cache)
      obj_tuple = bounds_tuple_for_entity(obj, split_bounds_cache)
      total = 0.0
      tol = cp_tol
      pene_tol = cp_pene_tol
      grp.each do |other|
        next if other == obj
        other_tuple = bounds_tuple_for_entity(other, split_bounds_cache)
        next unless bounds_tuple_touch?(obj_tuple, other_tuple)
        faces_b = cached_faces_world(other, face_cache)
        faces_a.each do |fa|
          faces_b.each do |fb|
            next unless fa[:normal].dot(fb[:normal]) < -0.99
            d_a = Geom::Vector3d.new(fa[:pts][0].x,fa[:pts][0].y,fa[:pts][0].z).dot(fa[:normal])
            d_b = Geom::Vector3d.new(fb[:pts][0].x,fb[:pts][0].y,fb[:pts][0].z).dot(fa[:normal])
            gap = d_b - d_a
            next if gap < -pene_tol || gap > tol
            u, v   = cp_make_axes(fa[:normal])
            poly_a = cp_project_pts(fa[:pts], fa[:normal], d_a, u, v)
            poly_b = cp_project_pts(fb[:pts], fa[:normal], d_a, u, v)
            inter  = cp_poly_intersect(poly_a, poly_b)
            next if inter.length < 3
            total += cp_signed_area_2d(inter).abs
          end
        end
      end
      total
    end

    # Điểm "vuông vức" của bbox khi gộp obj vào grp
    # Score cao = bbox gần hình hộp lý tưởng hơn (tỉ lệ cân đối)
    # Dùng: 1 / (max_dim/min_dim) – càng gần 1 càng tốt
    def self.squareness_score(obj, grp)
      bb = Geom::BoundingBox.new
      (grp + [obj]).each { |e| bb.add(e.bounds) }
      w = (bb.max.x - bb.min.x).abs
      d = (bb.max.y - bb.min.y).abs
      h = (bb.max.z - bb.min.z).abs
      dims = [w, d, h].sort
      return 0.0 if dims[2] < 1e-6
      dims[0] / dims[2].to_f   # 0..1, 1 = hoàn toàn vuông vức
    end

    # Kiểm tra obj có tiếp xúc (bbox chạm) với bất kỳ obj nào trong grp không
    def self.touches_group?(obj, grp)
      bb_o = obj.bounds
      tol = cp_tol * 10
      grp.any? { |other|
        next false if other == obj
        bb_g = other.bounds
        (0..2).all? { |ax|
          bb_o.min.to_a[ax] <= bb_g.max.to_a[ax] + tol &&
          bb_g.min.to_a[ax] <= bb_o.max.to_a[ax] + tol
        }
      }
    end

    def self.merge_orphans_into_groups(groups, split_bounds_cache = nil, face_cache = nil)
      split_bounds_cache ||= {}
      face_cache ||= {}
      big_groups = groups.select { |g| g[:ents].length >= 2 }
      orphans = groups.select { |g| g[:ents].length == 1 }.map { |g| g[:ents].first }
      return groups if orphans.empty? || big_groups.empty?

      big_groups.each do |grp|
        grp[:bounds] ||= bounds_from_entities(grp[:ents], split_bounds_cache)
        grp[:bounds_tuple] = bounds_pair_to_tuple(grp[:bounds])
      end

      orphans.each do |obj|
        obj_tuple = bounds_tuple_for_entity(obj, split_bounds_cache)
        touching = big_groups.select do |grp|
          grp[:bounds_tuple] && bounds_tuple_touch?(obj_tuple, grp[:bounds_tuple])
        end
        candidates = touching.empty? ? big_groups : touching

        best_sq = -Float::INFINITY
        best_groups = []
        candidates.each do |grp|
          next unless grp[:bounds_tuple]
          sq = squareness_score_for_tuple(bounds_tuple_union(obj_tuple, grp[:bounds_tuple]))
          if sq > best_sq + 1e-9
            best_sq = sq
            best_groups = [grp]
          elsif (sq - best_sq).abs <= 1e-9
            best_groups << grp
          end
        end

        best_grp =
          if best_groups.length <= 1
            best_groups.first
          else
            best_groups.max_by { |grp| contact_area_with_group(obj, grp[:ents], face_cache, split_bounds_cache) }
          end

        if best_grp
          best_grp[:ents] << obj
          best_grp[:bounds_tuple] = bounds_tuple_union(best_grp[:bounds_tuple], obj_tuple)
          best_grp[:bounds] = bounds_tuple_to_pair(best_grp[:bounds_tuple])
        else
          big_groups << {
            ents: [obj],
            bounds_tuple: obj_tuple,
            bounds: bounds_tuple_to_pair(obj_tuple)
          }
        end
      end

      big_groups.each { |grp| grp.delete(:bounds_tuple) }
      big_groups.reject { |g| g[:ents].empty? }
    end

    # ════════════════════════════════════════════════════════════════
    # UNION-FIND
    # ════════════════════════════════════════════════════════════════
    class UnionFind
      def initialize(n)
        @parent = (0...n).to_a
        @rank   = Array.new(n, 0)
      end
      def find(x)
        root = x
        root = @parent[root] while @parent[root] != root
        while @parent[x] != root; nx = @parent[x]; @parent[x] = root; x = nx; end
        root
      end
      def union(a, b)
        ra = find(a); rb = find(b)
        return if ra == rb
        ra, rb = rb, ra if @rank[ra] < @rank[rb]
        @parent[rb] = ra
        @rank[ra] += 1 if @rank[ra] == @rank[rb]
      end
      def groups
        result = {}
        @parent.length.times { |i| (result[find(i)] ||= []) << i }
        result.values
      end
    end

    # ════════════════════════════════════════════════════════════════
    # ZONE CLASS
    # ════════════════════════════════════════════════════════════════
    class Zone
      attr_accessor :id, :label, :bounds, :entities, :zone_type,
                    :parent_id, :label_offset, :locked, :hidden

      def initialize(id, bounds, entities = [])
        @id = id; @bounds = bounds; @entities = entities
        @label = ""; @zone_type = :sp; @parent_id = nil
        @label_offset = 0; @locked = false; @hidden = false
      end

      def contains?(entity)
        bb = entity.bounds; center = bb.center
        mn, mx = @bounds
        center.x >= mn.x && center.x <= mx.x &&
          center.y >= mn.y && center.y <= mx.y &&
          center.z >= mn.z && center.z <= mx.z
      end

      def center
        mn, mx = @bounds
        Geom::Point3d.new((mn.x+mx.x)/2.0, (mn.y+mx.y)/2.0, (mn.z+mx.z)/2.0)
      end

      def width;  @bounds[1].x - @bounds[0].x; end
      def depth;  @bounds[1].y - @bounds[0].y; end
      def height; @bounds[1].z - @bounds[0].z; end

      def split(axis, pos)
        ents1 = []; ents2 = []
        @entities.each do |e|
          split_bb = MH::FastRename.content_bounds_for_entity(e) || e.bounds
          bb_min = split_bb.min.send(axis)
          bb_max = split_bb.max.send(axis)
          thickness = bb_max - bb_min
          if thickness < 1.0
            tol = 0.5 / 25.4
            if bb_max <= pos + tol
              ents1 << e
            elsif bb_min >= pos - tol
              ents2 << e
            else
              ol = [bb_max, pos].min - bb_min
              or_ = bb_max - [bb_min, pos].max
              ol >= or_ ? ents1 << e : ents2 << e
            end
          else
            ((bb_min + bb_max) / 2.0) < pos ? ents1 << e : ents2 << e
          end
        end
        zones = []
        zones << MH::FastRename.create_zone(0, ents1) if ents1.any?
        zones << MH::FastRename.create_zone(0, ents2) if ents2.any?
        zones
      end

      def corners
        mn, mx = @bounds
        [Geom::Point3d.new(mn.x,mn.y,mn.z), Geom::Point3d.new(mx.x,mn.y,mn.z),
         Geom::Point3d.new(mx.x,mx.y,mn.z), Geom::Point3d.new(mn.x,mx.y,mn.z),
         Geom::Point3d.new(mn.x,mn.y,mx.z), Geom::Point3d.new(mx.x,mn.y,mx.z),
         Geom::Point3d.new(mx.x,mx.y,mx.z), Geom::Point3d.new(mn.x,mx.y,mx.z)]
      end
    end

    # ════════════════════════════════════════════════════════════════
    # CLUSTERING & ZONE HELPERS
    # ════════════════════════════════════════════════════════════════
    def self.extract_sp_key(entity)
      return nil unless entity.respond_to?(:name)
      if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:code_from_entity)
        code = MH::ProductContext.code_from_entity(entity).to_s
        return code.upcase unless code.empty?
      end

      name = entity.name
      return nil if name.nil? || name.empty?
      code = defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:first_product) ? MH::NameGrammar.first_product(name).to_s : ''
      code.empty? ? nil : code.upcase
    end

    def self.extract_sp_base_key(entity)
      key = extract_sp_key(entity)
      return nil if key.nil? || key.empty?
      return MH::ProductContext.base(key) if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:base)

      base = product_base_label(key)
      base.empty? ? key.upcase : base
    end

    def self.extract_sp_module_key(entity, base_label = nil, module_rules = nil)
      return nil unless entity.respond_to?(:name)
      name = entity.name.to_s
      return nil if name.empty?
      clean = name.sub(/^_+\d+\.?\s*/, "")
      base = base_label.to_s.strip
      base = extract_sp_base_key(entity).to_s if base.empty?
      return nil if base.empty?

      rules = module_rules || registry_module_rules_for_sp(base)
      labels = rules.each_with_index.map { |rule, idx| registry_module_label(base, idx, rule) }
      labels = labels.map { |label| label.to_s.strip }.reject(&:empty?).uniq
      labels.sort_by { |label| -label.length }.each do |label|
        next unless clean.upcase.start_with?(label.upcase)
        tail = clean[label.length..-1].to_s
        return label if tail.empty? || tail.match?(/\A(?:[._\-\s]|$)/)
      end
      nil
    rescue
      nil
    end

    def self.partition_virtual_box_entities(entities, entity_cache = nil)
      core = []
      special = []
      Array(entities).each do |e|
        next unless e && e.valid?
        if virtual_box_excluded_entity_cached?(e, entity_cache)
          special << e
        else
          core << e
        end
      end
      [core, special]
    end

    def self.attach_special_entities_to_zones(zones, special_entities, split_bounds_cache = nil)
      return zones if zones.nil? || zones.empty? || special_entities.nil? || special_entities.empty?

      split_bounds_cache ||= {}
      special_entities.each do |ent|
        e_tuple = bounds_tuple_for_entity(ent, split_bounds_cache)
        touching = zones.select do |zone|
          z_tuple = bounds_pair_to_tuple(zone.bounds)
          z_tuple && bounds_tuple_touch?(e_tuple, z_tuple)
        end
        candidates = touching.empty? ? zones : touching
        target = candidates.min_by do |zone|
          z_tuple = bounds_pair_to_tuple(zone.bounds)
          next Float::INFINITY unless z_tuple
          bb_distance_raw(
            e_tuple[0], e_tuple[1], e_tuple[2], e_tuple[3], e_tuple[4], e_tuple[5],
            z_tuple[0], z_tuple[1], z_tuple[2], z_tuple[3], z_tuple[4], z_tuple[5]
          )
        end
        next unless target
        target.entities << ent unless target.entities.include?(ent)
      end
      zones
    end

    def self.bb_distance_raw(min1x,max1x,min1y,max1y,min1z,max1z,
                              min2x,max2x,min2y,max2y,min2z,max2z)
      if defined?(MH::Geo::Cluster)
        return MH::Geo::Cluster.bb_distance_raw(
          min1x, max1x, min1y, max1y, min1z, max1z,
          min2x, max2x, min2y, max2y, min2z, max2z
        )
      end

      dx = min2x > max1x ? min2x-max1x : (min1x > max2x ? min1x-max2x : 0.0)
      dy = min2y > max1y ? min2y-max1y : (min1y > max2y ? min1y-max2y : 0.0)
      dz = min2z > max1z ? min2z-max1z : (min1z > max2z ? min1z-max2z : 0.0)
      dx*dx + dy*dy + dz*dz
    end

    def self.auto_gap_threshold(boxes_flat, count)
      return MH::Geo::Cluster.auto_gap_threshold(boxes_flat, count) if defined?(MH::Geo::Cluster)

      return 100.0 if count < 2
      max_sample = [count, 80].min
      indices = count <= 80 ? (0...count).to_a : (0...count).to_a.sample(80)
      nn_dists = []
      indices.each do |i|
        i6 = i*6
        ax0=boxes_flat[i6]; ax1=boxes_flat[i6+1]
        ay0=boxes_flat[i6+2]; ay1=boxes_flat[i6+3]
        az0=boxes_flat[i6+4]; az1=boxes_flat[i6+5]
        min_d2 = Float::INFINITY
        indices.each do |j|
          next if i==j
          j6=j*6
          d2=bb_distance_raw(ax0,ax1,ay0,ay1,az0,az1,
                             boxes_flat[j6],boxes_flat[j6+1],
                             boxes_flat[j6+2],boxes_flat[j6+3],
                             boxes_flat[j6+4],boxes_flat[j6+5])
          min_d2=d2 if d2<min_d2
        end
        nn_dists << min_d2 if min_d2 < Float::INFINITY
      end
      return 100.0 if nn_dists.empty?
      sorted = nn_dists.sort
      best_jump=0; best_split=nil
      sorted.each_cons(2) do |a,b|
        jump=b-a
        if jump>best_jump; best_jump=jump; best_split=(a+b)/2.0; end
      end
      range = sorted.last - sorted.first
      thr_sq = if best_split && best_jump > range*0.2
        best_split
      else
        sorted[sorted.length/2]*2.0
      end
      Math.sqrt(thr_sq)
    end

    def self.cluster_entities(entities, gap_threshold = nil, use_named_groups = false, split_bounds_cache = nil)
      return [] if entities.empty?
      split_bounds_cache ||= {}
      entity_cache = {}
      core_entities, special_entities = partition_virtual_box_entities(entities, entity_cache)
      if core_entities.empty?
        core_entities = entities
        special_entities = []
      end
      if core_entities.length == 1
        single_zone = create_zone(0, core_entities, split_bounds_cache)
        attach_special_entities_to_zones([single_zone], special_entities, split_bounds_cache)
        return [single_zone]
      end

      # Nếu dùng named_groups: tách entity có tên SP cũ thành nhóm riêng
      named_groups = {}; to_cluster = []
      if use_named_groups
        core_entities.each do |e|
          key = extract_sp_key(e)
          key ? ((named_groups[key] ||= []) << e) : (to_cluster << e)
        end
      else
        to_cluster = core_entities
      end

      # Clustering theo khoảng cách cho các entity chưa được gán nhóm
      distance_clusters = []
      if to_cluster.length > 1
        n = to_cluster.length
        boxes_flat = Array.new(n*6)
        n.times do |i|
          b = content_bounds_for_entity(to_cluster[i], split_bounds_cache) || to_cluster[i].bounds
          i6=i*6
          boxes_flat[i6]=b.min.x; boxes_flat[i6+1]=b.max.x
          boxes_flat[i6+2]=b.min.y; boxes_flat[i6+3]=b.max.y
          boxes_flat[i6+4]=b.min.z; boxes_flat[i6+5]=b.max.z
        end
        groups = MH::Geo::Cluster.distance_cluster_indices(
          boxes_flat,
          gap_threshold,
          count: n,
          grid: true
        )
        groups.each { |indices| distance_clusters << indices.map { |i| to_cluster[i] } }
      elsif to_cluster.length == 1
        distance_clusters = [to_cluster]
      end

      all_clusters = []
      named_groups.each_value { |ents| all_clusters << ents }
      distance_clusters.each { |cl| all_clusters << cl }
      result = []; idx = 0
      all_clusters.each { |cl| result << create_zone(idx, cl, split_bounds_cache); idx += 1 }
      attach_special_entities_to_zones(result, special_entities, split_bounds_cache)
      result
    end

    def self.cluster_entities_by_sp_base(entities, lock_existing_labels = true)
      return [] if entities.empty?

      split_bounds_cache = {}
      entity_cache = {}
      core_entities, special_entities = partition_virtual_box_entities(entities, entity_cache)
      if core_entities.empty?
        core_entities = entities
        special_entities = []
      end

      grouped = {}
      unnamed = []
      core_entities.each do |entity|
        key = extract_sp_base_key(entity)
        key ? ((grouped[key] ||= []) << entity) : (unnamed << entity)
      end

      zones = []
      grouped.sort_by { |key, _ents| key }.each_with_index do |(key, ents), idx|
        zone = create_zone(idx, ents, split_bounds_cache)
        zone.label = key
        zone.zone_type = :sp
        zone.locked = lock_existing_labels
        zones << zone
      end

      unless unnamed.empty?
        unnamed_zone = create_zone(zones.length, unnamed, split_bounds_cache)
        zones << unnamed_zone
      end

      attach_special_entities_to_zones(zones, special_entities, split_bounds_cache)
      zones.each_with_index { |zone, idx| zone.id = idx }
      zones
    end

    def self.distance_clusters_for_entities(entities, gap_threshold, split_bounds_cache = nil)
      return [] if entities.empty?
      return [entities] if entities.length == 1

      split_bounds_cache ||= {}
      n = entities.length
      boxes_flat = Array.new(n * 6)
      n.times do |i|
        b = content_bounds_for_entity(entities[i], split_bounds_cache) || entities[i].bounds
        i6 = i * 6
        boxes_flat[i6] = b.min.x; boxes_flat[i6 + 1] = b.max.x
        boxes_flat[i6 + 2] = b.min.y; boxes_flat[i6 + 3] = b.max.y
        boxes_flat[i6 + 4] = b.min.z; boxes_flat[i6 + 5] = b.max.z
      end

      if defined?(MH::Geo::Cluster)
        groups = MH::Geo::Cluster.distance_cluster_indices(boxes_flat, gap_threshold, count: n, grid: true)
        return groups.map { |indices| indices.map { |i| entities[i] } }
      end

      gap_sq = gap_threshold * gap_threshold
      uf = UnionFind.new(n)
      (0...n).each do |i|
        i6 = i * 6
        ax0 = boxes_flat[i6]; ax1 = boxes_flat[i6 + 1]
        ay0 = boxes_flat[i6 + 2]; ay1 = boxes_flat[i6 + 3]
        az0 = boxes_flat[i6 + 4]; az1 = boxes_flat[i6 + 5]
        ((i + 1)...n).each do |j|
          j6 = j * 6
          d2 = bb_distance_raw(
            ax0, ax1, ay0, ay1, az0, az1,
            boxes_flat[j6], boxes_flat[j6 + 1],
            boxes_flat[j6 + 2], boxes_flat[j6 + 3],
            boxes_flat[j6 + 4], boxes_flat[j6 + 5]
          )
          uf.union(i, j) if d2 < gap_sq
        end
      end
      uf.groups.map { |indices| indices.map { |i| entities[i] } }
    end

    def self.cluster_entities_by_sp_distance(entities, gap_threshold, keep_existing_labels = true)
      return [] if entities.empty?

      split_bounds_cache = {}
      entity_cache = {}
      core_entities, special_entities = partition_virtual_box_entities(entities, entity_cache)
      if core_entities.empty?
        core_entities = entities
        special_entities = []
      end

      clusters = distance_clusters_for_entities(core_entities, gap_threshold, split_bounds_cache)
      zones = []
      clusters.each_with_index do |cluster, idx|
        zone = create_zone(idx, cluster, split_bounds_cache)
        base_labels = cluster.map { |entity| extract_sp_base_key(entity) }.compact.uniq
        zone.label = keep_existing_labels && base_labels.length == 1 ? base_labels.first : ""
        zone.zone_type = :sp
        zone.locked = keep_existing_labels && !zone.label.empty?
        zones << zone
      end

      attach_special_entities_to_zones(zones, special_entities, split_bounds_cache)
      zones.each_with_index { |zone, idx| zone.id = idx }
      zones
    end

    def self.sort_and_label_sp_zones(zones, prefix = nil, start_num = 1, force = true)
      prefix = product_family if prefix.to_s.strip.empty?
      sorted_zones = zones.sort_by { |z| [z.center.x.round(0), -z.center.z.round(0)] }
      current_num = start_num
      sorted_zones.each do |zone|
        zone.zone_type = :sp
        zone.parent_id = nil if zone.respond_to?(:parent_id=)
        if force || zone.label.to_s.empty?
          zone.label = format_product_code(current_num, prefix)
          current_num += 1
        else
          existing = zone.label.to_s.strip.upcase
          if product_base_label(existing) != existing && !product_base_label(existing).empty?
            zone.label = existing
            zone.zone_type = :modul
          else
            base = product_base_label(existing)
            zone.label = base.empty? ? existing : base
          end
        end
      end
      sorted_zones.each_with_index { |zone, idx| zone.id = idx }
      sorted_zones
    end

    def self.create_zone(idx, ents, split_bounds_cache = nil)
      bounds = bounds_from_entities(ents, split_bounds_cache)
      bb = Geom::BoundingBox.new; existing_label = ""; z_type = :sp
      if bounds
        bb.add(bounds[0]); bb.add(bounds[1])
      end
      ents.each do |e|
        bb.add(e.bounds) unless bounds
        if existing_label.empty? && e.respond_to?(:name)
          module_label = extract_sp_module_key(e)
          if module_label
            existing_label = module_label
            z_type = :modul
          else
            sp_key = extract_sp_key(e)
            if sp_key
              existing_label = sp_key.upcase
              is_module = if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:module?)
                MH::ProductContext.module?(existing_label)
              else
                product_base_label(existing_label) != existing_label
              end
              z_type = is_module ? :modul : :sp
            end
          end
        end
      end
      mn=bb.min; mx=bb.max
      z = Zone.new(idx, [Geom::Point3d.new(mn.x,mn.y,mn.z),
                          Geom::Point3d.new(mx.x,mx.y,mx.z)], ents)
      z.label = existing_label; z.zone_type = z_type; z
    end

    def self.sort_and_label_zones(zones, prefix = nil, start_num = 1, force = true)
      prefix = product_family if prefix.to_s.strip.empty?
      # Extract base label helper (SP01.1 -> SP01)
      get_base = lambda do |lbl|
        base = product_base_label(lbl)
        base.empty? ? "UNNAMED" : base
      end

      # Group all zones by their base label
      groups = {}
      zones.each do |z|
        base = get_base.call(z.label)
        base = "UNNAMED" if z.label.empty?
        (groups[base] ||= []) << z
      end

      # For each group, calculate the average center for sorting
      group_info = groups.map do |base, g_zones|
        avg_x = g_zones.map { |z| z.center.x }.sum / g_zones.length
        avg_z = g_zones.map { |z| z.center.z }.sum / g_zones.length
        
        old_num = product_number(base) || 9999
        
        {
          base: base,
          zones: g_zones,
          center: Geom::Point3d.new(avg_x, 0, avg_z),
          old_num: old_num
        }
      end

      # Sort groups spatially (Left -> Right, Top -> Bottom)
      sorted_groups = group_info.sort_by { |g| [g[:center].x.round(0), -g[:center].z.round(0)] }

      if !force
        max_existing = start_num - 1
        sorted_groups.each do |g|
          max_existing = g[:old_num] if g[:old_num] > max_existing && g[:old_num] != 9999
        end
        start_num = max_existing + 1
      end

      # Assign new labels sequentially
      current_num = start_num
      sorted_groups.each do |g|
        # Nếu force=false (giữ mã cũ) VÀ đã có mã cũ -> Giữ nguyên mã cũ
        # Nếu force=true (đánh lại toàn bộ), chỉ giữ mã cũ nếu CÓ KHỐI LÀ LOCKED
        has_locked = g[:zones].any? { |z| z.locked }
        if (!force || has_locked) && g[:old_num] != 9999
          new_base = format_product_code(g[:old_num], prefix)
        else
          new_base = format_product_code(current_num, prefix)
          current_num += 1
        end

        # Sort zones inside the group
        g_zones = g[:zones].sort_by { |z| [z.center.x.round(0), -z.center.z.round(0)] }
        
        # Determine if this group is just a single SP or multiple moduls
        if g_zones.length == 1 && g_zones.first.zone_type == :sp
          z = g_zones.first
          # Chỉ đổi tên nếu: không bị khóa VÀ (force=true hoặc label đang trống)
          if !z.locked && (force || z.label.empty?)
            z.label = new_base
          end
        else
          # Multiple zones -> they all become moduls
          g_zones.each_with_index do |z, idx|
            if !z.locked && (force || z.label.empty?)
              z.zone_type = :modul
              z.label = module_label(new_base, idx + 1)
            end
          end
        end
      end
      
      # Flatten the sorted groups into the final array and update IDs
      final_zones = sorted_groups.flat_map { |g| g[:zones].sort_by { |z| [z.center.x.round(0), -z.center.z.round(0)] } }
      final_zones.each_with_index { |z, i| z.id = i }
      final_zones
    end

    def self.renumber_module_labels(zones)
      groups = {}
      zones.each do |z|
        base = product_base_label(z.label)
        next if base.empty?
        (groups[base] ||= []) << z
      end

      sorted_groups = groups.values.sort_by do |g_zones|
        avg_x = g_zones.map { |z| z.center.x }.sum / g_zones.length
        avg_z = g_zones.map { |z| z.center.z }.sum / g_zones.length
        [avg_x.round(0), -avg_z.round(0)]
      end

      sorted_groups.each do |g_zones|
        base = product_base_label(g_zones.first.label)
        module_rules = registry_module_rules_for_sp(base)
        has_module = g_zones.any? { |z| z.zone_type == :modul || module_number_from_label(z.label, base) }
        renumber_scope = (has_module || g_zones.length > 1 || !module_rules.empty?) ? g_zones : []
        renumber_scope.sort_by { |z| [z.center.x.round(0), -z.center.z.round(0)] }.each_with_index do |z, idx|
          next if z.locked
          z.zone_type = :modul
          z.label = registry_module_label(base, idx, module_rules[idx])
        end
      end

      final_zones = sorted_groups.flat_map { |g_zones| g_zones.sort_by { |z| [z.center.x.round(0), -z.center.z.round(0)] } }
      unlabeled = zones - final_zones
      final_zones.concat(unlabeled.sort_by { |z| [z.center.x.round(0), -z.center.z.round(0)] })
      final_zones.each_with_index { |z, i| z.id = i }
      final_zones
    end

    def self.renumber_sp_labels(zones, prefix = nil, start_num = 1)
      prefix = product_family if prefix.to_s.strip.empty?
      groups = []
      by_base = {}

      zones.each do |z|
        base = product_base_label(z.label)
        if base.empty?
          groups << { base: "", zones: [z] }
        else
          group = by_base[base] ||= { base: base, zones: [] }
          group[:zones] << z
        end
      end
      groups.concat(by_base.values)

      sorted_groups = groups.sort_by do |g|
        g_zones = g[:zones]
        avg_x = g_zones.map { |z| z.center.x }.sum / g_zones.length
        avg_z = g_zones.map { |z| z.center.z }.sum / g_zones.length
        [avg_x.round(0), -avg_z.round(0)]
      end

      current_num = start_num
      sorted_groups.each do |g|
        new_base = format_product_code(current_num, prefix)
        current_num += 1
        g[:zones].each do |z|
          next if z.locked
          z.label = product_base_label(z.label).empty? ? new_base : replace_product_base(z.label, new_base)
        end
      end

      final_zones = sorted_groups.flat_map { |g| g[:zones].sort_by { |z| [z.center.x.round(0), -z.center.z.round(0)] } }
      final_zones.each_with_index { |z, i| z.id = i }
      final_zones
    end

    def self.sync_registry_config(config_data = nil)
      invalidate_settings_cache
      config_data ||= if defined?(MH::RegistryApp) && MH::RegistryApp.respond_to?(:load_config)
        MH::RegistryApp.load_config
      else
        nil
      end
      return false unless config_data.is_a?(Hash)

      @registry_prefix_suggestions = []
      moduls = config_data['modul'] || config_data[:modul] || config_data['all_modul'] || config_data[:all_modul] || []
      @registry_module_suggestions = Array(moduls).map(&:to_s).map(&:strip).reject(&:empty?) unless Array(moduls).empty?
      separators = config_data['separators'] || config_data[:separators] || {}
      sep_prefix = separators['sep_prefix'] || separators[:sep_prefix]
      @registry_prefix_modul_separator = sep_prefix.to_s unless sep_prefix.nil?
      sync_registry_project_config
      true
    rescue => e
      dbg("MH::FastRename registry sync error: #{e.message}")
      false
    end

    def self.registry_prefix_suggestions
      @registry_prefix_suggestions || []
    end

    def self.sync_registry_project_config
      return false unless defined?(MH::Registry)

      MH::Registry.reload! if MH::Registry.respond_to?(:reload!)
      project = MH::Registry.project
      @registry_project_modules = Array(project['modules']).select { |row| row.is_a?(Hash) }
      project_moduls = MH::Registry.respond_to?(:modul_suggestions) ? MH::Registry.modul_suggestions : []
      @registry_module_suggestions = Array(project_moduls).map(&:to_s).map(&:strip).reject(&:empty?) unless Array(project_moduls).empty?
      true
    rescue => e
      dbg("MH::FastRename registry project sync error: #{e.message}")
      false
    end

    def self.registry_project_modules
      sync_registry_project_config if @registry_project_modules.nil?
      @registry_project_modules || []
    end

    def self.registry_module_rules_for_sp(sp_label)
      sp = sp_label.to_s.strip.upcase
      return [] if sp.empty?

      explicit_rules = registry_project_modules.select do |row|
        row['sp'].to_s.strip.upcase == sp
      end
      return explicit_rules unless explicit_rules.empty?

      Array(@registry_module_suggestions).map do |modul|
        { 'sp' => sp, 'modul' => modul.to_s.strip }
      end.reject { |row| row['modul'].empty? }
    end

    def self.registry_modules_enabled_for_sp?(sp_label)
      !registry_module_rules_for_sp(sp_label).empty?
    end

    def self.module_separator
      sep = @registry_prefix_modul_separator.to_s
      if sep.empty? && defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:module_separator)
        sep = MH::NameGrammar.module_separator.to_s
      end
      sep = "." if sep.empty?
      sep
    end

    def self.module_label(base_label, number)
      if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:build_code)
        return MH::NameGrammar.build_code(product: base_label, module_raw: number.to_s, pad_numeric: true).to_s.upcase
      end
      "#{base_label}#{module_separator}#{number}"
    end

    def self.module_number_from_label(label, base_label = nil)
      text = label.to_s.strip
      base = base_label.to_s.strip
      base = product_base_label(text) if base.empty?
      return nil if base.empty? || !text.upcase.start_with?(base.upcase)

      suffix = text[base.length..-1].to_s
      match = suffix.match(/\A[._-](\d+)\z/)
      match ? match[1].to_i : nil
    end

    def self.replace_product_base(label, new_base)
      text = label.to_s
      old_base = product_base_label(text)
      return text if old_base.empty?

      suffix = text[old_base.length..-1].to_s
      if (match = suffix.match(/\A[._-](\d+)\z/))
        module_label(new_base, match[1].to_i)
      else
        "#{new_base}#{suffix}"
      end
    end

    def self.registry_module_label(base_label, index, rule)
      label = rule ? rule['prefix'].to_s.strip : ""
      return label unless label.empty?

      modul = rule ? rule['modul'].to_s.strip : ""
      sep = module_separator
      unless modul.empty?
        if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:build_code)
          return MH::NameGrammar.build_code(product: base_label, module_raw: modul, pad_numeric: true).to_s.upcase
        end
        return "#{base_label}#{sep}#{modul}"
      end

      module_label(base_label, index.to_i + 1)
    end

    def self.rename_candidate_entity?(entity, split_bounds_cache = nil)
      return false unless entity && entity.valid?
      return false unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      return false if entity.hidden?
      layer = entity.respond_to?(:layer) ? entity.layer : nil
      return false if layer && layer.respond_to?(:visible?) && !layer.visible?

      bb = entity.bounds
      return false unless bb && bb.valid?

      dims = [
        (bb.max.x - bb.min.x).abs,
        (bb.max.y - bb.min.y).abs,
        (bb.max.z - bb.min.z).abs
      ]
      dims.max.to_f > (0.001 / 25.4)
    rescue
      false
    end

    def self.model_rename_candidates(model, split_bounds_cache = nil)
      model.active_entities.to_a.select { |entity| rename_candidate_entity?(entity, split_bounds_cache) }
    end

    # ════════════════════════════════════════════════════════════════
    # FAST RENAME TOOL
    # ════════════════════════════════════════════════════════════════
    class FastRenameTool
      unless defined?(ZONE_COLORS)
        ZONE_COLORS = [
          Sketchup::Color.new(91,140,255,105), Sketchup::Color.new(120,220,120,105),
          Sketchup::Color.new(255,180,80,105),  Sketchup::Color.new(220,120,220,105),
          Sketchup::Color.new(255,255,120,105), Sketchup::Color.new(120,255,255,105)
        ].freeze
        ZONE_EDGE_COLORS = [
          Sketchup::Color.new(0,0,150,255),   Sketchup::Color.new(0,100,0,255),
          Sketchup::Color.new(150,60,0,255),  Sketchup::Color.new(100,0,100,255),
          Sketchup::Color.new(150,150,0,255), Sketchup::Color.new(0,150,150,255)
        ].freeze
        ZONE_SEL_COLOR   = Sketchup::Color.new(255,204,85,145)
        ZONE_SEL_EDGE    = Sketchup::Color.new(255,204,85,255)
        SPLIT_COLOR      = Sketchup::Color.new(255,0,0,255)
        SPLIT_PREVIEW    = Sketchup::Color.new(255,0,0,150)
        LABEL_COLOR      = Sketchup::Color.new(255,255,255)
        LABEL_BG         = Sketchup::Color.new(30,30,50,200)
        MODUL_COLOR      = Sketchup::Color.new(127,212,232,105)
        MODUL_EDGE_COLOR = Sketchup::Color.new(127,212,232,200)
        MOVE_SOURCE_EDGE = Sketchup::Color.new(255,220,0,255)
        MOVE_GHOST_FILL  = Sketchup::Color.new(0,255,255,55)
        MOVE_GHOST_EDGE  = Sketchup::Color.new(0,255,255,255)
        EDGES = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],
                 [0,4],[1,5],[2,6],[3,7]].freeze
        SPLIT_AXES = [:x, :z, :y].freeze
        SPLIT_MODE_LABELS = {
          x: "DOC",
          z: "NGANG",
          y: "VUONG GOC"
        }.freeze
      end

      def initialize(initial_grouping_mode = nil)
        @initial_grouping_mode = initial_grouping_mode
        @zones=[]; @selected_zone=nil; @mode=:select
        @split_axis=MH::FastRename.default_split_axis_index; @hovered_zone=nil
        @prefix_suggestions=[]; @selected_zones=[]
        @drag_start=nil; @drag_current=nil
        @sp_start_num=MH::FastRename.setting_int('default_sp_start_num', 1)
        @gap_threshold_mm=MH::FastRename.setting_float('gap_threshold_mm', 1000.0)
        @merge_source=nil; @split_all=MH::FastRename.setting_bool('split_all_default', false)
        @sp_prefix_grouping_active=false
        @move_entity=nil; @move_source_zone=nil
        @move_target_zone=nil
        @move_hover_entity=nil; @move_hover_source_zone=nil
        @move_dragging=false
        @alt_down_latched=false
        @ip=Sketchup::InputPoint.new
        load_config
      end

      def reload_user_settings
        MH::FastRename.invalidate_settings_cache if MH::FastRename.respond_to?(:invalidate_settings_cache)
        @split_axis = MH::FastRename.default_split_axis_index
        @sp_start_num = MH::FastRename.setting_int('default_sp_start_num', @sp_start_num || 1)
        @gap_threshold_mm = MH::FastRename.setting_float('gap_threshold_mm', @gap_threshold_mm || 1000.0)
        @split_all = MH::FastRename.setting_bool('split_all_default', @split_all || false)
        update_status if respond_to?(:update_status)
        @view.invalidate if @view
      rescue => e
        MH::FastRename.dbg("FastRename reload_user_settings error: #{e.message}")
      end

      def load_config
        begin
          MH::FastRename.sync_registry_project_config

          if defined?(MH::RegistryApp) && MH::RegistryApp.respond_to?(:load_config)
            MH::FastRename.sync_registry_config
          end
          @prefix_suggestions = []
        rescue => e
          MH::FastRename.dbg("FastRename config load error: #{e.message}")
        end
      end

      def activate
        @model = Sketchup.active_model; @view = @model.active_view
        @split_bounds_cache = {}
        sel = @model.selection.to_a.select { |e|
          MH::FastRename.rename_candidate_entity?(e, @split_bounds_cache)
        }
        if sel.empty?
          sel = MH::FastRename.model_rename_candidates(@model, @split_bounds_cache)
          if sel.empty?
            UI.messagebox("Không tìm thấy chi tiết hợp lệ có chiều dài khác 0mm!")
            @model.select_tool(nil)
            return
          end
          Sketchup.status_text = "Không có selection — tự lấy #{sel.length} chi tiết hợp lệ trong model"
        end

        if @initial_grouping_mode == :sp_prefix
          activate_sp_prefix_selection(sel)
          return
        end

        res = UI.inputbox(["Số SP bắt đầu (để trống giữ mã cũ):"],[""],"MH Fast Rename")
        if res
          if res[0].to_s.strip != ""
            @sp_start_num = [res[0].to_i,1].max; @force_renumber = true
          else
            @force_renumber = false
          end
        else
          @model.select_tool(nil); return
        end
        @all_entities = sel
        @model.selection.clear
        recluster_all
        @mode = :select; update_status; @view.invalidate
      end

      def activate_sp_prefix_selection(selection_entities)
        res = UI.inputbox(["Số SP bắt đầu (để trống giữ mã cũ):"], [""], "Chia theo mã SP gốc")
        unless res
          @model.select_tool(nil)
          return
        end

        if res[0].to_s.strip != ""
          @sp_start_num = [res[0].to_i, 1].max
          @force_renumber = true
        else
          @force_renumber = false
        end

        @all_entities = selection_entities
        @model.selection.clear
        regroup_by_sp_prefix
        @mode = :select
        update_status
        @view.invalidate
      end

      def recluster_all
        @sp_prefix_grouping_active = false
        gap_inches = @gap_threshold_mm / 25.4
        @split_bounds_cache ||= {}
        if !@force_renumber
          face_cache = {}
          @zones = cluster_entities_by_existing_module_codes(@all_entities, @split_bounds_cache, face_cache)
          if @zones.empty?
            @zones = MH::FastRename.cluster_entities(@all_entities, gap_inches, true, @split_bounds_cache)
            @zones = MH::FastRename.sort_and_label_sp_zones(@zones, MH::FastRename.product_family, @sp_start_num, false)
          end
          @selected_zones=[]; @hovered_zone=nil
          update_status
          @view.invalidate if @view
          return
        end
        # force_renumber=true (nhập số mới) → cluster theo khoảng cách
        # force_renumber=false (để trống, giữ mã cũ) → dùng named_groups
        use_names = !@force_renumber
        @zones = MH::FastRename.cluster_entities(@all_entities, gap_inches, use_names, @split_bounds_cache)
        @zones = MH::FastRename.sort_and_label_sp_zones(@zones, MH::FastRename.product_family, @sp_start_num, @force_renumber)
        @selected_zones=[]; @hovered_zone=nil
        auto_split_contact_planes if MH::FastRename.auto_contact_split?
      end

      def regroup_by_sp_prefix
        return unless @all_entities && !@all_entities.empty?
        @sp_prefix_grouping_active = true
        gap_inches = @gap_threshold_mm / 25.4
        @zones = MH::FastRename.cluster_entities_by_sp_distance(@all_entities, gap_inches, !@force_renumber)
        @zones = MH::FastRename.sort_and_label_sp_zones(@zones, MH::FastRename.product_family, @sp_start_num, @force_renumber)
        @selected_zones = []
        @hovered_zone = nil
        update_status
        @view.invalidate if @view
      end

      def prompt_and_regroup_by_sp_prefix
        res = UI.inputbox(["Số SP bắt đầu (để trống giữ mã cũ):"], [""], "Chia theo mã SP gốc")
        return unless res

        if res[0].to_s.strip != ""
          @sp_start_num = [res[0].to_i, 1].max
          @force_renumber = true
        else
          @force_renumber = false
        end
        regroup_by_sp_prefix
      end

      # Trích xuất gốc mã sản phẩm từ label bất kỳ.
      def extract_sp_base(label)
        base = MH::FastRename.product_base_label(label)
        base.to_s.empty? ? label : base
      end

      def preserved_module_label_for_group(entities, base_label, module_rules = nil)
        return nil if @force_renumber
        base = base_label.to_s.upcase
        rules = module_rules || MH::FastRename.registry_module_rules_for_sp(base)
        counts = Hash.new(0)
        Array(entities).each do |entity|
          label = MH::FastRename.extract_sp_module_key(entity, base, rules)
          next if label.nil? || label.empty?
          next unless extract_sp_base(label).to_s.upcase == base
          counts[label] += 1
        end
        counts.max_by { |label, count| [count, -label.length] }&.first
      end

      def bounds_pair_union(bounds_a, bounds_b)
        return bounds_b unless bounds_a
        return bounds_a unless bounds_b
        a_min, a_max = bounds_a
        b_min, b_max = bounds_b
        [
          Geom::Point3d.new([a_min.x, b_min.x].min, [a_min.y, b_min.y].min, [a_min.z, b_min.z].min),
          Geom::Point3d.new([a_max.x, b_max.x].max, [a_max.y, b_max.y].max, [a_max.z, b_max.z].max)
        ]
      end

      def bounds_pair_center(bounds)
        bmin, bmax = bounds
        Geom::Point3d.new((bmin.x + bmax.x) * 0.5, (bmin.y + bmax.y) * 0.5, (bmin.z + bmax.z) * 0.5)
      end

      def assign_old_module_groups(sorted_groups, base_label, module_rules)
        return sorted_groups.map.with_index { |grp, idx|
          [grp.merge(label: MH::FastRename.registry_module_label(base_label, idx, module_rules[idx])), false]
        } if @force_renumber

        assigned = sorted_groups.map do |grp|
          label = preserved_module_label_for_group(grp[:ents], base_label, module_rules)
          grp.merge(label: label)
        end
        labeled = assigned.select { |grp| !grp[:label].to_s.empty? }

        if labeled.any?
          assigned.each do |grp|
            next unless grp[:label].to_s.empty?
            center = bounds_pair_center(grp[:bounds])
            nearest = labeled.min_by do |known|
              known_center = bounds_pair_center(known[:bounds])
              dx = center.x - known_center.x
              dy = center.y - known_center.y
              dz = center.z - known_center.z
              dx * dx + dy * dy + dz * dz
            end
            grp[:label] = nearest[:label] if nearest
          end
        else
          assigned.each_with_index do |grp, idx|
            grp[:label] = MH::FastRename.registry_module_label(base_label, idx, module_rules[idx])
          end
        end

        merged_by_label = {}
        assigned.each do |grp|
          label = grp[:label].to_s
          if merged_by_label[label]
            merged_by_label[label][:ents].concat(grp[:ents])
            merged_by_label[label][:bounds] = bounds_pair_union(merged_by_label[label][:bounds], grp[:bounds])
          else
            merged_by_label[label] = {
              label: label,
              ents: grp[:ents].dup,
              bounds: grp[:bounds]
            }
          end
        end
        merged_by_label.values.sort_by { |grp|
          bmin, bmax = grp[:bounds]
          [((bmin.x + bmax.x) * 0.5).round(0), -((bmin.z + bmax.z) * 0.5).round(0)]
        }.map { |grp| [grp, labeled.any?] }
      end

      def cluster_entities_by_existing_module_codes(entities, split_bounds_cache = nil, face_cache = nil)
        split_bounds_cache ||= {}
        face_cache ||= {}
        module_groups = {}
        unassigned = []

        Array(entities).each do |entity|
          next unless entity && entity.valid?
          base_label = MH::FastRename.extract_sp_base_key(entity)
          if base_label
            rules = MH::FastRename.registry_module_rules_for_sp(base_label)
            module_label = MH::FastRename.extract_sp_module_key(entity, base_label, rules)
            if module_label && !module_label.empty?
              (module_groups[module_label] ||= []) << entity
              next
            end
          end
          unassigned << entity
        end

        zones = []
        module_groups.sort_by { |label, _ents| label }.each_with_index do |(label, ents), idx|
          zone = MH::FastRename.create_zone(idx, ents, split_bounds_cache)
          zone.label = label
          zone.zone_type = :modul
          zone.locked = true
          zones << zone
        end

        modules_by_base = {}
        zones.each do |zone|
          base = extract_sp_base(zone.label).to_s.upcase
          (modules_by_base[base] ||= []) << zone unless base.empty?
        end

        fallback_groups = {}
        unassigned.each do |entity|
          base_label = MH::FastRename.extract_sp_base_key(entity).to_s.upcase
          fallback_key = base_label.empty? ? "__UNNAMED__" : base_label
          (fallback_groups[fallback_key] ||= []) << entity
        end

        zones.each { |zone| refresh_zone_bounds(zone) }

        fallback_groups.sort_by { |key, _ents| key }.each do |key, ents|
          zone = MH::FastRename.create_zone(zones.length, ents, split_bounds_cache)
          unless key == "__UNNAMED__"
            zone.label = key
            zone.locked = true
          end
          zones << zone
        end

        zones.each_with_index { |zone, idx| zone.id = idx }
        zones
      end

      def split_entities_for_virtual_box(entities)
        core = []
        sp_base_only = []
        modul_contact = []
        entity_cache = {}
        entities.each do |e|
          next unless e && e.valid?
          if MH::FastRename.modul_contact_entity_cached?(e, entity_cache)
            modul_contact << e
          elsif MH::FastRename.sp_base_only_entity_cached?(e, entity_cache)
            sp_base_only << e
          else
            core << e
          end
        end
        [core, sp_base_only, modul_contact]
      end

      def pick_best_module_zone_for_entity(entity, module_zones, split_bounds_cache = nil, face_cache = nil)
        return nil if module_zones.nil? || module_zones.empty?

        e_tuple = MH::FastRename.bounds_tuple_for_entity(entity, split_bounds_cache)
        touching = module_zones.select do |zone|
          z_tuple = MH::FastRename.bounds_pair_to_tuple(zone.bounds)
          z_tuple && MH::FastRename.bounds_tuple_touch?(e_tuple, z_tuple)
        end
        candidates = touching.empty? ? module_zones : touching
        return candidates.first if candidates.length == 1

        best_zone = nil
        best_area = -Float::INFINITY
        best_dist = Float::INFINITY
        candidates.each do |zone|
          area = MH::FastRename.contact_area_with_group(entity, zone.entities, face_cache, split_bounds_cache)
          z_tuple = MH::FastRename.bounds_pair_to_tuple(zone.bounds)
          dist = if z_tuple
            MH::FastRename.bb_distance_raw(
              e_tuple[0], e_tuple[1], e_tuple[2], e_tuple[3], e_tuple[4], e_tuple[5],
              z_tuple[0], z_tuple[1], z_tuple[2], z_tuple[3], z_tuple[4], z_tuple[5]
            )
          else
            Float::INFINITY
          end
          if area > best_area + 1e-9 || ((area - best_area).abs <= 1e-9 && dist < best_dist)
            best_area = area
            best_dist = dist
            best_zone = zone
          end
        end
        best_zone || candidates.first
      end

      def pick_touching_module_zone_for_entity(entity, module_zones, split_bounds_cache = nil, face_cache = nil)
        return nil if module_zones.nil? || module_zones.empty?

        e_tuple = MH::FastRename.bounds_tuple_for_entity(entity, split_bounds_cache)
        touching = module_zones.select do |zone|
          z_tuple = MH::FastRename.bounds_pair_to_tuple(zone.bounds)
          z_tuple && MH::FastRename.bounds_tuple_touch?(e_tuple, z_tuple)
        end
        return nil if touching.empty?
        return touching.first if touching.length == 1

        pick_best_module_zone_for_entity(entity, touching, split_bounds_cache, face_cache)
      end

      def module_zone_matching_entity_label(entity, module_zones)
        return nil unless entity && entity.respond_to?(:name)
        zones_by_base = {}
        Array(module_zones).each do |zone|
          label = zone.label.to_s.strip
          next if label.empty?
          base = extract_sp_base(label).to_s.upcase
          next if base.empty?
          (zones_by_base[base] ||= []) << zone
        end

        zones_by_base.each do |base, zones|
          rules = MH::FastRename.registry_module_rules_for_sp(base)
          module_label = MH::FastRename.extract_sp_module_key(entity, base, rules)
          next if module_label.to_s.empty?
          matched = zones.find { |zone| zone.label.to_s.strip.upcase == module_label.to_s.upcase }
          return matched if matched
        end
        nil
      rescue
        nil
      end

      def attach_special_entities_to_modules(module_zones, sp_base_only, modul_contact, split_bounds_cache = nil, face_cache = nil)
        return if module_zones.nil? || module_zones.empty?
        (modul_contact + sp_base_only).each do |entity|
          target = module_zone_matching_entity_label(entity, module_zones) ||
                   pick_best_module_zone_for_entity(entity, module_zones, split_bounds_cache, face_cache)
          next unless target
          target.entities << entity unless target.entities.include?(entity)
        end
      end

      def merge_old_coded_zones_into_modules(split_bounds_cache = nil)
        module_zones = @zones.select { |zone| module_label?(zone.label) }
        return if module_zones.empty?

        changed = false

        @zones.dup.each do |zone|
          next if module_zones.include?(zone)
          target_counts = Hash.new(0)
          zone.entities.each do |entity|
            target_zone = module_zone_matching_entity_label(entity, module_zones)
            target_counts[target_zone] += 1 if target_zone
          end
          next if target_counts.empty?

          target_zone = target_counts.max_by { |target, count| [count, target.label.to_s] }&.first
          next unless target_zone

          zone.entities.each do |entity|
            target_zone.entities << entity unless target_zone.entities.include?(entity)
          end
          @zones.delete(zone)
          refresh_zone_bounds(target_zone)
          changed = true
        end

        @zones.each_with_index { |zone, idx| zone.id = idx } if changed
      end

      def create_base_accessory_zone(base_label, parent_id, special_entities, module_index, module_rule = nil)
        accessory_ents = special_entities.select { |entity| MH::FastRename.base_accessory_entity?(entity) }
        return [nil, special_entities] if accessory_ents.empty?

        remaining = special_entities - accessory_ents
        bb = Geom::BoundingBox.new
        accessory_ents.each { |entity| bb.add(entity.bounds) if entity && entity.valid? }
        return [nil, remaining] unless bb.valid?

        zone = Zone.new(0, [bb.min, bb.max], accessory_ents)
        zone.zone_type = :modul
        zone.parent_id = parent_id
        zone.label = MH::FastRename.registry_module_label(base_label, module_index - 1, module_rule)
        zone.locked = true
        [zone, remaining]
      end

      # ── AUTO SPLIT bằng contact-plane algorithm v5 ──────────────
      # Zone rời = SPxx, zone cạnh nhau (split) = SPxx.aa
      def auto_split_contact_planes
        t0 = Time.now
        total_splits = 0
        split_bounds_cache = @split_bounds_cache ||= {}
        face_cache = {}

        new_zones = []
        @zones.each do |zone|
          ents = zone.entities
          core_ents, sp_base_only_ents, modul_contact_ents = split_entities_for_virtual_box(ents)
          parent_label = zone.label  # VD: "SP01" hoặc "SP01.2"
          base_label = extract_sp_base(parent_label)
          module_rules = MH::FastRename.registry_module_rules_for_sp(base_label)

          if core_ents.length < 2
            new_zones << zone
            next
          end

          if module_rules.empty?
            new_zones << zone
            next
          end

          # Tách nhóm → sub-nhóm bằng contact-plane splitting
          named_separators = MH::FastRename.cp_named_contact_separators(core_ents, split_bounds_cache)
          sub_groups = MH::FastRename.split_entities_into_groups(core_ents, zone.bounds, split_bounds_cache, named_separators, face_cache)

          if sub_groups.length <= 1
            # Không cắt được → giữ nguyên zone
            new_zones << zone
          else
            merged = MH::FastRename.merge_orphans_into_groups(sub_groups, split_bounds_cache, face_cache)

            # Nếu sau merge chỉ còn 1 nhóm → không cần thêm .aa
            if merged.length <= 1
              new_zones << zone
              next
            end
            sorted_merged = merged.sort_by { |grp|
              bmin, bmax = grp[:bounds]
              cx = (bmin.x + bmax.x) * 0.5
              cz = (bmin.z + bmax.z) * 0.5
              [cx.round(0), -cz.round(0)]
            }
            assigned_groups = assign_old_module_groups(sorted_merged, base_label, module_rules)
            if module_rules.length < assigned_groups.length
              new_zones << zone
              next
            end

            module_zones = []

            assigned_groups.each_with_index do |(grp, _used_old_labels), sub_idx|
              nz = Zone.new(0, grp[:bounds], grp[:ents])
              nz.zone_type = :modul
              nz.parent_id = zone.id
              nz.label = grp[:label].to_s.empty? ? MH::FastRename.registry_module_label(base_label, sub_idx, module_rules[sub_idx]) : grp[:label]
              nz.locked = true
              new_zones << nz
              module_zones << nz
            end
            accessory_zone, remaining_sp_base_only = create_base_accessory_zone(
              base_label,
              zone.id,
              sp_base_only_ents,
              module_zones.length + 1
            )
            if accessory_zone
              new_zones << accessory_zone
              module_zones << accessory_zone
            end
            attach_special_entities_to_modules(module_zones, remaining_sp_base_only, modul_contact_ents, split_bounds_cache, face_cache)
            total_splits += merged.length - 1
          end
        end

        @zones = new_zones
        merge_old_coded_zones_into_modules(split_bounds_cache) unless @force_renumber
        # Gán lại ID theo thứ tự
        @zones.each_with_index { |z, i| z.id = i }

        elapsed = ((Time.now-t0)*1000).round(0)
        MH::FastRename.dbg("MH::FastRename auto_split: #{total_splits} split(s), #{@zones.length} zones, #{elapsed}ms")
      end

      def deactivate(view)
        if @isolated_zone
          @hidden_by_isolate&.each { |e| e.hidden = false if e && e.valid? }
          @isolated_zone=nil
          @hidden_by_isolate&.clear
        end
        @model.selection.add(@all_entities.select(&:valid?)) if @all_entities
        view.invalidate
      end
      def resume(view);  update_status; view.invalidate; end
      def suspend(view); view.invalidate; end

      def update_status_legacy
        case @mode
        when :select
          sel_txt = @selected_zones.length > 0 ? " [#{@selected_zones.length} đã chọn]" : ""
          Sketchup.status_text="MH Fast Rename#{sel_txt} | Click: chọn | Ctrl+Click: gộp khối | Shift+Click tên modul: sửa | C: Cắt | Enter: Áp dụng"
        when :split
          ax=SPLIT_AXES[@split_axis].to_s.upcase
          md=@split_all ? "XUYÊN KHỐI" : "1 KHỐI"
          Sketchup.status_text="CẮT [#{ax}-#{md}] | Ctrl: đổi kiểu | Tab: đổi trục | ESC/P.PHẢI: Thoát"
        when :merge_target
          Sketchup.status_text="GỘP | Click khối khác để gộp | ESC: Hủy"
        end
      end

      def draw(view)
        draw_zones(view)
        draw_split_preview(view) if @mode==:split && @split_preview_pos && @hovered_zone && !@drag_start
        draw_move_entity_preview(view)
        draw_selection_box(view)
        draw_labels(view)
        @ip.draw(view) if @mode==:split && @ip&.valid? && !@drag_start
      end

      def draw_selection_box(view)
        return unless @drag_start && @drag_current
        x1,y1=@drag_start; x2,y2=@drag_current
        pts=[Geom::Point3d.new(x1,y1,0),Geom::Point3d.new(x2,y1,0),
             Geom::Point3d.new(x2,y2,0),Geom::Point3d.new(x1,y2,0)]
        MH::OverlayEngine.rect(view, x1, y1, x2 - x1, y2 - y1, Sketchup::Color.new(100,100,255,50), pts)
        MH::OverlayEngine.rect_outline(view, x1, y1, x2 - x1, y2 - y1, Sketchup::Color.new(100,100,255,255), pts)
      end

      def bbox_corners(bounds)
        mn = bounds.min
        mx = bounds.max
        [Geom::Point3d.new(mn.x,mn.y,mn.z), Geom::Point3d.new(mx.x,mn.y,mn.z),
         Geom::Point3d.new(mx.x,mx.y,mn.z), Geom::Point3d.new(mn.x,mx.y,mn.z),
         Geom::Point3d.new(mn.x,mn.y,mx.z), Geom::Point3d.new(mx.x,mn.y,mx.z),
         Geom::Point3d.new(mx.x,mx.y,mx.z), Geom::Point3d.new(mn.x,mx.y,mx.z)]
      end

      def draw_move_entity_preview(view)
        preview_entity = entity_move_pending? ? @move_entity : @move_hover_entity
        return unless preview_entity && preview_entity.valid?

        src_bounds = preview_entity.bounds
        src_pts = bbox_corners(src_bounds)
        src_pts2d = src_pts.map { |p| view.screen_coords(p) }

        EDGES.each { |a,b| MH::OverlayEngine.line2d(view, [src_pts2d[a], src_pts2d[b]], color: MOVE_SOURCE_EDGE, stipple: '', width: 4) }

        return unless entity_move_pending?
        return unless @move_target_zone && @move_target_zone != @move_source_zone

        src_center = src_bounds.center
        target_center = label_center_for_zone(@move_target_zone, view)
        src_2d = view.screen_coords(src_center)
        dst_2d = view.screen_coords(target_center)
        p1 = Geom::Point3d.new(src_2d.x, src_2d.y, 0)
        p2 = Geom::Point3d.new(dst_2d.x, dst_2d.y, 0)
        MH::OverlayEngine.line2d(view, [p1, p2], color: MOVE_GHOST_EDGE, stipple: '', width: 3)
      rescue
        nil
      end

      def label_center_for_zone(zone, view)
        entry = label_entries(view).find { |item| item[:zones].include?(zone) }
        entry ? entry[:center] : zone.center
      end

      def draw_zones(view)
        has_active = @selected_zones.any? || @hovered_zone || @merge_source || @move_source_zone || @move_target_zone
        @zones.each do |zone|
          next if zone.hidden
          next if @isolated_zone && zone!=@isolated_zone
          pts = zone.corners
          is_sel   = @selected_zones.include?(zone)||@hovered_zone==zone||@merge_source==zone||@move_source_zone==zone||@move_target_zone==zone
          is_modul = zone.zone_type==:modul
          base_idx = zone.id % ZONE_COLORS.length
          fill = is_sel ? ZONE_SEL_COLOR : (is_modul ? MODUL_COLOR : ZONE_COLORS[base_idx])
          fill = Sketchup::Color.new(fill.red,fill.green,fill.blue,25) if has_active && !is_sel
          edge = is_sel ? ZONE_SEL_EDGE  : (is_modul ? MODUL_EDGE_COLOR : ZONE_EDGE_COLORS[base_idx])
          view.drawing_color=fill
          [[0,1,2,3],[4,5,6,7],[0,1,5,4],[3,2,6,7],[0,3,7,4],[1,2,6,5]].each do |f|
            view.draw(GL_QUADS, pts.values_at(*f))
          end
          view.line_width=3; view.line_stipple='-'
          ec=Sketchup::Color.new(0,0,0,(has_active && !is_sel) ? 30 : 255)
          view.drawing_color=ec
          if is_sel
            pts2d=pts.map{|p|view.screen_coords(p)}
            EDGES.each{|a,b| MH::OverlayEngine.line2d(view, [pts2d[a], pts2d[b]], color: ec, stipple: '-', width: 3)}
          else
            EDGES.each{|a,b|view.draw(GL_LINES,[pts[a],pts[b]])}
          end
        end
      end

      def draw_labels(view)
        has_active = @selected_zones.any? || @hovered_zone || @merge_source || @move_source_zone || @move_target_zone
        label_entries(view).each do |entry|
          zones = entry[:zones]
          screen=view.screen_coords(entry[:center])
          text=entry[:text]
          tw=text.length*8+16; th=22
          sx=screen.x-tw/2; sy=screen.y-th/2
          bg_pts=[Geom::Point3d.new(sx,sy,0),Geom::Point3d.new(sx+tw,sy,0),
                  Geom::Point3d.new(sx+tw,sy+th,0),Geom::Point3d.new(sx,sy+th,0)]
          is_sel=zones.any? { |zone| @selected_zones.include?(zone)||@hovered_zone==zone||@merge_source==zone||@move_source_zone==zone }
          bg_c=LABEL_BG; txt_c=is_sel ? Sketchup::Color.new(255,0,0,255) : LABEL_COLOR
          if has_active && !is_sel
            bg_c=Sketchup::Color.new(LABEL_BG.red,LABEL_BG.green,LABEL_BG.blue,30)
            txt_c=Sketchup::Color.new(LABEL_COLOR.red,LABEL_COLOR.green,LABEL_COLOR.blue,50)
          end
          MH::OverlayEngine.rect(view, sx, sy, tw, th, bg_c, bg_pts)
          MH::OverlayEngine.text(view, screen.x, sy + 4, text, size: 14, bold: true, color: txt_c, align: 1)
        end
      end

      def label_entries(view)
        visible = @isolated_zone ? [@isolated_zone] : @zones.reject(&:hidden)
        grouped = {}
        singles = []

        visible.each do |zone|
          label = zone.label.to_s
          next if label.empty?

          base = sp_base_label(label)
          if base
            (grouped[base] ||= []) << zone
          else
            singles << { text: label, center: zone.center, zones: [zone] }
          end
        end

        entries = []
        grouped.each do |base, zones|
          modules = zones.select { |zone| module_label?(zone.label) }
          if modules.any? && !modules.all? { |zone| full_module_label_visible?(zone, view) }
            entries << { text: base, center: group_label_center(zones), zones: zones }
          else
            zones.each { |zone| entries << { text: zone.label.to_s, center: zone.center, zones: [zone] } }
          end
        end
        entries.concat(singles)
      end

      def sp_base_label(label)
        base = MH::FastRename.product_base_label(label)
        base.to_s.empty? ? nil : base
      end

      def module_label?(label)
        text = label.to_s
        base = sp_base_label(text)
        return false if base.to_s.empty? || !text.upcase.start_with?(base.to_s.upcase)
        suffix = text[base.length..-1].to_s
        suffix.match?(/\A\.\d+/) || suffix.match?(/\A[._-].+/)
      end

      def bounds_tuple_for_zones(zones)
        bb = Geom::BoundingBox.new
        Array(zones).each do |zone|
          next unless zone
          zone.corners.each { |point| bb.add(point) }
        end
        return nil unless bb.valid?
        [bb.min.x, bb.max.x, bb.min.y, bb.max.y, bb.min.z, bb.max.z]
      end

      def zone_distance_to_tuple(zone, tuple)
        return Float::INFINITY unless zone && tuple
        z_tuple = MH::FastRename.bounds_pair_to_tuple(zone.bounds)
        return Float::INFINITY unless z_tuple
        MH::FastRename.bb_distance_raw(
          z_tuple[0], z_tuple[1], z_tuple[2], z_tuple[3], z_tuple[4], z_tuple[5],
          tuple[0], tuple[1], tuple[2], tuple[3], tuple[4], tuple[5]
        )
      end

      def nearest_named_neighbor_zone(source_zones)
        source_tuple = bounds_tuple_for_zones(source_zones)
        return nil unless source_tuple

        candidates = (@zones - Array(source_zones)).select do |zone|
          sp_base_label(zone.label).to_s != ""
        end
        return nil if candidates.empty?

        candidates.min_by do |zone|
          module_bias = module_label?(zone.label) ? -1 : 0
          [zone_distance_to_tuple(zone, source_tuple), module_bias]
        end
      end

      def full_module_label_visible?(zone, view)
        label = zone.label.to_s
        return true unless module_label?(label)

        full_text_width = label.length * 8 + 16
        max_screen_span = zone_screen_span(zone, view)
        max_screen_span >= full_text_width + 24
      end

      def group_label_center(zones)
        bb = Geom::BoundingBox.new
        zones.each { |zone| zone.corners.each { |point| bb.add(point) } }
        bb.center
      end

      def zone_screen_span(zone, view)
        pts2d = zone.corners.map { |p| view.screen_coords(p) }
        xs = pts2d.map(&:x)
        ys = pts2d.map(&:y)
        [(xs.max - xs.min).abs, (ys.max - ys.min).abs].max
      rescue
        0
      end

      def draw_split_preview(view)
        zone=@hovered_zone; return unless zone
        axis=SPLIT_AXES[@split_axis]; pos=@split_preview_pos
        split_scope = @isolated_zone ? [@isolated_zone] : @zones
        if @split_all && !split_scope.empty?
          mn=Geom::Point3d.new(split_scope.map{|z|z.bounds[0].x}.min,
                               split_scope.map{|z|z.bounds[0].y}.min,
                               split_scope.map{|z|z.bounds[0].z}.min)
          mx=Geom::Point3d.new(split_scope.map{|z|z.bounds[1].x}.max,
                               split_scope.map{|z|z.bounds[1].y}.max,
                               split_scope.map{|z|z.bounds[1].z}.max)
        else
          mn,mx=zone.bounds
        end
        pts=split_plane_pts(mn,mx,axis,pos); return unless pts
        pts2d=pts.map{|p|view.screen_coords(p)}
        MH::OverlayEngine.polygon2d(view, pts2d, color: SPLIT_PREVIEW)
        MH::OverlayEngine.line2d(view, pts2d, color: SPLIT_COLOR, mode: GL_LINE_LOOP, stipple: '', width: 3)
        MH::OverlayEngine.line2d(view, [pts2d[0], pts2d[2], pts2d[1], pts2d[3]], color: SPLIT_COLOR, stipple: '', width: 3)
      end

      def split_plane_pts(mn,mx,axis,pos)
        case axis
        when :z
          return nil if pos<mn.z||pos>mx.z
          [Geom::Point3d.new(mn.x,mn.y,pos),Geom::Point3d.new(mx.x,mn.y,pos),
           Geom::Point3d.new(mx.x,mx.y,pos),Geom::Point3d.new(mn.x,mx.y,pos)]
        when :x
          return nil if pos<mn.x||pos>mx.x
          [Geom::Point3d.new(pos,mn.y,mn.z),Geom::Point3d.new(pos,mx.y,mn.z),
           Geom::Point3d.new(pos,mx.y,mx.z),Geom::Point3d.new(pos,mn.y,mx.z)]
        when :y
          return nil if pos<mn.y||pos>mx.y
          [Geom::Point3d.new(mn.x,pos,mn.z),Geom::Point3d.new(mx.x,pos,mn.z),
           Geom::Point3d.new(mx.x,pos,mx.z),Geom::Point3d.new(mn.x,pos,mx.z)]
        end
      end

      def pick_zone(ray,view,x,y,ip=nil)
        visible = @isolated_zone ? [@isolated_zone] : @zones.reject(&:hidden)
        # Label pick
        label_entries(view).each do |entry|
          sc=view.screen_coords(entry[:center])
          text=entry[:text]
          tw=text.length*8+16; th=22
          sx=sc.x-tw/2; sy=sc.y-th/2
          return [entry[:zones].first,nil,:text,entry[:zones]] if x>=sx&&x<=sx+tw&&y>=sy&&y<=sy+th
        end
        # IP snapping
        if ip&&ip.valid?&&ip.degrees_of_freedom<2
          pt=ip.position; best_z=nil; best_d=Float::INFINITY
          visible.each do |z|
            mn,mx=z.bounds; pad=0.5
            if pt.x>=mn.x-pad&&pt.x<=mx.x+pad&&
               pt.y>=mn.y-pad&&pt.y<=mx.y+pad&&
               pt.z>=mn.z-pad&&pt.z<=mx.z+pad
              d=pt.distance(z.center)
              if d<best_d; best_d=d; best_z=z; end
            end
          end
          return [best_z,pt,:box] if best_z
        end
        # Ray-AABB
        origin,dir=ray
        ox,oy,oz=origin.x,origin.y,origin.z
        dx,dy,dz=dir.x,dir.y,dir.z
        best_t=Float::INFINITY; best_zone=nil; best_pt=nil
        visible.each do |zone|
          mn,mx=zone.bounds; pad=0.5
          mnx,mny,mnz=mn.x-pad,mn.y-pad,mn.z-pad
          mxx,mxy,mxz=mx.x+pad,mx.y+pad,mx.z+pad
          tx1=dx.abs<1e-12 ? (ox>=mnx&&ox<=mxx ? -Float::INFINITY : Float::INFINITY) : (mnx-ox)/dx
          tx2=dx.abs<1e-12 ? (ox>=mnx&&ox<=mxx ?  Float::INFINITY : -Float::INFINITY) : (mxx-ox)/dx
          tx1,tx2=tx2,tx1 if tx1>tx2
          ty1=dy.abs<1e-12 ? (oy>=mny&&oy<=mxy ? -Float::INFINITY : Float::INFINITY) : (mny-oy)/dy
          ty2=dy.abs<1e-12 ? (oy>=mny&&oy<=mxy ?  Float::INFINITY : -Float::INFINITY) : (mxy-oy)/dy
          ty1,ty2=ty2,ty1 if ty1>ty2
          tz1=dz.abs<1e-12 ? (oz>=mnz&&oz<=mxz ? -Float::INFINITY : Float::INFINITY) : (mnz-oz)/dz
          tz2=dz.abs<1e-12 ? (oz>=mnz&&oz<=mxz ?  Float::INFINITY : -Float::INFINITY) : (mxz-oz)/dz
          tz1,tz2=tz2,tz1 if tz1>tz2
          t_enter=[tx1,ty1,tz1].max; t_exit=[tx2,ty2,tz2].min
          next if t_exit<0||t_enter>t_exit
          t_hit=t_enter<0 ? t_exit : t_enter; next if t_hit<0
          if t_hit<best_t
            best_t=t_hit; best_zone=zone
            best_pt=Geom::Point3d.new(ox+dx*t_hit,oy+dy*t_hit,oz+dz*t_hit)
          end
        end
        return [best_zone,best_pt,:box] if best_zone
        # Fallback: zone gần cursor nhất
        best_d=Float::INFINITY
        visible.each do |z|
          sc=view.screen_coords(z.center)
          d=Math.sqrt((sc.x-x)**2+(sc.y-y)**2)
          if d<best_d; best_d=d; best_zone=z; end
        end
        [best_zone,nil,:fallback]
      end

      def get_split_pos(zone,axis,hit_pt,ip)
        mn,mx=zone.bounds; axis_idx=[:x,:y,:z].index(axis)
        mn_val=[mn.x,mn.y,mn.z][axis_idx]; mx_val=[mx.x,mx.y,mx.z][axis_idx]
        if ip&&ip.valid?&&ip.degrees_of_freedom<2
          pt=ip.position; pad=0.5
          if pt.x>=mn.x-pad&&pt.x<=mx.x+pad&&
             pt.y>=mn.y-pad&&pt.y<=mx.y+pad&&
             pt.z>=mn.z-pad&&pt.z<=mx.z+pad
            return pt.to_a[axis_idx].clamp(mn_val,mx_val)
          end
        end
        return hit_pt.to_a[axis_idx].clamp(mn_val,mx_val) if hit_pt
        return ip.position.to_a[axis_idx].clamp(mn_val,mx_val) if ip&&ip.valid?
        zone.center.to_a[axis_idx]
      end

      def onMouseMove(flags,x,y,view)
        @mouse_x,@mouse_y=x,y
        if @drag_start; @drag_current=[x,y]; view.invalidate; return; end
        ray=view.pickray(x,y)
        if @mode==:select
          if entity_move_pending?
            update_alt_hover_move(ray, x, y, view)
          elsif alt_down?(flags)
            update_alt_hover_move(ray, x, y, view)
          else
            zone,_pt,_ht=pick_zone(ray,view,x,y)
            @hovered_zone=zone
            clear_move_hover
          end
          view.invalidate
        elsif @mode==:split
          @ip.pick(view,x,y)
          zone,hit_pt,_ht=pick_zone(ray,view,x,y,@ip)
          @hovered_zone=zone
          @split_preview_pos=zone&&@selected_zones.empty? ? get_split_pos(zone,SPLIT_AXES[@split_axis],hit_pt,@ip) : nil
          view.invalidate
        elsif @mode==:merge_target
          zone,_pt,_ht=pick_zone(ray,view,x,y)
          @hovered_zone=zone; view.invalidate
        end
      end

      def update_alt_hover_move(ray, x, y, view)
        zone, _pt, _ht = pick_zone(ray, view, x, y)
        @hovered_zone = zone

        if !entity_move_pending?
          entity = pick_zone_entity(view, x, y)
          source_zone = entity ? find_zone_for_entity(entity) : nil
          @move_hover_entity = entity
          @move_hover_source_zone = source_zone
          set_move_target_zone(nil)
        elsif zone && zone != @move_source_zone
          set_move_target_zone(zone)
        else
          set_move_target_zone(nil)
        end
        update_status
      end

      def set_move_target_zone(zone)
        @move_target_zone = zone
      end

      def onLButtonDoubleClick_deprecated_old(flags,x,y,view)
        onLButtonDoubleClick(flags,x,y,view)
        return
        ray=view.pickray(x,y)
        zone,_pt,_hit_type,_label_zones=pick_zone(ray,view,x,y)
        return unless zone
        if hit_type==:text
          if label_zones && label_zones.length > 1
            @selected_zones = label_zones
            update_status
            view.invalidate
            return
          end
          res=UI.inputbox(["Nhập mã cố định:"],[zone.label],"Sửa mã thủ công")
          if res; zone.label=res[0].to_s.strip; zone.locked=true; view.invalidate; end
        else
          isolate_zone(zone,view)
        end
      end

      def isolate_zone(zone,view)
        @isolated_zone||=nil; @hidden_by_isolate||=[]
        model = @model || Sketchup.active_model
        model.start_operation('MH Fast Rename Isolate', true)
        begin
          @hidden_by_isolate.each { |e| e.hidden = false if e && e.valid? }
          @hidden_by_isolate.clear
          if @isolated_zone==zone
            @isolated_zone=nil
          else
            target_lookup = {}
            zone.entities.each do |entity|
              target_lookup[entity.object_id] = true if entity && entity.valid?
            end
            isolate_scope = @all_entities && @all_entities.any? ? @all_entities : model.active_entities.to_a
            isolate_scope.each do |entity|
              next unless entity && entity.valid? && !entity.hidden?
              next if target_lookup[entity.object_id]
              entity.hidden = true
              @hidden_by_isolate << entity
            end
            @isolated_zone=zone
          end
          model.commit_operation
        rescue => e
          model.abort_operation
          UI.beep
          Sketchup.status_text = "Loi isolate: #{e.message}"
        end
        view.invalidate
      end

      def merge_zones(zones, view = nil)
        merge_list = Array(zones).compact.uniq.select { |zone| @zones.include?(zone) }
        return nil if merge_list.length < 2

        first = merge_list.first
        merged_ents = []
        merge_list.each { |zone| merged_ents.concat(zone.entities) }

        nz = MH::FastRename.create_zone(first.id, merged_ents, @split_bounds_cache)
        nz.label = extract_sp_base(first.label)
        nz.zone_type = :sp
        nz.parent_id = first.parent_id
        nz.locked = true

        merge_list.each { |zone| @zones.delete(zone) }
        @zones << nz
        @zones.each_with_index { |zone, idx| zone.id = idx }
        @selected_zones = [nz]
        @hovered_zone = nz
        @mode = :select
        @merge_source = nil
        update_status
        view.invalidate if view
        nz
      end

      def onLButtonDown(flags,x,y,view)
        if @mode==:select
          if alt_down?(flags)
            lock_hover_move_entity(view)
            return
          end
          if entity_move_pending?
            clear_entity_move
            update_status
            view.invalidate
            return
          end
          # Bắt đầu drag-to-select
          @drag_start=[x,y]; @drag_current=[x,y]
          @drag_ctrl = copy_down?(flags)
        elsif @mode==:split
          if @hovered_zone&&@split_preview_pos&&@selected_zones.empty?
            @split_all ? split_all_zones(SPLIT_AXES[@split_axis],@split_preview_pos) :
                         split_zone_immediately(@hovered_zone,SPLIT_AXES[@split_axis],@split_preview_pos)
            view.invalidate
          end
        elsif @mode==:merge_target
          ray=view.pickray(x,y)
          target,_pt,_ht=pick_zone(ray,view,x,y)
          if target&&target!=@merge_source
            merge_zones([@merge_source, target], view)
          end
        end
      end

      def onLButtonUp(flags,x,y,view)
        if entity_move_pending?
          moved = move_entity_to_zone(@move_target_zone, view)
          unless moved
            clear_entity_move
            update_status
            view.invalidate if view
          end
          return
        end
        return unless @drag_start
        x1=[@drag_start[0],@drag_current[0]].min; x2=[@drag_start[0],@drag_current[0]].max
        y1=[@drag_start[1],@drag_current[1]].min; y2=[@drag_start[1],@drag_current[1]].max
        ctrl_held = @drag_ctrl || false

        if (x2-x1) > 5 || (y2-y1) > 5
          # Drag select: quét chọn nhiều zone
          drag_zones = @zones.select { |zone|
            sc=view.screen_coords(zone.center)
            sc.x>=x1 && sc.x<=x2 && sc.y>=y1 && sc.y<=y2
          }
          if ctrl_held
            # Ctrl+Drag: toggle các zone trong vùng quét
            drag_zones.each do |z|
              if @selected_zones.include?(z)
                @selected_zones.delete(z)
              else
                @selected_zones << z
              end
            end
          else
            @selected_zones = drag_zones
          end
        else
          # Click đơn
          ray=view.pickray(x,y)
          zone,_pt,_ht,label_zones=pick_zone(ray,view,x,y)
          if zone
            hit_zones = label_zones || [zone]
            if shift_down?(flags) && _ht == :text
              editable_zone = hit_zones.find { |hit_zone| module_label?(hit_zone.label) }
              if editable_zone
                edit_module_label(editable_zone, view)
              else
                UI.beep
                Sketchup.status_text = "Shift+Click chỉ sửa tên modul"
              end
              @drag_start=nil; @drag_current=nil; @drag_ctrl=false
              return
            elsif ctrl_held
              merge_targets = @selected_zones.dup
              hit_zones.each do |hit_zone|
                merge_targets << hit_zone unless merge_targets.include?(hit_zone)
              end
              if merge_targets.uniq.length >= 2
                merge_zones(merge_targets, view)
                @drag_start=nil; @drag_current=nil; @drag_ctrl=false
                return
              end
              @selected_zones = hit_zones
              Sketchup.status_text = "Đã chọn khối nguồn — Ctrl+Click khối khác để gộp"
            else
              @selected_zones = hit_zones
            end
          else
            @selected_zones.clear unless ctrl_held
          end
        end
        @drag_start=nil; @drag_current=nil; @drag_ctrl=false
        update_status; view.invalidate
      end

      def edit_module_label(zone, view)
        return false unless zone && module_label?(zone.label)
        res = UI.inputbox(["Tên modul:"], [zone.label.to_s], "Sửa tên modul")
        return false unless res
        new_label = res[0].to_s.strip
        return false if new_label.empty?
        zone.label = new_label
        zone.zone_type = :modul
        zone.locked = true
        @selected_zones = [zone]
        @hovered_zone = zone
        update_status
        view.invalidate if view
        true
      end

      def assign_zones_to_neighbor_modules(zones, view)
        target_zones = Array(zones).compact
        return false if target_zones.empty?

        neighbor_zone = nearest_named_neighbor_zone(target_zones)
        neighbor_base = neighbor_zone ? sp_base_label(neighbor_zone.label) : nil

        base_nums = target_zones.map { |z| MH::FastRename.product_number(z.label) }.compact
        base_label = neighbor_base || (base_nums.empty? ? nil : MH::FastRename.format_product_code(base_nums.min))
        unless base_label
          UI.messagebox("Không tìm thấy sản phẩm lân cận để lấy mã modul.")
          return false
        end

        module_rules = MH::FastRename.registry_module_rules_for_sp(base_label)
        if module_rules.empty?
          UI.messagebox("#{base_label} chưa có dòng modul trong MH_Registry.")
          return false
        end
        if module_rules.length < target_zones.length
          UI.messagebox("#{base_label} có #{module_rules.length} modul trong MH_Registry, nhưng đang chọn #{target_zones.length} khối.")
          return false
        end

        sel_sp_nums = target_zones.map { |z| MH::FastRename.product_number(z.label) }.compact.uniq.sort
        base_num = MH::FastRename.product_number(base_label).to_i

        sorted_targets = target_zones.sort_by { |z| [z.center.x.round(0), -z.center.z.round(0)] }
        sorted_targets.each_with_index do |z, idx|
          z.label = MH::FastRename.registry_module_label(base_label, idx, module_rules[idx])
          z.zone_type = :modul
          z.locked = true
        end

        freed_count = sel_sp_nums.reject { |n| n == base_num }.length
        if freed_count > 0
          other_zones = @zones - sorted_targets
          other_zones.sort_by! { |z|
            MH::FastRename.product_number(z.label) || 9999
          }
          other_zones.each do |z|
            sp_num = MH::FastRename.product_number(z.label)
            next unless sp_num
            next if sp_num <= base_num
            new_sp_num = [sp_num - freed_count, base_num + 1].max
            z.label = MH::FastRename.replace_product_base(z.label, MH::FastRename.format_product_code(new_sp_num))
          end
        end

        @zones.each_with_index { |z, i| z.id = i }
        @selected_zones.clear
        update_status
        view.invalidate if view
        true
      end

      def clear_product_module_names_for_zones(zones, view)
        target_zones = Array(zones).compact
        return false if target_zones.empty?

        entities = target_zones.flat_map { |zone| zone.entities }.compact.uniq
        return false if entities.empty?

        model = Sketchup.active_model
        model.start_operation('MH Fast Rename Clear SP/Modul', true)
        renamed = MH::FastRename.clear_product_module_prefixes(entities)
        model.commit_operation

        Sketchup.status_text = "Đã xóa mã SP/Modul #{renamed} object(s)"
        update_status
        view.invalidate if view
        true
      rescue => e
        model.abort_operation rescue nil
        UI.messagebox("Không xóa được mã SP/Modul: #{e.message}")
        false
      end

      def getMenu(menu,flags,x,y,view)
        if @mode==:split
          menu.add_item("Tắt chế độ Cắt khối (ESC)") {
            @mode=:select; @split_preview_pos=nil; update_status; view.invalidate
          }
          return true
        end
        if @mode==:select
          menu.add_item("Bật chế độ Cắt khối (C)") {
            clear_entity_move
            @mode=:split; @selected_zones.clear; update_status; view.invalidate
          }
          menu.add_item("Tự động chia lại tất cả") {
            recluster_all; view.invalidate
          }
          menu.add_item("Chia theo mã SP gốc (P)") {
            prompt_and_regroup_by_sp_prefix
          }
          menu.add_separator
          ray=view.pickray(x,y)
          zone,_pt=pick_zone(ray,view,x,y)
          if @selected_zones.length>1
            menu.add_item("Gộp #{@selected_zones.length} khối đã chọn") {
              merge_zones(@selected_zones, view)
            }
            menu.add_item("Gộp modul theo MH_Registry") {
              assign_zones_to_neighbor_modules(@selected_zones, view)
            }
            menu.add_item("Xóa mã SP/Modul #{@selected_zones.length} khối đã chọn") {
              clear_product_module_names_for_zones(@selected_zones, view)
            }
          elsif zone
            menu.add_item("Sửa mã thủ công...") {
              res=UI.inputbox(["Mã:"],[zone.label],"Sửa mã")
              if res; zone.label=res[0].to_s.strip; zone.locked=true; view.invalidate; end
            }
            menu.add_item("Đánh modul theo SP lân cận") {
              assign_zones_to_neighbor_modules([zone], view)
            }
            menu.add_item("Xóa mã SP/Modul khối này") {
              clear_product_module_names_for_zones([zone], view)
            }
            menu.add_item("Gộp với khối khác...") {
              clear_entity_move
              @mode=:merge_target; @merge_source=zone
              @selected_zones.clear; update_status; view.invalidate
            }
            menu.add_separator
            menu.add_item("Tự động cắt lại khối này") {
              split_bounds_cache = {}
              face_cache = {}
              core_ents, sp_base_only_ents, modul_contact_ents = split_entities_for_virtual_box(zone.entities)
              base_label = extract_sp_base(zone.label)
              module_rules = MH::FastRename.registry_module_rules_for_sp(base_label)
              if module_rules.empty?
                UI.messagebox("SP #{base_label} chưa có dòng modul trong MH_Registry.")
                next
              end
              named_separators = MH::FastRename.cp_named_contact_separators(core_ents, split_bounds_cache)
              sub_groups = MH::FastRename.split_entities_into_groups(core_ents, zone.bounds, split_bounds_cache, named_separators, face_cache)
              if core_ents.length > 1 && sub_groups.length > 1
                merged = MH::FastRename.merge_orphans_into_groups(sub_groups, split_bounds_cache, face_cache)
                # Sắp xếp sub-zones: X rồi Z
                sorted_merged = merged.sort_by { |grp|
                  bmin, bmax = grp[:bounds]
                  cx = (bmin.x + bmax.x) * 0.5
                  cz = (bmin.z + bmax.z) * 0.5
                  [cx.round(0), -cz.round(0)]
                }
                assigned_groups = assign_old_module_groups(sorted_merged, base_label, module_rules)
                if module_rules.length < assigned_groups.length
                  UI.messagebox("SP #{base_label} có #{module_rules.length} modul trong MH_Registry, nhưng khối đang tách ra #{assigned_groups.length} nhóm.")
                  next
                end
                @zones.delete(zone)
                module_zones = []
                assigned_groups.each_with_index do |(grp, _used_old_labels), sub_idx|
                  nz=Zone.new(0, grp[:bounds], grp[:ents])
                  nz.zone_type=:modul; nz.parent_id=zone.id
                  nz.label=grp[:label].to_s.empty? ? MH::FastRename.registry_module_label(base_label, sub_idx, module_rules[sub_idx]) : grp[:label]
                  nz.locked=true
                  @zones<<nz
                  module_zones << nz
                end
                accessory_zone, remaining_sp_base_only = create_base_accessory_zone(
                  base_label,
                  zone.id,
                  sp_base_only_ents,
                  module_zones.length + 1,
                  module_rules[module_zones.length]
                )
                if accessory_zone
                  @zones << accessory_zone
                  module_zones << accessory_zone
                end
                attach_special_entities_to_modules(module_zones, remaining_sp_base_only, modul_contact_ents, split_bounds_cache, face_cache)
                @zones.each_with_index { |z, i| z.id = i }
              else
                UI.messagebox("Không thể cắt thêm khối này!")
              end
              view.invalidate
            }
          end
          menu.add_separator
          menu.add_item("Cài đặt số SP bắt đầu...") {
            res=UI.inputbox(["Số bắt đầu:"],[@sp_start_num],"Cài đặt")
            if res
              @sp_start_num=[res[0].to_i,1].max
              @force_renumber = true
              @zones = if @sp_prefix_grouping_active
                MH::FastRename.sort_and_label_sp_zones(@zones, MH::FastRename.product_family, @sp_start_num, true)
              else
                MH::FastRename.sort_and_label_zones(@zones, MH::FastRename.product_family, @sp_start_num)
              end
              view.invalidate
            end
          }
          menu.add_item("Khoảng cách gộp (mm)...") {
            res=UI.inputbox(["Khoảng cách tối đa (mm):"],[@gap_threshold_mm],"Gộp khối")
            if res&&res[0].to_f>0
              @gap_threshold_mm=res[0].to_f
              @sp_prefix_grouping_active ? regroup_by_sp_prefix : recluster_all
              view.invalidate
            end
          }
          menu.add_separator
          menu.add_item("Xóa mã SP/Modul toàn bộ zone") {
            clear_product_module_names_for_zones(@zones, view)
          }
          menu.add_item("Đánh số lại Modul") {
            # Unlock tất cả, đánh số lại modul theo từng SP, rồi lock lại
            @zones.each { |z| z.locked = false }
            @zones = MH::FastRename.renumber_module_labels(@zones)
            @zones.each { |z| z.locked = true }
            update_status; view.invalidate
          }
          menu.add_item("Đánh số lại SP") {
            # Unlock tất cả, đánh số lại mã SP, giữ nguyên hậu tố modul, rồi lock lại
            @zones.each { |z| z.locked = false }
            @zones = MH::FastRename.renumber_sp_labels(@zones, MH::FastRename.product_family, @sp_start_num)
            @zones.each { |z| z.locked = true }
            update_status; view.invalidate
          }
        elsif @mode==:merge_target
          menu.add_item("Hủy Gộp") {
            @mode=:select; @merge_source=nil; update_status; view.invalidate
          }
        end
        true
      end

      def onKeyDown(key,repeat,flags,view)
        case key
        when 67
          if @mode==:select
            clear_entity_move
            @mode=:split; @selected_zones.clear; update_status; view.invalidate; return true
          elsif @mode==:split
            @mode=:select; @split_preview_pos=nil; update_status; view.invalidate; return true
          end
        when COPY_MODIFIER_KEY,17
          if @mode==:split; @split_all=!@split_all; update_status; view.invalidate; return true; end
        when 18
          @alt_down_latched = true
          if @mode==:select && @mouse_x && @mouse_y
            ray=view.pickray(@mouse_x,@mouse_y)
            update_alt_hover_move(ray, @mouse_x, @mouse_y, view)
            view.invalidate
          end
          return true
        when 9
          cycle_split_mode(view)
          return true
        when 80
          if @mode == :select
            prompt_and_regroup_by_sp_prefix
            return true
          end
        when 38  # Arrow Up — tăng SP từ zone chọn trở đi, SP trước không đổi
          if @mode==:select && @selected_zones.length >= 1
            sel = @selected_zones.first
            old_num = MH::FastRename.product_number(sel.label)
            if old_num
              # Dồn từ lớn→nhỏ: tất cả SP >= old_num tăng lên 1
              (99).downto(old_num) do |n|
                pf = MH::FastRename.format_product_code(n)
                np = MH::FastRename.format_product_code(n + 1)
                @zones.each do |z|
                  z.label = MH::FastRename.replace_product_base(z.label, np) if z.label.start_with?(pf)
                end
              end
            end
          else
            @sp_start_num+=1; @force_renumber=true
            if @sp_prefix_grouping_active
              @zones=MH::FastRename.sort_and_label_sp_zones(@zones, MH::FastRename.product_family, @sp_start_num, true)
            else
              @zones=MH::FastRename.sort_and_label_zones(@zones, MH::FastRename.product_family, @sp_start_num, true)
              auto_split_contact_planes if MH::FastRename.auto_contact_split?
            end
          end
          update_status; view.invalidate; return true
        when 40  # Arrow Down — giảm SP từ zone chọn trở đi, SP trước không đổi
          if @mode==:select && @selected_zones.length >= 1
            sel = @selected_zones.first
            old_num = MH::FastRename.product_number(sel.label)
            if old_num
              return true if old_num <= 1
              # Dồn từ nhỏ→lớn: tất cả SP >= old_num giảm xuống 1
              (old_num).upto(99) do |n|
                pf = MH::FastRename.format_product_code(n)
                np = MH::FastRename.format_product_code(n - 1)
                @zones.each do |z|
                  z.label = MH::FastRename.replace_product_base(z.label, np) if z.label.start_with?(pf)
                end
              end
            end
          else
            @sp_start_num=[@sp_start_num-1,1].max; @force_renumber=true
            if @sp_prefix_grouping_active
              @zones=MH::FastRename.sort_and_label_sp_zones(@zones, MH::FastRename.product_family, @sp_start_num, true)
            else
              @zones=MH::FastRename.sort_and_label_zones(@zones, MH::FastRename.product_family, @sp_start_num, true)
              auto_split_contact_planes if MH::FastRename.auto_contact_split?
            end
          end
          update_status; view.invalidate; return true
        when 13
          if @mode==:select||@mode==:split; apply_rename; @model.select_tool(nil); return true; end
        when 27
          if entity_move_pending?
            clear_entity_move
            update_status
            view.invalidate
            return true
          end
          if @mode==:split
            @mode=:select; @split_preview_pos=nil; update_status; view.invalidate; return true
          elsif @mode!=:select
            @mode=:select; @merge_source=nil; update_status; view.invalidate; return true
          else
            @model.select_tool(nil); return true
          end
        end
        false
      end
      def onKeyUp(key,repeat,flags,view)
        if key == 18
          @alt_down_latched = false
          unless entity_move_pending?
            clear_move_hover
            update_status
            view.invalidate if view
          end
          return true
        end
        false
      end

      def getExtents
        bb=Geom::BoundingBox.new
        @zones.each{|z|z.corners.each{|p|bb.add(p)}}; bb
      end

      def renumber_zones
        @zones = if @sp_prefix_grouping_active
              MH::FastRename.sort_and_label_sp_zones(@zones, MH::FastRename.product_family, @sp_start_num, true)
        else
              MH::FastRename.sort_and_label_zones(@zones, MH::FastRename.product_family, @sp_start_num, true)
        end
      end

      def move_zone_label(zone,direction)
        zone.label_offset=(zone.label_offset||0)+direction
        zone.label_offset=0 if zone.label_offset<0
        renumber_zones
      end

      def split_zone_immediately(zone,axis,pos)
        new_zones=zone.split(axis,pos)
        if new_zones&.length==2
          base_label = extract_sp_base(zone.label)
          @zones.delete(zone)

          # Sắp xếp 2 nhóm mới theo X rồi Z
          sorted_new = new_zones.sort_by { |z|
            [z.center.x.round(0), -z.center.z.round(0)]
          }

          # Tìm số modul hiện có của base_label
          existing_moduls = @zones.select { |z|
            MH::FastRename.module_number_from_label(z.label, base_label)
          }
          max_modul = existing_moduls.map { |z|
            MH::FastRename.module_number_from_label(z.label, base_label).to_i
          }.max || 0

          # Nếu zone gốc là SP và chưa có modul nào thì bắt đầu từ modul 1.
          if max_modul == 0
            sorted_new.each_with_index do |z, idx|
              z.zone_type = :modul
              z.parent_id = zone.id
              z.label = MH::FastRename.module_label(base_label, idx + 1)
              z.locked = true
            end
          else
            # Đã có modul → tiếp tục đánh số
            sorted_new.each_with_index do |z, idx|
              z.zone_type = :modul
              z.parent_id = zone.id
              z.label = MH::FastRename.module_label(base_label, max_modul + idx + 1)
              z.locked = true
            end
          end

          @zones.concat(sorted_new)
          @zones.each_with_index { |z, i| z.id = i }
          @hovered_zone=nil; @split_preview_pos=nil
        else
          UI.beep
          Sketchup.status_text="Không thể cắt tại đây!"
        end
      end

      def split_all_zones(axis,pos)
        to_add=[]; to_del=[]; count=0
        split_scope = @isolated_zone ? [@isolated_zone] : @zones
        split_scope.each do |z|
          nz=z.split(axis,pos)
          if nz&.length==2
            count+=1; to_del<<z
            nz.each{|n|n.zone_type=z.zone_type;n.parent_id=z.id}
            to_add.concat(nz)
          end
        end
        if count>0
          @zones-=to_del; @zones.concat(to_add)
        @zones=MH::FastRename.sort_and_label_zones(@zones, MH::FastRename.product_family, @sp_start_num, @force_renumber)
          @hovered_zone=nil; @split_preview_pos=nil
        else
          UI.beep; Sketchup.status_text="Không có khối nào bị cắt!"
        end
      end

      def module_zones_by_base_label
        grouped = Hash.new { |h, k| h[k] = [] }
        @zones.each do |z|
          next unless module_label?(z.label)
          base = sp_base_label(z.label)
          next if base.nil? || base.empty?
          grouped[base] << z
        end
        grouped
      end

      def resolve_prefix_for_entity(entity, zone, modules_by_base, split_bounds_cache = nil, face_cache = nil)
        current_label = zone.label.to_s
        base_label = extract_sp_base(current_label)

        return base_label if MH::FastRename.sp_base_only_entity?(entity)

        if MH::FastRename.modul_contact_entity?(entity)
          module_candidates = modules_by_base[base_label]
          if module_candidates && !module_candidates.empty?
            best_zone = pick_best_module_zone_for_entity(entity, module_candidates, split_bounds_cache, face_cache)
            return best_zone.label.to_s if best_zone
          end
        end

        current_label
      end

      def strip_leading_module_tokens(text)
        MH::FastRename.strip_leading_module_tokens(text)
      end

      def strip_existing_fast_prefix(name)
        MH::FastRename.strip_product_module_prefix(name)
      end

      def apply_rename
        model=Sketchup.active_model
        model.start_operation('MH Fast Rename',true)
        modules_by_base = module_zones_by_base_label
        split_bounds_cache = {}
        face_cache = {}
        @zones.each do |zone|
          zone.entities.each do |e|
            next unless e.valid?
            raw_name=e.respond_to?(:name) ? e.name : ''
            clean=raw_name.gsub(/^_+\d+\.?\s*/,'')
            clean=strip_existing_fast_prefix(clean)
            has_prefix=false
            @prefix_suggestions.each do |p|
              if clean.downcase.start_with?(p.downcase)
                sep_match=clean[p.length..-1]&.match(/^[.\-_\s]*/)
                sep=sep_match ? sep_match[0] : ""
                body=clean[(p.length+sep.length)..-1]||""
                clean=body; has_prefix=true; break
              end
            end
            unless has_prefix
              m=clean.match(/^([A-Za-z]+\d+(?:\.[A-Za-z0-9]+)*)([.\-_\s]*)/)
              clean=clean[m[0].length..-1]||"" if m
            end
            new_prefix = resolve_prefix_for_entity(e, zone, modules_by_base, split_bounds_cache, face_cache)
            part_sep = if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:part_separator)
              MH::NameGrammar.part_separator.to_s
            else
              "_"
            end
            part_sep = "_" if part_sep.empty?
            sep=new_prefix.empty? ? "" : part_sep
            new_name=clean.empty? ? new_prefix : "#{new_prefix}#{sep}#{clean}"
            sys=raw_name.match(/^(_+\d+\.?\s*)/){$1}||""
            e.name=sys+new_name
          end
        end
        model.commit_operation
        Sketchup.status_text="Đã đổi tên #{@zones.sum{|z|z.entities.length}} object(s) trong #{@zones.length} zone(s)"
      end

      # Double click chỉ dùng để isolate/unisolate khối
      # Double click chỉ dùng để isolate/unisolate khối
      # Double click chỉ dùng để isolate/unisolate khối
      def onLButtonDoubleClick(flags,x,y,view)
        ray=view.pickray(x,y)
        zone,_pt,_hit_type,_label_zones=pick_zone(ray,view,x,y)
        return unless zone
        isolate_zone(zone,view)
      end

      def update_status
        case @mode
        when :select
          if entity_move_pending?
            Sketchup.status_text = "CHUYEN OBJ | Da khoa chi tiet | Giu chuot keo den modul dich | Nha chuot: xac nhan | ESC: huy"
          elsif @move_hover_entity
            Sketchup.status_text = "CHUYEN OBJ | ALT dang highlight chi tiet | Click de khoa chi tiet, giu chuot keo den modul dich"
          else
            sel_txt = @selected_zones.length > 0 ? " [#{@selected_zones.length} da chon]" : ""
            Sketchup.status_text = "MH Fast Rename#{sel_txt} | Click: chon | Ctrl+Click: gop khoi | Shift+Click ten modul: sua | ALT+Hover: highlight chi tiet | ALT+Click+Keo: chuyen modul | P: Chia theo SP | C: Cat | Enter: Ap dung"
          end
        when :split
          ax = split_mode_label(SPLIT_AXES[@split_axis])
          md = @split_all ? "XUYEN KHOI" : "1 KHOI"
          Sketchup.status_text = "CAT [#{ax}-#{md}] | Ctrl: doi kieu | Tab: doi che do | ESC/P.PHAI: Thoat"
        when :merge_target
          Sketchup.status_text = "GOP | Click khoi khac de gop | ESC: Huy"
        end
      end

      def split_mode_label(axis)
        SPLIT_MODE_LABELS[axis] || axis.to_s.upcase
      end

      def cycle_split_mode(view)
        if @mode != :split
          clear_entity_move
          @merge_source = nil if @mode == :merge_target
          @mode = :split
          @split_axis = 0
          @selected_zones.clear
        elsif @split_axis < SPLIT_AXES.length - 1
          @split_axis += 1
        else
          @mode = :select
          @split_preview_pos = nil
          @hovered_zone = nil
        end
        update_status
        view.invalidate
      end

      def entity_move_pending?
        @move_entity && @move_source_zone
      end

      def clear_move_hover
        @move_hover_entity = nil
        @move_hover_source_zone = nil
      end

      def clear_entity_move
        @move_entity = nil
        @move_source_zone = nil
        set_move_target_zone(nil)
        @move_dragging = false
        clear_move_hover
      end

      def lock_hover_move_entity(view)
        entity = @move_hover_entity
        source_zone = @move_hover_source_zone
        unless entity && entity.valid? && source_zone
          UI.beep
          Sketchup.status_text = "Giữ ALT và hover đúng chi tiết cần chuyển"
          view.invalidate if view
          return false
        end

        @move_entity = entity
        @move_source_zone = source_zone
        @move_dragging = true
        @selected_zones = [source_zone]
        set_move_target_zone(nil)
        update_status
        view.invalidate if view
        true
      end

      def move_entity_to_zone(target_zone, view)
        unless target_zone
          return false
        end

        if target_zone == @move_source_zone
          return false
        end

        unless @move_source_zone.entities.include?(@move_entity)
          clear_entity_move
          update_status
          view.invalidate
          return false
        end

        model = Sketchup.active_model
        model.start_operation('MH Fast Rename Move Object', true)
        begin
          @move_source_zone.entities.delete(@move_entity)
          target_zone.entities << @move_entity unless target_zone.entities.include?(@move_entity)

          if @move_source_zone.entities.empty?
            @zones.delete(@move_source_zone)
          else
            refresh_zone_bounds(@move_source_zone)
          end
          refresh_zone_bounds(target_zone)
          @zones.each_with_index { |z, i| z.id = i }
          model.commit_operation
        rescue => e
          model.abort_operation
          UI.beep
          Sketchup.status_text = "Loi chuyen object: #{e.message}"
          return false
        end

        clear_entity_move
        @selected_zones = [target_zone]
        @hovered_zone = target_zone
        update_status
        view.invalidate
        true
      end

      def find_zone_for_entity(entity)
        @zones.find { |zone| zone.entities.include?(entity) }
      end

      def zone_entity?(entity)
        return false unless entity
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end

      def pick_zone_entity(view, x, y)
        ph = view.pick_helper
        ph.do_pick(x, y)
        if ph.count == 0
          ray = view.pickray(x, y)
          zone, _pt, _ht = pick_zone(ray, view, x, y)
          return nearest_entity_in_zone(zone, x, y, view)
        end

        best = ph.best_picked
        if zone_entity?(best)
          zone = find_zone_for_entity(best)
          return best if zone
        end

        ph.count.times do |idx|
          path = ph.path_at(idx)
          next unless path
          path.reverse_each do |ent|
            next unless zone_entity?(ent)
            zone = find_zone_for_entity(ent)
            return ent if zone
          end
        end
        ray = view.pickray(x, y)
        zone, _pt, _ht = pick_zone(ray, view, x, y)
        nearest_entity_in_zone(zone, x, y, view)
      rescue
        nil
      end

      def nearest_entity_in_zone(zone, x, y, view)
        return nil unless zone
        best = nil
        best_d = Float::INFINITY
        zone.entities.each do |ent|
          next unless ent && ent.valid?
          sc = view.screen_coords(ent.bounds.center)
          d = (sc.x - x) * (sc.x - x) + (sc.y - y) * (sc.y - y)
          if d < best_d
            best_d = d
            best = ent
          end
        end
        best
      rescue
        nil
      end

      def refresh_zone_bounds(zone)
        return unless zone
        zone.entities = zone.entities.select(&:valid?)
        return if zone.entities.empty?
        rebuilt = MH::FastRename.create_zone(zone.id, zone.entities)
        zone.bounds = rebuilt.bounds
      end

      private
      unless defined?(VK_UP)
        VK_UP=0x26; VK_DOWN=0x28
      end
      unless defined?(ALT_MODIFIER_MASK)
        ALT_MODIFIER_MASK = 0x20
      end
      unless defined?(COPY_MODIFIER_MASK)
        COPY_MODIFIER_MASK = 0x08
      end
      unless defined?(SHIFT_MODIFIER_MASK)
        SHIFT_MODIFIER_MASK = 0x04
      end

      def alt_down?(flags)
        @alt_down_latched || ((flags & ALT_MODIFIER_MASK) == ALT_MODIFIER_MASK)
      end

      def copy_down?(flags)
        (flags & COPY_MODIFIER_MASK) == COPY_MODIFIER_MASK
      end

      def shift_down?(flags)
        (flags & SHIFT_MODIFIER_MASK) == SHIFT_MODIFIER_MASK
      end
    end

    # ════════════════════════════════════════════════════════════════
    # ENTRY POINTS
    # ════════════════════════════════════════════════════════════════
    def self.activate_tool
      Sketchup.active_model.select_tool(FastRenameTool.new)
    end

    def self.activate_sp_prefix_tool
      Sketchup.active_model.select_tool(FastRenameTool.new(:sp_prefix))
    end

    def self.reload
      load __FILE__
      dbg('MH::FastRename reloaded')
    end

    unless defined?(@loaded)
      @loaded = true
      toolbar = UI::Toolbar.new('MH Fast Rename')
      icons_dir = File.join(__dir__, 'icons')
      cmd = UI::Command.new('Fast Rename') { MH::FastRename.activate_tool }
      cmd.tooltip = 'MH Fast Rename - Zone-based rename tool'
      icon = File.join(icons_dir, 'fast_rename.svg')
      if File.exist?(icon)
        cmd.small_icon = icon
        cmd.large_icon = icon
      end
      cmd_sp = UI::Command.new('Chia theo SP') { MH::FastRename.activate_sp_prefix_tool }
      cmd_sp.tooltip = 'MH Fast Rename - Chia khối theo mã SP gốc'
      icon_sp = File.join(icons_dir, 'split_by_sp.svg')
      if File.exist?(icon_sp)
        cmd_sp.small_icon = icon_sp
        cmd_sp.large_icon = icon_sp
      end
      toolbar.add_item(cmd)
      toolbar.add_item(cmd_sp)
      toolbar.restore
    end

  end
end


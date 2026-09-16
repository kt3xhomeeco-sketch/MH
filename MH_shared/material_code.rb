# encoding: UTF-8
#
# Data-driven material-code parser shared by MH_* apps.
# Rules live in MH::Registry.material_code_rules / global_registry.json.

module MH
  module MaterialCode
    DEFAULT_RULES = {
      'segment_separator' => '.',
      'multi_separators' => ['&'],
      'uppercase' => true,
      'trim_segments' => true,
      'gloss_suffix_regex' => '-(\d+)\z',
      'single_segment_gloss_is_finish' => true,
      'paint_surface_token' => 'SON',
      'paint_code_regex' => '\A(?=.*[A-Z])(?=.*\d)[A-Z0-9][A-Z0-9 _\/.\-]*\z',
      'surface_variant_regex' => '\.(?:1M|2M|1M-BCT|2M-BCT)\z',
      'surface_groups' => {
        'SON' => {
          'label' => 'Sơn',
          'members' => ['SON'],
          'tail_label' => 'mã sơn - độ bóng',
          'finish_kind' => 'paint_code',
          'finish_required' => true,
          'allow_gloss' => true,
          'allow_surface_variant' => false,
          'finish_pattern' => '\A(?=.*[A-Z])(?=.*\d)[A-Z0-9][A-Z0-9 _\/.\-]*\z'
        },
        'LK' => {
          'label' => 'Laminate',
          'members' => ['LK'],
          'tail_label' => 'mã vật liệu .1M/.2M',
          'finish_kind' => 'material_code',
          'finish_required' => false,
          'allow_gloss' => false,
          'allow_surface_variant' => true
        },
        'VER' => {
          'label' => 'Veneer',
          'members' => ['VER', 'VERKT', 'VERSOI', 'VERKTSOI'],
          'tail_label' => 'mã sơn .1M/.2M',
          'finish_kind' => 'paint_code',
          'finish_required' => false,
          'allow_gloss' => false,
          'allow_surface_variant' => true,
          'finish_pattern' => '\A(?=.*[A-Z])(?=.*\d)[A-Z0-9][A-Z0-9 _\/.\-]*\z'
        },
        'MS' => {
          'label' => 'Melamine',
          'members' => ['MS'],
          'tail_label' => 'mã vật liệu',
          'finish_kind' => 'material_code',
          'finish_required' => false,
          'allow_gloss' => false,
          'allow_surface_variant' => false
        }
      },
      'layers' => [
        { 'key' => 'chat_lieu', 'label' => 'Chất liệu', 'required' => true },
        { 'key' => 'do_day', 'label' => 'Độ dày', 'role' => 'thickness', 'optional' => true, 'omit_from_parent' => true, 'pattern' => '\A\d+(?:[,.]\d+)?\z' },
        { 'key' => 'nha_cung_cap', 'label' => 'Nhà cung cấp', 'optional' => true },
        { 'key' => 'be_mat', 'label' => 'Bề mặt', 'optional' => true },
        { 'key' => 'finish_code', 'label' => 'Mã hoàn thiện / mã sơn', 'role' => 'finish', 'optional' => true, 'capture_rest' => true }
      ]
    }.freeze

    @rules_override = nil

    module_function

    def configure(rules = nil)
      @rules_override = rules.is_a?(Hash) ? deep_merge(DEFAULT_RULES, stringify_keys(rules)) : nil
      @rules_override || rules
    end

    def rules
      return @rules_snapshot if @rules_snapshot
      return @rules_override if @rules_override

      base = if defined?(MH::Registry) && MH::Registry.respond_to?(:material_code_rules)
               MH::Registry.material_code_rules
             else
               {}
             end
      merged = deep_merge(DEFAULT_RULES, base.is_a?(Hash) ? base : {})
      if defined?(MH::Registry) && MH::Registry.respond_to?(:material_code_mappings)
        merged['mappings'] = MH::Registry.material_code_mappings
      end
      merged
    rescue
      @rules_override || DEFAULT_RULES
    end

    # Reuse one rule set during a synchronous batch; the next batch reads fresh
    # settings. Nested callers and exceptions restore the previous scope.
    def with_rules_snapshot
      previous = @rules_snapshot
      @rules_snapshot = rules unless previous
      yield
    ensure
      @rules_snapshot = previous
    end

    def split(value)
      text = value.to_s.strip
      return [] if text.empty?

      seps = Array(rules['multi_separators']).map(&:to_s).reject(&:empty?)
      return [normalize_text(text)] if seps.empty?

      regex = Regexp.union(seps)
      text.split(regex).map { |part| normalize_text(part) }.reject(&:empty?)
    end

    def parse(value)
      raw = value.to_s.strip
      normalized = normalize_text(raw)
      result = base_result(raw, normalized)
      return result if normalized.empty?

      sep = rules['segment_separator'].to_s
      sep = '.' if sep.empty?
      segments = normalized.split(sep).map { |part| normalize_segment(part) }.reject(&:empty?)
      segments = expand_implicit_paint_surface(segments)
      result[:segments] = segments

      if single_segment_finish?(segments)
        assign_finish!(result, segments.first)
        classify_surface!(result)
        validate_surface_group!(result)
        finalize_parent!(result)
        return result
      end

      consume_layers!(result, segments, sep)
      classify_surface!(result)
      validate_surface_group!(result)
      finalize_parent!(result)
      result
    rescue => e
      base_result(value, value).merge(error: "#{e.class}: #{e.message}")
    end

    def normalize(value)
      parse(value)[:vl_parent].to_s
    end

    def canonical(value)
      compose_code(parse(value), include_thickness: true, include_finish: true)
    end

    def without_finish(value)
      compose_code(parse(value), include_thickness: true, include_finish: false)
    end

    def without_thickness(value)
      normalize(value)
    end

    def with_thickness(value, thickness)
      parsed = parse(value)
      return '' if parsed[:normalized].to_s.empty?

      sep = rules['segment_separator'].to_s
      sep = '.' if sep.empty?
      thickness_text = normalize_segment(thickness)
      parts = []
      inserted = false
      pending_thickness = false

      Array(rules['layers']).each do |layer|
        layer = stringify_keys(layer)
        key = layer['key'].to_s
        next if key.empty?

        if layer['role'].to_s == 'thickness'
          unless thickness_text.empty?
            if parts.empty?
              pending_thickness = true
            else
              parts << thickness_text
              inserted = true
            end
          end
          next
        end

        value_for_layer = parsed[:layers][key].to_s
        next if value_for_layer.empty?

        parts << value_for_layer
        if pending_thickness && !inserted
          parts << thickness_text
          inserted = true
        end
      end

      unless inserted || thickness_text.empty?
        parts.length > 1 ? parts.insert(1, thickness_text) : parts << thickness_text
      end

      parts.join(sep)
    end

    # ------------------------------------------------------------------------
    # Public material-name helpers.  These methods are deliberately kept in
    # MH_shared so every MH_* app resolves the same Excel code in the same way.

    def map_thickness(actual_thickness, mappings: nil, fallback_to_actual: false)
      actual = actual_thickness.to_s.strip.tr(',', '.').to_f
      mappings = default_thickness_mappings if mappings.nil?

      Array(mappings).each do |mapping|
        row = stringify_keys(mapping || {})
        min = row['min'].to_s.strip.tr(',', '.').to_f
        max = row['max'].to_s.strip.tr(',', '.').to_f
        value = row['value'].to_s.strip
        next if value.empty?

        return normalize_thickness_token(value) if actual >= min && actual <= max
      end

      fallback_to_actual ? normalize_thickness_token(actual) : nil
    rescue
      fallback_to_actual ? normalize_thickness_token(actual_thickness) : nil
    end

    # Builds the SketchUp material name from the logical Excel code and the
    # measured OBJ thickness.  MH_xxx is a tag/material shortcut, not a
    # structured material code.
    def material_name(value, actual_thickness, mappings: nil, fallback_to_actual: false)
      logical_code = without_thickness(value)
      return nil if logical_code.empty?
      return logical_code.sub(/\AMH_/i, '') if logical_code =~ /\AMH_/i

      thickness = map_thickness(actual_thickness, mappings: mappings, fallback_to_actual: fallback_to_actual)
      return nil if thickness.to_s.empty?

      with_thickness(logical_code, thickness)
    end

    # Returns the material family without its thickness token and optional
    # face suffix.  The group is config-driven, so VER/VERKT/VERSOI/VERKTSOI
    # all resolve to the Registry's Veneer group.
    def family_parts(value)
      strip_surface_variant(without_thickness(value)).split(segment_separator).reject(&:empty?)
    end

    def finish_group(value)
      parsed = parse(value)
      surface_group_for_token(parsed[:layers]['be_mat']).to_s
    end

    def surface_variant?(value)
      !surface_variant_from_finish(value).to_s.empty?
    end

    def strip_surface_variant(value)
      finish_base_without_surface_variant(value)
    end

    # Parent candidates are ordered nearest parent first. Declared
    # parent_codes from Registry are used as priority entries.
    def parent_candidates(value)
      code = strip_surface_variant(without_thickness(value))
      return [] if code.empty? || code =~ /\AMH_/i

      parts = code.split(segment_separator).reject(&:empty?)
      return [] if parts.length <= 2

      candidates = parent_prefixes(parts)
      parsed = parse(code)
      surface_token = parsed[:layers]['be_mat'].to_s
      group = finish_group(code)
      if !surface_token.empty? && !group.empty? && comparable_text(surface_token) != comparable_text(group)
        grouped_parts = parts.map { |part| comparable_text(part) == comparable_text(surface_token) ? group : part }
        candidates.concat(parent_prefixes(grouped_parts))
      end
      candidates.uniq!
      configured = configured_parent_codes
      return candidates if configured.empty?

      preferred, remaining = candidates.partition { |candidate| configured.include?(candidate) }
      preferred + remaining
    end

    def display(value)
      normalize(value)
    end

    def same?(left, right)
      normalize(left) == normalize(right)
    end

    def color_code(value)
      parse(value)[:color_code].to_s
    end

    def gloss(value)
      parse(value)[:do_bong].to_s
    end

    def segment_separator
      separator = rules['segment_separator'].to_s
      separator.empty? ? '.' : separator
    end

    def configured_parent_codes
      Array(rules['parent_codes']).map { |code| without_thickness(code) }.reject(&:empty?).uniq
    rescue
      []
    end

    def parent_prefixes(parts)
      (parts.length - 1).downto(2).map { |length| parts.first(length).join(segment_separator) }
    end

    def compose_code(parsed, include_thickness: true, include_finish: true)
      parsed = parse(parsed) unless parsed.is_a?(Hash)
      return '' if parsed[:normalized].to_s.empty?

      sep = rules['segment_separator'].to_s
      sep = '.' if sep.empty?
      parts = []
      Array(rules['layers']).each do |layer|
        layer = stringify_keys(layer)
        key = layer['key'].to_s
        next if key.empty?
        next if layer['role'].to_s == 'thickness' && !include_thickness
        next if (layer['role'].to_s == 'finish' || key == 'finish_code') && !include_finish

        value = parsed[:layers][key].to_s
        parts << value unless value.empty?
      end
      parts.join(sep)
    end

    def base_result(raw, normalized)
      {
        raw: raw.to_s,
        normalized: normalized.to_s,
        segments: [],
        layers: {},
        vl_parent: '',
        finish_code: '',
        finish_base: '',
        surface_group: '',
        surface_variant: '',
        color_code: '',
        do_bong: '',
        valid: true,
        validation_errors: [],
        validation_warnings: [],
        error: nil
      }
    end

    def consume_layers!(result, segments, sep)
      idx = 0
      Array(rules['layers']).each do |layer|
        layer = stringify_keys(layer)
        key = layer['key'].to_s
        next if key.empty?

        if truthy?(layer['capture_rest'])
          value = segments[idx..-1].to_a.join(sep)
          assign_layer!(result, layer, value) unless value.empty?
          idx = segments.length
          break
        end

        current = segments[idx].to_s
        if layer['role'].to_s == 'thickness'
          if matches_layer?(current, layer)
            assign_layer!(result, layer, current)
            idx += 1
          elsif !truthy?(layer['optional'])
            assign_layer!(result, layer, '')
          end
          next
        end

        if !current.empty? && matches_layer?(current, layer)
          assign_layer!(result, layer, current)
          idx += 1
        elsif !truthy?(layer['optional'])
          assign_layer!(result, layer, '')
        end
      end
    end

    def classify_surface!(result)
      group = surface_group_for_token(result[:layers]['be_mat'])
      result[:surface_group] = group.to_s
      result[:surface_variant] = surface_variant_from_finish(result[:finish_code])
      result[:finish_base] = finish_base_without_surface_variant(result[:finish_code])
      result
    end

    def validate_surface_group!(result)
      errors = result[:validation_errors] ||= []
      warnings = result[:validation_warnings] ||= []
      be_mat = result[:layers]['be_mat'].to_s
      group = result[:surface_group].to_s
      finish = result[:finish_code].to_s
      finish_base = result[:finish_base].to_s

      if be_mat.empty?
        warnings << 'Thiếu be_mat: không phân loại được nhóm SON/LK/VER/MS.'
        result[:valid] = errors.empty?
        return result
      end

      if group.empty?
        errors << "be_mat \"#{be_mat}\" chưa thuộc nhóm SON/LK/VER/MS."
        result[:valid] = false
        return result
      end

      rule = surface_group_rule(group)
      errors << "Nhóm #{group}: thiếu finish_code." if truthy?(rule['finish_required']) && finish.empty?

      unless truthy?(rule['allow_surface_variant'])
        errors << "Nhóm #{group}: không dùng hậu tố phủ mặt 1M/2M." unless result[:surface_variant].to_s.empty?
      end

      unless truthy?(rule['allow_gloss'])
        errors << "Nhóm #{group}: không dùng độ bóng dạng -30." unless result[:do_bong].to_s.empty?
      end

      pattern = rule['finish_pattern'].to_s
      if !pattern.empty? && !finish_base.empty? && !(finish_base =~ Regexp.new(pattern))
        errors << "Nhóm #{group}: finish_code không đúng mẫu."
      end

      result[:valid] = errors.empty?
      result
    rescue => e
      (result[:validation_warnings] ||= []) << "Không kiểm tra được nhóm bề mặt: #{e.message}"
      result[:valid] = result[:validation_errors].to_a.empty?
      result
    end

    def surface_group_rules
      value = rules['surface_groups']
      return {} unless value.is_a?(Hash)

      stringify_keys(value)
    end

    def surface_group_rule(group)
      surface_group_rules[group.to_s] || {}
    end

    def surface_group_for_token(value)
      token = comparable_text(value)
      return '' if token.empty?

      surface_group_rules.each do |group, rule|
        members = Array(rule['members']).map { |member| comparable_text(member) }
        return group.to_s if members.include?(token)
      end
      ''
    end

    def surface_variant_from_finish(value)
      finish = value.to_s
      pattern = rules['surface_variant_regex'].to_s
      return '' if finish.empty? || pattern.empty?

      match = finish.match(Regexp.new(pattern))
      match ? match[0].to_s.sub(/\A\./, '') : ''
    rescue
      ''
    end

    def finish_base_without_surface_variant(value)
      finish = value.to_s
      pattern = rules['surface_variant_regex'].to_s
      return finish if finish.empty? || pattern.empty?

      finish.sub(Regexp.new(pattern), '')
    rescue
      finish
    end

    def default_thickness_mappings
      return MH::Registry.thickness_mappings if defined?(MH::Registry) && MH::Registry.respond_to?(:thickness_mappings)

      Array(rules['thickness_mappings'])
    rescue
      []
    end

    def normalize_thickness_token(value)
      text = value.to_s.strip.tr(',', '.')
      return '' if text.empty?

      number = text.to_f
      (number - number.round).abs < 0.0001 ? number.round.to_s : number.to_s
    rescue
      value.to_s.strip
    end

    def expand_implicit_paint_surface(segments)
      parts = Array(segments).map(&:to_s)
      return parts if parts.empty?

      token = normalize_segment(rules['paint_surface_token'].to_s)
      return parts if token.empty? || parts.include?(token)

      index = parts.find_index { |part| paint_code?(part) }
      return parts unless index && index >= 2

      previous = parts[index - 1].to_s
      return parts if surface_token?(previous)

      parts.dup.insert(index, token)
    end

    def paint_code?(value)
      text = normalize_segment(value)
      return false if text.empty?

      pattern = rules['paint_code_regex'].to_s
      return false if pattern.empty?

      !!(text =~ Regexp.new(pattern))
    rescue
      false
    end

    def surface_token?(value)
      token = comparable_text(value)
      return false if token.empty?

      # A configured group member (MS/LK/VERSOI...) is already an explicit
      # surface token.  Do not infer and insert SON before its finish code.
      !surface_group_for_token(value).to_s.empty? || mapped_values_for_layer('be_mat').include?(token)
    end

    def mapped_values_for_layer(layer_key)
      key = comparable_text(layer_key)
      values = []
      Array(rules['mappings']).each do |row|
        row = stringify_keys(row)
        group = (row['nhom'] || row['layer'] || row['key'] || row['group']).to_s
        next unless comparable_text(group) == key

        values << comparable_text(row['gia_tri'])
        values << comparable_text(row['gia_tri_map'])
        values << comparable_text(row['mapped'])
        values << comparable_text(row['canonical'])
        values << comparable_text(row['map'])
      end
      values << comparable_text(rules['paint_surface_token'])
      values.reject(&:empty?).uniq
    rescue
      []
    end

    def assign_layer!(result, layer, value)
      key = layer['key'].to_s
      val = map_layer_value(layer, normalize_segment(value))
      result[:layers][key] = val

      if layer['role'].to_s == 'finish' || key == 'finish_code'
        assign_finish!(result, val)
      elsif key == 'do_bong'
        result[:do_bong] = val
      end
    end

    def assign_finish!(result, value)
      finish = normalize_segment(value)
      result[:finish_code] = finish
      result[:layers]['finish_code'] = finish

      gloss_regex = Regexp.new(rules['gloss_suffix_regex'].to_s)
      if finish =~ gloss_regex
        result[:do_bong] = Regexp.last_match(1).to_s
        result[:color_code] = finish.sub(gloss_regex, '').strip
      else
        result[:color_code] = finish
      end
    rescue
      result[:color_code] = finish
    end

    def finalize_parent!(result)
      sep = rules['segment_separator'].to_s
      sep = '.' if sep.empty?

      parent_parts = []
      Array(rules['layers']).each do |layer|
        layer = stringify_keys(layer)
        key = layer['key'].to_s
        next if key.empty? || truthy?(layer['omit_from_parent'])

        value = result[:layers][key].to_s
        parent_parts << value unless value.empty?
      end

      if parent_parts.empty? && !result[:finish_code].to_s.empty?
        parent_parts << result[:finish_code].to_s
      end

      result[:vl_parent] = parent_parts.join(sep)
      result
    end

    def single_segment_finish?(segments)
      return false unless truthy?(rules['single_segment_gloss_is_finish'])
      return false unless segments.length == 1

      regex = Regexp.new(rules['gloss_suffix_regex'].to_s)
      !!(segments.first.to_s =~ regex)
    rescue
      false
    end

    def map_layer_value(layer, value)
      val = value.to_s
      key = layer['key'].to_s
      return val if key.empty? || val.empty?

      Array(rules['mappings']).each do |row|
        row = stringify_keys(row)
        group = (row['nhom'] || row['layer'] || row['key'] || row['group']).to_s
        next unless comparable_text(group) == comparable_text(key)

        source = (row['gia_tri'] || row['value'] || row['raw']).to_s
        mapped = (row['gia_tri_map'] || row['mapped'] || row['canonical'] || row['map']).to_s
        next if mapped.empty?

        val_key = comparable_text(val)
        if val_key == comparable_text(source) || val_key == comparable_text(mapped)
          return normalize_segment(mapped)
        end
      end
      val
    rescue
      value.to_s
    end

    def matches_layer?(value, layer)
      pattern = layer['pattern'].to_s
      return true if pattern.empty?

      !!(value.to_s =~ Regexp.new(pattern))
    rescue
      false
    end

    def normalize_text(value)
      text = value.to_s.strip
      text = text.upcase if truthy?(rules['uppercase'])
      text
    end

    def normalize_segment(value)
      text = value.to_s
      text = text.strip if truthy?(rules['trim_segments'])
      text = text.upcase if truthy?(rules['uppercase'])
      text
    end

    def comparable_text(value)
      value.to_s.strip.upcase.gsub(/\s+/, '')
    end

    def truthy?(value)
      value == true || value.to_s.downcase == 'true' || value.to_s == '1'
    end

    def stringify_keys(value)
      return value unless value.is_a?(Hash)
      value.each_with_object({}) { |(k, v), h| h[k.to_s] = v.is_a?(Hash) ? stringify_keys(v) : v }
    end

    def deep_merge(left, right)
      a = stringify_keys(left || {})
      b = stringify_keys(right || {})
      a.merge(b) do |_key, old_val, new_val|
        old_val.is_a?(Hash) && new_val.is_a?(Hash) ? deep_merge(old_val, new_val) : new_val
      end
    end
  end
end

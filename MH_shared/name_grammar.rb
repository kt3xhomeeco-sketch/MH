# encoding: UTF-8

module MH
  module NameGrammar
    DEFAULT_PREFIX = 'SP'.freeze
    DEFAULT_SEPARATORS = {
      'sep_sub_prefix' => '-',
      'sep_prefix' => '_',
      'sep_suffix' => '_',
      'default_prefix' => DEFAULT_PREFIX
    }.freeze

    @grammar = nil
    @regex_cache = {}

    module_function

    def configure(config = nil)
      @last_config = config || {}
      @grammar = build_grammar(@last_config)
      @regex_cache = {}
      MH::ProductContext.refresh_grammar if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:refresh_grammar)
      @grammar
    rescue => e
      puts "[MH::NameGrammar] configure error: #{e.class}: #{e.message}"
      @grammar ||= build_grammar({})
    end

    def grammar
      @grammar ||= build_grammar({})
    end

    def last_config
      @last_config || {}
    end

    def prefixes(active: false)
      key = active ? :active_prefixes : :all_prefixes
      grammar[key].dup
    end

    def product_families(active: false)
      key = active ? :active_product_family_order : :all_product_family_order
      Array(grammar[key]).dup
    end

    def sub_prefixes(active: false)
      key = active ? :active_sub_prefixes : :all_sub_prefixes
      grammar[key].dup
    end

    def modules(active: false)
      key = active ? :active_modules : :all_modules
      grammar[key].dup
    end

    def separators
      grammar[:separators].dup
    end

    def module_separator
      value = grammar[:separators]['sep_prefix'].to_s
      value.empty? ? '.' : value
    end

    def part_separator
      value = grammar[:separators]['sep_suffix'].to_s
      value.empty? ? '_' : value
    end

    def default_prefix
      grammar[:default_prefix].to_s.empty? ? DEFAULT_PREFIX : grammar[:default_prefix].to_s
    end

    def parse(raw)
      source = raw.to_s
      stripped = source.strip
      result = base_result(source)
      return result.merge(unmatched_reason: 'empty_name') if stripped.empty?

      sys = extract_sys_id(stripped)
      result[:sys_id] = sys[:id]
      result[:numbered] = !sys[:id].nil?
      result[:body] = sys[:body]

      split = split_part(sys[:body])
      head = split[:head].strip
      result[:part] = split[:part].to_s.strip
      apply_suffix!(result)

      parsed = parse_head(head)
      result.merge!(parsed)
      return result unless parsed[:recognized]

      result[:product] = parsed[:product].to_s.empty? ? "#{result[:prefix]}#{result[:product_no_raw]}" : parsed[:product]
      result[:modul_label] = module_label(result[:module_raw])
      result[:module_no] = result[:module_raw].to_s.empty? ? nil : result[:modul_label]
      result[:module_code] = build_code(product: result[:product], module_raw: result[:module_raw], pad_numeric: true)
      result[:full_module_code] = result[:module_code]
      result[:unmatched_reason] = nil
      result
    rescue => e
      base_result(raw).merge(unmatched_reason: "#{e.class}: #{e.message}")
    end

    def product_of(raw)
      parsed = parse(raw)
      parsed[:recognized] ? parsed[:product].to_s.upcase : ''
    end

    def module_of(raw)
      parsed = parse(raw)
      parsed[:recognized] ? parsed[:module_code].to_s.upcase : ''
    end

    def valid_product?(code)
      !!(code.to_s.strip =~ strict_regex)
    end

    def strip_to_part(raw)
      parse(raw)[:part].to_s
    end

    def build_code(product:, module_raw: nil, pad_numeric: false)
      base = product.to_s.strip
      raw_mod = module_raw.to_s.strip
      mod = pad_numeric ? module_label(raw_mod) : raw_mod
      return base if base.empty? || raw_mod.empty?

      "#{base}#{module_separator}#{mod}"
    end

    def build_name(product:, part: nil, module_raw: nil, sub_prefix: nil, suffix: nil, sys_id: nil)
      code = build_code(product: product, module_raw: module_raw, pad_numeric: false)
      return '' if code.empty?

      sub = sub_prefix.to_s.strip
      code = "#{sub}#{grammar[:separators]['sep_sub_prefix']}#{code}" unless sub.empty?

      name = code
      clean_part = part.to_s.strip
      name += "#{part_separator}#{clean_part}" unless clean_part.empty?

      clean_suffix = suffix.to_s.strip
      name += "#{part_separator}#{clean_suffix}" unless clean_suffix.empty?

      id = sys_id.to_s.strip
      id.empty? ? name : "__#{id}. #{name}"
    end

    def scan_products(text)
      text.to_s.scan(capture_regex).flatten.map { |code| code.to_s.upcase }.uniq
    rescue
      []
    end

    def first_product(text)
      scan_products(text).first
    end

    def capture_regex
      @regex_cache[:capture] ||= begin
        /((?:#{product_capture_pattern})(?:#{module_segment_pattern})?)/i
      end
    end

    def scan_regex
      @regex_cache[:scan] ||= begin
        /(?:#{product_capture_pattern})(?:#{module_segment_pattern})?/i
      end
    end

    def strict_regex
      @regex_cache[:strict] ||= begin
        /\A(?:#{product_capture_pattern})(?:#{module_segment_pattern})?\z/i
      end
    end

    def product_capture_pattern
      product = product_code_pattern
      return product if product_code_rules_active?

      prefix = prefix_pattern
      "(?:(?:#{product})|(?:#{prefix})\\d+[A-Za-z]?)"
    end

    def module_segment_pattern
      parts = ['\.[A-Za-z0-9]+']
      sep = module_separator
      parts << "#{Regexp.escape(sep)}\\d+" unless sep.to_s.empty? || sep == '.'
      "(?:#{parts.join('|')})"
    end

    def product_code_rules_active?
      return true if grammar[:product_rules_active]
      !Array(grammar[:active_product_codes]).empty? ||
        !Array(grammar[:all_product_codes]).empty? ||
        !Array(grammar[:active_product_families]).empty? ||
        !Array(grammar[:all_product_families]).empty?
    end

    def build_grammar(config)
      seps = DEFAULT_SEPARATORS.merge(hash_at(config, 'separators'))
      default = seps['default_prefix'].to_s.strip
      default = DEFAULT_PREFIX if default.empty?

      active_prefixes = clean_list(config['prefix'] || config[:prefix])
      all_prefixes = clean_list(config['all_prefix'] || config[:all_prefix])
      rule_product_codes = product_code_rule_values(config)
      rule_product_families = product_code_rule_family_values(config)
      rule_product_family_order = clean_list(rule_product_families)
      rules_active = !rule_product_codes.empty? || !rule_product_families.empty?
      if rules_active
        active_product_codes = clean_list(rule_product_codes)
        all_product_codes = clean_list(rule_product_codes)
        active_prefixes = clean_list(rule_product_families)
        active_prefixes = [default] if active_prefixes.empty?
        all_prefixes = clean_list(active_prefixes)
      else
        active_product_codes = clean_list(product_code_values(active_prefixes))
        all_product_codes = clean_list(active_product_codes + product_code_values(all_prefixes))
        active_prefixes = clean_list(prefix_family_values(active_prefixes) + non_product_prefix_values(active_prefixes))
        all_prefixes = clean_list(prefix_family_values(all_prefixes) + non_product_prefix_values(all_prefixes))
        active_prefixes = [default] if active_prefixes.empty?
        all_prefixes = clean_list(active_prefixes + all_prefixes + [default])
      end

      active_sub = clean_list(config['sub_prefix'] || config[:sub_prefix])
      all_sub = clean_list(active_sub + clean_list(config['all_sub_prefix'] || config[:all_sub_prefix]))

      active_modules = clean_list(config['modul'] || config[:modul])
      all_modules = clean_list(active_modules + clean_list(config['all_modul'] || config[:all_modul]))

      suffixes = Array(config['suffix'] || config[:suffix]).map do |item|
        item.is_a?(Hash) ? (item['value'] || item[:value]).to_s.strip : item.to_s.strip
      end
      suffixes += product_code_rule_suffix_values(config)

      {
        separators: seps,
        default_prefix: default,
        active_prefixes: sort_longest(active_prefixes),
        all_prefixes: sort_longest(all_prefixes),
        active_product_codes: sort_longest(active_product_codes),
        all_product_codes: sort_longest(all_product_codes),
        active_product_families: sort_longest(rule_product_families),
        all_product_families: sort_longest(rule_product_families),
        active_product_family_order: rule_product_family_order,
        all_product_family_order: rule_product_family_order,
        product_rules_active: rules_active,
        active_sub_prefixes: sort_longest(active_sub),
        all_sub_prefixes: sort_longest(all_sub),
        active_modules: sort_longest(active_modules),
        all_modules: sort_longest(all_modules),
        suffixes: sort_longest(clean_list(suffixes))
      }
    end

    def base_result(raw)
      {
        raw: raw.to_s,
        body: raw.to_s.strip,
        sys_id: nil,
        numbered: false,
        sub_prefix: nil,
        sub_prefix_declared: false,
        prefix: nil,
        product_no: nil,
        product_no_raw: nil,
        product: nil,
        module_raw: nil,
        module_no: nil,
        module_kind: nil,
        module_code: nil,
        full_module_code: nil,
        modul: 0,
        modul_label: '00',
        part: '',
        suffix: nil,
        recognized: false,
        unmatched_reason: 'unknown_prefix'
      }
    end

    def extract_sys_id(text)
      match = text.match(/\A\s*_*(\d+)\s*\.\s*(.+)\z/)
      return { id: nil, body: text } unless match

      { id: match[1].to_i, body: match[2].to_s }
    end

    def split_part(text)
      sep = grammar[:separators]['sep_suffix'].to_s
      sep = DEFAULT_SEPARATORS['sep_suffix'] if sep.empty?
      idx = text.index(sep)

      if idx && module_separator == sep
        after = text[(idx + sep.length)..-1].to_s
        second = after.index(sep)
        candidate_base = text[0...idx].to_s
        module_token = second ? after[0...second].to_s : after
        if looks_like_product_head?(candidate_base) && module_token?(module_token)
          if second
            head_end = idx + sep.length + second
            return { head: text[0...head_end].to_s, part: after[(second + sep.length)..-1].to_s }
          end
          return { head: text, part: '' }
        end
      end
      return { head: text, part: '' } unless idx

      { head: text[0...idx].to_s, part: text[(idx + sep.length)..-1].to_s }
    end

    def parse_head(head)
      product_head = head.to_s.strip
      sub_prefix = nil
      sub_declared = false
      sep = grammar[:separators]['sep_sub_prefix'].to_s

      if !sep.empty? && product_head.include?(sep)
        before, after = product_head.split(sep, 2)
        candidate = before.to_s.strip
        if declared?(candidate, :all_sub_prefixes) || looks_like_product_head?(after)
          sub_prefix = candidate.empty? ? nil : candidate
          sub_declared = declared?(candidate, :all_sub_prefixes)
          product_head = after.to_s.strip
        end
      end

      parsed = parse_product_segment(product_head)
      parsed[:sub_prefix] = sub_prefix
      parsed[:sub_prefix_declared] = sub_declared
      parsed
    end

    def parse_product_segment(segment)
      value = segment.to_s.strip
      product_match = match_product_code(value)
      if product_match
        tail = value[product_match.length..-1].to_s
        module_raw = module_from_tail(tail)
        parts = product_match.match(/\A([A-Za-z]+)(\d+[A-Za-z]?)\z/)
        return {
          recognized: true,
          prefix: parts ? parts[1].upcase : product_match.upcase,
          product_no_raw: parts ? parts[2] : '',
          product_no: parts ? parts[2].to_i : nil,
          sp_no: parts ? parts[2].to_i : nil,
          product: product_match.upcase,
          product_code: product_match.upcase,
          module_raw: module_raw.to_s.empty? ? nil : module_raw,
          module_kind: module_kind(module_raw),
          has_modul: !module_raw.to_s.empty?,
          modul: numeric_module_value(module_raw)
        }
      end

      return generic_unrecognized(value) if product_code_rules_active?

      match = match_prefix(value)
      return generic_unrecognized(value) unless match

      rest = value[match.length..-1].to_s
      no_match = rest.match(/\A(\d+[A-Za-z]?)(.*)\z/)
      return generic_unrecognized(value) unless no_match

      product_no_raw = no_match[1].to_s
      tail = no_match[2].to_s
      module_raw = module_from_tail(tail)

      {
        recognized: true,
        prefix: match.upcase,
        product_no_raw: product_no_raw,
        product_no: product_no_raw.to_i,
        sp_no: product_no_raw.to_i,
        product: "#{match}#{product_no_raw}".upcase,
        product_code: "#{match}#{product_no_raw}".upcase,
        module_raw: module_raw.to_s.empty? ? nil : module_raw,
        module_kind: module_kind(module_raw),
        has_modul: !module_raw.to_s.empty?,
        modul: numeric_module_value(module_raw)
      }
    end

    def generic_unrecognized(value)
      m = value.to_s.match(/\A([A-Za-z]+)(\d+[A-Za-z]?)(?:\.([A-Za-z0-9]+))?/)
      return { recognized: false, unmatched_reason: 'unknown_prefix' } unless m

      {
        recognized: false,
        unmatched_reason: 'unknown_prefix',
        prefix: m[1].upcase,
        product_no_raw: m[2],
        product_no: m[2].to_i,
        sp_no: m[2].to_i,
        module_raw: m[3],
        module_kind: module_kind(m[3]),
        has_modul: !m[3].to_s.empty?,
        modul: numeric_module_value(m[3])
      }
    end

    def apply_suffix!(result)
      part = result[:part].to_s
      sep = grammar[:separators]['sep_suffix'].to_s
      sep = DEFAULT_SEPARATORS['sep_suffix'] if sep.empty?
      grammar[:suffixes].each do |suffix|
        token = "#{sep}#{suffix}"
        next unless part.downcase.end_with?(token.downcase)

        result[:suffix] = suffix
        result[:part] = part[0...(part.length - token.length)].to_s.strip
        return
      end
    end

    def match_prefix(value)
      (grammar[:active_prefixes] + grammar[:all_prefixes]).uniq.each do |prefix|
        next unless value.length >= prefix.length
        return value[0, prefix.length] if value[0, prefix.length].downcase == prefix.downcase
      end
      nil
    end

    def match_product_code(value)
      (grammar[:active_product_codes] + grammar[:all_product_codes]).uniq.each do |code|
        next unless value.length >= code.length
        next unless value[0, code.length].downcase == code.downcase
        tail = value[code.length..-1].to_s
        return value[0, code.length] if tail.empty? || tail.start_with?('.') || tail =~ /\A[\s#{Regexp.escape(part_separator)}]/
      end
      (grammar[:active_product_families] + grammar[:all_product_families]).uniq.each do |family|
        match = value.match(/\A(#{Regexp.escape(family)}\d+[A-Za-z]?)(.*)\z/i)
        next unless match
        tail = match[2].to_s
        return match[1] if tail.empty? || tail.start_with?('.') || tail =~ /\A[\s#{Regexp.escape(part_separator)}]/
      end
      nil
    end

    def module_from_tail(tail)
      text = tail.to_s
      separators = ['.']
      sep = module_separator
      separators << sep unless sep.to_s.empty? || sep == '.'

      selected = separators.find { |item| text.start_with?(item) }
      return nil unless selected

      token = text[selected.length..-1].to_s.strip.split(/[#{Regexp.escape(selected)}\s]+/, 2).first.to_s
      return token if selected == '.'
      return token if token.match?(/\A\d+\z/)
      return token if declared?(token, :all_modules)

      nil
    end

    def module_token?(value)
      token = value.to_s.strip
      return false if token.empty?
      return true if token.match?(/\A\d+\z/)
      declared?(token, :all_modules)
    end

    def looks_like_product_head?(value)
      !!match_prefix(value.to_s.strip)
    end

    def declared?(value, key)
      needle = value.to_s.downcase
      return false if needle.empty?
      grammar[key].any? { |item| item.to_s.downcase == needle }
    end

    def module_kind(value)
      text = value.to_s
      return nil if text.empty?
      return :numeric if text =~ /\A\d+\z/
      return :alnum if text =~ /\A[A-Za-z0-9]+\z/
      :named
    end

    def numeric_module_value(value)
      value.to_s =~ /\A\d+\z/ ? value.to_i : 0
    end

    def module_label(value)
      return '00' if value.to_s.empty?
      value.to_s =~ /\A\d+\z/ ? format('%02d', value.to_i) : value.to_s
    end

    def prefix_pattern
      items = prefixes(active: false)
      items = [default_prefix] if items.empty?
      sort_longest(items).map { |prefix| Regexp.escape(prefix) }.join('|')
    end

    def product_code_pattern
      items = grammar[:active_product_codes] + grammar[:all_product_codes]
      items = [] if items.nil?
      fallback = "#{Regexp.escape(default_prefix)}\\d+[A-Za-z]?"
      families = grammar[:active_product_families] + grammar[:all_product_families]
      family_pattern = sort_longest(families || []).map { |family| "#{Regexp.escape(family)}\\d+[A-Za-z]?" }
      pattern = (sort_longest(items).map { |code| Regexp.escape(code) } + family_pattern).join('|')
      pattern.empty? ? fallback : pattern
    end

    def product_code_values(values)
      clean_list(values).select { |value| value =~ /\A[A-Za-z]+\d+[A-Za-z]?\z/ }
    end

    def product_code_rule_values(config = nil)
      rules = nil
      if config
        rules = config['product_code_rules'] || config[:product_code_rules]
      end
      if (!rules || rules.empty?) && defined?(MH::Registry) && MH::Registry.respond_to?(:product_code_rules)
        rules = MH::Registry.product_code_rules
      end
      layers = Array((rules || {})['layers'] || (rules || {})[:layers])
      layer = layers.find { |row| (row['key'] || row[:key]).to_s == 'product_code' }
      product_code_values(layer ? (layer['values'] || layer[:values]) : [])
    rescue
      []
    end

    def product_code_rule_family_values(config = nil)
      rules = nil
      if config
        rules = config['product_code_rules'] || config[:product_code_rules]
      end
      if (!rules || rules.empty?) && defined?(MH::Registry) && MH::Registry.respond_to?(:product_code_rules)
        rules = MH::Registry.product_code_rules
      end
      layers = Array((rules || {})['layers'] || (rules || {})[:layers])
      layer = layers.find { |row| (row['key'] || row[:key]).to_s == 'product_code' }
      product_code_family_values(layer ? (layer['values'] || layer[:values]) : [])
    rescue
      []
    end

    def product_code_rule_suffix_values(config = nil)
      rules = nil
      if config
        rules = config['product_code_rules'] || config[:product_code_rules]
      end
      if (!rules || rules.empty?) && defined?(MH::Registry) && MH::Registry.respond_to?(:product_code_rules)
        rules = MH::Registry.product_code_rules
      end
      layers = Array((rules || {})['layers'] || (rules || {})[:layers])
      layer = layers.find { |row| (row['key'] || row[:key]).to_s == 'suffix' }
      Array(layer ? (layer['values'] || layer[:values]) : []).map do |item|
        item.is_a?(Hash) ? (item['value'] || item[:value]).to_s.strip : item.to_s.strip
      end
    rescue
      []
    end

    def prefix_family_values(values)
      clean_list(values).filter_map do |value|
        match = value.match(/\A([A-Za-z]+)\d+[A-Za-z]?\z/)
        match ? match[1] : nil
      end
    end

    def product_code_family_values(values)
      clean_list(values).filter_map do |value|
        match = value.match(/\A([A-Za-z]+)(?:\d+[A-Za-z]?|\.\.\.|\*)?\z/)
        match ? match[1] : nil
      end
    end

    def non_product_prefix_values(values)
      clean_list(values).select { |value| value =~ /\A[A-Za-z]+\z/ }
    end

    def hash_at(config, key)
      value = config[key] || config[key.to_sym]
      value.is_a?(Hash) ? value : {}
    end

    def clean_list(values)
      Array(values).map { |v| v.to_s.strip }.reject(&:empty?).uniq
    end

    def sort_longest(values)
      clean_list(values).sort_by { |item| [-item.length, item.downcase] }
    end
  end
end

# encoding: UTF-8
#
# Product context nhe dung chung cho MH_*.
# Chi doc name/definition/selection khi duoc hoi, khong scan viewport lien tuc.

module MH
  module ProductContext
    remove_const(:CODE_CAPTURE) if const_defined?(:CODE_CAPTURE)
    remove_const(:CODE_SCAN) if const_defined?(:CODE_SCAN)
    remove_const(:CODE_STRICT) if const_defined?(:CODE_STRICT)
    CODE_CAPTURE = MH::NameGrammar.capture_regex
    CODE_SCAN = MH::NameGrammar.capture_regex
    CODE_STRICT = MH::NameGrammar.strict_regex

    @codes_cache_key = nil
    @codes_cache = nil
    @last_selected_code_by_model = {}
    @observed_selection_by_model = {}

    module_function

    def refresh_grammar
      remove_const(:CODE_CAPTURE) if const_defined?(:CODE_CAPTURE)
      remove_const(:CODE_SCAN) if const_defined?(:CODE_SCAN)
      remove_const(:CODE_STRICT) if const_defined?(:CODE_STRICT)
      const_set(:CODE_CAPTURE, MH::NameGrammar.capture_regex)
      const_set(:CODE_SCAN, MH::NameGrammar.capture_regex)
      const_set(:CODE_STRICT, MH::NameGrammar.strict_regex)
      @codes_cache_key = nil
      @codes_cache = nil
      true
    rescue => e
      MH::Shared.dbg("[MH::ProductContext] refresh_grammar error: #{e.class}: #{e.message}") if defined?(MH::Shared)
      false
    end

    def base(code)
      source = exact(code)
      parsed = defined?(MH::NameGrammar) ? MH::NameGrammar.parse(source) : nil
      return parsed[:product].to_s.upcase if parsed && parsed[:recognized] && !parsed[:product].to_s.empty?

      seps = ['.']
      if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:module_separator)
        sep = MH::NameGrammar.module_separator.to_s
        seps << sep unless sep.empty? || seps.include?(sep)
      end
      first_sep = seps.map { |sep| [sep, source.index(sep)] }.select { |_, idx| idx }.min_by { |_, idx| idx }
      first_sep ? source[0...first_sep[1]].to_s.upcase : source
    rescue
      code.to_s.strip.upcase.split('.').first.to_s
    end

    def active_family
      if defined?(MH::NameGrammar)
        if MH::NameGrammar.respond_to?(:product_families)
          family = Array(MH::NameGrammar.product_families(active: true)).map(&:to_s).map(&:strip).find { |v| v =~ /\A[A-Za-z]+\z/ }
          return family.upcase if family && !family.empty?
        end
        family = Array(MH::NameGrammar.prefixes(active: true)).map(&:to_s).map(&:strip).find { |v| v =~ /\A[A-Za-z]+\z/ }
        return family.upcase if family && !family.empty?
        default = MH::NameGrammar.default_prefix.to_s.strip
        return default.upcase unless default.empty?
      end
      'SP'
    rescue
      'SP'
    end

    def format_code(number, family: nil, width: 2)
      fam = family.to_s.strip
      fam = active_family if fam.empty?
      raw = number.to_s.strip
      return fam.upcase if raw.empty?

      if raw =~ /\A(\d+)([A-Za-z]?)\z/
        digits = format("%0#{width.to_i <= 0 ? 1 : width.to_i}d", $1.to_i)
        "#{fam}#{digits}#{$2}".upcase
      else
        "#{fam}#{raw}".upcase
      end
    end

    def exact(code)
      code.to_s.strip.upcase
    end

    def number(code)
      parsed = defined?(MH::NameGrammar) ? MH::NameGrammar.parse(base(code)) : nil
      return parsed[:product_no].to_i if parsed && parsed[:recognized] && parsed[:product_no]

      match = base(code).match(/\A[A-Za-z]+(\d+)/)
      match ? match[1].to_i : nil
    rescue
      nil
    end

    def with_number(code, number_value)
      source = exact(code)
      parsed = defined?(MH::NameGrammar) ? MH::NameGrammar.parse(source) : nil
      family = if parsed && parsed[:recognized] && parsed[:prefix].to_s =~ /\A[A-Za-z]+\z/
        parsed[:prefix].to_s
      else
        source[/\A([A-Za-z]+)/, 1].to_s
      end
      family = active_family if family.empty?
      suffix = source.sub(/\A#{Regexp.escape(base(source))}/i, '')
      "#{format_code(number_value, family: family)}#{suffix}".upcase
    rescue
      format_code(number_value)
    end

    def module?(code)
      source = exact(code)
      parsed = defined?(MH::NameGrammar) ? MH::NameGrammar.parse(source) : nil
      return !!parsed[:has_modul] if parsed && parsed[:recognized]

      sep = defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:module_separator) ? MH::NameGrammar.module_separator.to_s : '.'
      source.include?('.') || (!sep.empty? && source.include?(sep))
    rescue
      exact(code).include?('.')
    end

    def valid?(code)
      value = exact(code)
      !value.empty? && value != '--' && MH::NameGrammar.valid_product?(value)
    end

    def sort_key(code)
      code.to_s.split(/(\d+)/).map { |part| part =~ /\d/ ? [1, part.to_i] : [0, part.downcase] }
    end

    def match?(value, target, mode = 'product')
      v = exact(value)
      t = exact(target)
      return false if v.empty? || t.empty? || v == '--'
      return base(v) == base(t) if mode.to_s == 'product' || !module?(t)

      v == t || (!module?(v) && base(v) == base(t))
    end

    def text_for_entity(entity)
      text = entity.respond_to?(:name) ? entity.name.to_s : ''
      text += " #{entity.definition.name}" if entity.respond_to?(:definition) && entity.definition
      text
    rescue
      ''
    end

    def code_from_entity(entity)
      text = text_for_entity(entity)
      code = MH::NameGrammar.first_product(text)
      code.to_s.empty? ? nil : exact(code)
    rescue
      nil
    end

    def codes_for_entity(entity)
      MH::NameGrammar.scan_products(text_for_entity(entity)).map { |code| exact(code) }.uniq
    rescue
      []
    end

    # Parse 1 tên thành cấu trúc đầy đủ. Giữ nil cho caller cũ khi tên không nhận diện.
    # => { id:, prefix:, sp_no:, product:, modul:, modul_label:, module_code:, part:, raw: }
    def parse_full(name)
      parsed = MH::NameGrammar.parse(name)
      return nil unless parsed[:recognized]

      {
        id:           parsed[:sys_id],
        sys_id:       parsed[:sys_id],
        numbered:     parsed[:numbered],
        sub_prefix:   parsed[:sub_prefix],
        prefix:       parsed[:prefix],
        sp_no:        parsed[:sp_no],
        product_no:   parsed[:product_no],
        product:      parsed[:product],
        has_modul:    parsed[:has_modul],
        modul:        parsed[:modul],
        module_no:    parsed[:module_no],
        module_raw:   parsed[:module_raw],
        module_kind:  parsed[:module_kind],
        modul_label:  parsed[:modul_label],
        module_code:  parsed[:module_code],
        full_module_code: parsed[:full_module_code],
        part:         parsed[:part],
        suffix:       parsed[:suffix],
        recognized:   true,
        raw:          name.to_s
      }
    rescue
      nil
    end

    def selection_signature(model = Sketchup.active_model)
      model.selection.to_a.map { |entity| entity.entityID rescue nil }.compact.sort.join(',')
    rescue
      ''
    end

    def active_path_signature(model = Sketchup.active_model)
      Array(model.active_path).map { |entity| entity.entityID rescue nil }.compact.join('/')
    rescue
      ''
    end

    def codes_from_selection(model = Sketchup.active_model, allow_slow_scan: true)
      return [] unless model

      cache_key = [
        model.respond_to?(:guid) ? model.guid.to_s : model.object_id.to_s,
        allow_slow_scan ? '1' : '0',
        selection_signature(model),
        active_path_signature(model)
      ].join('::')
      return @codes_cache.dup if @codes_cache_key.to_s == cache_key && @codes_cache.is_a?(Array)

      selection = model.selection.to_a
      return cache_result(cache_key, []) if selection.empty?

      products = []
      add_product = lambda do |value|
        code = exact(value)
        products << code if valid?(code) && !products.include?(code)
      end

      Array(model.active_path).reverse_each do |entity|
        codes_for_entity(entity).each { |code| add_product.call(code) }
      end

      selection.each do |entity|
        codes_for_entity(entity).each { |code| add_product.call(code) }
      end

      unless products.empty?
        return cache_result(cache_key, products.sort_by { |code| sort_key(code) })
      end

      if allow_slow_scan
        selected_ids = selection.map { |entity| entity.entityID rescue nil }.compact
        scan_entities_for_selected_products(model.entities, selected_ids, '', 0, add_product)
      end

      cache_result(cache_key, products.sort_by { |code| sort_key(code) })
    rescue
      []
    end

    def selected_code(model = Sketchup.active_model, allow_slow_scan: true)
      codes_from_selection(model, allow_slow_scan: allow_slow_scan).first.to_s
    rescue
      ''
    end

    def current_or_last_code(model = Sketchup.active_model, allow_slow_scan: true)
      install_observer(model)
      code = selected_code(model, allow_slow_scan: allow_slow_scan)
      return remember_code(code, model) unless code.to_s.empty?

      last_code(model)
    rescue
      ''
    end

    def refresh_from_selection(model = Sketchup.active_model, allow_slow_scan: false)
      code = selected_code(model, allow_slow_scan: allow_slow_scan)
      code.to_s.empty? ? last_code(model) : remember_code(code, model)
    rescue
      ''
    end

    def remember_code(code, model = Sketchup.active_model)
      value = exact(code)
      return '' unless valid?(value)

      key = model_key(model)
      @last_selected_code_by_model[key] = value
      model.set_attribute('MH_ProductContext', 'last_selected_product_code', value) if model && model.respond_to?(:set_attribute)
      value
    rescue
      value.to_s
    end

    def last_code(model = Sketchup.active_model)
      key = model_key(model)
      cached = @last_selected_code_by_model[key].to_s
      return cached if valid?(cached)

      stored = model.get_attribute('MH_ProductContext', 'last_selected_product_code').to_s if model && model.respond_to?(:get_attribute)
      valid?(stored) ? stored : ''
    rescue
      ''
    end

    def model_key(model = Sketchup.active_model)
      return 'nil' unless model
      model.respond_to?(:guid) ? model.guid.to_s : model.object_id.to_s
    rescue
      model.object_id.to_s
    end

    def install_observer(model = Sketchup.active_model)
      return false unless model && model.respond_to?(:selection)

      key = model_key(model)
      return true if @observed_selection_by_model[key]

      observer = MH::ModelHub.subscribe(
        :product_context,
        on_selection: ->(_kind) { MH::ProductContext.refresh_from_selection(Sketchup.active_model, allow_slow_scan: false) },
        visible: -> { true }
      )
      @observed_selection_by_model[key] = observer
      refresh_from_selection(model, allow_slow_scan: false)
      true
    rescue => e
      MH::Shared.dbg("[MH::ProductContext] selection observer error: #{e.class}: #{e.message}") if defined?(MH::Shared)
      false
    end

    def cache_result(cache_key, result)
      @codes_cache_key = cache_key
      @codes_cache = Array(result).dup
      @codes_cache.dup
    end

    def scan_entities_for_selected_products(entities, selected_ids, current_product, depth, add_product)
      return if depth > 2 || !entities

      entities.each do |entity|
        next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

        own_code = code_from_entity(entity)
        product = own_code.to_s.empty? ? current_product : own_code
        add_product.call(product) if selected_ids.include?(entity.entityID) && !product.to_s.empty?

        child_entities = if entity.is_a?(Sketchup::Group)
                           entity.entities
                         elsif entity.respond_to?(:definition) && entity.definition
                           entity.definition.entities
                         end
        scan_entities_for_selected_products(child_entities, selected_ids, product, depth + 1, add_product) if child_entities
      end
      nil
    rescue
      nil
    end
  end
end

MH::ProductContext.install_observer if defined?(Sketchup)

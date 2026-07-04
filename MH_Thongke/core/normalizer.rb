# encoding: utf-8
# MH_Thongke — Normalizer
# Single class for all name/material normalization with unified cache.
# Replaces: cached_norm (@norm_cache), import_name_norm (@import_name_norm_cache),
# import_equivalent_norm (@import_equiv_norm_cache) — 3 caches → 1.

module MH_Thongke
  class Normalizer
    MAX_CACHE_SIZE = 4000

    def initialize
      @cache = {}
    end

    def clear!
      @cache.clear
    end

    def size
      @cache.size
    end

    # Base normalization: Vietnamese mojibake fix → remove diacritics → downcase
    def base(value)
      return "" if value.nil?
      key = [:base, value.to_s]
      return @cache[key] if @cache.key?(key)
      evict_if_full!

      result = MH::Text.fold(value)
      @cache[key] = result
    end

    # Name normalization: base + synonym pair replacement
    def name(value, rules = nil)
      return "" if value.nil?
      pairs = synonym_pairs(rules)
      key = [:name, value.to_s, pairs.hash]
      return @cache[key] if @cache.key?(key)
      evict_if_full!

      norm = base(value)
      pairs.each do |pair|
        next unless pair.is_a?(Array) && pair.size >= 2
        a = pair[0].to_s.strip
        b = pair[1].to_s.strip
        next if a.empty? || b.empty?
        norm = norm.gsub(/\b#{Regexp.escape(a)}\b/, b)
                   .gsub(/\b#{Regexp.escape(b)}\b/, b)
      end
      @cache[key] = norm
    end

    # Equivalent normalization: name + equivalent pair replacement
    def equivalent(value, rules = nil)
      return "" if value.nil?
      pairs = equivalent_pairs(rules)
      key = [:equiv, value.to_s, pairs.hash]
      return @cache[key] if @cache.key?(key)
      evict_if_full!

      norm = name(value, rules)
      pairs.each do |pair|
        next unless pair.is_a?(Array) && pair.size >= 2
        from = pair[0].to_s.strip
        to = pair[1].to_s.strip
        next if from.empty? || to.empty?
        norm = norm.gsub(/\b#{Regexp.escape(from)}\b/, to)
      end
      result = norm.gsub(/\s+/, " ").strip
      @cache[key] = result
    end

    # Check if two names match (by name norm or equivalent norm)
    def names_match?(a, b, rules = nil)
      na = name(a, rules)
      nb = name(b, rules)
      return true if !na.empty? && na == nb

      ea = equivalent(a, rules)
      eb = equivalent(b, rules)
      !ea.empty? && ea == eb
    end

    # Hidden item normalization (same as base, for hidden_item_name? matching)
    def hidden(value)
      base(value).gsub(/\s+/, " ").strip
    rescue
      value.to_s.downcase.gsub(/\s+/, " ").strip
    end

    # Material/hardware dispatch
    def accept(kind, value, rules = nil)
      kind.to_s == "VL" ? material(value) : name(value, rules)
    end

    # Material code normalization (no cache — very fast, stateless)
    def material(value)
      code = value.to_s.strip.upcase.gsub(/\s+/, "")
      parts = code.split(".")
      parts.delete_at(1) if parts.size > 1 && parts[1].to_s =~ /\A\d+(?:\.\d+)?\z/
      parts = parts.reject { |part| part.to_s =~ /\A[12]M\z/i }
      parts.join(".")
    end

    private

    def evict_if_full!
      @cache.clear if @cache.size > MAX_CACHE_SIZE
    end

    def synonym_pairs(rules)
      rules_hash = rules || MH_Thongke.instance_variable_get(:@general_rules)
      pairs = (rules_hash && rules_hash["synonym_pairs"]).is_a?(Array) ? rules_hash["synonym_pairs"] : []
      pairs = MH_Thongke::DEFAULT_GENERAL_RULES["synonym_pairs"] if pairs.empty?
      pairs || []
    end

    def equivalent_pairs(rules)
      rules_hash = rules || MH_Thongke.instance_variable_get(:@general_rules)
      pairs = (rules_hash && rules_hash["equivalent_pairs"]).is_a?(Array) ? rules_hash["equivalent_pairs"] : []
      pairs = MH_Thongke::DEFAULT_GENERAL_RULES["equivalent_pairs"] if pairs.empty?
      pairs.is_a?(Array) ? pairs : []
    end
  end

  # Singleton accessor
  def self.normalizer
    @normalizer ||= Normalizer.new
  end

  def self.reset_normalizer!
    @normalizer = Normalizer.new
  end
end

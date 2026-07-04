# encoding: UTF-8

module MH
  module Rename
    module NameParser
      SYS_PFX_RE = /^(_+\d+)\.?\s*/.freeze
      PREFIX_SEP_RE = /^[.\-_\s]*/.freeze

      module_function

      def strip_sys_prefix(raw)
        raw.to_s.sub(SYS_PFX_RE, '')
      end

      def sys_prefix(raw)
        match = raw.to_s.match(SYS_PFX_RE)
        match ? "#{match[1]}. " : ''
      end

      def sys_token(raw)
        match = raw.to_s.match(SYS_PFX_RE)
        match ? match[0] : ''
      end

      def extract_prefix(name, prefixes)
        remaining = name.to_s
        prefix = ''
        separator = ''

        Array(prefixes).compact.map(&:to_s).reject(&:empty?).sort_by { |p| -p.length }.each do |candidate|
          next unless remaining.length >= candidate.length
          next unless remaining[0, candidate.length].downcase == candidate.downcase

          prefix = remaining[0, candidate.length]
          remaining = remaining[candidate.length..-1] || ''
          sep_match = remaining.match(PREFIX_SEP_RE)
          if sep_match && !sep_match[0].empty?
            separator = sep_match[0]
            remaining = remaining[separator.length..-1] || ''
          end
          return { prefix: prefix, separator: separator, prefix_with_separator: prefix + separator, remaining: remaining }
        end

        match = remaining.match(/^([A-Za-z]+\d+(?:\.[A-Za-z0-9]+)*)([.\-_\s]*)/)
        if match
          prefix = match[1]
          separator = match[2].to_s
          remaining = remaining[match[0].length..-1] || ''
        end

        { prefix: prefix, separator: separator, prefix_with_separator: prefix + separator, remaining: remaining }
      end

      def parse_name(raw, config = {})
        parsed = defined?(MH::NameGrammar) ? MH::NameGrammar.parse(raw) : nil
        if parsed && parsed[:recognized]
          prefix = parsed[:module_code].to_s.empty? ? parsed[:product].to_s : parsed[:module_code].to_s
          core = if defined?(MH::Rename) && MH::Rename.respond_to?(:strip_leading_module_tokens)
            MH::Rename.strip_leading_module_tokens(parsed[:part].to_s)
          else
            parsed[:part].to_s.strip
          end
          separator = core.empty? ? '' : (defined?(MH::NameGrammar) ? MH::NameGrammar.part_separator : '_')
          return {
            sys: sys_token(raw),
            sys_prefix: sys_prefix(raw),
            prefix: prefix,
            separator: separator,
            prefix_with_separator: prefix.empty? ? '' : "#{prefix}#{separator}",
            core: core,
            suffix: core,
            product_code: parsed[:product],
            module_no: parsed[:module_no],
            module_raw: parsed[:module_raw],
            modul: parsed[:modul],
            modul_label: parsed[:modul_label],
            module_code: parsed[:module_code],
            full_module_code: parsed[:full_module_code]
          }
        end

        clean = strip_sys_prefix(raw)
        extracted = extract_prefix(clean, config[:prefixes] || config['prefixes'])
        {
          sys: sys_token(raw),
          sys_prefix: sys_prefix(raw),
          prefix: extracted[:prefix],
          separator: extracted[:separator],
          prefix_with_separator: extracted[:prefix_with_separator],
          core: extracted[:remaining],
          suffix: extracted[:remaining].to_s.strip
        }
      end

      def format_display(parsed, show_id:, show_prefix:, show_suffix:)
        result = ''
        result += parsed[:sys].to_s if show_id

        prefix = parsed[:prefix].to_s
        suffix = parsed[:suffix].to_s
        if show_prefix && show_suffix
          result += if prefix.empty?
            suffix
          elsif suffix.empty?
            prefix
          else
            "#{prefix} - #{suffix}"
          end
        elsif show_prefix
          result += prefix
        elsif show_suffix
          result += suffix
        end

        result.empty? ? '<Ẩn>' : result
      end
    end
  end
end

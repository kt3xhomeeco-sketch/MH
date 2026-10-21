# encoding: UTF-8
require_relative 'domain'

module MH
  module ModuleStudio
    # Rename own references; original ATT keys and source formulas are evidence.
    module ParameterRename
      extend self
      TOKENS = /"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?|[a-zA-Z_][a-zA-Z_0-9]*/.freeze

      def expression(text, renames, detail: false)
        return text if renames.empty? || !text.is_a?(String) || text.empty?
        text.gsub(TOKENS) do |token|
          match = Regexp.last_match
          replacement = renames[token.downcase]
          next token unless replacement
          before = text[0...match.begin(0)].rstrip
          after = text[match.end(0)..].lstrip
          # Functions and scope names are not variable references.
          next token if after.start_with?('(', '!', '.')
          if before.end_with?('!', '.')
            scope = before[/([a-zA-Z_][a-zA-Z_0-9]*)\s*[!.]\z/, 1].to_s.downcase
            next token unless detail && %w[module parent].include?(scope) && !%w[lenx leny lenz x y z].include?(token.downcase)
          end
          replacement
        end
      end

      def apply!(bundle, previous, rows)
        old = previous.to_h { |row| [row['id'], row] }
        renames = rows.each_with_object({}) do |row, result|
          prior = old[row['id']]
          next unless prior
          raise Core::Error, 'ID biến không được chuyển sang tham số khác.' unless prior['binding'] == row['binding']
          symbol = row['symbol']
          unless symbol.is_a?(String) && symbol.match?(/\A[a-zA-Z_][a-zA-Z_0-9]{0,63}\z/)
            raise Core::Error, 'Ký hiệu biến không hợp lệ.'
          end
          result[prior['symbol'].downcase] = symbol unless prior['symbol'] == symbol
        end
        rows.each { |row| row['formula'] = expression(row['formula'], renames) }
        bundle.fetch('part_formulas', {}).each_value do |cells|
          cells.transform_values! { |text| expression(text, renames, detail: true) }
        end
        bundle.fetch('thickness_merge_anchors',[]).each { |entry| entry['formula'] = expression(entry['formula'],renames,detail:true) }
      end
    end
  end
end

# encoding: UTF-8
require_relative 'formula_math'
require_relative 'formula_aliases'

module MH
  module ModuleStudio
    module DCFormulas
      PRECEDENCE = { '=' => 1, '<>' => 1, '!=' => 1, '<' => 1, '>' => 1, '<=' => 1, '>=' => 1,
                     '+' => 2, '-' => 2, '*' => 3, '/' => 3 }.freeze

      class Parser
        def initialize(text, aliases: NOMINAL_FUNCTIONS)
          @aliases = aliases
          raise Core::Error, 'Công thức ATT quá dài.' if text.to_s.length > 4096
          source = text.to_s.strip.sub(/\A=/, '')
          @tokens = []
          until source.empty?
            source = source.lstrip
            break if source.empty?
            scope=source[/\A[\p{L}\p{N}_][\p{L}\p{N}_ .#]*?(?=\s*!(?!=))/]
            if scope
              @tokens << '@scope:'+scope.strip.downcase
              source=source[scope.length..]
              next
            end
            token = source[/\A(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?|\A[a-zA-Z_][a-zA-Z_0-9]*|\A(?:<=|>=|<>|!=|[+*\/=<>!(),-])/]
            raise Core::Error, "Cú pháp ATT chưa hỗ trợ: #{source[0, 35]}" unless token
            @tokens << token.downcase
            source = source[token.length..]
          end
          raise Core::Error, 'Công thức ATT quá phức tạp.' if @tokens.length > 512
          @index = 0
        end

        def parse
          result = expression(0, 0)
          raise Core::Error, 'Công thức ATT còn dữ liệu không hợp lệ.' if peek
          result
        end

        def peek
          @tokens[@index]
        end

        def take
          value = peek
          @index += 1
          value
        end

        def expect(token)
          raise Core::Error, "Công thức ATT thiếu #{token}." unless take == token
        end

        def expression(minimum, depth)
          raise Core::Error, 'Công thức ATT lồng quá sâu.' if depth > 40
          token = take
          left = if %w[+ -].include?(token)
                   [:unary, token, expression(4, depth + 1)]
                 elsif token == '('
                   value = expression(0, depth + 1)
                   expect(')')
                   value
                 elsif token&.start_with?('@scope:')
                   identifier(token.delete_prefix('@scope:'),depth)
                 elsif token && token.match?(/\A(?:\d|\.)/)
                   [:number, Core.number(token)]
                 elsif token && token.match?(/\A[a-z_]/)
                   identifier(token, depth)
                 else
                   raise Core::Error, 'Công thức ATT thiếu giá trị.'
                 end
          while PRECEDENCE[peek] && PRECEDENCE[peek] >= minimum
            operator = take
            left = [:binary, operator, left, expression(PRECEDENCE[operator] + 1, depth + 1)]
          end
          left
        end

        def identifier(token, depth)
          if peek == '('
            unless FUNCTIONS.include?(token) || @aliases.key?(token)
              raise Core::Error, "Hàm ATT chưa hỗ trợ hoặc chưa có định nghĩa đã xác minh: #{token}()"
            end
            take
            arguments = []
            unless peek == ')'
              loop do
                arguments << expression(0, depth + 1)
                break unless peek == ','
                take
              end
            end
            expect(')')
            if @aliases.key?(token)
              raise Core::Error, "Hàm kích thước #{token} không nhận đối số." unless arguments.empty?
              return [:nominal, 'parent', @aliases.fetch(token)]
            end
            expected = ARITIES.fetch(token, 1..512)
            raise Core::Error, "Số đối số của #{token} không hợp lệ." unless expected.cover?(arguments.length)
            [:call, token, arguments]
          elsif peek == '!'
            take
            name = take
            raise Core::Error, 'Tham chiếu ATT thiếu tên.' unless name && name.match?(/\A[a-z_][a-z_0-9]*\z/)
            [:reference, token, name]
          else
            [:reference, nil, token]
          end
        end
      end

    end
  end
end

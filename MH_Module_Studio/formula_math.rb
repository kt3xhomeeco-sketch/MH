# encoding: UTF-8
require_relative 'domain'

module MH
  module ModuleStudio
    module DCFormulas
      FUNCTIONS = %w[if and or not min max abs smallest largest round ceiling floor sqrt iseven choose sin cos tan pi true false
                     degrees even exp int isodd ln log10 odd radians sign acos acosh asin asinh atan atanh cosh sinh tanh nearest].freeze
      ARITIES = { 'if' => 3..3, 'not' => 1..1, 'abs' => 1..1, 'sqrt' => 1..1, 'iseven' => 1..1,
                  'sin' => 1..1, 'cos' => 1..1, 'tan' => 1..1, 'round' => 1..2, 'ceiling' => 1..2,
                  'floor' => 1..2, 'pi' => 0..0, 'true' => 0..0, 'false' => 0..0, 'choose' => 2..512,
                  'degrees' => 1..1, 'even' => 1..1, 'exp' => 1..1, 'int' => 1..1, 'isodd' => 1..1,
                  'ln' => 1..1, 'log10' => 1..1, 'odd' => 1..1, 'radians' => 1..1, 'sign' => 1..1,
                  'acos' => 1..1, 'acosh' => 1..1, 'asin' => 1..1, 'asinh' => 1..1, 'atan' => 1..1,
                  'atanh' => 1..1, 'cosh' => 1..1, 'sinh' => 1..1, 'tanh' => 1..1, 'nearest' => 2..512 }.freeze
      def self.binary(operator, a, b)
        case operator
        when '+' then a + b
        when '-' then a - b
        when '*' then a * b
        when '/'
          raise Core::Error, 'Công thức ATT chia cho 0.' if b.abs < 1.0e-12
          a / b
        when '=' then (a - b).abs < 1.0e-9 ? 1.0 : 0.0
        when '<>', '!=' then (a - b).abs >= 1.0e-9 ? 1.0 : 0.0
        when '<' then a < b ? 1.0 : 0.0
        when '>' then a > b ? 1.0 : 0.0
        when '<=' then a <= b ? 1.0 : 0.0
        when '>=' then a >= b ? 1.0 : 0.0
        end
      end
      def self.choice_index(value, count)
        index = Core.number(value).to_i
        raise Core::Error, 'CHOOSE: chỉ số ngoài danh sách.' unless index.between?(1, count)
        index
      end

      def self.numeric_function(name, values)
        first = values.first
        result = case name
                 when 'and' then values.all? { |value| !value.zero? } ? 1.0 : 0.0
                 when 'or' then values.any? { |value| !value.zero? } ? 1.0 : 0.0
                 when 'not' then first.zero? ? 1.0 : 0.0
                 when 'min', 'smallest' then values.min
                 when 'max', 'largest' then values.max
                 when 'abs' then first.abs
                 when 'true' then 1.0
                 when 'false' then 0.0
                 when 'pi' then Math::PI
                 when 'sqrt' then Math.sqrt(first)
                 when 'iseven' then first.to_i.even? ? 1.0 : 0.0
                 when 'isodd' then first.to_i.odd? ? 1.0 : 0.0
                 when 'int' then first.floor
                 when 'sign' then first <=> 0
                 when 'degrees' then first * 180.0 / Math::PI
                 when 'radians' then first * Math::PI / 180.0
                 when 'exp' then Math.exp(first)
                 when 'ln' then Math.log(first)
                 when 'log10' then Math.log10(first)
                 when 'even', 'odd'
                   magnitude = first.abs.ceil
                   magnitude += 1 unless name == 'even' ? magnitude.even? : magnitude.odd?
                   first.negative? ? -magnitude : magnitude
                 when 'nearest' then values.drop(1).min_by { |value| (value - first).abs }
                 when 'acos' then Math.acos(first) * 180.0 / Math::PI
                 when 'asin' then Math.asin(first) * 180.0 / Math::PI
                 when 'atan' then Math.atan(first) * 180.0 / Math::PI
                 when 'acosh' then Math.acosh(first) * 180.0 / Math::PI
                 when 'asinh' then Math.asinh(first) * 180.0 / Math::PI
                 when 'atanh' then Math.atanh(first) * 180.0 / Math::PI
                 when 'cosh' then Math.cosh(first * Math::PI / 180.0)
                 when 'sinh' then Math.sinh(first * Math::PI / 180.0)
                 when 'tanh' then Math.tanh(first * Math::PI / 180.0)
                 when 'sin' then Math.sin(first * Math::PI / 180.0)
                 when 'cos' then Math.cos(first * Math::PI / 180.0)
                 when 'tan' then Math.tan(first * Math::PI / 180.0)
                 when 'round'
                   places = (values[1] || 0).to_i
                   raise Core::Error, 'ROUND: số chữ số ngoài phạm vi -12–12.' unless places.between?(-12, 12)
                   first.round(places)
                 when 'ceiling', 'floor'
                   step = values[1] || 1.0
                   raise Core::Error, "#{name.upcase}: bước làm tròn phải dương." unless step > 0
                   rounded = name == 'ceiling' ? (first / step).ceil : (first / step).floor
                   rounded * step
                 else raise Core::Error, "Hàm chưa hỗ trợ trong biểu thức số: #{name}."
                 end
        Core.number(result)
      rescue Math::DomainError, RangeError
        raise Core::Error, "#{name.upcase}: kết quả số không hợp lệ."
      end

    end
  end
end

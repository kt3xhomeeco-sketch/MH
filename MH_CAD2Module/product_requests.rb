# frozen_string_literal: true

module MH
  module CAD2Module
    # Expand an inclusive SP range before starting the single source-reading job.
    module ProductRequests
      module_function

      def normalise(value)
        text = value.to_s.strip
        text = "SP#{text.rjust(2, '0')}" if text.match?(/\A\d+\z/)
        text.sub(/\ASP\s*[-_]?\s*(\d+)\z/i) { "SP#{Regexp.last_match(1).rjust(2, '0')}" }
      end

      def parse(first, last = nil)
        first = normalise(first)
        last = normalise(last)
        if first.empty? || last.empty?
          entries = (first.empty? ? last : first).split(/[\r\n,;]+/).map { |v| normalise(v) }.reject(&:empty?).uniq
          raise ArgumentError, 'Nhập mã SP vào một ô, hoặc mã bắt đầu và mã kết thúc.' if entries.empty?
          return entries
        end
        start_code = /\A([A-Z][A-Z0-9_-]*?)(\d+)\z/i.match(first)
        end_code = /\A([A-Z][A-Z0-9_-]*?)(\d+)\z/i.match(last)
        raise ArgumentError, 'Dải sản phẩm cần hai mã cùng tiền tố, ví dụ SP01 đến SP11 hoặc D1 đến D3.' unless start_code && end_code && start_code[1].upcase == end_code[1].upcase
        start_number = start_code[2].to_i
        end_number = end_code[2].to_i
        raise ArgumentError, 'Mã SP kết thúc phải lớn hơn hoặc bằng mã bắt đầu.' if end_number < start_number
        raise ArgumentError, 'Mỗi lượt dựng tối đa 1000 mã SP; chọn dải nhỏ hơn.' if end_number - start_number >= 1000
        prefix = start_code[1].upcase
        width = [prefix == 'SP' ? 2 : 1, start_code[2].length, end_code[2].length].max
        (start_number..end_number).map { |number| "#{prefix}#{number.to_s.rjust(width, '0')}" }
      end
    end
  end
end

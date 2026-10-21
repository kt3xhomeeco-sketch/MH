# encoding: UTF-8

module MH
  module Text
    module_function

    MOJIBAKE_MARKER_PARTS = [
      "\u00C3\u00A1", "\u00C3\u00A0", "\u00C3\u00A2", "\u00C3\u00A3",
      "\u00C3\u00AA", "\u00C3\u00A9", "\u00C3\u00A8", "\u00C3\u00AD",
      "\u00C3\u00AC", "\u00C3\u00B3", "\u00C3\u00B2", "\u00C3\u00B4",
      "\u00C3\u00B5", "\u00C3\u00BA", "\u00C3\u00B9", "\u00C3\u00BD",
      "áº", "á»", "Âº", "Â£", "Â¥", "Â°", "Â¡",
      "Æ°", "Æ¡", "Ä‘", "Ä", "â€", "â€“", "â€”", "â†"
    ].freeze
    MOJIBAKE_MARKERS = Regexp.union(MOJIBAKE_MARKER_PARTS)

    VIET_ASCII_UPPER = {
      "À"=>"A","Á"=>"A","Ạ"=>"A","Ả"=>"A","Ã"=>"A","Â"=>"A","Ầ"=>"A","Ấ"=>"A","Ậ"=>"A","Ẩ"=>"A","Ẫ"=>"A",
      "Ă"=>"A","Ằ"=>"A","Ắ"=>"A","Ặ"=>"A","Ẳ"=>"A","Ẵ"=>"A","Đ"=>"D","È"=>"E","É"=>"E","Ẹ"=>"E","Ẻ"=>"E",
      "Ẽ"=>"E","Ê"=>"E","Ề"=>"E","Ế"=>"E","Ệ"=>"E","Ể"=>"E","Ễ"=>"E","Ì"=>"I","Í"=>"I","Ị"=>"I","Ỉ"=>"I",
      "Ĩ"=>"I","Ò"=>"O","Ó"=>"O","Ọ"=>"O","Ỏ"=>"O","Õ"=>"O","Ô"=>"O","Ồ"=>"O","Ố"=>"O","Ộ"=>"O","Ổ"=>"O",
      "Ỗ"=>"O","Ơ"=>"O","Ờ"=>"O","Ớ"=>"O","Ợ"=>"O","Ở"=>"O","Ỡ"=>"O","Ù"=>"U","Ú"=>"U","Ụ"=>"U","Ủ"=>"U",
      "Ũ"=>"U","Ư"=>"U","Ừ"=>"U","Ứ"=>"U","Ự"=>"U","Ử"=>"U","Ữ"=>"U","Ỳ"=>"Y","Ý"=>"Y","Ỵ"=>"Y","Ỷ"=>"Y",
      "Ỹ"=>"Y"
    }.freeze

    def fix_mojibake(value)
      text = value.to_s
      return text if text.empty? || !(text =~ MOJIBAKE_MARKERS)

      3.times do
        break unless text =~ MOJIBAKE_MARKERS
        marker_count = text.scan(MOJIBAKE_MARKERS).size
        fixed = text.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "")
                    .force_encoding("UTF-8")
                    .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        fixed_count = fixed.scan(MOJIBAKE_MARKERS).size
        break if fixed.empty? || fixed == text || fixed_count >= marker_count
        text = fixed
      end
      text
    rescue
      value.to_s
    end

    def fold(value)
      return "" if value.nil?

      source = fix_mojibake(value).to_s.gsub("Đ", "D").gsub("đ", "d")
      result = begin
        source.unicode_normalize(:nfkd).gsub(/\p{Mn}+/, "")
      rescue
        source
      end
      result.gsub(/[._-]+/, " ").gsub(/\s+/, " ").strip.downcase
    end

    def slug(value)
      fold(value).gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
    end

    def upper_no_accent(value)
      source = fix_mojibake(value).to_s
      result = begin
        source.unicode_normalize(:nfkd).gsub(/\p{Mn}+/, "")
      rescue
        source
      end
      result.tr("đĐ", "dD").chars.map { |ch| VIET_ASCII_UPPER[ch] || ch }.join.upcase
    end

    def strip_sys_prefix(value)
      value.to_s.sub(/^_+\d+\.?\s*/, "")
    end
  end
end

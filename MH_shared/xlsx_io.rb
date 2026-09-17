# encoding: UTF-8
#
# MH::XlsxIO -- Đọc/ghi file .xlsx bằng pure-Ruby.
# ---------------------------------------------------------------------------
# Phụ thuộc:
#   * ::Zip   (rubyzip vendored)  -- container .xlsx là 1 file zip
#   * REXML   (default gem)       -- parse/build XML, KHÔNG cần nokogiri
#
# Phạm vi: bảng tabular (rows x cols), giá trị chuỗi & số. Bỏ qua style,
# merged cells, formula (chỉ lấy giá trị tính sẵn nếu có).
#
# API:
#   MH::XlsxIO.read(path)                  -> { "Sheet1" => [[..],[..]], ... }
#   MH::XlsxIO.read_sheet(path, name_or_i) -> [[..],[..]]
#   MH::XlsxIO.sheet_names(path)           -> ["Sheet1", ...]
#   MH::XlsxIO.write(path, sheets_hash)    -> path   (sheets_hash: { name => rows })
# ---------------------------------------------------------------------------

require 'rexml/document'
require 'stringio'
require 'fileutils'

module MH
  module XlsxIO
    class Error < StandardError; end

    module_function

    # =======================================================================
    # ĐỌC
    # =======================================================================

    # Trả về Hash { sheet_name => Array<Array<String>> } theo đúng thứ tự sheet.
    # Đọc qua StringIO (in-memory) để không lock file gốc trên Windows.
    def read(path)
      raise Error, "Khong tim thay file: #{path}" unless File.exist?(path)

      bytes = File.binread(path)
      io = StringIO.new(bytes)

      result = {}
      ::Zip::File.open_buffer(io) do |zip|
        entries = index_entries(zip)
        shared = parse_shared_strings(read_entry(zip, entries['xl/sharedstrings.xml']))
        sheets = workbook_sheets(zip, entries)
        sheets.each do |name, target|
          xml = read_entry(zip, entries[target.downcase])
          result[name] = xml ? parse_sheet(xml, shared) : []
        end
      end
      result
    end

    # Đọc 1 sheet theo tên hoặc chỉ số (0-based).
    def read_sheet(path, name_or_index = 0)
      all = read(path)
      if name_or_index.is_a?(Integer)
        all.values[name_or_index] || []
      else
        all[name_or_index.to_s] || all[name_or_index.to_s.downcase] ||
          all.detect { |k, _| k.to_s.downcase == name_or_index.to_s.downcase }&.last || []
      end
    end

    # Đọc rút gọn sheet đầu tiên cho các luồng chỉ cần vài cột (vd Ma_SP,
    # Ma_vat_lieu). Khác với read/read_sheet, hàm này không dựng DOM REXML,
    # không normalize đến cột cuối sheet và không giải mã các ô ngoài cột cần.
    # Rất quan trọng với file Excel bị dính format đến XFD.
    #
    # header_aliases: { 'Ma_SP' => ['Mã SP', ...], 'Ma_vat_lieu' => [...] }
    # header_normalizer: proc biến header/alias về cùng một key để so sánh.
    # Trả { sheet:, header_row:, rows: [{ 'Ma_SP' => '...', ... }] }.
    def read_first_sheet_selected_columns(path, header_aliases, header_normalizer:, header_row_limit: 50,
                                         relative_columns: {})
      raise Error, "Khong tim thay file: #{path}" unless File.exist?(path)

      alias_lookup = {}
      header_aliases.each do |key, aliases|
        Array(aliases).each { |name| alias_lookup[header_normalizer.call(name)] = key.to_s }
      end

      # Mở trực tiếp từ path. Một số RubyZip đi kèm SketchUp không tương thích
      # ổn định với StringIO ở open_buffer (undefined method [] for StringIO).
      ::Zip::File.open(path) do |zip|
        entries = index_entries(zip)
        shared = parse_shared_strings(read_entry(zip, entries['xl/sharedstrings.xml']))
        sheet = workbook_sheets(zip, entries).first
        raise Error, 'File Excel khong co worksheet.' unless sheet

        sheet_name, target = sheet
        xml = read_entry(zip, entries[target.downcase])
        raise Error, "Khong doc duoc worksheet: #{sheet_name}" unless xml

        selected_columns = {}
        selected_cell_pattern = nil
        output_rows = []
        header_row = nil
        row_number = 0

        xml.to_enum(:scan, /<row\b[^>]*>(.*?)<\/row>/m).each do
          row_xml = Regexp.last_match(1)
          row_number += 1
          cells = row_xml.to_enum(:scan, /<c\b([^>]*)(?:\/>|>(.*?)<\/c>)/m)

          if header_row.nil?
            found = {}
            cells.each do
              attrs = Regexp.last_match(1)
              body = Regexp.last_match(2)
              col = raw_cell_column(attrs)
              next if col.nil?

              value = raw_cell_value(attrs, body, shared)
              key = alias_lookup[header_normalizer.call(value)]
              found[col] = key if key
            end
            if found.values.uniq.length == header_aliases.keys.length
              selected_columns = found
              # A generated MH workbook keeps its runtime helper columns (Ma_SP,
              # Ma_vat_lieu) to the right of the human-facing material columns.
              # Read nearby columns by a fixed offset without parsing the whole
              # sheet, including intentionally blank/merged headers such as F.
              relative_columns.each do |anchor_key, offsets|
                # A sheet can contain both its visible "MÃ SP" column and the
                # generated runtime "Ma_SP" helper column. The helper is the
                # rightmost match, and its offsets point back to E/F/G.
                anchor_col = found.select { |_col, key| key == anchor_key.to_s }.keys.max
                next unless anchor_col

                offsets.each do |offset, output_key|
                  selected_columns[anchor_col + offset.to_i] = output_key.to_s
                end
              end
              header_row = row_number
              # Stream only the selected columns. The previous lookahead form
              # could skip a valid E cell after blank/merged cells; matching
              # the cell reference directly preserves E/F/G while avoiding a
              # costly scan of every formatted cell through XFD.
              selected_source = selected_columns.keys.map { |col| Regexp.escape(col_letter(col)) }.join('|')
              selected_cell_pattern = Regexp.new(
                '<c\\b([^>]*\\br=["\'](?:' + selected_source + ')\\d+["\'][^>]*)(?:/>|>(.*?)</c>)',
                Regexp::MULTILINE
              )
            elsif row_number >= header_row_limit
              break
            end
            next
          end

          compact = {}
          row_xml.to_enum(:scan, selected_cell_pattern).each do
            attrs = Regexp.last_match(1)
            body = Regexp.last_match(2)
            key = selected_columns[raw_cell_column(attrs)]
            next unless key

            compact[key] = raw_cell_value(attrs, body, shared).to_s.strip
          end
          output_rows << compact unless compact.empty?
        end

        {
          'sheet' => sheet_name.to_s,
          'header_row' => header_row,
          'rows' => output_rows
        }
      end
    end

    def sheet_names(path)
      ::Zip::File.open(path) do |zip|
        entries = index_entries(zip)
        return workbook_sheets(zip, entries).map(&:first)
      end
    end

    # ---- helpers đọc -------------------------------------------------------

    # Map tên entry (lowercase) -> tên entry thật (giữ nguyên hoa/thường).
    def index_entries(zip)
      map = {}
      zip.each { |e| map[e.name.downcase] = e.name }
      map
    end

    def read_entry(zip, real_name)
      return nil unless real_name
      entry = zip.find_entry(real_name)
      return nil unless entry
      data = entry.get_input_stream.read
      data.force_encoding('UTF-8')
      data
    end

    # attr của cell (vd: r="K7" t="s") -> index cột 0-based.
    def raw_cell_column(attrs)
      ref = attrs.to_s[/\br=["']([A-Za-z]+)\d+["']/, 1]
      ref ? col_index(ref) : nil
    end

    # Chỉ gọi cho header và các cột đã chọn. Hỗ trợ shared string, inline
    # string và giá trị/formula đã tính sẵn trong .xlsx.
    def raw_cell_value(attrs, body, shared)
      return '' if body.nil? || body.empty?

      type = attrs.to_s[/\bt=["']([^"']+)["']/, 1]
      case type
      when 's'
        index = body[/<v[^>]*>(.*?)<\/v>/m, 1]
        index ? shared[index.to_i].to_s : ''
      when 'inlineStr'
        body.scan(/<t[^>]*>(.*?)<\/t>/m).flatten.map { |text| xml_unescape(text) }.join
      else
        xml_unescape(body[/<v[^>]*>(.*?)<\/v>/m, 1].to_s)
      end
    end

    def xml_unescape(value)
      value.to_s.gsub('&lt;', '<').gsub('&gt;', '>').gsub('&quot;', '"')
        .gsub('&apos;', "'").gsub('&amp;', '&')
    end

    # Lấy danh sách [name, target_path] từ workbook.xml + workbook.xml.rels.
    def workbook_sheets(zip, entries)
      wb_xml = read_entry(zip, entries['xl/workbook.xml'])
      return [] unless wb_xml
      rels_xml = read_entry(zip, entries['xl/_rels/workbook.xml.rels'])

      # rId -> target (vd "worksheets/sheet1.xml")
      rid_target = {}
      if rels_xml
        REXML::Document.new(rels_xml).each_element('//Relationship') do |rel|
          id = rel.attributes['Id']
          tgt = rel.attributes['Target']
          rid_target[id] = tgt if id && tgt
        end
      end

      sheets = []
      idx = 0
      REXML::Document.new(wb_xml).each_element('//sheet') do |sh|
        idx += 1
        name = sh.attributes['name'] || "Sheet#{idx}"
        rid = sh.attributes['r:id'] || sh.attributes['id']
        target = rid_target[rid]
        target ||= "worksheets/sheet#{idx}.xml" # fallback theo thứ tự
        target = target.sub(%r{\A/}, '')         # bỏ '/' đầu nếu có
        full = target.start_with?('xl/') ? target : "xl/#{target}"
        sheets << [name, full]
      end
      sheets
    end

    # sharedStrings.xml -> Array<String> theo index.
    def parse_shared_strings(xml)
      return [] unless xml
      out = []
      REXML::Document.new(xml).each_element('//si') do |si|
        # Ghép tất cả text trong <t> (kể cả rich text nhiều <r><t>)
        buf = +''
        si.each_element('.//t') { |t| buf << (t.text || '') }
        out << buf
      end
      out
    end

    # worksheet xml -> Array<Array<String>>
    def parse_sheet(xml, shared)
      rows = []
      doc = REXML::Document.new(xml)
      doc.each_element('//row') do |row|
        cells = []
        max_col = -1
        row.each_element('c') do |c|
          ref = c.attributes['r']            # vd "B3"
          col = ref ? col_index(ref) : (cells.size)
          type = c.attributes['t']
          val = cell_value(c, type, shared)
          col = cells.size if col < 0
          # nới mảng nếu có ô trống ở giữa
          (cells.size..col - 1).each { cells << '' } if col > cells.size
          if col < cells.size
            cells[col] = val
          else
            cells << val
          end
          max_col = col if col > max_col
        end
        rows << cells
      end
      normalize_width(rows)
    end

    def cell_value(c, type, shared)
      case type
      when 's' # shared string
        v = c.elements['v']
        idx = v ? v.text.to_i : nil
        idx && shared[idx] ? shared[idx] : ''
      when 'inlineStr'
        is = c.elements['is']
        if is
          buf = +''
          is.each_element('.//t') { |t| buf << (t.text || '') }
          buf
        else
          ''
        end
      when 'str' # kết quả formula dạng chuỗi
        v = c.elements['v']
        v ? (v.text || '') : ''
      when 'b' # boolean
        v = c.elements['v']
        v && v.text.to_s.strip == '1' ? 'TRUE' : 'FALSE'
      else # số hoặc không có type
        v = c.elements['v']
        v ? (v.text || '') : ''
      end
    end

    # "B3" -> 1 (0-based col). Chỉ lấy phần chữ cái.
    def col_index(ref)
      letters = ref.to_s[/\A[A-Za-z]+/]
      return -1 unless letters
      n = 0
      letters.upcase.each_byte { |b| n = n * 26 + (b - 64) }
      n - 1
    end

    # Đảm bảo mọi row cùng độ rộng (max cols), ô thiếu = "".
    def normalize_width(rows)
      w = rows.map(&:size).max || 0
      rows.each { |r| (r.size...w).each { r << '' } }
      rows
    end

    # =======================================================================
    # GHI  (minimal valid xlsx, inline strings)
    # =======================================================================

    # sheets: Hash { "Sheet1" => [[r0c0, r0c1...], ...], ... }
    #   - giá trị Numeric  -> ghi dạng số
    #   - còn lại          -> inlineStr (giữ nguyên chuỗi, kể cả "001")
    def write(path, sheets)
      sheets = { 'Sheet1' => sheets } if sheets.is_a?(Array)
      names = sheets.keys
      names = ['Sheet1'] if names.empty?

      ::Zip::File.open(path, ::Zip::File::CREATE) do |zip|
        # Xoá entry cũ nếu ghi đè
        zip.entries.map(&:name).each { |n| zip.remove(n) rescue nil }

        add_entry(zip, '[Content_Types].xml', content_types_xml(names.size))
        add_entry(zip, '_rels/.rels', root_rels_xml)
        add_entry(zip, 'xl/workbook.xml', workbook_xml(names))
        add_entry(zip, 'xl/_rels/workbook.xml.rels', workbook_rels_xml(names.size))
        add_entry(zip, 'xl/styles.xml', styles_xml)

        names.each_with_index do |name, i|
          rows = sheets[name] || []
          add_entry(zip, "xl/worksheets/sheet#{i + 1}.xml", sheet_xml(rows))
        end
      end
      path
    end

    # ---- helpers ghi -------------------------------------------------------

    def add_entry(zip, name, content)
      zip.get_output_stream(name) { |os| os.write(content) }
    end

    def xml_escape(s)
      s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
       .gsub('"', '&quot;').gsub("'", '&apos;')
    end

    def col_letter(idx) # 0-based -> "A","B",... ,"AA"
      n = idx + 1
      s = +''
      while n > 0
        n, r = (n - 1).divmod(26)
        s.prepend((65 + r).chr)
      end
      s
    end

    def content_types_xml(sheet_count)
      sheets = (1..sheet_count).map do |i|
        %(<Override PartName="/xl/worksheets/sheet#{i}.xml" ) +
          %(ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>)
      end.join
      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>) +
        %(<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">) +
        %(<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>) +
        %(<Default Extension="xml" ContentType="application/xml"/>) +
        %(<Override PartName="/xl/workbook.xml" ) +
        %(ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>) +
        %(<Override PartName="/xl/styles.xml" ) +
        %(ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>) +
        sheets + %(</Types>)
    end

    def root_rels_xml
      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>) +
        %(<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">) +
        %(<Relationship Id="rId1" ) +
        %(Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" ) +
        %(Target="xl/workbook.xml"/></Relationships>)
    end

    def workbook_xml(names)
      sheets = names.each_with_index.map do |name, i|
        %(<sheet name="#{xml_escape(name)}" sheetId="#{i + 1}" r:id="rId#{i + 1}"/>)
      end.join
      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>) +
        %(<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ) +
        %(xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">) +
        %(<sheets>#{sheets}</sheets></workbook>)
    end

    def workbook_rels_xml(sheet_count)
      rels = (1..sheet_count).map do |i|
        %(<Relationship Id="rId#{i}" ) +
          %(Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" ) +
          %(Target="worksheets/sheet#{i}.xml"/>)
      end.join
      styles_id = "rId#{sheet_count + 1}"
      rels += %(<Relationship Id="#{styles_id}" ) +
        %(Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" ) +
        %(Target="styles.xml"/>)
      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>) +
        %(<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">) +
        rels + %(</Relationships>)
    end

    def styles_xml
      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>) +
        %(<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">) +
        %(<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>) +
        %(<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>) +
        %(<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>) +
        %(<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>) +
        %(<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>) +
        %(</styleSheet>)
    end

    def sheet_xml(rows)
      body = rows.each_with_index.map do |row, r|
        rownum = r + 1
        cells = Array(row).each_with_index.map do |val, c|
          ref = "#{col_letter(c)}#{rownum}"
          cell_xml(ref, val)
        end.join
        %(<row r="#{rownum}">#{cells}</row>)
      end.join
      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>) +
        %(<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">) +
        %(<sheetData>#{body}</sheetData></worksheet>)
    end

    def cell_xml(ref, val)
      if val.is_a?(Numeric)
        %(<c r="#{ref}"><v>#{val}</v></c>)
      else
        s = val.to_s
        return %(<c r="#{ref}"/>) if s.empty?
        %(<c r="#{ref}" t="inlineStr"><is><t xml:space="preserve">#{xml_escape(s)}</t></is></c>)
      end
    end
  end
end

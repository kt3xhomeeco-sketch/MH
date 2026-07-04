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

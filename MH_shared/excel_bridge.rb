# encoding: UTF-8
#
# MH::ExcelBridge -- Wrapper cấp cao trên MH::XlsxIO.
# ---------------------------------------------------------------------------
# Đây là API mà các plugin (và MH_Registry) dùng để đọc/ghi Excel:
#   - read_as_hashes : đọc sheet, hàng đầu = header -> Array<Hash<String,String>>
#   - read_sheet     : đọc raw rows -> Array<Array<String>>
#   - read_all       : đọc tất cả sheet -> Hash<name, rows>
#   - write          : ghi nhiều sheet { name => rows }
#   - write_hashes   : ghi Array<Hash> thành 1 sheet (tự suy ra cột)
#
# Hành vi tương thích với ConfigLoader.read_xlsx_sheet cũ:
#   * ô trống -> ""
#   * số dạng "17.0" -> "17" (bỏ đuôi .0)
#   * bỏ qua hàng rỗng hoàn toàn
# ---------------------------------------------------------------------------

require File.join(__dir__, 'xlsx_io')
require_relative 'material_code'

module MH
  module ExcelBridge
    module_function

    # ---- ĐỌC ---------------------------------------------------------------

    def read_all(path)
      MH::XlsxIO.read(path)
    end

    def sheet_names(path)
      MH::XlsxIO.sheet_names(path)
    end

    # Raw rows của 1 sheet (mặc định sheet đầu tiên).
    def read_sheet(path, sheet: nil)
      MH::XlsxIO.read_sheet(path, sheet.nil? ? 0 : sheet)
    end

    # Đọc sheet thành Array<Hash>. Hàng đầu là header (key).
    # Bỏ hàng rỗng. Giá trị được chuẩn hoá qua clean_value.
    def read_as_hashes(path, sheet: nil)
      rows = read_sheet(path, sheet: sheet)
      return [] if rows.nil? || rows.size < 2
      headers = rows.first.map { |h| h.to_s.strip }
      rows.drop(1).filter_map do |row|
        next if row.all? { |c| c.to_s.strip.empty? }
        h = {}
        headers.each_with_index do |key, i|
          next if key.empty?
          h[key] = clean_value(row[i])
        end
        h
      end
    end

    # Chuẩn hoá giá trị ô: nil -> "", "17.0" -> "17", strip.
    def clean_value(v)
      s = v.to_s
      s = s.sub(/\.0\z/, '') if s =~ /\A-?\d+\.0\z/
      s.strip
    end

    # ---- GHI ---------------------------------------------------------------

    # Ghi nhiều sheet. sheets: { "Name" => [[...row...], ...] }.
    # Mỗi giá trị có thể là Array<Array> (rows) HOẶC Array<Hash> (tự dựng header).
    def write(path, sheets:)
      normalized = {}
      sheets.each do |name, data|
        normalized[name.to_s] = material_export_sizes(rows_from(data))
      end
      MH::XlsxIO.write(path, normalized)
    end

    # Ghi 1 sheet từ Array<Hash>. columns: thứ tự cột (mặc định = union keys).
    def write_hashes(path, sheet_name:, rows:, columns: nil)
      MH::XlsxIO.write(path, { sheet_name.to_s => material_export_sizes(rows_from(rows, columns: columns)) })
    end

    # Shared report boundary for all MH_* exporters. Configuration sheets
    # have no purchase-size header and pass through unchanged.
    def material_export_sizes(rows)
      result = rows.map(&:dup)
      size_column = code_column = name_column = unit_column = nil
      result.each do |row|
        headers = row.map { |cell| cell.to_s.strip.downcase.gsub(/[\s_]+/, '') }
        found_size = headers.index { |h| %w[kíchthước kichthuoc dày day độdày doday size].include?(h) }
        found_code = headers.index { |h| %w[mãhiệu mahieu mãvậtliệu mavatlieu materialcode].include?(h) }
        found_name = headers.index { |h| %w[tênhàng tenhang tênvậtliệu tenvatlieu].include?(h) }
        found_unit = headers.index { |h| %w[đvt dvt đơnvị donvi unit].include?(h) }
        if found_size && (found_code || found_name)
          size_column, code_column, name_column, unit_column = found_size, found_code, found_name, found_unit
          next
        end
        next unless size_column

        unit = unit_column ? row[unit_column].to_s.strip.downcase : ''
        name = name_column ? row[name_column].to_s.strip : ''
        # Edge rows carry their board's code, but have their own thickness.
        next if name.match?(/\A(?:NẸP|NEP)(?:\s|\z)/i) || %w[md m dài].include?(unit)

        code = code_column ? row[code_column].to_s.strip : ''
        code = name if code.empty? && %w[tấm tam m2 m²].include?(unit)
        next if code.empty?

        row[size_column] = MH::MaterialCode.export_size(code, fallback: row[size_column])
      end
      result
    end

    # Chuyển Array<Hash> -> rows (kèm header). Nếu đã là Array<Array> thì giữ nguyên.
    def rows_from(data, columns: nil)
      arr = Array(data)
      return [] if arr.empty?
      if arr.first.is_a?(Hash)
        cols = columns || arr.flat_map(&:keys).map(&:to_s).uniq
        header = cols.dup
        body = arr.map { |h| cols.map { |c| fetch_cell(h, c) } }
        [header] + body
      else
        arr.map { |r| Array(r) }
      end
    end

    def fetch_cell(hash, col)
      v = hash[col]
      v = hash[col.to_sym] if v.nil?
      v.nil? ? '' : v
    end
  end
end

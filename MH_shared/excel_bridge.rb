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
        normalized[name.to_s] = rows_from(data)
      end
      MH::XlsxIO.write(path, normalized)
    end

    # Ghi 1 sheet từ Array<Hash>. columns: thứ tự cột (mặc định = union keys).
    def write_hashes(path, sheet_name:, rows:, columns: nil)
      MH::XlsxIO.write(path, { sheet_name.to_s => rows_from(rows, columns: columns) })
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

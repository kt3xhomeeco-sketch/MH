# MH::MaterialApp/main.rb
# Plugin: Tự động gán vật liệu cho Group theo tên Instance và dữ liệu từ Excel
# Format mã vật liệu: Lớp lõi.Độ dày.NCC.Mã VL bề mặt.Mặt phủ

require 'sketchup.rb'
require File.join(Sketchup.find_support_file('Plugins'), 'MH_shared.rb')
raise "[MH::MaterialApp] requires MH_shared" unless defined?(MH::Shared)

module MH
  module MaterialApp

    # ========== CONSTANTS ==========
    PLUGIN_DIR = File.dirname(__FILE__).gsub('/', '\\')
    CONFIG_DIR = PLUGIN_DIR  # CONFIG.xlsx nằm trong cùng thư mục plugin
    MATERIAL_FOLDER = 'D:/Cong viec/Sketchup/Material'
    MODEL_ATTR_DICT = 'MH_Material'
    ATTR_LAST_EXCEL_PATH = 'LastExcelPath'
    DEFAULT_LAST_EXCEL_PREFIX = 'LastExcelPathByModel:'
    DEBUG = false  # true = verbose logging ra Ruby Console (CHẬM khi vẽ HUD liên tục)
    # Alias cho tên cột header - mỗi key là tên nội bộ, value là danh sách tên chấp nhận (case-insensitive)
    COLUMN_ALIASES = {
      'Ma_SP'         => ['Ma_SP', 'Mã SP', 'Ma SP', 'MaSP', 'Mã sản phẩm', 'Ma san pham', 'Product Code', 'SP'],
      'Ma_vat_lieu'   => ['Ma_vat_lieu', 'Mã vật liệu', 'Ma vat lieu', 'MaVL', 'Mã VL', 'Ma VL', 'Material Code', 'Material', 'VL'],
      'Ten_chi_tiet'  => ['Ten_chi_tiet', 'Tên chi tiết', 'Ten chi tiet', 'TenCT', 'Chi tiết', 'Chi tiet', 'Detail Name', 'Detail', 'Tên CT', 'Quy cách vật liệu', 'Quy cach vat lieu']
    }

    COLUMN_ALIASES['Ten_chi_tiet'] += ['Product Name']

    EXCEL_DATA_COLUMNS = {
      'Ma_SP'        => 9,   # I
      'Ten_SP'       => 10,  # J
      'Ma_vat_lieu'  => 11   # K
    }.freeze
    EXCEL_DETAIL_COLUMN = 5 # E: Ten_chi_tiet / Quy cach vat lieu

    # ========== DATA STORES ==========
    @excel_data ||= []           # Array of Hash từ Excel
    @product_codes ||= []        # Danh sách mã SP
    @module_names ||= []         # Danh sách tên modul
    @thickness_mappings ||= []   # Bảng quy đổi độ dày
    @header_columns ||= []       # Tên các cột header
    @detail_aliases ||= {}       # Alias cho tên chi tiết (pattern => target)
    @tag_material_map ||= {      # Default mappings cho tag đặc biệt
      'MH_Sat' => 'Sat',
      'MH_Inox' => 'Inox'
    }
    # Column aliases - khởi tạo từ COLUMN_ALIASES, có thể ghi đè từ CONFIG.xlsx
    @column_aliases ||= COLUMN_ALIASES.each_with_object({}) { |(k,v), h| h[k] = v.dup }
    COLUMN_ALIASES.each do |internal_name, aliases|
      @column_aliases[internal_name] ||= []
      aliases.each do |alias_name|
        next if @column_aliases[internal_name].any? { |existing| existing.to_s.casecmp(alias_name.to_s) == 0 }

        @column_aliases[internal_name] << alias_name
      end
    end
    
    @last_assign_success ||= 0
    @last_assign_failed ||= 0
    @show_assign_counts ||= false
    @assign_counts_token ||= 0
    @max_length_limit ||= Sketchup.read_default("MH_Material", "MaxLength", 2400.0).to_f
    @surface_face_rules ||= []

    class << self
      attr_accessor :excel_data, :product_codes, :module_names, 
                    :thickness_mappings, :header_columns, :detail_aliases, :tag_material_map,
                    :column_aliases, :max_length_limit,
                    :last_assign_success, :last_assign_failed, :show_assign_counts, :assign_counts_token,
                    :surface_face_rules
    end

    def self.dbg(message)
      puts message if DEBUG
    end

    def self.notify(message)
      Sketchup.status_text = message.to_s rescue nil
      dbg(message)
    end

    # ========== CONFIG LOADER ==========
    module ConfigLoader
      # Đọc file CONFIG.xlsx bằng MH::ExcelBridge
      def self.read_xlsx_sheet(workbook, sheet_name)
        begin
          values = Array(workbook[sheet_name])
          
          return [] if values.length < 2 # Phải có ít nhất 1 dòng header và 1 dòng data
          
          # Đọc header row
          headers = values[0].map { |v| v.to_s.strip }
          
          # Đọc data rows
          data = []
          (1...values.length).each do |row_num|
            row_data = {}
            row_vals = values[row_num]
            headers.each_with_index do |header, idx|
              next if header.empty?
              cell_value = row_vals[idx]
              # Chuyển đổi nil thành chuỗi rỗng
              val = cell_value.nil? ? "" : cell_value.to_s.strip
              # Format số nguyên nếu kết thúc bằng .0 (Vd: "17.0" -> "17")
              val = val.gsub(/\.0$/, '') if val =~ /^\d+\.0$/
              row_data[header] = val
            end
            data << row_data unless row_data.values.all?(&:empty?)
          end
          
          puts "[MH::MaterialApp] Read #{data.length} rows from sheet '#{sheet_name}'" if DEBUG
          data
        rescue => e
          puts "[MH::MaterialApp] Error reading sheet #{sheet_name}: #{e.message}" if DEBUG
          []
        end
      end
      
      # Load tất cả config từ CONFIG.xlsx
      def self.load_all
        # Primary: load config từ MH_Registry connector
        if defined?(MH::RegistryApp::Connector)
          connector = MH::RegistryApp::Connector.get('material_assign')
          if connector && connector.respond_to?(:sync_config) && connector.available?
            result = connector.sync_config rescue false
            if result
              puts "[MH::MaterialApp] Config loaded from MH_Registry" if DEBUG
              return true
            end
          end
        end

        # Fallback: CONFIG.xlsx hoặc CONFIG1.xlsx
        config_file = File.join(CONFIG_DIR, 'CONFIG.xlsx')
        config_file = File.join(CONFIG_DIR, 'CONFIG1.xlsx') unless File.exist?(config_file)

        unless File.exist?(config_file)
          puts "[MH::MaterialApp] CONFIG.xlsx not found in #{CONFIG_DIR}" if DEBUG
          return false
        end
        
        begin
          workbook = MH::ExcelBridge.read_all(config_file)
          
          # Load product codes
          data = read_xlsx_sheet(workbook, 'ProductCodes')
          MH::MaterialApp.product_codes = data.map { |r| r['code'].to_s.strip }.reject(&:empty?)
          puts "[MH::MaterialApp] Loaded #{MH::MaterialApp.product_codes.length} product codes" if DEBUG
          
          # Load module names
          data = read_xlsx_sheet(workbook, 'ModuleNames')
          MH::MaterialApp.module_names = data.map { |r| r['name'].to_s.strip }.reject(&:empty?)
          puts "[MH::MaterialApp] Loaded #{MH::MaterialApp.module_names.length} module names" if DEBUG
          
          # Load thickness mappings
          data = read_xlsx_sheet(workbook, 'ThicknessMapping')
          MH::MaterialApp.thickness_mappings = []
          data.each do |row|
            min_val = row['min'].to_s.strip
            max_val = row['max'].to_s.strip
            value = row['value'].to_s.strip
            
            next if min_val.empty? || max_val.empty? || value.empty?
            
            MH::MaterialApp.thickness_mappings << {
              min: min_val.to_f,
              max: max_val.to_f,
              value: value
            }
          end
          puts "[MH::MaterialApp] Loaded #{MH::MaterialApp.thickness_mappings.length} thickness mappings" if DEBUG
          
          # Load header columns
          data = read_xlsx_sheet(workbook, 'HeaderColumns')
          MH::MaterialApp.header_columns = data.map { |r| r['column'].to_s.strip }.reject(&:empty?)
          puts "[MH::MaterialApp] Loaded #{MH::MaterialApp.header_columns.length} header columns" if DEBUG
          
          # Load detail aliases
          data = read_xlsx_sheet(workbook, 'DetailAliases')
          MH::MaterialApp.detail_aliases = {}
          data.each do |row|
            pattern = row['pattern'].to_s.strip.downcase
            target = row['target'].to_s.strip.downcase
            next if pattern.empty? || target.empty?
            MH::MaterialApp.detail_aliases[pattern] = target
          end
          puts "[MH::MaterialApp] Loaded #{MH::MaterialApp.detail_aliases.length} detail aliases" if DEBUG
          
          # Load tag materials mapping
          data = read_xlsx_sheet(workbook, 'TagMaterials')
          unless data.empty?
            tag_material_map = MH::MaterialApp.tag_material_map.dup
            data.each do |row|
              tag_name = row['tag_name'].to_s.strip
              material_name = row['material_name'].to_s.strip
              next if tag_name.empty? || material_name.empty?
              tag_material_map[tag_name] = material_name
            end
            MH::MaterialApp.tag_material_map = tag_material_map
          end
          puts "[MH::MaterialApp] Loaded #{MH::MaterialApp.tag_material_map.length} tag materials" if DEBUG
          
          # Load column aliases (merge với defaults)
          data = read_xlsx_sheet(workbook, 'ColumnAliases')
          unless data.empty?
            # Reset về defaults trước
            MH::MaterialApp.column_aliases = COLUMN_ALIASES.each_with_object({}) { |(k,v), h| h[k] = v.dup }
            data.each do |row|
              internal = row['internal_name'].to_s.strip
              alias_name = row['alias'].to_s.strip
              next if internal.empty? || alias_name.empty?
              MH::MaterialApp.column_aliases[internal] ||= []
              unless MH::MaterialApp.column_aliases[internal].any? { |a| a.casecmp(alias_name) == 0 }
                MH::MaterialApp.column_aliases[internal] << alias_name
              end
            end
            puts "[MH::MaterialApp] Loaded column aliases from Excel:" if DEBUG
            MH::MaterialApp.column_aliases.each do |k, v|
              puts "  #{k}: #{v.join(', ')}" if DEBUG
            end
          end
          
          total = MH::MaterialApp.product_codes.length + MH::MaterialApp.module_names.length + 
                  MH::MaterialApp.thickness_mappings.length + MH::MaterialApp.header_columns.length +
                  MH::MaterialApp.detail_aliases.length + MH::MaterialApp.tag_material_map.length +
                  MH::MaterialApp.column_aliases.values.flatten.length
          MH::MaterialApp.dbg("[MH::MaterialApp] Total configs loaded from CONFIG.xlsx: #{total}")
          
          true
        rescue => e
          puts "[MH::MaterialApp] Error loading CONFIG.xlsx: #{e.message}" if DEBUG
          puts e.backtrace.first(5).join("\n") if DEBUG
          false
        end
      end
    end

    # ========== EXCEL READER ==========
    module ExcelReader
      # Import từ Excel file (.xlsx) - sử dụng ExcelBridge pure-Ruby
      def self.import(file_path)
        MH::MaterialApp.excel_data = []
        
        begin
          rows = MH::ExcelBridge.read_sheet(file_path)
          
          # Tìm dòng header
          header_row, column_map = find_header_row(rows)

          unless header_row
            header_row = 0
            column_map = EXCEL_DATA_COLUMNS.dup
            puts "[MH::MaterialApp] No header detected; using fixed Excel columns I/J/K" if DEBUG
          end
          
          unless header_row
            MH::MaterialApp.notify("❌ Không tìm thấy dòng header trong file Excel!\nĐảm bảo có cột 'Ma_SP'.")
            workbook.Close(false)
            excel.Quit
            return false
          end
          
          puts "[MH::MaterialApp] Found header at row #{header_row}" if DEBUG
          EXCEL_DATA_COLUMNS.each { |col_name, col_idx| column_map[col_name] = col_idx }
          column_map['Ten_chi_tiet'] = EXCEL_DETAIL_COLUMN
          puts "[MH::MaterialApp] Column map: #{column_map}" if DEBUG
          
          # Đọc dữ liệu từ dòng sau header
          current_product = nil
          
          rows.drop(header_row).each do |row|
            row_data = {}
            
            # Đọc từng cột theo column_map
            column_map.each do |col_name, col_idx|
              value = cell_at(row, col_idx).to_s.strip
              row_data[col_name] = value
            end
            
            # Ten_chi_tiet: ưu tiên column_map, fallback về cột E (cột 5)
            row_data['Ten_chi_tiet'] = cell_at(row, EXCEL_DETAIL_COLUMN).to_s.strip
            
            # Skip dòng hoàn toàn trống
            next if row_data.values.all?(&:empty?)
            
            # Track current product code (có thể merge cells)
            if row_data['Ma_SP'] && !row_data['Ma_SP'].empty?
              current_product = row_data['Ma_SP']
            else
              row_data['Ma_SP'] = current_product
            end
            
            # Chỉ lưu nếu có thông tin vật liệu
            has_material_info = (row_data['Ma_vat_lieu'] && !row_data['Ma_vat_lieu'].empty?)
            
            if has_material_info
              MH::MaterialApp.excel_data << row_data
            end
          end
          
          puts "[MH::MaterialApp] Imported #{MH::MaterialApp.excel_data.length} records from Excel" if DEBUG
          MH::MaterialApp.notify("✅ Đã import #{MH::MaterialApp.excel_data.length} dòng dữ liệu từ Excel!")
          true
          
        rescue => e
          MH::MaterialApp.notify("❌ Lỗi import Excel: #{e.message}")
          MH::MaterialApp.dbg("[MH::MaterialApp] Error: #{e.message}")
          puts e.backtrace.first(5).join("\n") if DEBUG
          false
        end
      end

      # Tìm dòng header trong sheet
      # Sử dụng COLUMN_ALIASES để nhận diện nhiều tên cột khác nhau
      def self.find_header_row(rows)
        max_search_rows = 20  # Chỉ tìm trong 20 dòng đầu
        
        rows.first(max_search_rows).each_with_index do |row, idx|
          row_num = idx + 1
          column_map = {}
          all_cells = []  # Debug: lưu tất cả các cell values
          
          # Scan các cột trong dòng này
          (1..50).each do |col_num|
            raw_value = cell_at(row, col_num).to_s.strip
            cell_value = raw_value.strip
            
            # Debug: lưu lại để hiển thị
            all_cells << raw_value unless raw_value.empty?
            
            # So sánh với danh sách alias (case-insensitive Unicode)
            MH::MaterialApp.column_aliases.each do |internal_name, aliases|
              next if column_map.key?(internal_name)  # Đã tìm thấy rồi thì bỏ qua
              if aliases.any? { |a| a.to_s.downcase.strip == cell_value.downcase.strip }
                column_map[internal_name] = col_num
                puts "[MH::MaterialApp] Mapped column '#{raw_value}' -> '#{internal_name}' (col #{col_num})" if DEBUG
              end
            end
          end
          
          # Nếu tìm thấy cột "Ma_SP" thì coi như đây là header row
          if column_map.key?('Ma_SP')
            puts "[MH::MaterialApp] Excel row #{row_num} cells: #{all_cells.join(' | ')}" if DEBUG
            puts "[MH::MaterialApp] Detected columns: #{column_map.map { |k,v| "#{k}=col#{v}" }.join(', ')}" if DEBUG
            return [row_num, column_map]
          end
        end
        
        [nil, {}]
      end

      def self.cell_at(row, one_based_col)
        Array(row)[one_based_col.to_i - 1]
      end
    end

    # ========== CSV READER ==========
    module CSVReader
      require 'csv'
      
      # Import từ CSV file
      def self.import(file_path)
        MH::MaterialApp.excel_data = []
        
        begin
          # Đọc file CSV với encoding UTF-8
          content = File.read(file_path, encoding: 'UTF-8:UTF-8')
          rows = CSV.parse(content)
          
          # Tìm dòng header
          header_row_idx, column_map = find_header_row(rows)
          
          unless header_row_idx
            MH::MaterialApp.notify("❌ Không tìm thấy dòng header trong file CSV!\nĐảm bảo có cột 'Ma_SP'.")
            return false
          end
          
          puts "[MH::MaterialApp] Found CSV header at row #{header_row_idx + 1}" if DEBUG
          puts "[MH::MaterialApp] Column map: #{column_map}" if DEBUG
          
          # Đọc dữ liệu từ dòng sau header
          current_product = nil
          
          ((header_row_idx + 1)...rows.length).each do |row_idx|
            row = rows[row_idx]
            next unless row
            
            row_data = {}
            
            # Đọc từng cột theo column_map
            column_map.each do |col_name, col_idx|
              value = row[col_idx].to_s.strip
              row_data[col_name] = value
            end
            
            # Ten_chi_tiet: ưu tiên column_map, fallback về cột E (index 4)
            unless column_map.key?('Ten_chi_tiet')
              row_data['Ten_chi_tiet'] = row[4].to_s.strip if row.length > 4
            end
            
            # Skip dòng hoàn toàn trống
            next if row_data.values.all?(&:empty?)
            
            # Track current product code (merge cells)
            if row_data['Ma_SP'] && !row_data['Ma_SP'].empty?
              current_product = row_data['Ma_SP']
            else
              row_data['Ma_SP'] = current_product
            end
            
            # Chỉ lưu nếu có thông tin
            unless row_data.values.all?(&:empty?)
              MH::MaterialApp.excel_data << row_data
            end
          end
          
          puts "[MH::MaterialApp] Imported #{MH::MaterialApp.excel_data.length} records from CSV" if DEBUG
          MH::MaterialApp.notify("✅ Đã import #{MH::MaterialApp.excel_data.length} dòng dữ liệu từ CSV!")
          true
          
        rescue => e
          MH::MaterialApp.notify("❌ Lỗi import CSV: #{e.message}")
          MH::MaterialApp.dbg("[MH::MaterialApp] CSV Error: #{e.message}")
          puts e.backtrace.first(5).join("\n") if DEBUG
          false
        end
      end
      
      # Tìm dòng header trong CSV
      # Sử dụng COLUMN_ALIASES để nhận diện nhiều tên cột khác nhau
      def self.find_header_row(rows)
        max_search_rows = [20, rows.length].min
        
        (0...max_search_rows).each do |row_idx|
          row = rows[row_idx]
          next unless row
          
          column_map = {}
          
          row.each_with_index do |cell, col_idx|
            cell_value = cell.to_s.strip
            
            # So sánh với danh sách alias (case-insensitive Unicode)
            MH::MaterialApp.column_aliases.each do |internal_name, aliases|
              next if column_map.key?(internal_name)  # Đã tìm thấy rồi thì bỏ qua
              if aliases.any? { |a| a.to_s.downcase.strip == cell_value.downcase.strip }
                column_map[internal_name] = col_idx
                puts "[MH::MaterialApp] CSV mapped column '#{cell_value}' -> '#{internal_name}' (col #{col_idx})" if DEBUG
              end
            end
          end
          
          # Nếu tìm thấy cột "Ma_SP" thì coi như đây là header row
          if column_map.key?('Ma_SP')
            puts "[MH::MaterialApp] Found CSV header at row #{row_idx + 1}, columns: #{column_map.map { |k,v| "#{k}=col#{v}" }.join(', ')}" if DEBUG
            return [row_idx, column_map]
          end
        end
        
        [nil, {}]
      end
    end

    # ========== INSTANCE NAME PARSER ==========
    module InstanceNameParser
      # Parse tên theo format: __ID .Mã SP_Tên chi tiết
      # Ví dụ: __0357 .SP01_Cánh trái
      def self.parse(name)
        result = {
          id: nil,
          product_code: nil,
          detail_name: nil,
          raw_name: name
        }
        
        # Extract ID: __xxx. hoặc __xxx  
        id_match = name.match(/^__(\d+)\s*\.?\s*/)
        if id_match
          result[:id] = id_match[1]
          # Phần còn lại sau ID
          remaining = name[id_match[0].length..-1].to_s.strip
        else
          remaining = name.strip
        end
        
        return result if remaining.empty?
        
        # Split theo underscore
        parts = remaining.split('_').map(&:strip).reject(&:empty?)
        return result if parts.empty?
        
        # Tìm Product Code trong các phần
        product_codes = MH::MaterialApp.product_codes
        
        product_idx = nil
        embedded_detail = nil
        
        # Đầu tiên tìm exact match (case-insensitive)
        parts.each_with_index do |part, idx|
          if product_codes.any? { |pc| pc.upcase == part.upcase } && product_idx.nil?
            product_idx = idx
            result[:product_code] = part.upcase
          end
        end
        
        # Nếu không tìm thấy exact match, thử tìm product code embedded theo NameGrammar
        if result[:product_code].nil?
          parts.each_with_index do |part, idx|
            found_code = if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:first_product)
              MH::NameGrammar.first_product(part).to_s
            else
              ''
            end
            unless found_code.empty?
              product_idx = idx
              result[:product_code] = found_code.upcase
              embedded_detail = part.sub(/#{Regexp.escape(found_code)}/i, '').strip
              puts "[MH::MaterialApp] Found embedded product code: '#{found_code}' in '#{part}'" if DEBUG
              break
            end
          end
        end
        
        # Xác định phần chi tiết (phần còn lại sau product)
        detail_parts = []
        parts.each_with_index do |part, idx|
          if idx == product_idx
            detail_parts << embedded_detail if embedded_detail && !embedded_detail.empty?
            next
          end
          detail_parts << part
        end
        
        result[:detail_name] = detail_parts.join('_') unless detail_parts.empty?
        
        puts "[MH::MaterialApp] Parsed '#{name}' => #{result}" if DEBUG
        result
      end
    end

    # ========== MATERIAL MATCHER ==========
    module MaterialMatcher
      def self.product_code_candidates(product_code)
        code = product_code.to_s.upcase.strip
        candidates = []

        base = parent_product_code(code)
        if base != code
          candidates << base
        end

        candidates << code
        candidates.uniq
      end

      def self.parent_product_code(product_code)
        code = product_code.to_s.upcase.strip
        if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:base)
          MH::ProductContext.base(code)
        else
          code.split('.').first.to_s
        end
      end

      def self.child_product_code?(product_code)
        code = product_code.to_s.upcase.strip
        code.include?('.') && parent_product_code(code) != code
      end

      def self.product_code_from_text(text)
        code = if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:first_product)
          MH::NameGrammar.first_product(text).to_s
        else
          ''
        end
        code.empty? ? text.to_s.upcase.strip : code.upcase
      end

      def self.exact_rows_for_product_code(product_code)
        code = product_code.to_s.upcase.strip
        MH::MaterialApp.excel_data.select do |row|
          row['Ma_SP'].to_s.upcase.strip == code
        end
      end

      def self.rows_for_product_code(product_code)
        matches = MH::MaterialApp.excel_data.select do |row|
          row['Ma_SP'].to_s.upcase.strip == product_code
        end

        if matches.empty?
          matches = MH::MaterialApp.excel_data.select do |row|
            excel_sp = row['Ma_SP'].to_s.upcase
            product_code_from_text(excel_sp) == product_code
          end
        end

        matches
      end

      def self.match_key(text)
        MH::Text.fold(text).gsub(/[#]+/, ' ').gsub(/\s+/, ' ').strip
      end

      def self.rows_for_detail_name(detail_name)
        detail_key = match_key(detail_name)
        return [] if detail_key.empty?

        rows = MH::MaterialApp.excel_data.select do |row|
          excel_detail = match_key(row['Ten_chi_tiet'])
          !excel_detail.empty? && excel_detail == detail_key && !row['Ma_vat_lieu'].to_s.strip.empty?
        end
        return rows if rows.any?

        MH::MaterialApp.excel_data.select do |row|
          excel_detail = match_key(row['Ten_chi_tiet'])
          !excel_detail.empty? &&
            (excel_detail.include?(detail_key) || detail_key.include?(excel_detail)) &&
            !row['Ma_vat_lieu'].to_s.strip.empty?
        end
      end

      def self.multi_material_row?(row)
        row['Ma_vat_lieu'].to_s.include?('&')
      end

      # Tìm dòng Excel phù hợp với OBJ
      # Thứ tự ưu tiên:
      #   1. Filter theo Product Code (bắt buộc)
      #   2. Match EXACT theo Tên chi tiết
      #   3. Match PARTIAL (chứa) theo Tên chi tiết
      #   4. Fallback về "thùng"
      #   5. Fallback về "cánh"
      def self.find_matching_row(parsed_name)
        product_code = parsed_name[:product_code]
        detail_name = parsed_name[:detail_name]
        
        return nil unless product_code

        original_product_code = product_code.to_s.upcase.strip
        parent_code = parent_product_code(original_product_code)

        if child_product_code?(original_product_code) && exact_rows_for_product_code(original_product_code).any?
          product_code = original_product_code
          puts "[MH::MaterialApp] Product code explicit child: '#{original_product_code}'" if DEBUG
        elsif parent_code != original_product_code && exact_rows_for_product_code(parent_code).any?
          product_code = parent_code
          puts "[MH::MaterialApp] Product code parent fallback: '#{original_product_code}' -> '#{parent_code}'" if DEBUG
        else
          product_code_candidates(product_code).each do |candidate|
            unless rows_for_product_code(candidate).empty?
              puts "[MH::MaterialApp] Product code priority: '#{product_code}' -> '#{candidate}'" if DEBUG && candidate != product_code
              product_code = candidate
              break
            end
          end
        end
        
        # ========== FILTER 1: Product Code (bắt buộc) ==========
        puts "[MH::MaterialApp] Searching in #{MH::MaterialApp.excel_data.length} Excel rows for SP='#{product_code}'" if DEBUG
        
        # Đầu tiên thử exact match
        matches = MH::MaterialApp.excel_data.select do |row|
          row['Ma_SP'].to_s.upcase == product_code.upcase
        end
        
        # Nếu không có exact match, thử tìm SP code embedded trong Ma_SP
        if matches.empty?
          puts "[MH::MaterialApp] No exact match, trying embedded product code search..." if DEBUG
          matches = MH::MaterialApp.excel_data.select do |row|
            excel_sp = row['Ma_SP'].to_s.upcase
            product_code_from_text(excel_sp) == product_code.upcase
          end
        end
        
        return nil if matches.empty?
        puts "[MH::MaterialApp] Found #{matches.length} rows for '#{product_code}'" if DEBUG
        
        # ========== MATCH 2: Exact name match ==========
        if detail_name && !detail_name.empty?
          detail_key = match_key(detail_name)
          
          # Tìm EXACT match (tên chi tiết trong Excel = tên chi tiết trong OBJ)
          exact_matches = matches.select do |row|
            excel_detail = match_key(row['Ten_chi_tiet'])
            excel_detail == detail_key
          end
          
          if exact_matches.any?
            puts "[MH::MaterialApp] EXACT match for '#{detail_name}'" if DEBUG
            matches = exact_matches
          else
            # ========== MATCH 3: Partial match (chứa) ==========
            # Excel chứa OBJ hoặc OBJ chứa Excel
            partial_matches = matches.select do |row|
              excel_detail = match_key(row['Ten_chi_tiet'])
              next false if excel_detail.empty?
              excel_detail.include?(detail_key) || detail_key.include?(excel_detail)
            end
            
            if partial_matches.any?
              # Ưu tiên match ngắn nhất (gần với exact nhất)
              partial_matches.sort_by! { |row| row['Ten_chi_tiet'].to_s.length }
              puts "[MH::MaterialApp] PARTIAL match for '#{detail_name}' -> '#{partial_matches.first['Ten_chi_tiet']}'" if DEBUG
              matches = partial_matches
            else
              keyword_matches = []
              if detail_key.include?('canh')
                keyword_matches = matches.select do |row|
                  excel_key = match_key(row['Ten_chi_tiet'])
                  next false if excel_key.include?('khong canh') && !detail_key.include?('khong canh')

                  excel_key.include?('canh') && !row['Ma_vat_lieu'].to_s.strip.empty?
                end
              end

              if keyword_matches.any?
                keyword_matches.sort_by! { |row| [match_key(row['Ten_chi_tiet']).length, row['Ten_chi_tiet'].to_s.length] }
                puts "[MH::MaterialApp] KEYWORD match for '#{detail_name}' -> '#{keyword_matches.first['Ten_chi_tiet']}'" if DEBUG
                matches = keyword_matches
              else
              # ========== MATCH 4: Alias (từ CSV) ==========
              alias_target = nil
              MH::MaterialApp.detail_aliases.each do |pattern, target|
                pattern_key = match_key(pattern)
                next if pattern_key.empty?

                if detail_key.include?(pattern_key)
                  alias_target = match_key(target)
                  puts "[MH::MaterialApp] Alias: '#{detail_name}' -> '#{target}'" if DEBUG
                  break
                end
              end
              
              if alias_target
                alias_matches = matches.select do |row|
                  match_key(row['Ten_chi_tiet']).include?(alias_target)
                end
                matches = alias_matches if alias_matches.any?
              end
              
              # ========== MATCH 5: Fallback to "khung" ==========
              if matches.length > 1 || alias_target.nil?
                khung_matches = matches.select do |row|
                  row['Ten_chi_tiet'].to_s.downcase.strip == "khung"
                end
                
                if khung_matches.any?
                  puts "[MH::MaterialApp] No match for '#{detail_name}' -> fallback to 'khung'" if DEBUG
                  matches = khung_matches
                else
                  if detail_key.include?('canh')
                    multi_material_matches = matches.select do |row|
                      row['Ma_vat_lieu'].to_s.include?('&')
                    end

                    if multi_material_matches.any?
                      puts "[MH::MaterialApp] No match for '#{detail_name}' -> fallback to multi material row" if DEBUG
                      matches = multi_material_matches
                    end
                  end

                  # ========== MATCH 6: Most frequent Ma_vat_lieu (Final Fallback) ==========
                  puts "[MH::MaterialApp] No match for '#{detail_name}' -> fallback to most frequent Ma_vat_lieu" if DEBUG
                  
                  # Đếm số lần xuất hiện của mỗi Ma_vat_lieu
                  freq = {}
                  matches.each do |row|
                    code = row['Ma_vat_lieu'].to_s.strip
                    next if code.empty?
                    freq[code] ||= 0
                    freq[code] += 1
                  end
                  
                  unless freq.empty?
                    # Tìm Ma_vat_lieu xuất hiện nhiều nhất
                    most_frequent = freq.max_by { |_code, count| count }[0]
                    puts "[MH::MaterialApp] Most frequent Ma_vat_lieu: '#{most_frequent}' (#{freq[most_frequent]} times)" if DEBUG
                    
                    freq_matches = matches.select do |row|
                      row['Ma_vat_lieu'].to_s.strip == most_frequent
                    end
                    matches = freq_matches if freq_matches.any?
                  end
                end
              end
              end
            end
          end
        end
        
        # ========== CHỌN KẾT QUẢ TỐT NHẤT ==========
        # Ưu tiên dòng có Mã hiệu thường (không phải MH_xxx)
        normal_matches = matches.select do |row|
          ma_vl = row['Ma_vat_lieu'].to_s.strip
          !ma_vl.empty? && !(ma_vl =~ /^MH_/i)
        end

        if detail_name && match_key(detail_name).include?('canh')
          candidate_matches = normal_matches.any? ? normal_matches : matches
          multi_matches = candidate_matches.select { |row| multi_material_row?(row) }
          if multi_matches.any?
            puts "[MH::MaterialApp] Prefer multi material row for '#{detail_name}'" if DEBUG
            return multi_matches.first
          end
        end

        best_match = normal_matches.any? ? normal_matches.first : matches.first
        
        if best_match
          puts "[MH::MaterialApp] Best match: '#{best_match['Ten_chi_tiet']}' -> '#{best_match['Ma_vat_lieu']}'" if DEBUG
        end
        
        best_match
      end
    end

    # ========== MATERIAL CODE BUILDER ==========
    module MaterialCodeBuilder
      # Quy đổi độ dày theo bảng mapping
      def self.map_thickness(actual_thickness, fallback_to_actual: false)
        MH::MaterialCode.map_thickness(
          actual_thickness,
          mappings: MH::MaterialApp.thickness_mappings,
          fallback_to_actual: fallback_to_actual
        )
      end
      
      # Lấy kích thước 3 chiều thực của instance [min, mid, max]
      def self.get_dimensions(instance)
        begin
          if instance.is_a?(Sketchup::Group)
            bounds = instance.local_bounds
            min_pt = bounds.min
            max_pt = bounds.max
            
            corner_0 = Geom::Point3d.new(min_pt.x, min_pt.y, min_pt.z)
            corner_x = Geom::Point3d.new(max_pt.x, min_pt.y, min_pt.z)
            corner_y = Geom::Point3d.new(min_pt.x, max_pt.y, min_pt.z)
            corner_z = Geom::Point3d.new(min_pt.x, min_pt.y, max_pt.z)
            
            transform = instance.transformation
            pt_0 = corner_0.transform(transform)
            pt_x = corner_x.transform(transform)
            pt_y = corner_y.transform(transform)
            pt_z = corner_z.transform(transform)
            
            width = pt_0.distance(pt_x).to_mm
            height = pt_0.distance(pt_y).to_mm
            depth = pt_0.distance(pt_z).to_mm
            
          elsif instance.is_a?(Sketchup::ComponentInstance)
            def_bounds = instance.definition.bounds
            min_pt = def_bounds.min
            max_pt = def_bounds.max
            
            corner_0 = Geom::Point3d.new(min_pt.x, min_pt.y, min_pt.z)
            corner_x = Geom::Point3d.new(max_pt.x, min_pt.y, min_pt.z)
            corner_y = Geom::Point3d.new(min_pt.x, max_pt.y, min_pt.z)
            corner_z = Geom::Point3d.new(min_pt.x, min_pt.y, max_pt.z)
            
            transform = instance.transformation
            pt_0 = corner_0.transform(transform)
            pt_x = corner_x.transform(transform)
            pt_y = corner_y.transform(transform)
            pt_z = corner_z.transform(transform)
            
            width = pt_0.distance(pt_x).to_mm
            height = pt_0.distance(pt_y).to_mm
            depth = pt_0.distance(pt_z).to_mm
            
          else
            return [0, 0, 0]
          end
          
          [width, height, depth].map { |d| d.round(1) }.sort
        rescue => e
          [0, 0, 0]
        end
      end
      
      # Lấy độ dày (kích thước nhỏ nhất)
      def self.get_thickness(instance)
        get_dimensions(instance)[0]
      end
      
      # Lấy chiều dài (kích thước lớn nhất)
      def self.get_length(instance)
        get_dimensions(instance)[2]
      end
      
      # Thu thập geometry đệ quy
      def self.collect_geometry(entities, transform, faces_out, vertices_out)
        entities.each do |entity|
          if entity.is_a?(Sketchup::Face)
            # Lưu thông tin face với diện tích và normal đã transform
            transformed_normal = entity.normal.transform(transform)
            faces_out << {
              area: entity.area,
              normal: transformed_normal.normalize
            }
            
            # Thu thập vertices
            entity.vertices.each do |v|
              vertices_out << v.position.transform(transform)
            end
            
          elsif entity.is_a?(Sketchup::Group)
            nested_transform = transform * entity.transformation
            collect_geometry(entity.entities, nested_transform, faces_out, vertices_out)
            
          elsif entity.is_a?(Sketchup::ComponentInstance)
            nested_transform = transform * entity.transformation
            collect_geometry(entity.definition.entities, nested_transform, faces_out, vertices_out)
          end
        end
      end
      
      # Fallback: dùng bounding box nếu geometry analysis thất bại
      def self.fallback_thickness(instance)
        if instance.is_a?(Sketchup::Group)
          bounds = instance.local_bounds
        elsif instance.is_a?(Sketchup::ComponentInstance)
          bounds = instance.definition.bounds
        else
          bounds = instance.bounds
        end
        
        width = bounds.width.to_mm
        height = bounds.height.to_mm
        depth = bounds.depth.to_mm
        
        thickness = [width, height, depth].min.round(1)
        puts "[MH::MaterialApp] Fallback thickness: #{thickness}mm" if DEBUG
        thickness
      end
      
      # Lấy tên vật liệu từ Excel row
      # Sử dụng cột 'Ma_vat_lieu'
      def self.get_material_name(excel_row, thickness)
        material_code = excel_row['Ma_vat_lieu'].to_s.strip
        material_name_from_code(material_code, thickness)
      end

      def self.split_material_codes(material_code)
        MH::MaterialCode.split(material_code)
      end

      def self.multi_material_code?(material_code)
        split_material_codes(material_code).length > 1
      end

      def self.material_name_from_code(material_code, thickness, fallback_to_actual: false)
        result = MH::MaterialCode.material_name(
          material_code,
          thickness,
          mappings: MH::MaterialApp.thickness_mappings,
          fallback_to_actual: fallback_to_actual
        )
        puts "[MH::MaterialApp] Material code: #{material_code} + #{thickness}mm -> #{result}" if DEBUG && result
        result
      end

      def self.finish_group_for_material_code(material_code)
        MH::MaterialCode.finish_group(material_code)
      end

      def self.normalize_logical_material_code(value)
        MH::MaterialCode.display(value)
      end

      # Kiểm tra có phải MH_xxx không
      def self.is_mh_tag?(material_name)
        material_name.to_s =~ /^MH_/i
      end
      
      # Lấy tên tag từ MH_xxx
      def self.extract_tag_name(material_name)
        if material_name =~ /^(MH_\w+)/i
          return $1
        end
        nil
      end
    end

    # ========== MATERIAL CREATOR ==========
    module MaterialCreator
      # Các độ dày và biến thể phủ mặt cùng nhóm dùng chung hue.
      @generated_family_hues ||= {}

      def self.color_seed(name)
        name.to_s.each_byte.reduce(0) { |seed, byte| ((seed * 33) + byte) & 0xffffffff }
      end

      def self.hsl_color(hue, saturation = 0.70, lightness = 0.55)
        s = saturation
        l = lightness
        c = (1.0 - (2 * l - 1).abs) * s
        x = c * (1.0 - ((hue / 60.0) % 2 - 1).abs)
        m = l - c / 2.0

        case (hue / 60.0).floor
        when 0 then r1, g1, b1 = c, x, 0
        when 1 then r1, g1, b1 = x, c, 0
        when 2 then r1, g1, b1 = 0, c, x
        when 3 then r1, g1, b1 = 0, x, c
        when 4 then r1, g1, b1 = x, 0, c
        else        r1, g1, b1 = c, 0, x
        end

        Sketchup::Color.new(
          ((r1 + m) * 255).round,
          ((g1 + m) * 255).round,
          ((b1 + m) * 255).round
        )
      end

      def self.color_key(color)
        "#{color.red},#{color.green},#{color.blue}"
      end

      def self.color_distance_sq(left, right)
        dr = left.red.to_i - right.red.to_i
        dg = left.green.to_i - right.green.to_i
        db = left.blue.to_i - right.blue.to_i
        (dr * dr * 0.30) + (dg * dg * 0.59) + (db * db * 0.11)
      end

      # Trả về nhóm không có độ dày/biến thể bề mặt và dữ liệu tạo sắc độ.
      # MDF.17.AC, MDF.9.AC, MDF.18.AC.LK5110D.1M và .2M vì thế có cùng hue.
      def self.color_profile(name)
        text = name.to_s.strip
        family = if defined?(MH::MaterialCode)
          MH::MaterialCode.without_thickness(text).to_s.strip
        else
          ''
        end
        family = text.sub(/\.(\d+(?:[.,]\d+)?)(?=\.|\z)/, '') if family.empty?
        surface_variant = family[/\.(1M|2M|1M-BCT|2M-BCT)\z/i, 1].to_s.upcase
        family = family.sub(/\.(?:1M|2M|1M-BCT|2M-BCT)\z/i, '')
        family = 'MATERIAL' if family.empty?

        thickness = nil
        if defined?(MH::MaterialCode)
          parsed = MH::MaterialCode.parse(text)
          thickness = parsed[:layers]['do_day'] if parsed && parsed[:layers]
        end
        thickness ||= text[/\.(\d+(?:[.,]\d+)?)(?=\.|\z)/, 1]
        { family: family.upcase, thickness: thickness.to_s.tr(',', '.').to_f, surface_variant: surface_variant }
      rescue
        { family: text.to_s.upcase.empty? ? 'MATERIAL' : text.to_s.upcase, thickness: 0.0, surface_variant: '' }
      end

      # Tấm mỏng sáng hơn, tấm dày đậm hơn. Đây là trục ưu tiên số một:
      # bất kể đuôi 1M/2M, tấm dày hơn vẫn không được sáng hơn tấm mỏng hơn.
      def self.lightness_for_thickness(thickness)
        value = thickness.to_f
        return 0.50 if value <= 0
        # Bắt đầu ở 3 mm để các tấm mỏng cũng có từng màu nhận biết được:
        # 3 mm = 0.84, 8 mm = 0.64, 9 mm = 0.60, 17 mm = 0.28, 18 mm = 0.24.
        # Không được tăng giới hạn trên: trước đây 3 và 8 mm từng cùng chạm
        # trần 0.84, dẫn tới đúng cùng một màu.
        lightness = 0.84 - ((value - 3.0) * 0.04)
        [[lightness, 0.16].max, 0.84].min
      end

      # Đuôi phủ mặt chỉ là phân nhánh nhỏ trong CÙNG một độ dày.
      # 1M sáng hơn một chút, 2M đậm hơn một chút. Biên độ 0.012 nhỏ hơn
      # 1/2 bước 1 mm (0.04), nên 8 mm.2M vẫn sáng hơn 9 mm.1M; quy luật
      # "độ dày tăng => màu đậm" luôn đúng cho mọi tổ hợp.
      def self.surface_variant_lightness_offset(variant)
        case variant.to_s.upcase
        when '1M'     then 0.012
        when '2M'     then -0.012
        when '1M-BCT' then 0.006
        when '2M-BCT' then -0.006
        else 0.0
        end
      end

      def self.color_candidates_for_family(family, lightness)
        seed = color_seed(family)
        36.times.map do |i|
          hue = (seed + i * 137.508) % 360
          [hue, hsl_color(hue, 0.90, lightness)]
        end
      end

      # Chọn hue có khoảng cách RGB lớn nhất với mọi material có sẵn. Nhờ vậy
      # material MH mới không bị giống/gần giống màu đã tồn tại trong model.
      def self.family_hue(family, lightness, forbidden_colors)
        cached = @generated_family_hues[family]
        return cached if cached

        used = forbidden_colors.keys.filter_map do |rgb|
          values = rgb.to_s.split(',').map(&:to_i)
          Sketchup::Color.new(*values) if values.length == 3
        end
        candidate = color_candidates_for_family(family, lightness).each_with_index.max_by do |pair, index|
          color = pair[1]
          nearest = used.map { |other| color_distance_sq(color, other) }.min || Float::INFINITY
          [nearest, (color_seed(family) + index * 7919) % 104_729]
        end
        @generated_family_hues[family] = candidate ? candidate.first[0] : 0.0
      end

      def self.generated_color_for_name(name, forbidden_colors = nil)
        profile = color_profile(name)
        # Hue nhận theo family; độ sáng theo độ dày là trục chính và 1M/2M
        # chỉ tách nhẹ trong từng nấc độ dày. Vì vậy mọi mã của cùng family
        # đọc được theo thứ tự đậm dần khi độ dày tăng.
        base_lightness = lightness_for_thickness(profile[:thickness])
        lightness = base_lightness + surface_variant_lightness_offset(profile[:surface_variant])
        lightness = [[lightness, 0.06].max, 0.94].min
        hue = family_hue(profile[:family], lightness, forbidden_colors || {})
        hsl_color(hue, 0.90, lightness)
      end

      # Tạo hoặc lấy vật liệu trong model
      def self.get_or_create_material(model, name)
        materials = model.materials
        
        existing = materials[name]
        if existing
          return existing
        end
        
        mat = materials.add(name)
        ensure_visible_color(mat, name, model, force: true)
        
        puts "[MH::MaterialApp] Created material: #{name}" if DEBUG
        mat
      end

      # Load vật liệu từ file .skm
      def self.ensure_visible_color(material, material_name = nil, model = nil, force: false)
        return unless material
        return if material.texture
        return unless force

        key = material_name.to_s.strip
        key = material.name.to_s.strip if key.empty?
        profile = color_profile(key)
        model ||= material.model if material.respond_to?(:model)
        model ||= Sketchup.active_model if defined?(Sketchup)
        forbidden = {}
        if model && model.respond_to?(:materials)
          model.materials.each do |other|
            next if other == material || other.texture
            other_family = other.get_attribute('MH_MaterialApp', 'GeneratedColorFamily') rescue nil
            if other_family.to_s.strip.empty?
              other_key = other.get_attribute('MH_MaterialApp', 'GeneratedColorKey') rescue nil
              other_family = color_profile(other_key)[:family] unless other_key.to_s.strip.empty?
            end
            # Các độ dày cùng nhóm được phép cùng hue, chỉ khác sắc độ.
            next if other_family.to_s.strip.upcase == profile[:family]
            forbidden[color_key(other.color)] = other.name.to_s
          end
        end
        material.color = generated_color_for_name(key, forbidden)
        begin
          material.set_attribute('MH_MaterialApp', 'GeneratedColorKey', key)
          material.set_attribute('MH_MaterialApp', 'GeneratedColorFamily', profile[:family])
        rescue
        end
      end

      def self.recolor_generated_materials(model = nil)
        model ||= Sketchup.active_model if defined?(Sketchup)
        return 0 unless model && model.respond_to?(:materials)

        generated = model.materials.select do |material|
          next false if material.texture
          key = material.get_attribute('MH_MaterialApp', 'GeneratedColorKey') rescue nil
          !key.to_s.strip.empty?
        end

        @generated_family_hues = {}
        forbidden = {}
        # Chỉ các material không do MH tạo mới là màu cần tránh ngay từ đầu.
        model.materials.each do |material|
          next if material.texture || generated.include?(material)
          forbidden[color_key(material.color)] = material.name.to_s
        end

        generated.group_by do |material|
          key = material.get_attribute('MH_MaterialApp', 'GeneratedColorKey').to_s.strip
          color_profile(key.empty? ? material.name : key)[:family]
        end.sort_by { |family, _| family }.each do |family, members|
          members.sort_by { |material| material.name.to_s.upcase }.each do |material|
            key = material.get_attribute('MH_MaterialApp', 'GeneratedColorKey').to_s.strip
            key = material.name.to_s if key.empty?
            material.color = generated_color_for_name(key, forbidden)
            material.set_attribute('MH_MaterialApp', 'GeneratedColorFamily', family) rescue nil
          end
          # Xong cả nhóm mới đánh dấu forbidden: các độ dày trong nhóm không tự
          # đẩy nhau sang hue khác, nhưng nhóm tiếp theo phải tránh chúng.
          members.each { |material| forbidden[color_key(material.color)] = material.name.to_s }
        end
        model.active_view.invalidate if model.respond_to?(:active_view)
        generated.length
      end

      def self.load_material_from_file(model, material_name)
        materials = model.materials
        
        existing = materials[material_name]
        if existing
          return existing
        end
        
        file_path = File.join(MATERIAL_FOLDER, "#{material_name}.skm")
        
        if File.exist?(file_path)
          loaded = materials.load(file_path)
          begin
            loaded.name = material_name if loaded && loaded.name.to_s.strip != material_name.to_s.strip && !materials[material_name]
          rescue
          end
          ensure_visible_color(loaded, material_name, model, force: true) if loaded
          puts "[MH::MaterialApp] Loaded material from file: #{file_path}" if DEBUG
          return loaded
        else
          mat = materials.add(material_name)
          ensure_visible_color(mat, material_name, model, force: true)
          return mat
        end
      end
    end

    # ========== MATERIAL ASSIGNER ==========
    module MaterialAssigner
      MIN_SECOND_EDGE_LIMIT_MM = 15.0
      MAX_SECOND_EDGE_LIMIT_MM = 1200.0
      DEFAULT_SURFACE_FACE_RULES = [
        {
          'enabled' => '1',
          'surface_tokens' => 'LAM,LAMINATE,LK,VENE,VER',
          'max_one_side_thickness' => '9',
          'one_side_suffix' => '.1M',
          'two_side_details' => 'Đợt|Đợt Cố Định|Hông Giữa|Cánh',
          'two_side_suffix' => '.2M',
          'default_suffix' => '.1M',
          'finish_suffix_overrides' => 'LK:.1M-BCT,.2M-BCT'
        }
      ].freeze
      STATS_KEYS = [
        :success,
        :skip_no_product,
        :skip_no_match,
        :skip_no_thickness,
        :skip_second_edge,
        :skip_exceed_length,
        :skip_error,
        :processed
      ].freeze

      def self.blank_stats
        stats = Hash.new(0)
        STATS_KEYS.each { |key| stats[key] = 0 }
        stats
      end

      def self.special_tag?(instance)
        layer = instance.layer
        return false unless layer

        tag_name = layer.name
        MH::MaterialApp.tag_material_map.key?(tag_name)
      end

      # Kiểm tra tag đặc biệt MH_xxx từ layer của OBJ
      # Nếu OBJ có layer bắt đầu bằng MH_ -> load vật liệu tương ứng từ folder
      def self.check_special_tag(instance, model)
        layer = instance.layer
        return nil unless layer
        
        tag_name = layer.name
        
        # Kiểm tra có trong danh sách tag cố định không
        if MH::MaterialApp.tag_material_map.key?(tag_name)
          material_name = MH::MaterialApp.tag_material_map[tag_name]
          return MaterialCreator.load_material_from_file(model, material_name)
        end
        
        # Kiểm tra có bắt đầu bằng MH_ không (auto-detect)
        # Regex .+ để lấy toàn bộ phần sau MH_ (bao gồm cả dấu chấm)
        if false && tag_name =~ /^MH_(.+)$/i
          material_name = $1  # Lấy toàn bộ phần sau MH_ (ví dụ: Da.ni.vai)
          puts "[MH::MaterialApp] Found MH_ tag: #{tag_name} -> loading material '#{material_name}'" if DEBUG
          return MaterialCreator.load_material_from_file(model, material_name)
        end
        
        nil
      end

      # Gán vật liệu cho một instance
      def self.apply_material_to_instance(instance, material)
        instance.material = material
      end

      def self.clear_material_from_instance(instance)
        instance.material = nil if instance && instance.respond_to?(:material=)
      end

      def self.same_material_code?(left, right)
        MH::MaterialCode.same?(left, right)
      end

      def self.normalize_material_code(value)
        MH::MaterialCode.normalize(value)
      end

      def self.finish_group_for_material_code(material_code)
        group = MH::MaterialCode.finish_group(material_code)
        group.empty? ? nil : group
      end

      def self.surface_face_variant_code?(material_code)
        MH::MaterialCode.surface_variant?(material_code)
      end

      def self.base_surface_face_code(material_code)
        MH::MaterialCode.strip_surface_variant(material_code)
      end

      def self.instance_label(instance)
        label = instance.name.to_s.strip
        if label.empty? && instance.respond_to?(:definition) && instance.definition
          label = instance.definition.name.to_s.strip
        end
        label.empty? ? "Entity #{instance.entityID}" : label
      end

      def self.format_mm(value)
        number = value.to_f
        number == number.round ? number.round.to_s : format('%.1f', number)
      end

      def self.surface_face_rules
        rules = MH::MaterialApp.surface_face_rules
        rules && !rules.empty? ? rules : DEFAULT_SURFACE_FACE_RULES
      end

      def self.rule_enabled?(rule)
        value = rule['enabled'].to_s.strip.downcase
        value.empty? || %w[1 true yes y co có].include?(value)
      end

      def self.split_rule_values(value)
        value.to_s.split(/[|,;]/).map(&:strip).reject(&:empty?)
      end

      def self.surface_face_rule_for(material_name)
        material_tokens = material_name.to_s.split('.').map { |token| token.strip.upcase }.reject(&:empty?)

        surface_face_rules.find do |rule|
          next false unless rule_enabled?(rule)

          rule_tokens = split_rule_values(rule['surface_tokens']).map(&:upcase)
          next false if rule_tokens.empty?

          material_tokens.any? do |material_token|
            rule_tokens.any? { |rule_token| material_token.start_with?(rule_token) }
          end
        end
      end

      def self.strip_face_suffix(material_name)
        MH::MaterialCode.strip_surface_variant(material_name)
      end

      def self.two_side_detail?(instance, parsed = nil, rule = nil)
        detail = parsed && parsed[:detail_name].to_s.strip
        detail = instance_label(instance) if detail.nil? || detail.empty?
        detail_key = MaterialMatcher.match_key(detail)
        detail_keys = split_rule_values(rule && rule['two_side_details']).map { |value| MaterialMatcher.match_key(value) }
        # Khop TRON-TU (whole word), khong phai chuoi-con tuy tien: tu khoa loai
        # chi tiet ("canh", "dot co dinh"...) phai xuat hien nhu mot tu/cum tu
        # day du trong ten chi tiet. Vd "CĐ-Cánh Phải" -> "cd canh phai" chua tu
        # "canh" => 2 mat. Tranh "canhxyz" an nham nho dem khoang trang 2 dau.
        padded = " #{detail_key} "
        detail_keys.any? { |key| !key.empty? && (detail_key == key || padded.include?(" #{key} ")) }
      end

      def self.surface_face_suffix_override(rule, material_name)
        group = finish_group_for_material_code(material_name).to_s.upcase
        return nil if group.empty?

        overrides = rule['finish_suffix_overrides'].to_s
        if overrides.strip.empty? && group == 'LK'
          return ['.1M-BCT', '.2M-BCT', '.1M-BCT']
        end

        overrides.split(/[;|]/).each do |entry|
          key, value = entry.to_s.split(':', 2)
          next unless key && value
          next unless key.strip.upcase == group

          suffixes = value.split(/[,\s]+/).map(&:strip).reject(&:empty?)
          one_side = suffixes[0]
          two_side = suffixes[1] || one_side
          default = suffixes[2] || one_side
          return [one_side, two_side, default]
        end

        nil
      end

      def self.material_face_suffix_for(instance, thickness, parsed = nil, rule = nil, material_name = nil)
        rule ||= DEFAULT_SURFACE_FACE_RULES.first
        limit = rule['max_one_side_thickness'].to_s.gsub(',', '.').to_f
        one_side_suffix = rule['one_side_suffix'].to_s.strip
        one_side_suffix = '.1M' if one_side_suffix.empty?
        two_side_suffix = rule['two_side_suffix'].to_s.strip
        two_side_suffix = '.2M' if two_side_suffix.empty?
        default_suffix = rule['default_suffix'].to_s.strip
        default_suffix = one_side_suffix if default_suffix.empty?
        if material_name
          override = surface_face_suffix_override(rule, material_name)
          if override
            one_side_suffix = override[0] unless override[0].to_s.empty?
            two_side_suffix = override[1] unless override[1].to_s.empty?
            default_suffix = override[2] unless override[2].to_s.empty?
          end
        end

        return one_side_suffix if limit > 0 && thickness.to_f <= limit

        two_side_detail?(instance, parsed, rule) ? two_side_suffix : default_suffix
      end

      def self.apply_surface_face_suffix(material_name, instance, thickness, parsed = nil)
        base_name = strip_face_suffix(material_name)
        rule = surface_face_rule_for(base_name)
        return material_name unless rule

        base_name + material_face_suffix_for(instance, thickness, parsed, rule, base_name)
      end

      def self.second_edge_out_of_range?(dimensions, instance = nil)
        second_edge = dimensions[1].to_f
        second_edge > 0 && (second_edge < MIN_SECOND_EDGE_LIMIT_MM || second_edge > MAX_SECOND_EDGE_LIMIT_MM)
      end

      def self.second_edge_skip_message(instance, dimensions)
        second_edge = dimensions[1].to_f
        operator = second_edge > MAX_SECOND_EDGE_LIMIT_MM ? ">" : "<"
        limit = second_edge > MAX_SECOND_EDGE_LIMIT_MM ? MAX_SECOND_EDGE_LIMIT_MM : MIN_SECOND_EDGE_LIMIT_MM
        "Khong gan: #{instance_label(instance)} canh thu 2 #{format_mm(second_edge)} #{operator} #{format_mm(limit)}mm"
      end

      def self.second_edge_too_small?(dimensions, instance = nil)
        second_edge_out_of_range?(dimensions, instance)
      end

      def self.filter_second_edge_target_groups(target_groups, stats = nil, clear_material = false)
        target_groups.each_with_object([]) do |group, kept_groups|
          kept_targets = []

          group[:targets].each do |target|
            dimensions = MaterialCodeBuilder.get_dimensions(target)
            if second_edge_out_of_range?(dimensions, target)
              clear_material_from_instance(target) if clear_material
              add_skip_detail(stats, second_edge_skip_message(target, dimensions)) if stats && clear_material
            else
              kept_targets << target
            end
          end

          kept_groups << group.merge(targets: kept_targets) unless kept_targets.empty?
        end
      end

      def self.add_skip_detail(stats, message)
        return unless stats && stats[:details].respond_to?(:<<)

        stats[:details] << message
      end

      def self.stats_hash(stats, key)
        return nil unless stats

        stats[key] = {} unless stats.key?(key) && stats[key].is_a?(Hash)
        stats[key]
      end

      def self.row_choice_label(row)
        [
          row['Ma_SP'].to_s.strip,
          row['Ten_SP'].to_s.strip,
          row['Ten_chi_tiet'].to_s.strip,
          row['Ma_vat_lieu'].to_s.strip
        ].reject(&:empty?).join(' - ')
      end

      def self.choose_excel_row_by_detail(detail_name, stats = nil)
        detail_key = MaterialMatcher.match_key(detail_name)
        return nil if detail_key.empty?

        cache = stats_hash(stats, :row_choice_cache)
        return cache[detail_key] if cache && cache.key?(detail_key)

        rows = MaterialMatcher.rows_for_detail_name(detail_name)
        rows.uniq!
        if rows.empty?
          cache[detail_key] = nil if cache
          return nil
        end

        if rows.length == 1
          cache[detail_key] = rows.first if cache
          return rows.first
        end

        labels = rows.map { |row| row_choice_label(row) }
        input = UI.inputbox(
          ["Chon SP cho #{detail_name}:"],
          [labels.first],
          labels.join('|'),
          "Chon SP theo quy cach"
        )

        unless input
          cache[detail_key] = nil if cache
          return nil
        end

        selected = labels.index(input[0].to_s) || 0
        cache[detail_key] = rows[selected] if cache
        rows[selected]
      end

      def self.child_entities(instance)
        if instance.is_a?(Sketchup::Group)
          instance.entities
        elsif instance.is_a?(Sketchup::ComponentInstance)
          instance.definition.entities
        else
          []
        end
      end

      def self.child_material_label(entity)
        label = entity.name.to_s.strip
        if label.empty? && entity.respond_to?(:definition) && entity.definition
          label = entity.definition.name.to_s.strip
        end
        return nil if label.empty?
        return nil if label =~ /\AGroup#\d+\z/i

        label
      end

      def self.named_child_material_targets(instance)
        grouped = {}
        child_entities(instance).each do |child|
          next unless child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)

          label = child_material_label(child)
          next unless label

          grouped[label] ||= []
          grouped[label] << child
        end
        grouped
      end

      def self.multi_material_options(raw_codes, thickness)
        raw_codes.each_with_object([]) do |raw_code, options|
          material_name = material_name_for_multi_code(raw_code, thickness)
          next unless material_name

          options << { code: raw_code, material_name: material_name }
        end
      end

      def self.material_name_for_multi_code(raw_code, thickness)
        MaterialCodeBuilder.material_name_from_code(raw_code, thickness)
      end

      def self.multi_material_options_for_targets(raw_codes, targets)
        option_codes = []

        targets.each do |target|
          thickness = MaterialCodeBuilder.get_dimensions(target)[0]
          multi_material_options(raw_codes, thickness).each do |option|
            option_codes << option[:code] unless option_codes.any? { |code| same_material_code?(code, option[:code]) }
          end
        end

        option_codes
      end

      def self.option_for_code(options, code)
        options.find { |option| same_material_code?(option[:code], code) } ||
          options.find { |option| same_material_code?(option[:material_name], code) }
      end

      def self.multi_choice_detail_label(instance)
        parsed = InstanceNameParser.parse(instance_label(instance))
        detail = parsed[:detail_name].to_s.strip
        detail.empty? ? instance_label(instance) : detail
      end

      def self.multi_material_prompt_label(instance, excel_row, label = nil)
        raw_label = label.to_s.strip
        raw_label = instance_label(instance) if raw_label.empty?
        parsed_label = InstanceNameParser.parse(raw_label)
        detail = parsed_label[:detail_name].to_s.strip
        detail = raw_label if detail.empty?

        row_code = MaterialMatcher.product_code_from_text(excel_row['Ma_SP'])
        if row_code.empty?
          parsed_instance = InstanceNameParser.parse(instance_label(instance))
          code = parsed_instance[:product_code].to_s.strip
        else
          code = row_code
        end

        code.empty? ? detail : "#{code}_#{detail}"
      end

      def self.material_label_match?(label, detail_name)
        label_key = MaterialMatcher.match_key(label)
        detail_key = MaterialMatcher.match_key(detail_name)
        return false if label_key.empty? || detail_key.empty?

        label_key.include?(detail_key) || detail_key.include?(label_key)
      end

      def self.multi_material_target_groups(instance, parsed, excel_row)
        detail_name = excel_row['Ten_chi_tiet'].to_s.strip
        detail_name = parsed[:detail_name].to_s.strip if detail_name.empty?
        grouped = {}

        child_entities(instance).each do |child|
          next unless child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)

          label = child_material_label(child)
          next unless label
          next unless material_label_match?(label, detail_name)

          grouped[label] ||= []
          grouped[label] << child
        end

        if grouped.empty?
          grouped[instance_label(instance)] = [instance]
        end

        grouped.map { |label, targets| { label: label, targets: targets } }
      end

      def self.multi_material_choice_key(instance, excel_row, raw_codes, label = nil)
        choice_label = multi_material_prompt_label(instance, excel_row, label)

        [
          excel_row['Ma_SP'].to_s.strip,
          choice_label,
          raw_codes.join(' & ')
        ].join('|')
      end

      def self.prepare_multi_material_choices(targets, stats)
        cache = stats_hash(stats, :multi_material_choice_cache)
        entries_by_key = {}

        targets.each do |entity|
          name = instance_label(entity)
          parsed = InstanceNameParser.parse(name)
          next unless parsed[:product_code]

          excel_row = MaterialMatcher.find_matching_row(parsed)
          next unless excel_row

          raw_codes = MaterialCodeBuilder.split_material_codes(excel_row['Ma_vat_lieu'].to_s.strip)
          next unless raw_codes.length > 1

          thickness = MaterialCodeBuilder.get_thickness(entity)
          target_groups = filter_second_edge_target_groups(multi_material_target_groups(entity, parsed, excel_row))
          target_groups.each do |group|
            option_codes = multi_material_options_for_targets(raw_codes, group[:targets])
            next if option_codes.empty?

            choice_key = multi_material_choice_key(entity, excel_row, raw_codes, group[:label])
            next if cache.key?(choice_key) || entries_by_key.key?(choice_key)

            entries_by_key[choice_key] = {
              label: multi_material_prompt_label(entity, excel_row, group[:label]),
              default: option_codes.first,
              list: option_codes.join('|')
            }
          end
        end

        return true if entries_by_key.empty?

        keys = entries_by_key.keys
        entries = keys.map { |key| entries_by_key[key] }
        prompts = entries.map { |entry| "#{entry[:label]}:" }
        defaults = entries.map { |entry| entry[:default] }
        lists = entries.map { |entry| entry[:list] }
        input = UI.inputbox(prompts, defaults, lists, "Chon vat lieu")

        return false unless input

        keys.each_with_index do |key, index|
          cache[key] = input[index].to_s
        end

        true
      end

      def self.assign_multi_material_to_instance(instance, model, raw_codes, thickness, excel_row, stats = nil)
        options = multi_material_options(raw_codes, thickness)
        if options.empty?
          parsed = InstanceNameParser.parse(instance_label(instance))
          multi_material_target_groups(instance, parsed, excel_row).each do |group|
            group[:targets].each { |target| clear_material_from_instance(target) }
          end
          add_skip_detail(stats, "Khong gan: #{instance_label(instance)} chua map do day cho #{raw_codes.join(' & ')}")
          return :skip_no_thickness
        end

        cache = stats_hash(stats, :multi_material_choice_cache)
        parsed = InstanceNameParser.parse(instance_label(instance))
        target_groups = filter_second_edge_target_groups(multi_material_target_groups(instance, parsed, excel_row), stats, true)
        if target_groups.empty?
          return :skip_second_edge
        end
        local_choices = {}
        missing_groups = target_groups.select do |group|
          key = multi_material_choice_key(instance, excel_row, raw_codes, group[:label])
          !cache || !cache.key?(key)
        end

        if missing_groups.any?
          prompts = missing_groups.map { |group| "#{multi_material_prompt_label(instance, excel_row, group[:label])}:" }
          option_lists = missing_groups.map { |group| multi_material_options_for_targets(raw_codes, group[:targets]) }
          defaults = option_lists.map { |codes| codes.first || raw_codes.first }
          lists = option_lists.map { |codes| codes.join('|') }
          title = "Chon vat lieu cho #{instance_label(instance)}"
          input = UI.inputbox(prompts, defaults, lists, title)

          unless input
            add_skip_detail(stats, "Khong gan: #{instance_label(instance)} huy chon VL")
            return :skip_error
          end

          missing_groups.each_with_index do |group, index|
            key = multi_material_choice_key(instance, excel_row, raw_codes, group[:label])
            if cache
              cache[key] = input[index].to_s
            else
              local_choices[key] = input[index].to_s
            end
          end
        end

        assigned = 0
        target_groups.each do |group|
          key = multi_material_choice_key(instance, excel_row, raw_codes, group[:label])
          chosen_code = cache ? cache[key] : local_choices[key]
          option = option_for_code(options, chosen_code)
          next unless option

          material = MaterialCreator.load_material_from_file(model, option[:material_name])
          group[:targets].each do |target|
            apply_material_to_instance(target, material)
            assigned += 1
          end
        end

        if assigned.zero?
          add_skip_detail(stats, "Khong gan: #{instance_label(instance)} chua chon vat lieu")
          return :skip_error
        end

        puts "[MH::MaterialApp] Assigned multi material #{raw_codes.join(' & ')} to #{assigned} target(s) in '#{instance_label(instance)}'" if DEBUG
        :success
      end

      def self.assign_multi_material_to_children(instance, model, raw_codes, thickness, stats = nil)
        grouped_targets = named_child_material_targets(instance)
        if grouped_targets.empty?
          grouped_targets[instance_label(instance)] = [instance]
        end
        grouped_targets = filter_second_edge_target_groups(
          grouped_targets.map { |label, targets| { label: label, targets: targets } },
          stats,
          true
        ).each_with_object({}) do |group, memo|
          memo[group[:label]] = group[:targets]
        end
        return :skip_second_edge if grouped_targets.empty?

        options = multi_material_options(raw_codes, thickness)
        if options.empty?
          grouped_targets.values.flatten.each { |target| clear_material_from_instance(target) }
          add_skip_detail(stats, "Khong gan: #{instance_label(instance)} chua map do day cho #{raw_codes.join(' & ')}")
          return :skip_no_thickness
        end

        option_codes = options.map { |option| option[:code] }
        labels = grouped_targets.keys
        choice_cache = stats_hash(stats, :multi_material_choice_cache)
        cache_key_prefix = raw_codes.join(' & ')
        input = nil

        if !choice_cache || labels.any? { |label| !choice_cache.key?([cache_key_prefix, label]) }
          prompts = labels.map { |label| "#{label}:" }
          defaults = labels.map { |label| (choice_cache && choice_cache[[cache_key_prefix, label]]) || option_codes.first }
          lists = labels.map { option_codes.join('|') }
          title = "Chon vat lieu cho #{instance_label(instance)}"
          input = UI.inputbox(prompts, defaults, lists, title)

          unless input
            add_skip_detail(stats, "Khong gan: #{instance_label(instance)} huy chon VL")
            return :skip_error
          end

          labels.each_with_index do |label, index|
            choice_cache[[cache_key_prefix, label]] = input[index].to_s if choice_cache
          end
        end

        assigned = 0
        labels.each_with_index do |label, index|
          chosen_code =
            if choice_cache
              choice_cache[[cache_key_prefix, label]]
            else
              input[index].to_s
            end
          option = option_for_code(options, chosen_code)
          next unless option

          material = MaterialCreator.load_material_from_file(model, option[:material_name])
          grouped_targets[label].each do |target|
            apply_material_to_instance(target, material)
            assigned += 1
          end
        end

        if assigned.zero?
          add_skip_detail(stats, "Khong gan: #{instance_label(instance)} chua chon vat lieu")
          return :skip_error
        end

        puts "[MH::MaterialApp] Assigned multi materials #{raw_codes.join(' & ')} inside '#{instance_label(instance)}'" if DEBUG
        :success
      end

      def self.assign_to_instance(instance, model, stats = nil)
        dimensions = MaterialCodeBuilder.get_dimensions(instance)
        if second_edge_too_small?(dimensions, instance)
          clear_material_from_instance(instance)
          add_skip_detail(stats, second_edge_skip_message(instance, dimensions))
          return :skip_second_edge
        end

        special_material = check_special_tag(instance, model)
        if special_material
          apply_material_to_instance(instance, special_material)
          puts "[MH::MaterialApp] Assigned special tag material '#{special_material.name}' to '#{instance.name}'" if DEBUG
          return :success
        end

        # Parse tên và match với Excel
        name = instance.name.to_s.strip
        name = instance_label(instance) if name.empty?
        parsed = InstanceNameParser.parse(name)
        
        unless parsed[:product_code]
          puts "[MH::MaterialApp] Skip: Cannot parse product code from '#{name}'" if DEBUG
          add_skip_detail(stats, "Khong gan: #{instance_label(instance)} khong co ma SP")
          return :skip_no_product
        end
        
        # Tìm dòng Excel match
        excel_row = MaterialMatcher.find_matching_row(parsed)
        
        unless excel_row
          puts "[MH::MaterialApp] Skip: No Excel match for '#{name}'" if DEBUG
          add_skip_detail(stats, "Khong gan: #{instance_label(instance)} khong khop Excel")
          return :skip_no_match
        end
        
        # Lấy độ dày và chiều dài
        thickness = dimensions[0]
        length = dimensions[2]
        
        # Kiểm tra chiều dài vượt quá mức cho phép
        if MH::MaterialApp.max_length_limit > 0 && length > MH::MaterialApp.max_length_limit
          puts "[MH::MaterialApp] Skip: Length #{length} > limit #{MH::MaterialApp.max_length_limit} for '#{name}'" if DEBUG
          add_skip_detail(stats, "Khong gan: #{instance_label(instance)} dai #{format_mm(length)} > Lmax #{format_mm(MH::MaterialApp.max_length_limit)}")
          return :skip_exceed_length
        end
        
        # Lấy tên vật liệu từ Excel
        raw_mat = excel_row['Ma_vat_lieu'].to_s.strip
        raw_material_codes = MaterialCodeBuilder.split_material_codes(raw_mat)

        if raw_material_codes.length > 1
          return assign_multi_material_to_instance(instance, model, raw_material_codes, thickness, excel_row, stats)
        end

        material_name = material_name_for_multi_code(raw_mat, thickness)
        
        unless material_name
          puts "[MH::MaterialApp] Skip: No material mapped for thickness #{thickness} on '#{name}'" if DEBUG
          add_skip_detail(stats, "Khong gan: #{instance_label(instance)} chua map day #{format_mm(thickness)}")
          return :skip_no_thickness
        end

        material_name = apply_surface_face_suffix(material_name, instance, thickness, parsed)
        
        puts "[MH::MaterialApp] Ma_vat_lieu: '#{excel_row['Ma_vat_lieu']}' -> material: '#{material_name}'" if DEBUG
        
        # Load vật liệu từ folder hoặc tạo mới
        material = MaterialCreator.load_material_from_file(model, material_name)
        
        # Gán vật liệu
        apply_material_to_instance(instance, material)
        
        puts "[MH::MaterialApp] Assigned '#{material_name}' to '#{name}' (thickness: #{thickness}mm)" if DEBUG
        :success
      rescue => e
        MH::MaterialApp.dbg("[MH::MaterialApp] Error assigning material to '#{instance.name}': #{e.message}")
        puts e.backtrace.first(5).join("\n") if DEBUG
        add_skip_detail(stats, "Khong gan: #{instance_label(instance)} loi #{e.message}")
        :skip_error
      end

      # Gán cho selection
      def self.assign_to_selection(show_alert = true)
        model = Sketchup.active_model
        selection = model.selection
        MH::MaterialApp::ConfigLoader.load_all
        MH::MaterialApp.ensure_excel_data_loaded if MH::MaterialApp.excel_data.empty? && MH::MaterialApp.respond_to?(:ensure_excel_data_loaded)
        
        selection_has_special_tags = false
        selection.each do |entity|
          if (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) && special_tag?(entity)
            selection_has_special_tags = true
            break
          end
        end

        if MH::MaterialApp.excel_data.empty? && !selection_has_special_tags
          return { error: "Chưa import Excel!" }
        end
        
        if selection.empty?
          return { error: "Chưa chọn đối tượng!" }
        end
        
        model.start_operation("Assign Materials to Selection", true)
        
        stats = blank_stats
        stats[:details] = []

        targets = []
        selection.each do |entity|
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

          targets << entity
        end
        targets.uniq!
        stats[:processed] = targets.length

        unless prepare_multi_material_choices(targets, stats)
          model.abort_operation
          return { error: "Huy chon vat lieu" }
        end

        targets.each do |entity|
          result = assign_to_instance(entity, model, stats)
          stats[result] += 1
        end
        
        model.commit_operation
        
        MH::MaterialApp.notify("✅ Gán VL: Thành công #{stats[:success]}, Bỏ qua tên #{stats[:skip_no_product] + stats[:skip_no_match]}, Lỗi độ dày #{stats[:skip_no_thickness]}, Cạnh nhỏ #{stats[:skip_second_edge]}, Dài quá khổ #{stats[:skip_exceed_length]}, Lỗi khác #{stats[:skip_error]}")
        stats
      end

      # Gán cho toàn bộ model
      def self.assign_to_all(show_alert = true)
        model = Sketchup.active_model
        MH::MaterialApp::ConfigLoader.load_all
        MH::MaterialApp.ensure_excel_data_loaded if MH::MaterialApp.excel_data.empty? && MH::MaterialApp.respond_to?(:ensure_excel_data_loaded)
        
        targets = []
        model.entities.each do |entity|
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

          targets << entity
        end

        model_entities_have_special_tags = targets.any? { |entity| special_tag?(entity) }

        if MH::MaterialApp.excel_data.empty? && !model_entities_have_special_tags
          return { error: "Chưa import Excel!" }
        end
        
        model.start_operation("Assign Materials to All", true)
        
        stats = blank_stats
        stats[:details] = []
        stats[:processed] = targets.length

        unless prepare_multi_material_choices(targets, stats)
          model.abort_operation
          return { error: "Huy chon vat lieu" }
        end
        
        targets.each do |entity|
          result = assign_to_instance(entity, model, stats)
          stats[result] += 1
        end
        
        model.commit_operation
        
        MH::MaterialApp.notify("✅ Gán toàn bộ: Thành công #{stats[:success]}, Bỏ qua tên #{stats[:skip_no_product] + stats[:skip_no_match]}, Lỗi độ dày #{stats[:skip_no_thickness]}, Cạnh nhỏ #{stats[:skip_second_edge]}, Dài quá khổ #{stats[:skip_exceed_length]}, Lỗi khác #{stats[:skip_error]}")
        stats
      end
    end

    # ========== UI FUNCTIONS ==========
    def self.load_configs
      ConfigLoader.load_all
      notify("✅ Đã load configs từ folder:\n#{CONFIG_DIR}")
    end

    # Lưu đường dẫn file Excel cuối cùng để refresh
    @last_excel_path = nil
    
    def self.last_excel_path; @last_excel_path; end
    def self.last_excel_path=(v)
      remember_excel_path(v)
    end

    def self.model_excel_default_key(model = Sketchup.active_model)
      return nil unless model && model.respond_to?(:path)
      model_path = model.path.to_s
      return nil if model_path.empty?

      DEFAULT_LAST_EXCEL_PREFIX + model_path.downcase
    end

    def self.remember_excel_path(file_path, model = Sketchup.active_model)
      file_path = file_path.to_s.strip
      return nil if file_path.empty?

      @last_excel_path = file_path
      model.set_attribute(MODEL_ATTR_DICT, ATTR_LAST_EXCEL_PATH, file_path) rescue nil

      key = model_excel_default_key(model)
      # forward-slash: read_default EVAL lại chuỗi → path backslash Windows gây lỗi.
      Sketchup.write_default(MODEL_ATTR_DICT, key, file_path.tr('\\', '/')) if key

      file_path
    end

    def self.restore_last_excel_path(model = Sketchup.active_model)
      return @last_excel_path unless model && model.respond_to?(:get_attribute)
      model_path = model.get_attribute(MODEL_ATTR_DICT, ATTR_LAST_EXCEL_PATH) rescue nil
      default_key = model_excel_default_key(model)
      default_path = default_key ? Sketchup.read_default(MODEL_ATTR_DICT, default_key) : nil

      path = model_path.to_s.strip.empty? ? default_path.to_s.strip : model_path.to_s.strip
      @last_excel_path = path unless path.empty?
      @last_excel_path
    end

    # Throttle: khi không có Excel/JSON, @excel_data luôn rỗng → mỗi lần gọi sẽ
    # quét lại SPEC/Data (Dir.glob) + read_default. Bị gọi nhiều lần mỗi lần đặt
    # DC (per group trong resolve_product_materials) → LAG. Chỉ thử lại sau
    # EXCEL_LOAD_RETRY_TTL giây nếu vẫn rỗng. Có dữ liệu thì guard đầu return ngay.
    EXCEL_LOAD_RETRY_TTL = 4.0 unless defined?(EXCEL_LOAD_RETRY_TTL)
    @excel_load_attempt_at = 0.0

    def self.reset_excel_load_throttle
      @excel_load_attempt_at = 0.0
    end

    def self.ensure_excel_data_loaded
      return true unless @excel_data.empty?

      now = Time.now.to_f
      @excel_load_attempt_at ||= 0.0
      return false if (now - @excel_load_attempt_at) < EXCEL_LOAD_RETRY_TTL
      @excel_load_attempt_at = now

      # Primary: tìm JSON từ SPEC/Data/ qua MH_Registry
      if try_load_from_registry
        puts "[MH::MaterialApp] Auto loaded from Registry (SPEC)" if DEBUG
        return true
      end

      # Fallback: đường dẫn cũ (lưu trong model attributes)
      restore_last_excel_path
      return false unless @last_excel_path && File.exist?(@last_excel_path)

      puts "[MH::MaterialApp] Auto import Excel for model: #{@last_excel_path}" if DEBUG
      do_import(@last_excel_path)
      true
    end

    def self.try_load_from_registry
      return false unless defined?(MH::RegistryApp) && defined?(MH::RegistryApp::Connector)
      connector = MH::RegistryApp::Connector.get('material_assign')
      return false unless connector && connector.available?

      # 1. Nguồn chung runtime: Registry luôn trả JSON dữ liệu mới nhất trong
      # SPEC/Data (do MH Thongke Desktop tạo). Không lấy Excel/path cũ trước.
      runtime_json = (MH::RegistryApp.last_mvl_json_path rescue '').to_s.strip
      if !runtime_json.empty? && File.exist?(runtime_json) && connector.respond_to?(:load_from_json)
        connector.load_from_json(runtime_json)
        connector.mark_loaded_data(runtime_json) if connector.respond_to?(:mark_loaded_data)
        connector.clear_material_names_cache if connector.respond_to?(:clear_material_names_cache)
        return true if @excel_data.length > 0
      end

      # 2. Thử path Excel đã nhớ trước đó (tương thích file cũ)
      registry_path = (MH::RegistryApp.last_mvl_input_path rescue nil).to_s.strip
      paths = [restore_last_excel_path, registry_path].map { |path| path.to_s.strip }.reject(&:empty?).uniq
      paths.each do |path|
        next unless File.exist?(path)

        result = connector.load_data(path)
        return true if result && result['ok'] && @excel_data.length > 0
      end

      # 3. Scan SPEC/Data/ tìm JSON mới nhất
      spec_data = MH::RegistryApp.spec_data_dir rescue nil
      if spec_data && Dir.exist?(spec_data)
        jsons = Dir.glob("#{spec_data.to_s.tr('\\\\', '/')}/*.json").sort_by { |f| File.mtime(f) }.reverse
        jsons.each do |json_path|
          begin
            import_json(json_path)
            if @excel_data.length > 0
              # Nhớ xlsx tương ứng
              xlsx_name = File.basename(json_path, '.json') + '.xlsx'
              xlsx_path = File.join(MH::RegistryApp.spec_dir, xlsx_name)
              remember_excel_path(xlsx_path) if File.exist?(xlsx_path)
              puts "[MH::MaterialApp] Auto loaded from SPEC/Data: #{File.basename(json_path)}" if DEBUG
              return true
            end
          rescue => e
            puts "[MH::MaterialApp] Skip JSON #{json_path}: #{e.message}" if DEBUG
          end
        end
      end

      # 4. Scan SPEC/ tìm xlsx mới nhất
      spec = MH::RegistryApp.spec_dir rescue nil
      if spec && Dir.exist?(spec)
        xlsxs = Dir.glob("#{spec.to_s.tr('\\\\', '/')}/*.xlsx").sort_by { |f| File.mtime(f) }.reverse
        xlsxs.each do |xlsx_path|
          begin
            do_import(xlsx_path)
            if @excel_data.length > 0
              remember_excel_path(xlsx_path)
              puts "[MH::MaterialApp] Auto loaded from SPEC: #{File.basename(xlsx_path)}" if DEBUG
              return true
            end
          rescue => e
            puts "[MH::MaterialApp] Skip XLSX #{xlsx_path}: #{e.message}" if DEBUG
          end
        end
      end

      false
    rescue => e
      puts "[MH::MaterialApp] Registry load failed: #{e.message}" if DEBUG
      false
    end
    
    def self.import_excel_data
      file_path = UI.openpanel("Chọn file dữ liệu vật liệu", "", "All Supported|*.xlsx;*.csv;*.json|Excel|*.xlsx|CSV|*.csv|JSON|*.json||")
      return unless file_path

      remember_excel_path(file_path)
      do_import(file_path)
    end
    
    def self.refresh_excel_data
      restore_last_excel_path
      unless @last_excel_path && File.exist?(@last_excel_path)
        notify("⚠️ Chưa có file Excel nào được import trước đó!\nVui lòng dùng 'Import Excel/CSV' trước.")
        return
      end
      
      # Xóa dữ liệu cũ
      @excel_data = []
      do_import(@last_excel_path)
    end
    
    def self.do_import(file_path)
      # Load configs nếu chưa có
      ConfigLoader.load_all if @header_columns.empty?

      # Sync config từ MH_Registry nếu có
      if defined?(MH::RegistryApp::Connector)
        MH::RegistryApp::Connector.dispatch('material_assign', :sync_config) rescue nil
      end

      if file_path.downcase.end_with?('.json')
        import_json(file_path)
      elsif file_path.downcase.end_with?('.csv')
        CSVReader.import(file_path)
      elsif file_path.downcase.end_with?('.xlsx')
        ExcelReader.import(file_path)
      else
        notify("Khong ho tro dinh dang file nay: #{File.extname(file_path)}")
      end
    end

    def self.import_json(file_path)
      @excel_data = []
      begin
        raw = File.read(file_path, encoding: 'UTF-8')
        data = JSON.parse(raw)
        @excel_data = data.is_a?(Array) ? data : []
        puts "[MH::MaterialApp] Imported #{@excel_data.length} records from JSON" if DEBUG
        notify("Da import #{@excel_data.length} dong du lieu tu JSON!")
      rescue => e
        notify("Loi import JSON: #{e.message}")
        puts "[MH::MaterialApp] JSON Error: #{e.message}" if DEBUG
      end
    end

    def self.assign_to_selection(show_alert = true)
      MaterialAssigner.assign_to_selection(show_alert)
    end

    def self.assign_to_all(show_alert = true)
      MaterialAssigner.assign_to_all(show_alert)
    end



    def self.view_configs
      msg = "=== Configs đã load ===\n\n"
      msg += "📁 Config folder: #{CONFIG_DIR}\n\n"
      msg += "Mã SP: #{@product_codes.length} mã\n"
      msg += "Tên Modul: #{@module_names.length} tên\n"
      msg += "Thickness Mapping: #{@thickness_mappings.length} quy tắc\n"
      msg += "Header Columns: #{@header_columns.length} cột\n"
      
      UI.messagebox(msg)
    end

    # Debug thickness của object được chọn
    def self.debug_thickness
      model = Sketchup.active_model
      selection = model.selection
      
      if selection.empty?
        notify("⚠️ Chưa chọn đối tượng!")
        return
      end
      
      entity = selection.first
      
      unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        notify("⚠️ Chọn Group hoặc Component!")
        return
      end
      
      msg = "=== DEBUG THICKNESS ===\n\n"
      msg += "📦 Tên: #{entity.name}\n"
      msg += "📦 Loại: #{entity.class}\n\n"
      
      if entity.is_a?(Sketchup::Group)
        bounds = entity.local_bounds
        msg += "--- Group Local Bounds ---\n"
        msg += "Width: #{bounds.width.to_mm.round(2)} mm\n"
        msg += "Height: #{bounds.height.to_mm.round(2)} mm\n"
        msg += "Depth: #{bounds.depth.to_mm.round(2)} mm\n"
        msg += "Min: #{[bounds.width, bounds.height, bounds.depth].map { |d| d.to_mm.round(2) }.min} mm\n\n"
        
        # World bounds
        world_bounds = entity.bounds
        msg += "--- Group World Bounds ---\n"
        msg += "Width: #{world_bounds.width.to_mm.round(2)} mm\n"
        msg += "Height: #{world_bounds.height.to_mm.round(2)} mm\n"
        msg += "Depth: #{world_bounds.depth.to_mm.round(2)} mm\n"
        
      elsif entity.is_a?(Sketchup::ComponentInstance)
        def_bounds = entity.definition.bounds
        msg += "--- Definition Bounds (gốc) ---\n"
        msg += "Width: #{def_bounds.width.to_mm.round(2)} mm\n"
        msg += "Height: #{def_bounds.height.to_mm.round(2)} mm\n"
        msg += "Depth: #{def_bounds.depth.to_mm.round(2)} mm\n\n"
        
        # Transformation info
        transform = entity.transformation
        m = transform.to_a
        scale_x = Math.sqrt(m[0]**2 + m[1]**2 + m[2]**2)
        scale_y = Math.sqrt(m[4]**2 + m[5]**2 + m[6]**2)
        scale_z = Math.sqrt(m[8]**2 + m[9]**2 + m[10]**2)
        
        msg += "--- Transformation Scale ---\n"
        msg += "Scale X: #{scale_x.round(4)}\n"
        msg += "Scale Y: #{scale_y.round(4)}\n"
        msg += "Scale Z: #{scale_z.round(4)}\n\n"
        
        # World bounds
        world_bounds = entity.bounds
        msg += "--- Instance World Bounds ---\n"
        msg += "Width: #{world_bounds.width.to_mm.round(2)} mm\n"
        msg += "Height: #{world_bounds.height.to_mm.round(2)} mm\n"
        msg += "Depth: #{world_bounds.depth.to_mm.round(2)} mm\n\n"
        
        # Transformed corners
        min_pt = def_bounds.min
        max_pt = def_bounds.max
        
        corner_0 = Geom::Point3d.new(min_pt.x, min_pt.y, min_pt.z)
        corner_x = Geom::Point3d.new(max_pt.x, min_pt.y, min_pt.z)
        corner_y = Geom::Point3d.new(min_pt.x, max_pt.y, min_pt.z)
        corner_z = Geom::Point3d.new(min_pt.x, min_pt.y, max_pt.z)
        
        pt_0 = corner_0.transform(transform)
        pt_x = corner_x.transform(transform)
        pt_y = corner_y.transform(transform)
        pt_z = corner_z.transform(transform)
        
        edge_x = pt_0.distance(pt_x).to_mm
        edge_y = pt_0.distance(pt_y).to_mm
        edge_z = pt_0.distance(pt_z).to_mm
        
        msg += "--- Transformed Edge Lengths ---\n"
        msg += "Edge X: #{edge_x.round(2)} mm\n"
        msg += "Edge Y: #{edge_y.round(2)} mm\n"
        msg += "Edge Z: #{edge_z.round(2)} mm\n"
        msg += "Min (thickness): #{[edge_x, edge_y, edge_z].min.round(2)} mm\n"
      end
      
      # Kết quả từ function
      thickness = MaterialCodeBuilder.get_thickness(entity)
      msg += "\n=== KẾT QUẢ ===\n"
      msg += "Thickness từ function: #{thickness} mm\n"
      
      # Thickness mapping
      mapped = MaterialCodeBuilder.map_thickness(thickness)
      msg += "Mapped thickness: #{mapped || 'NIL (không có trong mapping)'}\n"
      
      UI.messagebox(msg)
    end

    # ========== HUD OVERLAY ==========
    # Overlay vẽ lên viewport mà KHÔNG chặn thao tác model
    class HudOverlay < Sketchup::Overlay
      def initialize
        super("mh.test2.hud", "MH Material HUD")
        @status = ""
        @data_count = 0
        update_info
      end

      def update_info
        @data_count = MH::MaterialApp.excel_data.length
        @last_file = MH::MaterialApp.last_excel_path ? File.basename(MH::MaterialApp.last_excel_path) : "Chua import"
      end

      def set_status(msg)
        @status = msg
        # Auto clear sau 3 giây
        UI.start_timer(3.0, false) { @status = ""; Sketchup.active_model.active_view.invalidate }
        Sketchup.active_model.active_view.invalidate
      end

      def draw(view)
        padding = 10
        x0 = 15
        y0 = 15

        # Title
        view.drawing_color = Sketchup::Color.new(50, 160, 255)
        view.draw_text([x0 + padding, y0 + padding], "MH Material", size: 13, bold: true)

        # Info
        view.drawing_color = Sketchup::Color.new(180, 180, 180)
        display_file = @last_file.length > 25 ? @last_file[0..22] + "..." : @last_file
        view.draw_text([x0 + padding, y0 + padding + 20], "Data: #{@data_count} | #{display_file}", size: 10)

        # Status message
        unless @status.empty?
          view.drawing_color = Sketchup::Color.new(100, 255, 100)
          view.draw_text([x0 + padding, y0 + padding + 38], @status, size: 11, bold: true)
        end
      end
    end

    # ========== HUD TOOL (với mouse pass-through) ==========
    # Tool hiển thị menu trên viewport + cho phép chọn object bình thường
    class HudTool
      MENU_GROUPS = [
        { name: "THAO TÁC GÁN", items: [0, 1] },
        { name: "DỮ LIỆU EXCEL", items: [2, 3, 4] },
        { name: "HỆ THỐNG", items: [5, 6, 7, 8] }
      ]

      MENU_ITEMS = [
        { label: "Gán VL Selection", action: :assign_selection },
        { label: "Gán VL Toàn bộ",   action: :assign_all },
        { label: "Import Excel/CSV", action: :import_excel },
        { label: "Làm mới Excel",    action: :refresh_excel },
        { label: "Xem dữ liệu",      action: :view_data },
        { label: "Giới hạn Lmax",    action: :set_max_length },
        { label: "Debug Thickness",  action: :debug_thickness },
        { label: "Tải lại Config",   action: :load_configs },
        { label: "Thoát",            action: :deactivate }
      ]

      def initialize
        @selected_index = 0
        @hover_index = nil
        @data_count = MH::MaterialApp.excel_data.length
        @last_file = MH::MaterialApp.last_excel_path ? File.basename(MH::MaterialApp.last_excel_path) : "Chua import"
        @status_msg = ""
        @ip = Sketchup::InputPoint.new
        @drag_start = nil
        @drag_end = nil
        @dragging = false
        @show_hud = false
        @last_assign_success = 0
        @last_assign_failed = 0
        @show_assign_counts = false
        @assign_counts_token = 0
        @shift_click_assign_pending = false
      end

      def activate
        # Auto-assign for initial selection
        unless Sketchup.active_model.selection.empty?
          execute_action(:assign_selection_silent, Sketchup.active_model.active_view)
        end
        Sketchup.active_model.active_view.invalidate
        Sketchup.status_text = "MH Material | TAB: HUD | ENTER: chon | Shift+Click: gan toan bo | ESC: thoat"
      end

      def deactivate(view)
        view.invalidate
      end

      def update_info
        @data_count = MH::MaterialApp.excel_data.length
        @last_file = MH::MaterialApp.last_excel_path ? File.basename(MH::MaterialApp.last_excel_path) : "Chua import"
      end

      def set_status(msg)
        @status_msg = msg
        Sketchup.active_model.active_view.invalidate
        UI.start_timer(3.0, false) do
          @status_msg = ""
          Sketchup.active_model.active_view.invalidate
        end
      end

      # ===== KEYBOARD =====
      def onKeyDown(key, repeat, flags, view)
        case key
        when 9  # Tab
          @show_hud = !@show_hud
          view.invalidate
        when 38 # Up Arrow
          if @show_hud
            @selected_index = (@selected_index - 1) % MENU_ITEMS.length
            view.invalidate
          end
        when 40 # Down Arrow
          if @show_hud
            @selected_index = (@selected_index + 1) % MENU_ITEMS.length
            view.invalidate
          end
        when 13  # Enter
          execute_action(MENU_ITEMS[@selected_index][:action], view) if @show_hud
        when 27  # Escape
          Sketchup.active_model.select_tool(nil)
        end
      end

      # ===== MOUSE: click + drag selection =====
      def onLButtonDown(flags, x, y, view)
        @shift_click_assign_pending = shift_modifier?(flags)

        if @show_hud
          # Check if click is on a HUD button
          clicked_idx = get_button_at(x, y)
          if clicked_idx && !@shift_click_assign_pending
            @selected_index = clicked_idx
            execute_action(MENU_ITEMS[@selected_index][:action], view)
            @drag_start = nil # Prevent dragging if button clicked
            return
          end
        end

        @drag_start = [x, y]
        @drag_end = [x, y]
        @dragging = false
      end

      def onMouseMove(flags, x, y, view)
        @ip.pick(view, x, y)
        view.tooltip = @ip.tooltip if @ip.valid?
        
        if @show_hud
          # Track hover state
          new_hover = get_button_at(x, y)
          if new_hover != @hover_index
            @hover_index = new_hover
            view.invalidate
          end
        end

        if @drag_start
          dx = (x - @drag_start[0]).abs
          dy = (y - @drag_start[1]).abs
          @dragging = true if dx > 5 || dy > 5
          @drag_end = [x, y] if @dragging
          view.invalidate if @dragging
        end
      end

      def onLButtonUp(flags, x, y, view)
        model = view.model
        sel = model.selection
        shift = shift_modifier?(flags)

        if @shift_click_assign_pending && !@dragging
          @shift_click_assign_pending = false
          @dragging = false
          @drag_start = nil
          @drag_end = nil
          execute_action(:assign_all, view)
          view.invalidate
          return
        end

        if @dragging && @drag_start
          x1 = [@drag_start[0], x].min
          y1 = [@drag_start[1], y].min
          x2 = [@drag_start[0], x].max
          y2 = [@drag_start[1], y].max
          sel.clear unless shift
          model.active_entities.each do |e|
            next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            pt2d = view.screen_coords(e.bounds.center)
            if pt2d.x >= x1 && pt2d.x <= x2 && pt2d.y >= y1 && pt2d.y <= y2
              sel.add(e)
            end
          end
        else
          ph = view.pick_helper
          ph.do_pick(x, y)
          entity = ph.best_picked
          if entity
            shift ? sel.toggle(entity) : (sel.clear; sel.add(entity))
          else
            sel.clear unless shift
          end
        end
        @dragging = false
        @drag_start = nil
        @drag_end = nil
        @shift_click_assign_pending = false
        
        # Auto-assign selected objects
        unless sel.empty?
          execute_action(:assign_selection_silent, view)
        end
        
        view.invalidate
      end

      def onLButtonDoubleClick(flags, x, y, view)
        ph = view.pick_helper
        ph.do_pick(x, y)
        entity = ph.best_picked
        if entity && (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
          view.model.active_path = view.model.active_path.to_a + [entity]
        end
      end

      # ===== DRAW HUD =====
      def draw(view)
        draw_rubber_band(view)
        unless @show_hud
          draw_compact_status(view)
          return
        end
        
        x0 = 20
        y0 = 20
        width = 240
        
        # --- Header ---
        view.drawing_color = Sketchup::Color.new(30, 30, 30)
        view.draw_text([x0, y0], "MH MATERIAL ASSIGN", size: 14, bold: true)
        
        view.drawing_color = Sketchup::Color.new(100, 100, 100)
        view.draw_text([x0, y0 + 22], "Data: #{@data_count} dòng", size: 10)
        
        # Truncate filename if too long to prevent overlap
        display_file = @last_file.length > 30 ? @last_file[0..27] + "..." : @last_file
        view.draw_text([x0, y0 + 38], "File: #{display_file}", size: 9)

        # Status
        unless @status_msg.empty?
          view.drawing_color = Sketchup::Color.new(0, 150, 0)
          view.draw_text([x0 + 130, y0 + 22], "● #{@status_msg}", size: 10, bold: true)
        end

        current_y = y0 + 65
        
        # --- Menu Groups ---
        MENU_GROUPS.each do |group|
          # Draw group header
          view.drawing_color = Sketchup::Color.new(150, 150, 150)
          view.draw_text([x0, current_y], group[:name], size: 8)
          
          # Draw divider line
          line_start = [x0 + 80, current_y + 6]
          line_end = [x0 + width, current_y + 6]
          view.drawing_color = Sketchup::Color.new(220, 220, 220)
          view.line_width = 1
          view.draw2d(GL_LINES, [line_start, line_end])
          
          current_y += 15
          
          # Draw items in group
          group[:items].each do |idx|
            item = MENU_ITEMS[idx]
            is_selected = (idx == @selected_index)
            is_hover = (idx == @hover_index)
            
            draw_button(view, x0, current_y, width, 26, item[:label], is_selected, is_hover)
            current_y += 32
          end
          
          current_y += 10
        end

        # --- Footer ---
        view.drawing_color = Sketchup::Color.new(150, 150, 150)
        view.draw_text([x0, current_y], "TAB: HUD | ENTER: chon | Shift+Click: gan toan bo | ESC: thoat", size: 9)

      end

      def draw_compact_status(view)
        x0 = 15
        y0 = 15
        display_file = @last_file.length > 38 ? @last_file[0..34] + "..." : @last_file

        view.drawing_color = Sketchup::Color.new(0, 0, 0)
        view.draw_text([x0, y0], "MH MATERIAL ASSIGN", size: 14, bold: true)
        view.draw_text([x0, y0 + 24], "Data: #{@data_count} dong", size: 12)
        view.draw_text([x0, y0 + 44], "File: #{display_file}", size: 11)
        if MH::MaterialApp.show_assign_counts
          view.draw_text([x0, y0 + 68], "Gan duoc: #{MH::MaterialApp.last_assign_success} obj", size: 11)
          view.draw_text([x0, y0 + 88], "Khong gan duoc: #{MH::MaterialApp.last_assign_failed} obj", size: 11)
        end
        unless @status_msg.to_s.empty?
          status_y = MH::MaterialApp.show_assign_counts ? y0 + 108 : y0 + 68
          view.draw_text([x0, status_y], trim_status(@status_msg, 78), size: 11, bold: true)
        end
      end

      def draw_rubber_band(view)
        if @dragging && @drag_start && @drag_end
          x1, y1 = @drag_start
          x2, y2 = @drag_end
          pts = [[x1,y1],[x2,y1],[x2,y2],[x1,y2]]
          view.drawing_color = Sketchup::Color.new(80, 160, 255, 40)
          view.draw2d(GL_QUADS, pts)
          view.line_width = 1
          view.drawing_color = Sketchup::Color.new(80, 160, 255)
          view.draw2d(GL_LINE_STRIP, pts + [[x1,y1]])
        end
      end

      private

      def shift_modifier?(flags)
        (flags & CONSTRAIN_MODIFIER_MASK) != 0
      end

      def draw_button(view, x, y, w, h, label, selected, hover)
        radius = 6
        bg_color = selected ? Sketchup::Color.new(70, 75, 140) : Sketchup::Color.new(235, 235, 235)
        
        # Use black border on hover, otherwise subtle border
        border_color = hover ? Sketchup::Color.new(0, 0, 0) : (selected ? Sketchup::Color.new(50, 55, 120) : Sketchup::Color.new(210, 210, 210))
        border_width = hover ? 2 : 1
        
        text_color = selected ? Sketchup::Color.new(255, 255, 255) : Sketchup::Color.new(60, 60, 60)

        # Background
        draw_rounded_rect(view, x, y, w, h, radius, bg_color)
        
        # Border
        draw_rounded_rect_outline(view, x, y, w, h, radius, border_color, border_width)

        # Label (centered)
        # Font size reduced by 30% from 11 -> 8
        font_size = 8
        char_w = 4.5 # smaller estimate for size 8
        text_x = x + (w - label.length * char_w) / 2
        
        view.drawing_color = text_color
        view.draw_text([text_x, y + 7], label, size: font_size, bold: selected)
      end

      def draw_rounded_rect(view, x, y, w, h, r, color)
        pts = []
        segments = 4
        # TL
        segments.times { |i| a = Math::PI + (Math::PI/2 * i / segments); pts << [x+r + r*Math.cos(a), y+r + r*Math.sin(a)] }
        # TR
        segments.times { |i| a = 3*Math::PI/2 + (Math::PI/2 * i / segments); pts << [x+w-r + r*Math.cos(a), y+r + r*Math.sin(a)] }
        # BR
        segments.times { |i| a = 0 + (Math::PI/2 * i / segments); pts << [x+w-r + r*Math.cos(a), y+h-r + r*Math.sin(a)] }
        # BL
        segments.times { |i| a = Math::PI/2 + (Math::PI/2 * i / segments); pts << [x+r + r*Math.cos(a), y+h-r + r*Math.sin(a)] }
        
        view.drawing_color = color
        view.draw2d(GL_POLYGON, pts)
      end

      def draw_rounded_rect_outline(view, x, y, w, h, r, color, width = 1)
        pts = []
        segments = 4
        segments.times { |i| a = Math::PI + (Math::PI/2 * i / segments); pts << [x+r + r*Math.cos(a), y+r + r*Math.sin(a)] }
        segments.times { |i| a = 3*Math::PI/2 + (Math::PI/2 * i / segments); pts << [x+w-r + r*Math.cos(a), y+r + r*Math.sin(a)] }
        segments.times { |i| a = 0 + (Math::PI/2 * i / segments); pts << [x+w-r + r*Math.cos(a), y+h-r + r*Math.sin(a)] }
        segments.times { |i| a = Math::PI/2 + (Math::PI/2 * i / segments); pts << [x+r + r*Math.cos(a), y+h-r + r*Math.sin(a)] }
        
        view.drawing_color = color
        view.line_width = width
        view.draw2d(GL_LINE_STRIP, pts + [pts[0]])
      end

      def update_assignment_counts(stats)
        has_error = stats.key?(:error) && stats[:error]
        success_count = stats.fetch(:success, 0).to_i
        processed_count = stats.fetch(:processed, 0).to_i
        failed_count =
          if processed_count > 0
            [processed_count - success_count, 0].max
          else
            stats.fetch(:skip_no_product, 0).to_i +
              stats.fetch(:skip_no_match, 0).to_i +
              stats.fetch(:skip_no_thickness, 0).to_i +
              stats.fetch(:skip_second_edge, 0).to_i +
              stats.fetch(:skip_exceed_length, 0).to_i +
              stats.fetch(:skip_error, 0).to_i
          end
        failed_count = 1 if failed_count == 0 && has_error
        MH::MaterialApp.last_assign_success = success_count
        MH::MaterialApp.last_assign_failed = failed_count
        MH::MaterialApp.show_assign_counts = true
        MH::MaterialApp.assign_counts_token = MH::MaterialApp.assign_counts_token.to_i + 1
        token = MH::MaterialApp.assign_counts_token
        view = Sketchup.active_model.active_view
        view.invalidate
        UI.start_timer(2.0, false) do
          next unless token == MH::MaterialApp.assign_counts_token

          MH::MaterialApp.show_assign_counts = false
          Sketchup.active_model.active_view.invalidate
        end
      end

      def trim_status(message, max_chars)
        text = message.to_s
        return text if text.length <= max_chars

        text[0, max_chars - 3] + "..."
      end

      def assignment_status_message(stats, prefix)
        details = stats[:details].is_a?(Array) ? stats[:details] : []
        unless details.empty?
          more = details.length > 1 ? " (+#{details.length - 1})" : ""
          return "#{prefix}: #{stats[:success]} | #{details.first}#{more}"
        end

        fail_name = stats[:skip_no_product] + stats[:skip_no_match]
        fail_thickness = stats[:skip_no_thickness]
        "#{prefix}: #{stats[:success]} | Fail: #{fail_name} | Day: #{fail_thickness} | Canh 15-1200: #{stats[:skip_second_edge]} | Dai: #{stats[:skip_exceed_length]}"
      end

      def execute_action(action, view)
        case action
        when :assign_selection
          stats = MH::MaterialApp.assign_to_selection(true)
          update_assignment_counts(stats)
          if stats.key?(:error) && stats[:error]
            set_status(stats[:error])
          else
            set_status(assignment_status_message(stats, "OK"))
          end
        when :assign_selection_silent
          stats = MH::MaterialApp.assign_to_selection(true)
          update_assignment_counts(stats)
          if stats.key?(:error) && stats[:error]
            set_status(stats[:error])
          else
            set_status(assignment_status_message(stats, "Auto OK"))
          end
        when :assign_all
          stats = MH::MaterialApp.assign_to_all(true)
          update_assignment_counts(stats)
          if stats.key?(:error) && stats[:error]
            set_status(stats[:error])
          else
            set_status(assignment_status_message(stats, "OK"))
          end
        when :import_excel
          MH::MaterialApp.import_excel_data
          update_info
          set_status("Import #{@data_count} dòng")
        when :refresh_excel
          MH::MaterialApp.refresh_excel_data
          update_info
          set_status("Refresh #{@data_count} dòng")
        when :set_max_length
          prompts = ["Lmax (mm): "]
          defaults = [MH::MaterialApp.max_length_limit.to_s]
          input = UI.inputbox(prompts, defaults, "Giới hạn chiều dài vật liệu")
          if input
            val = input[0].to_f
            MH::MaterialApp.max_length_limit = val
            Sketchup.write_default("MH_Material", "MaxLength", val)
            set_status("Lmax cập nhật: #{val}mm")
          end
        when :debug_thickness
          MH::MaterialApp.debug_thickness
        when :load_configs
          MH::MaterialApp.load_configs
          set_status("Config loaded!")
        when :view_data
          MH::MaterialApp.view_excel_data
        when :deactivate
          Sketchup.active_model.select_tool(nil)
          return
        end
        view.invalidate
      end

      def get_button_at(x, y)
        x0 = 20
        y0 = 20
        width = 240
        current_y = y0 + 65
        
        MENU_GROUPS.each do |group|
          current_y += 15 # header height
          group[:items].each do |idx|
            # Button is at [x0, current_y, width, 26]
            if x >= x0 && x <= x0 + width && y >= current_y && y <= current_y + 26
              return idx
            end
            current_y += 32 # item height
          end
          current_y += 10 # group spacing
        end
        nil
      end
    end

    # ========== HTML DIALOG: XEM DỮ LIỆU EXCEL ==========
    def self.esc_html_safe(val)
      s = val.to_s
      s = s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?') rescue s.to_s
      s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;').gsub("\n", ' ')
    end

    def self.view_excel_data
      if @excel_data.empty?
        notify("⚠️ Chưa có dữ liệu. Vui lòng import file Excel trước.")
        return
      end

      html = <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <title>Du lieu Excel</title>
          <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #1e1e2e; color: #cdd6f4; padding: 12px; }
            h2 { color: #89b4fa; margin-bottom: 10px; font-size: 16px; }
            .info { color: #a6adc8; font-size: 12px; margin-bottom: 12px; }
            table { width: 100%; border-collapse: collapse; font-size: 12px; }
            th { background: #313244; color: #89b4fa; padding: 8px 10px; text-align: left; position: sticky; top: 0; border-bottom: 2px solid #45475a; }
            td { padding: 6px 10px; border-bottom: 1px solid #313244; }
            tr:hover { background: #313244; }
            tr:nth-child(even) { background: #1a1a2e; }
            .sp { color: #f9e2af; font-weight: bold; }
            .detail { color: #cdd6f4; }
            .mat { color: #a6e3a1; font-weight: bold; }
            input[type="text"] { background: #313244; border: 1px solid #45475a; color: #cdd6f4; padding: 5px 10px; border-radius: 4px; width: 250px; margin-bottom: 10px; font-size: 12px; }
            input:focus { outline: none; border-color: #89b4fa; }
          </style>
        </head>
        <body>
          <h2>Du lieu Excel da import</h2>
          <div class="info">Tong: #{@excel_data.length} dong</div>
          <input type="text" id="search" placeholder="Tim kiem..." onkeyup="filterTable()">
          <table>
            <thead><tr><th>#</th><th>Ma SP</th><th>Ten chi tiet</th><th>Ma vat lieu</th></tr></thead>
            <tbody id="tbody">
      HTML

      @excel_data.each_with_index do |d, i|
        sp = esc_html_safe(d['Ma_SP'])
        detail = esc_html_safe(d['Ten_chi_tiet'] || d['TÊN SP'] || '')
        mat = esc_html_safe(d['Ma_vat_lieu'])
        html += "<tr><td>#{i+1}</td><td class='sp'>#{sp}</td><td class='detail'>#{detail}</td><td class='mat'>#{mat}</td></tr>\n"
      end

      html += <<~HTML
            </tbody>
          </table>
          <script>
            function filterTable() {
              var input = document.getElementById('search').value.toLowerCase();
              var rows = document.getElementById('tbody').getElementsByTagName('tr');
              for (var i = 0; i < rows.length; i++) {
                var text = rows[i].textContent.toLowerCase();
                rows[i].style.display = text.includes(input) ? '' : 'none';
              }
            }
          </script>
        </body>
        </html>
      HTML

      dialog = UI::HtmlDialog.new(
        dialog_title: "MH Material - Du lieu Excel",
        width: 600, height: 500, resizable: true,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      # Ghi HTML ra file tạm để tránh crash với chuỗi lớn
      tmp_html = File.join(PLUGIN_DIR, '_view_data.html')
      File.write(tmp_html, html, encoding: 'UTF-8')
      dialog.set_file(tmp_html)
      dialog.show
    end

    # ========== RUN VIA VBO AGENT ==========
    def self.run_agent
      ConfigLoader.load_all if @header_columns.empty?
      ensure_excel_data_loaded
      Sketchup.active_model.select_tool(HudTool.new)
    end

    

  end
end


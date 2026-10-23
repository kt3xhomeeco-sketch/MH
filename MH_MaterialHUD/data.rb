# encoding: UTF-8
module MH
  module MaterialHUD
    # No Thongke state, Excel imports or legacy stamped reports are read here.
    class Catalog
      attr_reader :signature, :path, :row_count

      def initialize(snapshot)
        @signature = [snapshot[:model_key], snapshot[:version], snapshot[:json_path]]
        @path = snapshot[:json_path].to_s
        @row_count = snapshot[:rows_count].to_i
        @products = Hash.new { |hash, key| hash[key] = [] }
        @product_names = {}
        @sections = {}
        MaterialCode.with_rules_snapshot do
          @acceptances = Acceptances.load
          Array(snapshot[:rows]).each do |row|
            product = ProductContext.base(ProjectData.product_value(row))
            next if product.empty?
            product_name = (row['Ten_SP'] || row['ten_sp'] || row['Tên SP']).to_s.strip
            @product_names[product] = product_name unless product_name.empty?
            raw = ['Ma_vat_lieu', 'ma_vat_lieu', 'material_code', 'Mã vật liệu'].map { |key| row[key].to_s.strip }.find { |v| !v.empty? }
            MaterialCode.split(raw).each do |code|
            @products[product] << {
              name: code, key: self.class.material_key(code),
              product_name: @product_names[product].to_s,
              spec: (row['spec'] || row['Spec']).to_s,
              spec_primary: self.class.material_specification_primary(row),
              spec_secondary: self.class.material_specification_secondary(row),
              note: self.class.material_specification(row)
            }
            end
          end
        end
        @products.each_value { |rows| rows.uniq! }
      end

      def self.material_key(value)
        parts = MaterialCode.strip_surface_variant(MaterialCode.without_thickness(value)).split('.')
        parts.reject! { |part| part == 'VER' } if parts.any? { |part| part != 'VER' && part.start_with?('VER') }
        parts.join('.')
      end

      def product_name(product)
        @product_names[product].to_s
      end

      # Public, lightweight view used by MH Material's choice palette. Keep the
      # raw JSON material code: MH Material maps its thickness only when it
      # applies the user's choice to a concrete object.
      def materials_for_product(product)
        @products.fetch(ProductContext.base(product), []).map { |row| row[:name].to_s }.reject(&:empty?).uniq
      end

      def material_options_for_product(product)
        grouped = {}
        @products.fetch(ProductContext.base(product), []).each do |row|
          code = row[:name].to_s.strip
          next if code.empty?

          product_name = row[:product_name].to_s.strip
          product_name = @product_names[ProductContext.base(product)].to_s.strip if product_name.empty?
          group = grouped[product_name] ||= { product_name: product_name, materials: {} }
          option = group[:materials][code] ||= { code: code, details: [], descriptions: [], fallback_descriptions: [] }
          # Excel_E có thể gom nhiều hạng mục dùng cùng một vật liệu, ví dụ
          # "CÁNH, MẶT BÀN". Hiển thị từng hạng mục để không làm mất phần sau
          # dấu phẩy khi HUD nhóm theo mã vật liệu.
          self.class.material_detail_labels(row[:spec_primary]).each do |detail|
            option[:details] << detail unless option[:details].include?(detail)
          end

          description = row[:spec_secondary].to_s.strip
          if description.empty?
            description = (row[:note].to_s.empty? ? row[:spec] : row[:note]).to_s.strip
            option[:fallback_descriptions] << description unless description.empty? || option[:fallback_descriptions].include?(description)
          else
            option[:descriptions] << description unless option[:descriptions].include?(description)
          end
        end
        grouped.values.flat_map do |group|
          group[:materials].values.each_with_index.map do |option, index|
            {
              code: option[:code],
              product_name: group[:product_name],
              product_group_start: index.zero?,
              detail: option[:details].join("\n"),
              description: (option[:descriptions].empty? ? option[:fallback_descriptions] : option[:descriptions]).join(', ')
            }
          end
        end
      rescue
        []
      end

      def self.material_specification(row)
        direct = (row['Quy_cach_vat_lieu'] || row['quy_cach_vat_lieu']).to_s.strip
        return direct unless direct.empty?

        parts = %w[Excel_E Excel_F Excel_G].map { |key| row[key].to_s.strip }.reject(&:empty?)
        return parts.join(' ') unless parts.empty?

        (row['ghi_chu'] || row['Ghi_chu']).to_s.strip
      end

      # Match SuperImp's HUD: Excel_E is the detail/category column (e.g.
      # THÙNG, HẬU TỦ), while Excel_F + Excel_G describe its material/finish.
      def self.material_specification_primary(row)
        (row['Excel_E'] || row['excel_e'] || row['material_specification_primary']).to_s.strip
      end

      def self.material_specification_secondary(row)
        direct = (row['material_specification_secondary'] || row['description']).to_s.strip
        return direct unless direct.empty?

        %w[Excel_F Excel_G].map { |key| (row[key] || row[key.downcase]).to_s.strip }.reject(&:empty?).join(' ')
      end

      def self.material_detail_labels(value)
        value.to_s.split(/[\r\n,;]+/).map(&:strip).reject(&:empty?).uniq
      rescue
        []
      end

      def self.matches?(left, right)
        return false if left.empty? || right.empty?
        return true if left == right
        longer, shorter = [left, right].sort_by { |value| -value.size }
        longer.start_with?(shorter + '/')
      end

      def section(product, materials, model_revision, complete: true)
        key = [product, model_revision, complete, materials.keys.sort]
        return @sections[key] if @sections.key?(key)
        @sections.clear if @sections.size > 200
        used = {}
        rows = @products.fetch(product, []).map do |row|
          matches = materials.keys.select { |code| self.class.matches?(row[:key], code) }
          matches.each { |code| used[code] = true }
          { type: :item, name: row[:name], product_name: row[:product_name], target: row[:spec], note: row[:note],
            status: matches.any? || @acceptances.accepted?(product, '', row[:key], row[:spec]) ? 'OK' : !complete ? '…' : 'SPEC' }
        end
        # An observed material with no JSON match is already proved NO SPEC;
        # only a missing model material (SPEC) requires a completed scan.
        materials.each_key do |code|
          next if used[code]
          # This row represents a logical material family, not whichever
          # thickness/face variant happened to be encountered last.
          rows << { type: :item, name: code, product_name: product_name(product), target: '', note: '', status: @acceptances.accepted?(product, code, '') ? 'OK' : 'NO SPEC' }
        end
        @sections[key] = rows
      end
    end
  end
end

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
        @sections = {}
        MaterialCode.with_rules_snapshot do
          @acceptances = Acceptances.load
          Array(snapshot[:rows]).each do |row|
            product = ProductContext.base(ProjectData.product_value(row))
            next if product.empty?
            raw = ['Ma_vat_lieu', 'ma_vat_lieu', 'material_code', 'Mã vật liệu'].map { |key| row[key].to_s.strip }.find { |v| !v.empty? }
            MaterialCode.split(raw).each do |code|
              @products[product] << {
                name: code, key: self.class.material_key(code),
                spec: (row['spec'] || row['Spec']).to_s,
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

      def self.material_specification(row)
        direct = (row['Quy_cach_vat_lieu'] || row['quy_cach_vat_lieu']).to_s.strip
        return direct unless direct.empty?

        parts = %w[Excel_E Excel_F Excel_G].map { |key| row[key].to_s.strip }.reject(&:empty?)
        return parts.join(' | ') unless parts.empty?

        (row['ghi_chu'] || row['Ghi_chu']).to_s.strip
      end

      def self.matches?(left, right)
        return false if left.empty? || right.empty?
        return true if left == right
        longer, shorter = [left, right].sort_by { |value| -value.size }
        longer.start_with?(shorter + '/')
      end

      def section(product, materials, model_revision, complete: true)
        key = [product, model_revision, complete]
        return @sections[key] if @sections.key?(key)
        @sections.clear if @sections.size > 200
        used = {}
        rows = @products.fetch(product, []).map do |row|
          matches = materials.keys.select { |code| self.class.matches?(row[:key], code) }
          matches.each { |code| used[code] = true }
          { type: :item, name: row[:name], target: row[:spec], note: row[:note],
            status: !complete ? '…' : matches.any? || @acceptances.accepted?(product, '', row[:key], row[:spec]) ? 'OK' : 'SPEC' }
        end
        if complete
          materials.each do |code, name|
            next if used[code]
            rows << { type: :item, name: name, target: '', note: '', status: @acceptances.accepted?(product, code, '') ? 'OK' : 'NO SPEC' }
          end
        end
        @sections[key] = rows
      end
    end
  end
end

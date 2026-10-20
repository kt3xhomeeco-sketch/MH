# encoding: UTF-8
require_relative 'assembly_math'

module MH
  module ModuleStudio
    # Shared HUD hierarchy from display data only; no host access or model edits.
    module AssemblyPresentation
      extend self

      # Envelope normals point out of the host; positive UI clearance points in.
      # This sign conversion is its own inverse for input and display.
      def gap(row,value)
        value && row['mode']=='contact' && !row['r1'] && row.dig('import_link','boundary')=='envelope' ? -value : value
      end

      def label(row)
        value = row['mode']=='angle' ? "#{row['angle']}°" : row['mode']=='repeat' ? "#{row['count']} bản" : "#{row.fetch('gap',0).to_f.round(3)} mm"
        kind = {'contact'=>row.fetch('gap',0).abs<=0.02 ? 'Tiếp xúc' : 'Khoảng cách','center'=>'Căn giữa','fit'=>'Vừa khoang','angle'=>'Góc','repeat'=>'Lặp / Chia đều'}.fetch(row['mode'],'Liên kết')
        kind = 'Đồng phẳng' if row['mode']=='contact' && row['relation']=='coplanar' && row.fetch('gap',0).abs<=0.02
        kind = 'Song song' if row['mode']=='contact' && row['relation']=='parallel'
        if row.dig('import_link','boundary')=='envelope'
          kind='Mốc phủ bì';value="#{gap(row,row.fetch('gap',0)).round(3)} mm"
        end
        row['mode']=='center' ? kind : "#{kind} · #{value}"
      end

      def modules(records)
        records.flat_map { |row| %w[a b c].filter_map { |key| row[key] } }.uniq { |ref| AssemblyMath.root_identity(ref) }.map do |ref|
          {'ref'=>Core.copy_data(ref),'name'=>ref['module_name'] || ref['name'] || 'Module'}
        end
      end

      def groups(records,scope: nil,members: [],name: nil)
        return [] if records.empty?
        records = Core.copy_data(records)
        subsets = scope ? {scope=>records} : records.group_by do |row|
          %w[a b c].filter_map { |key| AssemblyMath.root_identity(row[key]) if row[key] }.uniq.sort_by { |identity| JSON.generate(identity) }
        end
        subsets.map do |key,rows|
          {'id'=>scope ? 'scope:'+scope : 'pair:'+JSON.generate(key),'name'=>name,
           'modules'=>Core.copy_data(members.empty? ? modules(rows) : members),
           'links'=>rows.map { |row| {'id'=>row['id'],'label'=>label(row),'a'=>row['a'],'b'=>row['b']} }}
        end
      end
    end
  end
end

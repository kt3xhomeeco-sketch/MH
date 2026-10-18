# encoding: UTF-8
module MH
  module ModuleStudio
    # Import-only absolute restoration from an internally consistent saved
    # program/snapshot. Ordinary parameter edits retain strict baseline checks.
    module ImportRecovery
      extend self

      def plan(data,current)
        saved=Core.copy_data(data.fetch('snapshot'))
        current=Core.copy_data(current)
        Core.snapshot!(saved);Core.snapshot!(current)
        expected=saved['parts'].to_h { |part| [part['key'],part] }
        actual=current['parts'].to_h { |part| [part['key'],part] }
        unless expected.keys.sort==actual.keys.sort && actual.all? do |key,part|
          old=expected.fetch(key)
          %w[face_count edge_count visible].all? { |field| old[field]==part[field] }
        end
          raise Core::Error,'Cấu trúc chi tiết SKP đã đổi; không thể khôi phục chỉ bằng công thức đã lưu.'
        end
        result=Core.plan(data.fetch('rule'),saved,data.fetch('values'))
        raise Core::Error,'Thông số lưu trong SKP chưa khớp công thức; không tự khôi phục hình học.' unless result['changed_count'].zero?
        result['parts']=result['parts'].map do |part|
          DCVisibility.part_change(actual.fetch(part['key']),part['bounds'],part['visible']!=false,result.fetch('visibility_updates',[]))
        end
        result['changed_count']=result['parts'].count { |part| part['changed'] }
        result
      end
    end
  end
end

# encoding: UTF-8
module MH
  module ModuleStudio
    # No invented board thickness or silently discarded ATT inputs. Geometry
    # modules retain their real mesh and accept native Scale as ordinary objects.
    module StaticGeometry
      extend self
      def eligible?(snapshot)
        attrs=[snapshot.fetch('dc_inputs',{})]+Array(snapshot.dig('dc_graph','nodes')).map { |node| node['attributes'] }
        geometry=attrs.any? { |row| row.any? { |key,value| key.match?(/\A_(?:x|y|z|lenx|leny|lenz|hidden|copies|rotx|roty|rotz)_formula\z/) && !value.to_s.strip.empty? } }
        !geometry && Core.dc_controls(snapshot).empty?
      end

      def build(snapshot)
        raise Core::Error,'Module có ATT; không chuyển thành hình học tĩnh để bỏ qua công thức.' unless eligible?(snapshot)
        rule=RuleSystem.build(snapshot,nil,static_geometry:true)
        rule['module_name']=Parametric.module_title(snapshot)
        rule['module_name_source']='source'
        rule['warnings']=['Module hình học không có công thức ATT điều khiển; không tạo biến độ dày giả.']
        ThicknessSymbols.normalize(rule)
      end
    end
  end
end

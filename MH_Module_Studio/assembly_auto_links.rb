# encoding: UTF-8
require_relative 'assembly_inference'

module MH
  module ModuleStudio
    # Capture only the six oriented module envelope planes. Discovery never
    # traverses panels or runs the move/scale/redraw pipeline.
    module AssemblyAutoLinks
      extend self

      def selection(model)
        selected = model.selection.to_a
        pairs = selected.flat_map do |entity|
          raise Core::Error,'Chọn các module hoặc một cụm module để dò liên kết.' unless Assembly.container?(entity)
          if AssemblyContainers.managed?(entity)
            AssemblyContainers.members(entity).map { |member| [member,entity] }
          else
            [[entity,nil]]
          end
        end
        pairs.uniq! { |entity,owner| [owner&.persistent_id,entity.persistent_id] }
        # Prefer the enclosing/larger module as A; never depend on SketchUp's
        # unspecified Selection enumeration order. Existing links still win.
        pairs.sort_by! do |entity,owner|
          frame = owner ? owner.transformation*entity.transformation : entity.transformation
          size = Core.dimensions([entity.definition.bounds.min.to_a,entity.definition.bounds.max.to_a])
          volume = size.inject(:*)*frame.xaxis.length*frame.yaxis.length*frame.zaxis.length
          [-volume,owner&.persistent_id || 0,entity.persistent_id]
        end
        raise Core::Error,'Chọn ít nhất hai module, hoặc một cụm chứa các module.' if pairs.length<2
        raise Core::Error,'Chọn tối đa 40 module mỗi lần dò.' if pairs.length>40
        pairs.each do |entity,owner|
          Assembly.root(model,{'root'=>entity.persistent_id.to_s,'scope'=>owner&.persistent_id&.to_s}.compact)
          raise Core::Error,'Bỏ ẩn module trước khi dò liên kết.' if [entity,owner].compact.any? { |item| item.hidden? || !item.layer.visible? }
        end
        pairs
      end

      def capture(model,pairs)
        pairs.map do |entity,owner|
          bounds=entity.definition.bounds
          if bounds.empty? || Core.dimensions([bounds.min.to_a,bounds.max.to_a]).any? { |size| size<=1.0e-6 }
            raise Core::Error,'Module không có khung bao 3D hợp lệ.'
          end
          faces=3.times.flat_map do |axis|
            2.times.map do |side|
              anchor={'root'=>entity.persistent_id.to_s,'scope'=>owner&.persistent_id&.to_s,
                      'path'=>[],'axis'=>axis,'side'=>side,'level'=>'module','name'=>entity.name.to_s}.compact
              {'anchor'=>anchor,'plane'=>Assembly.world_plane(model,anchor)}
            end
          end
          {'faces'=>faces}
        end
      end

      def create(model,max_gap: 20)
        Runtime.ensure_top_level(model)
        existing = Assembly.records(model)
        pairs = selection(model)
        selected=pairs.map { |entity,owner| [owner&.persistent_id&.to_s,entity.persistent_id.to_s] }
        removed=AssemblyInference.legacy_panel_links(existing,selected)
        existing-=removed
        modules=capture(model,pairs)
        candidates = AssemblyInference.candidates(modules,max_gap:max_gap)
        # Keep the nearest opposing face for each physical side of a module
        # pair; a farther face behind it must not become an extra constraint.
        seen = []; planes = []
        candidates.select! do |row|
          key = [AssemblyMath.root_identity(row['a']),AssemblyMath.root_identity(row['b']),row['normal'].map { |v| v.round(5) }]
          if row['relation']=='coplanar'
            next false if planes.any? do |prior|
              key[0,2]==prior['pair'] && AssemblyMath.dot(row['normal'],prior['normal']).abs>0.999999 &&
                AssemblyMath.dot(AssemblyMath.sub(row['point'],prior['point']),row['normal']).abs<=0.02
            end
            planes << row.merge('pair'=>key[0,2])
            next true
          end
          next false if seen.include?(key) || !AssemblyInference.unobstructed?(row,modules)
          seen << key
          true
        end
        links = AssemblyInference.choose(candidates,existing) { |rows| AssemblyExternal.validate!(rows) }
        raise Core::Error,'Quá 200 liên kết; giảm vùng chọn hoặc xóa các liên kết không cần thiết.' if existing.length+links.length>200
        Assembly.store_contacts(model,existing,links,removed:removed) unless links.empty? && removed.empty?
        {'links'=>links,'removed'=>removed.length}
      end
    end
  end
end

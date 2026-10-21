# encoding: UTF-8
module MH
  module ModuleStudio
    # Native pointer/box picking, scoped to AssemblyTool. No model mutations.
    class AssemblyFacePicker
      LABELS = {'part'=>'Mặt tấm','module'=>'Phủ bì module','assembly'=>'Phủ bì cụm'}.freeze
      SIDES = [['Trái','Phải'],['Trước','Sau'],['Dưới','Trên']].freeze

      def self.level(flags,shift_mask: CONSTRAIN_MODIFIER_MASK,ctrl_mask: COPY_MODIFIER_MASK)
        return 'assembly' unless (flags & ctrl_mask).zero?
        (flags & shift_mask).zero? ? 'part' : 'module'
      end

      def self.label(anchor)
        level = anchor.fetch('level',anchor['part'] || anchor['panel'] || !anchor.fetch('path',[]).empty? ? 'part' : 'module')
        "#{LABELS.fetch(level)} · #{SIDES.fetch(anchor['axis']).fetch(anchor['side'])}"
      end

      def initialize(model)
        @model = model
      end

      def candidates(level)
        AssemblyContainers.containers(@model).then do |assemblies|
          return assemblies.map { |entity| [entity,nil] } if level=='assembly'
          roots = @model.entities.select { |entity| Assembly.container?(entity) && !AssemblyContainers.managed?(entity) } # rubocop:disable SketchupSuggestions/ModelEntities -- Picking is explicitly at model level.
          roots.map { |entity| [entity,nil] } + assemblies.flat_map { |owner| AssemblyContainers.members(owner).map { |entity| [entity,owner] } }
        end
      end

      def box_hit(entity,owner,x,y,view,frame: nil)
        return if entity.hidden? || !entity.layer.visible? || owner && (owner.hidden? || !owner.layer.visible?)
        frame ||= owner ? owner.transformation*entity.transformation : entity.transformation
        inverse = frame.inverse
        ray = view.pickray(x,y)
        origin = ray[0].transform(inverse).to_a; vector = ray[1].transform(inverse).to_a
        box = [entity.definition.bounds.min.to_a,entity.definition.bounds.max.to_a]
        tolerance = view.pixels_to_model(5,entity.definition.bounds.center.transform(frame))
        scales = [frame.xaxis.length,frame.yaxis.length,frame.zaxis.length]
        hits = 3.times.flat_map do |axis|
          next [] if vector[axis].abs<1.0e-12
          2.times.filter_map do |side|
            distance = (box[side][axis]-origin[axis])/vector[axis]
            next if distance<0
            point = 3.times.map { |index| origin[index]+distance*vector[index] }
            next unless ([0,1,2]-[axis]).all? { |index| point[index]>=box[0][index]-tolerance/scales[index] && point[index]<=box[1][index]+tolerance/scales[index] }
            [distance,axis,side]
          end
        end
        hits.min_by(&:first)
      end

      def part_surface(path,frame,accept)
        return unless path.last.is_a?(Sketchup::Face)
        anchor = Assembly.anchor(path)
        return if accept && !accept.call(anchor)
        {'anchor'=>anchor,'face'=>path.last,'mesh'=>path.last.mesh,'frame'=>frame,
         'plane'=>Assembly.world_plane(@model,anchor),'level'=>'part'}
      rescue Core::Error
        nil
      end

      # PickHelper can omit a face occluded by a previously chosen module.
      # Intersect real faces of allowed modules without hiding/editing geometry.
      def through_parts(x,y,view,accept)
        ray = view.pickray(x,y)
        hits = []
        visit = lambda do |item,path,frame,depth|
          return if depth>30 || item.hidden? || !item.layer.visible? || item.locked?
          local = [ray[0].transform(frame.inverse),ray[1].transform(frame.inverse)]
          item.definition.entities.each do |child|
            next if child.hidden? || !child.layer.visible?
            if Assembly.container?(child)
              child_frame = frame*child.transformation
              visit.call(child,path+[child],child_frame,depth+1) if box_hit(child,nil,x,y,view,frame:child_frame)
            elsif child.is_a?(Sketchup::Face)
              point = Geom.intersect_line_plane(local,child.plane)
              next unless point && [Sketchup::Face::PointInside,Sketchup::Face::PointOnEdge,Sketchup::Face::PointOnVertex].include?(child.classify_point(point))
              distance = (point.transform(frame)-ray[0]).dot(ray[1])
              next if distance<0
              surface = part_surface(path+[child],frame,accept)
              hits << [distance,surface] if surface
            end
          end
        end
        candidates('module').each do |entity,owner|
          ref = {'root'=>entity.persistent_id.to_s,'scope'=>owner&.persistent_id&.to_s}.compact
          next unless accept.call(ref) && box_hit(entity,owner,x,y,view)
          frame = owner ? owner.transformation*entity.transformation : entity.transformation
          visit.call(entity,[owner,entity].compact,frame,0)
        end
        hits.min_by(&:first)&.last
      end

      def hit(flags,x,y,view,accept: nil)
        level = self.class.level(flags)
        if level=='part'
          helper = view.pick_helper; helper.do_pick(x,y)
          indices = helper.count.times.select { |index| helper.leaf_at(index).is_a?(Sketchup::Face) }
          indices.sort_by! { |index| helper.leaf_at(index)==helper.picked_face ? 0 : 1 }
          indices.each do |index|
            surface = part_surface(helper.path_at(index),helper.transformation_at(index),accept)
            return surface if surface
          end
          return through_parts(x,y,view,accept) if accept
          return
        end
        matches = candidates(level).filter_map do |entity,owner|
          ref = {'root'=>entity.persistent_id.to_s,'scope'=>owner&.persistent_id&.to_s,'level'=>level}.compact
          next if accept && !accept.call(ref)
          hit = box_hit(entity,owner,x,y,view)
          [hit,entity,owner] if hit
        end
        winner = matches.min_by { |hit,_entity,_owner| hit[0] }
        return unless winner
        (_distance,axis,side),entity,owner = winner
        anchor = {'root'=>entity.persistent_id.to_s,'scope'=>owner&.persistent_id&.to_s,'path'=>[],
                  'axis'=>axis,'side'=>side,'level'=>level,'name'=>entity.name.to_s}.compact
        raise Core::Error,'Đối tượng đang bị khóa.' if entity.locked? || owner&.locked?
        {'anchor'=>anchor,'plane'=>Assembly.world_plane(@model,anchor),'level'=>level}
      end
    end
  end
end

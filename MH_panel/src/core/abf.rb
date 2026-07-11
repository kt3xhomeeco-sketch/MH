module MH::Panel::ABF
  def self.fix_marking(board)
    markings = MH::Panel.grep_ents(board, :group)
    return if markings.empty?
    faces = MH::Panel::Board.get_cnc_faces(board)
    return unless faces && faces.size == 2
    f1, f2 = faces
    markings.each do |marking|
      origin = marking.bounds.center
      [f1, f2].min_by { |f| (origin - f.vertices.first.position).dot(f.normal).abs }.tap do |face|
        dist = (origin - face.vertices.first.position).dot(face.normal)
        move_vec = face.normal.clone.transform(marking.transformation.inverse)
        move_vec.length = -dist
        marking.transformation = marking.transformation * Geom::Transformation.translation(move_vec)
      end
    end
  end
  def self.remove_band(face)
    return unless face.valid?
    face.delete_attribute("ABF", "edge-band-id")
  end
  def self.clean_tag(group)
    entities = MH::Panel.get_ents(group)
    group = entities.grep(Sketchup::Group)
    group.each(&:erase!)
  end
  def self.is_intersect(group, value)
    group.set_attribute("ABF", "is-intersect", value)
  end
  def self.ensure_is_board(parent)
    return false unless parent
    is_board = parent.get_attribute("ABF", "is-board")
    parent.set_attribute("ABF", "is-board", true) if is_board.nil?
    true
  end
  def self.set_hinge(group, setting_name)
    group.set_attribute("ABF", "is-hinge-part-b", true)
    group.set_attribute("ABF", "setting-name", setting_name)
  end
  def self.set_statistical(inst, name, type = "counter")
    inst.set_attribute("ABF", "is-statistical-object", true)
    inst.set_attribute("ABF", "statistical-name", name)
    inst.set_attribute("ABF", "statistical-type", type)
  end
  def self.set_minifix(inst, setting_name, part: "b")
    inst.set_attribute("ABF", "is-minifix-part-#{part}", true)
    inst.set_attribute("ABF", "setting-name", setting_name)
  end
  def self.set_side_drill_depth(inst)
    inst.set_attribute("ABF", "is-side-drill-depth", true)
  end
  def self.set_side_drill(inst, drill_depth)
    inst.set_attribute("ABF", "is-side-drill", true)
    inst.entities.each do |e|
      e.curve.set_attribute("ABF", "drill-depth", drill_depth) if e.is_a?(Sketchup::Edge) && e.curve
    end
  end
end
module MH
  module Panel
    module ABF
      # Dùng prepend + super thay vì alias set_attribute. ZSU cũng prepend một
      # guard lên Sketchup::Face; alias có thể vô tình trỏ vào guard đó rồi tạo
      # vòng lặp ZSU -> MH Panel -> ZSU và văng SystemStackError.
      module FaceAttributeGuard
        def set_attribute(dict, key, val)
          return val if dict == 'ABF' && get_attribute('MH::Panel', 'chan_dan_canh', false) == true

          super
        end
      end
    end
  end
end

unless Sketchup::Face.ancestors.include?(MH::Panel::ABF::FaceAttributeGuard)
  Sketchup::Face.prepend(MH::Panel::ABF::FaceAttributeGuard)
end

# encoding: UTF-8

module MH::Stretch
  module BoxModel
    AXES = [:x, :y, :z].freeze
    MIN_LEN = 1.mm
    PLANE_OFFSET_RATIO = 0.06
    AXIS_COLORS = {
      x: Sketchup::Color.new(213, 42, 42),
      y: Sketchup::Color.new(56, 161, 56),
      z: Sketchup::Color.new(58, 96, 214)
    }.freeze

    module_function

    [
      :setup_context,
      :oriented_instance_bounds,
      :local_context?,
      :box_to_world,
      :world_to_box,
      :to_world,
      :to_box,
      :world_axis_value,
      :axis_world_vector,
      :axis_delta_vector,
      :raw_corners,
      :normalized_axis
    ].each do |method_name|
      singleton_class.send(:remove_method, method_name) if singleton_class.method_defined?(method_name)
    end

    def selection_bounds(model)
      bb = Geom::BoundingBox.new
      model.selection.each { |ent| bb.add(ent.bounds) if ent.respond_to?(:bounds) }
      bb
    end

    def empty_bounds?(bb)
      !bb || !bb.valid? || (bb.width == 0 && bb.height == 0 && bb.depth == 0)
    end

    def axis_value(obj, axis)
      case axis
      when :x then obj.x
      when :y then obj.y
      else obj.z
      end
    end

    def axis_min(bb, axis)
      axis_value(bb.min, axis)
    end

    def axis_max(bb, axis)
      axis_value(bb.max, axis)
    end

    def axis_length(bb, axis)
      axis_max(bb, axis) - axis_min(bb, axis)
    end

    def axis_delta_vector(axis, amount)
      case axis
      when :x then Geom::Vector3d.new(amount.to_f, 0, 0)
      when :y then Geom::Vector3d.new(0, amount.to_f, 0)
      else Geom::Vector3d.new(0, 0, amount.to_f)
      end
    end

    def usable_axis?(bb, axis)
      axis_length(bb, axis).abs > MIN_LEN * 2
    end

    def clamp_pos(pos, bb, axis)
      return pos unless usable_axis?(bb, axis)

      [[pos, axis_min(bb, axis) + MIN_LEN].max, axis_max(bb, axis) - MIN_LEN].min
    end

    def corners(bb)
      (0..7).map { |i| bb.corner(i) }
    end

    def face_handles(bb)
      c = bb.center
      {
        { axis: :x, side: :minus } => Geom::Point3d.new(bb.min.x, c.y, c.z),
        { axis: :x, side: :plus } => Geom::Point3d.new(bb.max.x, c.y, c.z),
        { axis: :y, side: :minus } => Geom::Point3d.new(c.x, bb.min.y, c.z),
        { axis: :y, side: :plus } => Geom::Point3d.new(c.x, bb.max.y, c.z),
        { axis: :z, side: :minus } => Geom::Point3d.new(c.x, c.y, bb.min.z),
        { axis: :z, side: :plus } => Geom::Point3d.new(c.x, c.y, bb.max.z)
      }
    end

    def display_plane_points(bb, plane)
      p = plane[:pos]
      mx = bb.width * PLANE_OFFSET_RATIO
      my = bb.height * PLANE_OFFSET_RATIO
      mz = bb.depth * PLANE_OFFSET_RATIO
      min = Geom::Point3d.new(bb.min.x - mx, bb.min.y - my, bb.min.z - mz)
      max = Geom::Point3d.new(bb.max.x + mx, bb.max.y + my, bb.max.z + mz)

      case plane[:axis]
      when :x
        [Geom::Point3d.new(p, min.y, min.z), Geom::Point3d.new(p, max.y, min.z),
         Geom::Point3d.new(p, max.y, max.z), Geom::Point3d.new(p, min.y, max.z)]
      when :y
        [Geom::Point3d.new(min.x, p, min.z), Geom::Point3d.new(max.x, p, min.z),
         Geom::Point3d.new(max.x, p, max.z), Geom::Point3d.new(min.x, p, max.z)]
      else
        [Geom::Point3d.new(min.x, min.y, p), Geom::Point3d.new(max.x, min.y, p),
         Geom::Point3d.new(max.x, max.y, p), Geom::Point3d.new(min.x, max.y, p)]
      end
    end

    def plane_center(bb, plane)
      c = bb.center
      case plane[:axis]
      when :x then Geom::Point3d.new(plane[:pos], c.y, c.z)
      when :y then Geom::Point3d.new(c.x, plane[:pos], c.z)
      else Geom::Point3d.new(c.x, c.y, plane[:pos])
      end
    end

    def color(axis)
      AXIS_COLORS[axis] || Sketchup::Color.new(80, 80, 80)
    end
  end
end




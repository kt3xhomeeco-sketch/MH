# encoding: UTF-8
#
# Stretch Pro preserves container origins after a single-cut stretch. DC length
# preparation and redraw are delegated to DcLengths so formulas stay untouched.
#
module MH::Scale
  module StretchPro
    CONTAINERS = [Sketchup::Group, Sketchup::ComponentInstance].freeze
    EPS = 1e-6

    module_function

    def finalize(model, axis, side, amount, boundary, redraw_enabled, origin_states = nil)
      roots = model.selection.to_a.select { |e| container?(e) && dynamic?(e) }
      return result(true, false) if roots.empty?

      move = SmartScale::StretchCore.delta_for_axis(axis, amount)

      changed = 0
      model.start_operation('MH Scale Stretch Pro', true)
      roots.each do |root|
        root.definition.entities.to_a.each do |child|
          next unless container?(child)

          if crossing?(child, root.transformation, boundary, axis)
            changed += deep_reorigin(
              child,
              root.transformation,
              move,
              boundary,
              side,
              axis
            )
          end
        end
      end
      changed.positive? ? model.commit_operation : model.abort_operation

      return result(true, false, roots.length) unless redraw_enabled

      dc_result = DcLengths.sync_roots(
        roots,
        axis: axis,
        origin_states: origin_states
      )
      result(true, true, roots.length, dc_result)
    rescue => e
      model.abort_operation rescue nil
      warn "MHScale StretchPro failed: #{e.class}: #{e.message}"
      result(false, false)
    end

    def crossing?(inst, parent_world, boundary, axis)
      bb = inst.bounds
      vals = (0..7).map { |i| axis_val(bb.corner(i).transform(parent_world), axis) }
      vals.min < boundary - EPS && vals.max > boundary + EPS
    end

    def deep_reorigin(inst, parent_world, move, boundary, side, axis)
      changed = 0
      origin_v = axis_val((parent_world * inst.transformation).origin, axis)
      on_moving = side == :minus ? origin_v <= boundary + EPS : origin_v >= boundary - EPS
      changed += move_origin(inst, parent_world, move) if on_moving
      npw = parent_world * inst.transformation
      inst.definition.entities.to_a.each do |c|
        changed += deep_reorigin(c, npw, move, boundary, side, axis) if container?(c)
      end
      changed
    end

    def move_origin(inst, parent_world, move)
      inst.make_unique if inst.respond_to?(:make_unique) && shared_definition?(inst)

      vp = move.transform(parent_world.inverse)
      back = Geom::Vector3d.new(-vp.x, -vp.y, -vp.z)
      shift_local = back.transform(inst.transformation.inverse)
      ents = inst.definition.entities
      DcLengths.transform_definition_contents(
        ents,
        Geom::Transformation.translation(shift_local)
      )
      inst.transformation = Geom::Transformation.translation(vp) * inst.transformation
      1
    end

    def shared_definition?(instance)
      instance.definition.instances.length > 1
    rescue
      false
    end

    def axis_val(pt, axis)
      case axis
      when :x then pt.x
      when :y then pt.y
      else pt.z
      end
    end

    def dynamic?(inst)
      inst.attribute_dictionary('dynamic_attributes', false) ||
        inst.definition.attribute_dictionary('dynamic_attributes', false)
    end

    def container?(entity)
      CONTAINERS.any? { |klass| entity.is_a?(klass) }
    end

    def result(ok, redraw_requested, roots = 0, dc_result = nil)
      {
        ok: ok,
        redraw_requested: redraw_requested,
        roots: roots,
        dc: dc_result
      }
    end
  end
end


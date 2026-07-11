# encoding: UTF-8

module MH
module Stretch
  # Executes the bounded-region stretch selected by BetweenPlanesSelector.
  module BetweenPlanesOperation
    MIN_AMOUNT = StretchOperation::MIN_AMOUNT

    module_function

    def commit(model, axis:, min_pos:, max_pos:, amount:, clearance: BetweenPlanesSelector::DEFAULT_CLEARANCE, make_unique: true)
      return result(false, 0, 'Selection rong.') if model.selection.empty?
      return result(false, 0, 'Cap plane khong hop le.') unless BetweenPlanesSelector.valid_interval?(min_pos, max_pos, clearance)
      return result(false, 0, 'Doan keo qua nho.') if amount.to_f.abs <= MIN_AMOUNT

      model.start_operation('MH Stretch Between Planes', true)
      unique_count = make_unique ? PlaneVertexSelector.make_selection_unique(model.selection.to_a) : 0
      buckets = BetweenPlanesSelector.select(
        model,
        axis: axis,
        min_pos: min_pos,
        max_pos: max_pos,
        clearance: clearance
      )
      snapshot = StretchOperation.snapshot_target_edges(buckets)
      world_delta = PlaneVertexSelector.world_delta(axis, amount.to_f)
      moved = StretchOperation.move_origin_containers(buckets[:origin_containers], world_delta)
      moved += StretchOperation.move_containers(buckets[:containers], world_delta)
      moved += StretchOperation.move_curves(buckets[:curves], world_delta)
      moved += StretchOperation.move_vertex_buckets(buckets[:vertex_buckets], world_delta)
      StretchOperation.remove_new_coplanar_seams(snapshot)
      model.commit_operation

      output = result(
        moved.positive?,
        moved,
        moved.positive? ? "Da stretch #{moved} doi tuong/vertex giua 2 plane." : 'Khong co vertex trong vung giua 2 plane.'
      )
      output[:unique_count] = unique_count
      output
    rescue => error
      model.abort_operation rescue nil
      result(false, 0, "#{error.class}: #{error.message}")
    end

    def result(ok, changed, message)
      { ok: ok, changed: changed, message: message }
    end
  end
end
end

# frozen_string_literal: true

module MH
  module CAD2Module
    module PlanDepth
      module_function

      def refresh_preview(model, instance, product, root)
        return false unless instance.is_a?(Assembly) && product.dig('envelope_preview', 'dimensions_from') == 'closed_stock_depth'
        old = JSON.parse(instance.get_attribute(Model::DICT, 'analysis'))
        return false unless old['envelope_preview'] && !old['manual_boxes'] && old['source_hash'] == product['source_hash'] &&
                            old['source_plan_envelope'] == product['source_plan_envelope'] && old['plan_view_id'] == product['plan_view_id'] &&
                            !Corrections.active? && !model.active_path && Array(old['modules']).length == 1 && Array(product['modules']).length == 1
        before = old['modules'].first; after = product['modules'].first
        return false if before == after
        return false unless before['id'] == after['id'] && before['origin'][0] == after['origin'][0] && before['size'][0] == after['size'][0] &&
                            before['origin'][2] == after['origin'][2] && before['size'][2] == after['size'][2] &&
                            after['origin'][1] >= before['origin'][1] - 0.01 &&
                            after['origin'][1] + after['size'][1] <= before['origin'][1] + before['size'][1] + 0.01 &&
                            after['size'][1] < before['size'][1] - 0.15 && !before['plan_profile'] && !before['panel_parts']
        Placement.validate_envelope_preview(product)
        group = ProductHeight.untouched_preview_group(instance, before)
        return false unless group
        update = JSON.parse(JSON.generate(old))
        %w[modules bounds envelope_preview geometry_pipeline explanation warnings product_height height_source height_pending elevation_pending].each do |key|
          product.key?(key) ? update[key] = product[key] : update.delete(key)
        end
        model.start_operation('CAD2Module: Sâu Box', true)
        begin
          group.entities.transform_entities(Geom::Transformation.scaling(1, after['size'][1] / before['size'][1].to_f, 1), group.entities.to_a)
          group.definition.invalidate_bounds
          group.transformation = instance.transformation * Geom::Transformation.translation(after['origin'].map(&:mm))
          group.set_attribute(Model::DICT, 'source_module', JSON.generate(after))
          instance.set_attribute(Model::DICT, 'analysis', JSON.generate(update))
          Storage.event(root, 'kind' => 'plan_depth_refresh', 'code' => old['code'], 'product_id' => instance.persistent_id,
                        'activity_id' => old['activity_id'], 'before' => before, 'after' => after,
                        'proof' => product.dig('envelope_preview', 'depth_evidence'))
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        true
      end
    end
  end
end

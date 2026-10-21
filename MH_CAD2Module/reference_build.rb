# frozen_string_literal: true

require_relative 'plan_depth'

module MH
  module CAD2Module
    # Named CAD can be restored without rebuilding existing module solids.
    module ReferenceBuild
      module_function

      def call(product, root, job, model, owner_id = nil)
        full = product.dig('plan_reference', 'scope') == 'all_views'
        shared = product.dig('plan_reference', 'shared') == true
        eligible = (full || shared) && product.dig('placement', 'mode') != 'source_plan'
        matches = eligible ? Model.products(model).select do |p|
          p.get_attribute(Model::DICT, 'code') == Model.normalise(product['code']) && p.get_attribute(Model::DICT, 'plan_view_id') == product['plan_view_id']
        end : []
        raise ArgumentError, 'Có nhiều bộ box cùng mặt bằng; chưa tự chọn bộ để khôi phục CAD.' if matches.length > 1
        existing = matches.first
        if existing
          analysis = JSON.parse(existing.get_attribute(Model::DICT, 'analysis'))
          raise ArgumentError, 'Box hiện tại thuộc phiên bản CAD khác; chưa tự ghi đè.' unless analysis['source_hash'] == product['source_hash']
        end
        packet = owner_id ? product.merge('cad_reference_owner_id' => owner_id) : product
        if existing
          updated = PartialPlan.refresh_preview(model, existing, packet, root)
          ProductHeight.refresh_preview(model, existing, packet, root)
          PlanDepth.refresh_preview(model, existing, packet, root)
          restored = full ? PlanReference.restore_missing(model, packet, existing, root) : 0
          if shared && owner_id
            group = PlanReference.shared_group(model, packet, Assembly.new(model, owner_id))
            if existing.get_attribute(Model::DICT, 'plan_reference_id') != group.persistent_id
              model.start_operation('CAD2Module: Ghép CAD', true)
              begin
                existing.set_attribute(Model::DICT, 'plan_reference_id', group.persistent_id)
                model.commit_operation
              rescue StandardError
                model.abort_operation
                raise
              end
            end
          end
          return { instance: existing, created: false, updated: updated, restored: restored, owner: full ? existing.persistent_id : owner_id }
        end
        instance = Model.build(packet, root, job, model)
        { instance: instance, created: true, restored: 0, owner: full ? instance.persistent_id : owner_id }
      end
    end
  end
end

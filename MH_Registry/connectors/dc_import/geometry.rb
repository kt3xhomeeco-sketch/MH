# encoding: UTF-8
#
# MH_Registry / connectors / dc_import / geometry.rb
# ---------------------------------------------------------------------------
# Geometry fallback helpers for DCImportPipeline.
# ---------------------------------------------------------------------------

module MH
  module RegistryApp
    module Connectors
      module DCImportPipeline
        module_function

        def ensure_profile_geometry_thickness(instance, profile)
          return unless instance && instance.valid?
          pairs = collect_thickness_groups(instance.definition.entities, instance.transformation)
          return if pairs.empty?

          model = Sketchup.active_model
          model.start_operation('MH DC Geometry Thickness', true)
          changed = 0
          pairs.each do |group, world_tr|
            target_mm = back_group?(group) ? profile['back_thickness_mm'].to_f : profile['panel_thickness_mm'].to_f
            changed += scale_group_to_thickness(group, target_mm, world_tr)
          end
          changed > 0 ? model.commit_operation : model.abort_operation
        rescue => e
          model.abort_operation rescue nil
          MH::RegistryApp.dbg("[DCImportPipeline] geometry thickness error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
        end

        # Thu thap [group, world_transform] theo CA chuoi transform cha, vi do day
        # thuc cua chi tiet phu thuoc scale cua instance/group cha (vd transform
        # nen local-Y xuong 3% de tao do day) -> phai biet transform world day du.
        def collect_thickness_groups(entities, world_tr, result = [])
          entities.each do |entity|
            next unless visible_entity?(entity)

            if entity.is_a?(Sketchup::Group)
              child_tr = world_tr * entity.transformation
              result << [entity, child_tr]
              collect_thickness_groups(entity.entities, child_tr, result)
            elsif entity.is_a?(Sketchup::ComponentInstance)
              collect_thickness_groups(entity.definition.entities, world_tr * entity.transformation, result)
            end
          end
          result
        end

        def scale_group_to_thickness(group, target_mm, world_tr = nil)
          return 0 unless group && group.valid? && target_mm > 0

          ents = group.respond_to?(:entities) ? group.entities : nil
          return 0 unless ents

          # Sketchup::Entities KHONG co method .bounds -> tu gom bbox cuc bo
          # (bounds tung entity con da o he toa do local cua group).
          bb = Geom::BoundingBox.new
          ents.each { |e| bb.add(e.bounds) if e.respond_to?(:bounds) }
          return 0 unless bb.valid?

          # Do day THUC = kich thuoc local * scale cua chuoi transform world tren
          # truc do. Phai dung world_tr (instance*...*group), KHONG chi group.tr,
          # neu khong se do nham truc/sai do day (bug cu: lay local-X=14 trong khi
          # do day world that = local-Y * 0.03 = 17.6mm).
          chain = world_tr || group.transformation
          ca = chain.to_a
          w = ca[15].abs > 1e-9 ? ca[15].abs : 1.0
          col = [
            Geom::Vector3d.new(ca[0], ca[1], ca[2]).length / w,
            Geom::Vector3d.new(ca[4], ca[5], ca[6]).length / w,
            Geom::Vector3d.new(ca[8], ca[9], ca[10]).length / w
          ]
          local_mm = [bb.width.to_mm, bb.height.to_mm, bb.depth.to_mm]
          dims = [:x, :y, :z].each_with_index.map { |sym, i| [sym, local_mm[i] * col[i]] }
                            .select { |_sym, value| value > 0.001 }
          axis, current_mm = dims.min_by { |_sym, value| value }
          return 0 unless axis && current_mm > 0.001
          return 0 if (current_mm - target_mm).abs < 0.05

          factor = target_mm.to_f / current_mm.to_f
          sx = axis == :x ? factor : 1.0
          sy = axis == :y ? factor : 1.0
          sz = axis == :z ? factor : 1.0
          ents.transform_entities(Geom::Transformation.scaling(thickness_scale_anchor(group, bb, axis), sx, sy, sz), ents.to_a)
          1
        rescue => e
          MH::RegistryApp.dbg("[DCImportPipeline] scale thickness error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          0
        end

        def thickness_scale_anchor(group, bounds, axis)
          center = bounds.center
          case axis
          when :x
            Geom::Point3d.new(bounds.min.x, center.y, center.z)
          when :y
            Geom::Point3d.new(center.x, bounds.min.y, center.z)
          when :z
            Geom::Point3d.new(center.x, center.y, bounds.min.z)
          else
            center
          end
        rescue
          bounds.center
        end

      end
    end
  end
end

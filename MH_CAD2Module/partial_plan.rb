# frozen_string_literal: true

module MH
  module CAD2Module
    # Failed regions remain correction targets alongside independently proven bays.
    module PartialPlan
      module_function

      def near(a, b)
        RegisteredElevation.near(a, b)
      end

      def covers?(boxes, left, right)
        reach = left
        boxes.sort_by(&:first).each do |box|
          break if box[0] > reach + 0.15
          reach = [reach, box[2]].max
        end
        reach >= right - 0.15
      end

      def validate(part, product)
        proof = product.fetch('partial_plan'); ev = part.fetch('elevation_evidence')
        depth = proof.fetch('depth_evidence'); d = Placement.validate_depth_sections(depth, product)
        poses = product.fetch('view_relations').fetch('poses')
        pose = poses.fetch(ev.fetch('front_id')); plan = poses.fetch(product.fetch('plan_view_id'))
        low = ev.fetch('low_mm'); high = ev.fetch('high_mm'); fb = ev.fetch('front_box')
        sb = part.fetch('source_box'); offset = ev.fetch('front_offset_mm')
        base = product.fetch('source_plan_envelope').first(2).zip(product.fetch('plan_origin_offset_mm', [0, 0])).map { |a, b| a + b }
        expected = 2.times.map { |i| base[i] + part['origin'][i] }
        expected += 2.times.map { |i| expected[i] + part['size'][i] }
        unless product['unified_partial_plan'] && proof['engine'] == 'registered-partial-bays-v1' && d &&
               ev['source_signature'] == product.dig('product_height', 'source_signature') &&
               pose['status'] == 'proven' && pose['root_id'] == plan['root_id'] && near(offset, pose['offset_mm']) &&
               RegisteredElevation.box?(fb) && sb.zip(expected).all? { |a, b| near(a, b) } && near(part['size'][1], d) && near(sb[1], depth['low_mm']) &&
               near(part['origin'][2], low) && near(part['size'][2], high - low) && low >= -0.15 && high > low
          raise ArgumentError, 'Khoang chia cục bộ thiếu liên kết mặt bằng/mặt đứng và chiều sâu.'
        end
        case ev['kind']
        when 'bay'
          a, b = ev.fetch('walls'); caps = ev.fetch('caps')
          panels = [a, b] + caps.flatten(1)
          unless panels.all? { |q| RegisteredElevation.box?(q) && RegisteredElevation.stock?([q[2] - q[0], q[3] - q[1]].min) } &&
                 near(a[0] + offset, sb[0]) && near(b[2] + offset, sb[2]) && near(a[1], b[1]) && near(a[3], b[3]) &&
                 near(panels.map { |q| q[1] }.min - fb[1], low) && near(panels.map { |q| q[3] }.max - fb[1], high) &&
                 caps.length == 2 && caps.zip([a[1], a[3]]).all? { |rows, level|
                   !rows.empty? && covers?(rows, a[2], b[0]) && rows.all? { |q| near(q[1], level) || near(q[3], level) }
                 }
            raise ArgumentError, 'Khoang chưa có cặp vách và tấm ngang kín tại cao độ đã đo.'
          end
          witnesses = ev.fetch('plan_witnesses')
          unless !witnesses.empty? && witnesses.all? { |w|
            q = w['source_box']; p = poses[w['view_id']]
            p && p['status'] == 'proven' && p['root_id'] == plan['root_id'] && near(p['offset_mm'], w['offset_mm']) &&
              RegisteredElevation.box?(q) && near(q[0] + w['offset_mm'], sb[0]) && near(q[2] + w['offset_mm'], sb[2]) &&
              (q[3] - q[1] - d).abs <= 1 && !Array(w['handles']).empty?
          }
            raise ArgumentError, 'Biên khoang không khớp các mặt bằng được đối chiếu.'
          end
        when 'trim'
          panels = ev.fetch('panels')
          coverage = panels.map { |q| [q[1], 0, q[3], 1] }
          unless !panels.empty? && panels.all? { |q| RegisteredElevation.box?(q) && RegisteredElevation.stock?(q[2] - q[0]) &&
            near(q[0] + offset, sb[0]) && near(q[2] + offset, sb[2]) } && covers?(coverage, fb[1] + low, fb[1] + high) &&
                 near(panels.map { |q| q[1] }.min - fb[1], low) && near(panels.map { |q| q[3] }.max - fb[1], high)
            raise ArgumentError, 'Nẹp phụ chưa khớp tấm ván đo trên mặt đứng.'
          end
        else raise ArgumentError, 'Chứng cứ chia cục bộ chưa được hỗ trợ.'
        end
        true
      end

      def validate_band(part, product)
        ev = part.fetch('elevation_evidence'); q = ev.fetch('front_band'); fb = ev.fetch('front_box')
        low = ev.fetch('low_mm'); high = ev.fetch('high_mm'); sections = ev.fetch('sections')
        unless ev['kind'] == 'band' && product['unified_partial_plan'] && RegisteredElevation.box?(q) &&
               near(q[1] - fb[1], low) && near(q[3] - fb[1], high) && near(part['origin'][2], low) && near(part['size'][2], high - low) &&
               near(q[0] + ev['front_offset_mm'], part['source_box'][0]) && near(q[2] - q[0], part['size'][0]) &&
               ev['source_signature'] == product.dig('product_height', 'source_signature') && !ev['front_handle'].to_s.empty? &&
               sections.map { |s| s['view_id'] }.uniq.length >= 2
          raise ArgumentError, 'Module chân/nóc chưa khớp một biên kín liên tục trên mặt đứng.'
        end
        sections.each do |s|
          box = s.fetch('section_box'); a, b = s.fetch('panels')
          d0, d1 = s['reversed_depth'] ? [box[2] - b[2], box[2] - a[0]] : [a[0] - box[0], b[2] - box[0]]
          unless [a, b].all? { |r| RegisteredElevation.box?(r) && RegisteredElevation.stock?(r[2] - r[0]) &&
            r[1] - box[1] <= low + 0.15 && r[3] - box[1] >= high - 0.15 } &&
                 near(d0, s['depth_low_mm']) && near(d1, s['depth_high_mm']) && near(part['size'][1], d1 - d0) &&
                 near(product.dig('partial_plan', 'depth_evidence', 'low_mm') + d0, part['source_box'][1]) &&
                 !s['cuts'].empty? && s['cuts'].all? { |c| c['source_x_mm'] >= part['source_box'][0] - 0.15 && c['source_x_mm'] <= part['source_box'][2] + 0.15 }
            raise ArgumentError, 'Chân/nóc thiếu cặp ván đầu/cuối mặt cắt ở đúng cao độ/chiều sâu.'
          end
        end
        true
      end

      def refresh_preview(model, instance, product, root)
        return false unless product['unified_partial_plan'] || product['plan_components']
        old = JSON.parse(instance.get_attribute(Model::DICT, 'analysis'))
        return false unless old['envelope_preview'] || old['unified_partial_plan'] || old['plan_components']
        # Worker analyses do not carry the host's auxiliary-build preference.
        # Preserve the existing setting rather than deleting unchanged trims.
        product = product.merge('build_auxiliary' => old.fetch('build_auxiliary', true)) unless product.key?('build_auxiliary')
        return false if %w[modules trim_parts panel_parts].all? { |key| old[key] == product[key] }
        safe = !old['manual_boxes'] && old['source_hash'] == product['source_hash'] &&
               old['source_plan_envelope'] == product['source_plan_envelope'] && old['plan_view_id'] == product['plan_view_id'] &&
               !Corrections.active? && !model.active_path
        old_parts = Array(old['modules']) + (old['build_auxiliary'] ? Array(old['trim_parts']) : []) + Array(old['panel_parts'])
        new_parts = Array(product['modules']) + (product['build_auxiliary'] ? Array(product['trim_parts']) : []) + Array(product['panel_parts'])
        groups = instance.members
        retained = []; retained_parts = []
        safe &&= groups.length == old_parts.length && groups.all? { |g|
          raw = g.get_attribute(Model::DICT, g.get_attribute(Model::DICT, 'role') == 'module' ? 'source_module' : 'source_part')
          part = raw && JSON.parse(raw)
          keep = part && new_parts.include?(part)
          valid = part && old_parts.include?(part) && ProductHeight.untouched_preview_group(instance, part, g, read_only: !!keep)
          if valid && keep
            retained << g; retained_parts << part
          end
          valid
        }
        raise ArgumentError, 'Box đã sửa/di chuyển/khóa hoặc đang sửa; giữ nguyên. Hoàn tất sửa trước khi thay bằng các module.' unless safe
        Placement.validate_elevation_product(product)
        update = JSON.parse(JSON.generate(product))
        %w[activity_id native_times].each { |key| update[key] = old[key] if old.key?(key) }
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        model.start_operation('CAD2Module: Chia Module', true)
        begin
          before = Storage.snapshot(root, instance, "partial-before-#{Ids.uuid}")
          entities = instance.definition.entities
          product['modules'].each { |part| Model.module_instance(entities, part) unless retained_parts.include?(part) }
          Array(product['trim_parts']).each { |part| Model.reference_part(entities, part) unless retained_parts.include?(part) } if product['build_auxiliary']
          Array(product['panel_parts']).each { |part| Model.panel_part(entities, part) unless retained_parts.include?(part) }
          (groups - retained).each(&:erase!)
          values = instance.data; values['members'] = instance.members.map(&:persistent_id); instance.write(values)
          instance.set_attribute(Model::DICT, 'analysis', JSON.generate(update))
          after = Storage.snapshot(root, instance, "partial-after-#{Ids.uuid}")
          Storage.event(root, 'kind' => 'partial_module_refresh', 'code' => old['code'], 'product_id' => instance.persistent_id,
                        'activity_id' => old['activity_id'], 'before' => old, 'analysis' => update, 'before_skp' => before, 'skp' => after,
                        'retained_group_ids' => retained.map(&:persistent_id), 'seconds' => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
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

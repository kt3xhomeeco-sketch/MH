# encoding: UTF-8
#
# MH_Registry / connectors / dc_import / materials.rb
# ---------------------------------------------------------------------------
# Material assignment/bootstrap helpers for DCImportPipeline.
# ---------------------------------------------------------------------------

module MH
  module RegistryApp
    module Connectors
      module DCImportPipeline
        module_function

        def assign_profile_materials(instance, profile)
          return unless instance && instance.valid?

          model = Sketchup.active_model
          panel_mat = material_for(model, profile['panel_material'], profile['panel_source_material'])
          back_mat = material_for(model, profile['back_material'], profile['back_source_material'])
          product_code = profile['product_code'].to_s.strip
          product_code = instance.get_attribute('MH_Registry', 'dc_product_code').to_s.strip if product_code.empty?

          # Single-thickness mode: khi binding khai panel nhung khong khai back,
          # nghia la moi panel (ke ca tam hau) deu cung do day -> material code
          # cung phai dong nhat panel_mat. Tranh case "tam hau 17.6mm nhung ma
          # MDFCA.6.AC".
          binding = profile['_binding'] || profile[:_binding]
          single_thickness = binding &&
                             !binding['param_panel'].to_s.strip.empty? &&
                             binding['param_back'].to_s.strip.empty?

          model.start_operation('MH DC Import Materials', true)
          stats = { 'panel' => 0, 'back' => 0, 'excel' => 0, 'fallback' => 0, 'miss' => 0 }
          visible_groups(instance).each do |group|
            resolved = resolve_material_for_group(group, instance, profile, binding, product_code)
            is_back = resolved && resolved['role'] == 'back'
            if resolved && !resolved['material_name'].to_s.empty?
              target = material_for(model, resolved['material_name'])
              stats['excel'] += 1
            else
              thickness_info = resolve_thickness_for_group(group, profile, binding, instance)
              material_thickness_mm = material_thickness_for_group(group, profile, thickness_info)
              is_back = !single_thickness && (thickness_info['role'] == 'back' || back_group?(group))
              fallback_detail = detail_candidates_for_group(group, instance, binding, thickness_info['key']).first
              fallback_detail = fallback_detail && fallback_detail['detail']
              fallback_detail = detail_name_for_role(is_back ? 'back' : 'panel') if fallback_detail.to_s.strip.empty?
              fallback_name = material_name_from_code(profile['material_code'], material_thickness_mm) rescue ''
              if fallback_name.empty?
                fallback_name = (is_back ? profile['back_material'] : profile['panel_material']).to_s.strip
              end
              fallback_name = surface_face_material_name(
                fallback_name,
                group,
                material_thickness_mm,
                { 'material_detail' => fallback_detail, 'product_code' => product_code },
                profile
              )
              source_name = is_back ? profile['back_source_material'] : profile['panel_source_material']
              target = material_for(
                model,
                fallback_name.empty? ? (is_back ? back_mat.name : panel_mat.name) : fallback_name,
                source_name
              )
              stats['fallback'] += 1
              stats['miss'] += 1 if !product_code.empty?
            end
            next if group.material == target && group.get_attribute('dynamic_attributes', 'material') == target.name
            assign_material(group, target)
            stats[is_back ? 'back' : 'panel'] += 1
          end
          model.commit_operation
          puts "[DCImportPipeline] materials panel=#{stats['panel']} back=#{stats['back']} excel=#{stats['excel']} fallback=#{stats['fallback']} miss=#{stats['miss']}#{single_thickness ? ' (single-thickness)' : ''}"
          stats
        rescue => e
          model.abort_operation rescue nil
          raise e
        end

        def resolve_material_for_group(group, instance, profile, binding, product_code)
          return nil if product_code.to_s.strip.empty?

          material_assign = material_assign_connector
          return nil unless material_assign &&
                            material_assign.respond_to?(:material_row_for_product) &&
                            material_assign.respond_to?(:material_name_for_code)

          thickness_info = resolve_thickness_for_group(group, profile, binding, instance)
          material_thickness_mm = material_thickness_for_group(group, profile, thickness_info)
          detail_candidates_for_group(group, instance, binding, thickness_info['key']).each do |candidate|
            spec = material_assign.material_row_for_product(product_code, candidate['detail'])
            next unless spec && spec['ok']
            unless material_spec_relevant_for_candidate?(candidate['detail'], spec)
              puts "[DCImportPipeline] skip unrelated material match for #{product_code} #{candidate['detail']}: #{spec['excel_detail']} -> #{spec['material_code']}"
              next
            end

            raw_code = spec['material_code'].to_s.strip
            codes = material_code_parts(raw_code)
            if codes.length > 1
              puts "[DCImportPipeline] skip multi material bootstrap for #{product_code} #{candidate['detail']}: #{raw_code}"
              next
            end

            chosen_code = codes.first || raw_code
            material_name = material_assign.material_name_for_code(chosen_code, material_thickness_mm)
            next if material_name.to_s.strip.empty?
            surface_detail = surface_face_detail_for_material(candidate['detail'], spec)
            material_name = surface_face_material_name(
              material_name,
              group,
              material_thickness_mm,
              { 'material_detail' => surface_detail, 'product_code' => product_code },
              profile
            )

            return {
              'material_name' => material_name.to_s.strip,
              'role' => thickness_info['role'],
              'detail' => candidate['detail'],
              'surface_detail' => surface_detail,
              'source' => candidate['source'],
              'excel_detail' => spec['excel_detail'].to_s,
              'material_code' => chosen_code.to_s,
              'material_thickness_mm' => material_thickness_mm
            }
          end

          nil
        rescue => e
          puts "[DCImportPipeline] resolve material error: #{e.class}: #{e.message}"
          nil
        end

        def material_spec_relevant_for_candidate?(candidate_detail, spec)
          excel_detail = spec && spec['excel_detail'].to_s.strip
          return false if excel_detail.empty?

          product = spec['product_code'].to_s
          candidate = strip_product_prefix(candidate_detail.to_s, product)
          candidate_key = material_match_key(candidate)
          excel_key = material_match_key(excel_detail)
          return false if candidate_key.empty? || excel_key.empty?
          return true if candidate_key == excel_key
          return true if candidate_key.include?(excel_key)
          return true if excel_key.include?(candidate_key) && candidate_key.length >= 4

          alias_key = material_alias_target_key(candidate_key)
          !alias_key.empty? && (excel_key == alias_key || excel_key.include?(alias_key))
        rescue
          false
        end

        def material_alias_target_key(candidate_key)
          return '' unless defined?(MH::MaterialApp) && MH::MaterialApp.respond_to?(:detail_aliases)

          MH::MaterialApp.detail_aliases.each do |pattern, target|
            pattern_key = material_match_key(pattern)
            next if pattern_key.empty?
            return material_match_key(target) if candidate_key.include?(pattern_key)
          end
          ''
        rescue
          ''
        end

        def detail_candidates_for_group(group, instance, binding, driver_key = nil)
          candidates = []
          add_detail_candidate(candidates, group.name, 'group.name')
          add_detail_candidate(candidates, group.get_attribute('dynamic_attributes', 'name'), 'group.da.name')
          add_detail_candidate(candidates, group.get_attribute('dynamic_attributes', '_name'), 'group.da._name')

          key = driver_key.to_s.strip
          key = attr_driving_thickness_for_group(group, binding).to_s.strip if key.empty?
          add_detail_candidate(candidates, formlabel_for_attr(instance, key), 'formlabel') unless key.empty?
          add_detail_candidate(candidates, detail_name_for_role(role_from_binding_key(key, binding)), 'binding.role') unless key.empty?
          add_detail_candidate(candidates, back_group?(group) ? 'hậu' : 'khung', 'legacy.role')
          candidates
        end

        def add_detail_candidate(candidates, value, source)
          text = clean_dc_meta_text(value)
          return if text.empty?

          key = material_match_key(text)
          return if key.empty? || candidates.any? { |item| item['key'] == key }

          candidates << { 'detail' => text, 'key' => key, 'source' => source }
        end

        def resolve_thickness_for_group(group, profile, binding, instance = nil)
          key = attr_driving_thickness_for_group(group, binding).to_s.strip
          role = role_from_binding_key(key, binding)
          role = infer_role_from_group_thickness(group, profile, instance, key) if role.empty?
          role = back_group?(group) ? 'back' : 'panel' if role.empty?
          role = role == 'hậu' ? 'back' : role
          role = 'panel' unless role == 'back'

          {
            'key' => key,
            'role' => role,
            'thickness_mm' => role == 'back' ? profile['back_thickness_mm'].to_f : profile['panel_thickness_mm'].to_f
          }
        end

        # Fallback cho DC cũ chưa khai binding: một số file ngăn kéo có tấm đáy
        # dùng biến "Bottom Thickness" / tên "Đáy" và hình học đã đúng độ dày
        # hậu/back, nhưng heuristic cũ chỉ nhận "hậu/back" nên vật liệu bị dựng
        # theo panel thickness. Không mark mọi "Đáy" là back: chỉ đổi vai khi
        # tên/label có dấu hiệu đáy-bottom-hậu VÀ độ dày thực tế gần back hơn panel.
        def infer_role_from_group_thickness(group, profile, instance = nil, driver_key = nil)
          panel_mm = profile && profile['panel_thickness_mm'].to_f
          back_mm = profile && profile['back_thickness_mm'].to_f
          return '' unless panel_mm && back_mm && panel_mm > 0 && back_mm > 0
          return '' if (panel_mm - back_mm).abs < 0.05

          text = [
            group.name,
            (group.definition.name rescue nil),
            group.get_attribute('dynamic_attributes', 'name'),
            group.get_attribute('dynamic_attributes', '_name'),
            (driver_key.to_s.strip.empty? ? nil : formlabel_for_attr(instance, driver_key))
          ].compact.join(' ')

          return '' unless back_like_detail_text?(text)

          current_mm = current_group_thickness_mm(group)
          if current_mm && current_mm > 0
            back_delta = (current_mm - back_mm).abs
            panel_delta = (current_mm - panel_mm).abs
            return 'back' if back_delta <= [0.25, panel_delta * 0.75].max
            return 'panel' if panel_delta < back_delta
          end

          key = material_match_key(text)
          return 'back' if key.include?('bottom thickness')
          ''
        rescue
          ''
        end

        def back_like_detail_text?(text)
          raw = text.to_s.downcase
          key = material_match_key(text)
          raw.include?('hậu') ||
            raw.include?('đáy') ||
            key.include?('hau') ||
            key.include?('back') ||
            key.include?('bottom')
        rescue
          false
        end

        def current_group_thickness_mm(group)
          dims = %w[lenx leny lenz].map do |axis|
            value = group.get_attribute('dynamic_attributes', axis)
            number = value.to_f
            number > 0 ? number * 25.4 : nil
          rescue
            nil
          end.compact
          dims.min
        rescue
          nil
        end

        def material_thickness_for_group(group, profile, thickness_info = nil)
          actual = current_group_thickness_mm(group).to_f
          if actual > 0
            return normalized_material_thickness(actual, profile)
          end

          fallback = thickness_info && thickness_info['thickness_mm'].to_f
          fallback && fallback > 0 ? fallback : profile['panel_thickness_mm'].to_f
        rescue
          thickness_info && thickness_info['thickness_mm'].to_f
        end

        def normalized_material_thickness(value, profile)
          mm = value.to_f
          [profile['panel_thickness_mm'], profile['back_thickness_mm']].map(&:to_f).each do |candidate|
            next unless candidate > 0
            return candidate if (mm - candidate).abs <= 0.25
          end

          mm.round(1)
        rescue
          value.to_f
        end

        def attr_driving_thickness_for_group(group, binding = nil)
          formulas = %w[lenx leny lenz].map do |axis|
            value = group.get_attribute('dynamic_attributes', axis).to_f
            formula = group.get_attribute('dynamic_attributes', "_#{axis}_formula").to_s
            [axis, value, formula]
          end

          preferred = binding_thickness_keys(binding)
          thickness_axis = formulas.select { |_axis, value, _formula| value > 0 }.min_by { |_axis, value, _formula| value.to_f }
          if thickness_axis
            _axis, _value, formula = thickness_axis
            keys = dc_formula_attr_keys(formula)
            hit = keys.find { |key| preferred.include?(key.downcase) }
            return hit if hit
            return keys.first.to_s unless keys.empty?
          end

          formulas.each do |_axis, _value, formula|
            keys = dc_formula_attr_keys(formula)
            hit = keys.find { |key| preferred.include?(key.downcase) }
            return hit if hit
          end

          ''
        rescue
          ''
        end

        def dc_formula_attr_keys(formula)
          text = formula.to_s
          keys = text.scan(/\bparent!([A-Za-z][A-Za-z0-9_]*)\b/i).flatten
          if text =~ /\A[A-Za-z][A-Za-z0-9_]*\z/i
            keys << text
          end
          keys.map(&:to_s).map(&:strip).reject(&:empty?).reject { |key| %w[lenx leny lenz].include?(key.downcase) }.uniq
        end

        def binding_thickness_keys(binding)
          keys = []
          split_attr_specs(binding && binding['param_panel']).each { |spec| keys << attr_spec_key(spec) }
          split_attr_specs(binding && binding['param_back']).each { |spec| keys << attr_spec_key(spec) }
          extra_attr_pairs(binding && binding['param_extra']).each { |spec, _raw| keys << attr_spec_key(spec) }
          keys.map(&:to_s).map(&:downcase).reject(&:empty?).uniq
        rescue
          []
        end

        def role_from_binding_key(key, binding)
          clean = key.to_s.strip.downcase
          return '' if clean.empty? || !binding

          split_attr_specs(binding['param_back']).each do |spec|
            return 'back' if attr_spec_key(spec).to_s.downcase == clean
          end

          split_attr_specs(binding['param_panel']).each do |spec|
            return 'panel' if attr_spec_key(spec).to_s.downcase == clean
          end

          extra_attr_pairs(binding['param_extra']).each do |spec, raw|
            next unless attr_spec_key(spec).to_s.downcase == clean
            token = raw.to_s.strip.downcase
            return 'back' if %w[back hau hậu back_mm param_back].include?(token)
            return 'panel' if %w[panel panel_mm param_panel].include?(token)
          end

          ''
        end

        def detail_name_for_role(role)
          case role.to_s
          when 'back' then 'hậu'
          when 'panel' then 'khung'
          else ''
          end
        end

        def formlabel_for_attr(instance, key)
          clean = key.to_s.strip
          return '' if clean.empty?

          values = []
          values << instance.get_attribute('dynamic_attributes', "_#{clean}_formlabel") if instance
          values << instance.get_attribute('dynamic_attributes', "_#{clean}_label") if instance
          if instance && instance.respond_to?(:definition) && instance.definition
            values << instance.definition.get_attribute('dynamic_attributes', "_#{clean}_formlabel")
            values << instance.definition.get_attribute('dynamic_attributes', "_#{clean}_label")
          end
          values.map { |value| clean_dc_meta_text(value) }.find { |value| !value.empty? }.to_s
        rescue
          ''
        end

        def material_code_parts(raw_code)
          if defined?(MH::MaterialCode) && MH::MaterialCode.respond_to?(:split)
            return MH::MaterialCode.split(raw_code)
          end

          raw_code.to_s.split(/\s*&\s*/).map(&:strip).reject(&:empty?)
        end

        def material_assign_connector
          return nil unless defined?(MH::RegistryApp::Connector)

          MH::RegistryApp::Connector.get('material_assign') rescue nil
        end

        def material_match_key(text)
          material_assign = material_assign_connector
          return material_assign.match_key(text) if material_assign && material_assign.respond_to?(:match_key)
          return MH::Text.fold(text).gsub(/[#]+/, ' ').gsub(/\s+/, ' ').strip if defined?(MH::Text) && MH::Text.respond_to?(:fold)

          text.to_s.downcase.gsub(/[#]+/, ' ').gsub(/\s+/, ' ').strip
        end

        def assign_material(group, material)
          return unless group && group.valid? && material

          group.material = material
          name = material.name.to_s
          group.set_attribute('dynamic_attributes', 'material', name)
          group.set_attribute('dynamic_attributes', '_material_formula', "\"#{name}\"")
          group.set_attribute('dynamic_attributes', '_material_error', name)
        end

        def material_for(model, name, source_name = nil)
          clean = name.to_s.strip
          clean = 'MH_DC_MATERIAL' if clean.empty?
          existing = model.materials[clean]
          return existing if existing

          source_clean = source_name.to_s.strip
          unless source_clean.empty? || source_clean.casecmp(clean).zero?
            source = material_for(model, source_clean)
            if source
              target = model.materials.add(clean)
              target.alpha = source.alpha if target.respond_to?(:alpha=) && source.respond_to?(:alpha)
              if source.texture
                target.color = source.color
                target.texture = source.texture.filename
                target.texture.size = source.texture.size if target.texture && source.texture.respond_to?(:size)
              elsif defined?(MH::MaterialApp::MaterialCreator)
                MH::MaterialApp::MaterialCreator.ensure_visible_color(target, clean, model, force: true)
              else
                target.color = color_for(clean)
              end
              target.set_attribute('MH_MaterialApp', 'SourceMaterial', source_clean) rescue nil
              return target
            end
          end

          if defined?(MH::MaterialApp::MaterialCreator) &&
             MH::MaterialApp::MaterialCreator.respond_to?(:load_material_from_file)
            loaded = MH::MaterialApp::MaterialCreator.load_material_from_file(model, clean)
            return loaded if loaded
          end

          mat = model.materials.add(clean)
          mat.color = color_for(clean)
          mat
        end

        def color_for(name)
          seed = name.to_s.each_byte.reduce(0) { |acc, byte| ((acc * 33) + byte) & 0xffffffff }
          Sketchup::Color.new(60 + seed % 156, 60 + (seed / 7) % 156, 60 + (seed / 17) % 156)
        end

        def resolve_product_materials(instance, profile, context = {})
          resolved = profile.dup
          product = context_value(context, :product_code, 'product_code')
          product = resolve_product_code(instance, context) if product.to_s.strip.empty?
          return resolved if product.to_s.strip.empty?

          material = resolve_material_names(product, resolved, context, instance)
          return resolved unless material && material['ok']

          resolved['product_code'] = product
          resolved['material_code'] = material['material_code'].to_s.strip unless material['material_code'].to_s.strip.empty?
          resolved['panel_material'] = material['panel_material'].to_s.strip unless material['panel_material'].to_s.strip.empty?
          resolved['back_material'] = material['back_material'].to_s.strip unless material['back_material'].to_s.strip.empty?
          resolved['panel_source_material'] = material['panel_source_material'].to_s.strip unless material['panel_source_material'].to_s.strip.empty?
          resolved['back_source_material'] = material['back_source_material'].to_s.strip unless material['back_source_material'].to_s.strip.empty?
          resolved['panel_code'] = material['panel_code'].to_s.strip unless material['panel_code'].to_s.strip.empty?
          resolved['back_code'] = material['back_code'].to_s.strip unless material['back_code'].to_s.strip.empty?
          resolved['source_detail'] = material['excel_detail'].to_s.strip unless material['excel_detail'].to_s.strip.empty?
          resolved['profile_name'] = "#{product} | #{resolved['profile_name']}"
          resolved
        rescue => e
          puts "[DCImportPipeline] resolve product material error: #{e.class}: #{e.message}"
          profile
        end


        def resolve_material_names(product_code, profile, context = {}, instance = nil)
          return nil unless defined?(MH::RegistryApp::Connector)
          material_assign = MH::RegistryApp::Connector.get('material_assign') rescue nil
          return nil unless material_assign && material_assign.respond_to?(:material_names_for_product)

          detail = material_detail_for_context(context, profile)
          detail = 'khung' if detail.to_s.strip.empty?
          profile_code = profile['material_code'].to_s.strip
          if !profile_code.empty? && material_assign.respond_to?(:material_names_for_code)
            names = material_assign.material_names_for_code(
              profile_code,
              profile['panel_thickness_mm'],
              profile['back_thickness_mm']
            )
            return apply_surface_face_suffix_to_names(names, instance, context, profile) if names && names['ok']
          end

          if material_assign.respond_to?(:material_spec_for_product)
            spec = material_assign.material_spec_for_product(product_code, detail)
            if spec && spec['ok'] && !spec['material_code'].to_s.strip.empty? && material_assign.respond_to?(:material_names_for_code)
              names = material_assign.material_names_for_code(
                spec['material_code'],
                profile['panel_thickness_mm'],
                profile['back_thickness_mm']
              )
              return apply_surface_face_suffix_to_names(spec.merge(names || {}), instance, context, profile) if names && names['ok']
            end
          end
          names = material_assign.material_names_for_product(
            product_code,
            profile['panel_thickness_mm'],
            profile['back_thickness_mm'],
            detail
          )
          names && names['ok'] ? apply_surface_face_suffix_to_names(names, instance, context, profile) : names
        rescue => e
          puts "[DCImportPipeline] resolve material names error: #{e.class}: #{e.message}"
          nil
        end

        def apply_surface_face_suffix_to_names(names, instance, context = {}, profile = nil)
          result = names.dup
          result['panel_material'] = surface_face_material_name(
            result['panel_material'],
            instance,
            result['panel_thickness_mm'] || (profile && profile['panel_thickness_mm']),
            context,
            profile
          )
          result['back_material'] = surface_face_material_name(
            result['back_material'],
            instance,
            result['back_thickness_mm'] || (profile && profile['back_thickness_mm']),
            context,
            profile
          )
          result
        end

        def surface_face_material_name(material_name, instance, thickness_mm, context = {}, profile = nil)
          name = material_name.to_s.strip
          return name if name.empty?
          return name unless defined?(MH::MaterialApp::MaterialAssigner) &&
                             MH::MaterialApp::MaterialAssigner.respond_to?(:apply_surface_face_suffix)

          detail = material_detail_for_context(context || {}, profile)
          parsed = { detail_name: detail, raw_name: detail }
          MH::MaterialApp::MaterialAssigner.apply_surface_face_suffix(name, instance, thickness_mm, parsed).to_s.strip
        rescue => e
          puts "[DCImportPipeline] surface face suffix error: #{e.class}: #{e.message}"
          name
        end

        def surface_face_detail_for_material(candidate_detail, spec = nil)
          detail = spec && spec['excel_detail'].to_s.strip
          detail = candidate_detail.to_s.strip if detail.to_s.empty?
          detail
        rescue
          candidate_detail.to_s.strip
        end

        def material_detail_for_context(context = {}, profile = nil)
          detail = context_value(context || {}, :material_detail, 'material_detail').to_s.strip
          detail = profile['material_detail'].to_s.strip if detail.empty? && profile
          detail = context_value(context || {}, :import_name, 'import_name').to_s.strip if detail.empty?
          strip_product_prefix(detail, context_value(context || {}, :product_code, 'product_code').to_s)
        rescue
          ''
        end

        def preferred_material_code_for_context(product_code, context = nil)
          return '' if product_code.to_s.strip.empty?
          return '' unless defined?(MH::RegistryApp::Connector)

          material_assign = MH::RegistryApp::Connector.get('material_assign') rescue nil
          return '' unless material_assign && material_assign.respond_to?(:material_spec_for_product)

          detail = material_detail_for_context(context || {}, nil)
          spec = material_assign.material_spec_for_product(product_code, detail)
          spec && spec['ok'] ? spec['material_code'].to_s.strip : ''
        rescue => e
          puts "[DCImportPipeline] preferred material code error: #{e.class}: #{e.message}"
          ''
        end

      end
    end
  end
end

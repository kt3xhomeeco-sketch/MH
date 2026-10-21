#
# MH_Registry / connectors / dc_import_pipeline.rb
# ---------------------------------------------------------------------------
# Registry-owned coordinator for Dynamic Component import post-processing.
# MH_Superimp only sends import/context events; profile selection and future
# material/thickness rules live here.
# ---------------------------------------------------------------------------

dc_import_dir = File.join(File.dirname(__FILE__), 'dc_import')
%w[config material_code traversal dc_attrs thickness_selection hud naming geometry materials].each do |part|
  load File.join(dc_import_dir, "#{part}.rb")
end

module MH
  module RegistryApp
    module Connectors
      module DCImportPipeline
        DEFERRED_PROFILE_FINISH_DELAY = 0.10 unless const_defined?(:DEFERRED_PROFILE_FINISH_DELAY)

        module_function
        def after_import_dc(instance, context = {})
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          profile = if context && context[:material_profile].is_a?(Hash)
                      context[:material_profile]
                    elsif context && context['material_profile'].is_a?(Hash)
                      context['material_profile']
                    else
                      selected_profile(context)
          end
          profile = normalize_profile(profile)
          use_manual_materials = manual_mode?(context)
          profile = resolve_product_materials(instance, profile, context) unless use_manual_materials
          if default_profile?(profile)
            thickness_profile = selected_thickness_profile_for_material_code(profile['material_code'], context)
            if thickness_profile
              thickness_profile['product_code'] = profile['product_code']
              thickness_profile['source_detail'] = profile['source_detail']
              profile = use_manual_materials ? thickness_profile : resolve_product_materials(instance, thickness_profile, context)
            end
          end
          profile['_binding'] = binding_for(context, instance)
          # Import only applies the chosen material/thickness. Product/module
          # naming must not stamp SP metadata onto the DC or its child groups.

          instance.set_attribute('MH_Registry', 'dc_material_profile_id', profile['profile_id'] || profile[:profile_id]) if instance && instance.valid?
          instance.set_attribute('MH_Registry', 'dc_material_profile_name', profile['profile_name'] || profile[:profile_name] || profile['label'] || profile[:label]) if instance && instance.valid?
          # SP is transient import context for material/thickness selection.
          # Import must not stamp product ownership onto the placed DC.
          instance.set_attribute('MH_Registry', 'dc_material_code', profile['material_code']) if instance && instance.valid? && !profile['material_code'].to_s.empty?

          apply_profile(instance, profile) if instance && instance.valid?

          setup_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0).round(1)
          @last_profile_timing = {
            'pid' => (instance.persistent_id rescue nil),
            'setup_ms' => setup_ms,
            'status' => 'pending'
          }
          MH::RegistryApp.dbg("[DCImportPipeline] after_import_dc pid=#{instance.persistent_id rescue '?'} setup_ms=#{setup_ms} profile=#{profile.inspect}") if MH::RegistryApp.respond_to?(:dbg)
          { 'ok' => true, 'profile' => profile, 'label' => profile_label(profile) }
        rescue => e
          MH::RegistryApp.dbg("[DCImportPipeline] after_import_dc error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          { 'ok' => false, 'error' => e.message }
        end

        # Public: ap NHANH do day vao 1 DC dang co (vd HUD Superimp go so + Enter
        # khi dang chon DC). Chi ap do day (+ vat lieu theo apply_profile), KHONG
        # doi ten. Binding resolve tu chinh DC. panel/back tinh bang mm.
        def apply_quick_thickness(instance, panel_mm, back_mm = nil, context = {})
          return { 'ok' => false, 'error' => 'instance khong hop le' } unless instance && instance.valid?

          ctx = (context || {}).dup
          rd = instance.attribute_dictionary('MH_Registry')
          ctx[:import_name] = instance.definition.name if ctx[:import_name].to_s.strip.empty? rescue nil
          ctx[:product_code] = (rd && rd['dc_product_code']).to_s if ctx[:product_code].to_s.strip.empty? rescue nil
          panel = panel_mm.to_f
          back = back_mm.nil? ? panel : back_mm.to_f
          profile = normalize_profile({
            'profile_id' => "quick::#{panel}::#{back}",
            'profile_name' => "Quick #{panel}/#{back}",
            'material_code' => (rd && rd['dc_material_code']).to_s,
            'panel_thickness_mm' => panel,
            'back_thickness_mm' => back
          })
          profile['_binding'] = binding_for(ctx, instance)
          instance.set_attribute('MH_Registry', 'dc_panel_thickness_mm', panel)
          instance.set_attribute('MH_Registry', 'dc_back_thickness_mm', back)
          apply_profile(instance, profile)
          { 'ok' => true, 'panel' => panel, 'back' => back }
        rescue => e
          MH::RegistryApp.dbg("[DCImportPipeline] apply_quick_thickness error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          { 'ok' => false, 'error' => e.message }
        end

        def apply_naming_to_selection(product_code = nil)
          model = Sketchup.active_model
          selection = model.selection.to_a.select { |entity| entity.is_a?(Sketchup::ComponentInstance) && entity.valid? }
          return { 'ok' => false, 'error' => 'Chua chon Dynamic Component/Component.' } if selection.empty?

          count = 0
          selection.each do |instance|
            rd = instance.attribute_dictionary('MH_Registry', false)
            product = product_code.to_s.strip
            product = rd['dc_product_code'].to_s.strip if product.empty? && rd
            context = {
              product_code: product,
              import_name: instance.respond_to?(:definition) && instance.definition ? instance.definition.name.to_s : instance.name.to_s,
              source: 'MH_Superimp'
            }
            profile = { 'product_code' => product }
            profile['_binding'] = binding_for(context, instance)
            naming = resolve_dc_naming(instance, profile, context)
            next if naming.empty?

            apply_dc_naming(instance, naming)
            count += 1
          end
          { 'ok' => true, 'count' => count }
        rescue => e
          { 'ok' => false, 'error' => e.message }
        end

        def context_value(context, *keys)
          keys.each do |key|
            return context[key] if context.respond_to?(:key?) && context.key?(key)
          end
          nil
        end

        def resolve_product_code(instance, context = {})
          return '' unless defined?(MH::RegistryApp::Connector)
          thongke = MH::RegistryApp::Connector.get('thongke') rescue nil
          return '' unless thongke && thongke.respond_to?(:resolve_product_for_import)

          result = thongke.resolve_product_for_import(instance, context)
          result['product_code'].to_s.strip
        rescue => e
          MH::RegistryApp.dbg("[DCImportPipeline] resolve product error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          ''
        end

        def apply_profile(instance, profile)
          model = Sketchup.active_model
          binding = profile['_binding'] || profile[:_binding]

          # Key + unit lấy từ binding của file; fallback key cứng cũ (unit length).
          # QUAN TRỌNG: khi binding ton tai, ton trong dung gia tri user khai —
          # khong fallback BACK_THICKNESS_KEY/PANEL_THICKNESS_KEY. Lien quan bug
          # "ghi de": binding khong khai back -> apply_profile van ghi back_mm vao
          # constant ikqikbwfw7, de len panel write truoc do.
          explicit_panel_binding = binding && !binding['param_panel'].to_s.strip.empty?
          explicit_back_binding = binding && !binding['param_back'].to_s.strip.empty?
          panel_key = if binding
                        binding['param_panel'].to_s.strip
                      else
                        PANEL_THICKNESS_KEY
                      end
          back_key  = if binding
                        binding['param_back'].to_s.strip
                      else
                        BACK_THICKNESS_KEY
                      end
          extra_specs = binding ? binding['param_extra'].to_s : ''
          unit = binding && !binding['unit'].to_s.strip.empty? ? binding['unit'].to_s.strip.downcase : 'length'

          panel_mm = profile['panel_thickness_mm']
          back_mm  = profile['back_thickness_mm']
          panel_specs = split_attr_specs(panel_key)
          back_specs = split_attr_specs(back_key)
          inferred_thickness_params = false
          unless binding
            inferred_panel_specs = inferred_thickness_attr_specs(instance, 'panel', profile)
            inferred_back_specs = inferred_thickness_attr_specs(instance, 'back', profile)
            inferred_thickness_params = !inferred_panel_specs.empty? || !inferred_back_specs.empty?
            # Nếu đã đọc được key thật từ formula của DC (vd parent!eqgyit1tf1),
            # dùng key đó và bỏ key fallback cứng để tránh ghi rác 17.6/11 vào
            # attr không thuộc DC hiện tại.
            panel_specs = inferred_panel_specs.empty? ? panel_specs : inferred_panel_specs
            back_specs = inferred_back_specs.empty? ? back_specs : inferred_back_specs
          end
          panel_specs = [] unless panel_mm.to_f > 0
          back_specs = [] unless back_mm.to_f > 0
          return if panel_specs.empty? && back_specs.empty?
          extra_pairs = extra_attr_pairs(extra_specs)
          allow_create_attrs = !binding || [panel_specs, back_specs].flatten.any? { |spec| attr_spec_scope(spec) == 'root' }
          # Nếu có binding: chỉ ghi key được khai (back trống ⇒ DC 1 giá trị, bỏ hậu).
          write_back = if binding
                         !back_specs.empty?
                       else
                         true
                       end

          profile_metadata = lambda do
            instance.set_attribute('MH_Registry', 'dc_panel_thickness_mm', panel_mm)
            instance.set_attribute('MH_Registry', 'dc_back_thickness_mm', back_mm) if write_back
            instance.set_attribute('MH_Registry', 'dc_panel_material', profile['panel_material'].to_s)
            instance.set_attribute('MH_Registry', 'dc_back_material', profile['back_material'].to_s)
            instance.set_attribute('MH_Registry', 'dc_material_code', profile['material_code'].to_s) unless profile['material_code'].to_s.empty?
          end

          changed = false
          if unit != 'none'
            panel_specs.each { |spec| changed ||= dc_attr_changed_for_spec(instance, spec, panel_mm, unit, 'panel', allow_create_attrs) }
            back_specs.each { |spec| changed ||= dc_attr_changed_for_spec(instance, spec, back_mm, unit, 'back', allow_create_attrs) } if write_back
            extra_pairs.each do |spec, raw|
              value = extra_attr_value(raw, profile, unit)
              targets = attr_targets_for_spec(instance, spec, nil, allow_create_attrs)
              key = attr_spec_key(spec)
              changed ||= targets.any? { |target| dc_attr_raw_changed?(target, key, value) }
            end
          end

          if changed
            model.start_operation('MH DC Import Profile', true)
            panel_specs.each { |spec| set_dc_attr_spec(instance, spec, panel_mm, unit, 'panel', allow_create_attrs) }
            back_specs.each { |spec| set_dc_attr_spec(instance, spec, back_mm, unit, 'back', allow_create_attrs) } if write_back
            extra_pairs.each do |spec, raw|
              set_dc_attr_raw_spec(instance, spec, extra_attr_value(raw, profile, unit), nil, allow_create_attrs)
            end
            profile_metadata.call
            model.commit_operation
          else
            model.start_operation('MH DC Import Metadata', true)
            profile_metadata.call
            model.commit_operation
          end

          # Redraw DC co the rat nang. Chay dong bo tai day se khoa callback click
          # dat vi tri, trong khi pipeline vat lieu phia duoi von da can doi DC on
          # dinh. De timer thuc hien mot lan redraw duy nhat sau khi callback tra ve.
          schedule_deferred_profile_finish(instance, profile, binding, inferred_thickness_params, false)
        rescue => e
          model.abort_operation rescue nil
          raise e
        end

        def schedule_deferred_profile_finish(instance, profile, binding, inferred_thickness_params, did_sync_redraw)
          return unless instance && instance.valid?

          key = instance.persistent_id rescue instance.object_id
          @deferred_profile_finish_generations ||= {}
          generation = @deferred_profile_finish_generations[key].to_i + 1
          @deferred_profile_finish_generations[key] = generation
          profile_snapshot = profile.dup
          binding_snapshot = binding ? binding.dup : nil

          UI.start_timer(DEFERRED_PROFILE_FINISH_DELAY, false) do
            begin
              current = @deferred_profile_finish_generations && @deferred_profile_finish_generations[key]
              next unless current == generation
              next unless instance && instance.valid?

              # Neu co binding thi DC phai tu cap nhat geometry tu input root.
              # Fallback scale tay chỉ dùng cho DC không có binding VÀ không suy
              # ra được tham số thickness thật từ formula.
              phase_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              redraw_dc(instance) unless did_sync_redraw
              redraw_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - phase_started_at) * 1000.0).round(1)

              geometry_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              ensure_profile_geometry_thickness(instance, profile_snapshot) unless binding_snapshot || inferred_thickness_params
              geometry_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - geometry_started_at) * 1000.0).round(1)

              materials_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              assign_profile_materials(instance, profile_snapshot)
              materials_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - materials_started_at) * 1000.0).round(1)
              total_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - phase_started_at) * 1000.0).round(1)
              @last_profile_timing = {
                'pid' => (instance.persistent_id rescue nil),
                'setup_ms' => (@last_profile_timing && @last_profile_timing['setup_ms']),
                'redraw_ms' => redraw_ms,
                'geometry_ms' => geometry_ms,
                'materials_ms' => materials_ms,
                'total_ms' => total_ms,
                'status' => 'finished'
              }
              if MH::RegistryApp.respond_to?(:dbg)
                MH::RegistryApp.dbg("[DCImportPipeline] finish pid=#{instance.persistent_id rescue '?'} redraw_ms=#{redraw_ms} geometry_ms=#{geometry_ms} materials_ms=#{materials_ms} total_ms=#{total_ms}")
              end
              Sketchup.status_text = "VL: #{profile_label(profile_snapshot)}"
            rescue => timer_error
              @last_profile_timing = (@last_profile_timing || {}).merge(
                'pid' => (instance.persistent_id rescue nil),
                'status' => 'error',
                'error' => "#{timer_error.class}: #{timer_error.message}"
              )
              MH::RegistryApp.dbg("[DCImportPipeline] apply timer error: #{timer_error.class}: #{timer_error.message}") if MH::RegistryApp.respond_to?(:dbg)
            ensure
              @deferred_profile_finish_generations.delete(key) if @deferred_profile_finish_generations && @deferred_profile_finish_generations[key] == generation
            end
          end
        end

        def last_profile_timing
          @last_profile_timing ? @last_profile_timing.dup : nil
        end

        def profile_thickness_changed?(instance, profile)
          panel = profile['panel_thickness_mm'].to_f.mm.to_f
          back = profile['back_thickness_mm'].to_f.mm.to_f
          current_panel = instance.get_attribute('dynamic_attributes', PANEL_THICKNESS_KEY)
          current_back = instance.get_attribute('dynamic_attributes', BACK_THICKNESS_KEY)
          (current_panel.to_f - panel).abs > 0.000001 || (current_back.to_f - back).abs > 0.000001
        end

      end
    end

    if defined?(Connector)
      Connector.register('dc_import_pipeline', Connectors::DCImportPipeline)

      begin
        if MH::RegistryApp.respond_to?(:load_config)
          Connectors::DCImportPipeline.on_config_changed(MH::RegistryApp.load_config)
        end
      rescue => e
        warn "[MH Registry] dc_import_pipeline config sync failed: #{e.message}"
      end
    end
  end
end

# encoding: UTF-8
#
# MH_Registry / connectors / dc_import / dc_attrs.rb
# ---------------------------------------------------------------------------
# Dynamic Component attribute learning/binding/write helpers for DCImportPipeline.
# ---------------------------------------------------------------------------

module MH
  module RegistryApp
    module Connectors
      module DCImportPipeline
        module_function

        def dynamic_attrs_for_selection
          model = Sketchup.active_model
          inst = model.selection.to_a.find { |e| e.is_a?(Sketchup::ComponentInstance) }
          return { 'ok' => false, 'error' => 'Chọn 1 Component/DC trước.' } unless inst

          attrs = []
          collect_bindable_dc_attrs(inst, attrs, 'root', inst.definition.name.to_s)
          if inst.respond_to?(:definition) && inst.definition
            collect_bindable_dc_attrs(inst.definition, attrs, 'definition', "#{inst.definition.name} definition")
          end
          direct_visible_groups(inst).each do |group|
            label = group.name.to_s.strip
            label = group.definition.name.to_s.strip if label.empty? && group.respond_to?(:definition) && group.definition
            collect_bindable_dc_attrs(group, attrs, 'child', label)
          end

          if attrs.empty?
            message = has_dynamic_attrs_for_learning?(inst) ?
                        'DC này không có custom input root/child học được.' :
                        'Không phải Dynamic Component (thiếu dynamic_attributes).'
            return { 'ok' => false, 'error' => message }
          end

          attrs = unique_dc_attr_rows(attrs)
          attrs.sort_by! { |a| [dc_attr_scope_order(a['scope']), a['key']] }
          { 'ok' => true, 'definition' => inst.definition.name.to_s,
            'suggest_match' => inst.definition.name.to_s, 'attrs' => attrs }
        rescue => e
          { 'ok' => false, 'error' => "#{e.class}: #{e.message}" }
        end

        def has_dynamic_attrs_for_learning?(instance)
          return true if instance && instance.attribute_dictionary('dynamic_attributes', false)
          definition = instance.respond_to?(:definition) ? instance.definition : nil
          return true if definition && definition.attribute_dictionary('dynamic_attributes', false)

          direct_visible_groups(instance).any? { |group| group.attribute_dictionary('dynamic_attributes', false) }
        rescue
          false
        end

        def collect_bindable_dc_attrs(entity, attrs, scope, label = '')
          dict = entity.attribute_dictionary('dynamic_attributes', false)
          return unless dict

          dict.each_pair do |k, v|
            key = k.to_s
            next if key.start_with?('_')

            attr_formula = entity.get_attribute('dynamic_attributes', "_#{key}_formula").to_s.strip
            attr_label = clean_dc_meta_text(entity.get_attribute('dynamic_attributes', "_#{key}_label"))
            attr_formlabel = clean_dc_meta_text(entity.get_attribute('dynamic_attributes', "_#{key}_formlabel"))
            attr_units = clean_dc_meta_text(entity.get_attribute('dynamic_attributes', "_#{key}_units"))
            attr_formula_units = clean_dc_meta_text(entity.get_attribute('dynamic_attributes', "_#{key}_formulaunits"))
            attr_access = clean_dc_meta_text(entity.get_attribute('dynamic_attributes', "_#{key}_access"))
            next unless learnable_dc_attr?(key, attr_label, attr_formlabel, attr_units, attr_access, attr_formula)

            number = dc_attr_numeric_value(v)
            number = dc_attr_numeric_value(attr_formula) if number.nil?

            unit_guess = dc_attr_unit_guess(attr_units, attr_formula_units, number)
            bindable = !number.nil? && dc_attr_bindable_access?(attr_access) && unit_guess != 'string'
            attrs << {
              'key' => key,
              'spec' => "#{scope}:#{key}",
              'scope' => scope.to_s,
              # Trung voi Component Options: uu tien _formlabel (text user thay
              # trong dialog), fallback _label, cuoi cung ten entity scope.
              'label' => [attr_formlabel, attr_label, label.to_s].find { |s| !s.to_s.strip.empty? }.to_s.strip,
              'value' => dc_attr_display_value(v, attr_formula),
              'mm_if_length' => number.nil? ? '' : dc_attr_mm_preview(number, unit_guess),
              'unit_guess' => unit_guess,
              'units' => attr_units,
              'formula_units' => attr_formula_units,
              'access' => attr_access,
              'formula' => attr_formula,
              'bindable' => bindable
            }
          end
        rescue
          nil
        end

        def dc_attr_display_value(value, formula = '')
          text = value.to_s.strip
          return text unless text.empty?

          formula.to_s.strip
        rescue
          value
        end

        def clean_dc_meta_text(value)
          value.to_s.gsub(/&nbsp;|\u00a0/i, ' ').gsub(/<[^>]*>/, '').strip
        rescue
          ''
        end

        def dc_attr_scope_order(scope)
          case scope.to_s
          when 'root'
            0
          when 'definition'
            1
          when 'child'
            2
          else
            9
          end
        end

        def unique_dc_attr_rows(attrs)
          seen = {}
          attrs.filter_map do |row|
            key = "#{row['scope']}|#{row['key']}".downcase
            next nil if seen[key]

            seen[key] = true
            row
          end
        rescue
          attrs
        end

        def learnable_dc_attr?(key, label, formlabel, units, access, formula)
          text_key = key.to_s.strip
          return false if text_key.empty?
          return false if dc_system_attr_key?(text_key)

          # Bang Custom cua DC Options chi hien attr co _formlabel HOAC _access
          # khac NONE. Loai bo nhanh "ten doc duoc" cu vi no keo ca bien trung
          # gian (vd b2chieucaochan, _access=NONE) khong xuat hien trong Options.
          return true if !formlabel.to_s.strip.empty?
          return true if !access.to_s.strip.empty? && access.to_s.strip.upcase != 'NONE'
          false
        rescue
          false
        end

        def dc_attr_bindable_access?(access)
          %w[TEXTBOX LIST].include?(access.to_s.strip.upcase)
        rescue
          false
        end

        def dc_system_attr_key?(key)
          %w[
            name material hidden copies dialogwidth dialogheight lenx leny lenz
            x y z rotx roty rotz scalex scaley scalez scaletool
          ].include?(key.to_s.strip.downcase)
        end

        def dc_attr_numeric_value(value)
          return value.to_f if value.is_a?(Numeric)

          text = value.to_s.strip.tr(',', '.')
          text = text.sub(/\A#=\s*/, '').strip
          match = text.match(/\A(-?\d+(?:\.\d+)?)(?:\s*(mm|cm|m|inch|in))?\z/i)
          return nil unless match

          number = match[1].to_f
          unit = match[2].to_s.downcase
          case unit
          when 'cm'
            number * 10.0
          when 'm'
            number * 1000.0
          when 'inch', 'in'
            number * 25.4
          else
            number
          end
        rescue
          nil
        end

        def dc_attr_unit_guess(units, formula_units = nil, number = nil)
          text = units.to_s.strip.downcase
          formula_text = formula_units.to_s.strip.downcase
          return 'string' if text == 'string' || formula_text == 'string'
          return 'length' if text =~ /millimeter|centimeter|meter|inch|length|mm|cm|\bin\b/
          return 'length' if formula_text =~ /millimeter|centimeter|meter|inch|length|mm|cm|\bin\b/
          return 'mm' if text =~ /float|integer|number/ || formula_text =~ /float|integer|number/

          number.to_f.abs < 5.0 ? 'length' : 'mm'
        end

        def dc_attr_mm_preview(number, unit_guess)
          value = unit_guess.to_s == 'length' ? number.to_f * 25.4 : number.to_f
          value.round(2)
        rescue
          ''
        end

        # ---- dc_thickness_bindings: áp độ dày vào tham số từng file DC ----
        def parse_bindings(data)
          rows = (data && (data['dc_thickness_bindings'] || data[:dc_thickness_bindings])) || []
          rows.filter_map do |row|
            match = value_for(row, 'match').to_s.strip
            panel = value_for(row, 'param_panel').to_s.strip
            back  = value_for(row, 'param_back').to_s.strip
            extra = value_for(row, 'param_extra').to_s.strip
            modul_only = value_for(row, 'modul_only', 'module_only', 'modulOnly', 'moduleOnly').to_s.strip
            product_only = value_for(row, 'product_only', 'productOnly', 'sp_only').to_s.strip
            unit  = value_for(row, 'unit').to_s.strip.downcase
            enabled = value_for(row, 'enabled').to_s.strip
            next if match.empty? || (panel.empty? && back.empty? && extra.empty?)
            next if %w[0 false no].include?(enabled.downcase)
            { 'match' => match, 'param_panel' => panel, 'param_back' => back,
              'param_extra' => extra, 'modul_only' => modul_only, 'product_only' => product_only,
              'unit' => (unit.empty? ? 'length' : unit) }
          end
        end

        def binding_for(context, instance = nil)
          return nil unless context
          list = @bindings || []
          return nil if list.empty?
          path = (context[:import_path] || context['import_path']).to_s.tr('\\', '/').downcase
          group = (context[:superimp_group] || context['superimp_group']).to_s.strip.downcase
          import_name = context_value(context, :import_name, 'import_name').to_s.strip
          def_name = instance && instance.respond_to?(:definition) && instance.definition ? instance.definition.name.to_s : ''
          # Khop CHINH XAC theo ten (da bo `#NN`). KHONG dung chuoi-con:
          # "Nẹp Bù Phải" (DC khac, key d1) KHONG duoc nuot "Nẹp Bù Phải 50"
          # (key dodaytam), va "Tấm Đứng" KHONG nuot "Tấm Đứng Trước".
          # Uu tien nguon nhan dang: def_name (ten THAT cua DC) > path >
          # import_name (nhan trong list, co the la tien to chung nhieu bien the).
          # Trong cung mot nguon, neu nhieu row trung thi lay match dai nhat.
          [def_name, path, import_name].each do |text|
            nt = normalize_binding_match_text(text)
            next if nt.empty?
            hits = list.select do |b|
              m = b['match'].to_s.strip
              next false if m.empty? || m.downcase.start_with?('group:')
              normalize_binding_match_text(m) == nt
            end
            best = hits.max_by { |b| normalize_binding_match_text(b['match']).length }
            return best if best
          end
          unless group.empty?
            hit = list.find { |b| b['match'].to_s.strip.downcase == "group:#{group}" }
            return hit if hit
          end
          nil
        end

        def normalize_binding_match_text(value)
          value.to_s.tr('\\', '/').downcase.sub(/#\d+\b/, '').strip
        end

        def set_dc_attr_unit(instance, key, mm_value, unit)
          return if key.to_s.strip.empty? || mm_value.nil?
          value = dc_attr_target_value(instance, key, mm_value, unit)
          write_dc_attr_value(instance, key, value, formula: dc_attr_formula_value(instance, key, mm_value, value))
        end

        def dc_attr_changed?(instance, key, mm_value, unit)
          return false if key.to_s.strip.empty? || mm_value.nil?
          target = dc_attr_target_value(instance, key, mm_value, unit)
          cur = instance.get_attribute('dynamic_attributes', key)
          (cur.to_f - target).abs > 0.000001
        end

        def dc_attr_target_value(instance, key, mm_value, unit, inferred_current = nil)
          requested = unit.to_s.strip.downcase
          current = instance.get_attribute('dynamic_attributes', key) rescue nil
          current = inferred_current if current.nil? && !inferred_current.nil?
          if requested == 'mm'
            # Nhiều DC lưu độ dày dạng length inch dù người dùng chọn mm.
            # Nếu giá trị hiện tại rất nhỏ, kể cả string "0.6929...", coi key
            # này là length để tránh ghi 18.6 inch (= 47.244cm).
            current_number = dc_plain_numeric_value(current)
            return mm_value.to_f.mm.to_f if dc_attr_length_storage?(instance, key)
            return mm_value.to_f.mm.to_f if current_number && current_number.abs < 5.0 && mm_value.to_f.abs > 5.0
            return mm_value.to_f
          end
          mm_value.to_f.mm.to_f
        end

        # Tra metadata `_<key>_<suffix>` cua DC. Khi ghi vao ROOT (auto-route) thi
        # root instance THUONG khong co metadata don vi - no nam o definition/child.
        # -> fallback: entity -> definition -> visible children.
        def dc_attr_meta_lookup(entity, key, suffix)
          val = entity.get_attribute('dynamic_attributes', "_#{key}_#{suffix}")
          return val unless val.to_s.strip.empty?

          definition = entity.respond_to?(:definition) ? entity.definition : nil
          if definition
            val = definition.get_attribute('dynamic_attributes', "_#{key}_#{suffix}")
            return val unless val.to_s.strip.empty?
            definition.entities.each do |child|
              next unless child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)
              cv = child.get_attribute('dynamic_attributes', "_#{key}_#{suffix}")
              return cv unless cv.to_s.strip.empty?
            end
          end
          val
        rescue
          nil
        end

        def dc_attr_length_storage?(entity, key)
          units = clean_dc_meta_text(dc_attr_meta_lookup(entity, key, 'units')).downcase
          formula_units = clean_dc_meta_text(dc_attr_meta_lookup(entity, key, 'formulaunits')).downcase
          text = "#{units} #{formula_units}"
          text =~ /millimeter|centimeter|meter|inch|length|\bmm\b|\bcm\b|\bin\b/
        rescue
          false
        end

        def dc_plain_numeric_value(value)
          return value.to_f if value.is_a?(Numeric)

          text = value.to_s.strip.tr(',', '.')
          text =~ /\A-?\d+(?:\.\d+)?\z/ ? text.to_f : nil
        rescue
          nil
        end

        def attr_spec_key(spec)
          text = spec.to_s.strip
          return '' if text.empty?
          text.include?(':') ? text.split(':', 2)[1].to_s.strip : text
        end

        def attr_spec_scope(spec)
          text = spec.to_s.strip
          text.include?(':') ? text.split(':', 2)[0].to_s.strip.downcase : 'root'
        end

        def split_attr_specs(value)
          value.to_s.split(/[\n,;|]+/).map(&:strip).reject(&:empty?)
        end

        def attr_targets_for_spec(instance, spec, role = nil, allow_create = true)
          key = attr_spec_key(spec)
          return [] if key.empty?

          scope = attr_spec_scope(spec)
          groups = visible_groups(instance)
          groups = groups.select { |group| back_group?(group) } if role.to_s == 'back'
          groups = groups.reject { |group| back_group?(group) } if role.to_s == 'panel'

          # AUTO-ROUTE -> ROOT: neu co group con doc gia tri qua `parent!<key>` thi
          # gia tri PHAI nam o ROOT instance (noi parent! tro toi). Ghi vao
          # definition/child se bi redraw tinh lai tu parent! => vo hieu. Vi vay
          # bat ke binding khai scope nao (definition:/child:/root:), van ep ve root.
          # -> moi binding `definition:` cu cua user tu chay dung, khoi sua tung dong.
          # Kiem tra tren TAT CA visible_groups (KHONG loc role): gia tri luon ve
          # root bat ke panel/back, vi `parent!<key>` co the nam o group khac role
          # (vd key duoc nhom panel tham chieu nhung binding khai la back).
          return [instance] if visible_groups(instance).any? { |group| parent_formula_for_key?(group, key) }

          case scope
          when 'root'
            # Cho phep ghi/tao attr tren ROOT khi: allow_create, attr da co san o
            # root, HOAC co group con tham chieu `parent!<key>` (chung to hinh hoc
            # phu thuoc bien nay o root nhung root chua co o input -> day chinh la
            # cho can ep dien so vd `ag8wlf51yh`).
            (allow_create ||
             root_dc_attr_known?(instance, key) ||
             groups.any? { |group| parent_formula_for_key?(group, key) }) ? [instance] : []
          when 'definition', 'root_definition'
            definition = instance.respond_to?(:definition) ? instance.definition : nil
            definition && (allow_create || definition.get_attribute('dynamic_attributes', key) != nil || dc_user_input_metadata?(definition, key)) ? [definition] : []
          when 'child', 'children'
            groups.select { |entity| entity.get_attribute('dynamic_attributes', key) != nil }
          else
            unless allow_create
              return legacy_auto_root_target?(instance, key) ? [instance] : []
            end

            hits = [instance].select { |entity| entity.get_attribute('dynamic_attributes', key) != nil }
            hits.concat(groups.select { |entity| entity.get_attribute('dynamic_attributes', key) != nil })
            if allow_create && hits.none? { |entity| entity.equal?(instance) } && groups.any? { |entity| parent_formula_for_key?(entity, key) }
              hits.unshift(instance)
            end
            hits.empty? && allow_create ? [instance] : hits
          end
        rescue
          allow_create ? [instance] : []
        end

        def root_dc_attr_known?(instance, key)
          return false unless instance && key.to_s.strip != ''
          return false if generated_dc_internal_key?(key)

          return true if instance.get_attribute('dynamic_attributes', key) != nil
          return true if dc_user_input_metadata?(instance, key)

          definition = instance.respond_to?(:definition) ? instance.definition : nil
          return false unless definition
          return true if definition.get_attribute('dynamic_attributes', key) != nil
          dc_user_input_metadata?(definition, key)
        rescue
          false
        end

        def legacy_auto_root_target?(instance, key)
          return false unless instance && instance.get_attribute('dynamic_attributes', key) != nil

          # `auto:key` từ bản cũ không được mò xuống child nữa. Với key nội bộ
          # dạng random, chỉ cho ghi nếu thật sự có metadata input của DC.
          return true unless generated_dc_internal_key?(key)
          dc_user_input_metadata?(instance, key)
        rescue
          false
        end

        def generated_dc_internal_key?(key)
          text = key.to_s.strip
          text =~ /\A[a-z0-9_]{8,}\z/
        end

        def dc_user_input_metadata?(entity, key)
          !clean_dc_meta_text(entity.get_attribute('dynamic_attributes', "_#{key}_label")).empty? ||
            !clean_dc_meta_text(entity.get_attribute('dynamic_attributes', "_#{key}_formlabel")).empty?
        rescue
          false
        end

        def parent_formula_for_key?(entity, key)
          da = entity.attribute_dictionary('dynamic_attributes')
          return false unless da
          # Check ALL _*_formula attrs, not just _key_formula. Some DCs expose
          # the key via another dimension's formula (e.g. _lenx_formula: "parent!DoDayTam").
          pattern = /\bparent!#{Regexp.escape(key)}\b/i
          da.each { |k, v| return true if k.to_s.end_with?('_formula') && v.to_s =~ pattern }
          false
        rescue
          false
        end

        def inferred_current_for_target(root, target, key, role = nil)
          current = target.get_attribute('dynamic_attributes', key) rescue nil
          return current unless current.nil?
          return nil unless target.equal?(root)

          groups = visible_groups(root)
          groups = groups.select { |group| back_group?(group) } if role.to_s == 'back'
          groups = groups.reject { |group| back_group?(group) } if role.to_s == 'panel'
          child = groups.find { |group| parent_formula_for_key?(group, key) && !group.get_attribute('dynamic_attributes', key).nil? }
          child ? child.get_attribute('dynamic_attributes', key) : nil
        rescue
          nil
        end

        def dc_attr_changed_for_spec(instance, spec, mm_value, unit, role = nil, allow_create = true)
          key = attr_spec_key(spec)
          return false if key.empty?

          attr_targets_for_spec(instance, spec, role, allow_create).any? do |target|
            current = inferred_current_for_target(instance, target, key, role)
            target_value = dc_attr_target_value(target, key, mm_value, unit, current)
            cur = target.get_attribute('dynamic_attributes', key)
            cur.nil? ||
              (cur.to_f - target_value.to_f).abs > 0.000001 ||
              dc_attr_formula_changed?(target, key, mm_value, target_value) ||
              dc_dependent_attr_changed?(target, key, target_value)
          end
        end

        def set_dc_attr_spec(instance, spec, mm_value, unit, role = nil, allow_create = true)
          key = attr_spec_key(spec)
          return 0 if key.empty?

          count = 0
          attr_targets_for_spec(instance, spec, role, allow_create).each do |target|
            # Đường Component Options: dc.set_attribute_formula tự ghi cả value,
            # _formula, _error, lan toa formula xuong children qua redraw — tranh
            # bug "redraw revert" khi raw set_attribute khong sync formula def.
            next count += 1 if write_dc_thickness_via_options(target, key, mm_value, unit)

            current = inferred_current_for_target(instance, target, key, role)
            value = dc_attr_target_value(target, key, mm_value, unit, current)
            write_dc_attr_value(target, key, value, formula: dc_attr_formula_value(target, key, mm_value, value))
            count += 1
          end
          count
        end

        # Routes thickness write qua $dc_observers (chinh path Component Options
        # dung). Tra ve true neu da ghi qua DC API, false neu phai fallback raw.
        def write_dc_thickness_via_options(target, key, mm_value, unit)
          return false unless target && key.to_s.strip != ''
          return false if unit.to_s == 'none'
          # PHONG THU: DC API set_attribute_formula chi nhan ComponentInstance.
          # Goi tren ComponentDefinition se crash (no goi .definition noi bo).
          # Tra false -> fallback raw set_attribute (chay duoc tren ca definition).
          # Auto-route trong attr_targets_for_spec da dam bao key parent! ve root
          # instance; guard nay chan moi truong hop con sot (vd binding definition:
          # khong qua parent!) khoi crash.
          return false unless target.is_a?(Sketchup::ComponentInstance)
          return false unless defined?($dc_observers) && $dc_observers
          dc = $dc_observers.get_latest_class rescue nil
          return false unless dc && dc.respond_to?(:set_attribute_formula)

          formula = dc_options_formula_token(target, key, mm_value, unit)
          return false unless formula

          dc.set_attribute_formula(target, key, formula)
          true
        rescue => e
          MH::RegistryApp.dbg("[DCImportPipeline] set_attribute_formula fallback (#{key}): #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          false
        end

        # Tinh chuoi formula theo formulaunits cua attribute (mm/cm/m/in).
        # `unit` o binding row CHI co y nghia cho fallback path (mm vs length);
        # con day o DC API path, formula luon viet theo formulaunits cua chinh
        # attr de DC eval ra dung. Tra nil khi attr khong phai LENGTH (vd FLOAT,
        # STRING) de caller fallback raw write.
        def dc_options_formula_token(target, key, mm_value, _unit)
          mm = mm_value.to_f
          case dc_attr_formula_unit(target, key)
          when 'centimeters' then format_mm_token(mm / 10.0)
          when 'millimeters' then format_mm_token(mm)
          when 'meters'      then format('%.6f', mm / 1000.0).sub(/0+\z/, '').sub(/\.\z/, '')
          when 'inches'      then format('%.6f', mm / 25.4).sub(/0+\z/, '').sub(/\.\z/, '')
          else nil
          end
        rescue
          nil
        end

        def extra_attr_pairs(value)
          split_attr_specs(value).filter_map do |item|
            spec, raw = item.split('=', 2).map { |part| part.to_s.strip }
            next if spec.empty? || raw.nil?
            [spec, raw]
          end
        end

        def extra_attr_value(raw, profile, unit)
          token = raw.to_s.strip
          case token.downcase
          when 'panel', 'panel_mm', 'param_panel'
            unit == 'mm' ? profile['panel_thickness_mm'].to_f : profile['panel_thickness_mm'].to_f.mm.to_f
          when 'back', 'hau', 'hậu', 'back_mm', 'param_back'
            unit == 'mm' ? profile['back_thickness_mm'].to_f : profile['back_thickness_mm'].to_f.mm.to_f
          else
            numeric = token.tr(',', '.')
            numeric =~ /\A-?\d+(?:\.\d+)?\z/ ? numeric.to_f : token
          end
        end

        def dc_attr_raw_changed?(target, key, value)
          current = target.get_attribute('dynamic_attributes', key)
          if current.is_a?(Numeric) && value.is_a?(Numeric)
            (current.to_f - value.to_f).abs > 0.000001
          else
            current.to_s != value.to_s
          end
        end

        def set_dc_attr_raw_spec(instance, spec, value, role = nil, allow_create = true)
          key = attr_spec_key(spec)
          return 0 if key.empty?

          count = 0
          attr_targets_for_spec(instance, spec, role, allow_create).each do |target|
            write_dc_attr_value(target, key, value, formula: value.is_a?(Numeric) ? nil : dc_formula_value(value))
            count += 1
          end
          count
        end

        def write_dc_attr_value(entity, key, value, formula: nil)
          return unless entity && key.to_s.strip != ''

          entity.set_attribute('dynamic_attributes', key, value)
          entity.set_attribute('dynamic_attributes', "_#{key}_error", dc_attr_error_value(value, formula))
          if formula
            entity.set_attribute('dynamic_attributes', "_#{key}_formula", formula)
          elsif value.is_a?(Numeric)
            delete_dc_attr_formula(entity, key)
          end
          sync_dc_dependent_attrs(entity, key, value)
        end

        def dc_attr_formula_value(entity, key, mm_value, stored_value)
          mm = mm_value.to_f
          stored = stored_value.to_f
          if dc_attr_length_storage?(entity, key)
            return dc_attr_formula_for_length_mm(entity, key, mm)
          end

          return nil if (stored - mm).abs < 0.000001

          "#{format_mm_token(mm)}mm"
        end

        def dc_attr_formula_for_length_mm(entity, key, mm)
          unit = dc_attr_formula_unit(entity, key)
          case unit
          when 'centimeters'
            format_mm_token(mm.to_f / 10.0)
          when 'millimeters'
            format_mm_token(mm)
          when 'meters'
            format('%.6f', mm.to_f / 1000.0).sub(/0+\z/, '').sub(/\.\z/, '')
          when 'inches'
            format('%.6f', mm.to_f / 25.4).sub(/0+\z/, '').sub(/\.\z/, '')
          else
            "#{format_mm_token(mm)}mm"
          end
        rescue
          "#{format_mm_token(mm)}mm"
        end

        def dc_attr_formula_unit(entity, key)
          formula_units = clean_dc_meta_text(dc_attr_meta_lookup(entity, key, 'formulaunits')).downcase
          units = clean_dc_meta_text(dc_attr_meta_lookup(entity, key, 'units')).downcase
          text = formula_units.empty? ? units : formula_units
          return 'centimeters' if text.include?('centimeter') || text == 'cm'
          return 'millimeters' if text.include?('millimeter') || text == 'mm'
          return 'meters' if text == 'meters' || text == 'meter' || text == 'm'
          return 'inches' if text.include?('inch') || text == 'in'
          ''
        rescue
          ''
        end

        def dc_attr_error_value(value, formula = nil)
          text = formula.to_s.strip
          return text unless text.empty?

          value.to_s
        rescue
          value.to_s
        end

        def dc_attr_formula_changed?(entity, key, mm_value, stored_value)
          current = entity.get_attribute('dynamic_attributes', "_#{key}_formula")
          target = dc_attr_formula_value(entity, key, mm_value, stored_value)
          return current.to_s.strip != target.to_s if target

          current.to_s.strip =~ /\A-?\d+(?:\.\d+)?\z/
        rescue
          false
        end

        def dc_formula_value(value)
          "\"#{value.to_s.gsub('\\', '\\\\\\').gsub('"', '\"')}\""
        end

        def delete_dc_attr_formula(entity, key)
          dict = entity.attribute_dictionary('dynamic_attributes', false)
          return unless dict

          dict.delete_key("_#{key}_formula") if dict.respond_to?(:delete_key)
        rescue
          nil
        end

        def dc_dependent_attr_changed?(entity, key, value)
          dict = entity.attribute_dictionary('dynamic_attributes', false)
          return false unless dict

          dependency_formula_match?(dict, key).any? do |attr_key|
            current = entity.get_attribute('dynamic_attributes', attr_key)
            current.nil? || (current.to_f - value.to_f).abs > 0.000001
          end
        rescue
          false
        end

        def sync_dc_dependent_attrs(entity, key, value)
          dict = entity.attribute_dictionary('dynamic_attributes', false)
          return unless dict

          dependency_formula_match?(dict, key).each do |attr_key|
            entity.set_attribute('dynamic_attributes', attr_key, value)
            entity.set_attribute('dynamic_attributes', "_#{attr_key}_error", value.to_s)
          end
        rescue
          nil
        end

        def dependency_formula_match?(dict, source_key)
          source = source_key.to_s.strip.downcase
          return [] if source.empty?

          hits = []
          dict.each_pair do |key, formula|
            text = key.to_s
            next unless text.start_with?('_') && text.end_with?('_formula')
            attr_key = text.sub(/\A_/, '').sub(/_formula\z/, '')
            next if attr_key.empty? || attr_key.downcase == source
            normalized = formula.to_s.strip.downcase
            hits << attr_key if normalized == source
          end
          hits
        rescue
          []
        end

        # ---- Thickness options làm "profile" (panel/hậu mm thực tế) ----

        def inferred_thickness_attr_specs(instance, role = nil, profile = nil)
          visible_groups(instance).filter_map do |group|
            next if thickness_inference_ignored_group?(group)

            inferred_role = inferred_role_for_thickness_spec(group, instance, profile)
            next if role.to_s == 'back' && inferred_role != 'back'
            next if role.to_s == 'panel' && inferred_role == 'back'

            key = inferred_group_thickness_key(group, instance)
            key.empty? ? nil : "child:#{key}"
          end.uniq
        rescue
          []
        end

        def thickness_inference_ignored_group?(group)
          text = [
            group.name,
            (group.definition.name rescue nil),
            group.get_attribute('dynamic_attributes', 'name'),
            group.get_attribute('dynamic_attributes', '_name')
          ].compact.join(' ')
          folded = if defined?(MH::Text) && MH::Text.respond_to?(:fold)
                     MH::Text.fold(text)
                   else
                     text.downcase
                   end
          folded.include?('danh dau ray') ||
            folded.include?('ray phai') ||
            folded.include?('ray trai') ||
            folded.include?('minifix') ||
            folded.include?('abf_')
        rescue
          false
        end

        def inferred_role_for_thickness_spec(group, instance = nil, profile = nil)
          if profile && respond_to?(:resolve_thickness_for_group)
            info = resolve_thickness_for_group(group, profile, nil, instance) rescue nil
            role = info && info['role'].to_s
            return role unless role.empty?
          end

          back_group?(group) ? 'back' : 'panel'
        rescue
          back_group?(group) ? 'back' : 'panel'
        end

        def inferred_group_thickness_key(group, instance = nil)
          dims = {
            'lenx' => group.get_attribute('dynamic_attributes', 'lenx'),
            'leny' => group.get_attribute('dynamic_attributes', 'leny'),
            'lenz' => group.get_attribute('dynamic_attributes', 'lenz')
          }.select { |_key, value| value.to_f > 0 }
          axis = dims.min_by { |_key, value| value.to_f }&.first
          return '' unless axis

          axis_formula = group.get_attribute('dynamic_attributes', "_#{axis}_formula").to_s.strip
          key = thickness_key_from_formula(group, axis_formula, instance)
          return key unless key.empty?

          key = %w[lenx leny lenz].map do |dim|
            thickness_key_from_formula(group, group.get_attribute('dynamic_attributes', "_#{dim}_formula").to_s, instance)
          end.find { |candidate| !candidate.to_s.empty? }.to_s
          return '' if key.empty?
          return key if group.get_attribute('dynamic_attributes', key) != nil
          return key if parent_formula_for_key?(group, key)
          ''
        rescue
          ''
        end

        def thickness_key_from_formula(group, formula, instance = nil)
          dc_formula_attr_keys(formula).find do |candidate|
            key = candidate.to_s
            next false if key.empty? || %w[lenx leny lenz].include?(key.downcase)

            thickness_attr_key?(group, key, instance)
          end.to_s
        rescue
          ''
        end

        def thickness_attr_key?(entity, key, instance = nil)
          text = [
            (instance ? dc_attr_meta_lookup(instance, key, 'formlabel') : nil),
            (instance ? dc_attr_meta_lookup(instance, key, 'label') : nil),
            dc_attr_meta_lookup(entity, key, 'formlabel'),
            dc_attr_meta_lookup(entity, key, 'label')
          ].compact.join(' ')
          clean = clean_dc_meta_text(text)
          folded = if defined?(MH::Text) && MH::Text.respond_to?(:fold)
                     MH::Text.fold(clean)
                   else
                     clean.downcase
                   end
          folded.include?('do day') ||
            folded.include?('thickness') ||
            folded.include?('bottom thickness')
        rescue
          false
        end

        def set_dc_attr(instance, key, mm_value)
          value = mm_value.to_f.mm.to_f
          write_dc_attr_value(instance, key, value, formula: dc_attr_formula_value(instance, key, mm_value, value))
        end

        def redraw_dc(instance)
          return unless instance && instance.valid?
          return unless defined?($dc_observers)

          dc = $dc_observers.get_latest_class
          return unless dc && dc.respond_to?(:redraw_with_undo)

          # CHI redraw INSTANCE (DC engine tu de quy xuong children). KHONG redraw
          # tung group rieng le: redraw 1 group (vd "Hau") doc lap se tinh lai tu
          # trang thai cu va LAT NGUOC gia tri parent! vua set tu root (vd back ve
          # 11 thay vi 12). 1 lan redraw instance la du cho ca panel lan back.
          dc.redraw_with_undo(instance)
        end

      end
    end
  end
end

# encoding: utf-8
# MH_Thongke P3-FULL TRIAL — scanner chạy trên MH::ModelHub.each_record (streaming).
# CHỈ DÙNG ĐỂ ĐO/ĐỐI CHIẾU. KHÔNG sửa model_scanner.rb active.
# Lưu/khôi phục ivar của MH_Thongke để không phá session sống.

module MH_Thongke
  module P3Trial
    TrialResult = Struct.new(:data_map, :mat_data_map, :prod_groups,
                             :all_item_names, :all_item_names_set, :led_per_product,
                             keyword_init: true)

    CTX_IVARS = %i[@data_map @mat_data_map @all_item_names @all_item_names_set
                   @led_per_product @prod_groups @stat_entity_ids @entity_ids_in_data
                   @hidden_list @unit_overrides @group_by].freeze

    module_function

    def skip_material?(m); MH_Thongke.skip_material?(m); end
    def material_code_thickness(c); MH_Thongke.material_code_thickness(c); end

    # ---- Streaming scan: tái lập semantics của ModelScanner.scan worker ----
    def scan_stream(model:, selection:, group_by:, hidden_list:, unit_overrides:, led_power_factor:, psu_list:)
      data_map = {}
      mat_data_map = {}
      all_item_names = []
      all_item_names_set = Set.new
      led_per_product = {}
      prod_groups = {}
      stat_entity_ids = Hash.new { |h, k| h[k] = Set.new }
      entity_ids_in_data = Hash.new { |h, k| h[k] = Set.new }
      prod_group_entity_ids = Hash.new { |h, k| h[k] = Set.new }
      selection_set = selection.respond_to?(:to_a) ? selection.to_a.to_set : Set.new
      phaochi_map = {}
      material_face_fallback_cache = {}

      ctx = MH_Thongke
      ctx.instance_variable_set(:@data_map, data_map)
      ctx.instance_variable_set(:@mat_data_map, mat_data_map)
      ctx.instance_variable_set(:@all_item_names, all_item_names)
      ctx.instance_variable_set(:@all_item_names_set, all_item_names_set)
      ctx.instance_variable_set(:@led_per_product, led_per_product)
      ctx.instance_variable_set(:@prod_groups, prod_groups)
      ctx.instance_variable_set(:@stat_entity_ids, stat_entity_ids)
      ctx.instance_variable_set(:@entity_ids_in_data, entity_ids_in_data)
      ctx.instance_variable_set(:@hidden_list, hidden_list)
      ctx.instance_variable_set(:@unit_overrides, unit_overrides)
      ctx.instance_variable_set(:@group_by, group_by)

      # state[rec.key] = [current_prod, current_top, is_selected]
      state = {}

      MH::ModelHub.each_record(
        root: model.active_entities,
        types: %i[group component],
        depth: -1,
        include_hidden: true,            # scanner KHÔNG lọc hidden → phải true để khớp node-set
        reject_names: ['__ABF_Nesting']
      ) do |rec|
        e = rec.entity
        next unless e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)

        parent_wt = rec.transform
        pstate = state[rec.parent_key]
        parent_prod     = pstate ? pstate[0] : "--"
        top_level       = pstate ? pstate[1] : nil
        parent_selected = pstate ? pstate[2] : false

        e_name = e.name.to_s.strip
        parent_has_product = MH_Thongke.product_code_valid?(parent_prod) rescue !!(parent_prod =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?/)
        current_prod = parent_prod
        unless e_name.empty?
          product_hit = MH_Thongke.product_codes_from_text(e_name).first rescue e_name[/([A-Z]+\d+[A-Z]?(?:\.\d+)?)/i, 1]
          if product_hit
            product_hit = MH_Thongke.product_code_exact(product_hit) rescue product_hit.to_s.upcase
            if !parent_has_product || (MH_Thongke.product_code_base(product_hit) rescue product_hit) == (MH_Thongke.product_code_base(parent_prod) rescue parent_prod) || parent_prod == "--"
              current_prod = product_hit
            end
            product_key = product_hit
            prod_groups[product_key] ||= []
            product_entity_id = e.entityID rescue e.object_id
            unless prod_group_entity_ids[product_key].include?(product_entity_id)
              prod_groups[product_key] << e
              prod_group_entity_ids[product_key] << product_entity_id
            end
          elsif !parent_has_product
            current_prod = e_name
          end
        end

        prod_code = current_prod
        current_top = top_level || e
        is_selected = parent_selected || selection_set.include?(e)

        # Lưu state cho con (thay cho việc truyền đối số trong đệ quy)
        state[rec.key] = [current_prod, current_top, is_selected]

        name = nil
        dict = "ABF"
        key = "statistical-name"
        type = :count

        e_display_name = e.get_attribute("ABF", "statistical-name") || e.get_attribute("ABF", "setting-name") || e_name
        is_phaochi = begin
          if ctx.respond_to?(:phaochi_name?)
            from_def = (e.respond_to?(:definition) && e.definition) ? e.definition.name.to_s : ""
            ctx.phaochi_name?(e_display_name) || ctx.phaochi_name?(e_name) || (!from_def.empty? && ctx.phaochi_name?(from_def))
          else
            e_display_name.to_s =~ /ph[àa]o ch[ỉi]/i
          end
        rescue
          e_display_name.to_s =~ /ph[àa]o ch[ỉi]/i
        end

        generated_pk = e.get_attribute("MH_Thongke", "generated_pk").to_s == "true"
        is_phaochi = false if generated_pk
        if generated_pk
          name = e.get_attribute("MH_Thongke", "pk_name") ||
                 e.get_attribute("ABF", "statistical-name") ||
                 e.get_attribute("ABF", "setting-name") ||
                 e_name.to_s.sub(/\APK\s+\w+\s*-\s*/i, "")
          name = ctx.ensure_pk_marker_attributes(e, name)
          dict = "MH_Thongke"
          key = "pk_name"
          type = :count
        end

        special_name = e_display_name.to_s.empty? && e.respond_to?(:definition) ? e.definition.name : e_display_name
        special_kind = generated_pk ? nil : ctx.special_hardware_kind(special_name)
        if special_kind
          ctx.add_special_hardware_row(special_kind, e, parent_wt, prod_code, current_top, is_selected, special_name)
          next
        end

        if is_phaochi
          info = ctx.get_phaochi_info(e, parent_wt)
          w_r = info[:w_mm].round(0).to_i
          h_r = info[:h_mm].round(0).to_i
          stat_name = "Phào chỉ #{w_r}x#{h_r}"
          phaochi_prod = (MH_Thongke.product_code_valid?(prod_code) rescue prod_code.to_s =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?/i) ? (MH_Thongke.product_code_exact(prod_code) rescue prod_code.to_s.upcase) : "--"
          display_prod = group_by == "NAME" ? "--" : phaochi_prod
          pc_key = group_by == "NAME" ? stat_name : "#{stat_name}_#{phaochi_prod}"

          phaochi_map[pc_key] ||= {
            name: stat_name, product: display_prod, actual_product: phaochi_prod,
            ten_sp: e.get_attribute("MH_Thongke", "ten_sp") || "",
            ghi_chu: e.get_attribute("MH_Thongke", "ghi_chu") || "",
            ngay_dat: ctx.normalize_order_date(e.get_attribute("MH_Thongke", "ngay_dat")),
            last_modified: e.get_attribute("MH_Thongke", "last_modified") || "",
            layer: e.layer.name, len_total_mm: 0.0, sel_len_mm: 0.0,
            count: 0, sel_count: 0, unit: "md",
            type: :phaochi, dict: "ABF", key: "statistical-name",
            entities: [], stat_entities: [], length_items: [],
            trang_thai: "", new_name: "", is_missing: false
          }

          phaochi_map[pc_key][:len_total_mm] += info[:len_mm]
          phaochi_map[pc_key][:sel_len_mm] += info[:len_mm] if is_selected
          phaochi_map[pc_key][:count] += 1
          phaochi_map[pc_key][:sel_count] += 1 if is_selected
          top_id = current_top.entityID rescue nil
          e_id = e.entityID rescue nil
          phaochi_map[pc_key][:entities] << current_top unless top_id && entity_ids_in_data[pc_key].include?(top_id)
          entity_ids_in_data[pc_key] << top_id if top_id
          unless e_id && stat_entity_ids[pc_key].include?(e_id)
            phaochi_map[pc_key][:stat_entities] << [e, current_top, parent_wt]
            stat_entity_ids[pc_key] << e_id if e_id
          end
          phaochi_map[pc_key][:length_items] << { len_mm: info[:len_mm], top: current_top, selected: is_selected }

          if group_by == "NAME"
            ten_sp_value = e.get_attribute("MH_Thongke", "ten_sp").to_s
            phaochi_map[pc_key][:product_list] ||= []
            phaochi_map[pc_key][:ten_sp_list] ||= []
            phaochi_map[pc_key][:product_list] << phaochi_prod unless phaochi_prod.empty? || phaochi_prod == "--" || phaochi_map[pc_key][:product_list].include?(phaochi_prod)
            phaochi_map[pc_key][:ten_sp_list] << ten_sp_value unless ten_sp_value.empty? || phaochi_map[pc_key][:ten_sp_list].include?(ten_sp_value)
          end

          all_item_names << stat_name unless all_item_names_set.include?(stat_name)
          all_item_names_set << stat_name
          next
        end

        if !generated_pk && (e.get_attribute("ABF", "is-minifix-part-a") || e.get_attribute("ABF", "is-minifix-part-b") || e.get_attribute("ABF", "is-hinge-part-b") || e.get_attribute("ABF", "is-side-drill"))
          name = e.get_attribute("ABF", "setting-name")
          key = "setting-name"
        elsif e.get_attribute("ZSU_LED", "ten_hien_thi") || e.get_attribute("ABF", "statistical-type") == "length_measuring"
          name = e.get_attribute("ZSU_LED", "ten_hien_thi") || e.get_attribute("ABF", "statistical-name") || e.get_attribute("ABF", "setting-name")
          dict = e.get_attribute("ZSU_LED", "ten_hien_thi") ? "ZSU_LED" : "ABF"
          key = e.get_attribute("ZSU_LED", "ten_hien_thi") ? "ten_hien_thi" : (e.get_attribute("ABF", "statistical-name") ? "statistical-name" : "setting-name")
          type = :length
        elsif e.get_attribute("ABF", "is-intersect").to_s == "true"
          name = e.get_attribute("ABF", "setting-name")
          dict = "ABF"
          key = "setting-name"
          type = :length
        elsif e.get_attribute("ABF", "is-statistical-object").to_s == "true"
          name = e.get_attribute("ABF", "statistical-name")
        elsif e.get_attribute("ZSU", "ban_le")
          name = e.get_attribute("ABF", "statistical-name") || "Bản lề ZSU"
        elsif e.get_attribute("ABF", "statistical-name")
          name = e.get_attribute("ABF", "statistical-name")
        end

        if name
          row_product = prod_code
          if generated_pk
            marker_product = e.get_attribute("MH_Thongke", "product_code").to_s.strip
            row_product = marker_product unless marker_product.empty?
          end
          name = ctx.accessory_display_name_for_rules(name) if ctx.respond_to?(:accessory_display_name_for_rules)
          all_item_names << name unless all_item_names_set.include?(name)
          all_item_names_set << name
          unless ctx.hidden_item_name?(name)
            layer_name = e.layer.name
            unit_default = "Cái"
            unit_actual = type == :length ? "mm" : unit_default
            unit_actual = ctx.accessory_unit_for_name(name) || unit_actual if ctx.respond_to?(:accessory_unit_for_name)
            data_key = case group_by
                       when "NAME" then name
                       when "PRODUCT" then "#{name}_#{row_product}"
                       else name
                       end
            data_map[data_key] ||= {
              name: name, product: (group_by == "NAME" ? "--" : row_product),
              actual_product: row_product,
              ten_sp: e.get_attribute("MH_Thongke", "ten_sp") || "",
              ghi_chu: e.get_attribute("MH_Thongke", "ghi_chu") || "",
              ngay_dat: ctx.normalize_order_date(e.get_attribute("MH_Thongke", "ngay_dat")),
              last_modified: e.get_attribute("MH_Thongke", "last_modified") || "",
              trang_thai: "", new_name: "",
              layer: layer_name, count: 0, length: 0.0, sel_count: 0, sel_length: 0.0, unit: unit_actual,
              dict: dict, key: key, type: type, entities: [], stat_entities: [],
              length_items: [], is_missing: false
            }
            if group_by == "NAME"
              ten_sp_value = e.get_attribute("MH_Thongke", "ten_sp").to_s
              data_map[data_key][:product_list] ||= []
              data_map[data_key][:ten_sp_list] ||= []
              data_map[data_key][:product_list] << row_product unless row_product.to_s.empty? || data_map[data_key][:product_list].include?(row_product)
              data_map[data_key][:ten_sp_list] << ten_sp_value unless ten_sp_value.empty? || data_map[data_key][:ten_sp_list].include?(ten_sp_value)
            end
            if type == :length
              len = ctx.get_world_length(e, parent_wt)
              data_map[data_key][:length] += len
              data_map[data_key][:sel_length] += len if is_selected
              data_map[data_key][:length_items] << { len_inch: len, top: current_top, selected: is_selected }
              if name.to_s =~ /led/i
                led_per_product[row_product] ||= { length: 0.0, sel_length: 0.0, layer: layer_name, entities: [] }
                led_per_product[row_product][:length] += len
                led_per_product[row_product][:sel_length] += len if is_selected
                led_per_product[row_product][:entities] << current_top unless led_per_product[row_product][:entities].include?(current_top)
              end
            else
              data_map[data_key][:count] += 1
              data_map[data_key][:sel_count] += 1 if is_selected
            end
            top_id = current_top.entityID rescue nil
            e_id = e.entityID rescue nil
            unless top_id && entity_ids_in_data[data_key].include?(top_id)
              data_map[data_key][:entities] << current_top
              entity_ids_in_data[data_key] << top_id if top_id
            end
            unless e_id && stat_entity_ids[data_key].include?(e_id)
              data_map[data_key][:stat_entities] << [e, current_top, parent_wt]
              stat_entity_ids[data_key] << e_id if e_id
            end
          end
        end

        if name.nil?
          mat_name = nil
          if e.material && !e.material.name.empty? && !skip_material?(e.material.display_name)
            mat_name = e.material.display_name
          end
          if mat_name.nil?
            cache_key =
              if e.is_a?(Sketchup::ComponentInstance) && e.respond_to?(:definition) && e.definition
                begin
                  "def:#{e.definition.persistent_id}"
                rescue
                  "def:#{e.definition.object_id}"
                end
              else
                begin
                  "ent:#{e.persistent_id}"
                rescue
                  "ent:#{e.object_id}"
                end
              end
            cached_face_material = material_face_fallback_cache[cache_key]
            if cached_face_material == false
              mat_name = nil
            elsif cached_face_material
              mat_name = cached_face_material
            else
              inner_ents = (e.is_a?(Sketchup::ComponentInstance) ? e.definition.entities : e.entities) rescue nil
              if inner_ents
                face_mats = inner_ents.grep(Sketchup::Face).flat_map { |f|
                  [f.material&.display_name, f.back_material&.display_name]
                }.compact.reject { |m| m.empty? || skip_material?(m) }.uniq
                mat_name = face_mats.first unless face_mats.empty?
              end
              material_face_fallback_cache[cache_key] = mat_name || false
            end
          end

          if mat_name && !mat_name.empty?
            mat_prod = (MH_Thongke.product_code_valid?(prod_code) rescue prod_code.to_s =~ /\A[A-Z]+\d+/i) ? (MH_Thongke.product_code_exact(prod_code) rescue prod_code.to_s.upcase) : "--"
            display_mat_name = mat_name.to_s.strip
            thickness = material_code_thickness(display_mat_name)
            layer_name = e.layer.name.to_s
            m_key = case group_by
                    when "NAME" then display_mat_name
                    when "PRODUCT" then "#{display_mat_name}_#{mat_prod}"
                    else display_mat_name
                    end
            mat_data_map[m_key] ||= {
              name: display_mat_name, thickness: thickness,
              product: (group_by == "NAME" ? "--" : mat_prod), actual_product: mat_prod,
              ten_sp: e.get_attribute("MH_Thongke", "mat_ten_sp") || "",
              ghi_chu: e.get_attribute("MH_Thongke", "mat_ghi_chu") || "",
              ngay_dat: ctx.normalize_order_date(e.get_attribute("MH_Thongke", "mat_ngay_dat")),
              last_modified: "", trang_thai: "", new_name: "", layer: layer_name,
              count: 0, length: 0.0, sel_count: 0, sel_length: 0.0, unit: "Tam",
              dict: "", key: "", type: :count, entities: [], stat_entities: [], is_missing: false,
              layer_tags: []
            }
            mat_data_map[m_key][:count] += 1
            mat_data_map[m_key][:sel_count] += 1 if is_selected
            mat_data_map[m_key][:layer_tags] << layer_name unless mat_data_map[m_key][:layer_tags].include?(layer_name)
            m_top_id = current_top.entityID rescue nil
            m_e_id = e.entityID rescue nil
            unless m_top_id && entity_ids_in_data[m_key].include?(m_top_id)
              mat_data_map[m_key][:entities] << current_top
              entity_ids_in_data[m_key] << m_top_id if m_top_id
            end
            unless m_e_id && stat_entity_ids[m_key].include?(m_e_id)
              mat_data_map[m_key][:stat_entities] << [e, current_top, parent_wt]
              stat_entity_ids[m_key] << m_e_id if m_e_id
            end
          end
        end
      end

      # ---- post-loop (verbatim từ ModelScanner.scan 340-442) ----
      phaochi_map.each do |pc_key, pc_data|
        next if ctx.hidden_item_name?(pc_data[:name])
        dk_ovr = unit_overrides[pc_key]
        data_map[pc_key] = pc_data.merge(unit: dk_ovr || "md")
      end

      led_per_product.each do |prod, info|
        total_led_length = info[:length]
        sel_led_length = info[:sel_length] || 0.0
        display_prod = group_by == "NAME" ? "--" : prod
        alum_name = "Thanh nhôm LED"
        alum_key = group_by == "NAME" ? alum_name : "#{alum_name}_#{prod}"
        if data_map[alum_key]
          data_map[alum_key][:length] += total_led_length
          data_map[alum_key][:sel_length] += sel_led_length
        else
          data_map[alum_key] = {
            name: alum_name, product: display_prod, actual_product: prod,
            layer: info[:layer], count: 0, sel_count: 0, length: total_led_length,
            sel_length: sel_led_length, unit: "md",
            dict: "ZSU_LED", key: "ten_hien_thi", type: :length, entities: info[:entities],
            ngay_dat: "", ghi_chu: "", trang_thai: "", new_name: "", last_modified: "",
            stat_entities: [], length_items: [], is_missing: false
          }
        end
        if group_by == "NAME"
          data_map[alum_key][:product_list] ||= []
          data_map[alum_key][:product_list] << prod unless prod.to_s.empty? || data_map[alum_key][:product_list].include?(prod)
        end

        total_led_length_m = total_led_length.to_f * 0.0254
        sel_led_length_m = sel_led_length.to_f * 0.0254
        req_power = led_power_factor.to_f * total_led_length_m
        sel_req_power = led_power_factor.to_f * sel_led_length_m
        best_combo = ctx.led_psu_combo(req_power, psu_list)
        sel_combo = ctx.led_psu_combo(sel_req_power, psu_list)
        best_combo.each do |watt, qty|
          next if qty <= 0
          psu_name = "Nguồn LED #{watt}W"
          psu_key = group_by == "NAME" ? psu_name : "#{psu_name}_#{prod}"
          sel_qty = sel_combo[watt] || 0
          if data_map[psu_key]
            data_map[psu_key][:count] += qty
            data_map[psu_key][:sel_count] += sel_qty
          else
            data_map[psu_key] = {
              name: psu_name, product: display_prod, actual_product: prod,
              layer: info[:layer], count: qty, sel_count: sel_qty, length: 0.0, sel_length: 0.0,
              unit: "Cái", dict: "ZSU_LED", key: "ten_hien_thi", type: :count,
              entities: info[:entities], ngay_dat: "", ghi_chu: "", trang_thai: "",
              new_name: "", last_modified: "", stat_entities: [], length_items: [], is_missing: false
            }
          end
          if group_by == "NAME"
            data_map[psu_key][:product_list] ||= []
            data_map[psu_key][:product_list] << prod unless prod.to_s.empty? || data_map[psu_key][:product_list].include?(prod)
          end
        end
      end

      data_map.values.select { |v| v[:name].to_s =~ /suốt áo/i }.each do |suot_data|
        bas_name = "Bas treo suốt áo"
        prod = suot_data[:actual_product] || suot_data[:product]
        display_prod = group_by == "NAME" ? "--" : prod
        bas_key = group_by == "PRODUCT" ? "#{bas_name}_#{prod}" : bas_name
        suot_count = suot_data[:length_items].is_a?(Array) ? suot_data[:length_items].size : suot_data[:count]
        suot_sel_count = suot_data[:length_items].is_a?(Array) ? suot_data[:length_items].count { |li| li[:selected] } : suot_data[:sel_count]
        bas_qty = suot_count * 2
        bas_sel_qty = suot_sel_count * 2
        if data_map[bas_key]
          data_map[bas_key][:count] = bas_qty
          data_map[bas_key][:sel_count] = bas_sel_qty
        else
          data_map[bas_key] = {
            name: bas_name, product: display_prod, actual_product: prod,
            layer: suot_data[:layer], count: bas_qty, sel_count: bas_sel_qty,
            length: 0.0, sel_length: 0.0, unit: "Cái",
            dict: "ABF", key: "setting-name", type: :count,
            entities: suot_data[:entities], stat_entities: [], length_items: [],
            ngay_dat: "", ghi_chu: "", trang_thai: "", new_name: "", last_modified: "",
            is_missing: false
          }
        end
        if group_by == "NAME"
          data_map[bas_key][:product_list] ||= []
          Array(suot_data[:product_list]).each do |p|
            data_map[bas_key][:product_list] << p unless p.to_s.empty? || data_map[bas_key][:product_list].include?(p)
          end
          data_map[bas_key][:product_list] << prod unless prod.to_s.empty? || data_map[bas_key][:product_list].include?(prod)
        end
      end

      if ctx.respond_to?(:accessory_unit_for_name)
        data_map.each do |data_key, row|
          next unless ctx.accessory_unit_for_name(row[:name]) == "md"
          norm_name = ctx.respond_to?(:mh_name_norm) ? ctx.mh_name_norm(row[:name]) : row[:name].to_s.downcase
          next if norm_name =~ /(nguon led|bo nguon|driver led|adapter)/
          next unless norm_name =~ /(led|suot ao|thanh nhom)/
          row[:unit] = "md"
          unit_overrides.delete(data_key)
        end
      end

      TrialResult.new(
        data_map: data_map, mat_data_map: mat_data_map, prod_groups: prod_groups,
        all_item_names: all_item_names, all_item_names_set: all_item_names_set,
        led_per_product: led_per_product
      )
    end

    # ---- fingerprint + diff ----
    def fp_map(map)
      out = {}
      map.each do |k, row|
        out[k.to_s] = {
          'name' => row[:name].to_s, 'product' => row[:product].to_s,
          'actual_product' => row[:actual_product].to_s,
          'count' => row[:count], 'sel_count' => row[:sel_count],
          'length' => (row[:length].to_f.round(4)), 'sel_length' => (row[:sel_length].to_f.round(4)),
          'unit' => row[:unit].to_s, 'type' => row[:type].to_s
        }
      end
      out
    end

    def diff_maps(ref, got)
      ref_keys = ref.keys.sort
      got_keys = got.keys.sort
      missing = ref_keys - got_keys
      extra = got_keys - ref_keys
      changed = []
      (ref_keys & got_keys).each do |k|
        changed << { 'key' => k, 'ref' => ref[k], 'got' => got[k] } if ref[k] != got[k]
      end
      {
        'same' => missing.empty? && extra.empty? && changed.empty?,
        'ref_count' => ref_keys.length, 'got_count' => got_keys.length,
        'missing_keys' => missing.first(10), 'extra_keys' => extra.first(10),
        'changed' => changed.first(10), 'changed_total' => changed.length
      }
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rescue
      Time.now.to_f
    end

    def ms(t0); ((now - t0) * 1000.0).round(1); end

    def run(model: Sketchup.active_model, selection: nil)
      selection ||= model.selection
      s = MH_Thongke.session
      args = {
        group_by: s.group_by,
        hidden_list: Array(s.hidden_list).dup,
        unit_overrides: (s.unit_overrides.is_a?(Hash) ? s.unit_overrides.dup : {}),
        led_power_factor: MH_Thongke.instance_variable_get(:@led_power_factor),
        psu_list: MH_Thongke.instance_variable_get(:@psu_list)
      }

      ctx = MH_Thongke
      saved = {}
      CTX_IVARS.each { |iv| saved[iv] = ctx.instance_variable_get(iv) }

      result = { 'ok' => true }
      begin
        # 1) reference = scanner active thật
        ref = MH_Thongke::Engine::ModelScanner.scan(model: model, selection: selection, **args)
        ref_data = fp_map(ref.data_map)
        ref_mat  = fp_map(ref.mat_data_map)
        ref_prod = ref.prod_groups.keys.sort

        # 2) streaming cold (sau invalidate) + warm
        MH::ModelHub.invalidate!(:all) if defined?(MH::ModelHub)
        t0 = now
        st1 = scan_stream(model: model, selection: selection, **args)
        cold = ms(t0)
        t1 = now
        st2 = scan_stream(model: model, selection: selection, **args)
        warm = ms(t1)

        got_data = fp_map(st2.data_map)
        got_mat  = fp_map(st2.mat_data_map)
        got_prod = st2.prod_groups.keys.sort

        result['stream_cold_ms'] = cold
        result['stream_warm_ms'] = warm
        result['counts'] = {
          'ref' => { 'data_map' => ref_data.length, 'mat' => ref_mat.length, 'prod' => ref_prod.length },
          'stream' => { 'data_map' => got_data.length, 'mat' => got_mat.length, 'prod' => got_prod.length }
        }
        result['diff_data_map'] = diff_maps(ref_data, got_data)
        result['diff_mat_data_map'] = diff_maps(ref_mat, got_mat)
        result['diff_prod_groups_same'] = (ref_prod == got_prod)
        result['bom_diff_zero'] = result['diff_data_map']['same'] && result['diff_mat_data_map']['same'] && result['diff_prod_groups_same']
      rescue => e
        result['ok'] = false
        result['error'] = "#{e.class}: #{e.message}"
        result['backtrace'] = Array(e.backtrace).first(10)
      ensure
        CTX_IVARS.each { |iv| ctx.instance_variable_set(iv, saved[iv]) }
      end
      result
    end

    # ============================================================
    # PHƯƠNG ÁN MỚI: walker chung "stateful, allocation-light".
    # State nghiệp vụ luồn xuống con qua GIÁ TRỊ TRẢ VỀ của block (giống đệ quy gốc).
    # KHÔNG ScanRecord, KHÔNG Context, KHÔNG khoá chuỗi, KHÔNG hash parent_key.
    # ============================================================

    # block.call(entity, parent_transform, parent_state) -> child_state
    def walk_stateful(root_entities, types:, include_hidden:, reject_names:, root_state:, &blk)
      reject = reject_names || []
      want_group = types.include?(:group)
      want_comp = types.include?(:component)
      recur = nil
      recur = lambda do |ents, parent_tr, pstate|
        ents.each do |e|
          is_grp = e.is_a?(Sketchup::Group)
          is_cmp = e.is_a?(Sketchup::ComponentInstance)
          next unless (want_group && is_grp) || (want_comp && is_cmp)
          next if reject.include?(e.name.to_s.strip)
          next if !include_hidden && (e.hidden? rescue false)
          cstate = blk.call(e, parent_tr, pstate)
          ch = (is_cmp ? e.definition.entities : e.entities) rescue nil
          recur.call(ch, parent_tr * e.transformation, cstate) if ch
        end
      end
      recur.call(root_entities, Geom::Transformation.new, root_state)
      nil
    end

    def scan_stream_lean(model:, selection:, group_by:, hidden_list:, unit_overrides:, led_power_factor:, psu_list:)
      data_map = {}
      mat_data_map = {}
      all_item_names = []
      all_item_names_set = Set.new
      led_per_product = {}
      prod_groups = {}
      stat_entity_ids = Hash.new { |h, k| h[k] = Set.new }
      entity_ids_in_data = Hash.new { |h, k| h[k] = Set.new }
      prod_group_entity_ids = Hash.new { |h, k| h[k] = Set.new }
      selection_set = selection.respond_to?(:to_a) ? selection.to_a.to_set : Set.new
      phaochi_map = {}
      material_face_fallback_cache = {}

      ctx = MH_Thongke
      ctx.instance_variable_set(:@data_map, data_map)
      ctx.instance_variable_set(:@mat_data_map, mat_data_map)
      ctx.instance_variable_set(:@all_item_names, all_item_names)
      ctx.instance_variable_set(:@all_item_names_set, all_item_names_set)
      ctx.instance_variable_set(:@led_per_product, led_per_product)
      ctx.instance_variable_set(:@prod_groups, prod_groups)
      ctx.instance_variable_set(:@stat_entity_ids, stat_entity_ids)
      ctx.instance_variable_set(:@entity_ids_in_data, entity_ids_in_data)
      ctx.instance_variable_set(:@hidden_list, hidden_list)
      ctx.instance_variable_set(:@unit_overrides, unit_overrides)
      ctx.instance_variable_set(:@group_by, group_by)

      node = lambda do |e, parent_wt, pstate|
        parent_prod     = pstate[0]
        top_level       = pstate[1]
        parent_selected = pstate[2]

        e_name = e.name.to_s.strip
        parent_has_product = MH_Thongke.product_code_valid?(parent_prod) rescue !!(parent_prod =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?/)
        current_prod = parent_prod
        unless e_name.empty?
          product_hit = MH_Thongke.product_codes_from_text(e_name).first rescue e_name[/([A-Z]+\d+[A-Z]?(?:\.\d+)?)/i, 1]
          if product_hit
            product_hit = MH_Thongke.product_code_exact(product_hit) rescue product_hit.to_s.upcase
            if !parent_has_product || (MH_Thongke.product_code_base(product_hit) rescue product_hit) == (MH_Thongke.product_code_base(parent_prod) rescue parent_prod) || parent_prod == "--"
              current_prod = product_hit
            end
            product_key = product_hit
            prod_groups[product_key] ||= []
            product_entity_id = e.entityID rescue e.object_id
            unless prod_group_entity_ids[product_key].include?(product_entity_id)
              prod_groups[product_key] << e
              prod_group_entity_ids[product_key] << product_entity_id
            end
          elsif !parent_has_product
            current_prod = e_name
          end
        end

        prod_code = current_prod
        current_top = top_level || e
        is_selected = parent_selected || selection_set.include?(e)
        ret = [current_prod, current_top, is_selected]

        name = nil
        dict = "ABF"
        key = "statistical-name"
        type = :count

        e_display_name = e.get_attribute("ABF", "statistical-name") || e.get_attribute("ABF", "setting-name") || e_name
        is_phaochi = begin
          if ctx.respond_to?(:phaochi_name?)
            from_def = (e.respond_to?(:definition) && e.definition) ? e.definition.name.to_s : ""
            ctx.phaochi_name?(e_display_name) || ctx.phaochi_name?(e_name) || (!from_def.empty? && ctx.phaochi_name?(from_def))
          else
            e_display_name.to_s =~ /ph[àa]o ch[ỉi]/i
          end
        rescue
          e_display_name.to_s =~ /ph[àa]o ch[ỉi]/i
        end

        generated_pk = e.get_attribute("MH_Thongke", "generated_pk").to_s == "true"
        is_phaochi = false if generated_pk
        if generated_pk
          name = e.get_attribute("MH_Thongke", "pk_name") ||
                 e.get_attribute("ABF", "statistical-name") ||
                 e.get_attribute("ABF", "setting-name") ||
                 e_name.to_s.sub(/\APK\s+\w+\s*-\s*/i, "")
          name = ctx.ensure_pk_marker_attributes(e, name)
          dict = "MH_Thongke"
          key = "pk_name"
          type = :count
        end

        special_name = e_display_name.to_s.empty? && e.respond_to?(:definition) ? e.definition.name : e_display_name
        special_kind = generated_pk ? nil : ctx.special_hardware_kind(special_name)
        if special_kind
          ctx.add_special_hardware_row(special_kind, e, parent_wt, prod_code, current_top, is_selected, special_name)
          next ret
        end

        if is_phaochi
          info = ctx.get_phaochi_info(e, parent_wt)
          w_r = info[:w_mm].round(0).to_i
          h_r = info[:h_mm].round(0).to_i
          stat_name = "Phào chỉ #{w_r}x#{h_r}"
          phaochi_prod = (MH_Thongke.product_code_valid?(prod_code) rescue prod_code.to_s =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?/i) ? (MH_Thongke.product_code_exact(prod_code) rescue prod_code.to_s.upcase) : "--"
          display_prod = group_by == "NAME" ? "--" : phaochi_prod
          pc_key = group_by == "NAME" ? stat_name : "#{stat_name}_#{phaochi_prod}"

          phaochi_map[pc_key] ||= {
            name: stat_name, product: display_prod, actual_product: phaochi_prod,
            ten_sp: e.get_attribute("MH_Thongke", "ten_sp") || "",
            ghi_chu: e.get_attribute("MH_Thongke", "ghi_chu") || "",
            ngay_dat: ctx.normalize_order_date(e.get_attribute("MH_Thongke", "ngay_dat")),
            last_modified: e.get_attribute("MH_Thongke", "last_modified") || "",
            layer: e.layer.name, len_total_mm: 0.0, sel_len_mm: 0.0,
            count: 0, sel_count: 0, unit: "md",
            type: :phaochi, dict: "ABF", key: "statistical-name",
            entities: [], stat_entities: [], length_items: [],
            trang_thai: "", new_name: "", is_missing: false
          }

          phaochi_map[pc_key][:len_total_mm] += info[:len_mm]
          phaochi_map[pc_key][:sel_len_mm] += info[:len_mm] if is_selected
          phaochi_map[pc_key][:count] += 1
          phaochi_map[pc_key][:sel_count] += 1 if is_selected
          top_id = current_top.entityID rescue nil
          e_id = e.entityID rescue nil
          phaochi_map[pc_key][:entities] << current_top unless top_id && entity_ids_in_data[pc_key].include?(top_id)
          entity_ids_in_data[pc_key] << top_id if top_id
          unless e_id && stat_entity_ids[pc_key].include?(e_id)
            phaochi_map[pc_key][:stat_entities] << [e, current_top, parent_wt]
            stat_entity_ids[pc_key] << e_id if e_id
          end
          phaochi_map[pc_key][:length_items] << { len_mm: info[:len_mm], top: current_top, selected: is_selected }

          if group_by == "NAME"
            ten_sp_value = e.get_attribute("MH_Thongke", "ten_sp").to_s
            phaochi_map[pc_key][:product_list] ||= []
            phaochi_map[pc_key][:ten_sp_list] ||= []
            phaochi_map[pc_key][:product_list] << phaochi_prod unless phaochi_prod.empty? || phaochi_prod == "--" || phaochi_map[pc_key][:product_list].include?(phaochi_prod)
            phaochi_map[pc_key][:ten_sp_list] << ten_sp_value unless ten_sp_value.empty? || phaochi_map[pc_key][:ten_sp_list].include?(ten_sp_value)
          end

          all_item_names << stat_name unless all_item_names_set.include?(stat_name)
          all_item_names_set << stat_name
          next ret
        end

        if !generated_pk && (e.get_attribute("ABF", "is-minifix-part-a") || e.get_attribute("ABF", "is-minifix-part-b") || e.get_attribute("ABF", "is-hinge-part-b") || e.get_attribute("ABF", "is-side-drill"))
          name = e.get_attribute("ABF", "setting-name")
          key = "setting-name"
        elsif e.get_attribute("ZSU_LED", "ten_hien_thi") || e.get_attribute("ABF", "statistical-type") == "length_measuring"
          name = e.get_attribute("ZSU_LED", "ten_hien_thi") || e.get_attribute("ABF", "statistical-name") || e.get_attribute("ABF", "setting-name")
          dict = e.get_attribute("ZSU_LED", "ten_hien_thi") ? "ZSU_LED" : "ABF"
          key = e.get_attribute("ZSU_LED", "ten_hien_thi") ? "ten_hien_thi" : (e.get_attribute("ABF", "statistical-name") ? "statistical-name" : "setting-name")
          type = :length
        elsif e.get_attribute("ABF", "is-intersect").to_s == "true"
          name = e.get_attribute("ABF", "setting-name")
          dict = "ABF"
          key = "setting-name"
          type = :length
        elsif e.get_attribute("ABF", "is-statistical-object").to_s == "true"
          name = e.get_attribute("ABF", "statistical-name")
        elsif e.get_attribute("ZSU", "ban_le")
          name = e.get_attribute("ABF", "statistical-name") || "Bản lề ZSU"
        elsif e.get_attribute("ABF", "statistical-name")
          name = e.get_attribute("ABF", "statistical-name")
        end

        if name
          row_product = prod_code
          if generated_pk
            marker_product = e.get_attribute("MH_Thongke", "product_code").to_s.strip
            row_product = marker_product unless marker_product.empty?
          end
          name = ctx.accessory_display_name_for_rules(name) if ctx.respond_to?(:accessory_display_name_for_rules)
          all_item_names << name unless all_item_names_set.include?(name)
          all_item_names_set << name
          unless ctx.hidden_item_name?(name)
            layer_name = e.layer.name
            unit_default = "Cái"
            unit_actual = type == :length ? "mm" : unit_default
            unit_actual = ctx.accessory_unit_for_name(name) || unit_actual if ctx.respond_to?(:accessory_unit_for_name)
            data_key = case group_by
                       when "NAME" then name
                       when "PRODUCT" then "#{name}_#{row_product}"
                       else name
                       end
            data_map[data_key] ||= {
              name: name, product: (group_by == "NAME" ? "--" : row_product),
              actual_product: row_product,
              ten_sp: e.get_attribute("MH_Thongke", "ten_sp") || "",
              ghi_chu: e.get_attribute("MH_Thongke", "ghi_chu") || "",
              ngay_dat: ctx.normalize_order_date(e.get_attribute("MH_Thongke", "ngay_dat")),
              last_modified: e.get_attribute("MH_Thongke", "last_modified") || "",
              trang_thai: "", new_name: "",
              layer: layer_name, count: 0, length: 0.0, sel_count: 0, sel_length: 0.0, unit: unit_actual,
              dict: dict, key: key, type: type, entities: [], stat_entities: [],
              length_items: [], is_missing: false
            }
            if group_by == "NAME"
              ten_sp_value = e.get_attribute("MH_Thongke", "ten_sp").to_s
              data_map[data_key][:product_list] ||= []
              data_map[data_key][:ten_sp_list] ||= []
              data_map[data_key][:product_list] << row_product unless row_product.to_s.empty? || data_map[data_key][:product_list].include?(row_product)
              data_map[data_key][:ten_sp_list] << ten_sp_value unless ten_sp_value.empty? || data_map[data_key][:ten_sp_list].include?(ten_sp_value)
            end
            if type == :length
              len = ctx.get_world_length(e, parent_wt)
              data_map[data_key][:length] += len
              data_map[data_key][:sel_length] += len if is_selected
              data_map[data_key][:length_items] << { len_inch: len, top: current_top, selected: is_selected }
              if name.to_s =~ /led/i
                led_per_product[row_product] ||= { length: 0.0, sel_length: 0.0, layer: layer_name, entities: [] }
                led_per_product[row_product][:length] += len
                led_per_product[row_product][:sel_length] += len if is_selected
                led_per_product[row_product][:entities] << current_top unless led_per_product[row_product][:entities].include?(current_top)
              end
            else
              data_map[data_key][:count] += 1
              data_map[data_key][:sel_count] += 1 if is_selected
            end
            top_id = current_top.entityID rescue nil
            e_id = e.entityID rescue nil
            unless top_id && entity_ids_in_data[data_key].include?(top_id)
              data_map[data_key][:entities] << current_top
              entity_ids_in_data[data_key] << top_id if top_id
            end
            unless e_id && stat_entity_ids[data_key].include?(e_id)
              data_map[data_key][:stat_entities] << [e, current_top, parent_wt]
              stat_entity_ids[data_key] << e_id if e_id
            end
          end
        end

        if name.nil?
          mat_name = nil
          if e.material && !e.material.name.empty? && !skip_material?(e.material.display_name)
            mat_name = e.material.display_name
          end
          if mat_name.nil?
            cache_key =
              if e.is_a?(Sketchup::ComponentInstance) && e.respond_to?(:definition) && e.definition
                begin
                  "def:#{e.definition.persistent_id}"
                rescue
                  "def:#{e.definition.object_id}"
                end
              else
                begin
                  "ent:#{e.persistent_id}"
                rescue
                  "ent:#{e.object_id}"
                end
              end
            cached_face_material = material_face_fallback_cache[cache_key]
            if cached_face_material == false
              mat_name = nil
            elsif cached_face_material
              mat_name = cached_face_material
            else
              inner_ents = (e.is_a?(Sketchup::ComponentInstance) ? e.definition.entities : e.entities) rescue nil
              if inner_ents
                face_mats = inner_ents.grep(Sketchup::Face).flat_map { |f|
                  [f.material&.display_name, f.back_material&.display_name]
                }.compact.reject { |m| m.empty? || skip_material?(m) }.uniq
                mat_name = face_mats.first unless face_mats.empty?
              end
              material_face_fallback_cache[cache_key] = mat_name || false
            end
          end

          if mat_name && !mat_name.empty?
            mat_prod = (MH_Thongke.product_code_valid?(prod_code) rescue prod_code.to_s =~ /\A[A-Z]+\d+/i) ? (MH_Thongke.product_code_exact(prod_code) rescue prod_code.to_s.upcase) : "--"
            display_mat_name = mat_name.to_s.strip
            thickness = material_code_thickness(display_mat_name)
            layer_name = e.layer.name.to_s
            m_key = case group_by
                    when "NAME" then display_mat_name
                    when "PRODUCT" then "#{display_mat_name}_#{mat_prod}"
                    else display_mat_name
                    end
            mat_data_map[m_key] ||= {
              name: display_mat_name, thickness: thickness,
              product: (group_by == "NAME" ? "--" : mat_prod), actual_product: mat_prod,
              ten_sp: e.get_attribute("MH_Thongke", "mat_ten_sp") || "",
              ghi_chu: e.get_attribute("MH_Thongke", "mat_ghi_chu") || "",
              ngay_dat: ctx.normalize_order_date(e.get_attribute("MH_Thongke", "mat_ngay_dat")),
              last_modified: "", trang_thai: "", new_name: "", layer: layer_name,
              count: 0, length: 0.0, sel_count: 0, sel_length: 0.0, unit: "Tam",
              dict: "", key: "", type: :count, entities: [], stat_entities: [], is_missing: false,
              layer_tags: []
            }
            mat_data_map[m_key][:count] += 1
            mat_data_map[m_key][:sel_count] += 1 if is_selected
            mat_data_map[m_key][:layer_tags] << layer_name unless mat_data_map[m_key][:layer_tags].include?(layer_name)
            m_top_id = current_top.entityID rescue nil
            m_e_id = e.entityID rescue nil
            unless m_top_id && entity_ids_in_data[m_key].include?(m_top_id)
              mat_data_map[m_key][:entities] << current_top
              entity_ids_in_data[m_key] << m_top_id if m_top_id
            end
            unless m_e_id && stat_entity_ids[m_key].include?(m_e_id)
              mat_data_map[m_key][:stat_entities] << [e, current_top, parent_wt]
              stat_entity_ids[m_key] << m_e_id if m_e_id
            end
          end
        end

        ret
      end

      walk_stateful(
        model.active_entities,
        types: %i[group component],
        include_hidden: true,
        reject_names: ['__ABF_Nesting'],
        root_state: ["--", nil, false],
        &node
      )

      # ---- post-loop (verbatim) ----
      phaochi_map.each do |pc_key, pc_data|
        next if ctx.hidden_item_name?(pc_data[:name])
        dk_ovr = unit_overrides[pc_key]
        data_map[pc_key] = pc_data.merge(unit: dk_ovr || "md")
      end

      led_per_product.each do |prod, info|
        total_led_length = info[:length]
        sel_led_length = info[:sel_length] || 0.0
        display_prod = group_by == "NAME" ? "--" : prod
        alum_name = "Thanh nhôm LED"
        alum_key = group_by == "NAME" ? alum_name : "#{alum_name}_#{prod}"
        if data_map[alum_key]
          data_map[alum_key][:length] += total_led_length
          data_map[alum_key][:sel_length] += sel_led_length
        else
          data_map[alum_key] = {
            name: alum_name, product: display_prod, actual_product: prod,
            layer: info[:layer], count: 0, sel_count: 0, length: total_led_length,
            sel_length: sel_led_length, unit: "md",
            dict: "ZSU_LED", key: "ten_hien_thi", type: :length, entities: info[:entities],
            ngay_dat: "", ghi_chu: "", trang_thai: "", new_name: "", last_modified: "",
            stat_entities: [], length_items: [], is_missing: false
          }
        end
        if group_by == "NAME"
          data_map[alum_key][:product_list] ||= []
          data_map[alum_key][:product_list] << prod unless prod.to_s.empty? || data_map[alum_key][:product_list].include?(prod)
        end

        total_led_length_m = total_led_length.to_f * 0.0254
        sel_led_length_m = sel_led_length.to_f * 0.0254
        req_power = led_power_factor.to_f * total_led_length_m
        sel_req_power = led_power_factor.to_f * sel_led_length_m
        best_combo = ctx.led_psu_combo(req_power, psu_list)
        sel_combo = ctx.led_psu_combo(sel_req_power, psu_list)
        best_combo.each do |watt, qty|
          next if qty <= 0
          psu_name = "Nguồn LED #{watt}W"
          psu_key = group_by == "NAME" ? psu_name : "#{psu_name}_#{prod}"
          sel_qty = sel_combo[watt] || 0
          if data_map[psu_key]
            data_map[psu_key][:count] += qty
            data_map[psu_key][:sel_count] += sel_qty
          else
            data_map[psu_key] = {
              name: psu_name, product: display_prod, actual_product: prod,
              layer: info[:layer], count: qty, sel_count: sel_qty, length: 0.0, sel_length: 0.0,
              unit: "Cái", dict: "ZSU_LED", key: "ten_hien_thi", type: :count,
              entities: info[:entities], ngay_dat: "", ghi_chu: "", trang_thai: "",
              new_name: "", last_modified: "", stat_entities: [], length_items: [], is_missing: false
            }
          end
          if group_by == "NAME"
            data_map[psu_key][:product_list] ||= []
            data_map[psu_key][:product_list] << prod unless prod.to_s.empty? || data_map[psu_key][:product_list].include?(prod)
          end
        end
      end

      data_map.values.select { |v| v[:name].to_s =~ /suốt áo/i }.each do |suot_data|
        bas_name = "Bas treo suốt áo"
        prod = suot_data[:actual_product] || suot_data[:product]
        display_prod = group_by == "NAME" ? "--" : prod
        bas_key = group_by == "PRODUCT" ? "#{bas_name}_#{prod}" : bas_name
        suot_count = suot_data[:length_items].is_a?(Array) ? suot_data[:length_items].size : suot_data[:count]
        suot_sel_count = suot_data[:length_items].is_a?(Array) ? suot_data[:length_items].count { |li| li[:selected] } : suot_data[:sel_count]
        bas_qty = suot_count * 2
        bas_sel_qty = suot_sel_count * 2
        if data_map[bas_key]
          data_map[bas_key][:count] = bas_qty
          data_map[bas_key][:sel_count] = bas_sel_qty
        else
          data_map[bas_key] = {
            name: bas_name, product: display_prod, actual_product: prod,
            layer: suot_data[:layer], count: bas_qty, sel_count: bas_sel_qty,
            length: 0.0, sel_length: 0.0, unit: "Cái",
            dict: "ABF", key: "setting-name", type: :count,
            entities: suot_data[:entities], stat_entities: [], length_items: [],
            ngay_dat: "", ghi_chu: "", trang_thai: "", new_name: "", last_modified: "",
            is_missing: false
          }
        end
        if group_by == "NAME"
          data_map[bas_key][:product_list] ||= []
          Array(suot_data[:product_list]).each do |p|
            data_map[bas_key][:product_list] << p unless p.to_s.empty? || data_map[bas_key][:product_list].include?(p)
          end
          data_map[bas_key][:product_list] << prod unless prod.to_s.empty? || data_map[bas_key][:product_list].include?(prod)
        end
      end

      if ctx.respond_to?(:accessory_unit_for_name)
        data_map.each do |data_key, row|
          next unless ctx.accessory_unit_for_name(row[:name]) == "md"
          norm_name = ctx.respond_to?(:mh_name_norm) ? ctx.mh_name_norm(row[:name]) : row[:name].to_s.downcase
          next if norm_name =~ /(nguon led|bo nguon|driver led|adapter)/
          next unless norm_name =~ /(led|suot ao|thanh nhom)/
          row[:unit] = "md"
          unit_overrides.delete(data_key)
        end
      end

      TrialResult.new(
        data_map: data_map, mat_data_map: mat_data_map, prod_groups: prod_groups,
        all_item_names: all_item_names, all_item_names_set: all_item_names_set,
        led_per_product: led_per_product
      )
    end

    def run_lean(model: Sketchup.active_model, selection: nil)
      selection ||= model.selection
      s = MH_Thongke.session
      args = {
        group_by: s.group_by,
        hidden_list: Array(s.hidden_list).dup,
        unit_overrides: (s.unit_overrides.is_a?(Hash) ? s.unit_overrides.dup : {}),
        led_power_factor: MH_Thongke.instance_variable_get(:@led_power_factor),
        psu_list: MH_Thongke.instance_variable_get(:@psu_list)
      }
      ctx = MH_Thongke
      saved = {}
      CTX_IVARS.each { |iv| saved[iv] = ctx.instance_variable_get(iv) }
      result = { 'ok' => true }
      begin
        ref = MH_Thongke::Engine::ModelScanner.scan(model: model, selection: selection, **args)
        ref_data = fp_map(ref.data_map); ref_mat = fp_map(ref.mat_data_map); ref_prod = ref.prod_groups.keys.sort

        MH::ModelHub.invalidate!(:all) if defined?(MH::ModelHub)
        t0 = now; scan_stream_lean(model: model, selection: selection, **args); cold = ms(t0)
        t1 = now; st2 = scan_stream_lean(model: model, selection: selection, **args); warm = ms(t1)

        got_data = fp_map(st2.data_map); got_mat = fp_map(st2.mat_data_map); got_prod = st2.prod_groups.keys.sort
        result['lean_cold_ms'] = cold
        result['lean_warm_ms'] = warm
        result['counts'] = { 'ref' => { 'd' => ref_data.length, 'm' => ref_mat.length, 'p' => ref_prod.length },
                             'lean' => { 'd' => got_data.length, 'm' => got_mat.length, 'p' => got_prod.length } }
        dd = diff_maps(ref_data, got_data); dm = diff_maps(ref_mat, got_mat)
        result['diff_data_map'] = dd
        result['diff_mat_data_map'] = dm
        result['diff_prod_groups_same'] = (ref_prod == got_prod)
        result['bom_diff_zero'] = dd['same'] && dm['same'] && (ref_prod == got_prod)
      rescue => e
        result['ok'] = false; result['error'] = "#{e.class}: #{e.message}"; result['backtrace'] = Array(e.backtrace).first(10)
      ensure
        CTX_IVARS.each { |iv| ctx.instance_variable_set(iv, saved[iv]) }
      end
      result
    end
  end

  def self.p3_trial_run(**kw)
    P3Trial.run(**kw)
  end

  def self.p3_trial_run_lean(**kw)
    P3Trial.run_lean(**kw)
  end
end

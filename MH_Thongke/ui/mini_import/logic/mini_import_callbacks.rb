# encoding: utf-8
# MH_Thongke — mini import callbacks
# UI/render/dialog cho Mini Import. Không chứa logic xử lý thống kê lõi.
module MH_Thongke

  # === mini_import_dialog_callbacks_core.rb ===
  # --- mini_import_dialog_callbacks_core.rb ---
# MH_Thongke - Mini Import dialog core callbacks.


  def self.register_mini_import_dialog_core_callbacks
    @mini_dlg.add_action_callback("get_rows") { |_| refresh_import_mini_dialog(true, false) }
    @mini_dlg.add_action_callback("refresh") { |_| mini_import_on_refresh }
    @mini_dlg.add_action_callback("refresh_excel") { |_| mini_import_on_refresh_excel }
    @mini_dlg.add_action_callback("open_hud") { |_| mini_import_on_open_hud }
    @mini_dlg.add_action_callback("save_position") { |_, x, y| mini_import_on_save_position(x, y) }
    @mini_dlg.add_action_callback("set_mode") { |_, mode| mini_import_on_set_mode(mode) }
    @mini_dlg.add_action_callback("set_source_mode") { |_, mode| mini_import_on_set_source_mode(mode) }
    @mini_dlg.add_action_callback("close_mini") { |_| mini_import_on_close }
    @mini_dlg.add_action_callback("cancel_accepts") { |_| mini_import_on_cancel }
    @mini_dlg.add_action_callback("ok_accepts") { |_| mini_import_on_ok }
    @mini_dlg.add_action_callback("undo_mini") { |_| mini_import_on_undo }
  end

  def self.mini_import_on_refresh
    if respond_to?(:invalidate_mini_import_caches)
      invalidate_mini_import_caches(model: true)
    else
      @mini_model_items_cache = nil
      @mini_last_refresh_state_sig = nil
    end
    @mini_force_sp_index_rebuild = true
    refresh_import_mini_dialog(true, false)
    refresh_import_material_hud(false, true) if respond_to?(:material_hud_visible?) && material_hud_visible?
  end

  def self.mini_import_on_refresh_excel
    schedule_import_excel_reload(nil, "mini_import")
  end

  def self.mini_import_on_open_hud
    show_import_material_hud
  end

  def self.mini_import_on_save_position(x, y)
    save_import_mini_dialog_position(x, y)
  end

  def self.mini_import_on_set_mode(mode)
    set_mini_group_mode(mode)
    refresh_mini_import_context_views(false)
  end

  def self.mini_import_on_set_source_mode(mode)
    set_mini_product_source_mode(mode)
    refresh_mini_import_context_views(true)
  end

  def self.mini_import_on_close
    @mini_close_requested = true
    @mini_close_action = "close"
    save_import_mini_dialog_position
    @mini_dlg.close if @mini_dlg
    detach_observers_if_idle
  end

  def self.mini_import_on_cancel
    begin
      @mini_close_requested = true
      @mini_close_action = "cancel"
      @mini_cancel_requested_at = Time.now.to_f
      mini_cancel_session
      clear_caches if respond_to?(:clear_caches)
      if respond_to?(:refresh_import_related_views)
        refresh_import_related_views(true, false, false)
      else
        respond_to?(:process_selection_cached) ? process_selection_cached(true) : process_selection
        refresh_import_material_hud(false, false) if respond_to?(:material_hud_visible?) && material_hud_visible?
        update_html if @dlg && @dlg.visible?
      end
      save_import_mini_dialog_position
      @mini_dlg.close if @mini_dlg
      detach_observers_if_idle
    rescue => e
      @model.abort_operation rescue nil
      UI.messagebox(e.message)
    end
  end

  def self.mini_import_on_ok
    @mini_close_requested = true
    @mini_close_action = "ok"
    mini_ok_session
    save_import_mini_dialog_position
    @mini_dlg.close if @mini_dlg
    detach_observers_if_idle
  end

  def self.mini_import_on_undo
    begin
      mini_undo_last_action
      if respond_to?(:refresh_import_related_views)
        refresh_import_related_views(true, false, false)
      else
        respond_to?(:process_selection_cached) ? process_selection_cached(true) : process_selection
        refresh_import_mini_dialog(false, false)
        refresh_import_material_hud(false, false) if respond_to?(:material_hud_visible?) && material_hud_visible?
        update_html if @dlg && @dlg.visible?
      end
    rescue => e
      UI.messagebox(e.message)
    end
  end

  # === mini_import_dialog_callbacks_items_accept.rb ===
  # --- mini_import_dialog_callbacks_items_accept.rb ---
# MH_Thongke - Mini Import dialog item callbacks (accept/keep/apply).


  def self.mini_import_refresh_after_status_change
    if respond_to?(:refresh_import_related_views)
      refresh_import_related_views(true, false, false, 0.1)
    else
      respond_to?(:process_selection_cached) ? process_selection_cached(true) : process_selection
      refresh_import_mini_dialog(false, false)
      refresh_import_material_hud(false, false) if respond_to?(:material_hud_visible?) && material_hud_visible?
      UI.start_timer(0.1, false) { update_html if @dlg && @dlg.visible? } if defined?(UI)
    end
  end

  def self.register_mini_import_item_callback_accept
    @mini_dlg.add_action_callback("accept_item") { |_, product_code, kind, old_name, new_name, spec|
      begin
        product = mini_action_product(product_code)
        restore_before = respond_to?(:mini_import_restore_before_state) ? mini_import_restore_before_state : (respond_to?(:current_restore_state) ? current_restore_state : nil)
        if kind.to_s == "VL"
          target_product = product.to_s.strip
          target_product_valid = begin
            product_code_valid?(target_product)
          rescue
            target_product =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?\z/i
          end
          if target_product_valid
            selected_codes = respond_to?(:selected_product_codes) ? selected_product_codes(false) : []
            selected_products = selected_codes.map do |c|
              begin
                product_code_exact(c)
              rescue
                c.to_s.strip.upcase
              end
            end.select do |c|
              begin
                product_code_valid?(c)
              rescue
                c =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?\z/i
              end
            end
                                             .uniq
            target_norm = begin
              product_code_exact(target_product)
            rescue
              target_product.upcase
            end
            unless selected_products.include?(target_norm)
              UI.messagebox("Vui l\u00F2ng ch\u1ECDn \u0111\u1ED1i t\u01B0\u1EE3ng thu\u1ED9c \u0111\u00FAng #{target_product} tr\u01B0\u1EDBc khi Add v\u1EADt li\u1EC7u.")
              next
            end
          else
            UI.messagebox("\u0110\u1ED1i t\u01B0\u1EE3ng \u0111ang ch\u1ECDn kh\u00F4ng thu\u1ED9c m\u00E3 s\u1EA3n ph\u1EA9m h\u1EE3p l\u1EC7. Kh\u00F4ng th\u1EC3 Add v\u1EADt li\u1EC7u.")
            next
          end
        end

        @model.start_operation("Mini Import Accept Status", true)
        record_mini_accept(product, kind, old_name, new_name, spec, "accept")
        @model.commit_operation
        record_restore_action("mini_accept", "Mini Import accept", { product: product, kind: kind, old_name: old_name, name: new_name, spec: spec }, restore_before, current_restore_state) if restore_before && respond_to?(:record_restore_action)
        mark_mini_session_operation
        mini_import_refresh_after_status_change
      rescue => e
        respond_to?(:mini_import_abort_with_message) ? mini_import_abort_with_message(e) : UI.messagebox(e.message)
      end
    }
  end

  def self.mini_import_manual_match_choices(product, kind)
    Array(mini_excel_items(product, false, mini_group_mode)).select do |row|
      row_kind = row[:kind].to_s.empty? ? "PK" : row[:kind].to_s
      row_kind == kind.to_s
    end.map do |row|
      hw = row[:hw_name].to_s.strip
      spec = row[:spec].to_s.strip
      section = row[:section].to_s.strip
      label_parts = []
      label_parts << hw unless hw.empty?
      label_parts << spec unless spec.empty?
      label_parts << "[#{section}]" unless section.empty?
      label = label_parts.join(" — ")
      next if label.empty?

      [label, row]
    end.compact
  rescue
    []
  end

  def self.mini_import_choose_manual_match(product, kind, model_name)
    choices = mini_import_manual_match_choices(product, kind)
    raise "Không có dòng Excel cùng SP để match." if choices.empty?

    labels = choices.map(&:first)
    result = UI.inputbox(
      ["Tên model/att", "Chọn dòng Excel"],
      [model_name.to_s, labels.first],
      ["", labels.join("|")],
      "Match tay với Excel"
    )
    return nil unless result

    selected_label = result[1].to_s
    pair = choices.find { |label, _| label == selected_label }
    pair ? pair[1] : nil
  end

  def self.register_mini_import_item_callback_manual_match
    @mini_dlg.add_action_callback("manual_match_item") { |_, product_code, kind, model_name|
      begin
        product = mini_action_product(product_code)
        kind = kind.to_s.empty? ? "PK" : kind.to_s
        model_name = model_name.to_s.strip
        raise "Tên model/att rỗng." if model_name.empty?

        excel_row = mini_import_choose_manual_match(product, kind, model_name)
        next unless excel_row

        hw_name = excel_row[:hw_name].to_s.strip
        spec = excel_row[:spec].to_s.strip
        section = excel_row[:section].to_s.strip
        target_name = if respond_to?(:pk_update_target_name)
          pk_update_target_name(excel_row, nil).to_s
        elsif respond_to?(:import_display_name)
          import_display_name(hw_name, spec)
        else
          [hw_name, spec].reject(&:empty?).join(" ")
        end
        restore_before = mini_import_restore_before_state
        entities = mini_import_resolve_entities_for_name(product, model_name) rescue []

        @model.start_operation("Mini Import Manual Match", true)
        record_mini_accept(product, kind, model_name, target_name, spec, "manual_match")
        entities.each do |ent|
          next unless ent && !(ent.respond_to?(:deleted?) && ent.deleted?)
          record_entity_excel_match(ent, {
            product: product,
            kind: kind,
            old_name: model_name,
            target_name: target_name,
            excel_name: hw_name,
            spec: spec,
            section: section,
            source: "manual_match",
            action: "manual_match"
          }) if respond_to?(:record_entity_excel_match)
        end
        @model.commit_operation

        save_history("Mini Import match tay", "Mã SP: #{product}, #{model_name} -> Excel: #{target_name}") rescue nil
        mini_import_record_restore_if_available("mini_manual_match", "Mini Import match tay", { product: product, kind: kind, model_name: model_name, target: target_name, spec: spec }, restore_before)
        mark_mini_session_operation
        invalidate_mini_import_caches(model: false, excel: false, table: true, refresh_state: true) if respond_to?(:invalidate_mini_import_caches)
        reset_mini_import_refresh_state(true) if respond_to?(:reset_mini_import_refresh_state)
        refresh_import_mini_dialog(true, false) if respond_to?(:refresh_import_mini_dialog)
      rescue => e
        mini_import_abort_with_message(e)
      end
    }
  end

  def self.register_mini_import_item_callback_unmatch
    @mini_dlg.add_action_callback("unmatch_item") { |_, product_code, kind, model_name, target_name, spec|
      begin
        product = mini_action_product(product_code)
        kind = kind.to_s.empty? ? "PK" : kind.to_s
        model_name = model_name.to_s.strip
        target_name = target_name.to_s.strip
        spec = spec.to_s.strip
        raise "Thiếu tên để unmatch." if model_name.empty?

        removed = respond_to?(:remove_mini_accept) ? remove_mini_accept(product, kind, model_name, target_name, spec, "manual_match") : 0
        save_history("Mini Import unmatch", "Mã SP: #{product}, #{model_name} x Excel: #{target_name}") rescue nil if removed.to_i > 0
        invalidate_mini_import_caches(model: false, excel: false, table: true, refresh_state: true) if respond_to?(:invalidate_mini_import_caches)
        reset_mini_import_refresh_state(true) if respond_to?(:reset_mini_import_refresh_state)
        refresh_import_mini_dialog(true, false) if respond_to?(:refresh_import_mini_dialog)
      rescue => e
        mini_import_abort_with_message(e)
      end
    }
  end

  def self.register_mini_import_item_callback_keep
    @mini_dlg.add_action_callback("keep_item") { |_, product_code, kind, old_name, new_name, spec|
      begin
        product = mini_action_product(product_code)
        restore_before = respond_to?(:mini_import_restore_before_state) ? mini_import_restore_before_state : (respond_to?(:current_restore_state) ? current_restore_state : nil)
        @model.start_operation("Mini Import Keep Model Name", true)
        record_mini_accept(product, kind, old_name, new_name, spec, "keep")
        save_history("Mini Import gi\u1EEF t\u00EAn", "M\u00E3 SP: #{product}, T\u00EAn model: #{old_name}, T\u00EAn Excel: #{new_name}") rescue nil
        @model.commit_operation
        record_restore_action("mini_keep", "Mini Import gi\u1EEF t\u00EAn", { product: product, kind: kind, old_name: old_name, name: new_name, spec: spec }, restore_before, current_restore_state) if restore_before && respond_to?(:record_restore_action)
        mark_mini_session_operation
        mini_import_refresh_after_status_change
      rescue => e
        respond_to?(:mini_import_abort_with_message) ? mini_import_abort_with_message(e) : UI.messagebox(e.message)
      end
    }
  end

  def self.register_mini_import_item_callback_apply_all
    @mini_dlg.add_action_callback("apply_all_status") { |_|
      begin
        restore_before = respond_to?(:mini_import_restore_before_state) ? mini_import_restore_before_state : (respond_to?(:current_restore_state) ? current_restore_state : nil)
        @model.start_operation("Mini Import Apply All", true)
        count = mini_apply_all_status
        @model.commit_operation
        record_restore_action("mini_apply_all", "Mini Import apply all", { count: count }, restore_before, current_restore_state) if count.to_i > 0 && restore_before && respond_to?(:record_restore_action)
        mark_mini_session_operation if count.to_i > 0
        save_history("Mini Import Apply All", "S\u1ED1 d\u00F2ng: #{count}") rescue nil
        if count.to_i > 0
          invalidate_mini_import_caches(model: true, excel: true) if respond_to?(:invalidate_mini_import_caches)
          finish_mini_change
        else
          refresh_import_mini_dialog(false, false)
        end
      rescue => e
        respond_to?(:mini_import_abort_with_message) ? mini_import_abort_with_message(e) : UI.messagebox(e.message)
      end
    }
  end

  # === mini_import_dialog_callbacks_items_select.rb ===
  # --- mini_import_dialog_callbacks_items_select.rb ---
# MH_Thongke - Mini Import dialog item callbacks (select/highlight).


  def self.register_mini_import_item_callback_select
    @mini_dlg.add_action_callback("select_item") { |_, product_code, hw_name, ids|
      @dialog_selecting = true
      product = mini_action_product(product_code)
      entries = mini_stat_entries_for_ids(ids)
      entries = mini_stat_entries_for_name(product, hw_name) if entries.empty? && !hw_name.to_s.empty?
      if entries && !entries.empty?
        sel_ents = entries.map { |p| p.is_a?(Array) ? (p[1] || p[0]) : p }
                          .compact
                          .uniq
                          .reject { |e| e.respond_to?(:deleted?) && e.deleted? }
        @model.selection.clear
        @model.selection.add(sel_ents) unless sel_ents.empty?
        @model.select_tool(HighlightTool.new(entries))
      end
      UI.start_timer(0.5, false) { @dialog_selecting = false }
    }
  end

  # === mini_import_dialog_callbacks_items_edit.rb ===
  # --- mini_import_dialog_callbacks_items_edit.rb ---
# MH_Thongke - Mini Import dialog item callbacks (edit/delete/note).


  def self.mini_import_restore_before_state
    respond_to?(:current_restore_state) ? current_restore_state : nil
  end

  def self.mini_import_record_restore_if_available(action, label, payload, restore_before)
    return unless restore_before && respond_to?(:record_restore_action)

    record_restore_action(action, label, payload, restore_before, current_restore_state)
  end

  def self.mini_import_abort_with_message(error)
    @model.abort_operation rescue nil
    UI.messagebox(error.message)
  end

  def self.mini_import_resolve_entities_for_name(product, name)
    entities = mini_entities_for_name(product, name)
    raise "Kh\u00F4ng t\u00ECm th\u1EA5y '#{name}' trong model" if entities.empty?
    entities
  end

  def self.mini_import_apply_name_to_entities(entities, new_name, metadata = {})
    entities.each do |ent|
      apply_import_entity_name(ent, new_name)
      ent.set_attribute("MH_Thongke", "last_modified", Time.now.strftime("%d/%m/%y %H:%M"))
      next if metadata.nil? || metadata.empty?

      if respond_to?(:record_entity_excel_match)
        excel_key = record_entity_excel_match(ent, metadata.merge(to_name: new_name))
        metadata = metadata.merge(excel_key: excel_key) if excel_key && !excel_key.to_s.empty?
      end
      if respond_to?(:record_entity_rename_history)
        record_entity_rename_history(ent, metadata[:old_name], new_name, metadata)
      end
    end
  end

  # Tìm các sibling entities (ABF hardware parts như hinge-part-b, minifix, side-drill)
  # thuộc cùng product và loại phần cứng nhưng có tên khác với old_name.
  # Điều này giúp đổi tên đồng loạt toàn bộ các part của cùng một loại phụ kiện, tránh sinh ra dòng trùng lặp.
  def self.mini_import_find_sibling_hardware_entities(product, old_name, primary_entities)
    # Xác định loại phần cứng của nhóm primary_entities
    is_hinge = false
    is_minifix = false
    is_side_drill = false
    
    primary_entities.each do |ent|
      next unless ent && !(ent.respond_to?(:deleted?) && ent.deleted?)
      is_hinge = true if ent.get_attribute("ABF", "is-hinge-part-b") || (respond_to?(:import_hardware_family) && import_hardware_family(ent.get_attribute("ABF", "setting-name") || ent.get_attribute("ABF", "statistical-name") || ent.name) == :hinge)
      is_minifix = true if ent.get_attribute("ABF", "is-minifix-part-a") || ent.get_attribute("ABF", "is-minifix-part-b")
      is_side_drill = true if ent.get_attribute("ABF", "is-side-drill")
    end
    
    return [] unless is_hinge || is_minifix || is_side_drill

    primary_ids = Set.new(primary_entities.map { |e| e.respond_to?(:entityID) ? e.entityID : nil }.compact)
    report = @current_report_items || []
    siblings = []
    
    report.each do |row|
      next unless row.is_a?(Hash)
      row_product = row[:actual_product] || row[:product]
      next unless mini_product_code_match?(row_product, product, mini_group_mode)
      row_name = row[:name].to_s
      next if row_name.empty?
      next if import_name_norm(row_name) == import_name_norm(old_name)

      live_stat_entries(row[:stat_entities]).each do |pair|
        ent = pair.is_a?(Array) ? pair[0] : pair
        next unless ent && !(ent.respond_to?(:deleted?) && ent.deleted?)
        ent_id = ent.respond_to?(:entityID) ? ent.entityID : nil
        next if ent_id.nil? || primary_ids.include?(ent_id)

        if is_hinge && (ent.get_attribute("ABF", "is-hinge-part-b") || (respond_to?(:import_hardware_family) && import_hardware_family(ent.get_attribute("ABF", "setting-name") || ent.get_attribute("ABF", "statistical-name") || ent.name) == :hinge))
          siblings << ent
        elsif is_minifix && (ent.get_attribute("ABF", "is-minifix-part-a") || ent.get_attribute("ABF", "is-minifix-part-b"))
          siblings << ent
        elsif is_side_drill && ent.get_attribute("ABF", "is-side-drill")
          siblings << ent
        end
      end
    end
    siblings.compact.uniq
  rescue => e
    puts "mini_import_find_sibling_hardware_entities error: #{e.class}: #{e.message}" rescue nil
    []
  end

  def self.mark_mini_model_name_change(product_code, old_name, new_name)
    product = product_code_exact(product_code) rescue product_code.to_s.strip.upcase
    old_text = old_name.to_s.strip
    new_text = new_name.to_s.strip
    return false if product.empty? || old_text.empty? || new_text.empty?

    @mini_changed_products_for_save ||= []
    @mini_changed_products_for_save << product unless @mini_changed_products_for_save.include?(product)

    @mini_recent_name_changes ||= []
    @mini_recent_name_changes << {
      product: product,
      old_name: old_text,
      new_name: new_text,
      at: Time.now.to_f
    }
    @mini_recent_name_changes = @mini_recent_name_changes.last(30)

    @mini_loaded_from_snapshot_cache = false
    @mini_data_dirty = true
    @mini_force_live_rows = true
    @mini_pk_model_name_match_cache = nil
    invalidate_mini_import_caches(model: true, excel: false) if respond_to?(:invalidate_mini_import_caches)
    true
  rescue => e
    puts "mark_mini_model_name_change error: #{e.class}: #{e.message}" rescue nil
    false
  end

  def self.refresh_mini_runtime_after_model_change(product_code = nil)
    product = product_code_exact(product_code) rescue product_code.to_s.strip.upcase
    @mini_changed_products_for_save ||= []
    product_valid = begin
      product_code_valid?(product)
    rescue
      product =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?\z/i
    end
    @mini_changed_products_for_save << product if product_valid && !@mini_changed_products_for_save.include?(product)
    @mini_loaded_from_snapshot_cache = false
    @mini_data_dirty = true
    @mini_force_live_rows = true
    @mini_pk_model_name_match_cache = nil
    invalidate_mini_import_caches(model: true, excel: true) if respond_to?(:invalidate_mini_import_caches)

    if respond_to?(:process_selection)
      process_selection
      @process_selection_base_sig = model_base_signature if respond_to?(:model_base_signature)
      @process_selection_sel_sig = selection_signature if respond_to?(:selection_signature)
      @process_selection_last_status = :mini_manual_live_scan
      @process_selection_last_at = Time.now.to_f
    end

    snap = respond_to?(:export_current_snapshot_from_current_cache) ? export_current_snapshot_from_current_cache : nil
    if snap
      @mini_data_dirty = false
      @mini_force_live_rows = false
      @mini_changed_products_for_save = []
      invalidate_mini_import_caches(model: true, excel: false) if respond_to?(:invalidate_mini_import_caches)
    end
    snap
  rescue => e
    puts "refresh_mini_runtime_after_model_change error: #{e.class}: #{e.message}" rescue nil
    nil
  end

  def self.register_mini_import_item_callback_update
    @mini_dlg.add_action_callback("update_item") { |_, product_code, old_name, new_name, spec|
      begin
        product = mini_action_product(product_code)
        restore_before = mini_import_restore_before_state
        entities = mini_import_resolve_entities_for_name(product, old_name)
        model_before = respond_to?(:restore_entity_snapshot) ? restore_entity_snapshot(entities) : []
        @model.start_operation("Update Ph\u1EE5 Ki\u1EC7n Mini Import", true)
        # The table already computed the intended target name. Re-running the
        # Hafele special rule here can re-add the spec and keep the old name.
        target_name = new_name.to_s.strip
        target_name = pk_preserve_dimension_for_update(old_name, target_name, spec) if respond_to?(:pk_preserve_dimension_for_update)
        mini_import_apply_name_to_entities(entities, target_name, {
          product: product,
          kind: "PK",
          old_name: old_name,
          target_name: target_name,
          excel_name: target_name,
          spec: spec,
          source: "mini_import",
          action: "update"
        })
        
        # Cập nhật đồng thời các sibling entities khác tên nhưng cùng hardware family
        sibling_entities = mini_import_find_sibling_hardware_entities(product, old_name, entities)
        unless sibling_entities.empty?
          sibling_old_names = sibling_entities.map { |e| (e.get_attribute("ABF", "setting-name") || e.get_attribute("ABF", "statistical-name") || e.name).to_s }.uniq
          mini_import_apply_name_to_entities(sibling_entities, target_name, {
            product: product,
            kind: "PK",
            old_name: sibling_old_names.first || old_name,
            target_name: target_name,
            excel_name: target_name,
            spec: spec,
            source: "mini_import",
            action: "update_sibling"
          })
          sibling_old_names.each { |sn| mark_mini_model_name_change(product, sn, target_name) }
        end

        mark_mini_model_name_change(product, old_name, target_name)
        save_history("Mini Import update ph\u1EE5 ki\u1EC7n","M\u00E3 SP: #{product}, #{old_name} -> #{target_name}")
        record_mini_accept(product, "PK", old_name, target_name, spec, "update")
        @model.commit_operation
        mini_import_record_restore_if_available("mini_update", "Mini Import update t\u00EAn", { product: product, kind: "PK", old_name: old_name, name: target_name, spec: spec, model_before: model_before }, restore_before)
        refresh_mini_runtime_after_model_change(product)
        mark_mini_session_operation
        finish_mini_change
      rescue => e
        mini_import_abort_with_message(e)
      end
    }
  end

  def self.register_mini_import_item_callback_rename
    @mini_dlg.add_action_callback("rename_item") { |_, product_code, old_name, new_name, target_name = "", spec = "", kind = "PK"|
      begin
        product = mini_action_product(product_code)
        restore_before = mini_import_restore_before_state
        new_name = new_name.to_s.strip
        target_name = target_name.to_s.strip
        spec = spec.to_s.strip
        kind = kind.to_s.empty? ? "PK" : kind.to_s
        raise "T\u00EAn m\u1EDBi r\u1ED7ng" if new_name.empty?
        entities = mini_import_resolve_entities_for_name(product, old_name)
        model_before = respond_to?(:restore_entity_snapshot) ? restore_entity_snapshot(entities) : []
        @model.start_operation("S\u1EEDa T\u00EAn Ph\u1EE5 Ki\u1EC7n Mini Import", true)
        mini_import_apply_name_to_entities(entities, new_name, {
          product: product,
          kind: kind,
          old_name: old_name,
          target_name: target_name,
          excel_name: target_name.empty? ? new_name : target_name,
          spec: spec,
          source: "mini_import",
          action: "rename"
        })

        # Cập nhật đồng thời các sibling entities khác tên nhưng cùng hardware family
        sibling_entities = mini_import_find_sibling_hardware_entities(product, old_name, entities)
        unless sibling_entities.empty?
          sibling_old_names = sibling_entities.map { |e| (e.get_attribute("ABF", "setting-name") || e.get_attribute("ABF", "statistical-name") || e.name).to_s }.uniq
          mini_import_apply_name_to_entities(sibling_entities, new_name, {
            product: product,
            kind: kind,
            old_name: sibling_old_names.first || old_name,
            target_name: target_name,
            excel_name: target_name.empty? ? new_name : target_name,
            spec: spec,
            source: "mini_import",
            action: "rename_sibling"
          })
          sibling_old_names.each { |sn| mark_mini_model_name_change(product, sn, new_name) }
        end

        mark_mini_model_name_change(product, old_name, new_name)
        save_history("Mini Import s\u1EEDa t\u00EAn","M\u00E3 SP: #{product}, #{old_name} -> #{new_name}")
        record_mini_name_lineage(product, kind, old_name, new_name, spec, "rename", "manual_rename") if respond_to?(:record_mini_name_lineage)
        record_mini_accept(product, kind, new_name, target_name, spec, "rename_update") unless target_name.empty?
        @model.commit_operation
        mini_import_record_restore_if_available("mini_rename", "Mini Import s\u1EEDa t\u00EAn", { product: product, kind: kind, old_name: old_name, name: new_name, target: target_name, spec: spec, model_before: model_before }, restore_before)
        refresh_mini_runtime_after_model_change(product)
        mark_mini_session_operation
        finish_mini_change
      rescue => e
        mini_import_abort_with_message(e)
      end
    }
  end

  def self.register_mini_import_item_callback_set_note
    @mini_dlg.add_action_callback("set_note") { |_, product_code, kind, hw_name, spec, note|
      begin
        product = mini_action_product(product_code)
        update_import_excel_note(product, kind, hw_name, spec, note)
        if respond_to?(:refresh_import_related_views)
          refresh_import_related_views(false, false, false)
        else
          refresh_import_material_hud(false, false) if respond_to?(:material_hud_visible?) && material_hud_visible?
        end
      rescue => e
        UI.messagebox(e.message)
      end
    }
  end

  def self.register_mini_import_item_callback_remove_excel
    @mini_dlg.add_action_callback("remove_excel_item") { |_, product_code, kind, hw_name, spec|
      begin
        product = mini_action_product(product_code)
        restore_before = mini_import_restore_before_state
        removed = remove_import_excel_item(product, kind, hw_name, spec)
        raise "Khong tim thay dong de xoa" if removed.to_i <= 0
        mini_import_record_restore_if_available("mini_hide_excel", "\u1EA8n d\u00F2ng Excel", { product: product, kind: kind, name: hw_name, spec: spec }, restore_before)
        finish_mini_change
      rescue => e
        UI.messagebox(e.message)
      end
    }
  end

  def self.register_mini_import_item_callback_delete
    @mini_dlg.add_action_callback("delete_item") { |_, product_code, hw_name, ids|
      begin
        product = mini_action_product(product_code)
        restore_before = mini_import_restore_before_state
        entities = entities_by_ids(ids)
        entities = mini_entities_for_name(product, hw_name) if entities.empty?
        raise "Kh\u00F4ng t\u00ECm th\u1EA5y '#{hw_name}' trong model" if entities.empty?
        @model.start_operation("X\u00F3a Ph\u1EE5 Ki\u1EC7n Mini Import", true)
        erase_mini_entities(entities)
        record_hidden_import_excel_item(product, "PK", hw_name, "") if respond_to?(:record_hidden_import_excel_item)
        save_history("Mini Import x\u00F3a ph\u1EE5 ki\u1EC7n","M\u00E3 SP: #{product}, PK: #{hw_name}")
        @model.commit_operation
        mini_import_record_restore_if_available("mini_delete_item", "Mini Import x\u00F3a PK", { product: product, kind: "PK", name: hw_name, ids: ids, note: "Geometry \u0111\u00E3 x\u00F3a th\u1EADt; restore ch\u1EC9 kh\u00F4i ph\u1EE5c rule/\u1EA9n." }, restore_before)
        mark_mini_session_operation
        finish_mini_change
      rescue => e
        mini_import_abort_with_message(e)
      end
    }
  end

  # === mini_import_dialog_callbacks_items.rb ===
  # --- mini_import_dialog_callbacks_items.rb ---
# MH_Thongke - Mini Import dialog item callback registry.


  def self.register_mini_import_dialog_item_callbacks
    register_mini_import_item_callback_accept
    register_mini_import_item_callback_manual_match
    register_mini_import_item_callback_unmatch
    register_mini_import_item_callback_keep
    register_mini_import_item_callback_apply_all
    register_mini_import_item_callback_select
    register_mini_import_item_callback_update
    register_mini_import_item_callback_rename
    register_mini_import_item_callback_set_note
    register_mini_import_item_callback_remove_excel
    register_mini_import_item_callback_delete
  end

  # === mini_import_dialog_callbacks.rb ===
  # --- mini_import_dialog_callbacks.rb ---
# MH_Thongke - Mini Import dialog callbacks.


  def self.register_mini_import_dialog_callbacks
    register_mini_import_dialog_core_callbacks
    register_mini_import_dialog_item_callbacks
  end
end

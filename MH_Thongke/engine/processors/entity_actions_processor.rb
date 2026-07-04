# encoding: utf-8
# MH_Thongke — entity actions processor
# Logic xử lý dùng chung cho Mini Import và các bảng thống kê.
module MH_Thongke

  # === mini_import_entity_lookup.rb ===
  # --- mini_import_entity_lookup.rb ---
# MH_Thongke - Mini Import entity lookup and matching helpers.


  def self.sync_mini_product_from_selection(allow_slow_scan = false, force: false)
    mini_visible = respond_to?(:mini_dialog_visible?) && mini_dialog_visible?
    hud_visible = respond_to?(:material_hud_visible?) && material_hud_visible?
    return false unless force || mini_visible || hud_visible
    return false if @mini_product_lock_until && Time.now.to_f < @mini_product_lock_until.to_f

    before = current_mini_products
    if respond_to?(:sync_mini_products_from_active_source)
      sync_mini_products_from_active_source(false, allow_slow_scan)
    else
      new_products = mini_context_product_codes(allow_slow_scan)
      set_mini_products(new_products) unless new_products.empty?
    end
    changed = current_mini_products != before
    if changed
      @mini_last_refresh_state_sig = nil
      @mini_last_table_key = nil
      @mini_table_html_cache = nil
      @mini_product_block_cache = nil
    end
    changed
  end

  def self.mini_stat_entries_for_name(product_code, name, mode = mini_group_mode, section = nil)
    target_norm = import_name_norm(name)
    section_norm = import_section_norm(section)
    rows = ((@current_report_items || []) + (@current_mat_items || [])).select do |row|
      next false if row[:is_missing]
      [row[:actual_product], row[:product]].any? { |p| mini_product_code_match?(p, product_code, mode) } &&
        import_name_norm(row[:name]) == target_norm &&
        (section_norm.empty? || import_section_norm(row[:ten_sp]) == section_norm)
    end
    rows.flat_map { |row| live_stat_entries(row[:stat_entities]) }.compact
  end

  def self.mini_entities_for_name(product_code, name, section = nil)
    mini_stat_entries_for_name(product_code, name, mini_group_mode, section)
      .map { |pair| pair.is_a?(Array) ? pair[0] : pair }
      .compact
      .uniq
      .reject { |e| e.respond_to?(:deleted?) && e.deleted? }
  end

  def self.mini_stat_entries_for_ids(ids)
    wanted = ids.to_s.split(",").map { |v| v.to_i }.reject(&:zero?)
    return [] if wanted.empty?
    items = (@current_report_items || []) + (@current_mat_items || [])
    items.flat_map { |row| live_stat_entries(row[:stat_entities]) }
      .select { |pair| ent = pair.is_a?(Array) ? pair[0] : pair; wanted.include?(ent.entityID) rescue false }
      .compact
      .uniq
  end

  def self.selected_import_roots
    roots = []
    active_path = @model.active_path || []
    active_path.reverse_each do |e|
      roots << e if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    end
    @model.selection.to_a.each do |e|
      roots << e if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    end
    roots.compact.uniq.reject { |e| e.respond_to?(:deleted?) && e.deleted? }
  end

  def self.selected_import_object_count(product_code = nil)
    @model ||= Sketchup.active_model
    selected = @model.selection.to_a.select do |e|
      next false unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      next false unless import_placeable_root?(e)

      codes = entity_product_codes(e)
      product_code.to_s.strip.empty? || codes.empty? || codes.any? { |code| mini_product_code_match?(code, product_code, mini_group_mode) }
    end
    selected.uniq.size
  rescue
    0
  end

  def self.live_entity?(entity)
    entity && !(entity.respond_to?(:deleted?) && entity.deleted?)
  rescue
    false
  end

  def self.live_stat_entries(entries)
    Array(entries).select do |pair|
      ent = pair.is_a?(Array) ? pair[0] : pair
      live_entity?(ent)
    end
  end

  def self.live_row_entries(row)
    stat_entries = live_stat_entries(row[:stat_entities])
    return stat_entries unless stat_entries.empty?

    # Auto-generated rows (e.g. Thanh nhom LED, Nguon LED) may only
    # carry references in :entities.
    live_stat_entries(row[:entities])
  end

  def self.entity_product_codes(entity)
    text = "#{entity.respond_to?(:name) ? entity.name : ''} #{entity.respond_to?(:definition) && entity.definition ? entity.definition.name : ''}"
    respond_to?(:product_codes_from_text) ? product_codes_from_text(text) : text.scan(/[A-Z]+\d+[A-Z]?(?:\.\d+)?/i).map(&:upcase).uniq
  rescue
    []
  end

  def self.entity_product_match?(entity, product_code)
    codes = entity_product_codes(entity)
    return true if codes.empty?
    codes.any? { |code| mini_product_code_match?(code, product_code, mini_group_mode) }
  end

  def self.import_placeable_root?(entity)
    live_entity?(entity) && !pk_marker_entity?(entity)
  rescue
    false
  end

  # === mini_import_entity_naming.rb ===
  # --- mini_import_entity_naming.rb ---
# MH_Thongke - Mini Import entity naming helpers.


  def self.import_entity_name_attr(entity)
    return ["ABF", "statistical-name"] unless entity

    if entity.get_attribute("ABF", "is-minifix-part-a") ||
       entity.get_attribute("ABF", "is-minifix-part-b") ||
       entity.get_attribute("ABF", "is-hinge-part-b") ||
       entity.get_attribute("ABF", "is-side-drill")
      return ["ABF", "setting-name"]
    end

    if entity.get_attribute("ZSU_LED", "ten_hien_thi")
      return ["ZSU_LED", "ten_hien_thi"]
    end

    if entity.get_attribute("ABF", "statistical-type").to_s == "length_measuring"
      return ["ABF", entity.get_attribute("ABF", "statistical-name") ? "statistical-name" : "setting-name"]
    end

    return ["ABF", "setting-name"] if entity.get_attribute("ABF", "is-intersect").to_s == "true"
    ["ABF", "statistical-name"]
  end

  def self.apply_import_entity_name(entity, new_name, dict = nil, key = nil)
    return if entity.nil? || (entity.respond_to?(:deleted?) && entity.deleted?)

    value = fix_vietnamese_mojibake(new_name).strip
    return if value.empty?

    attr_dict, attr_key = dict.to_s.strip, key.to_s.strip
    if attr_dict.empty? || attr_key.empty?
      attr_dict, attr_key = import_entity_name_attr(entity)
    end

    old_attr = entity.get_attribute(attr_dict, attr_key).to_s.strip
    old_name = entity.name.to_s.strip if entity.respond_to?(:name)

    entity.set_attribute(attr_dict, attr_key, value)
    entity.definition.set_attribute(attr_dict, attr_key, value) if entity.respond_to?(:definition)

    same_hardware_family = lambda do |other|
      left = import_hardware_family(other)
      right = import_hardware_family(value)
      left && right && left == right
    rescue
      false
    end

    if attr_dict == "ABF"
      if attr_key == "setting-name"
        stat = entity.get_attribute("ABF", "statistical-name").to_s.strip
        if stat.empty? || import_name_norm(stat) == import_name_norm(old_attr) || import_name_norm(stat) == import_name_norm(old_name) || same_hardware_family.call(stat)
          entity.set_attribute("ABF", "statistical-name", value)
          entity.definition.set_attribute("ABF", "statistical-name", value) if entity.respond_to?(:definition)
        end
      elsif attr_key == "statistical-name"
        setting = entity.get_attribute("ABF", "setting-name").to_s.strip
        if setting.empty? || import_name_norm(setting) == import_name_norm(old_attr) || import_name_norm(setting) == import_name_norm(old_name) || same_hardware_family.call(setting)
          entity.set_attribute("ABF", "setting-name", value)
          entity.definition.set_attribute("ABF", "setting-name", value) if entity.respond_to?(:definition)
        end
      end
    end

    scan_dict, scan_key = import_entity_name_attr(entity)
    if scan_dict.to_s == "ABF" && scan_key.to_s != attr_key.to_s
      scan_value = entity.get_attribute(scan_dict, scan_key).to_s.strip
      if scan_value.empty? || import_name_norm(scan_value) == import_name_norm(old_attr) || import_name_norm(scan_value) == import_name_norm(old_name) || same_hardware_family.call(scan_value)
        entity.set_attribute(scan_dict, scan_key, value)
        entity.definition.set_attribute(scan_dict, scan_key, value) if entity.respond_to?(:definition)
      end
    end

    if entity.respond_to?(:name=) && (old_name.to_s.empty? || import_name_norm(old_name) == import_name_norm(old_attr) || import_hardware_family(old_name))
      entity.name = value
    end
  end

  # === mini_import_entity_actions.rb ===
  # --- mini_import_entity_actions.rb ---
# MH_Thongke - Mini Import entity actions and target selection.


  def self.erase_mini_entities(entities)
    live = entities.compact.uniq.reject { |e| e.respond_to?(:deleted?) && e.deleted? }
    erased = 0
    errors = []
    live.each do |ent|
      begin
        if ent.respond_to?(:erase!)
          ent.erase!
          erased += 1
          next
        end

        parent = ent.respond_to?(:parent) ? ent.parent : nil
        collection =
          if parent.respond_to?(:erase_entities)
            parent
          elsif parent.respond_to?(:entities) && parent.entities.respond_to?(:erase_entities)
            parent.entities
          end
        if collection
          collection.erase_entities([ent])
          erased += 1
        end
      rescue => e
        errors << "#{ent.respond_to?(:entityID) ? ent.entityID : '?'}: #{e.message}"
      end
    end
    raise "Khong xoa duoc phu kien: #{errors.first || 'khong co entity hop le'}" if erased.zero? && !live.empty?
    erased
  end

  def self.entities_by_ids(ids)
    wanted = ids.to_s.split(",").map { |v| v.to_i }.reject(&:zero?)
    return [] if wanted.empty?
    found = []
    finder = lambda do |entities|
      entities.each do |e|
        found << e if wanted.include?(e.entityID) rescue nil
        child = import_target_entities(e) if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        finder.call(child) if child
      end
    end
    finder.call(Sketchup.active_model.entities)
    found.uniq.reject { |e| e.respond_to?(:deleted?) && e.deleted? }
  end

  # === mini_import_entity_core.rb ===
  # --- mini_import_entity_core.rb ---
# MH_Thongke - Mini Import entity core entrypoint.
#
# Logic is split into:
# - mini_import_entity_lookup.rb
# - mini_import_entity_naming.rb
# - mini_import_entity_actions.rb

  # === mini_import_target_utils.rb ===
  # --- mini_import_target_utils.rb ---
# MH_Thongke - Mini Import target transform and section utilities.


  def self.entity_world_transform(target)
    return Geom::Transformation.new unless target
    found = nil
    visited = {}
    finder = lambda do |entities, parent_tr|
      return if found || !entities
      entities.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        tr = parent_tr * e.transformation
        if e == target
          found = tr
          return
        end
        child = import_target_entities(e)
        next unless child
        key = child.object_id
        next if visited[key]
        visited[key] = true
        finder.call(child, tr)
        return if found
      end
    end
    finder.call(@model.entities, Geom::Transformation.new)
    found || (target.respond_to?(:transformation) ? target.transformation : Geom::Transformation.new)
  rescue
    Geom::Transformation.new
  end

  def self.normalize_transform_axes(tr)
    x_axis = tr.xaxis
    y_axis = tr.yaxis
    return tr if x_axis.length <= 0 || y_axis.length <= 0
    x_axis.length = 1.0
    y_axis.length = 1.0
    z_axis = x_axis.cross(y_axis)
    return tr if z_axis.length <= 0
    z_axis.length = 1.0
    y_axis = z_axis.cross(x_axis)
    y_axis.length = 1.0 if y_axis.length > 0
    Geom::Transformation.axes(tr.origin, x_axis, y_axis, z_axis)
  rescue
    tr
  end

  def self.unscaled_local_transform(local_tr, container_tr)
    world_tr = container_tr * local_tr
    world_unscaled = normalize_transform_axes(world_tr)
    container_tr.inverse * world_unscaled
  rescue
    local_tr
  end

  def self.prepare_import_target(target, root = nil, section_text = nil)
    return nil unless live_entity?(target)
    world_tr = entity_world_transform(target)
    target.make_unique if target.is_a?(Sketchup::ComponentInstance) && target.respond_to?(:make_unique)
    ents = import_target_entities(target)
    return nil unless ents
    face_tr = largest_face_transform(ents)
    {
      ents: ents,
      face_tr: face_tr || Geom::Transformation.new,
      target: target,
      root: root || target,
      section_text: section_text.to_s.empty? ? import_target_section_text(target, root) : section_text.to_s,
      on_panel_face: !!face_tr,
      container_tr: world_tr
    }
  rescue
    nil
  end

  def self.import_section_norm(value)
    import_name_norm(strip_product_code_prefix(fix_vietnamese_mojibake(value).to_s).strip)
  rescue
    import_name_norm(value)
  end

  def self.import_target_section_text(target, root = nil)
    parts = []
    [root, target].compact.uniq.each { |entity| parts.concat(import_target_text_parts_for_entity(entity)) }
    parts.concat(import_target_child_section_parts(target))
    parts.map { |v| fix_vietnamese_mojibake(v).to_s.strip }.reject(&:empty?).uniq.join(" ")
  rescue
    ""
  end

  def self.import_target_section_match?(target, section, root = nil, section_text = nil)
    wanted = import_section_norm(section)
    return true if wanted.empty?

    source = section_text.to_s.empty? ? import_target_section_text(target, root) : section_text.to_s
    text = import_section_norm(source)
    return false if text.empty?
    text.include?(wanted) || wanted.include?(text)
  rescue
    false
  end

  def self.filter_import_roots_by_section(roots, section)
    roots = Array(roots).compact.uniq
    return roots if import_section_filter_empty?(section)

    matched = roots.select { |root| import_target_section_match?(root, section, root) }
    matched.empty? ? roots : matched
  rescue
    roots
  end

  def self.filter_import_descs_by_section(descs, section)
    descs = Array(descs).compact
    return descs if import_section_filter_empty?(section)

    matched = descs.select { |desc| import_target_section_match?(desc[:target], section, desc[:root], desc[:section_text]) }
    matched.empty? ? descs : matched
  rescue
    descs
  end

  def self.import_target_text_parts_for_entity(entity)
    return [] unless entity

    parts = []
    parts << entity.get_attribute("MH_Thongke", "ten_sp").to_s if entity.respond_to?(:get_attribute)
    parts << entity.name.to_s if entity.respond_to?(:name)
    parts << entity.definition.name.to_s if entity.respond_to?(:definition) && entity.definition
    parts
  rescue
    []
  end

  def self.import_target_child_section_parts(target)
    child = import_target_entities(target)
    return [] unless child

    parts = []
    child.each do |entity|
      next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      parts.concat(import_target_text_parts_for_entity(entity))
    end
    parts
  rescue
    []
  end

  def self.import_section_filter_empty?(section)
    import_section_norm(section).empty?
  rescue
    true
  end

  # === mini_import_entities.rb ===
  # --- mini_import_entities.rb ---
# MH_Thongke - import target transforms and panel candidates.


  def self.preferred_import_panel_in_root(root)
    return nil unless live_entity?(root)
    priorities = [
      ["day"],
      ["hong trai", "hongtrai"],
      ["hong phai", "hongphai"]
    ]
    priorities.each do |patterns|
      text = import_name_norm("#{root.name} #{root.respond_to?(:definition) ? root.definition.name : ''}")
      return root if patterns.any? { |pattern| text.include?(pattern) }
      child = import_target_entities(root)
      found = find_panel_by_name_patterns(child, patterns) if child
      return found if found
    end
    nil
  end

  def self.import_panel_priority(entity)
    text = import_name_norm("#{entity.respond_to?(:name) ? entity.name : ''} #{entity.respond_to?(:definition) ? entity.definition.name : ''}")
    return 0 if text.include?("day")
    return 1 if text.include?("hong trai") || text.include?("hongtrai")
    return 2 if text.include?("hong phai") || text.include?("hongphai")
    9
  rescue
    9
  end

  def self.sort_import_target_descs(candidates)
    Array(candidates).compact.sort_by do |desc|
      target = desc[:target]
      [
        import_panel_priority(target),
        (target.respond_to?(:entityID) ? target.entityID.to_i : 0)
      ]
    end
  end

  def self.import_child_container(child_entity)
    return nil unless live_entity?(child_entity)

    visited = {}
    finder = lambda do |entities|
      return nil unless entities

      entities.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        child = import_target_entities(e)
        next unless child
        return e if child.to_a.include?(child_entity)

        key = child.object_id
        next if visited[key]
        visited[key] = true
        found = finder.call(child)
        return found if found
      end
      nil
    end
    finder.call(@model.entities)
  rescue
    nil
  end

  # === mini_import_panel_candidates_search.rb ===
  # --- mini_import_panel_candidates_search.rb ---
# MH_Thongke - Mini Import panel candidate search helpers.


  def self.panel_name_patterns_priority
    [
      ["day"],
      ["hong trai", "hongtrai"],
      ["hong phai", "hongphai"]
    ]
  end

  def self.panel_entity_text_norm(entity)
    import_name_norm("#{entity.name} #{entity.respond_to?(:definition) ? entity.definition.name : ''}")
  rescue
    ""
  end

  def self.find_import_panel(product_code)
    code = product_code_exact(product_code)
    base = product_code_base(code)
    wanted_groups = [
      ["#{code}_day", "#{code} day"],
      ["#{code}_noc", "#{code} noc"],
      ["#{base}_day", "#{base} day"],
      ["#{base}_noc", "#{base} noc"]
    ]

    roots = selected_import_roots
    roots.each do |root|
      root_text = panel_entity_text_norm(root)
      wanted_groups.each do |wanted|
        return root if wanted.any? { |key| root_text.include?(key) }
        child = import_target_entities(root)
        panel = find_panel_by_name_patterns(child, wanted) if child
        return panel if panel
      end
    end
    return nil unless roots.empty?

    wanted_groups.each do |wanted|
      panel = find_panel_by_name_patterns(@model.entities, wanted)
      return panel if panel
    end
    nil
  end

  def self.find_preferred_import_panel(product_code)
    target = find_import_target(product_code)
    roots = selected_import_roots
    roots << target if target
    roots = roots.compact.uniq.reject { |e| e.respond_to?(:deleted?) && e.deleted? }
    search_spaces = roots.empty? ? [@model.entities] : roots.map { |root| import_target_entities(root) }.compact

    panel_name_patterns_priority.each do |patterns|
      roots.each do |root|
        return root if patterns.any? { |pattern| panel_entity_text_norm(root).include?(pattern) }
      end
      search_spaces.each do |entities|
        found = find_panel_by_name_patterns(entities, patterns)
        return found if found
      end
    end
    nil
  end

  def self.collect_panels_by_name_patterns(entities, patterns, found = [])
    return found unless entities
    entities.each do |e|
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      found << e if patterns.any? { |pattern| panel_entity_text_norm(e).include?(pattern) }
      child = import_target_entities(e)
      collect_panels_by_name_patterns(child, patterns, found) if child
    end
    found
  end

  def self.find_panel_by_name_patterns(entities, patterns)
    return nil unless entities
    entities.each do |e|
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      return e if patterns.any? { |pattern| panel_entity_text_norm(e).include?(pattern) }
      child = import_target_entities(e)
      found = find_panel_by_name_patterns(child, patterns) if child
      return found if found
    end
    nil
  end

  # === mini_import_panel_candidates_descs.rb ===
  # --- mini_import_panel_candidates_descs.rb ---
# MH_Thongke - Mini Import panel descriptor collection helpers.


  def self.preferred_import_panel_descs_for_product(product_code, section = nil)
    code = product_code_exact(product_code)
    base = product_code_base(code)
    roots = []
    roots.concat(selected_import_roots)
    if @prod_groups.nil? || @prod_groups.empty?
      respond_to?(:process_selection_cached) ? process_selection_cached(false) : process_selection
    end
    [code, base].reject(&:empty?).uniq.each { |key| roots.concat(@prod_groups[key] || []) }
    target = find_import_target(product_code)
    roots << target if target
    roots = roots.compact.uniq.select { |root| import_placeable_root?(root) }
    coded_roots = roots.select { |root| entity_product_codes(root).any? && entity_product_match?(root, product_code) }
    roots = coded_roots.empty? ? roots.select { |root| entity_product_match?(root, product_code) } : coded_roots

    panel_name_patterns_priority.each do |patterns|
      found = []
      roots.each do |root|
        collect_panel_descs_by_name_patterns(root, patterns, section, found, root, [])
      end
      found = sort_import_target_descs(unique_import_target_descs(found))
      return found unless found.empty?
    end
    []
  rescue
    []
  end

  def self.preferred_import_panels_for_product(product_code, section = nil)
    preferred_import_panel_descs_for_product(product_code, section).map { |desc| desc[:target] }.compact
  rescue
    []
  end

  def self.collect_panel_descs_by_name_patterns(entity, patterns, section, found = [], root = nil, path_parts = [])
    return found unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

    current_text = [
      entity.get_attribute("MH_Thongke", "ten_sp").to_s,
      entity.name.to_s,
      (entity.respond_to?(:definition) && entity.definition ? entity.definition.name.to_s : "")
    ].reject(&:empty?).join(" ")
    path_text = (path_parts + [current_text]).reject(&:empty?).join(" ")
    norm_text = import_name_norm(current_text)
    if patterns.any? { |pattern| norm_text.include?(pattern) } &&
       import_target_section_match?(entity, section, root || entity, path_text)
      desc = prepare_import_target(entity, root || entity, path_text)
      found << desc if desc && desc[:on_panel_face]
    end

    child = import_target_entities(entity)
    if child
      child.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        collect_panel_descs_by_name_patterns(e, patterns, section, found, root || entity, path_parts + [current_text])
      end
    end
    found
  rescue
    found
  end

  # === mini_import_panel_candidates.rb ===
  # --- mini_import_panel_candidates.rb ---
# MH_Thongke - Mini Import panel candidate discovery entrypoint.
#
# Logic is split into:
# - mini_import_panel_candidates_search.rb
# - mini_import_panel_candidates_descs.rb
end


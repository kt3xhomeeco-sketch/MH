# encoding: utf-8
# MH_Thongke — product context processor
# Logic xử lý dùng chung cho Mini Import và các bảng thống kê.
module MH_Thongke

  # === mini_import_context_codes.rb ===
  # --- mini_import_context_codes.rb ---
# MH_Thongke - product code helpers for Mini Import context.


  def self.product_code_base(code)
    if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:base)
      MH::ProductContext.base(code)
    else
      code.to_s.strip.split('.').first.to_s.upcase
    end
  end

  def self.product_code_exact(code)
    if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:exact)
      MH::ProductContext.exact(code)
    else
      code.to_s.strip.upcase
    end
  end

  def self.product_code_valid?(code)
    if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:valid?)
      MH::ProductContext.valid?(code)
    else
      value = product_code_exact(code)
      !value.empty? && value != "--" && value =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?\z/i
    end
  rescue
    false
  end

  def self.product_codes_from_text(text)
    if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:scan_products)
      return MH::NameGrammar.scan_products(text.to_s).map { |code| product_code_exact(code) }.select { |code| product_code_valid?(code) }.uniq
    end

    text.to_s.scan(/[A-Z]+\d+[A-Z]?(?:\.\d+)?/i).map { |code| product_code_exact(code) }.select { |code| product_code_valid?(code) }.uniq
  rescue
    []
  end

  def self.product_code_module?(code)
    product_code_exact(code).include?(".")
  end

  def self.mini_product_code_match?(value, target, mode = mini_group_mode)
    v = product_code_exact(value)
    t = product_code_exact(target)
    return false if v.empty? || t.empty? || v == "--"
    return product_code_base(v) == product_code_base(t) if mode.to_s == "product" || !product_code_module?(t)

    v == t || (!product_code_module?(v) && product_code_base(v) == product_code_base(t))
  end

  def self.product_code_sort_key(code)
    code.to_s.split(/(\d+)/).map { |s| s =~ /\d/ ? [1, s.to_i] : [0, s.downcase] }
  end

  def self.product_code_from_entity(entity)
    if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:code_from_entity)
      code = MH::ProductContext.code_from_entity(entity)
      return product_code_exact(code) if product_code_valid?(code)
    end

    text = entity.respond_to?(:name) ? entity.name.to_s : ""
    text += " #{entity.definition.name}" if entity.respond_to?(:definition) && entity.definition
    product_codes_from_text(text).first
  rescue
    nil
  end

  # === mini_import_context_modes.rb ===
  # --- mini_import_context_modes.rb ---
# MH_Thongke - source/mode state for Mini Import context.


  def self.mini_group_mode
    @mini_group_mode.to_s == "module" ? "module" : "product"
  end

  def self.set_mini_group_mode(mode)
    @mini_group_mode = mode.to_s == "module" ? "module" : "product"
  end

  def self.mini_product_mode?
    mini_group_mode == "product"
  end

  def self.mini_product_source_mode
    if @mini_product_source_mode.to_s.empty?
      @model ||= Sketchup.active_model
      raw = @model.get_attribute("MH_Thongke", "mini_source_mode").to_s rescue ""
      @mini_product_source_mode = raw == "select" ? "select" : "view"
    end
    @mini_product_source_mode == "select" ? "select" : "view"
  end

  def self.set_mini_product_source_mode(mode)
    @mini_product_source_mode = mode.to_s == "select" ? "select" : "view"
    @model ||= Sketchup.active_model
    @model.set_attribute("MH_Thongke", "mini_source_mode", @mini_product_source_mode) rescue nil
    @mini_product_source_mode
  end

  # === mini_import_context_targets.rb ===
  # --- mini_import_context_targets.rb ---
# MH_Thongke - target lookup utilities for Mini Import context.


  def self.import_target_entities(target)
    return nil unless target
    target.is_a?(Sketchup::Group) ? target.entities : target.definition.entities
  rescue
    nil
  end

  def self.find_import_target(product_code)
    code = product_code.to_s.strip
    base = product_code_base(code)
    keys = [code, base].reject(&:empty?).uniq

    if @prod_groups.nil? || @prod_groups.empty?
      respond_to?(:process_selection_cached) ? process_selection_cached(false) : process_selection
    end

    keys.each do |key|
      target = (@prod_groups[key] || []).find { |e| e && !e.deleted? rescue false }
      return target if target
    end

    selected = @model.selection.to_a.find do |e|
      next false unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      text = "#{e.name} #{e.respond_to?(:definition) ? e.definition.name : ''}"
      keys.any? { |key| text.include?(key) }
    end
    return selected if selected

    finder = lambda do |entities|
      entities.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        text = "#{e.name} #{e.respond_to?(:definition) ? e.definition.name : ''}"
        return e if keys.any? { |key| text.include?(key) }
        child = import_target_entities(e)
        found = finder.call(child) if child
        return found if found
      end
      nil
    end
    finder.call(@model.entities)
  end

  def self.find_import_library_item(hw_name, spec = nil)
    nil
  end

  def self.import_pk_marker_shape(hw_name, spec = nil)
    norm = import_name_norm([hw_name, spec].compact.join(" "))
    return "circle" if norm =~ /(ban le|hinge|minifix|bas|oc|vit)/
    return "square" if norm =~ /(ray|suot|led|nguon|tay nam|thanh)/
    "triangle"
  end

  def self.entity_layer_visible?(entity)
    layer = entity.layer rescue nil
    !layer || layer.visible?
  rescue
    true
  end

  # === mini_import_context_selection.rb ===
  # --- mini_import_context_selection.rb ---
# MH_Thongke - product selection/context sourcing.


  MINI_VIEW_SYNC_MIN_INTERVAL = 0.18 unless const_defined?(:MINI_VIEW_SYNC_MIN_INTERVAL)
  MINI_VIEW_SYNC_CACHE_MAX_AGE = 0.45 unless const_defined?(:MINI_VIEW_SYNC_CACHE_MAX_AGE)

  def self.selected_product_code(allow_slow_scan = true)
    selected_product_codes(allow_slow_scan).first.to_s
  end

  def self.mini_context_product_codes(allow_slow_scan = false)
    if mini_product_source_mode == "select"
      return selected_product_codes(true).select { |code| product_code_valid?(code) }
    end

    products = visible_product_codes_from_view
    return products unless products.empty?
    selected_product_codes(allow_slow_scan).select { |code| product_code_valid?(code) }
  end

  def self.refresh_mini_products_from_source(allow_slow_scan = false)
    found = mini_context_product_codes(allow_slow_scan)
    set_mini_products(found) unless found.empty?
    found
  rescue
    []
  end

  def self.sync_mini_products_from_active_source(force_context = false, allow_slow_scan = false)
    if mini_product_source_mode == "view"
      view = Sketchup.active_model.active_view rescue nil
      view_sig = view ? visible_product_view_signature(view) : ""
      now = Time.now.to_f
      recent_same_view = @mini_view_sync_last_sig.to_s == view_sig.to_s &&
                         @mini_view_sync_last_at.to_f > 0.0 &&
                         now - @mini_view_sync_last_at.to_f < MINI_VIEW_SYNC_CACHE_MAX_AGE.to_f
      if recent_same_view && @mini_view_sync_last_products.is_a?(Array) && !@mini_view_sync_last_products.empty?
        set_mini_products(@mini_view_sync_last_products)
        return current_mini_products
      end

      if !force_context &&
         @mini_view_sync_last_at.to_f > 0.0 &&
         now - @mini_view_sync_last_at.to_f < MINI_VIEW_SYNC_MIN_INTERVAL.to_f
        return current_mini_products
      end

      # VIEW mode must follow current viewport continuously, but throttled.
      found = refresh_mini_products_from_source(false)
      @mini_view_sync_last_products = Array(found).dup
      @mini_view_sync_last_sig = view_sig.to_s
      @mini_view_sync_last_at = now
      return current_mini_products
    end

    selected_products = selected_product_codes(true).select { |code| product_code_valid?(code) }
    # STICKY: selection không có mã sản phẩm hợp lệ thì giữ bảng trước,
    # không xoá. Chỉ đổi khi chọn mã mới hợp lệ.
    set_mini_products(selected_products) unless selected_products.empty?
    current_mini_products
  rescue
    current_mini_products
  end

  def self.mini_last_products_from_model
    @model ||= Sketchup.active_model
    raw = @model.get_attribute("MH_Thongke", "mini_last_products").to_s rescue ""
    raw = @model.get_attribute("MH_Thongke", "mini_last_product").to_s if raw.empty? rescue raw
    raw.split("|").map { |code| product_code_exact(code) }
       .select { |code| product_code_valid?(code) }
       .uniq
  rescue
    []
  end

  def self.selected_product_codes(allow_slow_scan = true)
    @model = Sketchup.active_model
    if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:codes_from_selection)
      shared_codes = MH::ProductContext.codes_from_selection(@model, allow_slow_scan: allow_slow_scan)
      shared_codes = Array(shared_codes).map { |code| product_code_exact(code) }.select { |code| product_code_valid?(code) }.uniq
      return shared_codes.sort_by { |code| product_code_sort_key(code) } unless shared_codes.empty?
    end

    sel_sig = begin
      if respond_to?(:selection_signature)
        selection_signature
      else
        @model.selection.to_a.map { |e| e.entityID rescue nil }.compact.sort.join(",")
      end
    rescue
      ""
    end
    path_sig = begin
      Array(@model.active_path).map { |e| e.entityID rescue nil }.compact.join("/")
    rescue
      ""
    end
    cache_key = [allow_slow_scan ? "1" : "0", sel_sig, path_sig, @process_selection_cache_sig.to_s].join("::")
    if @selected_product_codes_cache_key.to_s == cache_key && @selected_product_codes_cache.is_a?(Array)
      return @selected_product_codes_cache.dup
    end

    sel = @model.selection.to_a
    if sel.empty?
      @selected_product_codes_cache_key = cache_key
      @selected_product_codes_cache = []
      return []
    end

    products = []
    add_product = lambda do |value|
      code = value.to_s.strip
      products << code unless code.empty? || code == "--" || products.include?(code)
    end

    active_path = @model.active_path || []
    active_path.reverse_each do |e|
      text = e.name.to_s
      text += " #{e.definition.name}" if e.respond_to?(:definition) && e.definition
      product_codes_from_text(text).each { |code| add_product.call(code) }
    end

    sel.each do |e|
      text = e.name.to_s
      text += " #{e.definition.name}" if e.respond_to?(:definition) && e.definition
      product_codes_from_text(text).each { |code| add_product.call(code) }
    end

    return products unless products.empty?

    if allow_slow_scan
      visible_product_index rescue nil
      entity_products = @visible_product_index_cache && @visible_product_index_cache[:entity_products]
      if entity_products
        sel.each do |e|
          id = e.entityID rescue nil
          add_product.call(entity_products[id]) if id
        end
        return products unless products.empty?
      end
    end

    report_products = selected_product_codes_from_current_report
    return report_products unless report_products.empty?
    return products unless allow_slow_scan

    selected_ids = sel.map { |e| e.entityID rescue nil }.compact
    finder = lambda do |entities, current_prod, depth|
      return if depth > 2 || !entities

      entities.each do |e|
        next unless e.is_a?(Sketchup::Group)
        text = e.respond_to?(:name) ? e.name.to_s : ""
        text += " #{e.definition.name}" if e.respond_to?(:definition) && e.definition
        prod = product_codes_from_text(text).first || current_prod
        add_product.call(prod) if selected_ids.include?(e.entityID) && !prod.to_s.empty?
        child = e.entities
        finder.call(child, prod, depth + 1) if child
      end
      nil
    end
    finder.call(@model.entities, "", 0)

    result = products.sort_by { |code| product_code_sort_key(code) }
    @selected_product_codes_cache_key = cache_key
    @selected_product_codes_cache = result.dup
    result
  end

  def self.selected_product_codes_from_current_report
    products = []
    add_product = lambda do |value|
      code = value.to_s.strip
      products << code unless code.empty? || code == "--" || products.include?(code)
    end
    ((@current_report_items || []) + (@current_mat_items || [])).each do |row|
      selected = row[:sel_count].to_i > 0 || row[:sel_length].to_f > 0
      next unless selected
      prod = row[:actual_product].to_s.empty? ? row[:product].to_s : row[:actual_product].to_s
      add_product.call(prod)
    end
    products.sort_by { |code| product_code_sort_key(code) }
  end

  # === mini_import_context_state.rb ===
  # --- mini_import_context_state.rb ---
# MH_Thongke - current product state/display helpers.


  def self.current_mini_products
    products = (@mini_products || []).map(&:to_s).map(&:strip).reject(&:empty?)
    products = [@mini_product.to_s.strip] if products.empty? && !@mini_product.to_s.strip.empty?
    products = mini_last_products_from_model if products.empty? && respond_to?(:mini_last_products_from_model)
    products.uniq
  end

  def self.set_mini_products(products)
    @mini_products = products.map(&:to_s).map(&:strip).reject(&:empty?).uniq
    @mini_product = @mini_products.first.to_s
    if !@mini_products.empty?
      @model ||= Sketchup.active_model
      @model.set_attribute("MH_Thongke", "mini_last_product", @mini_product) rescue nil
      @model.set_attribute("MH_Thongke", "mini_last_products", @mini_products.join("|")) rescue nil
    end
  end

  def self.mini_display_products
    products = current_mini_products
    if mini_group_mode == "module"
      products.map { |code| product_code_exact(code) }.reject(&:empty?).uniq
    else
      products.map { |code| product_code_base(code) }.reject(&:empty?).uniq
    end
  end

  def self.mini_product_display_title(products = mini_display_products)
    products = if mini_group_mode == "module"
      products.map { |code| product_code_exact(code) }.reject(&:empty?).uniq
    else
      products.map { |code| product_code_base(code) }.reject(&:empty?).uniq
    end
    return "" if products.empty?
    return mini_import_title(products.first, false, mini_group_mode) if products.size == 1

    "#{products.size} s\u1EA3n ph\u1EA9m: #{products.join(', ')}"
  end

  def self.with_mini_product(product_code)
    old_product = @mini_product
    @mini_product = product_code.to_s
    yield
  ensure
    @mini_product = old_product
  end

  def self.mini_action_product(product_code)
    product = product_code.to_s.strip
    product.empty? ? @mini_product.to_s : product
  end

  # === mini_import_context.rb ===
  # --- mini_import_context.rb ---
# MH_Thongke - Mini Import context entrypoint.
#
# Logic is split into:
# - mini_import_context_codes.rb
# - mini_import_context_modes.rb
# - mini_import_context_targets.rb
# - mini_import_context_selection.rb
# - mini_import_context_state.rb

  # === mini_import_view_geometry.rb ===
  # --- mini_import_view_geometry.rb ---
# MH_Thongke - Mini Import viewport geometry helpers.


  def self.product_entity_bounds(entity)
    if entity.is_a?(Sketchup::ComponentInstance) && entity.definition
      entity.definition.bounds
    elsif entity.is_a?(Sketchup::Group) && entity.respond_to?(:local_bounds)
      entity.local_bounds
    else
      entity.bounds
    end
  rescue
    nil
  end

  def self.product_screen_rect(entity, world_tr, view, eye, direction)
    bounds = product_entity_bounds(entity)
    return nil unless bounds && bounds.valid?

    corners = (0..7).map { |i| bounds.corner(i).transform(world_tr) }
    front_corners = corners.select { |pt| ((pt - eye).dot(direction) rescue -1.0) > 0.0 }
    return nil if front_corners.empty?

    screen_pts = front_corners.map { |pt| view.screen_coords(pt) rescue nil }.compact
    return nil if screen_pts.empty?

    xs = screen_pts.map(&:x)
    ys = screen_pts.map(&:y)
    center = view.screen_coords(bounds.center.transform(world_tr)) rescue nil
    {
      left: xs.min,
      top: ys.min,
      right: xs.max,
      bottom: ys.max,
      center: center
    }
  rescue
    nil
  end

  def self.screen_rect_on_screen?(rect, width, height, margin = 32)
    return false unless rect

    rect[:right] >= -margin && rect[:left] <= width.to_f + margin &&
      rect[:bottom] >= -margin && rect[:top] <= height.to_f + margin
  rescue
    false
  end

  def self.screen_rect_focus_score(rect, focus_rect)
    return 0.0 unless rect

    overlap_area = rect_overlap_area(rect, focus_rect)
    return 0.0 if overlap_area <= 0.0

    left = rect[:left]
    right = rect[:right]
    top = rect[:top]
    bottom = rect[:bottom]
    box_w = [right - left, 1.0].max
    box_h = [bottom - top, 1.0].max
    box_area = box_w * box_h
    focus_area = [focus_rect[:right] - focus_rect[:left], 1.0].max * [focus_rect[:bottom] - focus_rect[:top], 1.0].max

    center_in_focus = point_in_rect?(rect[:center], focus_rect)

    overlap_ratio = overlap_area / box_area
    focus_ratio = overlap_area / focus_area
    return 0.0 unless center_in_focus || overlap_area >= 700.0 || overlap_ratio >= 0.08 || focus_ratio >= 0.004

    score = overlap_area
    score += 10_000.0 if center_in_focus
    score += overlap_ratio * 2_000.0
    score
  rescue
    0.0
  end

  def self.rect_overlap_area(rect, frame)
    overlap_w = [rect[:right], frame[:right]].min - [rect[:left], frame[:left]].max
    overlap_h = [rect[:bottom], frame[:bottom]].min - [rect[:top], frame[:top]].max
    overlap_w > 0.0 && overlap_h > 0.0 ? overlap_w * overlap_h : 0.0
  rescue
    0.0
  end

  def self.product_rects_visible_enough?(rects, width, height, focus_rect)
    rects = Array(rects).compact
    return false if rects.empty?

    union = {
      left: rects.map { |r| r[:left] }.min,
      top: rects.map { |r| r[:top] }.min,
      right: rects.map { |r| r[:right] }.max,
      bottom: rects.map { |r| r[:bottom] }.max
    }
    box_area = [[union[:right] - union[:left], 1.0].max * [union[:bottom] - union[:top], 1.0].max, 1.0].max
    viewport = { left: 0.0, top: 0.0, right: width.to_f, bottom: height.to_f }
    viewport_ratio = rect_overlap_area(union, viewport) / box_area
    focus_ratio = rect_overlap_area(union, focus_rect) / box_area
    max_focus_overlap = rects.map { |r| rect_overlap_area(r, focus_rect) }.max.to_f
    focus_hits = rects.count { |r| rect_overlap_area(r, focus_rect) > 0.0 }
    center_hits = rects.count { |r| point_in_rect?(r[:center], focus_rect) }

    # Zoom gần: chỉ cần một phần đủ lớn của SP nằm trong vùng focus là chấp nhận.
    return true if center_hits > 0 && max_focus_overlap >= 30.0
    return true if max_focus_overlap >= 140.0
    return true if focus_hits > 0 && viewport_ratio >= 0.10 && focus_ratio >= 0.005
    false
  rescue
    false
  end

  def self.point_in_rect?(point, rect)
    return false unless point && rect

    point.x >= rect[:left] && point.x <= rect[:right] &&
      point.y >= rect[:top] && point.y <= rect[:bottom]
  rescue
    false
  end

  # === mini_import_view_context.rb ===
  # --- mini_import_view_context.rb ---
# MH_Thongke - Mini Import viewport product detection.


  def self.visible_product_view_signature(view)
    cam = view.camera
    path_ids = Array(Sketchup.active_model.active_path).map { |e| e.entityID rescue nil }.compact
    parts = [
      "focus_score_v7",
      view.vpwidth, view.vpheight,
      cam.eye.to_a.map { |v| v.to_f.round(0) },
      cam.target.to_a.map { |v| v.to_f.round(0) },
      cam.up.to_a.map { |v| v.to_f.round(2) },
      path_ids,
      mini_group_mode
    ]
    parts.flatten.join(":")
  rescue
    Time.now.to_f.to_s
  end

  def self.product_bounds_visible_on_screen?(entity, world_tr, view, width, height, eye, direction, margin = 32)
    rect = product_screen_rect(entity, world_tr, view, eye, direction)
    screen_rect_on_screen?(rect, width, height, margin)
  rescue
    false
  end

  def self.visible_product_focus_rect(width, height)
    inset_x = (width.to_f * 0.10).round
    inset_y = (height.to_f * 0.10).round
    {
      left: inset_x,
      top: inset_y,
      right: width.to_f - inset_x,
      bottom: height.to_f - inset_y
    }
  end

  def self.product_bounds_focus_score(entity, world_tr, view, eye, direction, focus_rect)
    rect = product_screen_rect(entity, world_tr, view, eye, direction)
    screen_rect_focus_score(rect, focus_rect)
  rescue
    0.0
  end

  # === mini_import_view_index.rb ===
  # --- mini_import_view_index.rb ---
# MH_Thongke - Mini Import viewport index builder.


  def self.visible_product_index
    @model = Sketchup.active_model
    model_sig = model_structure_signature rescue @model.guid.to_s
    path_sig = Array(@model.active_path).map { |e| e.entityID rescue nil }.compact.join("/")
    if @visible_product_index_cache &&
       @visible_product_index_cache[:model_sig] == model_sig &&
       @visible_product_index_cache[:path_sig] == path_sig
      return @visible_product_index_cache[:items]
    end

    items, entity_products = build_visible_product_index_items(@model)
    @visible_product_index_cache = { model_sig: model_sig, path_sig: path_sig, items: items, entity_products: entity_products }
    items
  rescue => e
    puts "visible_product_index error: #{e.message}"
    []
  end

  def self.build_visible_product_index_items(model)
    items = []
    entity_products = {}
    scan_count = 0
    max_scan = 1500
    max_depth = 2
    active_path_tr = Geom::Transformation.new
    Array(model.active_path).each do |entity|
      active_path_tr = active_path_tr * entity.transformation if entity.respond_to?(:transformation)
    end

    walker = lambda do |entities, parent_tr, current_product, depth|
      return if depth > max_depth || scan_count >= max_scan || !entities

      entities.each do |entity|
        break if scan_count >= max_scan
        next unless entity.is_a?(Sketchup::Group)
        next if entity.respond_to?(:deleted?) && entity.deleted?
        next if (entity.hidden? rescue false)
        next unless entity_layer_visible?(entity)

        scan_count += 1
        child_tr = parent_tr * entity.transformation
        code = product_code_from_entity(entity)
        product = product_code_exact(code || current_product)
        entity_products[entity.entityID] = product if entity.respond_to?(:entityID) && !product.empty?
        if code && product_code_valid?(code)
          exact_code = product_code_exact(code)
          index_code = mini_product_mode? ? product_code_base(exact_code) : exact_code
          current_base = product_code_base(current_product)
          parent_already_represents_product = mini_product_mode? && !current_base.empty? && current_base == index_code
          items << { code: index_code, entity: entity, tr: child_tr, depth: depth } unless parent_already_represents_product
        end

        child_entities = entity.entities rescue nil
        walker.call(child_entities, child_tr, product, depth + 1) if child_entities
      end
    end

    walker.call(model.active_entities, active_path_tr, "", 0)
    [items, entity_products]
  rescue
    [[], {}]
  end

  # === mini_import_view_codes.rb ===
  # --- mini_import_view_codes.rb ---
# MH_Thongke - Mini Import viewport product code scan.


  MINI_VIEW_MAX_PRODUCTS = 6 unless const_defined?(:MINI_VIEW_MAX_PRODUCTS)

  def self.visible_product_codes_from_view
    @model = Sketchup.active_model
    view = @model.active_view
    return [] unless view

    model_sig = model_structure_signature rescue @model.guid.to_s
    view_sig = visible_product_view_signature(view)
    cached = visible_product_codes_cache_hit(model_sig, view_sig)
    return cached if cached

    width = view.vpwidth rescue 0
    height = view.vpheight rescue 0
    return [] if width.to_i <= 0 || height.to_i <= 0
    focus_rect = visible_product_focus_rect(width, height)

    camera = view.camera
    eye = camera.eye
    direction = camera.direction
    products = []
    product_scores = Hash.new(0.0)
    product_rects = Hash.new { |hash, key| hash[key] = [] }

    active_product, active_path_tr = visible_product_active_context(@model)
    visible_product_scan_index(view, eye, direction, width, height, focus_rect, products, product_scores, product_rects)
    return visible_product_finalize_scan(model_sig, view_sig, products, product_scores, product_rects, active_product, width, height, focus_rect) unless products.empty?

    visible_product_scan_fallback(view, eye, direction, width, height, focus_rect, active_path_tr, active_product, products, product_scores, product_rects)
    visible_product_finalize_scan(model_sig, view_sig, products, product_scores, product_rects, active_product, width, height, focus_rect)
  rescue => e
    puts "visible_product_codes_from_view error: #{e.message}"
    []
  end

  def self.visible_product_codes_cache_hit(model_sig, view_sig)
    cache = @visible_product_codes_cache
    return visible_product_cache_products(cache) if visible_product_cache_exact_match?(cache, model_sig, view_sig)
    return visible_product_cache_products(cache) if visible_product_cache_recent_match?(cache, model_sig)

    nil
  rescue
    nil
  end

  def self.visible_product_active_context(model)
    active_product = nil
    Array(model.active_path).reverse_each do |entity|
      active_product ||= product_code_from_entity(entity)
    end
    active_path_tr = Geom::Transformation.new
    Array(model.active_path).each do |entity|
      active_path_tr = active_path_tr * entity.transformation if entity.respond_to?(:transformation)
    end
    [active_product, active_path_tr]
  rescue
    ["", Geom::Transformation.new]
  end

  def self.visible_product_scan_index(view, eye, direction, width, height, focus_rect, products, product_scores, product_rects)
    visible_product_index.each do |item|
      entity = item[:entity]
      next if entity.respond_to?(:deleted?) && entity.deleted?
      next if (entity.hidden? rescue false)
      next unless entity_layer_visible?(entity)

      product_code = product_code_exact(item[:code])
      next unless visible_product_code?(product_code)

      rect = product_screen_rect(entity, item[:tr], view, eye, direction)
      next unless screen_rect_on_screen?(rect, width, height)

      product_rects[product_code] << rect
      visible_product_add_from_rect(products, product_scores, product_code, rect, focus_rect)
    end
  end

  def self.visible_product_scan_fallback(view, eye, direction, width, height, focus_rect, active_path_tr, active_product, products, product_scores, product_rects)
    scan_count = 0
    max_scan = visible_product_fallback_max_scan
    max_depth = visible_product_fallback_max_depth
    walker = lambda do |entities, parent_tr, current_product, depth|
      return if depth > max_depth || scan_count >= max_scan
      entities.each do |entity|
        next unless visible_product_fallback_scannable_group?(entity)

        scan_count += 1
        child_tr = parent_tr * entity.transformation
        product = product_code_from_entity(entity) || current_product
        rect = product_screen_rect(entity, child_tr, view, eye, direction)
        entity_on_screen = screen_rect_on_screen?(rect, width, height)
        visible_product_collect_fallback_rect(product_rects, product, rect, entity_on_screen)
        visible_product_add_from_rect(products, product_scores, product, rect, focus_rect) if product && entity_on_screen
        next unless entity_on_screen

        child_entities = visible_product_fallback_child_entities(entity)
        walker.call(child_entities, child_tr, product, depth + 1) if child_entities
      end
    end

    walker.call(@model.active_entities, active_path_tr, active_product, 0)
    visible_product_apply_rect_fallback(products, product_scores, product_rects, focus_rect)
  end

  def self.visible_product_finalize_scan(model_sig, view_sig, products, product_scores, product_rects, active_product, width, height, focus_rect)
    add_active = product_code_exact(active_product)
    products << add_active if products.empty? && !add_active.empty? && !products.include?(add_active)
    products.select! do |code|
      code == add_active ||
        (product_scores[code].to_f > 0.0 && product_rects_visible_enough?(product_rects[code], width, height, focus_rect))
    end
    if MINI_VIEW_MAX_PRODUCTS.to_i > 0 && products.size > MINI_VIEW_MAX_PRODUCTS.to_i
      products = products
        .sort_by { |code| [-product_scores[code].to_f, product_code_sort_key(code)] }
        .first(MINI_VIEW_MAX_PRODUCTS.to_i)
    end
    products.sort_by! { |code| product_code_sort_key(code) }
    @visible_product_codes_cache = { model_sig: model_sig, view_sig: view_sig, products: products.dup, scanned_at: Time.now.to_f }
    products
  rescue
    []
  end

  def self.visible_product_code?(value)
    code = product_code_exact(value)
    product_code_valid?(code)
  rescue
    false
  end

  def self.visible_product_add(products, product_scores, value, score = 0.0)
    code = product_code_exact(value)
    return unless visible_product_code?(code)

    products << code unless products.include?(code)
    product_scores[code] += score.to_f
  rescue
    nil
  end

  def self.visible_product_add_from_rect(products, product_scores, value, rect, focus_rect)
    focus_score = screen_rect_focus_score(rect, focus_rect)
    if focus_score > 0.0
      visible_product_add(products, product_scores, value, focus_score)
    elsif rect && rect_overlap_area(rect, focus_rect) >= 20.0
      visible_product_add(products, product_scores, value, 0.01)
    end
  end

  def self.visible_product_apply_rect_fallback(products, product_scores, product_rects, focus_rect)
    return unless products.empty? && !product_rects.empty?

    fallback = product_rects.keys
      .map do |code|
        rects = product_rects[code]
        score = rects.map { |r| rect_overlap_area(r, focus_rect) }.max.to_f
        [code, score]
      end
      .select { |(_, score)| score > 0.0 }
      .sort_by { |(_, score)| -score }
      .map(&:first)
    fallback.each { |code| visible_product_add(products, product_scores, code, 0.01) }
  end

  def self.visible_product_cache_products(cache)
    Array(cache[:products]).dup
  rescue
    []
  end

  def self.visible_product_cache_exact_match?(cache, model_sig, view_sig)
    cache &&
      cache[:model_sig] == model_sig &&
      cache[:view_sig] == view_sig
  rescue
    false
  end

  def self.visible_product_cache_recent_match?(cache, model_sig, max_age = 1.2)
    cache &&
      cache[:model_sig] == model_sig &&
      cache[:scanned_at].to_f > 0 &&
      Time.now.to_f - cache[:scanned_at].to_f < max_age.to_f
  rescue
    false
  end

  def self.visible_product_fallback_max_scan
    700
  end

  def self.visible_product_fallback_max_depth
    1
  end

  def self.visible_product_fallback_scannable_group?(entity)
    return false unless entity.is_a?(Sketchup::Group)
    return false if entity.respond_to?(:deleted?) && entity.deleted?
    return false if (entity.hidden? rescue false)
    return false unless entity_layer_visible?(entity)

    true
  rescue
    false
  end

  def self.visible_product_collect_fallback_rect(product_rects, product, rect, entity_on_screen)
    return unless entity_on_screen

    product_code = product_code_exact(product)
    return unless visible_product_code?(product_code)

    product_rects[product_code] << rect
  rescue
    nil
  end

  def self.visible_product_fallback_child_entities(entity)
    entity.entities
  rescue
    nil
  end

  # === mini_import_view_scan.rb ===
  # --- mini_import_view_scan.rb ---
# MH_Thongke - Mini Import viewport scan entrypoint.
#
# Logic is split into:
# - mini_import_view_index.rb
# - mini_import_view_codes.rb
end


module MH_Thongke
  def self.skip_material?(mat_name)
    return true if mat_name.nil? || mat_name.empty?
    lower = mat_name.downcase.strip
    return true if SKIP_DEFAULT_MATERIALS.include?(lower)
    return true if lower =~ /\A<auto>\d*\z/            # <auto>, <auto>7, <auto>10...
    return true if lower =~ /\A\[.*\]\z/                # [Material1] etc.
    return true if lower =~ /\Acolor_[0-9a-f]+\z/i      # Color_FFFFFF
    false
  end

  def self.material_code_thickness(code)
    text = fix_vietnamese_mojibake(code).to_s.strip
    return "" if text.empty?

    parts = text.split(".")
    return "" if parts.size < 2

    parts[1].to_s.strip
  rescue
    ""
  end

  def self.material_layer_pending?(layer_name)
    cached_norm(layer_name).gsub(/\s+/, "_") == "chua_dat"
  rescue
    false
  end

  def self.material_row_pending?(row)
    tags = Array(row[:layer_tags]).map { |v| cached_norm(v).gsub(/\s+/, "_") }
    return true if tags.include?("chua_dat")

    Array(row[:stat_entities]).any? do |pair|
      ent = pair.is_a?(Array) ? pair[0] : pair
      next false unless ent && ent.respond_to?(:layer) && ent.layer

      material_layer_pending?(ent.layer.name.to_s)
    end
  rescue
    false
  end

  def self.apply_obj_material_status!
    excel_vl_by_base = Hash.new { |h, k| h[k] = [] }
    Array(@imported_excel_data).each do |ex|
      next unless ex[:kind].to_s.strip.upcase == "VL"
      code = ex[:ma_sp].to_s.strip
      next if code.empty?
      base = respond_to?(:product_code_base) ? product_code_base(code) : code.sub(/\.\d+\z/, "")
      next if base.to_s.empty?

      hw_name = ex[:hw_name].to_s
      spec = ex[:spec].to_s
      target = respond_to?(:import_display_name) ? import_display_name(hw_name, spec) : "#{hw_name} #{spec}".strip
      excel_vl_by_base[base] << {
        row: ex,
        hw_name: hw_name,
        spec: spec,
        target: target,
        norm_hw: import_name_norm(hw_name),
        norm_target: import_name_norm(target)
      }
    end

    local_cache = defined?(MH::Memo) ? MH::Memo.method(:local) : nil
    base_cache = local_cache ? local_cache.call : {}
    norm_model_cache = local_cache ? local_cache.call : {}
    pending_cache = local_cache ? local_cache.call : {}
    material_match_cache = local_cache ? local_cache.call : {}
    mini_material_match_cache = local_cache ? local_cache.call : {}
    related_cache = local_cache ? local_cache.call : {}

    product_base_for = lambda do |value|
      text = value.to_s
      base_cache.fetch(text) { respond_to?(:product_code_base) ? product_code_base(text) : text.sub(/\.\d+\z/, "") }
    end
    row_pending_for = lambda do |row|
      pending_cache.fetch(row.object_id) { material_row_pending?(row) }
    end
    material_match_for = lambda do |model_name, target_name|
      key = "#{model_name}\0#{target_name}"
      material_match_cache.fetch(key) { material_name_match?(model_name, target_name) }
    end
    mini_material_match_for = lambda do |excel_name, model_name|
      key = "#{excel_name}\0#{model_name}"
      mini_material_match_cache.fetch(key) { respond_to?(:mini_import_material_model_match?) && mini_import_material_model_match?(excel_name, model_name) }
    end
    related_for = lambda do |product, model_name, target_name|
      key = "#{product}\0#{model_name}\0#{target_name}"
      related_cache.fetch(key) { respond_to?(:mini_item_names_related?) && mini_item_names_related?(product, "VL", model_name, target_name) }
    end

    (@mat_data_map || {}).each_value do |row|
      product = row[:actual_product].to_s
      su_name = row[:name].to_s
      row[:new_name] = ""

      if row_pending_for.call(row) || product.empty? || su_name.empty?
        row[:trang_thai] = "THIEU"
        next
      end

      base = product_base_for.call(product)
      excel_rows = excel_vl_by_base[base] || []
      
      if excel_rows.empty?
        # No Excel VL data for this product → keep original DU/THIEU logic (layer-based)
        row[:trang_thai] = row_pending_for.call(row) ? "THIEU" : "DU"
        next
      end

      matched_ex = nil
      exact_match = false
      norm_model = norm_model_cache.fetch(su_name) { import_name_norm(su_name) }
      excel_rows.each do |ex|
        hw_name = ex[:hw_name]
        spec = ex[:spec]
        target = ex[:target]
        norm_hw = ex[:norm_hw]
        norm_target = ex[:norm_target]

        # Use same matching as Mini Import: material_code_norm / material_code_variant_norm
        if !norm_model.empty? && (norm_model == norm_target || norm_model == norm_hw)
          matched_ex = ex[:row]
          exact_match = true
          break
        end

        if mini_material_match_for.call(hw_name, su_name) || mini_material_match_for.call(target, su_name)
          matched_ex = ex[:row]
          exact_match = true
          break
        end

        if material_match_for.call(su_name, hw_name) || material_match_for.call(su_name, target)
          matched_ex = ex[:row]
          exact_match = true
          break
        end

        if related_for.call(product, su_name, hw_name) || related_for.call(product, su_name, target)
          matched_ex = ex[:row]
          break
        end
      end

      if matched_ex
        hw_name = matched_ex[:hw_name].to_s
        spec = matched_ex[:spec].to_s
        target = respond_to?(:import_display_name) ? import_display_name(hw_name, spec) : "#{hw_name} #{spec}".strip
        status = respond_to?(:resolve_mini_material_row_status_key) ? resolve_mini_material_row_status_key({ type: :matched, exact: exact_match, product_code: product, name: su_name, target_name: target, spec: spec }) : "OK"
        row[:trang_thai] = status == "OK" ? "DU" : status
      else
        status = respond_to?(:resolve_mini_material_row_status_key) ? resolve_mini_material_row_status_key({ type: :model_only, product_code: product, name: su_name }) : "NO_SPEC"
        row[:trang_thai] = status == "OK" ? "DU" : status
      end
    end
  rescue => e
    puts "apply_obj_material_status! error: #{e.message}" rescue nil
  end

  def self.material_name_match?(row_name, face_material_name)
    a = face_material_name.to_s.strip
    b = row_name.to_s.strip
    return false if a.empty? || b.empty?

    if respond_to?(:material_code_norm)
      material_code_norm(a) == material_code_norm(b)
    else
      import_name_norm(a) == import_name_norm(b)
    end
  rescue
    a.casecmp?(b)
  end

  def self.material_entity_face_collection(entity)
    return [] unless entity
    return [] if entity.respond_to?(:deleted?) && entity.deleted?

    if entity.is_a?(Sketchup::ComponentInstance)
      (entity.definition.entities.grep(Sketchup::Face) rescue [])
    elsif entity.is_a?(Sketchup::Group)
      (entity.entities.grep(Sketchup::Face) rescue [])
    else
      []
    end
  rescue
    []
  end

  def self.material_entity_largest_face_area(pair, row_name, match_cache = nil)
    ent = pair.is_a?(Array) ? pair[0] : pair
    parent_wt = pair.is_a?(Array) ? pair[2] : Geom::Transformation.new
    return 0.0 unless ent

    entity_tr = ent.respond_to?(:transformation) ? ent.transformation : Geom::Transformation.new
    world_tr = parent_wt ? (parent_wt * entity_tr) : entity_tr
    faces = material_entity_face_collection(ent)
    return 0.0 if faces.empty?

    matched_areas = []
    all_areas = []
    faces.each do |face|
      area = face.area(world_tr).to_f rescue 0.0
      next if area <= 0.0
      all_areas << area
      front = face.material ? face.material.display_name.to_s : ""
      back = face.back_material ? face.back_material.display_name.to_s : ""
      front_key = "#{row_name}\0#{front}"
      back_key = "#{row_name}\0#{back}"
      front_match = if match_cache
        match_cache[front_key] = material_name_match?(row_name, front) unless match_cache.key?(front_key)
        match_cache[front_key]
      else
        material_name_match?(row_name, front)
      end
      back_match = if match_cache
        match_cache[back_key] = material_name_match?(row_name, back) unless match_cache.key?(back_key)
        match_cache[back_key]
      else
        material_name_match?(row_name, back)
      end
      if front_match || back_match
        matched_areas << area
      end
    end
    source = matched_areas.empty? ? all_areas : matched_areas
    source.empty? ? 0.0 : source.max.to_f
  rescue
    0.0
  end

  def self.material_row_completion_percent(row, match_cache = nil, pending_cache = nil)
    pairs = Array(row[:stat_entities])
    return 0.0 if pairs.empty?

    total_area = 0.0
    done_area = 0.0
    pairs.each do |pair|
      ent = pair.is_a?(Array) ? pair[0] : pair
      next unless ent
      next if ent.respond_to?(:deleted?) && ent.deleted?

      largest_face = material_entity_largest_face_area(pair, row[:name], match_cache)
      next if largest_face <= 0.0

      total_area += largest_face
      layer_name = ent.respond_to?(:layer) && ent.layer ? ent.layer.name.to_s : ""
      pending = if pending_cache && !layer_name.empty?
        pending_cache[layer_name] = material_layer_pending?(layer_name) unless pending_cache.key?(layer_name)
        pending_cache[layer_name]
      else
        !layer_name.empty? && material_layer_pending?(layer_name)
      end
      done_area += largest_face unless pending
    end

    return 0.0 if total_area <= 0.0
    (done_area * 100.0 / total_area)
  rescue
    0.0
  end

  def self.material_completion_text(value)
    pct = value.to_f
    pct = 0.0 if pct.nan? || pct.infinite?
    pct = 0.0 if pct < 0.0
    pct = 100.0 if pct > 100.0
    text = format("%.1f", pct)
    text = text.sub(/\.0\z/, "")
    "#{text}%"
  rescue
    "0%"
  end

  def self.apply_material_completion_percent!
    if defined?(MH::Memo)
      match_cache = MH::Memo.local
      pending_cache = MH::Memo.local
    else
      match_cache = {}
      pending_cache = {}
    end
    (@mat_data_map || {}).each_value do |row|
      pct = material_row_completion_percent(row, match_cache, pending_cache)
      row[:completion_percent] = pct
      row[:completion_text] = material_completion_text(pct)
    end
  rescue
    nil
  end
end

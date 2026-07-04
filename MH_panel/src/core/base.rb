module MH::Panel
  # Gán mã hệ MH cho 1 part vừa tạo:
  #  - SP (product_code): lấy từ tấm gốc/parent (ProductContext), ghi attribute.
  #  - Mã vật liệu: từ material gốc + độ dày part + hậu tố .1M/.2M theo tên chi
  #    tiết (qua connector material_assign). Set group.material + attribute.
  # detail_name = tên chi tiết (vd "Cánh Trái"); thickness_mm = độ dày (mm);
  # material_name = tên VL gốc (mặc định lấy từ group.material); source = entity
  # tấm gốc để suy SP.
  def self.entity_attr(entity, key)
    return '' unless entity && entity.respond_to?(:get_attribute)

    value = entity.get_attribute('MH_Registry', key).to_s
    return value unless value.strip.empty?

    value = entity.get_attribute('dynamic_attributes', key).to_s
    return value unless value.strip.empty?

    if entity.respond_to?(:definition) && entity.definition
      value = entity.definition.get_attribute('MH_Registry', key).to_s
      return value unless value.strip.empty?

      value = entity.definition.get_attribute('dynamic_attributes', key).to_s
      return value unless value.strip.empty?
    end

    ''
  rescue
    ''
  end

  def self.product_code_from_source(source)
    code = entity_attr(source, 'product_code')
    code = entity_attr(source, 'dc_product_code') if code.strip.empty?
    if code.strip.empty? && defined?(MH::ProductContext)
      code = MH::ProductContext.code_from_entity(source).to_s
    end
    code.to_s.strip
  rescue
    ''
  end

  def self.material_name_from_source(source, fallback = nil)
    raw = entity_attr(source, 'dc_material_code')
    raw = entity_attr(source, 'material_code') if raw.strip.empty?
    if raw.strip.empty? && source && source.respond_to?(:material) && source.material && source.material.respond_to?(:name)
      raw = source.material.name.to_s
    end
    if raw.strip.empty? && fallback && fallback.respond_to?(:name)
      raw = fallback.name.to_s
    elsif raw.strip.empty?
      raw = fallback.to_s
    end
    raw.to_s.strip
  rescue
    fallback.to_s
  end

  def self.material_name_from_face_path(face, path = nil, source = nil)
    material = face.material if face && face.respond_to?(:material)
    material ||= face.back_material if face && face.respond_to?(:back_material)
    material ||= Array(path)[0..-2].reverse.find { |e| e.respond_to?(:material) && e.material }&.material
    material_name_from_source(source, material)
  rescue
    ''
  end

  def self.part_name_with_product(detail_name, product_code, source = nil)
    name = detail_name.to_s.strip
    if name.empty? && source && source.respond_to?(:name)
      name = source.name.to_s.strip
    end
    if name.empty? && source && source.respond_to?(:definition) && source.definition
      name = source.definition.name.to_s.strip
    end

    sp = product_code.to_s.strip
    return name if sp.empty?
    return sp if name.empty?
    if defined?(MH::NameGrammar)
      existing = MH::NameGrammar.first_product(name).to_s
      return name if !existing.empty? && existing.upcase == sp.upcase

      built = MH::NameGrammar.build_name(product: sp, part: name)
      return built unless built.to_s.strip.empty?
    end
    return name if name =~ /(^|[\s._-])#{Regexp.escape(sp)}([\s._-]|$)/i

    "#{sp}_#{name}"
  rescue
    detail_name.to_s.strip
  end

  def self.assign_part_name(group, detail_name, product_code = nil, source = nil)
    name = part_name_with_product(detail_name, product_code, source)
    return if name.to_s.strip.empty?

    group.name = name if group.respond_to?(:name=)
    if group.respond_to?(:definition) && group.definition && group.definition.respond_to?(:name=)
      group.definition.name = name
    end
  rescue => e
    puts "[MH::Panel] name error: #{e.class}: #{e.message}"
  end

  def self.effective_detail_name(detail_name, group = nil, source = nil)
    name = detail_name.to_s.strip
    name = group.name.to_s.strip if name.empty? && group && group.respond_to?(:name)
    name = source.name.to_s.strip if name.empty? && source && source.respond_to?(:name)
    if name.empty? && source && source.respond_to?(:definition) && source.definition
      name = source.definition.name.to_s.strip
    end
    name
  rescue
    detail_name.to_s.strip
  end

  def self.apply_mh_codes(group, detail_name: nil, thickness_mm: nil, material_name: nil, source: nil, product_code: nil)
    return unless group && group.valid?

    # 1) SP từ tấm gốc / container → attribute (ưu tiên product_code truyền vào)
    assigned_product_code = ''
    begin
      sp = product_code.to_s
      sp = product_code_from_source(source) if sp.strip.empty? && source
      sp = product_code_from_source(group) if sp.strip.empty?
      if sp.strip.empty? && defined?(MH::ProductContext)
        sp = product_code_from_source(source) if source
        sp = MH::ProductContext.current_or_last_code.to_s if sp.strip.empty?
      end
      group.set_attribute('MH_Registry', 'product_code', sp) unless sp.strip.empty?
      assigned_product_code = sp.to_s.strip
    rescue => e
      puts "[MH::Panel] SP error: #{e.class}: #{e.message}"
    end

    # Không ghép mã SP vào tên obj nữa — chỉ lưu SP ở attribute phía trên.
    # Tên chỉ dùng tên chi tiết (detail_name / tên nguồn).
    effective_detail = effective_detail_name(detail_name, group, source)
    assign_part_name(group, effective_detail, '', source)

    # 2) Mã vật liệu (+1M/2M) từ material gốc
    begin
      raw = material_name.to_s
      raw = material_name_from_source(source, group.material) if raw.empty?
      raw = material_name_from_source(group, group.material) if raw.empty?
      return if raw.empty? || thickness_mm.to_f <= 0
      mats = group.model.materials
      coded_name = nil
      if defined?(MH::RegistryApp::Connector)
        conn = MH::RegistryApp::Connector.get('material_assign') rescue nil
        if conn && conn.respond_to?(:coded_material)
          res = conn.coded_material(raw, thickness_mm.to_f, effective_detail)
          coded_name = res['material'].to_s if res && res['ok'] && !res['material'].to_s.empty?
        end
      end
      mat_name = coded_name.to_s.strip.empty? ? raw : coded_name.to_s.strip
      mat =
        if defined?(MH::MaterialApp::MaterialCreator) &&
           MH::MaterialApp::MaterialCreator.respond_to?(:load_material_from_file)
          MH::MaterialApp::MaterialCreator.load_material_from_file(group.model, mat_name)
        else
          mats[mat_name] || mats.add(mat_name)
        end
      group.material = mat
      group.entities.grep(Sketchup::Face).each { |f| f.material = nil; f.back_material = nil } rescue nil
      group.set_attribute('MH_Registry', 'dc_material_code', mat_name)
    rescue => e
      puts "[MH::Panel] material code error: #{e.class}: #{e.message}"
    end
  end

  def self.select_tool(tool_class)
    if tool_class.is_a?(Class)
      tool_instance = tool_class.new
      Sketchup.active_model.select_tool(tool_instance)
    else
      Sketchup.active_model.select_tool(nil)
    end
  end
  def self.init_undo
    start(false)
    Sketchup.active_model.set_attribute("_temp_", "_", nil)
    commit
  end
  def self.start(trans = true)
    Sketchup.active_model.start_operation("MH Panel", true, false, trans)
  end
  def self.commit
    Sketchup.active_model.commit_operation
  end
  def self.status(text)
    Sketchup.set_status_text(text)
  end
  def self.vcb(label, value)
    Sketchup.set_status_text(label, SB_VCB_LABEL)
    return unless value
    Sketchup.set_status_text(value, SB_VCB_VALUE)
  end
  def self.parse_color(value)
    if value.is_a?(String)
      rgb = value.split(',').map { |v| v.strip.to_i }
      Sketchup::Color.new(rgb[0], rgb[1], rgb[2], 200)
    elsif value.is_a?(Array)
      Sketchup::Color.new(value[0], value[1], value[2], 200)
    else
      Sketchup::Color.new(128, 128, 128, 200)
    end
  end
  def self.ensure_tag(tag_name)
    tag_name = tag_name.to_s.strip
    return nil if tag_name.empty?
    layers = Sketchup.active_model.layers
    tag = layers[tag_name] || layers.add(tag_name)
    tag.visible = true
    tag
  end
  def self.select(ents)
    selection = Sketchup.active_model.selection
    selection.clear
    ents = Array(ents)
    return unless ents && ents.size > 0
    selection.add(ents)
  end
  def self.get_transform(instance_path)
    MH::Geo::Util.get_transform(instance_path)
  end
  def self.find_concave_vertex(face, limit_length, limit_angle)
    MH::Geo::Util.find_concave_vertex(face, limit_length, limit_angle)
  end
  def self.is_container?(ent)
    MH::Geo::Util.is_container?(ent)
  end
  def self.create_color_mat(rgb, alpha = 1.0)
    MH::Panel::Material.create_color(rgb, alpha)
  end
  def self.grep_ents(b, mode)
    MH::Geo::Util.grep_ents(b, mode)
  end
  def self.get_ents(parent)
    MH::Geo::Util.get_ents(parent)
  end
  def self.intersect_fix(ent)
    MH::Geo::Util.intersect_fix(ent)
  end
  def self.find_face(ents)
    MH::Geo::Util.find_face(ents)
  end
end
# encoding: UTF-8

module MH
  module Panel
    TOL = 0.001 unless const_defined?(:TOL)
    AREA_TOL = 0.01 unless const_defined?(:AREA_TOL)
    VERSION = '1.0.0' unless const_defined?(:VERSION)
  end
end

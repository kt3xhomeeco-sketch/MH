module MH::Panel::Group
  def self.copy_behavior(target_behavior, source_behavior)
    target_behavior.always_face_camera = source_behavior.always_face_camera?
    target_behavior.cuts_opening = source_behavior.cuts_opening?
    target_behavior.is2d = source_behavior.is2d?
    target_behavior.no_scale_mask = source_behavior.no_scale_mask?
    target_behavior.shadows_face_sun = source_behavior.shadows_face_sun?
    target_behavior.snapto = source_behavior.snapto
  end
  def self.copy_attributes(target, reference)
    (reference.attribute_dictionaries || []).each do |attr_dict|
      next if attr_dict.name == "GSU_ContributorsInfo"
      copied_any = false
      attr_dict.each_pair do |k, v|
        # MH_panel không truyền metadata mã SP/vật liệu sang obj mới.
        next if attr_dict.name == "MH_Registry" &&
                ["product_code", "dc_material_code"].include?(k.to_s)
        target.set_attribute(attr_dict.name, k, v)
        copied_any = true
      end
      copy_attributes(target.attribute_dictionaries[attr_dict.name], attr_dict) if copied_any
    end
  end
  def self.component_to_group(comp)
    return nil unless comp.is_a?(Sketchup::ComponentInstance)
    definition = comp.definition
    parent = comp.parent
    transformation = comp.transformation
    group = parent.entities.add_group
    group.entities.add_instance(definition, IDENTITY).explode
    group.layer = comp.layer
    group.material = comp.material
    group.transformation = transformation
    copy_behavior(group.definition.behavior, definition.behavior)
    copy_attributes(group, comp)
    copy_attributes(group.definition, definition)
    comp.erase!
    group
  end
  def self.group_to_component(input_group)
    source_group = input_group.first
    source_component = source_group.to_component
    replacement = source_component.definition
    new_instances = [source_component]
    input_group[1..-1].each do |instance|
      definition = instance.entities.parent
      dsx = definition.bounds.width / replacement.bounds.width
      dsy = definition.bounds.height / replacement.bounds.height
      dsz = definition.bounds.depth / replacement.bounds.depth
      dts = Geom::Transformation.scaling(dsx, dsy, dsz)
      pt1 = replacement.bounds.corner(0)
      pt2 = definition.bounds.corner(0)
      v1 = pt1.vector_to(ORIGIN)
      v2 = ORIGIN.vector_to(pt2)
      t1 = Geom::Transformation.new(v1)
      t2 = Geom::Transformation.new(v2)
      t = instance.transformation
      nt = t * t2 * dts * t1 * t.inverse
      ents = instance.parent.entities
      tr = nt * instance.transformation
      new_instance = ents.add_instance(replacement, tr)
      new_instance.material = instance.material
      instance.erase!
      new_instances << new_instance
    end
    new_instances
  end
  def self.center_origin(group)
    MH::Panel.start
    MH::Geo::Axes.center_origin(group)
    MH::Panel.commit
  end
  def self.find_origin(edges)
    pts = edges.flat_map(&:vertices).uniq.map(&:position)
    pts.sort_by!(&:z)
    pts.select! { |pt| pt.z == pts.first.z }
    pts.sort_by!(&:y)
    pts.select! { |pt| pt.y == pts.first.y }
    pts.size == 1 ? pts.first : pts.sort_by(&:x).last
  end
  def self.find_edge_vectors(edges, origin)
    edges.select! { |e| e.vertices.any? { |v| v.position == origin } }
    edges.map { |e| origin.vector_to(e.other_vertex(e.vertices.find { |v| v.position == origin }).position) }
  end
  def self.select_lowest_vectors(vecs_with_length, origin)
    vecs = vecs_with_length.map(&:normalize)
    pts_from_vecs = vecs.map { |v| origin.offset(v) }
    pts_from_vecs.sort_by!(&:z)
    selected = vecs.select { |v| pts_from_vecs[0..1].include?(origin.offset(v)) }
    selected.length < 2 ? vecs[0..1] : selected
  end
  def self.find_longest_vector(vecs_with_length, selected_normalized)
    selected_with_length = vecs_with_length.select do |v|
      next false if v.length < 0.001
      normalized = v.normalize
      selected_normalized.any? { |sv| (normalized.x - sv.x).abs < 0.001 && (normalized.y - sv.y).abs < 0.001 && (normalized.z - sv.z).abs < 0.001 }
    end
    selected_with_length = vecs_with_length.select { |v| v.length >= 0.001 } if selected_with_length.empty?
    selected_with_length.sort_by! { |v| -v.length }
    selected_with_length.first&.normalize || X_AXIS
  end
  def self.calculate_axes(xaxis, second_vec)
    xaxis = xaxis.length > 0.001 ? xaxis.normalize : X_AXIS
    zaxis = xaxis.cross(second_vec)
    if zaxis.length < 0.001
      perpendicular = [X_AXIS, Y_AXIS, Z_AXIS].find { |a| xaxis.cross(a).length > 0.001 }
      zaxis = xaxis.cross(perpendicular)
    end
    zaxis = zaxis.normalize
    yaxis = zaxis.cross(xaxis).normalize
    [xaxis, yaxis, zaxis]
  end
  def self.reset_axes(group, tu_dong_xoay_van = false)
    MH::Panel.start
    MH::Geo::Axes.reset_axes(group, tu_dong_xoay_van)
    MH::Panel.commit
  end
  def self.fix_scale(group)
    return unless MH::Panel.is_container?(group)
    MH::Panel.start
    MH::Geo::Axes.fix_scale(group)
    MH::Panel.commit
  end
end

# encoding: utf-8
# MH_PK_Addon — phu kien tinh theo chieu dai (md).
# Marker giong het PK so luong (statistical object 'hardware' — khong vao nesting);
# chieu dai luu o MH_Thongke/length-mm|length-m|length-source, ABF/unit = 'md'.

module MH_PK_Addon
  LENGTH_SOURCE_LONGEST_EDGE = 'longest_edge'.freeze

  # Chieu dai lon nhat cua target theo he toa do the gioi (mm).
  def self.target_longest_dimension_mm(target, world_tr = nil)
    return MH::Measure.target_longest_dimension_mm(target, world_tr) if defined?(MH::Measure)

    0.0
  rescue
    0.0
  end

  # Ghi de attr chieu dai sau set_marker_attributes. Chi de ABF/unit, giu nguyen attr khac.
  def self.apply_length_attrs(marker, length_mm, source = LENGTH_SOURCE_LONGEST_EDGE)
    return unless live_entity?(marker)

    mm = length_mm.to_f.round(1)
    marker.set_attribute('MH_Thongke', 'measure-type', 'length')
    marker.set_attribute('MH_Thongke', 'length-mm', mm)
    marker.set_attribute('MH_Thongke', 'length-m', (mm / 1000.0).round(3))
    marker.set_attribute('MH_Thongke', 'length-source', source.to_s)
    marker.set_attribute('ABF', 'unit', 'md')
    marker
  rescue
    nil
  end

  def self.length_pk_marker?(entity)
    pk_marker?(entity) && entity.get_attribute('MH_Thongke', 'measure-type').to_s == 'length'
  rescue
    false
  end

  # Row excel co kieu chieu dai? (type='length' hoac co length_items)
  def self.length_excel_row?(row)
    raw = row.is_a?(Hash) ? (row[:raw] || row['raw'] || row) : row
    return false unless raw.is_a?(Hash)

    type = (raw['type'] || raw[:type]).to_s.strip.downcase
    return true if type == 'length'

    items = raw['length_items'] || raw[:length_items]
    !Array(items).empty?
  rescue
    false
  end

  def self.excel_row_length_mm(row)
    return MH::Measure.excel_row_length_mm(row) if defined?(MH::Measure)

    0.0
  rescue
    0.0
  end

  # Add PK do dai vao moi target dang chon: 1 marker/target, dai = canh dai nhat cua target.
  # Goi tu dialog.rb (Add PK theo canh dai nhat).
  def self.add_length_accessory_to_selection(raw_data)
    mdl = nil
    original_selection = []
    with_mh_thongke_mini_suspended do
      data = normalized_data(raw_data)
      mdl = model
      original_selection = live_selection(mdl)
      targets = selected_targets
      raise 'Chon Group/Component dich truoc khi add PK.' if targets.empty?

      added = []
      affected = []
      total_length_mm = 0.0

      mdl.start_operation('MH PK Add Length', true)
      targets.each do |target|
        world_tr = entity_world_transform(target)
        target.make_unique if target.is_a?(Sketchup::ComponentInstance) && target.respond_to?(:make_unique)
        ensure_abf_board_attributes(target)
        ents = target_entities(target)
        next unless ents

        face = placement_face(ents, world_tr)
        next unless face

        face_tr = face_transform(face)
        next unless face_tr

        length_mm = data[:length_mm].to_f
        length_mm = target_longest_dimension_mm(target, world_tr) if length_mm <= 0
        next if length_mm <= 0

        target_data = data.dup
        detected_product = detect_product_code(target)
        target_data[:product_code] = product_code_base(detected_product) unless detected_product.to_s.empty?
        target_data[:ten_sp] = detect_ten_sp(target) if target_data[:ten_sp].to_s.strip.empty?
        target_data[:face_normal] = face.normal.to_s
        target_data[:target_persistent_id] = target.persistent_id rescue nil

        size = marker_size_inches(target_data[:size_mm])
        transform = free_marker_transform(ents, face, face_tr, size)
        transform = unscaled_local_transform(transform, world_tr)
        marker = create_marker_group(ents, transform, target_data)
        next unless marker

        source = data[:length_mm].to_f > 0 ? data[:length_source].to_s : LENGTH_SOURCE_LONGEST_EDGE
        source = LENGTH_SOURCE_LONGEST_EDGE if source.empty?
        apply_length_attrs(marker, length_mm, source)
        trace_record_add(marker, target_data)
        added << marker
        affected << target
        total_length_mm += length_mm
      end

      raise 'Khong co object hop le de gan PK do dai.' if added.empty?

      mdl.commit_operation
      restore_selection(mdl, original_selection)
      refresh_abf_statistics
      { count: added.length, targets: affected.length, length_mm: total_length_mm }
    end
  rescue => e
    model.abort_operation rescue nil
    restore_selection(mdl, original_selection) rescue nil
    raise e
  end
end

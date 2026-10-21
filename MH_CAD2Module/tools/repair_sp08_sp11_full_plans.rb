# frozen_string_literal: true

# One-time repair, guarded against any later user edits or source changes.
app = MH::CAD2Module
model = Sketchup.active_model
raise 'Wrong working model' unless Process.pid == 23_252 && model.path.empty?
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings.library
data = %w[SP08 SP11].to_h { |code| [code, JSON.parse(File.read(File.join(app::Settings::ROOT, "outputs/#{code.downcase}-full-plans.json"), encoding: 'UTF-8'))] }
source_hash = 'c48b8576c7f1e7e8b029c1ea103b935a8efa71bb499efb3d3be8eae2c336f3f2'
raise 'Source changed' unless data.values.all? { |p| p['source_hash'] == source_hash } && Digest::SHA256.file(data['SP08']['source_path']).hexdigest == source_hash
owned = app::Model.products.select { |a| data.key?(a.get_attribute(app::Model::DICT, 'code')) }
expected_ids = %w[assembly-28023c5d-467b-fd7f-1b5c-0a91f4dc8ef7 assembly-b09a852c-e436-76a3-571d-4c321ad9758f]
raise 'Unexpected existing results' unless owned.map(&:persistent_id).sort == expected_ids.sort
before = {}; references = {}; centers = {}
owned.each do |a|
  old = JSON.parse(a.get_attribute(app::Model::DICT, 'analysis'))
  code = old['code']; before[a.persistent_id] = { 'analysis' => old, 'state' => app::Model.state(a) }
  raise 'Unexpected source' unless old['source_hash'] == source_hash
  labels = app::Model.labels(model).select { |label| label['code'] == code }
  raise 'Label ambiguous' unless labels.length == 1
  centers[code] = labels.first['center_x']
  expected_transform = Geom::Transformation.translation((app::Placement.named_origin(old, centers[code]) + [0]).map(&:mm))
  raise 'User moved result' unless a.transformation.to_a.zip(expected_transform.to_a).all? { |x, y| (x - y).abs < 0.0001 }
  ref = model.find_entity_by_persistent_id(a.get_attribute(app::Model::DICT, 'plan_reference_id'))
  raise 'Reference moved/missing' unless ref && ref.transformation.to_a == a.transformation.to_a
  references[a.persistent_id] = ref
  state = before[a.persistent_id]['state']
  %w[modules trim_parts panel_parts].each do |kind|
    raise 'User changed part count' unless state[kind].length == Array(old[kind]).length
    state[kind].each do |part|
      source = old[kind].find { |p| p['id'] == part['id'] }
      raise 'User edited a result' unless source && %w[origin size].all? { |key| part[key].zip(source[key]).all? { |x, y| (x - y).abs < 0.01 } }
    end
  end
  if code == 'SP08'
    raise 'Not the reported clipped preview' unless old['plan_view_id'] == 'V05.1' && old['envelope_preview'] && old['bounds'] == [2036, 230, 1600]
  else
    target = data[code]['plan_results'].first
    raise 'Accepted SP11 geometry changed' unless old['plan_view_id'] == 'V01.1' && old['signature'] == target['signature'] && old.dig('experience', 'event') == target.dig('experience', 'event')
    %w[modules trim_parts panel_parts].each do |kind|
      raise 'SP11 learned grouping changed' unless Array(old[kind]).map { |p| p.slice('id', 'origin', 'size') } == Array(target[kind]).map { |p| p.slice('id', 'origin', 'size') }
    end
  end
end
affected_ids = (owned.flat_map(&:members) + references.values).map(&:persistent_id)
baseline = model.entities.reject { |e| affected_ids.include?(e.persistent_id) }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
repair_id = app::Ids.uuid
owned.each do |a|
  record = before[a.persistent_id]
  record['skp'] = app::Storage.snapshot(root, a, "#{repair_id}-#{record['analysis']['code']}-before")
  ref_path = File.join(root, 'skp', "#{repair_id}-#{record['analysis']['code']}-cad-before.skp")
  raise 'Reference backup failed' unless references[a.persistent_id].definition.save_as(ref_path)
  record['reference_skp'] = ref_path
end
app::Storage.write_json(File.join(root, 'repairs', "#{repair_id}-full-plans-before.json"), before)
operations = %i[start_operation commit_operation abort_operation].to_h { |key| [key, [model.method(key), model.singleton_class.instance_methods(false).include?(key)]] }
operations[:start_operation][0].call('CAD2Module: Sửa CAD SP08 Và Bổ Sung Chữ L SP11', true)
built = []; committed = false
begin
  operations.each_key { |key| model.define_singleton_method(key) { |*_args| true } }
  data.each do |code, product|
    previous = owned.find { |a| a.get_attribute(app::Model::DICT, 'code') == code }
    old = before[previous.persistent_id]['analysis']
    product['plan_results'].each do |target|
      target['activity_id'] = target['plan_view_id'] == old['plan_view_id'] ? old['activity_id'] : app::Ids.uuid
      if code == 'SP11' && target['plan_view_id'] == old['plan_view_id']
        previous.transformation = Geom::Transformation.translation((app::Placement.named_origin(target, centers[code]) + [0]).map(&:mm))
        references[previous.persistent_id].transformation = previous.transformation
        target.merge!(old.slice('native_times', 'build_auxiliary'))
        previous.set_attribute(app::Model::DICT, 'analysis', JSON.generate(target))
        built << previous
      else
        if code == 'SP08' && target['plan_view_id'] == old['plan_view_id']
          references[previous.persistent_id].erase!
          previous.erase!
        end
        built << app::Model.build(target, root, repair_id, model)
      end
    end
  end
  new_ids = (built.flat_map(&:members) + built.map { |a| model.find_entity_by_persistent_id(a.get_attribute(app::Model::DICT, 'plan_reference_id')) }).map(&:persistent_id)
  raise 'Other geometry changed' unless baseline == model.entities.reject { |e| affected_ids.include?(e.persistent_id) || new_ids.include?(e.persistent_id) }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
  result = data.keys.map do |code|
    members = built.select { |a| a.get_attribute(app::Model::DICT, 'code') == code }.sort_by { |a| JSON.parse(a.get_attribute(app::Model::DICT, 'analysis'))['display_layout']['index'] }
    refs = members.map { |a| model.find_entity_by_persistent_id(a.get_attribute(app::Model::DICT, 'plan_reference_id')) }
    gaps = refs.each_cons(2).map { |a, b| b.bounds.min.x.to_mm - a.bounds.max.x.to_mm }
    raise 'Incorrect gap' unless gaps.all? { |gap| (gap - 1000).abs < 0.02 }
    { code: code, count: members.length, reference_sizes_mm: refs.map { |ref| [ref.bounds.width.to_mm, ref.bounds.height.to_mm] }, gaps_mm: gaps }
  end
  operations[:commit_operation][0].call
  committed = true
ensure
  operations.each { |key, (method, own)| own ? model.define_singleton_method(key, method) : model.singleton_class.send(:remove_method, key) }
  operations[:abort_operation][0].call unless committed
end
built.each do |a|
  analysis = JSON.parse(a.get_attribute(app::Model::DICT, 'analysis'))
  app::Storage.event(root, 'kind' => 'recognition_repair', 'status' => analysis['status'], 'analysis' => analysis,
                    'product_id' => a.persistent_id, 'repair_id' => repair_id,
                    'reason' => 'SP08 giữ đủ biên vát; SP11 bổ sung mặt cắt4-4 và hai mặt bằng chữ L không có tiêu đề. Giữ mẫu đúng đã xác nhận của3-3.')
end
app.instance_variable_set(:@analyses, [{ 'products' => data.values, 'diagnostics' => [], 'revision' => { 'original_path' => data['SP08']['source_path'] } }])
app.instance_variable_set(:@focused, 'SP11')
app.instance_variable_set(:@activity_focus, { model: model, key: app::Activity.key(data['SP11']['plan_results'][2]) })
app.instance_variable_set(:@last_built, { model: model, ids: built.map(&:persistent_id) })
model.selection.clear; model.selection.add(built.select { |a| a.get_attribute(app::Model::DICT, 'code') == 'SP11' }.flat_map(&:members))
app.publish('Đã sửa SP08:2 mặt bằng đủ nét. SP11:4 mặt bằng, gồm2 chữ L; khối mới chưa chia đủ dùng khung bao tạm1600 mm. Nhập một mã ở một ô, hoặc hai mã đầu/cuối để dựng dải SP.')
receipt = { passed: true, products: result, other_geometry_unchanged: true, accepted_sp11_groups_preserved: true, snapshots_preserved: true, model_saved: false, repair_id: repair_id }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs/full-plans-live-result.json'), receipt)
puts JSON.generate(receipt)

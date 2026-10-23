# frozen_string_literal: true

# One-time repair of the verified seven unchanged auto-generated SP04 previews.
# Never use this as a general recogniser or repeat it after manual corrections.
app = MH::CAD2Module
model = Sketchup.active_model
raise 'Wrong working model' unless Process.pid == 23_252 && model.path.empty?
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
data = JSON.parse(File.read(File.join(app::Settings::ROOT, 'outputs/detail-plans-sp04.json'), encoding: 'UTF-8'))
source_hash = 'c48b8576c7f1e7e8b029c1ea103b935a8efa71bb499efb3d3be8eae2c336f3f2'
raise 'Source changed' unless data['source_hash'] == source_hash && Digest::SHA256.file(data['source_path']).hexdigest == source_hash
targets = data.fetch('plan_results').to_h { |p| [p.fetch('plan_view_id'), p] }
raise 'Unexpected plans' unless targets.keys == %w[V01.1 V02.1 V06.1]
owned = app::Model.products.select { |a| a.get_attribute(app::Model::DICT, 'code') == 'SP04' }
raise 'SP04 already repaired or membership changed' unless owned.length == 7
labels = app::Model.labels(model).select { |l| l['code'] == 'SP04' }
raise 'Label ambiguous' unless labels.length == 1
center = labels.first['center_x']
refs = {}
before = {}
owned.each do |a|
  old = JSON.parse(a.get_attribute(app::Model::DICT, 'analysis'))
  raise 'Different source or manually corrected' unless old['source_hash'] == source_hash && old['envelope_preview']
  state = app::Model.state(a)
  raise 'Part membership changed' unless a.members.length == 1 && state['modules'].length == 1 && a.members.first.manifold?
  part = state['modules'].first
  raise 'User edited preview dimensions' unless part['origin'].all? { |x| x.abs < 0.01 } && part['size'].zip(old['bounds']).all? { |x, y| (x - y).abs < 0.01 }
  expected = Geom::Transformation.translation((app::Placement.named_origin(old, center) + [0]).map(&:mm))
  raise 'User moved preview' unless a.transformation.to_a.zip(expected.to_a).all? { |x, y| (x - y).abs < 0.0001 }
  ref = model.find_entity_by_persistent_id(a.get_attribute(app::Model::DICT, 'plan_reference_id'))
  raise 'Missing/moved reference' unless ref && ref.transformation.to_a == a.transformation.to_a
  refs[a.persistent_id] = ref
  before[a.persistent_id] = { 'analysis' => old, 'state' => state }
end
raise 'Unexpected detail set' unless before.values.map { |v| v['analysis']['plan_view_id'] }.sort == %w[V01.1 V01.2 V01.3 V01.4 V02.1 V02.2 V06.1]
affected = owned.flat_map(&:members) + refs.values
affected_ids = affected.map(&:persistent_id)
baseline = model.entities.reject { |e| affected_ids.include?(e.persistent_id) }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
root = app::Settings.library
repair_id = app::Ids.uuid
before.each do |id, record|
  a = owned.find { |item| item.persistent_id == id }
  record['skp'] = app::Storage.snapshot(root, a, "#{repair_id}-#{record['analysis']['plan_view_id']}-before")
  ref_path = File.join(root, 'skp', "#{repair_id}-#{record['analysis']['plan_view_id']}-cad-before.skp")
  raise 'Reference backup failed' unless refs[id].definition.save_as(ref_path)
  record['reference_skp'] = ref_path
end
app::Storage.write_json(File.join(root, 'repairs', "#{repair_id}-sp04-before.json"), before)
kept = []; removed = []
model.start_operation('CAD2Module: Bỏ Mặt Cắt Trích SP04', true)
begin
  owned.each do |a|
    old = before.fetch(a.persistent_id)['analysis']
    target = targets[old['plan_view_id']]
    if target
      target.merge!(old.slice('activity_id', 'native_times', 'build_auxiliary'))
      a.transformation = Geom::Transformation.translation((app::Placement.named_origin(target, center) + [0]).map(&:mm))
      refs[a.persistent_id].transformation = a.transformation
      a.set_attribute(app::Model::DICT, 'analysis', JSON.generate(target))
      kept << a
    else
      refs[a.persistent_id].erase!
      removed << a.persistent_id
      a.erase!
    end
  end
  raise 'Other geometry changed' unless baseline == model.entities.reject { |e| affected_ids.include?(e.persistent_id) }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
  gaps = kept.sort_by { |a| targets[a.get_attribute(app::Model::DICT, 'plan_view_id')]['display_layout']['index'] }.map { |a| refs[a.persistent_id] }.each_cons(2).map { |a, b| b.bounds.min.x.to_mm - a.bounds.max.x.to_mm }
  raise 'Gap incorrect' unless gaps.all? { |x| (x - 1000).abs < 0.01 }
  model.commit_operation
rescue StandardError
  model.abort_operation
  raise
end
before.each do |id, record|
  old = record['analysis']
  target = targets[old['plan_view_id']]
  analysis = target || old.merge('status' => 'excluded_detail', 'view_analysis' => data['view_analysis'])
  reason = target ? 'Đối chiếu lại SP04; giữ mặt bằng toàn SP và xếp cách1000 mm.' : 'Đã loại mặt cắt trích/chi tiết bị gán nhầm thành mặt bằng toàn SP; lệch kích thước từ50%.'
  app::Storage.event(root, 'kind' => 'recognition_repair', 'status' => target ? 'ready' : 'excluded_detail',
                    'analysis' => analysis, 'product_id' => id, 'reason' => reason, 'repair_id' => repair_id,
                    'before' => record['skp'], 'reference_before' => record['reference_skp'], 'model_path' => model.path)
end
app.instance_variable_set(:@analyses, [{ 'products' => [data], 'diagnostics' => [], 'revision' => { 'original_path' => data['source_path'] } }])
app.instance_variable_set(:@focused, 'SP04')
app.instance_variable_set(:@activity_focus, { model: model, key: app::Activity.key(targets.values.first) })
app.instance_variable_set(:@last_built, { model: model, ids: kept.map(&:persistent_id) })
model.selection.clear; model.selection.add(kept.flat_map(&:members))
app.publish('Đã sửa SP04: giữ3 mặt bằng5-5/4-4/6-6, loại4 hình chi tiết, khoảng trống1000 mm. Các khối vẫn là khung bao tạm, cao1600 mm.')
result = { passed: true, kept: kept.map(&:persistent_id), removed: removed, clear_gaps_mm: gaps,
           other_geometry_unchanged: true, repair_id: repair_id, snapshots_preserved: true, model_saved: false }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs/detail-plans-live-result.json'), result)
puts JSON.generate(result)

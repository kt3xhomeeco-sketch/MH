# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Wrong working model' unless Process.pid == 2724 && model.path == 'E:\\MAC\\OneDrive\\Desktop\\1.skp'
raise 'Busy/editing' if app::Jobs.busy? || model.active_path
session = app::Corrections.instance_variable_get(:@session)
raise 'Expected original SP41 manual session' unless session && session[:manual] && session[:id] == '25e5d56a-b397-a5dd-9323-511706885338'
raise 'Session already upgraded' if session[:analysis]['source_plan_envelope']
product = session[:product]
analysis = JSON.parse(File.read(File.join(app::Settings::ROOT, 'outputs', 'sp41-arc-analysis.json'), encoding: 'UTF-8'))
raise 'Wrong source' unless analysis['source_hash'] == session[:analysis]['source_hash'] && analysis['bounds'] == [2860, 350, 1600]
raise 'Source anchor changed' unless analysis['placement'] == session[:analysis]['placement']
source = model.find_entity_by_persistent_id(975803)
raise 'Source missing' unless source && source.valid?
edges = []
app::ManualBoxes.collect_edges(source.definition.entities, source.transformation, edges)
lines = edges.map { |e| e.map { |p| p.to_a.map(&:to_mm)[0, 2] } }
request = JSON.parse(File.read(File.join(app::Settings::ROOT, 'library', 'jobs', 'fc73be53-27e7-9eb1-2122-e371eaa409be', 'request.json'), encoding: 'UTF-8'))
match = lambda { |a, b| a.zip(b).all? { |u, v| (u - v).abs < 0.01 } }
raise 'CAD changed since scan' unless lines.length == 111 && request['geometry']['lines'].all? do |row|
  lines.any? { |a, b| (match.call(a, row['a']) && match.call(b, row['b'])) || (match.call(b, row['a']) && match.call(a, row['b'])) }
end
baseline = model.entities.map { |e| [e.persistent_id, e.transformation.to_a, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] if app::Model.container?(e) }.compact
selection = model.selection.map(&:persistent_id)
old_analysis = JSON.parse(product.get_attribute(app::Model::DICT, 'analysis'))
root = session[:root]; id = app::Ids.uuid
before = app::Storage.snapshot(root, product, "#{id}-profile-before")
model.start_operation('CAD2Module: Cập Nhật Biên Nguồn SP41', true)
begin
  product.set_attribute(app::Model::DICT, 'analysis', JSON.generate(analysis))
  after = app::Storage.snapshot(root, product, "#{id}-profile-after")
  event = app::Storage.event(root, 'id' => id, 'kind' => 'recognition_update', 'session' => session[:id],
    'reason' => 'Đã hỗ trợ bo cong; cập nhật biên nguồn SP41 rộng 2860 mm', 'source_hash' => analysis['source_hash'],
    'before_analysis' => old_analysis, 'analysis' => analysis, 'skp_before' => before, 'skp' => after,
    'resolves_errors' => ['ea2d00ff-a37c-e5bb-1b37-6bcd3708a1e0', '2fed3fef-ea43-9159-da02-6d70c961508f'])
  model.commit_operation
rescue StandardError
  model.abort_operation
  raise
end
session[:analysis] = analysis
analyses = app.instance_variable_get(:@analyses)
Array(analyses).each do |row|
  Array(row['products']).map! { |p| p['source_hash'] == analysis['source_hash'] ? analysis : p }
end
app.instance_variable_set(:@manual_acceptance, nil)
errors = app.instance_variable_get(:@errors)
Array(errors).reject! { |e| %w[22:33:23 22:33:50].include?(e['time']) && (e['error'].start_with?('Box đang xoay thật') || e['error'].start_with?('Box đúng rộng/sâu 2860.0')) }
raise 'Geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.transformation.to_a, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] if app::Model.container?(e) }.compact
raise 'Selection changed' unless selection == model.selection.map(&:persistent_id)
result = { 'status' => 'upgraded', 'session_id' => session[:id], 'product_id' => product.persistent_id,
           'source_bounds_mm' => analysis['bounds'], 'history_id' => event['id'], 'user_result_not_accepted' => true,
           'geometry_and_selection_unchanged' => true }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'sp41-profile-session-upgrade.json'), result)
app.publish('Đã nâng cấp bo cong R100 và đo đủ SP41 rộng 2860 mm. Chọn cả 4 khối mày vẽ rồi bấm Kết quả đúng.')
puts JSON.generate(result)

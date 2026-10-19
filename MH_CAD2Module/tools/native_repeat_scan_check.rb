# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
analysis = app.products.find do |p|
  p['automatic_scan'] && (p['status'] == 'ready' || p['envelope_preview']) &&
    app::Model.products(model).any? { |r| JSON.parse(r.get_attribute(app::Model::DICT, 'analysis'))['source_hash'] == p['source_hash'] }
end
raise 'No previously built scan available for regression' unless analysis
app::SelectionSource.validate_watch(analysis['source_watch'], model) if analysis['source_watch']
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
selection = model.selection.to_a
originals = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
qa_root = 'E:/MH_CAD2Module_QA/AI/tests/repeat-scan-native'
receipts = []
originals[:start_operation][0].call('CAD2Module: Kiểm Tra Giữ Box Và Quét Lại', true)
begin
  originals.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  preview = JSON.parse(File.read(File.join(root, 'outputs', 'envelope-preview-fixture.json'), encoding: 'UTF-8'))
  [analysis, preview].each do |template|
    inputs = 2.times.map do
      Marshal.load(Marshal.dump(template)).merge('code' => "SCAN-QA-#{app::Ids.uuid.upcase}", 'activity_id' => app::Ids.uuid)
    end
    built = inputs.map { |p| app::Model.build(p, qa_root, app::Ids.uuid, model) }
    raise 'Repeated scans shared product identity' unless built.map(&:persistent_id).uniq.length == 2
    raise 'Repeated scans shared visible Groups' unless (built[0].members & built[1].members).empty?
    raise 'A repeat did not create solids' unless built.all? { |p| p.members.all? { |g| g.is_a?(Sketchup::Group) && g.parent == model && g.manifold? } }
    built.each do |product|
      model.selection.clear; model.selection.add(product.members)
      raise 'Selection bound to another scan' unless app::Model.selected_product(model).persistent_id == product.persistent_id
    end
    rows = app::Activity.rows(qa_root, built)
    identities = built.map { |p| p.get_attribute(app::Model::DICT, 'activity_id') }
    raise 'History/correction identity merged by source hash' unless identities.uniq.length == 2 && identities.all? { |key| rows.any? { |r| r['key'] == key && r['available'] } }
    count = model.entities.length
    begin
      app::Model.build(inputs.first, qa_root, app::Ids.uuid, model)
      raise 'Same scan ID was built twice'
    rescue ArgumentError => error
      raise 'Wrong duplicate callback rejection' unless error.message.include?('đã được dựng') && model.entities.length == count
    end
    receipts << { preview: !!template['envelope_preview'], independent_products: 2, old_groups_kept: true,
                  separate_selection_and_history: true, duplicate_callback_blocked: true }
  end
ensure
  originals.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  originals[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'QA registry leaked' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
result = { passed: true, cases: receipts, user_geometry_unchanged: true }
app::Storage.write_json(File.join(root, 'outputs', 'repeat-scan-native-result.json'), result)
puts JSON.generate(result)

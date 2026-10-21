# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
%w[cad_views.rb plan_reference.rb product_labels.rb product_requests.rb].each { |name| load File.join(root, name) }
app::Model.send(:remove_const, :DICT); load File.join(root, 'model.rb')
%w[manual_boxes.rb corrections.rb main.rb].each { |name| load File.join(root, name) }
data = JSON.parse(File.read(File.join(root, 'outputs/cad-levels-products.json'), encoding: 'UTF-8'))
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h; layers = model.layers.map(&:name); selection = model.selection.to_a
sha = Digest::SHA256.file(model.path).hexdigest unless model.path.empty?
read = app::Settings.method(:read); settings = read.call(model)
ivars = %i[@last_built @manual_acceptance @activity_focus @history_product @focus_cad @manager @entry].to_h { |key| [key, app.instance_variable_get(key)] }
publish = app.method(:publish)
methods = %i[start_operation commit_operation abort_operation].to_h { |key| [key, [model.method(key), model.singleton_class.instance_methods(false).include?(key)]] }
methods[:start_operation][0].call('CAD2Module: Kiểm Tra Cao Độ Và Sửa Trực Tiếp', true)
result = {}; qa_root = File.join(root, 'outputs/qle'); job = app::Ids.uuid
begin
  methods.each_key { |key| model.define_singleton_method(key) { |*_args| true } }
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('library' => qa_root, 'import_plan_reference' => false) }
  app.define_singleton_method(:publish) { |*_args, **_keys| true }
  app.instance_variable_set(:@manager, nil); app.instance_variable_set(:@entry, nil)
  code = app::Model.labels(model).any? { |v| v['code'] == 'D1' } ? 'D900001' : 'D1'
  built = data['plan_results'].map do |p|
    p['code'] = code; p['activity_id'] = app::Ids.uuid
    app::Model.build(p, qa_root, job, model)
  end
  refs = built.map { |p| model.find_entity_by_persistent_id(p.get_attribute(app::Model::DICT, 'plan_reference_id')) }
  raise 'Missing shared reference' unless refs.all? { |g| g.is_a?(Sketchup::Group) && g.parent == model }
  raise 'Incorrect CAD levels' unless refs.map { |g| g.bounds.min.z.to_mm.round(3) } == [700, 1700]
  raise 'Plans not stacked at same XY' unless refs[0].bounds.min.to_a.first(2).zip(refs[1].bounds.min.to_a.first(2)).all? { |a, b| (a - b).abs < 0.0001 } && refs[0].bounds.max.to_a.first(2).zip(refs[1].bounds.max.to_a.first(2)).all? { |a, b| (a - b).abs < 0.0001 }
  cad_ids = built[0].get_attribute(app::Model::DICT, 'cad_reference_ids')
  raise 'Duplicate plan generated' unless cad_ids.include?(refs[1].persistent_id) && cad_ids.uniq.length == cad_ids.length
  raise 'Wrong tag' unless refs.all? { |g| g.layer.name == 'MH_DWG' }
  raise 'Generic label not found' unless app::Model.labels(model).count { |v| v['code'] == code } == 1
  app.instance_variable_set(:@last_built, { model: model, ids: [built[0].persistent_id] })
  model.selection.clear; model.selection.add(built[1].members)
  app.dispatch('action' => 'entry_workflow', 'operation' => 'wrong')
  raise 'Entry reused stale product' unless app::Corrections.status['product_id'] == built[1].persistent_id
  raise 'Sai hid boxes' if built.any?(&:hidden?)
  app.dispatch('action' => 'entry_workflow', 'operation' => 'cancel_manual_boxes')
  model.selection.clear; model.selection.add(built[0].members)
  app.dispatch('action' => 'entry_workflow', 'operation' => 'wrong')
  cad_before = refs.map { |g| [g.persistent_id, g.transformation.to_a, g.bounds.min.to_a, g.bounds.max.to_a] }
  owned = built[0].members; before_origin = owned.first.bounds.min.to_a
  owned.first.transformation *= Geom::Transformation.scaling(1, 1, 1650.0 / 1600)
  model.selection.clear; model.selection.add(built[1].members)
  begin
    app::ManualBoxes.capture(model, built[0], model.selection.to_a)
    raise 'Accepted another product'
  rescue ArgumentError => error
    raise unless error.message.include?('sản phẩm khác')
  end
  model.selection.clear; model.selection.add(owned)
  session = app::Corrections.status['id']
  app.dispatch('action' => 'entry_workflow', 'operation' => 'accept_manual_boxes', 'request_id' => 'QA-INPLACE', 'session_id' => session)
  ack = app.instance_variable_get(:@manual_acceptance)
  raise 'In-place result not accepted' unless ack['status'] == 'saved' && !app::Corrections.active? && built[0].members.none?(&:hidden?)
  heights = app::Model.state(built[0])['modules'].map { |m| m['size'][2] }
  raise 'Edited height lost' unless heights.sort == [1600, 1650]
  raise 'Box jumped' unless built[0].members.first.bounds.min.to_a.zip(before_origin).all? { |a, b| (a - b).abs < 0.0001 }
  raise 'CAD moved during acceptance' unless cad_before == refs.map { |g| [g.persistent_id, g.transformation.to_a, g.bounds.min.to_a, g.bounds.max.to_a] }
  result = { passed: true, levels_mm: [700, 1700], same_xy: true, independent_root_views: true, no_duplicate_reference: true,
             generic_code: code, entry_targets_current_selection: true, sai_keeps_boxes_visible: true, edited_owned_boxes_accepted: true,
             foreign_product_rejected: true, accepted_heights_mm: heights, source_cad_unchanged: true }
ensure
  if app::Corrections.active?
    model.remove_observer(app::Corrections.instance_variable_get(:@observer))
    app::Corrections.instance_variable_set(:@session, nil)
  end
  app::Settings.define_singleton_method(:read, read); app.define_singleton_method(:publish, publish)
  ivars.each { |key, value| app.instance_variable_set(key, value) }
  methods.each { |key, (method, owned)| owned ? model.define_singleton_method(key, method) : model.singleton_class.send(:remove_method, key) }
  methods[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User state changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] } && registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h && layers == model.layers.map(&:name) && settings == read.call(model)
raise 'User file changed' if sha && sha != Digest::SHA256.file(model.path).hexdigest
result[:user_model_selection_settings_registry_tags_file_preserved] = true
app::Storage.write_json(File.join(root, 'outputs/levels-entry-native-result.json'), result)
puts JSON.generate(result)

# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
app::Settings.send(:remove_const, :DEFAULTS)
app::Settings.send(:remove_const, :DICT)
app::Settings.send(:remove_const, :ROOT)
load File.join(root, 'settings.rb')
app::Model.send(:remove_const, :DICT)
load File.join(root, 'model.rb')
fixtures = JSON.parse(File.read(File.join(root, 'outputs/product-plan-native-fixtures.json')))
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
layers = model.layers.map(&:name)
selection = model.selection.to_a
settings_read = app::Settings.method(:read)
settings_owned = app::Settings.singleton_class.instance_methods(false).include?(:read)
settings = settings_read.call
qa_root = 'E:/MH_CAD2Module_QA/AI/tests/product-plan-0120/native'
originals = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
originals[:start_operation][0].call('CAD2Module: Kiểm Tra Mặt Bằng Đi Kèm', true)
results = []
begin
  originals.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('import_plan_reference' => true, 'build_auxiliary' => true) }
  fixtures.each_with_index do |fixture, i|
    data = fixture['product']; code = "SP#{9000 + i}"
    data['code'] = code
    label = model.entities.add_group
    label.entities.add_line([0, 0, 0], [2.mm, 0, 0])
    label.transformation = Geom::Transformation.translation([(120_000 + i * 10_000).mm, 8000.mm, 0])
    label.set_attribute('Curic Single-Line Text', 'text', code)
    product = app::Model.build(data, qa_root, app::Ids.uuid, model)
    reference = model.find_entity_by_persistent_id(product.get_attribute(app::Model::DICT, 'plan_reference_id'))
    raise 'No independent CAD Group' unless reference.is_a?(Sketchup::Group) && reference.parent == model && !product.members.include?(reference)
    raise 'Reference placement changed' unless reference.transformation.to_a == product.transformation.to_a
    raise 'Reference not flat on XOY' unless reference.bounds.depth.to_mm.abs < 0.001 && reference.bounds.min.z.to_mm.abs < 0.001
    raise 'Reference contains faces' unless reference.entities.grep(Sketchup::Face).empty?
    raise 'Reference tag missing' unless reference.layer.name == 'MH_DWG'
    raise 'Source metadata missing' unless reference.get_attribute(app::Model::DICT, 'view_id') == data.dig('view_analysis', 'selected_view_id')
    raise 'Wrong label centre' unless (product.transformation.origin.x.to_mm + data['bounds'][0] / 2 - label.bounds.center.x.to_mm).abs < 0.01
    raise 'Module selection includes reference' if app::Model.selection_entities(product).include?(reference)
    raise 'Modules not solid/independent' unless product.members.all? { |e| e.is_a?(Sketchup::Group) && e.parent == model && e.manifold? }
    actual = app::Model.state(product)['modules']
    raise 'Measured size changed' unless actual.zip(data['modules']).all? { |a, b| a['size'].zip(b['size']).all? { |x, y| (x - y).abs < 0.01 } }
    if fixture['name'] == 'curved-plan'
      raise 'CAD corner is not ArcCurve' unless reference.entities.grep(Sketchup::Edge).any? { |e| e.curve.is_a?(Sketchup::ArcCurve) }
    end
    app::Corrections.begin_manual(product)
    raise 'Sai hid CAD reference' if reference.hidden?
    raise 'Sai hid editable modules' if product.hidden?
    app::Corrections.cancel_manual
    raise 'Cancel left modules hidden' if product.hidden?
    results << { source: fixture['name'], cad_edges: reference.entities.grep(Sketchup::Edge).length,
                 modules: actual.length, dimensions: true, label_placement: true, correction_reference_visible: true }
  end
  off = Marshal.load(Marshal.dump(fixtures[0]['product'])); off['code'] = 'SP9999'
  label = model.entities.add_group; label.entities.add_line([0, 0, 0], [1.mm, 0, 0])
  label.set_attribute('Curic Single-Line Text', 'text', off['code'])
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('import_plan_reference' => false) }
  product = app::Model.build(off, qa_root, app::Ids.uuid, model)
  raise 'Import toggle ignored' if product.get_attribute(app::Model::DICT, 'plan_reference_id')
ensure
  observer = app::Corrections.instance_variable_get(:@observer)
  model.remove_observer(observer) if observer
  app::Corrections.instance_variable_set(:@session, nil)
  settings_owned ? app::Settings.define_singleton_method(:read, settings_read) : app::Settings.singleton_class.send(:remove_method, :read)
  originals.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  originals[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'User registry changed' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
raise 'User tags changed' unless layers == model.layers.map(&:name)
raise 'Settings changed' unless settings == settings_read.call
receipt = { passed: true, cases: results, import_toggle: true, user_geometry_registry_tags_settings_unchanged: true }
app::Storage.write_json(File.join(root, 'outputs/product-plan-native-result.json'), receipt)
puts JSON.generate(receipt)

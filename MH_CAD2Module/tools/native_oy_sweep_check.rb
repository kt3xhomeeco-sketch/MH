# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
load File.join(root, 'placement.rb')
app::Model.send(:remove_const, :DICT)
load File.join(root, 'model.rb')
%w[activity.rb main.rb].each { |file| load File.join(root, file) }
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
selection = model.selection.to_a
settings_read = app::Settings.method(:read)
settings = settings_read.call
qa_root = 'E:/MH_CAD2Module_QA/AI/tests/oy-sweep-0110/native'
fixtures = JSON.parse(File.read(File.join(root, 'outputs/oy-sweep-native-fixtures.json')))
originals = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
originals[:start_operation][0].call('CAD2Module: Kiểm Tra Bộ Quét OY', true)
results = []
begin
  originals.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('build_auxiliary' => true) }
  fixtures.each do |fixture|
    data = fixture['product']; data['code'] = "QA-#{app::Ids.uuid}"
    product = app::Model.build(data, qa_root, app::Ids.uuid, model)
    expected = data['modules'].length + data['trim_parts'].length
    raise 'Groups not independent/solid' unless product.members.length == expected && product.members.all? { |g| g.is_a?(Sketchup::Group) && g.parent == model && g.manifold? }
    saved = JSON.parse(product.get_attribute(app::Model::DICT, 'analysis'))
    raise 'Missing measured preflight/timings' unless saved.dig('geometry_check', 'passed') && saved.dig('native_times', 'groups')
    app::Model.state(product)['modules'].zip(data['modules']).each do |actual, measured|
      raise 'Native dimensions changed' unless actual['size'].zip(measured['size']).all? { |a, b| (a - b).abs < 0.01 }
    end
    if fixture['name'] == 'sp41_plan_edges'
      raise 'ArcCurve missing' unless product.members.any? { |g| g.entities.grep(Sketchup::Edge).any? { |e| e.curve.is_a?(Sketchup::ArcCurve) } }
    end
    results << { source: fixture['name'], independent_solids: expected, preflight: true, native_times: saved['native_times'] }
  end
  data = fixtures.find { |f| f['name'] == 'recessed_trim_plan_edges' }['product']
  data['code'] = "QA-#{app::Ids.uuid}"
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('build_auxiliary' => false) }
  without = app::Model.build(data, qa_root, app::Ids.uuid, model)
  raise 'Auxiliary switch ignored' unless without.members.length == 3
  app::Settings.define_singleton_method(:read, settings_read)
  product = app::Model.product_by_id(model, results.empty? ? nil : without.persistent_id)
  app::Corrections.begin_manual(product)
  inputs = 2.times.map do |i|
    box = app::Model.cube(model.entities, 'id' => "Q#{i}", 'origin' => [992.5 * i, 23.986, 0], 'size' => [992.5, 598, 1600])
    box.transformation = product.transformation * box.transformation
    box
  end
  expected = inputs.map { |g| [g.bounds.min.to_a, g.bounds.max.to_a] }.sort.flatten
  model.selection.clear; model.selection.add(inputs)
  event = app::Corrections.accept_manual
  actual = product.members.map { |g| [g.bounds.min.to_a, g.bounds.max.to_a] }.sort.flatten
  raise 'Manual Y changed' unless expected.zip(actual).all? { |a, b| (a - b).abs < 0.001 } && (event['plan_origin_offset_mm'][1] - 23.986).abs < 0.001
  forged = Marshal.load(Marshal.dump(fixtures[0]['product'])); forged['modules'][0]['size'][0] += 10
  rejected = false
  begin
    app::Placement.validate_oy_product(forged)
  rescue ArgumentError
    rejected = true
  end
  raise 'Forged measured dimensions accepted' unless rejected
ensure
  model.remove_observer(app::Corrections.instance_variable_get(:@observer))
  app::Corrections.instance_variable_set(:@session, nil)
  app::Settings.define_singleton_method(:read, settings_read)
  originals.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  originals[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'User registry changed' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
raise 'Settings changed' unless settings == settings_read.call
receipt = { passed: true, cases: results, auxiliary_toggle: true, selected_box_y_preserved: true, forged_dimensions_rejected: true, user_geometry_unchanged: true }
app::Storage.write_json(File.join(root, 'outputs/oy-sweep-native-result.json'), receipt)
puts JSON.generate(receipt)

# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Wait for current work' if app::Jobs.busy? || app::Corrections.active? || model.active_path
product = JSON.parse(File.read(File.join(app::Settings::ROOT, 'outputs', 'sp40-repaired-product.json'), encoding: 'UTF-8'))
product['automatic_scan'] = false
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
selection = model.selection.to_a
originals = %i[start_operation commit_operation abort_operation].to_h do |name|
  [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]]
end
results = []
originals[:start_operation][0].call('CAD2Module: Kiểm Tra Khối Phụ', true)
begin
  originals.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  [true, false].each do |enabled|
    model.set_attribute(app::Settings::DICT, 'settings', JSON.generate(app::Settings.read(model).merge('build_auxiliary' => enabled)))
    product['code'] = "NATIVE-AUXILIARY-#{enabled}"
    built = app::Model.build(product, File.join(app::Settings::ROOT, 'outputs', 'v'), app::Ids.uuid, model)
    state = app::Model.state(built)
    raise 'Part count changed' unless state['modules'].length == 3 && state['trim_parts'].length == (enabled ? 2 : 0)
    state['modules'].each_with_index do |part, i|
      raise 'Module dimensions/positions changed' unless %w[origin size].all? { |key| part[key].zip(product['modules'][i][key]).all? { |a, b| (a - b).abs < 0.01 } }
    end
    trims = built.definition.entities.select { |e| e.get_attribute(app::Model::DICT, 'role') == 'trim_reference' }
    trims.each do |trim|
      raise 'Not a closed solid' unless trim.manifold? && trim.definition.entities.grep(Sketchup::Face).length == 6
      raise 'Wrong trim volume' unless (trim.volume * (25.4**3) - 18 * 170 * 1600).abs < 0.1
    end
    analysis = JSON.parse(built.get_attribute(app::Model::DICT, 'analysis'))
    raise 'Recognized evidence erased by setting' unless analysis['trim_parts'].length == 2 && analysis['bounds'] == product['bounds']
    raise 'Build option not recorded' unless analysis['build_auxiliary'] == enabled
    results << { 'enabled' => enabled, 'trims' => trims.length, 'solid_volumes_mm3' => trims.map { |e| (e.volume * (25.4**3)).round(3) },
                 'module_origins_mm' => state['modules'].map { |m| m['origin'] }, 'transform' => built.transformation.to_a }
  end
  raise 'Setting moved product' unless results[0]['transform'] == results[1]['transform']
ensure
  originals.each do |name, (method, owned)|
    owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name)
  end
  originals[:abort_operation][0].call
  model.selection.clear
  model.selection.add(selection.select(&:valid?))
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
result = { 'status' => 'passed', 'cases' => results, 'original_geometry_unchanged' => true }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'auxiliary-native-result.json'), result)
puts JSON.generate(result)

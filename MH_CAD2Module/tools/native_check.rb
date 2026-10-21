# frozen_string_literal: true

# Run through the already-connected VBO bridge. Never save/replace the active model.
require 'json'
plugin = File.expand_path('..', __dir__)
load File.join(plugin, '..', 'MH_CAD2Module.rb') unless defined?(MH::CAD2Module::VERSION)
require File.join(plugin, 'main')
app = MH::CAD2Module
model = Sketchup.active_model
baseline = model.entities.map(&:persistent_id).sort
selection = model.selection.to_a
active_path = model.active_path
raise 'Exit edit context before native verification' if active_path
root = File.join(plugin, 'outputs', 'native')
FileUtils.mkdir_p(root)
input = JSON.parse(File.read(File.join(plugin, 'outputs', 'actual-analysis.json'), encoding: 'UTF-8'))
source = input.fetch('products').find { |p| p['code'] == 'SP60' }
label = app::Model.labels.find { |row| app::Model.products.none? { |p| p.get_attribute(app::Model::DICT, 'code') == row['code'] } }
raise 'No free product label available for reversible check' unless label
product = nil
operations = 0
result = {}
begin
  invalid = JSON.parse(JSON.generate(source))
  invalid['code'] = label['code']
  invalid['modules'] = [invalid['modules'].first, invalid['modules'].first]
  begin
    app::Model.build(invalid, root, 'overlap-guard-check', model)
    raise 'Overlapping modules were built'
  rescue ArgumentError => error
    raise unless error.message.include?('chồng nhau')
  end
  raise 'Overlap rejection changed model' unless model.entities.map(&:persistent_id).sort == baseline
  product = app::Model.build(source.merge('code' => label['code']), root, 'native-check', model)
  operations += 1
  state = app::Model.state(product)
  raise 'Module count' unless state['modules'].length == 3
  state['modules'].each_with_index do |mod, i|
    expected = [[860, 600, 2110], [860, 600, 2110], [1720, 600, 432]][i]
    raise 'Measured native size' unless 3.times.all? { |axis| (mod['size'][axis] - expected[axis]).abs < 0.1 }
  end
  measured = product.bounds.center.x.to_mm
  raise 'Label centre mismatch' unless (measured - label['center_x']).abs < 0.1
  raise 'Offset Z' unless state['modules'].map { |mod| mod['origin'][2] } == [50.0, 50.0, 2160.0]
  joint = state['modules'].last.fetch('joint_evidence')
  raise 'Missing cross-view seam evidence' unless joint['section_no_cut'] && !joint['front_handles'].empty?
  app::Corrections.begin_session(product, 'Native regression check')
  original = product.definition.entities.find { |e| e.get_attribute(app::Model::DICT, 'role') == 'module' }
  model.selection.clear
  model.selection.add(original)
  app::Corrections.split(0, 430)
  operations += 1
  raise 'Split count' unless app::Model.state(product)['modules'].length == 4
  split = product.definition.entities.select { |e| e.get_attribute(app::Model::DICT, 'module_id').to_s.start_with?('M-') }
  model.selection.clear
  model.selection.add(split)
  app::Corrections.merge
  operations += 1
  raise 'Merge count' unless app::Model.state(product)['modules'].length == 3
  target = product.definition.entities.find { |e| e.get_attribute(app::Model::DICT, 'role') == 'module' }
  template = app::Storage.snapshot(root, target, 'compatible-template')
  model.selection.clear
  model.selection.add(target)
  app::Templates.replace(template)
  operations += 1
  raise 'Template replacement lost module' unless app::Model.state(product)['modules'].length == 3
  app::Corrections.finish
  operations += 1
  result['status'] = 'passed'
  result['label'] = label
  result['modules'] = state['modules']
  result['bounds_mm'] = [product.bounds.width, product.bounds.height, product.bounds.depth].map(&:to_mm)
  result['centre_x_mm'] = measured
  result['history_events'] = Dir.glob(File.join(root, 'history', '*.json')).length
ensure
  if app::Corrections.active?
    session = app::Corrections.instance_variable_get(:@session)
    model.remove_observer(app::Corrections.instance_variable_get(:@observer))
    app::Corrections.instance_variable_set(:@session, nil)
  end
  model.active_path = nil
  operations.times { Sketchup.undo }
  model.selection.clear
  model.selection.add(selection.select(&:valid?))
  result['model_unchanged'] = model.entities.map(&:persistent_id).sort == baseline
  app::Storage.write_json(File.join(root, 'result.json'), result)
end
raise 'Native check changed original model entities' unless result['model_unchanged']
puts JSON.generate(result)

# frozen_string_literal: true

plugin = File.expand_path('..', __dir__)
app = MH::CAD2Module
model = Sketchup.active_model
source = JSON.parse(File.read(File.join(plugin, 'outputs', 'sp01-plan-first.json'), encoding: 'UTF-8'))
baseline = model.entities.map(&:persistent_id).sort
selection = model.selection.to_a
label = app::Model.labels.find { |row| app::Model.products.none? { |p| p.get_attribute(app::Model::DICT, 'code') == row['code'] } }
raise 'No free label for native verification' unless label
operations = 0
result = {}
begin
  product = app::Model.build(source.merge('code' => label['code']), File.join(plugin, 'outputs', 'native-plan-first'), 'plan-first-check', model)
  operations += 1
  state = app::Model.state(product)
  expected = [[729,600,2200],[1502,600,2150],[681,600,443],[1502,600,443]]
  raise 'Module count' unless state['modules'].length == 4
  state['modules'].each_with_index do |mod,i|
    raise 'Native module dimensions' unless 3.times.all? { |axis| (mod['size'][axis]-expected[i][axis]).abs < 0.1 }
  end
  raise 'Trim was treated as module' unless state['trim_parts'].length == 3
  trims = product.definition.entities.select { |e| e.get_attribute(app::Model::DICT, 'role') == 'trim_reference' }
  raise 'Trim should be a wire reference' unless trims.all? { |e| e.definition.entities.grep(Sketchup::Face).empty? }
  auxiliary = state['trim_parts'].select { |p| p['owner_module_id'] == 'M03' }
  raise 'Missing module auxiliary parts' unless auxiliary.length == 2 && auxiliary.all? { |p| p['size'] == [24.0,18.0,443.0] }
  raise 'Module including doors position' unless state['modules'][2]['origin'] == [24.0,0.0,2200.0]
  raise 'Product centring including trim' unless (product.bounds.center.x.to_mm-label['center_x']).abs < 0.1
  raise 'Product width including trim' unless (product.bounds.width.to_mm-2255).abs < 0.1
  app::Corrections.begin_session(product, 'Native plan-first / separate-trim regression')
  app::Corrections.finish
  operations += 1
  raise 'Correction lost trim extent' unless app::Model.state(product)['bounds'][0] == 2255.0
  raise 'Correction changed centre' unless (product.bounds.center.x.to_mm-label['center_x']).abs < 0.1
  result = {'status'=>'passed','modules'=>state['modules'],'trim_parts'=>state['trim_parts'],
            'bounds'=>state['bounds'],'center_x'=>product.bounds.center.x.to_mm}
ensure
  if app::Corrections.active?
    model.remove_observer(app::Corrections.instance_variable_get(:@observer))
    app::Corrections.instance_variable_set(:@session,nil)
  end
  operations.times { Sketchup.undo }
  model.selection.clear
  model.selection.add(selection.select(&:valid?))
  result['model_unchanged'] = model.entities.map(&:persistent_id).sort == baseline
  app::Storage.write_json(File.join(plugin,'outputs','native-plan-first-result.json'),result)
end
raise 'Native verification changed source model' unless result['model_unchanged']
puts JSON.generate(result.slice('status','bounds','center_x','model_unchanged'))

# frozen_string_literal: true

plugin = File.expand_path('..', __dir__)
app = MH::CAD2Module
app::Jobs.cancel if app::Jobs.busy?
%w[model corrections main].each { |name| load File.join(plugin, name + '.rb') }
app.scan('targets' => ['SP01']) do |job|
  source = app.products.find { |p| p['code'] == 'SP01' }
  raise "SP01: #{source && source['error']}" unless source && source['status'] == 'ready'
  app::Storage.write_json(File.join(plugin, 'outputs', 'sp01-plan-first.json'), source)
  load File.join(plugin, 'tools', 'native_plan_first_check.rb')
  model = job[:model]
  product = app::Model.products(model).find { |p| p.get_attribute(app::Model::DICT, 'code') == 'SP01' }
  product ||= app::Model.build(source, job[:root], job[:id], model)
  model.selection.clear
  model.selection.add(product)
  model.active_view.zoom(product)
  event = app::Storage.event(job[:root], 'kind'=>'recognition_rule','status'=>'accepted','code'=>'SP01',
    'reason'=>'Chia dọc từ mặt bằng rồi chia tầng ngang; mặt đứng có cánh chỉ đối chiếu. Nẹp 24 mm là ván 18 quay mặt ra, tách riêng khỏi module.',
    'source_hash'=>source['source_hash'],'analysis'=>source,'after'=>app::Model.state(product),
    'material_standards_mm'=>[6,8,12,15,18,25,36],'lamination_candidates'=>{'36'=>[18,18]})
  app::Storage.write_json(File.join(job[:root], 'rules', 'material-priors.json'),
    {'source'=>'User feedback 2026-10-18','board_thicknesses_mm'=>[6,8,12,15,18,25,36],
     'lamination_candidates'=>{'36'=>[18,18]},'turned_exterior_trim'=>{'face_mm'=>24,'stock_mm'=>18,'requires_plan_witness'=>true}})
  app.instance_variable_set(:@focused, 'SP01')
  app.instance_variable_set(:@focus_cad, false)
  app.instance_variable_get(:@manager)&.close
  app.instance_variable_set(:@manager, nil)
  app.manager
  app.publish('Đã dựng SP01: 4 khối module từ mặt bằng → chia ngang; nẹp 24/ván 18 để riêng dạng khung đối chiếu.')
  model.active_view.write_image(File.join(plugin, 'outputs', 'sp01-built.png'))
  app::Storage.write_json(File.join(plugin, 'outputs', 'sp01-plan-first-built.json'),
    {'status'=>'passed','job_id'=>job[:id],'version'=>source['parser_version'],'entity_id'=>product.persistent_id,
     'state'=>app::Model.state(product),'centre_x'=>product.bounds.center.x.to_mm,'history'=>event['path']})
end
puts 'Started target-only SP01 plan-first scan and verified construction'

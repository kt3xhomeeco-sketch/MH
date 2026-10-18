# frozen_string_literal: true

# Explicit repair of the user's reported M03 error; never overwrite other modules.
plugin = File.expand_path('..', __dir__)
app = MH::CAD2Module
raise 'Finish the active correction first' if app::Corrections.active?
raise 'A scan is already running' if app::Jobs.busy?
%w[model main].each { |name| load File.join(plugin, name + '.rb') }
app.scan('targets' => ['SP01']) do |job|
  begin
    source = app.products.find { |p| p['code'] == 'SP01' }
    raise "SP01: #{source && source['error']}" unless source && source['status'] == 'ready'
    raise 'Unexpected parser version' unless source['parser_version'] == '0.2.1'
    app::Storage.write_json(File.join(plugin, 'outputs', 'sp01-plan-first.json'), source)
    load File.join(plugin, 'tools', 'native_plan_first_check.rb')
    model = job[:model]
    product = app::Model.products(model).find { |p| p.get_attribute(app::Model::DICT, 'code') == 'SP01' }
    raise 'SP01 missing, shared or currently being edited' unless product && product.definition.instances.length == 1 && !model.active_path
    before = app::Model.state(product)
    target = product.definition.entities.find { |e| e.get_attribute(app::Model::DICT, 'module_id') == 'M03' }
    old = before['modules'].find { |m| m['id'] == 'M03' }
    raise 'M03 has changed since the report' unless old && old['size'] == [729.0,600.0,443.0] && old['origin'] == [0.0,0.0,2200.0]
    expected = JSON.parse(product.get_attribute(app::Model::DICT, 'analysis'))
    raise 'Wrong source' unless expected['source_hash'] == source['source_hash']
    raise 'Unexpected existing auxiliary parts' unless before['trim_parts'].length == 1
    before['modules'].reject { |m| m['id'] == 'M03' }.each do |mod|
      planned = source['modules'].find { |m| m['id'] == mod['id'] }
      raise "#{mod['id']} was edited; preserve it for review" unless planned && %w[size origin].all? { |k| mod[k] == planned[k] }
    end
    labels = app::Model.labels(model)
    roots = model.entities.map(&:persistent_id).sort
    transform = product.transformation.to_a
    id = app::Ids.uuid
    root = product.get_attribute(app::Model::DICT, 'library')
    reason = 'Người dùng xác nhận hai nẹp 24 hai bên module trên trái là phần phụ; tách khỏi thùng M03 theo vách/nóc/đáy thực và mặt cắt.'
    snapshot = app::Storage.snapshot(root, product, "#{id}-before")
    report = app::Storage.event(root, 'kind'=>'error_report','status'=>'unresolved','session'=>id,
      'reason'=>reason,'analysis'=>expected,'before'=>before,'skp'=>snapshot)
    model.start_operation('CAD2Module: tách hai nẹp phụ module trên trái', true)
    operation = true
    refined = source['modules'].find { |m| m['id'] == 'M03' }
    temporary = app::Model.cube(product.definition.entities, refined)
    target.definition = temporary.definition
    target.transformation = temporary.transformation
    target.set_attribute(app::Model::DICT, 'source_module', JSON.generate(refined))
    temporary.erase!
    source['trim_parts'].select { |p| p['owner_module_id'] == 'M03' }.each do |part|
      app::Model.reference_part(product.definition.entities, part)
    end
    product.set_attribute(app::Model::DICT, 'analysis', JSON.generate(source))
    product.set_attribute(app::Model::DICT, 'job_id', job[:id])
    after = app::Model.state(product)
    raise 'Other modules changed' unless before['modules'].reject { |m| m['id'] == 'M03' } == after['modules'].reject { |m| m['id'] == 'M03' }
    raise 'Existing trim changed' unless before['trim_parts'].first == after['trim_parts'].first
    raise 'Product moved' unless transform == product.transformation.to_a
    raise 'Labels or other roots changed' unless labels == app::Model.labels(model) && roots == model.entities.map(&:persistent_id).sort
    raise 'M03 dimensions' unless after['modules'].find { |m| m['id'] == 'M03' }['size'] == [681.0,582.0,443.0]
    raise 'Auxiliary count' unless after['trim_parts'].count { |p| p['owner_module_id'] == 'M03' } == 2
    raise 'Centre changed' unless (product.bounds.center.x.to_mm - labels.find { |l| l['code'] == 'SP01' }['center_x']).abs < 0.1
    snapshot = app::Storage.snapshot(root, product, "#{id}-accepted")
    event = app::Storage.event(root, 'kind'=>'correction','status'=>'accepted','session'=>id,
      'reason'=>reason,'resolves_event'=>report['id'],'signature'=>source['signature'],
      'parser_version'=>source['parser_version'],'source_hash'=>source['source_hash'],
      'analysis'=>source,'before'=>before,'after'=>after,'skp'=>snapshot)
    app::Storage.experience(root, event)
    model.commit_operation
    operation = false
    model.selection.clear
    model.selection.add(product)
    model.active_view.zoom(product)
    app.instance_variable_set(:@focused, 'SP01')
    app.instance_variable_set(:@focus_cad, false)
    app.instance_variable_get(:@manager)&.close
    app.instance_variable_set(:@manager, nil)
    app.manager
    app.publish('Đã sửa M03: 681 × 582 × 443 mm; hai nẹp mặt 24/ván 18 là phần phụ liên kết M03.')
    model.active_view.write_image(File.join(plugin, 'outputs', 'sp01-built.png'))
    app::Storage.write_json(File.join(plugin, 'outputs', 'upper-left-repair-result.json'),
      {'status'=>'passed','version'=>source['parser_version'],'entity_id'=>product.persistent_id,
       'state'=>after,'other_modules_unchanged'=>true,'labels_unchanged'=>true,
       'history'=>event['path'],'centre_x'=>product.bounds.center.x.to_mm})
  rescue StandardError => error
    model.abort_operation if operation
    app::Storage.write_json(File.join(plugin, 'outputs', 'upper-left-repair-result.json'),
      {'status'=>'failed','error'=>error.message,'backtrace'=>error.backtrace.first(6)})
    app.publish("Chưa sửa SP01: #{error.message}")
  end
end
puts 'Scanning SP01 and checking the targeted auxiliary-trim repair.'

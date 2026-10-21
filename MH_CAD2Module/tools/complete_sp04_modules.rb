# frozen_string_literal: true

begin
  app = MH::CAD2Module
  plugin = app::Settings::ROOT
  %w[model corrections main].each { |name| load File.join(plugin,"#{name}.rb") }
  model = Sketchup.active_model
  raise 'Finish active job/correction or group editing first' if app::Jobs.busy? || app::Corrections.active? || model.active_path
  source = JSON.parse(File.read(File.join(plugin,'outputs','sp04-eleven-modules.json'),encoding:'UTF-8'))
  inspected = JSON.parse(File.read(File.join(plugin,'outputs','sp04-before-three-modules.json'),encoding:'UTF-8'))
  product = app::Model.products.find { |p| p.get_attribute(app::Model::DICT,'code')=='SP04' }
  before = app::Model.state(product)
  ordered = ->(state) { state.merge('trim_parts'=>state['trim_parts'].sort_by { |p| p['id'] }) }
  raise 'SP04 changed since inspection' unless ordered.call(before)==ordered.call(inspected['state']) && product.persistent_id==inspected['entity_id']
  baseline = model.entities.map(&:persistent_id).sort
  labels = app::Model.labels(model)
  selection = model.selection.to_a
  free = labels.find { |l| app::Model.products.none? { |p| p.get_attribute(app::Model::DICT,'code')==l['code'] } }
  raise 'No free label for native check' unless free
  operations = 0
  begin
    probe = app::Model.build(source.merge('code'=>free['code']),File.join(plugin,'outputs','n'),'eleven-module-check',model)
    operations += 1
    state = app::Model.state(probe)
    wall = state['modules'].find { |m| m['id']=='M11' }
    raise 'Native assembly count' unless state['modules'].length==11 && state['panel_parts'].empty? && wall['panel_parts'].length==23
    source['modules'].each do |expected|
      actual = state['modules'].find { |m| m['id']==expected['id'] }
      raise "Native dimensions #{expected['id']}" unless %w[size origin].all? { |k| 3.times.all? { |i| (actual[k][i]-expected[k][i]).abs<0.1 } }
    end
    app::Corrections.begin_session(probe,'Native check: bases and detailed wall are modules')
    app::Corrections.finish
    operations += 1
    raise 'Nested parts lost in correction' unless app::Model.state(probe)['modules'].find { |m| m['id']=='M11' }['panel_parts'].length==23
  ensure
    if app::Corrections.active?
      model.remove_observer(app::Corrections.instance_variable_get(:@observer))
      app::Corrections.instance_variable_set(:@session,nil)
    end
    operations.times { Sketchup.undo }
    if probe&.valid? && probe.get_attribute(app::Model::DICT,'job_id')=='eleven-module-check'
      model.start_operation('CAD2Module: xóa bản kiểm tra tạm',true)
      probe.erase!
      model.commit_operation
    end
    model.selection.clear
    model.selection.add(selection.select(&:valid?))
  end
  raise 'Native check changed original roots' unless baseline==model.entities.map(&:persistent_id).sort
  root = product.get_attribute(app::Model::DICT,'library')
  session = app::Ids.uuid
  snapshot = app::Storage.snapshot(root,product,"#{session}-before")
  report = app::Storage.event(root,'kind'=>'error_report','status'=>'unresolved','code'=>'SP04','reason'=>'Thiếu hai module dài ở dưới M01–M02, M03–M04 và một module vách giữa.','before'=>before,'analysis'=>inspected['analysis'],'skp'=>snapshot)
  model.start_operation('CAD2Module: bổ sung 3 module SP04',true)
  operation = true
  entities = product.definition.entities
  raise 'Shared product definition' unless product.definition.instances.length==1
  source['modules'].select { |m| %w[M09 M10].include?(m['id']) }.each { |m| app::Model.cube(entities,m) }
  bases = entities.select { |e| e.get_attribute(app::Model::DICT,'role')=='trim_reference' && JSON.parse(e.get_attribute(app::Model::DICT,'source_part'))['role']=='common_base' }
  raise 'Missing original base references' unless bases.length==2
  entities.erase_entities(bases)
  panels = entities.select { |e| e.get_attribute(app::Model::DICT,'role')=='panel_part' }
  raise 'Wall parts changed' unless panels.length==23
  wall_mod = source['modules'].find { |m| m['id']=='M11' }
  target_transform = Geom::Transformation.translation(wall_mod['origin'].map(&:mm))
  definition = model.definitions.add('CAD2Module_M11_Wall')
  panels.each do |entity|
    copy = definition.entities.add_instance(entity.definition,target_transform.inverse*entity.transformation)
    copy.name = entity.name
    copy.material = entity.material
    copy.layer = entity.layer
    copy.hidden = entity.hidden?
    entity.attribute_dictionaries&.each { |dict| dict.each_pair { |key,value| copy.set_attribute(dict.name,key,value) } }
  end
  group = entities.add_instance(definition,target_transform)
  group.name = wall_mod['name']
  group.set_attribute(app::Model::DICT,'role','module')
  group.set_attribute(app::Model::DICT,'module_id','M11')
  group.set_attribute(app::Model::DICT,'source_module',JSON.generate(wall_mod))
  group.definition.entities.each do |entity|
    part_id = JSON.parse(entity.get_attribute(app::Model::DICT,'source_part'))['id']
    part = wall_mod['panel_parts'].find { |p| p['id']==part_id }
    entity.set_attribute(app::Model::DICT,'source_part',JSON.generate(part))
    entity.set_attribute(app::Model::DICT,'owner_module_id','M11')
  end
  entities.erase_entities(panels)
  product.set_attribute(app::Model::DICT,'analysis',JSON.generate(source))
  after = app::Model.state(product)
  raise "Module count #{after['modules'].length}, root panels #{after['panel_parts'].length}, nested #{after['modules'].find { |m| m['id']=='M11' }&.dig('panel_parts')&.length}" unless after['modules'].length==11 && after['panel_parts'].empty?
  raise 'Original modules changed' unless before['modules']==after['modules'].select { |m| before['modules'].any? { |old| old['id']==m['id'] } }
  actual_wall = after['modules'].find { |m| m['id']=='M11' }
  before['panel_parts'].each do |part|
    nested = actual_wall['panel_parts'].find { |p| p['id']==part['id'] }
    raise 'Wall geometry moved' unless 3.times.all? { |i| (nested['origin'][i]+actual_wall['origin'][i]-part['origin'][i]).abs<0.1 && (nested['size'][i]-part['size'][i]).abs<0.1 }
  end
  raise 'Product moved' unless before['product_transform']==after['product_transform'] && labels==app::Model.labels(model)
  raise 'Label centre' unless (product.bounds.center.x.to_mm-labels.find { |l| l['code']=='SP04' }['center_x']).abs<0.1
  snapshot = app::Storage.snapshot(root,product,"#{session}-accepted")
  event = app::Storage.event(root,'kind'=>'correction','status'=>'accepted','code'=>'SP04','session'=>session,
    'resolves_event'=>report['id'],'parser_version'=>source['parser_version'],'signature'=>source['signature'],
    'source_hash'=>source['source_hash'],'reason'=>'Người dùng xác nhận 11 module; gom vách cùng tấm/nẹp thành một module, hai khối chân đế là module dài.',
    'analysis'=>source,'before'=>before,'after'=>after,'skp'=>snapshot)
  app::Storage.experience(root,event)
  model.commit_operation
  operation = false
  Array(app.instance_variable_get(:@analyses)).each { |a| a['products'].map! { |p| p['code']=='SP04' ? source : p } }
  app.instance_variable_set(:@focused,'SP04')
  app.instance_variable_set(:@focus_cad,false)
  app.instance_variable_set(:@history_product,nil)
  model.selection.clear
  model.selection.add(product)
  model.active_view.zoom(product)
  app.instance_variable_get(:@manager)&.close
  app.instance_variable_set(:@manager,nil)
  app.manager
  app.publish('SP04 đủ 11 module: 8 module tủ, 2 module dài phía dưới và module vách chứa nguyên các tấm/nẹp.')
  model.active_view.write_image(File.join(plugin,'outputs','sp04-eleven-built.png'))
  app::Storage.write_json(File.join(plugin,'outputs','sp04-eleven-native.json'),{'status'=>'passed','entity_id'=>product.persistent_id,
    'state'=>after,'original_modules_unchanged'=>true,'wall_parts_unchanged'=>true,'centre_x'=>product.bounds.center.x.to_mm,'history'=>event['path']})
  puts JSON.generate({'status'=>'passed','modules'=>after['modules'].length,'nested_parts'=>actual_wall['panel_parts'].length,'centre_x'=>product.bounds.center.x.to_mm})
rescue StandardError => error
  model.abort_operation if operation
  app::Storage.write_json(File.join(plugin,'outputs','sp04-eleven-native.json'),{'status'=>'failed','error'=>error.message,'backtrace'=>error.backtrace.first(6)})
  raise
end

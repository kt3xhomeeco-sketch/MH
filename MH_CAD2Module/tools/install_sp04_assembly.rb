# frozen_string_literal: true

begin
plugin = File.expand_path('..', __dir__)
app = MH::CAD2Module
raise 'Finish current job/correction first' if app::Jobs.busy? || app::Corrections.active?
%w[model corrections main].each { |name| load File.join(plugin, name + '.rb') }
response = JSON.parse(File.read(File.join(plugin,'outputs','assembly-response.json'),encoding:'UTF-8'))
raise 'Source analysis failed' unless response['ok'] && response['errors'].empty?
source01 = response['analyses'].flat_map { |a| a['products'] }.find { |p| p['code']=='SP01' }
source04 = JSON.parse(File.read(File.join(plugin,'outputs','sp04-geometry-recipe.json'),encoding:'UTF-8'))
raise 'Wrong SP01 analysis' unless source01['status']=='ready' && source01['parser_version']=='0.2.2'
model = Sketchup.active_model
raise 'Exit group editing first' if model.active_path
baseline = model.entities.map(&:persistent_id).sort
labels = app::Model.labels(model)
selection = model.selection.to_a
raise 'SP04 already exists' if app::Model.products.any? { |p| p.get_attribute(app::Model::DICT,'code')=='SP04' }
free = labels.find { |l| !%w[SP01 SP04].include?(l['code']) && app::Model.products.none? { |p| p.get_attribute(app::Model::DICT,'code')==l['code'] } }
raise 'No free label for native test' unless free
operations = 0
begin
  probe = app::Model.build(source04.merge('code'=>free['code']),File.join(plugin,'outputs','n'),'native-sp04',model)
  operations += 1
  state = app::Model.state(probe)
  raise 'Native SP04 module/part count' unless state['modules'].length==8 && state['panel_parts'].length==23
  (state['modules']+state['panel_parts']).each do |part|
    expected = (source04['modules']+source04['panel_parts']).find { |p| p['id']==part['id'] }
    raise "Size/position #{part['id']}" unless %w[size origin].all? { |key| 3.times.all? { |i| (part[key][i]-expected[key][i]).abs<0.1 } }
    entity = probe.definition.entities.find { |e| e.persistent_id==part['entity_id'] }
    raise "Non-solid #{part['id']}" unless entity.manifold? && entity.volume.positive?
  end
  raise 'Product centre' unless (probe.bounds.center.x.to_mm-free['center_x']).abs<0.1
  app::Corrections.begin_session(probe,'Native check: panels stay separate; module includes doors')
  app::Corrections.finish
  operations += 1
  raise 'Panel parts lost after correction' unless app::Model.state(probe)['panel_parts'].length==23
ensure
  if app::Corrections.active?
    model.remove_observer(app::Corrections.instance_variable_get(:@observer))
    app::Corrections.instance_variable_set(:@session,nil)
  end
  operations.times { Sketchup.undo }
  if probe&.valid? && probe.get_attribute(app::Model::DICT,'job_id')=='native-sp04'
    model.start_operation('CAD2Module: xóa bản kiểm tra tạm',true)
    probe.erase!
    model.commit_operation
  end
  model.selection.clear
  model.selection.add(selection.select(&:valid?))
end
raise 'Native test changed source model' unless baseline==model.entities.map(&:persistent_id).sort
root = app::Settings.library
product01 = app::Model.products.find { |p| p.get_attribute(app::Model::DICT,'code')=='SP01' }
before = app::Model.state(product01)
old = JSON.parse(File.read(File.join(plugin,'outputs','before-sp04.json'),encoding:'UTF-8'))['products'].find { |p| p['code']=='SP01' }['state']
raise 'SP01 edited since scan' unless before['modules']==old['modules'] && before['trim_parts']==old['trim_parts'] && before['product_transform']==old['product_transform']
session = app::Ids.uuid
snapshot = app::Storage.snapshot(root,product01,"#{session}-before")
report = app::Storage.event(root,'kind'=>'error_report','status'=>'unresolved','code'=>'SP01','reason'=>'Module phải bao gồm cả thùng và cánh.','before'=>before,'skp'=>snapshot)
model.start_operation('CAD2Module: module bao gồm thùng và cánh',true)
operation = true
source01['modules'].each do |mod|
  entity = product01.definition.entities.find { |e| e.get_attribute(app::Model::DICT,'module_id')==mod['id'] }
  measured = before['modules'].find { |m| m['id']==mod['id'] }
  unless %w[size origin].all? { |key| measured[key]==mod[key] }
    temporary = app::Model.cube(product01.definition.entities,mod)
    entity.definition = temporary.definition
    entity.transformation = temporary.transformation
    temporary.erase!
  end
  entity.set_attribute(app::Model::DICT,'source_module',JSON.generate(mod))
end
product01.set_attribute(app::Model::DICT,'analysis',JSON.generate(source01))
after = app::Model.state(product01)
raise 'Module depth/front' unless after['modules'].all? { |m| m['size'][1]==600.0 && m['origin'][1]==0.0 }
raise 'Trim changed' unless before['trim_parts']==after['trim_parts']
snapshot = app::Storage.snapshot(root,product01,"#{session}-accepted")
event01 = app::Storage.event(root,'kind'=>'correction','status'=>'accepted','code'=>'SP01','session'=>session,
  'resolves_event'=>report['id'],'signature'=>source01['signature'],'parser_version'=>'0.2.2',
  'source_hash'=>source01['source_hash'],'reason'=>'Người dùng xác nhận module gồm cả cánh; nẹp là phần phụ.',
  'analysis'=>source01,'before'=>before,'after'=>after,'skp'=>snapshot)
app::Storage.experience(root,event01)
model.commit_operation
operation = false
original04 = response['analyses'].flat_map { |a| a['products'] }.find { |p| p['code']=='SP04' }
report04 = app::Storage.event(root,'kind'=>'error_report','status'=>'unresolved','code'=>'SP04',
  'reason'=>'Vách giữa bị hiểu thành khoang tủ; người dùng xác nhận vách 1600 × 18 và hai nẹp sau chạy suốt 2500.', 'analysis'=>original04)
product04 = app::Model.build(source04,root,'geometry-role-correction-0.2.2',model)
state04 = app::Model.state(product04)
snapshot = app::Storage.snapshot(root,product04,"#{app::Ids.uuid}-verified")
event04 = app::Storage.event(root,'kind'=>'correction','status'=>'accepted','code'=>'SP04','resolves_event'=>report04['id'],
  'signature'=>source04['signature'],'parser_version'=>'0.2.2','source_hash'=>source04['source_hash'],
  'reason'=>'Hình học chia khoang/tầng; người dùng xác nhận vách và nẹp sau. Module tủ bao cả cánh. Giữ mối nối tấm 2400 + 100.',
  'analysis'=>source04,'before'=>{'modules'=>[],'panel_parts'=>[],'trim_parts'=>[],'bounds'=>source04['bounds']},
  'after'=>state04,'skp'=>snapshot)
app::Storage.experience(root,event04)
raise 'Existing roots or labels changed' unless baseline.all? { |id| model.entities.any? { |e| e.persistent_id==id } } && labels==app::Model.labels(model)
raise 'SP04 label centring' unless (product04.bounds.center.x.to_mm-labels.find { |l| l['code']=='SP04' }['center_x']).abs<0.1
response['analyses'].each { |a| a['products'].map! { |p| p['code']=='SP04' ? source04 : p } }
app.instance_variable_set(:@analyses,response['analyses'])
app.instance_variable_set(:@errors,[])
app.instance_variable_set(:@focused,'SP04')
app.instance_variable_set(:@focus_cad,false)
app.instance_variable_set(:@history_product,nil)
model.selection.clear
model.selection.add(product04)
model.active_view.zoom(product04)
app.instance_variable_get(:@manager)&.close
app.instance_variable_set(:@manager,nil)
app.manager
app.publish('SP04: 8 module bao gồm cánh; vách 18 rộng 1600 và nẹp dựng riêng. Hình học được ưu tiên, đã lưu xác nhận vai trò cấu kiện.')
model.active_view.write_image(File.join(plugin,'outputs','sp04-built.png'))
result={'status'=>'passed','version'=>'0.2.2','sp01'=>after,'sp04'=>state04,'entity_id'=>product04.persistent_id,
        'centre_x'=>product04.bounds.center.x.to_mm,'labels_unchanged'=>true,'native_solids'=>31,
        'history'=>[event01['path'],event04['path']]}
app::Storage.write_json(File.join(plugin,'outputs','sp04-native-result.json'),result)
puts JSON.generate(result.slice('status','version','entity_id','centre_x','native_solids','labels_unchanged'))
rescue StandardError => error
  model.abort_operation if operation
  app::Storage.write_json(File.join(plugin,'outputs','sp04-native-result.json'),{'status'=>'failed','error'=>error.message,'backtrace'=>error.backtrace.first(6)})
  raise
end

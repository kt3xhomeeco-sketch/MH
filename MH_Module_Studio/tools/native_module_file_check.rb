# encoding: UTF-8
studio = MH::ModuleStudio
base = File.dirname(studio::Panel.instance_method(:request).source_location.first)
model = Sketchup.active_model
raise 'Isolated persistence fixture only' unless File.expand_path(model.path).casecmp?(File.join(base,'outputs/assembly-028/cold/1.skp'))
roots = model.entities.to_a; definitions = model.definitions.to_a; selection = model.selection.to_a; modified = model.modified?
checks = {}
snapshot = JSON.parse(File.read(File.join(base,'test/fixtures/readable_nested_dc.json'),encoding:'UTF-8'))
rule = studio::StudioCalculation.build_system([snapshot])
path = File.join(base,'outputs/assembly-029/roundtrip-'+studio::Core::Ids.hex(4)+'.skp')
first = studio::ModuleFile.save(path,rule,snapshot)
checks['new_skp_contains_own_payload'] = studio::ModuleFile.read(path)['rule']==rule
panel = studio::Panel.new
panel.instance_variable_set(:@snapshots,[snapshot]);panel.instance_variable_set(:@rule,rule)
panel.instance_variable_set(:@source_file,path);panel.instance_variable_set(:@source_signature,first['signature'])
rows = studio::Parametric.variables(rule)
variable = rows.find { |row| row['symbol']=='dayvan' }
raise 'Thickness symbol fixture missing' unless variable
variable['symbol'] = 'VanDay'
panel.request('action'=>'save_skp','rule_id'=>rule['id'],'snapshot_id'=>snapshot['id'],'revision'=>0,'variables'=>rows)
saved = studio::ModuleFile.read(path)
checks['panel_save_skp_persists_symbol'] = saved['rule']['parametric_variables'].any? { |row| row['symbol']=='VanDay' }
sheet = studio::Parametric.sheet(saved['rule'],saved['snapshot'])
checks['reopened_detail_expressions_use_renamed_symbol'] = sheet['parts'].any? { |part| part['expressions'].any? { |entry| entry['text'].include?('VanDay') } }
backups = Dir[File.join(File.dirname(path),'.mh-backups',File.basename(path,'.skp')+'-*.skp')]
checks['backup_retains_previous_file'] = backups.any? { |file| studio::ModuleFile.signature(file)==first['signature'] }
before = studio::ModuleFile.signature(path)
begin
  studio::ModuleFile.save(path,saved['rule'],saved['snapshot'],expected:first['signature'])
  raise 'Stale file write accepted'
rescue studio::Core::Error
  checks['stale_write_keeps_existing_file'] = studio::ModuleFile.signature(path)==before
end
rows = studio::Parametric.variables(saved['rule'])
rows.find { |row| row['symbol']=='VanDay' }['value'] = 20
edited = studio::Parametric.edit_variables(saved['rule'],rows)
studio::ModuleFile.save(path,edited,saved['snapshot'],expected:before)
changed = studio::ModuleFile.read(path)
checks['saved_geometry_matches_changed_parameters'] = studio::Core.plan(changed['rule'],changed['snapshot'],{})['changed_count'].zero? && changed['values']['dayvan']==20
checks['native_file_actions_retain_model'] = roots==model.entities.to_a && definitions==model.definitions.to_a && selection==model.selection.to_a && modified==model.modified?
source = model.entities.grep(Sketchup::ComponentInstance).find { |entity| entity.name=='QA B Insert' }
model.selection.clear;model.selection.add(source)
panel.request('action'=>'capture_parametric')
checks['parametric_reads_selected_native_module'] = panel.instance_variable_get(:@snapshots).length==1 && panel.instance_variable_get(:@rule)['id']==source.get_attribute(studio::Reader::DICT,'rule_id')
model.selection.clear;selection.each { |entity| model.selection.add(entity) }
report = {'pid'=>Process.pid,'ok'=>checks.values.all?,'checks'=>checks,'path'=>path}
File.write(File.join(base,'outputs/assembly-029/native-file-check.json'),JSON.pretty_generate(report))
puts JSON.pretty_generate(report)

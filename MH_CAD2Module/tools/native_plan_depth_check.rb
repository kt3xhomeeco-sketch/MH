# frozen_string_literal: true

app = MH::CAD2Module; model = Sketchup.active_model; root = app::Settings::ROOT; dict = app::Model::DICT
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
%w[product_height.rb plan_depth.rb placement.rb reference_build.rb selection_source.rb].each { |file| load File.join(root, file) }
source = JSON.parse(File.read(File.join(root, 'outputs/sp25-styled-product.json'), encoding: 'UTF-8'))['plan_results'].first
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h; layers = model.layers.map(&:name); selection = model.selection.to_a
sha = Digest::SHA256.file(model.path).hexdigest unless model.path.empty?
read = app::Settings.method(:read); settings = read.call(model)
ops = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
ops[:start_operation][0].call('CAD2Module: Test Sâu Box', true)
records = []; started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
begin
  ops.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  qa = File.join(root, 'outputs/qdepth')
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('library' => qa) }
  %w[unchanged moved edited locked manual wrong_source].each_with_index do |kind, index|
    packet = JSON.parse(JSON.generate(source)); packet['code'] = "SP#{99600 + index}"; packet['activity_id'] = app::Ids.uuid
    old = JSON.parse(JSON.generate(packet)); frame = old['source_plan_envelope']
    old['envelope_preview'].delete('depth_evidence'); old['envelope_preview']['dimensions_from'] = 'selected_source_edges'
    old['modules'].first['origin'][1] = 0; old['modules'].first['size'][1] = frame[3] - frame[1]
    old['modules'].first['source_box'] = frame.dup; old['modules'].first['plan_box'] = frame.dup
    old['bounds'][1] = frame[3] - frame[1]
    instance = app::Model.build(old, qa, app::Ids.uuid, model); group = instance.members.first; id = group.persistent_id
    refs = instance.get_attribute(dict, 'cad_reference_ids').map { |pid| model.find_entity_by_persistent_id(pid) }
    reference_state = refs.map { |g| [g.persistent_id, g.transformation.to_a, g.entities.length] }
    if kind == 'moved' then group.transform!(Geom::Transformation.translation([0, 25.mm, 0]))
    elsif kind == 'edited' then group.entities.add_line([0, 0, 0], [1.mm, 1.mm, 1.mm])
    elsif kind == 'locked' then group.locked = true
    elsif kind == 'manual'
      old['manual_boxes'] = true; instance.set_attribute(dict, 'analysis', JSON.generate(old))
    elsif kind == 'wrong_source' then packet['source_hash'] = 'f' * 64
    end
    before = [group.transformation.to_a, group.definition.bounds.min.to_a, group.definition.bounds.max.to_a, group.entities.length]
    if kind == 'unchanged'
      outcome = app::ReferenceBuild.call(packet, qa, app::Ids.uuid, model)
      raise 'Depth update rebuilt the product' if outcome[:created] || outcome[:instance].persistent_id != instance.persistent_id
      changed = app::Model.state(instance)['modules'].first['size'][1] == 310
    else
      changed = app::PlanDepth.refresh_preview(model, instance, packet, qa)
    end
    raise "Wrong depth guard: #{kind}" unless changed == (kind == 'unchanged')
    raise 'Changed Group ID' unless group.persistent_id == id
    if changed
      measured = app::Model.state(instance)['modules'].first
      raise 'Wrong native box/cabinet front' unless measured['size'].last(2) == [310, 2730] && (measured['origin'][1] - packet['modules'].first['origin'][1]).abs < 0.001 && group.manifold?
      raise 'Depth retry not idempotent' if app::PlanDepth.refresh_preview(model, instance, packet, qa)
    else
      raise 'Protected box changed' unless before == [group.transformation.to_a, group.definition.bounds.min.to_a, group.definition.bounds.max.to_a, group.entities.length]
    end
    raise 'CAD moved during depth update' unless reference_state == refs.map { |g| [g.persistent_id, g.transformation.to_a, g.entities.length] }
    records << { guard: kind, refreshed: changed, id_retained: true, cad_preserved: true }
  end
  # Test actual native capture/tag inheritance and source-style watches.
  cad = model.entities.add_group; tag = model.layers.add('MH_QA_Stroke'); cad.layer = tag
  cad.entities.add_line([0, 0, 0], [100.mm, 0, 0]); cad.entities.add_line([0, 18.mm, 0], [100.mm, 18.mm, 0])
  model.selection.clear; model.selection.add(cad)
  first = app::SelectionSource.capture(model, include_views: false)
  raise 'Capture lost inherited stroke metadata' unless first['lines'].all? { |line| line['layer'] == tag.name && line['continuous'] && line.key?('color') }
  app::SelectionSource.validate_watch(first['source_watch'], model)
  tag.color = Sketchup::Color.new(1, 2, 3)
  begin
    app::SelectionSource.validate_watch(first['source_watch'], model)
    raise 'Changed stroke not detected'
  rescue ArgumentError
    nil
  end
  second = app::SelectionSource.capture(model, include_views: false)
  raise 'Style change reused stale source hash' if first['hash'] == second['hash']
ensure
  app::Settings.define_singleton_method(:read, read)
  ops.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  ops[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User state changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] } && registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h && layers == model.layers.map(&:name) && settings == read.call(model)
raise 'User file changed' if sha && sha != Digest::SHA256.file(model.path).hexdigest
result = { passed: true, depth_mm: 310, section_checks: 3, records: records, stroke_capture_watch_and_hash_checked: true, user_state_preserved: true,
           seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
app::Storage.write_json(File.join(root, 'outputs/plan-depth-native-result.json'), result)
puts JSON.generate(result)

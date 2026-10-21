# frozen_string_literal: true

app = MH::CAD2Module; model = Sketchup.active_model; root = app::Settings::ROOT; dict = app::Model::DICT
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
%w[product_height.rb partial_plan.rb placement.rb reference_build.rb].each { |file| load File.join(root, file) }
source = JSON.parse(File.read(File.join(root, 'outputs/sp25-partial-product.json'), encoding: 'UTF-8'))['plan_results'].first
legacy = JSON.parse(File.read(File.join(root, 'outputs/sp25-pre-partition-product.json'), encoding: 'UTF-8'))['plan_results'].first
partial = JSON.parse(File.read(File.join(root, 'outputs/sp25-pre-bands-product.json'), encoding: 'UTF-8'))['plan_results'].first
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h; layers = model.layers.map(&:name); selection = model.selection.to_a
sha = Digest::SHA256.file(model.path).hexdigest unless model.path.empty?
read = app::Settings.method(:read); settings = read.call(model)
ops = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
ops[:start_operation][0].call('CAD2Module: Test Chia Cục Bộ', true)
records = []; started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
begin
  ops.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  qa = File.join(root, 'outputs/qpartial')
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('library' => qa) }
  %w[new unchanged moved edited locked manual wrong_source partial partial_shared partial_edited partial_locked partial_moved partial_missing].each_with_index do |kind, index|
    packet = JSON.parse(JSON.generate(source)); packet['code'] = "SP#{99500 + index}"; packet['activity_id'] = app::Ids.uuid
    packet['build_auxiliary'] = true
    if kind == 'new'
      instance = app::Model.build(packet, qa, app::Ids.uuid, model)
      raise 'Wrong new partition' unless instance.members.length == 10 && instance.members.all? { |g| g.parent == model && g.manifold? }
      records << { guard: kind, groups: instance.members.length, native_solids: true }
      next
    end
    old = JSON.parse(JSON.generate(kind.start_with?('partial') ? partial : legacy)); old['code'] = packet['code']; old['activity_id'] = packet['activity_id']
    old['source_hash'] = packet['source_hash']
    old['build_auxiliary'] = true if kind.start_with?('partial')
    instance = app::Model.build(old, qa, app::Ids.uuid, model); group = instance.members.first
    refs = instance.get_attribute(dict, 'cad_reference_ids').map { |pid| model.find_entity_by_persistent_id(pid) }
    reference_state = refs.map { |g| [g.persistent_id, g.transformation.to_a, g.entities.length] }
    transform = instance.transformation.to_a
    if kind == 'partial_shared'
      copy = group.copy; copy.transform!(Geom::Transformation.translation([5000.mm, 0, 0]))
    end
    if %w[moved partial_moved].include?(kind) then group.transform!(Geom::Transformation.translation([0, 25.mm, 0]))
    elsif %w[edited partial_edited].include?(kind) then group.entities.add_line([0, 0, 0], [1.mm, 1.mm, 1.mm])
    elsif %w[locked partial_locked].include?(kind) then group.locked = true
    elsif kind == 'partial_missing' then instance.members.last.erase!
    elsif kind == 'manual'
      old['manual_boxes'] = true; instance.set_attribute(dict, 'analysis', JSON.generate(old))
    elsif kind == 'wrong_source' then packet['source_hash'] = 'f' * 64
    end
    before = [group.transformation.to_a, group.definition.bounds.min.to_a, group.definition.bounds.max.to_a, group.entities.length]
    packet.delete('build_auxiliary') if kind == 'partial'
    if %w[unchanged partial partial_shared partial_locked].include?(kind)
      outcome = app::ReferenceBuild.call(packet, qa, app::Ids.uuid, model)
      raise 'Not refreshed' unless outcome[:updated] && !outcome[:created] && outcome[:instance].persistent_id == instance.persistent_id
      raise 'Original preview survives' if kind == 'unchanged' && group.valid?
      raise 'Unchanged module was replaced' if kind.start_with?('partial') && !group.valid?
      raise 'Wrong module/trim count' unless instance.members.length == 10
      measured = app::Model.state(instance)['modules']
      raise 'Wrong native depths/partition' unless measured.length == 8 && measured.count { |m| m['size'][1] == 310 } == 7 && instance.members.all?(&:manifold?)
      roof = measured.find { |m| m['name'] == 'Module nóc liên tục' }; foot = measured.find { |m| m['name'] == 'Module chân' }
      raise 'Split roof/missing plinth' unless roof['size'] == [1992, 310, 30] && foot['size'] == [1992, 292, 50] && foot['origin'][2] == 0
      raise 'Source-tail box lost' unless measured.any? { |m| m['unresolved'] && m['origin'][0] == 2610 && m['size'][0] == 1084.829 }
      raise 'Retry not idempotent' if app::PartialPlan.refresh_preview(model, instance, packet, qa)
    else
      rejected = false
      begin
        app::ReferenceBuild.call(packet, qa, app::Ids.uuid, model)
      rescue ArgumentError
        rejected = true
      end
      raise "Missing guard: #{kind}" unless rejected
      raise 'Protected box changed' unless group.valid? && before == [group.transformation.to_a, group.definition.bounds.min.to_a, group.definition.bounds.max.to_a, group.entities.length]
    end
    raise 'Assembly/CAD moved' unless transform == instance.transformation.to_a && reference_state == refs.map { |g| [g.persistent_id, g.transformation.to_a, g.entities.length] }
    records << { guard: kind, refreshed: %w[unchanged partial partial_shared partial_locked].include?(kind), cad_preserved: true }
  end
ensure
  app::Settings.define_singleton_method(:read, read)
  ops.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  ops[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User state changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] } && registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h && layers == model.layers.map(&:name) && settings == read.call(model)
raise 'User file changed' if sha && sha != Digest::SHA256.file(model.path).hexdigest
result = { passed: true, records: records, user_state_preserved: true, seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
app::Storage.write_json(File.join(root, 'outputs/partial-plan-native-result.json'), result)
puts JSON.generate(result)

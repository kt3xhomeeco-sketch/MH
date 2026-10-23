# frozen_string_literal: true

app = MH::CAD2Module; model = Sketchup.active_model; root = app::Settings::ROOT; dict = app::Model::DICT
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
%w[plan_reference.rb reference_build.rb].each { |f| load File.join(root, f) }
data = JSON.parse(File.read(File.join(root, 'outputs/sp25-pre-partition-product.json'), encoding: 'UTF-8'))
children = data['plan_results']
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h; layers = model.layers.map(&:name); selection = model.selection.to_a
sha = Digest::SHA256.file(model.path).hexdigest unless model.path.empty?
read = app::Settings.method(:read); settings = read.call(model)
ops = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
ops[:start_operation][0].call('CAD2Module: Kiểm Tra Khôi Phục CAD Khi Giữ Box', true)
result = {}
begin
  ops.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  qa = File.join(root, 'outputs/qrestore')
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('library' => qa) }
  children.each { |p| p['code'] = 'SP99825'; p['activity_id'] = app::Ids.uuid }
  run = lambda do |job|
    owner = nil
    children.map do |p|
      outcome = app::ReferenceBuild.call(p, qa, job, model, owner)
      owner = outcome[:owner]; outcome
    end
  end
  first = run.call(app::Ids.uuid); primary = first.first[:instance]
  refs = primary.get_attribute(dict, 'cad_reference_ids').map { |id| model.find_entity_by_persistent_id(id) }
  raise 'Initial source incomplete' unless refs.length == 11 && first.all? { |r| r[:created] }
  kept = refs.find { |g| g.get_attribute(dict, 'view_id') == 'V02.1' }
  kept.hidden = true
  kept.transform!(Geom::Transformation.translation([10.mm, 0, 20.mm]))
  transform = kept.transformation.to_a
  refs.reject { |g| g == kept }.each(&:erase!)
  # Reproduce the actual retry: primary/two boxes retained, last box removed.
  first.last[:instance].members.each(&:erase!)
  old_box_ids = first.first(2).flat_map { |r| r[:instance].members.map(&:persistent_id) }
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  second = run.call(app::Ids.uuid)
  raise 'Wrong reuse/build counts' unless second.count { |r| r[:created] } == 1 && second.sum { |r| r[:restored] } == 10
  raise 'Old box IDs changed' unless old_box_ids == second.first(2).flat_map { |r| r[:instance].members.map(&:persistent_id) }
  raise 'User-adjusted CAD changed' unless kept.valid? && kept.hidden? && kept.transformation.to_a == transform
  ids = primary.get_attribute(dict, 'cad_reference_ids')
  refs = ids.map { |id| model.find_entity_by_persistent_id(id) }
  raise 'Wrong reference count after retry' unless refs.length == 11 && refs.all?(&:valid?)
  raise 'New child used cropped fallback' unless second.last[:instance].get_attribute(dict, 'plan_reference_id') == refs.find { |g| g.get_attribute(dict, 'view_id') == 'V05.1' }.persistent_id
  third = run.call(app::Ids.uuid)
  raise 'Repeated retry duplicated source or boxes' unless third.none? { |r| r[:created] } && third.sum { |r| r[:restored] }.zero? && primary.get_attribute(dict, 'cad_reference_ids') == ids
  bad = JSON.parse(JSON.generate(children.first)); bad['source_hash'] = 'f' * 64
  begin
    app::ReferenceBuild.call(bad, qa, app::Ids.uuid, model)
    raise 'Changed source reused old boxes'
  rescue ArgumentError
    nil
  end
  orphan = app::Assembly.create(model); orphan.set_attribute(dict, 'job_id', app::Ids.uuid)
  begin
    app::PlanReference.create(model, children.last, orphan)
    raise 'Missing source carrier silently became one plan'
  rescue ArgumentError
    nil
  end
  result = { passed: true, actual_sp25: true, restored_views: 10, complete_views: 11, retained_boxes: 2, new_box_sets: 1,
             repeated_retry_no_duplicates: true, existing_cad_edits_preserved: true, wrong_source_rejected: true, missing_shared_owner_rejected: true,
             seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
ensure
  app::Settings.define_singleton_method(:read, read)
  ops.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  ops[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User state changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] } && registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h && layers == model.layers.map(&:name) && settings == read.call(model)
raise 'User file changed' if sha && sha != Digest::SHA256.file(model.path).hexdigest
result[:user_state_preserved] = true
app::Storage.write_json(File.join(root, 'outputs/reference-restore-native-result.json'), result)
puts JSON.generate(result)

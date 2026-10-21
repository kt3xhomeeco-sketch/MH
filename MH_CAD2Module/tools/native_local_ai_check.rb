# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
analysis = JSON.parse(File.read(File.join(app::Settings::ROOT, 'outputs', 'local-ai-native-fixture.json'), encoding: 'UTF-8'))
raise 'Not real AI output' unless analysis.dig('learning', 'mode') == 'local_ai' && analysis.dig('local_ai', 'model').start_with?('qwen3:')
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
selection = model.selection.to_a
originals = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
root = File.join(app::Settings::ROOT, 'outputs', 'i')
originals[:start_operation][0].call('CAD2Module: Kiểm Tra AI Local', true)
begin
  originals.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  if analysis.dig('local_ai', 'workflow') == 'ai_plan_search_v2'
    source = model.entities.add_group
    edge = source.entities.add_line([30_000.mm, 40_000.mm, 73.mm], [30_018.mm, 40_000.mm, 73.mm])
    analysis['source_watch'] = [[edge.persistent_id.to_s, [source.persistent_id],
                                [30_000, 40_000, 73], [30_018, 40_000, 73]]]
    source.transformation = Geom::Transformation.translation([25.mm, 0, 0])
    count = model.entities.length
    begin
      app::Model.build(analysis, root, app::Ids.uuid, model)
      raise 'Moved source was accepted'
    rescue ArgumentError => error
      raise 'Wrong source failure' unless error.message.include?('CAD') && model.entities.length == count
    end
    source.transformation = Geom::Transformation.new
  end
  product = app::Model.build(analysis, root, app::Ids.uuid, model)
  raise 'Expected independent solids' unless product.members.length == 2 && product.members.all? { |g| g.is_a?(Sketchup::Group) && g.parent == model && g.manifold? }
  actual = app::Model.state(product)['modules'].sort_by { |part| part['origin'][0] }
  actual.zip(analysis['modules']).each do |a, b|
    raise 'Native dimensions differ from CAD measurement' unless (a['origin'] + a['size']).zip(b['origin'] + b['size']).all? { |x, y| (x - y).abs < 0.01 }
  end
  left = product.members.min_by { |g| g.bounds.min.x }
  raise 'World placement changed' unless (left.bounds.min.x.to_mm - 30_000).abs < 0.01 && (left.bounds.min.y.to_mm - 40_000).abs < 0.01 && (left.bounds.min.z.to_mm - 73).abs < 0.01
  event = app::Activity.compact_event('analysis' => analysis)
  raise 'AI provenance missing from history' unless event.dig('analysis', 'local_ai', 'model') == analysis.dig('local_ai', 'model')
ensure
  originals.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  originals[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'Temporary metadata leaked' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
result = { 'status' => 'passed', 'real_local_ai_response' => true, 'independent_solid_groups' => true,
           'cad_dimensions_and_position' => true, 'ai_history_provenance' => true, 'user_geometry_unchanged' => true,
           'moved_source_rejected_before_geometry' => analysis.dig('local_ai', 'workflow') == 'ai_plan_search_v2' }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'local-ai-native-result.json'), result)
puts JSON.generate(result)

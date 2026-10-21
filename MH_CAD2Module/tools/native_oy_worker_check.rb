# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
source = JSON.parse(File.read(File.join(root, 'library/jobs/f9052b1d-85ca-6e2f-9a0c-4250662196c7/request.json')))
raise 'Source model changed' unless source['geometry']['model_path'] == model.path
app::SelectionSource.validate_watch(source['geometry']['source_watch'], model)
read = app::Settings.method(:read)
settings = read.call
qa_root = 'E:/MH_CAD2Module_QA/AI/tests/oy-sweep-0110/async'
source['code'] = "QA-#{app::Ids.uuid}"
values = source.slice('geometry', 'code', 'name', 'automatic_scan').merge('ai_enabled' => true, 'build_elevation' => false)
app::Settings.define_singleton_method(:read) { |*_args| settings.merge('library' => qa_root) }
begin
  app::Jobs.start('geometry', values) do |result, job|
    receipt = { worker_seconds: Time.now - job[:started], error: result['error'] }
    begin
      data = result.dig('analyses', 0, 'products', 0)
      raise 'Worker failed' unless result['ok'] && data['status'] == 'ready' && data.dig('local_ai', 'status') == 'not_used'
      receipt[:processing_times] = data['processing_times']
      baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
      registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
      selection = model.selection.to_a
      originals = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
      originals[:start_operation][0].call('CAD2Module: Kiểm Tra Worker OY', true)
      begin
        originals.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
        product = app::Model.build(data, qa_root, job[:id], model)
        raise 'Expected four modules and three solid auxiliaries' unless product.members.length == 7 && product.members.all?(&:manifold?)
        saved = JSON.parse(product.get_attribute(app::Model::DICT, 'analysis'))
        receipt[:native_times] = saved['native_times']
        receipt[:measured_source_check] = saved.dig('geometry_check', 'passed')
      ensure
        originals.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
        originals[:abort_operation][0].call
        model.selection.clear; model.selection.add(selection.select(&:valid?))
      end
      raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
      raise 'Registry changed' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
      receipt[:no_ai_call] = true
      receipt[:user_geometry_unchanged] = true
      receipt[:passed] = true
    rescue StandardError => error
      receipt[:error] = error.message
    ensure
      app::Storage.write_json(File.join(root, 'outputs/oy-sweep-worker-result.json'), receipt)
    end
  end
ensure
  app::Settings.define_singleton_method(:read, read)
end
puts 'Windowless OY worker QA queued; machine settings restored.'

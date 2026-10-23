# frozen_string_literal: true

app = MH::CAD2Module
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active?
models = Sketchup.active_model.entities.map(&:persistent_id)
entry = app.instance_variable_get(:@entry); manager = app.instance_variable_get(:@manager)
saved = []
replace = lambda do |object, name, &block|
  owned = object.singleton_class.instance_methods(false).include?(name)
  saved << [object, name, object.method(name), owned]
  object.define_singleton_method(name, &block)
end
fields = %i[@errors @focused @last_products @last_product_end @last_built @entry_mode @message]
state = fields.to_h { |k| [k, [app.instance_variable_defined?(k), app.instance_variable_get(k)]] }
opened = 0; messages = []; catalog = []; fail_build = false
group = Struct.new(:persistent_id).new(987654321)
group.define_singleton_method(:get_attribute) { |_dict, _key, *_args| JSON.generate('envelope_preview' => { 'reason' => 'QA provisional' }) }
selection = Object.new
selection.define_singleton_method(:clear) { true }; selection.define_singleton_method(:add) { |_items| true }
fake_model = Struct.new(:selection).new(selection)
job = { root: File.join(app::Settings::ROOT, 'outputs/qcontroller'), id: 'qa', model: fake_model }
original_scan = app.method(:scan)
begin
  replace.call(app, :manager) { opened += 1 }
  replace.call(app, :publish) { |message = nil, **_kwargs| messages << message }
  replace.call(app, :products) { catalog }
  replace.call(app, :scan) { |_values = {}, &completion| completion.call(job) }
  replace.call(app::Storage, :event) { |*_args| true }
  replace.call(app::Model, :selection_entities) { |_product| [] }
  replace.call(app::ReferenceBuild, :call) do |*_args|
    raise 'QA native build error' if fail_build
    { instance: group, created: true, restored: 0, owner: group.persistent_id }
  end
  app.instance_variable_set(:@entry_mode, 'dwg')
  app.instance_variable_set(:@errors, [])
  catalog = [{ 'code' => 'SP99991', 'name' => 'QA' }]
  app.build_request('SP99991') # Provisional box used to open manager.
  catalog = []; app.instance_variable_set(:@errors, [])
  app.build_request('SP99991') # Missing product used report_error.
  catalog = [{ 'code' => 'SP99991', 'name' => 'QA' }]; fail_build = true; app.instance_variable_set(:@errors, [])
  app.build_request('SP99991')
  app.define_singleton_method(:scan, original_scan)
  replace.call(app::Jobs, :start) do |_action, _values, &completion|
    completion.call({ 'ok' => false, 'error' => 'QA worker error' }, { model: Sketchup.active_model })
  end
  app.scan
  raise 'Build or error opened manager' unless opened.zero?
  raise 'Errors/previews lost their message' unless messages.any? { |s| s.to_s.include?('QA provisional') } && messages.any? { |s| s.to_s.include?('QA worker error') }
ensure
  saved.reverse_each { |object, name, method, owned| owned ? object.define_singleton_method(name, method) : object.singleton_class.send(:remove_method, name) }
  state.each { |k, (present, value)| present ? app.instance_variable_set(k, value) : (app.remove_instance_variable(k) if app.instance_variable_defined?(k)) }
end
raise 'Dialogs or model changed' unless app.instance_variable_get(:@entry).equal?(entry) && app.instance_variable_get(:@manager).equal?(manager) && Sketchup.active_model.entities.map(&:persistent_id) == models
result = { passed: true, automatic_manager_opens: opened, provisional_missing_native_and_worker_errors_checked: true, messages_preserved: true, no_model_or_dialog_writes: true }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs/no-auto-manager-native-result.json'), result)
puts JSON.generate(result)

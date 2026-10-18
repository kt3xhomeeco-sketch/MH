# frozen_string_literal: true

require 'json'
app = MH::CAD2Module
model = Sketchup.active_model
raise 'Unexpected model/job/edit' unless model.title == '1' && !model.active_path && !app::Jobs.busy? && !app::Corrections.active?
source = model.find_entity_by_persistent_id(963192)
raise 'Current CAD missing' unless source && app::Model.container?(source)
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a] }
selection = model.selection.to_a
variables = %i[@entry_mode @selection_geometry @message @errors @last_products]
saved = variables.to_h { |name| [name, [app.instance_variable_defined?(name), app.instance_variable_get(name)]] }
start_method = app::Jobs.method(:start)
entry_method = app.method(:entry)
entry_owned = app.singleton_class.instance_methods(false).include?(:entry)
packet = nil
begin
  # Intercept only asynchronous dispatch: run the real selection/capture/build
  # routing without launching a second product over the user's existing SP32.
  app::Jobs.define_singleton_method(:start) { |action, values, &completion| packet = values.merge('action' => action); 'native-check' }
  app.define_singleton_method(:entry) { |*_args| raise 'Scan opened the code-entry dialog' }
  model.selection.clear
  model.selection.add(source)
  app.selection_ready(nil)
  raise 'No automatic request' unless packet && packet['automatic_scan'] && packet['action'] == 'geometry'
  raise 'Manual code still required' unless packet['code'].match?(/\ASCAN-[0-9A-F-]{36}\z/)
  raise 'Wrong scan origin' unless packet.dig('geometry', 'plane') == 'XY' && packet.dig('geometry', 'plane_offset_mm') == 0
  actual = app::Model.products(model).find { |e| e.get_attribute(app::Model::DICT, 'code') == 'SP32' }
  candidate = JSON.parse(actual.get_attribute(app::Model::DICT, 'analysis')).merge('code' => packet['code'], 'automatic_scan' => true)
  begin
    app::Model.build(candidate, app::Settings.library, 'must-not-duplicate', model)
    raise 'Duplicate source created overlapping geometry'
  rescue ArgumentError => error
    raise unless error.message.include?('Vùng CAD này đã được dựng')
  end
ensure
  app::Jobs.define_singleton_method(:start, start_method)
  if entry_owned
    app.define_singleton_method(:entry, entry_method)
  else
    app.singleton_class.send(:remove_method, :entry)
  end
  saved.each do |name, (present, value)|
    present ? app.instance_variable_set(name, value) : app.remove_instance_variable(name) if present || app.instance_variable_defined?(name)
  end
  model.selection.clear
  model.selection.add(selection.select(&:valid?))
  app.publish
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a] }
result = { status: 'passed', code_entry_opened: false, automatic_request: true,
           source_plane_preserved: true, duplicate_source_blocked: true, original_geometry_unchanged: true }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'no-code-native-result.json'), result)
puts JSON.generate(result)

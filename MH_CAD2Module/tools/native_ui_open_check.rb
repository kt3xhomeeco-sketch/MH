# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
selection = model.selection.to_a
model.start_operation('CAD2Module: Kiểm Tra Đọc Khối', true)
begin
  product = app::Assembly.create(model)
  group = model.entities.add_group
  product.add_member(group)
  raise 'Root member missing' unless product.members == [group] && product.valid?
  raise 'Selection missing' unless app::Model.products(model).include?(product)
  other = app::Assembly.create(model)
  other.add_member(group)
  raise 'Reassigned member retained' unless product.members.empty? && !product.valid?
  raise 'Reassigned member missing' unless other.members == [group]
  group.erase!
  raise 'Deleted member retained' unless other.members.empty? && !other.valid?
  parent = model.entities.add_group
  nested = parent.entities.add_group
  other.add_member(nested)
  raise 'Nested member accepted as root' unless other.members.empty?
ensure
  model.abort_operation
  model.selection.clear
  model.selection.add(selection.select(&:valid?))
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'User registry changed' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h

manager = app.instance_variable_get(:@manager)
entry = app.instance_variable_get(:@entry)
state_method = app.method(:public_state)
state_owned = app.singleton_class.instance_methods(false).include?(:public_state)
fake_dialog = Struct.new(:shown, :scripts) do
  def visible?
    shown
  end

  def execute_script(script)
    scripts << script
  end
end
begin
  app.define_singleton_method(:public_state) { raise 'Unnecessary full state read' }
  hidden = fake_dialog.new(false, [])
  input = fake_dialog.new(true, [])
  app.instance_variable_set(:@manager, hidden)
  app.instance_variable_set(:@entry, hidden)
  app.publish
  raise 'Published to hidden dialog' unless hidden.scripts.empty?
  app.instance_variable_set(:@entry, input)
  app.publish
  raise 'Entry state missing' unless input.scripts.length == 1 && input.scripts.first.include?('entry_mode') && !input.scripts.first.include?('activities')
ensure
  state_owned ? app.define_singleton_method(:public_state, state_method) : app.singleton_class.send(:remove_method, :public_state)
  app.instance_variable_set(:@manager, manager)
  app.instance_variable_set(:@entry, entry)
end

clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
results = { 'membership_fresh' => true, 'geometry_unchanged' => true, 'entry_isolated' => true, 'hidden_skipped' => true, 'samples' => [] }
3.times do
  started = clock.call
  state = app.public_state
  results['samples'] << { 'seconds' => clock.call - started, 'activities' => state['activities'].length, 'labels' => state['labels'].length }
end
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs/ui-open-native-result.json'), results)
puts JSON.generate(results)

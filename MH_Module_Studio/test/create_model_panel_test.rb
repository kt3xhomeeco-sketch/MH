# frozen_string_literal: true
require 'minitest/autorun'
require 'open3'
require 'rbconfig'

class ModuleStudioCreateModelPanelTest < Minitest::Test
  def test_create_uses_saved_variables_and_guards_module_identity
    script = <<~'RUBY'
      require 'json'
      $LOADED_FEATURES << 'sketchup.rb'
      def file_loaded?(*)
        true
      end
      require ARGV.fetch(0)
      studio = MH::ModuleStudio
      studio.define_singleton_method(:show_options) { nil }
      snapshot = JSON.parse(File.read(ARGV.fetch(1), encoding: 'UTF-8'))
      rule = studio::RuleSystem.build(snapshot, studio::Core.learn_module([snapshot]))
      rows = studio::Parametric.variables(rule)
      rows.find { |row| row['binding'] == 'dayvan' }['value'] = 20
      rows.find { |row| row['binding'] == 'dayvan' }['exported'] = false
      rule = studio::Parametric.edit_variables(rule, rows)
      key = snapshot['parts'].find { |part| part['name'] == 'Giằng Trước' }['key']
      rule = studio::Parametric.edit_part_formula(rule, key, 'lenz', 'giang + 10')
      calls = []
      studio::Runtime.define_singleton_method(:create_model) do |sample, bundle, targets|
        calls << [sample['id'], targets]
        calculation = Marshal.load(Marshal.dump(bundle))
        studio::Core.set_exposed_parameters!(calculation, calculation['parameters'].select { |param| param['editable'] }.map { |param| param['key'] })
        studio::Core.plan(calculation, sample, targets)
      end
      panel = studio::Panel.new
      panel.instance_variable_set(:@rule, rule)
      panel.instance_variable_set(:@snapshots, [snapshot])
      panel.instance_variable_set(:@parametric_revision, 4)
      data = { 'action' => 'create_model', 'rule_id' => rule['id'], 'snapshot_id' => snapshot['id'], 'revision' => 4, 'target' => 99 }
      panel.request(data)
      result = panel.instance_variable_get(:@plan)
      raise 'Own formula missing' unless (studio::Core.dimensions(result['parts'].find { |part| part['key'] == key }['bounds'])[2] - 80).abs < 0.001
      raise 'Saved input ignored' unless calls.first[1]['dayvan'] == 20
      raise 'Template changed' unless panel.instance_variable_get(:@snapshots).last.equal?(snapshot)
      raise 'Checkbox changed' if studio::Parametric.variables(panel.instance_variable_get(:@rule)).find { |row| row['binding'] == 'dayvan' }['exported']
      rejected = 0
      [data.merge('revision' => 3), data.merge('rule_id' => 'stale'), data.merge('snapshot_id' => 'stale')].each do |bad|
        begin
          panel.request(bad)
        rescue studio::Core::Error
          rejected += 1
        end
      end
      raise 'Stale create reached native adapter' unless rejected == 3 && calls.length == 1
      puts 'saved targets, own formula, template preservation and stale guards pass'
    RUBY
    output, error, status = Open3.capture3(RbConfig.ruby, '-e', script,
      File.expand_path('../main.rb', __dir__), File.join(__dir__, 'fixtures', 'readable_nested_dc.json'))
    assert status.success?, error
    assert_includes output, 'stale guards pass'
  end
end

# encoding: UTF-8
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'ripper'
require_relative '../core'

class ModuleStudioCalculationBoundariesTest < Minitest::Test
  Studio = MH::ModuleStudio
  Core = Studio::Core
  Root = File.expand_path('..', __dir__)

  def source
    JSON.parse(File.read(File.join(__dir__, 'fixtures/readable_nested_dc.json'), encoding: 'UTF-8'))
  end

  def freeze_data(value)
    value.each { |key, item| freeze_data(key); freeze_data(item) } if value.is_a?(Hash)
    value.each { |item| freeze_data(item) } if value.is_a?(Array)
    value.freeze
  end

  def test_cold_core_load_has_no_host_dependencies_and_matches_the_declared_boundary
    script = <<~'RUBY'
      root = ARGV.fetch(0)
      require File.join(root, 'core')
      host = %i[Sketchup Geom UI ABF DCFunctionsV1].select { |name| Object.const_defined?(name) }
      files = $LOADED_FEATURES.select { |path| path.start_with?(root + '/') }.map { |path| path.delete_prefix(root + '/') }.sort
      puts JSON.generate(host: host, files: files)
    RUBY
    output, errors, status = Open3.capture3(RbConfig.ruby, '-e', script, Root.tr('\\', '/'))
    assert status.success?, errors
    state = JSON.parse(output)
    assert_empty state['host']
    manifest = JSON.parse(File.read(File.join(Root, 'runtime_manifest.json'), encoding: 'UTF-8'))
    assert_equal manifest['calculation'].sort, state['files']
    manifest['calculation'].each do |name|
      code = File.read(File.join(Root, name), encoding: 'UTF-8')
      constants = Ripper.lex(code).select { |_position, token, _text, _state| token == :on_const }.map { |_position, _token, text, _state| text }
      assert_empty constants & %w[Sketchup Geom UI ABF DCFunctionsV1 RubyVM], name
    end
    files = manifest.values.flatten
    assert_equal files.uniq, files
    assert_equal Dir[File.join(Root, '*.rb')].map { |path| File.basename(path) }.sort,
                 (manifest['calculation'] + manifest['adapters']).sort
  end

  def test_numeric_symbolic_and_sheet_programs_have_separate_owners
    numeric = Studio::DCFormulas::Program
    symbolic = Studio::DCFormulas::SymbolicProgram
    sheet = Studio::DCFormulas::ParametricProgram
    refute_includes numeric.instance_methods, :symbolic_positions
    refute_includes numeric.instance_methods, :cell_formula_texts
    refute_includes numeric.instance_methods, :parametric_attributes
    assert_equal numeric, symbolic.superclass
    assert_equal symbolic, sheet.superclass
    assert_equal symbolic, symbolic.instance_method(:symbolic_positions).owner
    assert_equal sheet, sheet.instance_method(:cell_formula_texts).owner
    refute Studio::DCFormulas.respond_to?(:capture_function_aliases!)
  end

  def test_learned_rules_and_built_system_do_not_share_mutable_source_data
    snapshot = source
    original = JSON.generate(snapshot)
    engine = Core.learn_module([freeze_data(snapshot)])
    rule = Studio::RuleSystem.build(snapshot, engine)
    engine_before = JSON.generate(engine)
    rule['formula_engine']['attribute_program']['dc_inputs']['dayvan'] = -100
    rule['parts'].first['base_bounds'][0][0] = -100
    assert_equal original, JSON.generate(snapshot)
    assert_equal engine_before, JSON.generate(engine)
    engine['attribute_program']['dc_inputs']['dayvan'] = -200
    assert_equal original, JSON.generate(snapshot)
  end

  def test_sheet_preview_scale_and_failed_edit_leave_saved_inputs_unchanged
    snapshot = source
    rule = Studio::StudioCalculation.build_system([snapshot])
    saved = rule['parameters'].select { |param| param['editable'] }.to_h { |param| [param['key'], param['value']] }
    before = [JSON.generate(snapshot), JSON.generate(rule)]
    freeze_data(snapshot)
    freeze_data(rule)
    expected = Core.plan(rule, snapshot, 'dayvan' => 20)
    sheet = Studio::Parametric.sheet(rule, snapshot, expected)
    sheet['variables'].first['name'].replace('Local sheet edit')
    sheet['categories']['dimension'].replace('Local category edit')
    sheet['parts'].first['values'][0] = -999
    assert_equal 'Kích thước', Studio::Parametric::CATEGORIES['dimension']
    assert_raises(Core::Error) { Core.plan(rule, snapshot, 'dayvan' => -1) }
    actual = Core.plan(rule, snapshot, 'dayvan' => 20)
    assert_equal expected, actual
    scaled = Core.copy_data(snapshot)
    scaled['parts'].each { |part| part['bounds'].each { |point| point[0] *= 1.2 } }
    scaled['envelope'] = Core.union(scaled['parts'])
    scaled['dc_inputs'] = {}
    scaled['parameter_values'] = saved
    scaled_before = JSON.generate(scaled)
    result = Studio::ScalePlan.plan(rule, freeze_data(scaled), saved)
    assert result['changed_count'].positive?
    assert_equal scaled_before, JSON.generate(scaled)
    assert_equal before, [JSON.generate(snapshot), JSON.generate(rule)]
    actual['parts'].first['bounds'][0][0] = -999
    assert_equal before, [JSON.generate(snapshot), JSON.generate(rule)]
  end

  def test_alias_lookup_and_numeric_instances_do_not_leak_state_between_features
    first = Studio::DCFormulas.function_aliases({})
    key = first.keys.first
    value = first[key].dup
    first[key].replace('unrelated')
    assert_equal value, Studio::DCFormulas.function_aliases({})[key]
    snapshot = source
    a = Studio::DCFormulas::Program.new(snapshot)
    b = Studio::DCFormulas::Program.new(snapshot)
    values = Core.formula_values(snapshot, a.controls)
    expected = b.evaluate(values)
    a.evaluate(values.merge('dayvan' => 20))
    assert_equal expected, b.evaluate(values)
    assert_equal expected, a.evaluate(values)
  end

  def test_studio_policy_keeps_att_failure_evidence_in_its_own_rule
    snapshot = source
    leaf = snapshot['dc_graph']['nodes'].find { |node| node['part_key'] }
    leaf['attributes']['_lenx_formula'] = 'unsupported_helper()'
    before = JSON.generate(snapshot)
    rule = Studio::StudioCalculation.build_system([snapshot])
    assert(rule['constraints'].any? { |entry| entry['source'] == 'dc_attributes' && entry['translated'] == false })
    assert(rule['warnings'].any? { |text| text.include?('ATT chưa dịch được') })
    assert_equal before, JSON.generate(snapshot)
  end
end

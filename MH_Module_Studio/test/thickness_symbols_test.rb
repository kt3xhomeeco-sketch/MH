# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioThicknessSymbolsTest < Minitest::Test
  Studio = MH::ModuleStudio

  def setup
    @snapshot = JSON.parse(File.read(File.join(__dir__,'fixtures/readable_nested_dc.json'),encoding:'UTF-8'))
    @rule = Studio::RuleSystem.build(@snapshot,Studio::Core.learn_module([@snapshot]))
  end

  def test_thresholds_and_actual_drivers_exclude_equal_sized_offsets
    symbols = Studio::ThicknessSymbols
    [17,17.6,18,18.6,18.6000000001].each { |value| assert_equal 'T1',symbols.role(value) }
    [0.2,8,11,16.99].each { |value| assert_equal 'T2',symbols.role(value) }
    [0,-1,19,25,'18'].each { |value| assert_nil symbols.role(value) }
    before = JSON.generate(@rule)
    normalized = symbols.normalize(@rule)
    rows = Studio::Parametric.variables(normalized).to_h { |row| [row['binding'],row] }
    assert_equal 'T1',rows['dayvan']['symbol']
    assert_equal 'T2',rows['hauday']['symbol']
    assert_equal 'luihau',rows['luihau']['symbol']
    assert_equal 'sauranh',rows['sauranh']['symbol']
    assert_equal before,JSON.generate(@rule)
    assert_equal @rule['formula_engine'],normalized['formula_engine']
  end

  def test_references_follow_rename_and_geometry_values_visibility_are_preserved
    brace = @snapshot['parts'].find { |part| part['name']=='Giằng Trước' }['key']
    rule = Studio::Parametric.edit_part_formula(@rule,brace,'lenz','dayvan + hauday + 60')
    normalized = Studio::ThicknessSymbols.normalize(rule)
    assert_equal 'T1 + T2 + 60',normalized.dig('part_formulas',brace,'lenz')
    assert_equal rule['exposed_parameter_keys'],normalized['exposed_parameter_keys']
    assert_equal Studio::Core.plan(rule,@snapshot,{})['parts'],Studio::Core.plan(normalized,@snapshot,{})['parts']
    assert_equal normalized,Studio::ThicknessSymbols.normalize(normalized)
    rows = Studio::Parametric.variables(normalized)
    rows.find { |row| row['binding']=='dayvan' }['value'] = 16
    edited = Studio::Parametric.edit_variables(normalized,rows)
    assert_equal 'T1',Studio::Parametric.variables(Studio::ThicknessSymbols.normalize(edited)).find { |row| row['binding']=='dayvan' }['symbol']
  end

  def test_duplicate_inputs_merge_to_one_variable_and_drive_both_bindings
    @rule['parameters'].find { |param| param['key']=='hauday' }['value'] = 17.5
    normalized = Studio::ThicknessSymbols.normalize(@rule)
    rows = Studio::Parametric.variables(normalized).to_h { |row| [row['binding'],row] }
    assert_equal 'T1',rows['dayvan']['symbol']
    refute rows.key?('hauday')
    assert_equal 'dayvan',normalized['parameter_binding_aliases']['hauday']
    assert_equal 18.6,Studio::Parametric.targets(normalized)['hauday']
    assert_equal 18.6,rows['dayvan']['value']
    assert_equal({'dayvan'=>18,'hauday'=>18},Studio::Parametric.linked_requests(normalized,{'hauday'=>18}))
    assert_raises(Studio::Core::Error) { Studio::Parametric.linked_requests(normalized,{'dayvan'=>18,'hauday'=>8}) }
    edited_rows = Studio::Parametric.variables(normalized)
    edited_rows.find { |row| row['binding']=='dayvan' }['symbol'] = 'VanChung'
    renamed = Studio::Parametric.edit_variables(normalized,edited_rows)
    assert_equal 18.6,Studio::Parametric.targets(renamed)['hauday']
    assert_equal 'VanChung',Studio::Parametric.binding_rows(renamed)['hauday']['symbol']
  end

  def test_grouped_options_show_shared_thickness_and_private_sections_with_mixed_values
    rule = Studio::ThicknessSymbols.normalize(@rule)
    modules = %w[A B].each_with_index.map do |pid,index|
      {'pid'=>pid,'name'=>"Module #{pid}",'rule'=>rule,'values'=>Studio::Parametric.targets(rule).merge('dayvan'=>index.zero? ? 17.6 : 18.6)}
    end
    rows = Studio::OptionsParameters.grouped(modules)
    common = rows.find { |row| row['id']=='common:T1' }
    assert common['mixed']
    assert_nil common['value']
    assert_equal %w[A B],(common['targets'].map { |target| target['pid'] })
    assert_equal 'common',rows.first['section_id']
    assert(rows.any? { |row| row['section_id']=='A' && row['targets'].first['variable_id']=='input:giang' })
    hidden = Studio::Parametric.variables(rule)
    hidden.find { |row| row['binding']=='dayvan' }['exported'] = false
    modules.last['rule'] = Studio::Parametric.edit_variables(rule,hidden)
    refute(Studio::OptionsParameters.grouped(modules).any? { |row| row['id']=='common:T1' })
    assert_equal 2,common['targets'].length
  end

  def test_merged_overlapping_layers_keep_the_original_high_envelope_face
    parts = [
      {'key'=>'frame','name'=>'Frame','bounds'=>[[0,0,0],[100,14,100]],'thickness_axis'=>1,'box_verified'=>true},
      {'key'=>'panel','name'=>'Panel','bounds'=>[[0,13,0],[100,24,100]],'thickness_axis'=>1,'box_verified'=>true}
    ]
    source = {'id'=>'layered','parts'=>parts,'envelope'=>[[0,0,0],[100,24,100]]}
    rule = Studio::ThicknessSymbols.normalize(Studio::RuleSystem.build(source))
    plan = Studio::Core.plan(rule,source,Studio::Parametric.targets(rule))
    assert_equal [14.0,14.0],plan['target'].values
    panel = plan['parts'].find { |part| part['key']=='panel' }
    assert_in_delta 10,panel['bounds'][0][1],0.000001
    assert_in_delta 24,panel['bounds'][1][1],0.000001
    assert_equal source['envelope'],Studio::Core.union(plan['parts'])
    assert_equal 'Module.Y + Module.LenY - T2',rule.dig('part_formulas','panel','y')
    current = source.merge('parts'=>plan['parts'],'parameter_values'=>plan['target'])
    smaller = Studio::Core.plan(rule,current,{'thickness_1'=>12})
    current = source.merge('parts'=>smaller['parts'],'parameter_values'=>smaller['target'])
    restored = Studio::Core.plan(rule,current,{'thickness_1'=>14})
    assert_equal source['envelope'],Studio::Core.union(restored['parts'])
    assert_empty Studio::ThicknessSymbols.merge_reference(Studio::Parametric.edit_part_formula(rule,'panel','y','9'))
  end
end

# encoding: UTF-8
require 'minitest/autorun'
require_relative 'fixtures'
require_relative '../scale_redraw'

class ModuleStudioScaleRedrawTest < Minitest::Test
  Core = MH::ModuleStudio::Core
  System = MH::ModuleStudio::RuleSystem
  Redraw = MH::ModuleStudio::ScaleRedraw

  def setup
    @source = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'readable_nested_dc.json'), encoding: 'UTF-8'))
    @rule = System.build(@source, Core.learn_module([@source]))
    @saved = @rule['parameters'].select { |param| param['editable'] }.to_h { |param| [param['key'], param['value']] }
  end

  def stretch(source, scales)
    copy = Marshal.load(Marshal.dump(source))
    copy['parts'].each { |part| part['bounds'] = part['bounds'].map { |point| point.each_with_index.map { |value, axis| value * scales[axis] } } }
    copy['envelope'] = Core.union(copy['parts'])
    copy['dc_inputs'] = {}
    copy['parameter_values'] = @saved
    copy
  end

  def verify(rule, source, scales, saved)
    scaled = stretch(source, scales)
    before = JSON.generate(scaled)
    result = Redraw.plan(rule, scaled, saved)
    assert_equal before, JSON.generate(scaled)
    assert Core.bounds_close?(Core.union(result['parts']), scaled['envelope'], 0.001)
    assert_equal saved, result['target']
    actual = scaled.merge('parts' => result['parts'], 'parameter_values' => result['target'])
    assert_equal 0, Core.plan(rule, actual, {})['changed_count']
    actual
  end

  def test_att_nonuniform_repeated_scale_and_subsequent_parameter_edit
    current = @source
    [[1.4, 1, 1], [1, 1.25, 0.8], [0.8, 0.9, 1.5], [1.2, 1.2, 1.2]].each do |scales|
      current = verify(@rule, current, scales, @saved)
      back = current['parts'].find { |part| part['name'] == 'Hậu' }
      assert_in_delta @saved['hauday'], Core.dimensions(back['bounds'])[1], 0.001
    end
    assert Core.plan(@rule, current, 'dayvan' => 20)['changed_count'].positive?
  end

  def test_ordinary_constraints_restore_mixed_axis_thickness_and_contacts
    source = StudioFixtures.cabinet(18)
    rule = System.build(source)
    saved = rule['parameters'].to_h { |param| [param['key'], param['value']] }
    actual = verify(rule, source, [1.5, 1.1, 0.8], saved)
    lookup = actual['parts'].to_h { |part| [part['key'], part] }
    assert_in_delta 18, Core.dimensions(lookup['left']['bounds'])[0], 0.001
    assert_in_delta 18, Core.dimensions(lookup['bottom']['bounds'])[2], 0.001
    assert_in_delta 18, lookup['bottom']['bounds'][0][0], 0.001
    assert_in_delta 1182, lookup['bottom']['bounds'][1][0], 0.001
  end

  def test_saved_inputs_after_edit_are_preserved
    edited = Core.plan(@rule, @source, 'dayvan' => 20, 'sauranh' => 10)
    @saved = edited['target']
    current = @source.merge('parts' => edited['parts'], 'parameter_values' => @saved)
    verify(@rule, current, [1.3, 1.1, 1.2], @saved)
  end

  def test_own_spreadsheet_formula_is_recomputed
    back = @source['parts'].find { |part| part['name'] == 'Hậu' }
    rule = MH::ModuleStudio::Parametric.edit_part_formula(@rule, back['key'], 'lenx', 'Module.LenX - 2 * 18.6 + 2 * 8')
    verify(rule, @source, [1.4, 1, 1], @saved)
  end

  def test_unsafe_shrink_rejected_without_changing_source
    scaled = stretch(@source, [0.01, 1, 1])
    before = JSON.generate(scaled)
    assert_raises(Core::Error) { Redraw.plan(@rule, scaled, @saved) }
    assert_equal before, JSON.generate(scaled)
  end

  def test_missing_values_and_topology_are_not_guessed
    assert_raises(Core::Error) { Redraw.plan(@rule, stretch(@source, [1.2, 1, 1]), {}) }
    scaled = stretch(@source, [1.2, 1, 1])
    scaled['parts'].pop
    assert_raises(Core::Error) { Redraw.plan(@rule, scaled, @saved) }
  end

  def test_ordinary_parameter_edits_still_reject_scaled_att_baseline
    assert_match 'khác công thức ATT', assert_raises(Core::Error) { Core.plan(@rule, stretch(@source, [1.2, 1, 1]), 'dayvan' => 20) }.message
  end

  def test_repeated_shrink_keeps_inactive_geometry_scaled_instead_of_restoring_template_extents
    source = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'offset_origin_cabinet.json'), encoding: 'UTF-8'))
    rule = System.build(source, Core.learn_module([source]))
    @saved = rule['parameters'].select { |param| param['editable'] }.to_h { |param| [param['key'], param['value']] }
    current = source
    [[1.8648045853200883, 1, 1.6482244112361], [0.5, 1, 1], [1, 0.5, 1], [1, 1, 0.5], [1.8, 1.7, 1.6], [0.7, 0.7, 0.7]].each do |scales|
      stretched = stretch(current, scales)
      hidden = stretched['parts'].select { |part| part['visible'] == false }.to_h { |part| [part['key'], part['bounds']] }
      refute_empty hidden
      current = verify(rule, current, scales, @saved)
      current['parts'].select { |part| part['visible'] == false }.each do |part|
        assert Core.bounds_close?(hidden.fetch(part['key']), part['bounds'], 0.000001), 'Inactive geometry must retain its actual scaled shape.'
      end
    end
    assert Core.plan(rule, current, 'abh13iq2kv' => 20)['changed_count'].positive?
  end
end

# frozen_string_literal: true
require 'json'
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioDCParameterTest < Minitest::Test
  Core = MH::ModuleStudio::Core

  def samples
    JSON.parse(File.read(File.join(__dir__, 'fixtures', 'dc_mixed_thickness.json'), encoding: 'UTF-8'))
  end

  def test_reads_two_distinct_parameters_with_geometry_validated_units
    choices = Core.dc_thickness_parameters(samples).to_h { |choice| [choice['dc_key'], choice] }

    assert_equal %w[ba4ulq2qnw ikqikbwfw7], choices.keys.sort
    assert_equal [18.6, 17.6, 17.6], choices['ba4ulq2qnw']['values'].values
    assert_equal [8, 8, 11], choices['ikqikbwfw7']['values'].values
    assert_equal 25.4, choices['ikqikbwfw7']['factor']
    assert_equal ['haucha / hậu'], choices['ikqikbwfw7']['part_keys']
    refute_match(/<[^>]*>/, choices['ikqikbwfw7']['label'])
  end

  def test_reads_fixed_back_setback_separately
    control = Core.dc_controls(samples.last)['iwc3l3ib0g']

    assert_equal 'Hậu Lùi', control['label']
    assert_equal 18, control['display_value']
    assert_equal 'mm', control['unit']
  end

  def test_back_uses_controlled_pair_without_rewriting_source_samples
    data = samples
    original = JSON.generate(data)
    rule = Core.learn_dc_parameter(data, 'ikqikbwfw7')

    assert_equal [8, 11], rule['sample_range']
    assert_equal %w[dc-state-2 dc-state-3], rule['training_sample_ids']
    assert_equal ['dc-state-1'], rule['ignored_sample_ids']
    assert_equal ['Hậu'], (rule['parts'].select { |part| part['driver'] }.map { |part| part['name'] })
    assert_equal 18, rule['control_context']['iwc3l3ib0g']['display_value']
    assert_equal original, JSON.generate(data)
  end

  def test_carcass_uses_first_pair_with_constant_back
    rule = Core.learn_dc_parameter(samples, 'ba4ulq2qnw')

    assert_equal %w[dc-state-1 dc-state-2], rule['training_sample_ids']
    assert_equal ['dc-state-3'], rule['ignored_sample_ids']
    assert_equal [17.6, 18.6], rule['sample_range']
    assert_equal 4, (rule['parts'].count { |part| part['driver'] })
  end

  def test_back_preview_updates_panel_depths_preserves_sides_and_envelope
    data = samples
    rule = Core.learn_dc_parameter(data, 'ikqikbwfw7')
    plan = Core.plan(rule, data.last, 9)
    parts = plan['parts'].to_h { |part| [part['name'], part] }

    assert_in_delta 9, Core.dimensions(parts['Hậu']['bounds'])[1], 0.001
    assert_in_delta 173, Core.dimensions(parts['Nóc']['bounds'])[1], 0.001
    assert_in_delta 173, Core.dimensions(parts['Đáy']['bounds'])[1], 0.001
    assert_in_delta 17.6, Core.dimensions(parts['Hông Trái']['bounds'])[0], 0.001
    assert_equal data.last['envelope'], plan['envelope']
    assert_equal 3, plan['changed_count']
  end

  def test_modified_fixed_setback_rejects_source_dc
    data = samples
    rule = Core.learn_dc_parameter(data, 'ikqikbwfw7')
    data.last['dc_inputs']['iwc3l3ib0g'] = 20 / 25.4

    error = assert_raises(Core::Error) { Core.plan(rule, data.last, 9) }
    assert_match 'Hậu Lùi', error.message
  end

  def test_simultaneous_changes_do_not_prove_an_independent_rule
    data = samples.values_at(0, 2)
    error = assert_raises(Core::Error) { Core.learn_dc_parameter(data, 'ikqikbwfw7') }

    assert_match 'giữ nguyên các tham số DC khác', error.message
  end

  def test_other_editable_inputs_are_conditions_even_without_thickness_labels
    data = samples
    data.each_with_index do |sample, index|
      sample['dc_inputs'].merge!('_gap_access' => 'TEXTBOX', '_gap_formlabel' => 'Dịch hậu', 'gap' => index)
    end

    assert_raises(Core::Error) { Core.learn_dc_parameter(data, 'ikqikbwfw7') }
  end

  def test_hidden_geometry_is_not_parameter_mapping_evidence
    data = samples
    data.each { |sample| sample['parts'].find { |part| part['name'] == 'Hậu' }['visible'] = false }

    assert_equal ['ba4ulq2qnw'], (Core.dc_thickness_parameters(data).map { |choice| choice['dc_key'] })
  end

  def test_ambiguous_unit_factors_are_not_guessed
    sample = samples.first
    sample['dc_inputs'] = { '_t_formlabel' => 'Độ dày', 't' => 1 }
    sample['parts'] = [1, 25.4].map do |thickness|
      { 'key' => thickness.to_s, 'bounds' => [[0, 0, 0], [200, 200, thickness]], 'visible' => true }
    end

    assert_empty Core.dc_thickness_parameters([sample])
  end

  def test_import_rejects_malformed_condition_data
    rule = Core.learn_dc_parameter(samples, 'ikqikbwfw7')
    rule['control_context']['broken'] = ['bad']

    assert_raises(Core::Error) { Core.rule!(rule) }
  end
end

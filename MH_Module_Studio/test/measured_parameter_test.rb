# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'fixtures'

class ModuleStudioMeasuredParameterTest < Minitest::Test
  Core = MH::ModuleStudio::Core
  Reader = MH::ModuleStudio::Reader

  def cabinet(thickness)
    sample = StudioFixtures.cabinet(thickness)
    sample['parts'].find { |part| part['key'] == 'top' }['bounds'][0][2] = 720 - thickness
    sample['parts'].find { |part| part['key'] == 'bottom' }['bounds'][1][2] = thickness
    sample['parameter'] = 18 # The old UI's default, deliberately wrong.
    sample
  end

  def test_reads_main_board_group_separately_from_back_and_hidden_panels
    sample = cabinet(17.6)
    hidden = Marshal.load(Marshal.dump(sample['parts'].last))
    hidden['visible'] = false
    6.times { |index| sample['parts'] << hidden.merge('key' => "hidden#{index}") }

    Core.use_measured_parameter!(sample)

    assert_equal 17.6, sample['parameter']
    assert_equal %w[bottom left right top], sample['parameter_source']['part_keys']
    assert_equal 8, Core.dimensions(sample['parts'].find { |part| part['key'] == 'back' }['bounds']).min
  end

  def test_ambiguous_groups_do_not_silently_choose_a_thickness
    sample = StudioFixtures.cabinet(25) # Two 25 mm sides and two 18 mm horizontals.
    sample['parts'].reject! { |part| part['key'] == 'shelf' }
    error = assert_raises(Core::Error) { Core.use_measured_parameter!(sample) }

    assert_match 'Nhập thủ công', error.message
    assert_equal 25, sample['parameter']
  end

  def test_capture_with_no_typed_value_measures_before_learning
    samples = [17.6, 18.6].map do |thickness|
      sample = cabinet(thickness)
      Reader.make_snapshot(sample['parts'], 'Measured capture', nil, { 'kind' => 'selection' })
    end
    rule = Core.learn(samples)

    assert_equal [17.6, 18.6], (samples.map { |sample| sample['parameter'] })
    assert_equal %w[bottom left right top], (rule['parts'].select { |part| part['driver'] }.map { |part| part['key'] }.sort)
    assert_equal [17.6, 18.6], rule['sample_range']
  end

  def test_learning_rejects_switching_to_another_automatic_group
    samples = [17.6, 18.6].map { |thickness| Core.use_measured_parameter!(cabinet(thickness)) }
    samples.last['parameter_source']['part_keys'] = ['back']

    error = assert_raises(Core::Error) { Core.learn(samples) }
    assert_match 'Nhóm tấm tự đọc độ dày đã thay đổi', error.message
  end
end

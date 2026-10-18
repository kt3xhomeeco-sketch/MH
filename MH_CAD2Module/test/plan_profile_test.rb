# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../manual_boxes'

class PlanProfileTest < Minitest::Test
  def edges
    JSON.parse(File.read(File.join(__dir__, 'fixtures', 'sp41_curved_prism.json')))
  end

  def test_actual_rounded_prism_keeps_radius_sweep_and_dimensions
    part = MH::CAD2Module::PlanProfile.prism(edges)
    assert_equal [118, 350, 1600], part['size']
    arc = part['plan_profile']['segments'].find { |s| s['type'] == 'arc' }
    assert_in_delta 100, arc['radius'], 0.001
    assert_in_delta Math::PI / 2, arc['sweep'].abs, 0.001
    assert_equal 40, arc['segments']
    mirrored = edges.map { |e| e.map { |x, y, z| [-x + 6000, y - 2000, z + 70] } }
    shape = MH::CAD2Module::PlanProfile.prism(mirrored)
    assert_equal [118, 350, 1600], shape['size']
    assert_in_delta arc['sweep'].abs, shape['plan_profile']['segments'].find { |s| s['type'] == 'arc' }['sweep'].abs, 0.001
  end

  def test_invalid_open_noncircular_or_tapered_inputs_are_rejected
    data = edges
    assert_raises(ArgumentError) { MH::CAD2Module::PlanProfile.prism(data.drop(1)) }
    tapered = data.map { |e| e.map { |x, y, z| [x + (z > 100 ? 20 : 0), y, z] } }
    assert_raises(ArgumentError) { MH::CAD2Module::PlanProfile.prism(tapered) }
    ellipse = data.map { |e| e.map { |x, y, z| [x * 2, y, z] } }
    assert_raises(ArgumentError) { MH::CAD2Module::PlanProfile.prism(ellipse) }
  end

  def test_complete_measured_source_bounds_allow_curved_correction_but_reject_wrong_source
    analysis = { 'build_stages' => { 'elevation' => false }, 'envelope' => [0, 0, 2758, 350],
                 'source_plan_envelope' => [0, 0, 2860, 350] }
    boxes = [{ 'origin' => [0, 0, 0], 'size' => [2860, 350, 1600] }]
    assert_equal [2860, 350, 1600], MH::CAD2Module::ManualBoxes.parts({ 'boxes' => boxes }, analysis)['bounds']
    boxes[0]['size'][0] = 1310
    assert_raises(ArgumentError) { MH::CAD2Module::ManualBoxes.parts({ 'boxes' => boxes }, analysis) }
  end
end

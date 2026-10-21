# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../plan_reference'

class PlanReferenceTest < Minitest::Test
  def product
    { 'view_analysis' => { 'selected_view_id' => 'V1' }, 'plan_reference' => {
      'schema' => 1, 'view_id' => 'V1', 'source_origin_mm' => [100_000, 12_000],
      'segments' => [{ 'type' => 'line', 'start' => [0, 0], 'end' => [18, 600] },
                     { 'type' => 'arc', 'start' => [100, 0], 'end' => [0, 100], 'center' => [0, 0], 'radius' => 100, 'sweep' => Math::PI / 2 }] } }
  end

  def test_measured_line_and_arc_validate
    assert MH::CAD2Module::PlanReference.validate(product)
  end

  def test_side_and_vertical_cut_have_their_own_requested_tag
    assert_equal 'MH_DWG2', MH::CAD2Module::PlanReference.view_tag('role' => 'section_vertical', 'plane' => 'YZ')
    assert_equal 'MH_DWG1', MH::CAD2Module::PlanReference.view_tag('role' => 'front_check', 'plane' => 'XZ')
    %w[front_open front_unspecified plan].each do |role|
      assert_equal 'MH_DWG', MH::CAD2Module::PlanReference.view_tag('role' => role)
    end
  end

  def test_wrong_view_and_forged_arc_endpoint_rejected
    value = product
    value['plan_reference']['view_id'] = 'other'
    assert_raises(ArgumentError) { MH::CAD2Module::PlanReference.validate(value) }
    value = product
    value['plan_reference']['segments'].last['end'] = [1, 100]
    assert_raises(ArgumentError) { MH::CAD2Module::PlanReference.validate(value) }
  end

  def test_nonfinite_coordinates_and_unsupported_segment_rejected
    value = product
    value['plan_reference']['segments'][0]['start'] = [Float::INFINITY, 0]
    assert_raises(ArgumentError) { MH::CAD2Module::PlanReference.validate(value) }
    value = product
    value['plan_reference']['segments'][0]['type'] = 'spline'
    assert_raises(ArgumentError) { MH::CAD2Module::PlanReference.validate(value) }
  end
end

# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../placement'

class ElevationPlacementTest < Minitest::Test
  def product
    { 'plan_engine' => 'section-first-v1', 'build_stages' => { 'plan' => true, 'elevation' => true },
      'geometry_pipeline' => { 'horizontal' => { 'status' => 'measured' } },
      'source_plan_envelope' => [0, 200, 800, 800], 'plan_origin_offset_mm' => [0, 0],
      'placement' => { 'mode' => 'source_plan', 'plane' => 'XY', 'origin_mm' => [0, 200] },
      'modules' => [{ 'origin' => [0, 0, 1000], 'size' => [800, 600, 1400], 'source_box' => [0, 200, 800, 800],
                     'height_source' => 'linked_vertical_section', 'elevation_evidence' => {
                       'low_mm' => 1000, 'high_mm' => 2400, 'links' => [{ 'source_x_mm' => 400,
                         'cut_line' => [[4400, 1000], [4400, 3400]], 'section_base_mm' => 1000,
                         'tiers' => [{ 'low_mm' => 2000, 'high_mm' => 3400, 'handles' => ['cap', 'side'] }] }] } }],
      'trim_parts' => [], 'panel_parts' => [] }
  end

  def test_valid_measured_and_provisional_heights
    p = product
    MH::CAD2Module::Placement.validate_elevation_product(p)
    assert p.dig('geometry_check', 'passed')
    p['geometry_pipeline']['horizontal']['status'] = 'provisional'
    p['modules'][0].merge!('height_source' => 'provisional_default', 'elevation_pending' => true,
                           'origin' => [0, 0, 0], 'size' => [800, 600, 1600])
    MH::CAD2Module::Placement.validate_elevation_product(p)
    assert p.dig('geometry_check', 'passed')
    p['modules'][0].delete('elevation_pending')
    assert_raises(ArgumentError) { MH::CAD2Module::Placement.validate_elevation_product(p) }
  end

  def test_tampered_height_cut_location_and_xy_are_rejected
    [->(p) { p['modules'][0]['size'][2] += 25 },
     ->(p) { p['modules'][0]['elevation_evidence']['links'][0]['source_x_mm'] = 900 },
     ->(p) { p['modules'][0]['elevation_evidence']['links'][0]['cut_line'][1][0] += 100 },
     ->(p) { p['placement']['origin_mm'][1] -= 50 }].each do |mutate|
      p = product; mutate.call(p)
      assert_raises(ArgumentError) { MH::CAD2Module::Placement.validate_elevation_product(p) }
    end
  end

  def test_manual_heights_require_explicit_user_confirmation
    p = product
    p['modules'][0]['height_source'] = 'user_confirmed'
    assert_raises(ArgumentError) { MH::CAD2Module::Placement.validate_elevation_product(p) }
    p['manual_boxes'] = true
    p['learning'] = { 'mode' => 'user_confirmed' }
    p['geometry_pipeline']['horizontal']['status'] = 'user_confirmed'
    p['modules'][0]['size'][2] = 1500
    MH::CAD2Module::Placement.validate_elevation_product(p)
    assert p.dig('geometry_check', 'passed')
  end

  def product_envelope
    p = product
    p['plan_view_id'] = 'P1'
    p['geometry_pipeline']['horizontal']['status'] = 'provisional'
    p['product_height'] = { 'status' => 'measured', 'basis' => 'linked_front_stock_envelope',
      'scope' => 'product_envelope_only', 'module_tiers_measured' => false, 'plan_view_id' => 'P1',
      'source_signature' => 'a' * 64, 'low_mm' => 50, 'high_mm' => 2450,
      'supports' => [{ 'view_id' => 'F1', 'view_box' => [4000, 950, 4800, 4000],
        'registration' => { 'status' => 'proven' }, 'low_mm' => 50, 'high_mm' => 2450,
        'panels' => [{ 'box' => [4000, 1000, 4018, 3400], 'handle' => 'left' },
                     { 'box' => [4782, 1000, 4800, 3400], 'handle' => 'right' }] }] }
    p['modules'][0].merge!('height_source' => 'product_elevation_bounds', 'elevation_pending' => true,
      'origin' => [0, 0, 50], 'size' => [800, 600, 2400],
      'elevation_evidence' => { 'source_signature' => 'a' * 64, 'low_mm' => 50, 'high_mm' => 2450 })
    p
  end

  def test_measured_product_envelope_keeps_partition_pending
    p = product_envelope
    MH::CAD2Module::Placement.validate_elevation_product(p)
    assert p.dig('geometry_check', 'passed')
    assert_equal 'provisional', p.dig('geometry_check', 'status')
  end

  def test_product_envelope_tampering_is_rejected
    [->(p) { p['modules'][0]['size'][2] = 1600 },
     ->(p) { p['product_height']['supports'][0]['panels'][0]['box'][2] += 10 },
     ->(p) { p['product_height']['supports'][0]['low_mm'] = 0 },
     ->(p) { p['modules'][0]['origin'][2] = 0 },
     ->(p) { p['product_height']['module_tiers_measured'] = true },
     ->(p) { p['modules'][0]['elevation_evidence']['source_signature'] = 'b' * 64 }].each do |mutate|
      p = product_envelope; mutate.call(p)
      assert_raises(ArgumentError) { MH::CAD2Module::Placement.validate_elevation_product(p) }
    end
  end
end

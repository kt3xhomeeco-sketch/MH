# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../placement'

class PlacementTest < Minitest::Test
  def test_whole_product_centred_on_label
    assert_in_delta 8140, MH::CAD2Module::Placement.base_x(9000, 1720), 0.001
    assert_in_delta 9000, MH::CAD2Module::Placement.base_x(9000, 1720) + 860, 0.001
  end

  def test_invalid_sizes_rejected
    placement = MH::CAD2Module::Placement
    assert placement.validate_module('size' => [860, 582, 2110], 'origin' => [0, 18, 50])
    assert_raises(ArgumentError) { placement.validate_module('size' => [860, -1, 2110], 'origin' => [0, 0, 0]) }
    assert_raises(ArgumentError) { placement.validate_module('size' => [Float::NAN, 582, 2110], 'origin' => [0, 0, 0]) }
  end

  def test_source_placement_uses_cad_origin_and_plane_offset
    placement = MH::CAD2Module::Placement
    data = { 'origin_mm' => [1000, 2000], 'plane_offset_mm' => 73, 'plane' => 'XY' }
    matrix = placement.source_matrix(data)
    assert_equal [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0], matrix.first(12)
    assert_equal [1000 / 25.4, 2000 / 25.4, 73 / 25.4], matrix[12, 3]
    assert_equal [1000 / 25.4, 73 / 25.4, 2000 / 25.4], placement.source_matrix(data.merge('plane' => 'XZ'))[12, 3]
    assert_equal [73 / 25.4, 1000 / 25.4, 2000 / 25.4], placement.source_matrix(data.merge('plane' => 'YZ'))[12, 3]
    assert_raises(ArgumentError) { placement.source_matrix(data.merge('plane' => 'bad')) }
  end

  def test_touching_modules_not_overlap
    a = { 'origin' => [0, 18, 50], 'size' => [860, 582, 2110] }
    b = { 'origin' => [860, 18, 50], 'size' => [860, 582, 2110] }
    refute MH::CAD2Module::Placement.overlap?(a, b)
    b['origin'][0] = 850
    assert MH::CAD2Module::Placement.overlap?(a, b)
  end

  def ai_product
    { 'local_ai' => { 'workflow' => 'ai_plan_search_v2', 'status' => 'choose', 'final_check' => { 'passed' => true } },
      'geometry_pipeline' => { 'vertical' => { 'view_id' => 'P' } },
      'views' => [{ 'id' => 'P', 'role' => 'plan', 'region' => [1000, 2000, 1820, 2600] }],
      'source_plan_envelope' => [1000, 2000, 1820, 2600], 'plan_origin_offset_mm' => [0, 0],
      'placement' => { 'mode' => 'source_plan', 'plane' => 'XY', 'origin_mm' => [1000, 2000], 'plane_offset_mm' => 73 },
      'rectangles' => [{ 'box' => [1000, 2000, 1018, 2600] }],
      'modules' => [{ 'id' => 'M1', 'origin' => [0, 0, 0], 'size' => [820, 600, 1600] }], 'trim_parts' => [], 'panel_parts' => [] }
  end

  def test_ai_preflight_accepts_current_dimensions_without_template_identity
    product = ai_product
    MH::CAD2Module::Placement.validate_ai_product(product)
    assert product.dig('local_ai', 'native_preflight', 'passed')
    assert_equal 820, product['modules'][0]['size'][0]
  end

  def test_ai_preflight_rejects_unchecked_wrong_origin_and_wall_cut
    placement = MH::CAD2Module::Placement
    product = ai_product
    product['local_ai']['final_check']['passed'] = false
    assert_raises(ArgumentError) { placement.validate_ai_product(product) }
    product = ai_product
    product['placement']['origin_mm'][0] += 25
    assert_raises(ArgumentError) { placement.validate_ai_product(product) }
    product = ai_product
    product['modules'][0]['origin'][0] = 9
    assert_raises(ArgumentError) { placement.validate_ai_product(product) }
  end

  def test_ai_preflight_rejects_auxiliary_overlap_and_wrong_height
    placement = MH::CAD2Module::Placement
    product = ai_product
    product['trim_parts'] = [{ 'id' => 'T1', 'origin' => [0, 0, 0], 'size' => [18, 600, 1600] }]
    assert_raises(ArgumentError) { placement.validate_ai_product(product) }
    product = ai_product
    product['modules'][0]['size'][2] = 1500
    assert_raises(ArgumentError) { placement.validate_ai_product(product) }
  end

  def test_double_wall_envelope_does_not_remove_explicit_joint
    left = [1092, 0, 1110, 705]; right = [1110, 0, 1128, 705]; envelope = [1092, 0, 1128, 705]
    assert_equal [left, right], MH::CAD2Module::Placement.board_rectangles([left, right, envelope], 0)
    assert_equal [envelope], MH::CAD2Module::Placement.board_rectangles([envelope], 0)
    [3, 9].each do |stock|
      board = [0, 0, stock, 500]
      assert_equal [board], MH::CAD2Module::Placement.board_rectangles([board], 0)
    end
  end

  def test_native_preflight_preserves_stepped_outline_without_locking_grouping
    placement = MH::CAD2Module::Placement
    points = [[0, 0], [800, 0], [800, 600], [200, 600], [200, 400], [0, 400]]
    profile = { 'schema' => 1, 'segments' => (points + [points.first]).each_cons(2).map { |a, b| { 'type' => 'line', 'start' => a, 'end' => b } } }
    product = { 'geometry_pipeline' => { 'measured_stepped_footprints' => [{ 'box' => [1000, 2000, 1800, 2600], 'profile' => profile }] } }
    parts = [{ 'origin' => [0, 0, 0], 'size' => [800, 600, 1600], 'plan_profile' => profile }]
    placement.validate_stepped_footprints(product, parts, [1000, 2000])
    parts[0].delete('plan_profile')
    assert_raises(ArgumentError) { placement.validate_stepped_footprints(product, parts, [1000, 2000]) }
    parts = [{ 'origin' => [0, 0, 0], 'size' => [200, 400, 1600] }, { 'origin' => [200, 0, 0], 'size' => [600, 600, 1600] }]
    placement.validate_stepped_footprints(product, parts, [1000, 2000])
    assert_raises(ArgumentError) { placement.validate_stepped_footprints(product, parts.drop(1), [1000, 2000]) }
  end

  def test_preview_requires_exact_measured_envelope_and_remains_needs_review
    placement = MH::CAD2Module::Placement
    p = ai_product
    p.delete('local_ai')
    p.merge!('status' => 'needs_review', 'build_stages' => { 'elevation' => false }, 'envelope' => [1000, 2000, 1820, 2600],
             'envelope_preview' => { 'kind' => 'selected_cad_envelope', 'reason' => 'Unknown plan' },
             'outlines' => [{ 'points' => [[1000, 2000], [1820, 2000], [1820, 2600], [1000, 2600], [1000, 2000]] }])
    p['modules'][0]['rule'] = 'source-envelope-preview-v1'
    assert placement.validate_envelope_preview(p)
    assert_equal 'needs_review', p['status']
    p['modules'][0]['size'][0] += 1
    assert_raises(ArgumentError) { placement.validate_envelope_preview(p) }
    p['modules'][0]['size'][0] -= 1
    p['placement']['origin_mm'][0] += 10
    assert_raises(ArgumentError) { placement.validate_envelope_preview(p) }
  end
end

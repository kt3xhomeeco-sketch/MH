# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../manual_boxes'

class ManualBoxesTest < Minitest::Test
  def test_combined_stage_keeps_plan_frame_and_allows_vertical_tiers
    source = { 'plan_engine' => 'section-first-v1', 'build_stages' => { 'elevation' => true },
               'envelope' => [1000, 2000, 1800, 2600], 'source_plan_envelope' => [1000, 2000, 1800, 2600],
               'placement' => { 'mode' => 'source_plan', 'origin_mm' => [1000, 2000] } }
    capture = { 'boxes' => [{ 'origin' => [0, 0, 1000], 'size' => [800, 600, 1200] }],
                'normalised_from' => [0, 12, 0] }
    parts = MH::CAD2Module::ManualBoxes.parts(capture, source)
    assert_equal [1000, 2000, 1800, 2600], parts['modules'][0]['source_box']
    assert_equal 1000, parts['modules'][0]['origin'][2]
    assert_equal [0, 12], MH::CAD2Module::ManualBoxes.plan_offset(parts, source, capture)
  end
  def test_source_correction_keeps_box_y_when_module_widths_changed
    source = { 'build_stages' => { 'elevation' => false }, 'envelope' => [1000, 377.606283, 4588, 951.592283],
               'placement' => { 'mode' => 'source_plan', 'origin_mm' => [1000, 377.606283] },
               'modules' => [{ 'origin' => [0, 23.986, 0], 'size' => [1336, 573.986, 1600] }] }
    parts = { 'modules' => [{ 'origin' => [0, 0, 0], 'size' => [1300, 550, 1600] }] }
    capture = { 'normalised_from' => [0, 23.986, 0] }
    assert_equal [0, 23.986], MH::CAD2Module::ManualBoxes.plan_offset(parts, source, capture)
    source['plan_origin_offset_mm'] = [0, 23.986]
    source['plan_origin_basis'] = 'source_plan_envelope'
    source['placement']['origin_mm'][1] += 23.986
    capture['normalised_from'] = [0, 0, 0]
    assert_equal [0, 23.986], MH::CAD2Module::ManualBoxes.plan_offset(parts, source, capture)
    capture['normalised_from'] = [0, -5000, 0]
    assert_equal [0, 23.986], MH::CAD2Module::ManualBoxes.plan_offset(parts, source, capture)
  end
  def test_new_thin_stock_sizes_remain_auxiliary_in_manual_feedback
    [3, 9].each do |stock|
      boxes = [{ 'origin' => [stock, 0, 0], 'size' => [800, 600, 1600] }, { 'origin' => [0, 0, 0], 'size' => [stock, 600, 1600] }]
      result = MH::CAD2Module::ManualBoxes.parts({ 'boxes' => boxes }, {})
      assert_equal 1, result['modules'].length
      assert_equal stock, result['trim_parts'].first['stock_thickness_mm']
    end
  end
  def edges
    points = 8.times.map { |n| [100 + n[0] * 800, -700 + n[1] * 600, 300 + n[2] * 1600] }
    3.times.flat_map do |axis|
      8.times.filter_map { |n| [points[n], points[n | (1 << axis)]] if n[axis].zero? }
    end
  end

  def test_box_is_measured_from_real_edges_and_split_edges_are_supported
    segments = edges
    a, b = segments.shift
    midpoint = 3.times.map { |i| (a[i] + b[i]) / 2.0 }
    segments += [[a, midpoint], [midpoint, b]]
    box = MH::CAD2Module::ManualBoxes.cuboid(segments)
    assert_equal [100, -700, 300], box['origin']
    assert_equal [800, 600, 1600], box['size']
  end

  def test_incomplete_or_physically_rotated_box_is_rejected
    assert_raises(ArgumentError) { MH::CAD2Module::ManualBoxes.cuboid(edges.drop(1)) }
    angle = Math::PI / 7
    rotated = edges.map { |edge| edge.map { |x, y, z| [x * Math.cos(angle) - y * Math.sin(angle), x * Math.sin(angle) + y * Math.cos(angle), z] } }
    assert_raises(ArgumentError) { MH::CAD2Module::ManualBoxes.cuboid(rotated) }
  end

  def test_parts_keep_relative_layout_and_distinguish_thin_auxiliary
    boxes = [{ 'origin' => [18, 0, 0], 'size' => [800, 600, 1600] }, { 'origin' => [0, 0, 0], 'size' => [18, 600, 1600] }]
    parts = MH::CAD2Module::ManualBoxes.parts({ 'boxes' => boxes }, { 'build_stages' => { 'elevation' => false }, 'envelope' => [1000, 2000, 1818, 2600] })
    assert_equal [818, 600, 1600], parts['bounds']
    assert_equal [18, 0, 0], parts['modules'].first['origin']
    assert_equal 1, parts['trim_parts'].length
    assert parts['trim_parts'].first['solid_proxy']
    assert_equal [1018, 2000, 1818, 2600], parts['modules'].first['source_box']
  end

  def test_plan_boxes_cannot_be_silently_attached_to_a_different_sized_source
    boxes = [{ 'origin' => [0, 0, 0], 'size' => [1310, 600, 1600] }]
    source = { 'build_stages' => { 'elevation' => false }, 'envelope' => [0, 0, 2254, 600] }
    error = assert_raises(ArgumentError) { MH::CAD2Module::ManualBoxes.parts({ 'boxes' => boxes }, source) }
    assert_includes error.message, '2254'
    assert_includes error.message, '1310'
    source['envelope'] = [0, 0, 1274, 591]
    assert_equal [1310, 600, 1600], MH::CAD2Module::ManualBoxes.parts({ 'boxes' => boxes }, source)['bounds']
  end

  def test_plan_correction_keeps_measured_module_x_and_back_plane
    parts = { 'modules' => [{ 'origin' => [36, 0, 0], 'size' => [1238, 600, 1600] }] }
    source = { 'build_stages' => { 'elevation' => false }, 'modules' => [{ 'origin' => [18, 0, 0], 'size' => [1238, 591, 1600] }] }
    assert_equal [-18, -9], MH::CAD2Module::ManualBoxes.plan_offset(parts, source)
    source['modules'] << source['modules'].first.dup
    assert_equal [0, 0], MH::CAD2Module::ManualBoxes.plan_offset(parts, source)
  end
  def test_full_source_anchor_does_not_use_partial_recognition_origin
    parts = { 'modules' => [{ 'origin' => [2196, 0, 0], 'size' => [664, 230, 1600] }] }
    source = { 'build_stages' => { 'elevation' => false }, 'envelope' => [2178, 0, 2860, 230],
               'source_plan_envelope' => [0, 0, 2860, 230],
               'modules' => [{ 'origin' => [18, 0, 0], 'size' => [664, 230, 1600] }] }
    assert_equal [0, 0], MH::CAD2Module::ManualBoxes.plan_offset(parts, source)
    source['envelope'] = [18, 9, 1292, 600]
    source['source_plan_envelope'] = [0, 0, 1310, 600]
    source['modules'] = [{ 'origin' => [18, 0, 0], 'size' => [1238, 591, 1600] }]
    parts['modules'] = [{ 'origin' => [36, 0, 0], 'size' => [1238, 600, 1600] }]
    assert_equal [0, 0], MH::CAD2Module::ManualBoxes.plan_offset(parts, source)
  end
end

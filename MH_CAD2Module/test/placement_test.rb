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
end

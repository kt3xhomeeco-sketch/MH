# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../ids'
require_relative '../selection_source'

class SelectionRequestTest < Minitest::Test
  def test_scan_request_needs_no_user_code_and_keeps_geometry
    source = { 'hash' => 'geometry', 'lines' => [], 'plane' => 'XY', 'plane_offset_mm' => 73 }
    first = MH::CAD2Module::SelectionSource.build_request(source)
    second = MH::CAD2Module::SelectionSource.build_request(source)
    assert_equal 'geometry', first['action']
    assert_same source, first['geometry']
    assert_equal true, first['automatic_scan']
    assert_equal 'Vùng quét CAD', first['name']
    assert_match(/\ASCAN-[0-9A-F-]{36}\z/, first['code'])
    refute_equal first['code'], second['code']
  end
end

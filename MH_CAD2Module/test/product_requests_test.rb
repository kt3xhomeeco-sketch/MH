# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../product_requests'

class ProductRequestsTest < Minitest::Test
  def test_inclusive_range_normalises_codes
    assert_equal %w[SP08 SP09 SP10 SP11], MH::CAD2Module::ProductRequests.parse(' sp8 ', 'SP11')
    assert_equal ['SP11'], MH::CAD2Module::ProductRequests.parse('SP11', 'SP11')
    assert_equal %w[SP008 SP009 SP010], MH::CAD2Module::ProductRequests.parse('SP008', 'SP010')
  end

  def test_single_code_in_either_field_and_legacy_lists
    requests = MH::CAD2Module::ProductRequests
    assert_equal ['SP08'], requests.parse('SP08', '')
    assert_equal ['SP11'], requests.parse('', 'SP11')
    assert_equal %w[SP01 SP03], requests.parse("SP01\nSP03")
    assert_equal ['Tủ bếp'], requests.parse('Tủ bếp')
  end

  def test_invalid_ranges_fail_before_jobs_start
    requests = MH::CAD2Module::ProductRequests
    [['', ''], ['SP11', 'SP08'], ['SP01, SP03', 'SP11'], ['Tủ bếp', 'SP11'], ['SP01', 'SP1001']].each do |first, last|
      assert_raises(ArgumentError) { requests.parse(first, last) }
    end
  end

  def test_bare_numbers_and_other_code_prefixes
    requests = MH::CAD2Module::ProductRequests
    assert_equal ['SP20'], requests.parse('20')
    assert_equal ['SP02'], requests.parse('', '2')
    assert_equal %w[SP20 D1 SP03], requests.parse("20\nD1;3")
    assert_equal ['D1'], requests.parse('D1')
    assert_equal %w[D1 D2 D3], requests.parse('D1', 'D3')
    assert_equal %w[SP20 SP21], requests.parse('20', '21')
    assert_raises(ArgumentError) { requests.parse('D1', 'SP03') }
  end
end

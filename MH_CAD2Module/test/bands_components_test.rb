# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../placement'

class BandsComponentsTest < Minitest::Test
  def read(name)
    JSON.parse(File.read(File.join(__dir__, 'fixtures', "#{name}.json"), encoding: 'UTF-8'))
  end

  def test_continuous_roof_and_plinth_pass_with_their_actual_depths
    p = read('sp25-bands-proof')
    MH::CAD2Module::Placement.validate_elevation_product(p)
    bands = p['modules'].select { |m| m['height_source'] == 'front_section_band' }
    assert_equal [[1992, 310, 30], [1992, 292, 50]], bands.map { |m| m['size'] }
    assert_equal 1, p['modules'].count { |m| m['unresolved'] }
  end

  def test_tampered_band_panel_height_depth_and_continuity_are_rejected
    [->(m) { m['size'][0] /= 2 }, ->(m) { m['size'][1] += 18 },
     ->(m) { m['elevation_evidence']['sections'].pop },
     ->(m) { m['elevation_evidence']['sections'][0]['panels'][0][3] -= 50 }].each do |mutate|
      p = read('sp25-bands-proof'); mutate.call(p['modules'].find { |m| m['name'] == 'Module chân' })
      assert_raises(ArgumentError) { MH::CAD2Module::Placement.validate_elevation_product(p) }
    end
  end

  def test_linked_l_components_keep_unclosed_end_and_heights_pending
    p = read('sp35-components-proof')
    MH::CAD2Module::Placement.validate_elevation_product(p)
    assert p.dig('geometry_check', 'passed')
    assert p['modules'].all? { |m| m['elevation_pending'] }
    assert_equal ['V04.1', 'V08.1'], p['plan_components']['front_matches'].map { |g| g['front_id'] }
  end

  def test_wrong_cut_axis_stock_pair_xy_and_false_closed_status_are_rejected
    [->(p) { p['plan_components']['cut_links'][0]['axis'] = 'vertical' },
     ->(p) { p['modules'][0]['plan_component_evidence']['walls'][0][2] += 80 },
     ->(p) { p['modules'][0]['origin'][0] += 18 },
     ->(p) { p['modules'][2]['unresolved'] = false }].each do |mutate|
      p = read('sp35-components-proof'); mutate.call(p)
      assert_raises(ArgumentError) { MH::CAD2Module::Placement.validate_elevation_product(p) }
    end
  end
end

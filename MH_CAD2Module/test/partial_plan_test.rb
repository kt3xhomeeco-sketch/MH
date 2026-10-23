# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../placement'

class PartialPlanTest < Minitest::Test
  def product
    JSON.parse(File.read(File.join(__dir__, 'fixtures/partial_plan_proof.json'), encoding: 'UTF-8'))
  end

  def test_partial_bays_and_separate_residuals_pass_native_preflight
    p = product
    MH::CAD2Module::Placement.validate_elevation_product(p)
    assert p.dig('geometry_check', 'passed')
    assert_equal 5, p.dig('partial_plan', 'confirmed_modules')
    assert_equal 3, p['modules'].count { |m| m['unresolved'] }
  end

  def test_wrong_height_wall_cap_pose_depth_and_residual_are_rejected
    [->(p) { p['modules'][0]['size'][2] += 18 },
     ->(p) { p['modules'][0]['elevation_evidence']['walls'][0][0] += 50 },
     ->(p) { p['modules'][0]['elevation_evidence']['caps'][0][0][0] += 80 },
     ->(p) { p['modules'][0]['elevation_evidence']['plan_witnesses'][0]['offset_mm'] += 18 },
     ->(p) { p['partial_plan']['depth_evidence']['section_check']['chosen_depth_mm'] += 5 },
     ->(p) { p['modules'][-1]['size'][2] += 18 },
     ->(p) { p['modules'][-1]['unresolved'] = false },
     ->(p) { p['trim_parts'][0]['origin'][0] += 1 }].each do |mutate|
      p = product; mutate.call(p)
      assert_raises(ArgumentError) { MH::CAD2Module::Placement.validate_elevation_product(p) }
    end
  end
end

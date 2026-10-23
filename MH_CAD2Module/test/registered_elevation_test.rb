# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../placement'

class RegisteredElevationTest < Minitest::Test
  def product
    JSON.parse(File.read(File.join(__dir__, 'fixtures/registered_elevation_proof.json'), encoding: 'UTF-8'))
  end

  def test_actual_eight_part_proof_passes
    p = product
    MH::CAD2Module::Placement.validate_elevation_product(p)
    assert p.dig('geometry_check', 'passed')
    assert_equal 4, p['modules'].length
    assert_equal 4, p['trim_parts'].length
  end

  def test_changed_height_caps_registration_or_auxiliary_projection_are_rejected
    mutations = [
      ->(p) { p['modules'][0]['size'][2] += 7 },
      ->(p) { p['modules'][0]['elevation_evidence']['section_caps'] = [] },
      ->(p) { p['modules'][0]['elevation_evidence']['section_caps'][0][1] += 40 },
      ->(p) { p['modules'][0]['elevation_evidence']['front_walls'][0][1] += 18 },
      ->(p) { p['trim_parts'][0]['origin'][0] += 18 },
      ->(p) { p['trim_parts'][0]['elevation_evidence']['front_panels'].pop },
      ->(p) { p['trim_parts'][2]['origin'][1] += 18 },
      ->(p) { p['trim_parts'][2]['elevation_evidence']['parallel_proof'] = 'size_guess' },
      ->(p) { p['trim_parts'][2]['elevation_evidence']['stock_mm'] = 20 },
      ->(p) { p['modules'][0]['elevation_evidence']['front_checks'].pop }
    ]
    mutations.each do |mutate|
      p = product; mutate.call(p)
      assert_raises(ArgumentError) { MH::CAD2Module::Placement.validate_elevation_product(p) }
    end
  end

  def proxy_product
    p = product
    a, b = p['trim_parts'].last(2)
    ev = a['elevation_evidence']
    ev['section_parts'] = [a, b].map do |part|
      proof = part['elevation_evidence']
      { 'box' => proof['section_panel'], 'stock_mm' => proof['stock_mm'], 'parallel_proof' => proof['parallel_proof'] }
    end
    ev.merge!('kind' => 'top_trim_proxy', 'confirmed_box_mm' => [50, 30], 'confirmation_event' => 'QA')
    a['size'][1] = 50; a['source_box'][3] = a['source_box'][1] + 50
    p['trim_parts'].pop
    p
  end

  def test_single_confirmed_trim_box_and_tampered_evidence
    MH::CAD2Module::Placement.validate_elevation_product(proxy_product)
    mutations = [
      ->(p) { p['trim_parts'].last['elevation_evidence']['confirmation_event'] = '' },
      ->(p) { p['trim_parts'].last['elevation_evidence']['section_parts'].pop },
      ->(p) { p['trim_parts'].last['elevation_evidence']['section_parts'][0]['parallel_proof'] = 'guess' },
      ->(p) { p['trim_parts'].last['elevation_evidence']['confirmed_box_mm'] = [68, 30] },
      ->(p) { p['trim_parts'].last['elevation_evidence']['section_parts'][1]['box'][0] += 1 }
    ]
    mutations.each do |mutate|
      p = proxy_product; mutate.call(p)
      assert_raises(ArgumentError) { MH::CAD2Module::Placement.validate_elevation_product(p) }
    end
  end
end

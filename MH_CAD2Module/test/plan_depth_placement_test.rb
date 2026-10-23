# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../placement'

class PlanDepthPlacementTest < Minitest::Test
  def product
    panels = [{ 'box_mm' => [0, 20, 18, 329.8], 'handles' => ['left'] },
              { 'box_mm' => [982, 20, 1000, 329.8], 'handles' => ['right'] }]
    section = { 'box_mm' => [2000, 1000, 2310, 3400], 'depth_mm' => 310,
      'panels' => [{ 'box_mm' => [2000, 1000, 2018, 3400], 'handles' => ['sleft'] },
                  { 'box_mm' => [2292, 1000, 2310, 3400], 'handles' => ['sright'] }] }
    { 'status' => 'needs_review', 'build_stages' => { 'elevation' => false }, 'envelope' => [0, 0, 1000, 500],
      'placement' => { 'mode' => 'source_plan', 'plane' => 'XY', 'origin_mm' => [0, 0] }, 'plan_view_id' => 'P1',
      'view_analysis' => { 'candidates' => [{ 'id' => 'P1', 'reference_family' => 'F' },
        { 'id' => 'S1', 'role' => 'section_vertical', 'reference_family' => 'F' },
        { 'id' => 'S2', 'role' => 'section_vertical', 'reference_family' => 'F' }] },
      'outlines' => [{ 'handle' => 'raw', 'points' => [[0, 0], [1000, 500]] },
                     { 'handle' => 'left', 'points' => [[0, 20], [18, 329.8]] },
                     { 'handle' => 'right', 'points' => [[982, 20], [1000, 329.8]] }],
      'modules' => [{ 'origin' => [0, 20, 0], 'size' => [1000, 310, 1600], 'rule' => 'source-envelope-preview-v1' }],
      'trim_parts' => [], 'panel_parts' => [],
      'envelope_preview' => { 'kind' => 'selected_cad_envelope', 'dimensions_from' => 'closed_stock_depth',
        'depth_evidence' => { 'basis' => 'closed_compatible_stock_pairs', 'low_mm' => 20, 'high_mm' => 329.8, 'panels' => panels,
          'section_check' => { 'status' => 'supported', 'chosen_depth_mm' => 310, 'tolerance_mm' => 1, 'reference_family' => 'F',
            'sections' => [section.merge('view_id' => 'S1'), section.merge('view_id' => 'S2')] } } } }
  end

  def test_stock_depth_and_two_sections_confirm_small_plan_error
    assert MH::CAD2Module::Placement.validate_envelope_preview(product)
  end

  def test_bad_stock_foreign_sections_and_tampered_depth_are_rejected
    [->(p) { p['modules'][0]['size'][1] = 500 },
     ->(p) { p['envelope_preview']['depth_evidence']['panels'][0]['box_mm'][2] = 101 },
     ->(p) { p['view_analysis']['candidates'][1]['reference_family'] = 'other' },
     ->(p) { p['envelope_preview']['depth_evidence']['section_check']['chosen_depth_mm'] = 320 },
     ->(p) { p['envelope_preview']['depth_evidence']['section_check']['sections'][0]['view_id'] = 'S2' }].each do |mutate|
      p = product; mutate.call(p)
      assert_raises(ArgumentError) { MH::CAD2Module::Placement.validate_envelope_preview(p) }
    end
  end
end

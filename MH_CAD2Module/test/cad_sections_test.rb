# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../cad_views'

class CadSectionsTest < Minitest::Test
  def section
    { 'display_x_mm' => 500, 'display_y_mm' => 0, 'reversed_depth' => true,
      'section_position' => { 'basis' => 'cut_marker', 'front_id' => 'F', 'marker_handle' => 'M1',
                              'cut_line' => [[2500, -100], [2500, 2500]], 'source_origin_mm' => [0, 0], 'front_x_offset_mm' => -2000 },
      'direction_basis' => 'symbol_arrows', 'view_direction' => [1, 0],
      'arrow_heads' => [{ 'tip' => [2520, 0], 'tail_a' => [2500, -20], 'tail_b' => [2500, 20] }] }
  end

  def test_cut_position_and_arrow_direction_validate_independently_of_inspection_gap
    assert MH::CAD2Module::CadViews.validate_section(section, [0, 0, 1000, 600])
    [
      ->(v) { v['display_x_mm'] += 18 },
      ->(v) { v['display_y_mm'] = Float::INFINITY },
      ->(v) { v['reversed_depth'] = false },
      ->(v) { v['section_position']['cut_line'][0][0] += 20 },
      ->(v) { v['arrow_heads'].clear },
      ->(v) { v['arrow_heads'][0]['tip'][0] -= 40 }
    ].each do |change|
      v = section; change.call(v)
      refute MH::CAD2Module::CadViews.validate_section(v, [0, 0, 1000, 600])
    end
  end

  def test_missing_marker_uses_an_explicit_box_edge
    v = section; v.delete('direction_basis')
    v['section_position'] = { 'basis' => 'box_edge', 'box_mm' => [0, 0, 1000, 600], 'edge' => 'right' }
    v['display_x_mm'] = 1000
    assert MH::CAD2Module::CadViews.validate_section(v, [0, 0, 1000, 600])
    v['display_x_mm'] += 1000
    refute MH::CAD2Module::CadViews.validate_section(v, [0, 0, 1000, 600])
  end

  def test_depth_uses_cabinet_pairs_at_cut_and_rejects_shifted_y
    plan = { 'id' => 'P', 'role' => 'plan', 'reference_family' => 'F', 'xy_offset_mm' => [0, 0],
             'cabinet_datum' => { 'box_mm' => [0, 0, 1000, 600], 'bays_mm' => [[0, 0, 1000, 600]],
                                  'panels' => [{ 'box_mm' => [0, 0, 1000, 18] }, { 'box_mm' => [0, 582, 1000, 600] }] } }
    v = section.merge('reference_family' => 'F', 'anchor_box_mm' => [2000, 2000, 2600, 2900],
                      'cabinet_datum' => { 'box_mm' => [2000, 2000, 2600, 2900] },
                      'depth_alignment' => { 'basis' => 'cut_footprint', 'plan_id' => 'P', 'plan_y_mm' => 0, 'plan_x_mm' => 500,
                                             'plan_shift_mm' => [0, 0], 'side_box_mm' => [2000, 2000, 2600, 2900] })
    assert MH::CAD2Module::CadViews.validate_depth(v, [plan, v])
    [
      ->(s) { s['display_y_mm'] += 185 },
      ->(s) { s['display_y_mm'] += 185; s['depth_alignment']['plan_y_mm'] += 185 },
      ->(s) { s['anchor_box_mm'][2] += 25 },
      ->(s) { s['depth_alignment']['plan_x_mm'] += 20 },
      ->(s) { s['reference_family'] = 'OTHER' }
    ].each do |change|
      copy = Marshal.load(Marshal.dump(v)); change.call(copy)
      refute MH::CAD2Module::CadViews.validate_depth(copy, [plan, copy])
    end
  end
end

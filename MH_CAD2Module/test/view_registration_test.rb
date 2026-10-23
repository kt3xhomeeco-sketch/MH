# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../cad_views'

class ViewRegistrationTest < Minitest::Test
  def sample
    root = { 'id' => 'P', 'role' => 'plan', 'reference_family' => 'F', 'plane' => 'XY', 'xy_offset_mm' => [0, 0],
             'cabinet_datum' => { 'panels' => [{ 'box_mm' => [0, 0, 18, 600] }, { 'box_mm' => [982, 0, 1000, 600] }] } }
    front = { 'id' => 'F', 'role' => 'front_open', 'reference_family' => 'F', 'plane' => 'XZ', 'x_offset_mm' => -4000,
              'cabinet_datum' => { 'panels' => [{ 'box_mm' => [4000, 2000, 4018, 4400] }, { 'box_mm' => [4982, 2000, 5000, 4400] }] } }
    link = { 'target_id' => 'P', 'source_id' => 'F', 'axis' => 'W', 'target_axis' => 0, 'source_axis' => 0,
             'status' => 'proven', 'scale' => 1, 'offset_mm' => -4000, 'matched_pairs' => 2,
             'candidates' => [{ 'offset_mm' => -4000, 'scale' => 1, 'matched_pairs' => 2, 'coverage' => 1,
                                'matches' => [{ 'target' => [0, 18], 'source' => [4000, 4018] }, { 'target' => [982, 1000], 'source' => [4982, 5000] }] }] }
    front['axis_registration'] = { 'W' => { 'status' => 'proven', 'root_id' => 'P', 'view_id' => 'F', 'scale' => 1, 'offset_mm' => -4000, 'path' => [link] } }
    [root, front]
  end

  def test_matched_pairs_validate_against_each_views_measured_stock
    views = sample
    assert MH::CAD2Module::CadViews.validate_registration(views.last, views, [0, 0], [])
    views.last['drawing_x_offset_mm'] = 9000 # Display placement never changes registration.
    assert MH::CAD2Module::CadViews.validate_registration(views.last, views, [0, 0], [])
  end

  def test_wrong_transform_stock_repeated_votes_and_tied_candidates_are_rejected
    [
      ->(v, w) { v['x_offset_mm'] += 18 },
      ->(_v, w) { w['root_id'] = 'OTHER' },
      ->(_v, w) { w['path'][0]['scale'] = 1.1 },
      ->(_v, w) { w['path'][0]['candidates'][0]['matches'][0]['source'][1] += 1 },
      ->(_v, w) { w['path'][0]['candidates'] << Marshal.load(Marshal.dump(w['path'][0]['candidates'][0])) },
      ->(_v, w) { w['path'][0]['candidates'][0]['matches'][1] = w['path'][0]['candidates'][0]['matches'][0] }
    ].each do |change|
      views = sample; v = views.last; change.call(v, v['axis_registration']['W'])
      assert_raises(ArgumentError) { MH::CAD2Module::CadViews.validate_registration(v, views, [0, 0], []) }
    end
  end

  def test_one_changed_gap_is_not_the_same_as_uniform_scaling
    g = { 'target_stations' => [[0, 18], [400, 418], [1000, 1018], [1700, 1718]],
          'source_stations' => [[10000, 10018], [10400, 10418], [12600, 12618], [13300, 13318]],
          'break_after' => 1, 'sequence_coverage' => 1, 'left_offset_mm' => -10000, 'right_offset_mm' => -11600,
          'gap_difference_mm' => -1600, 'anchor_side' => 'left' }
    link = { 'changed_gap' => g, 'offset_mm' => -10000 }
    assert MH::CAD2Module::CadViews.validate_changed_gap(link)
    g['source_stations'][1] = [10440, 10458]
    assert_raises(ArgumentError) { MH::CAD2Module::CadViews.validate_changed_gap(link) }
  end

  def test_height_checks_must_cross_real_boards_at_a_shared_floor_and_unique_pose
    views = sample; link = views.last['axis_registration']['W']['path'].first
    link['height_support'] = 3
    link['height_checks'] = [100, 300, 500].map do |z|
      { 'height_mm' => z, 'target_slice' => z, 'source_slice' => z + 2000,
        'candidates' => Marshal.load(Marshal.dump(link['candidates'])) }
    end
    assert MH::CAD2Module::CadViews.validate_registration(views.last, views, [0, 0], [])
    link['height_checks'].each { |c| c['source_slice'] += 10_000 }
    assert_raises(ArgumentError) { MH::CAD2Module::CadViews.validate_registration(views.last, views, [0, 0], []) }
  end
end

# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../cad_views'

class CadLevelsTest < Minitest::Test
  def data
    { 'view_id' => 'P', 'z_mm' => 700, 'xy_offset_mm' => [0, -5000], 'level' => {
      'view_id' => 'P', 'status' => 'measured', 'basis' => 'horizontal_cut_geometry', 'level_mm' => 700,
      'links' => [{ 'front_id' => 'F', 'marker_handle' => 'H3', 'front_box' => [4000, 1000, 5618, 3400],
                    'cut_line' => [[4000, 1700], [5618, 1700]], 'level_mm' => 700 }] } }
  end

  def test_measured_cut_level_and_explicit_unknown_zero
    assert MH::CAD2Module::CadViews.validate_level(data)
    assert MH::CAD2Module::CadViews.validate_level('id' => 'P', 'z_mm' => 0, 'level' => { 'view_id' => 'P', 'status' => 'pending' })
  end

  def test_changed_level_oblique_cut_or_wrong_view_is_rejected
    changes = [
      ->(v) { v['z_mm'] += 1 },
      ->(v) { v['level']['view_id'] = 'OTHER' },
      ->(v) { v['level']['links'].clear },
      ->(v) { v['level']['links'][0]['cut_line'][1][1] += 18 },
      ->(v) { v['level']['links'][0]['front_box'][1] += 18 },
      ->(v) { v['xy_offset_mm'][0] = Float::INFINITY },
      ->(v) { v['level']['status'] = 'pending' }
    ]
    changes.each do |change|
      v = data; change.call(v)
      assert_raises(ArgumentError) { MH::CAD2Module::CadViews.validate_level(v) }
    end
  end

  def provisional
    { 'id' => 'P', 'z_mm' => 1000, 'xy_offset_mm' => [-8300, 100], 'level' => {
      'view_id' => 'P', 'status' => 'provisional', 'basis' => 'inspection_spacing', 'level_mm' => 1000,
      'spacing_mm' => 1000, 'base_mm' => 0, 'slot_index' => 1, 'issue' => 'Missing cut marker' } }
  end

  def test_provisional_spacing_is_validated_and_cannot_claim_a_measured_level
    assert MH::CAD2Module::CadViews.validate_level(provisional)
    changes = [
      ->(v) { v['z_mm'] = 2000 },
      ->(v) { v['level']['spacing_mm'] = 500 },
      ->(v) { v['level']['slot_index'] = -1 },
      ->(v) { v['level']['base_mm'] = Float::NAN },
      ->(v) { v['level']['issue'] = '' },
      ->(v) { v['level']['status'] = 'measured' }
    ]
    changes.each do |change|
      v = provisional; change.call(v)
      assert_raises(ArgumentError) { MH::CAD2Module::CadViews.validate_level(v) }
    end
  end

  def test_single_plan_at_zero_retains_and_validates_nonzero_source_cut_level
    v = data; v['z_mm'] = 0
    v['level'].merge!('placement_basis' => 'single_plan_zero', 'placement_z_mm' => 0, 'plan_count' => 1)
    assert MH::CAD2Module::CadViews.validate_level(v)
    [
      ->(d) { d['z_mm'] = 700 },
      ->(d) { d['level']['plan_count'] = 2 },
      ->(d) { d['level']['placement_z_mm'] = 700 },
      ->(d) { d['level']['level_mm'] = Float::INFINITY },
      ->(d) { d['level']['links'][0]['cut_line'][0][1] += 10 }
    ].each do |change|
      copy = Marshal.load(Marshal.dump(v)); change.call(copy)
      assert_raises(ArgumentError) { MH::CAD2Module::CadViews.validate_level(copy) }
    end
  end
end

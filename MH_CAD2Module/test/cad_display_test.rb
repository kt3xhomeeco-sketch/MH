# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../plan_reference'

class CadDisplayTest < Minitest::Test
  def product
    JSON.parse(File.read(File.join(__dir__, 'fixtures/cad_display_reference.json'), encoding: 'UTF-8'))
  end

  def test_source_ownership_and_extra_xoz_copy_validate_separately
    p = product
    assert MH::CAD2Module::PlanReference.validate(p)
    copy = p['plan_reference']['display_copies'].first
    assert_equal 'XZ', copy['plane']
    assert_equal 'MH_DWG2', MH::CAD2Module::PlanReference.view_tag(copy)
    refute copy.key?('segment_indices')
  end

  def test_incorrect_copy_spacing_source_floor_and_open_front_placement_are_rejected
    [
      ->(r) { r['display_copies'].first['x_offset_mm'] += 18 },
      ->(r) { r['display_copies'].first['display_placement']['spacing_mm'] = 499 },
      ->(r) { r['display_copies'].first['source_view_id'] = r['view_id'] },
      ->(r) { r['display_copies'].first['anchor_box_mm'][1] += 50 },
      ->(r) { r['display_copies'].clear },
      ->(r) { r['views'].find { |v| v['role'] == 'front_open' }['drawing_x_offset_mm'] -= 500 }
    ].each do |change|
      p = product; change.call(p['plan_reference'])
      assert_raises(ArgumentError) { MH::CAD2Module::PlanReference.validate(p) }
    end
  end

  def test_new_overlay_rejects_a_display_offset_but_retains_legacy_archives
    p = product; r = p['plan_reference']; r['display_mode'] = 'front_overlay'
    fronts = r['views'].select { |v| %w[front_open front_check front_unspecified].include?(v['role']) }
    fronts.each { |v| v.delete('drawing_x_offset_mm'); v.delete('display_placement') }
    previous = fronts.max_by { |v| v['box_mm'][2] + v['x_offset_mm'] }
    r['display_copies'].each do |v|
      left = previous['box_mm'][2] + previous['x_offset_mm'] + 500
      v['x_offset_mm'] = left - v['box_mm'][0]
      v['display_placement'].merge!('min_x_mm' => left, 'after_view_id' => previous['id'])
      previous = v
    end
    assert MH::CAD2Module::PlanReference.validate(p)
    fronts.find { |v| v['role'] == 'front_open' }['drawing_x_offset_mm'] = 500
    assert_raises(ArgumentError) { MH::CAD2Module::PlanReference.validate(p) }
    assert MH::CAD2Module::PlanReference.validate(product)
  end
end

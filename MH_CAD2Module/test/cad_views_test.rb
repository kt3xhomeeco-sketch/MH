# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../plan_reference'

class CadViewsTest < Minitest::Test
  def product
    JSON.parse(File.read(File.join(__dir__, 'fixtures/cad_views_reference.json'), encoding: 'UTF-8'))
  end

  def test_actual_uncropped_views_validate
    assert MH::CAD2Module::PlanReference.validate(product)
  end

  def test_side_yz_is_valid_but_a_front_cannot_be_misclassified_as_yz
    p = product; p['plan_reference']['views'].last['plane'] = 'YZ'
    assert MH::CAD2Module::PlanReference.validate(p)
    p['plan_reference']['views'][1]['plane'] = 'YZ'
    assert_raises(ArgumentError) { MH::CAD2Module::PlanReference.validate(p) }
  end

  def test_missing_duplicate_or_misplaced_reference_segments_are_rejected
    changes = [
      ->(p) { p['plan_reference']['views'].first['segment_indices'].pop },
      ->(p) { p['plan_reference']['views'].first['segment_indices'] << 0 },
      ->(p) { p['plan_reference']['views'][1]['plane'] = 'AB' },
      ->(p) { p['plan_reference']['views'][1]['alignment'] = 'guess' },
      ->(p) { p['plan_reference']['views'][1]['anchor_box_mm'][0] = Float::INFINITY },
      ->(p) { p['plan_reference']['views'].last.delete('reversed_depth') },
      ->(p) { p['build_stages']['elevation'] = false },
      ->(p) { p['plan_reference']['scope'] = 'unknown' }
    ]
    changes.each do |change|
      p = product; change.call(p)
      assert_raises(ArgumentError) { MH::CAD2Module::PlanReference.validate(p) }
    end
  end
end

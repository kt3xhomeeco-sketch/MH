# encoding: UTF-8
require 'minitest/autorun'
require_relative 'fixtures'

class ModuleStudioCoreTest < Minitest::Test
  Core = MH::ModuleStudio::Core
  Reader = MH::ModuleStudio::Reader
  Frames = MH::ModuleStudio::Frames

  def test_recognizes_two_drivers_and_eight_contact_relations
    rule = StudioFixtures.rule
    assert_equal %w[left right], (rule['parts'].select { |p| p['driver'] }.map { |p| p['key'] })
    assert_equal 8, rule['relations'].length
    assert_equal 'three_or_more_samples', rule['status']
  end

  def test_resize_keeps_outer_faces_and_updates_all_followers
    current = StudioFixtures.cabinet(18)
    plan = Core.plan(StudioFixtures.rule, current, 25)
    rows = plan['parts'].to_h { |p| [p['key'], p] }
    assert_equal 6, plan['changed_count']
    assert_in_delta 0, rows['left']['bounds'][0][0]
    assert_in_delta 25, rows['left']['bounds'][1][0]
    assert_in_delta 775, rows['right']['bounds'][0][0]
    assert_in_delta 800, rows['right']['bounds'][1][0]
    %w[top bottom shelf back].each { |key| assert_in_delta 750, Core.dimensions(rows[key]['bounds'])[0] }
    assert_equal current['envelope'], Core.union(plan['parts'])
    assert_equal 18, Core.dimensions(current['parts'].first['bounds'])[0], 'Input must not be changed by preview'
  end

  def test_current_stretched_envelope_is_used_instead_of_training_dimensions
    current = StudioFixtures.cabinet(18, width: 1000, height: 900, depth: 650)
    plan = Core.plan(StudioFixtures.rule, current, 25)
    assert_equal [1000.0, 650.0, 900.0], Core.dimensions(Core.union(plan['parts']))
    assert_in_delta 950, Core.dimensions(plan['parts'].find { |p| p['key'] == 'shelf' }['bounds'])[0]
  end

  def test_thinning_uses_the_same_anchor
    plan = Core.plan(StudioFixtures.rule, StudioFixtures.cabinet(25), 18)
    assert_in_delta 0, plan['parts'][0]['bounds'][0][0]
    assert_in_delta 18, plan['parts'][0]['bounds'][1][0]
    assert_in_delta 764, Core.dimensions(plan['parts'][2]['bounds'])[0]
  end

  def test_two_samples_are_marked_provisional
    rule = Core.learn(StudioFixtures.samples.first(2))
    assert_equal 'two_samples_provisional', rule['status']
  end

  def test_three_identical_parameter_values_do_not_train
    samples = StudioFixtures.samples
    samples.each { |s| s['parameter'] = 18 }
    assert_raises(Core::Error) { Core.learn(samples) }
  end

  def test_different_part_sets_do_not_train
    samples = StudioFixtures.samples
    samples[1]['parts'].pop
    assert_raises(Core::Error) { Core.learn(samples) }
  end

  def test_duplicate_names_do_not_silently_match
    sample = StudioFixtures.cabinet(18)
    sample['parts'][1]['key'] = 'left'
    assert_raises(Core::Error) { Core.snapshot!(sample) }
  end

  def test_different_envelope_does_not_train
    samples = [StudioFixtures.cabinet(18), StudioFixtures.cabinet(25, width: 810)]
    assert_raises(Core::Error) { Core.learn(samples) }
  end

  def test_non_linear_motion_is_rejected
    samples = StudioFixtures.samples
    samples.each do |sample|
      shelf = sample['parts'].find { |p| p['key'] == 'shelf' }
      shelf['bounds'].each { |point| point[2] += (sample['parameter'] - 18)**2 }
    end
    assert_raises(Core::Error) { Core.learn(samples) }
  end

  def test_wrong_parameter_is_rejected
    samples = StudioFixtures.samples
    samples.each { |sample| sample['parameter'] += 5 }
    assert_raises(Core::Error) { Core.learn(samples) }
  end

  def test_different_live_driver_thickness_is_rejected
    current = StudioFixtures.cabinet(18)
    current['parts'][1]['bounds'][0][0] -= 2
    assert_raises(Core::Error) { Core.plan(StudioFixtures.rule, current, 25) }
  end

  def test_broken_live_joint_is_rejected
    current = StudioFixtures.cabinet(18)
    current['parts'][2]['bounds'][0][0] += 2
    assert_raises(Core::Error) { Core.plan(StudioFixtures.rule, current, 25) }
  end

  def test_uncertified_geometry_cannot_be_modified
    current = StudioFixtures.cabinet(18)
    current['parts'][2]['box_verified'] = false
    assert_raises(Core::Error) { Core.plan(StudioFixtures.rule, current, 25) }
  end

  def test_zero_or_negative_follower_size_is_rejected
    current = StudioFixtures.cabinet(18, width: 60)
    assert_raises(Core::Error) { Core.plan(StudioFixtures.rule, current, 40) }
  end

  def test_corrupt_rule_is_rejected_before_use
    rule = StudioFixtures.rule
    rule['parts'][0]['coefficients'][0][0]['slope'] = Float::INFINITY
    assert_raises(Core::Error) { Core.plan(rule, StudioFixtures.cabinet(18), 25) }
  end

  def test_imported_rule_cannot_reference_missing_parts
    rule = StudioFixtures.rule
    rule['relations'][0]['follower'] = 'unknown'
    assert_raises(Core::Error) { Core.rule!(rule) }
  end

  def test_imported_numeric_strings_are_normalized
    rule = StudioFixtures.rule
    rule['parts'][0]['coefficients'][0][0]['slope'] = '0'
    assert_equal 6, Core.plan(rule, StudioFixtures.cabinet(18), 25)['changed_count']
  end

  def test_simple_face_motion_that_changes_outer_envelope_is_rejected
    rule = StudioFixtures.rule
    rule['parts'].find { |p| p['key'] == 'left' }['coefficients'][0][0]['slope'] = -1
    assert_raises(Core::Error) { Core.plan(rule, StudioFixtures.cabinet(18), 25) }
  end

  def test_no_change_is_a_no_op
    plan = Core.plan(StudioFixtures.rule, StudioFixtures.cabinet(18), 18)
    assert_equal 0, plan['changed_count']
  end

  def test_gap_without_projected_overlap_does_not_create_a_joint
    samples = StudioFixtures.samples
    samples.each do |sample|
      shelf = sample['parts'].find { |p| p['key'] == 'shelf' }
      shelf['bounds'].each { |point| point[1] += 1000 }
      sample['envelope'] = Core.union(sample['parts'])
    end
    # The same remote shelf moves in X but does not touch either side in Y.
    rule = Core.learn(samples)
    refute(rule['relations'].any? { |r| r['follower'] == 'shelf' })
  end

  def test_saved_json_round_trip_keeps_the_plan
    rule = JSON.parse(JSON.generate(StudioFixtures.rule))
    plan = Core.plan(rule, StudioFixtures.cabinet(18), 21)
    assert_in_delta 758, Core.dimensions(plan['parts'][2]['bounds'])[0]
  end

  def test_transform_math_uses_column_major_and_physical_scale
    a = Frames::IDENTITY.dup; a[0] = 2; a[5] = 3; a[10] = 4
    b = Frames::IDENTITY.dup; b[12] = 5; b[13] = 7; b[14] = 9
    assert_equal [12, 27, 48], Frames.point(Frames.multiply(a, b), [1, 2, 3])
    assert_equal [2.0, 3.0, 4.0], ([0, 5, 10].map { |i| Frames.scale_frame(a)[i] })
  end

  def test_shear_is_rejected
    matrix = Frames::IDENTITY.dup; matrix[4] = 0.25
    assert_raises(Core::Error) { Frames.scale_frame(matrix) }
  end

  def test_mirrored_root_still_has_a_valid_local_frame
    matrix = Frames::IDENTITY.dup; matrix[0] = -2
    assert_equal 2.0, Frames.scale_frame(matrix)[0]
  end

  def test_box_bounds_alone_are_not_geometry_verification
    faces = Array.new(6) { Struct.new(:loops, :vertices).new([1], [1, 2, 3, 4]) }
    edges = Array.new(12)
    points = Frames.corners([[0, 0, 0], [1, 2, 3]])
    assert Reader.rectangular_box?(points, faces, edges, [])
    points[7][0] -= 0.3
    refute Reader.rectangular_box?(points, faces, edges, [])
  end

  def test_bridge_capture_preserves_names_and_never_marks_bbox_as_verified
    data = {
      'root' => 'root', 'meta' => { 'model_attrs' => { 'dynamic_attributes/panel' => '0.7' } },
      'definitions' => {
        'root' => { 'nodes' => [{ 'name' => 'Hông trái', 'definition' => 'd1', 'transform' => Frames::IDENTITY }] },
        'd1' => { 'name' => 'Group#10', 'hasGeometry' => true, 'faceCount' => 6, 'edgeCount' => 12,
                  'bounds' => [[0, 0, 0], [0.7, 20, 30]], 'nodes' => [] }
      }
    }
    snapshot = Reader.from_bridge(data, label: 'File mẫu', parameter: 17.78)
    assert_equal 'hông trái', snapshot['parts'][0]['key']
    assert_in_delta 17.78, Core.dimensions(snapshot['parts'][0]['bounds'])[0]
    refute snapshot['parts'][0]['box_verified']
    assert_equal '0.7', snapshot['dc_inputs']['panel']
  end

  def test_whole_model_wrapper_is_normalized_like_selection
    wrapper = Frames::IDENTITY.dup; wrapper[0] = 2; wrapper[12] = 1000
    data = { 'root' => 'root', 'definitions' => {
      'root' => { 'nodes' => [{ 'name' => 'Tủ', 'definition' => 'cabinet', 'transform' => wrapper }] },
      'cabinet' => { 'nodes' => [{ 'name' => 'Hông', 'definition' => 'panel' }], 'hasGeometry' => false },
      'panel' => { 'hasGeometry' => true, 'faceCount' => 6, 'edgeCount' => 12, 'bounds' => [[0, 0, 0], [1, 10, 20]] }
    } }
    snapshot = Reader.from_bridge(data, label: 'Tủ', parameter: 50.8)
    assert_equal 'hông', snapshot['parts'][0]['key']
    assert_in_delta 0, snapshot['parts'][0]['bounds'][0][0]
    assert_in_delta 50.8, Core.dimensions(snapshot['parts'][0]['bounds'])[0]
  end
end

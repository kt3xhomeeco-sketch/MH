# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'
require_relative 'formula_fixtures'

class ModuleStudioDrawerFramesTest < Minitest::Test
  S = MH::ModuleStudio

  def source
    JSON.parse(File.read(File.join(__dir__,'fixtures/drawer_550.json'),encoding:'UTF-8'))
  end

  def test_numeric_string_length_list_is_converted_by_declared_units_not_label
    data = source
    controls = S::Core.dc_controls(data)
    assert_equal 'mm',controls['hghe0m3ihb']['unit']
    assert_in_delta 550,controls['hghe0m3ihb']['display_value'],0.000001
    assert_equal '',controls['sfugahsazi']['unit']
    data['dc_inputs']['_hghe0m3ihb_formulaunits'] = 'FLOAT'
    assert_equal '',S::Core.dc_controls(data)['hghe0m3ihb']['unit']
  end

  def test_drawer_builds_att_rules_and_moves_the_actual_flat_ray_without_changing_its_shape
    data = source
    engine = S::Core.learn_module([data])
    rule = S::RuleSystem.build(data,engine)
    assert_equal 0,S::Core.plan(rule,data,{})['changed_count']
    assert_equal 10,engine['rules'].length
    plan = S::Core.plan(rule,data,'eqgyit1tf1'=>20,'erhqw_82nd'=>9)
    ray = plan['parts'].find { |part| part['name']=='ABF_minifixPlasticBase55' }
    assert ray['changed']
    S::Core.dimensions(ray['old_bounds']).zip(S::Core.dimensions(ray['bounds'])).each { |a,b| assert_in_delta a,b,0.000001 }
    assert_in_delta 1.4,ray['bounds'][0][0]-ray['old_bounds'][0][0],0.000001
    assert_in_delta 1,ray['bounds'][0][2]-ray['old_bounds'][0][2],0.000001
    assert S::Core.bounds_close?(S::Core.union(plan['parts']),data['envelope'],0.001)
    normalized = S::ThicknessSymbols.normalize(rule)
    rows = S::Parametric.variables(normalized).to_h { |row| [row['binding'],row] }
    assert_equal 'T1',rows['eqgyit1tf1']['symbol']
    assert_equal 'T2',rows['erhqw_82nd']['symbol']
    refute_equal 'T2',rows['hfwgp2tb7u']['symbol']
    assert_in_delta 13.5,S::Parametric.targets(normalized)['hfwgp2tb7u'],0.000001
  end

  def test_zero_formula_only_preserves_an_already_flat_axis
    node = {'attributes'=>{'_leny_formula'=>'0'},'local_bounds'=>[[0,0,0],[1,0,1]],'transform'=>S::Frames::IDENTITY.dup}
    assert S::DCFrames.flat_axis?(node,1)
    node['local_bounds'][1][1] = 1
    refute S::DCFrames.flat_axis?(node,1)
    node['attributes']['_leny_formula'] = '0'
    node['local_bounds'][1][1] = 0.03/25.4
    node['transform'][5] = 0.001
    assert S::DCFrames.flat_axis?(node,1),'Use actual captured thickness, including a scaled-flat symbol'
    node['local_bounds'][1][1] = 0
    node['attributes']['_leny_formula'] = 'parent!Thickness'
    refute S::DCFrames.flat_axis?(node,1)
  end

  def test_copy_index_belongs_to_each_instance_and_not_the_shared_definition
    definition = {'copy'=>2,'_z_formula'=>'copy*parent!height'}
    assert_equal({'_z_formula'=>'copy*parent!height'},S::DCFrames.merge_attributes(definition,{}))
    assert_equal 1,S::DCFrames.merge_attributes(definition,{'copy'=>1})['copy']
    assert_equal 2,definition['copy']
    assert_nil S::DCFrames.merge_attributes({'dynamic_attributes/copy'=>2},{},prefix:'dynamic_attributes/')['dynamic_attributes/copy']
  end

  def test_nested_relative_dimensions_use_parent_scale_without_double_applying_physical_nominal_dimensions
    data = JSON.parse(File.read(File.join(__dir__,'fixtures/readable_nested_dc.json'),encoding:'UTF-8'))
    program = S::DCFormulas::Program.new(data)
    values = S::Core.formula_values(data,program.controls)
    computed, = program.evaluate(values)
    data['parts'].each { |p| assert S::Core.bounds_close?(p['bounds'],computed[p['key']]) }
    # The drawer includes fixed-size ray symbols nested under a flat intermediate
    # group; numeric, symbolic and editable cell frames must agree on that axis.
    drawer = source
    positions = S::DCFormulas::SymbolicProgram.new(drawer).symbolic_positions
    ray = drawer['parts'].find { |p| p['name']=='ABF_minifixPlasticBase55' }
    assert positions[ray['key']].flatten(1).all?
    cells = S::DCFormulas::ParametricProgram.new(drawer)
    cells.symbolic_positions
    texts = cells.cell_formula_texts({})
    assert(texts[ray['key']].all? { |text| text && !text.include?('/ (0)') })
  end

  def test_flat_wire_motion_matrix_is_finite_and_preserves_every_flat_coordinate
    old = [[0,0,0],[100,0,50]]; target = [[3,2,1],[203,2,51]]
    part = {'face_count'=>0,'edge_count'=>5,'bounds'=>old}
    S::GeometryMotion.validate!(part,target,true)
    matrix = S::GeometryMotion.matrix(old,target)
    assert matrix.all?(&:finite?)
    result = S::Frames.box(S::Frames.corners(old).map { |point| 3.times.map { |axis| point[axis]*matrix[axis*5]+matrix[12+axis]*25.4 } })
    assert S::Core.bounds_close?(result,target,0.000001)
    assert_raises(S::Core::Error) { S::GeometryMotion.validate!(part,[[0,0,0],[100,2,50]],true) }
  end

  def test_nonbox_solids_can_translate_but_cannot_deform_or_become_flat
    part = {'name'=>'Profile','bounds'=>[[0,0,0],[100,20,50]],'box_verified'=>false,'face_count'=>20,'edge_count'=>40}
    S::GeometryMotion.validate!(part,[[1,2,3],[101,22,53]],true)
    assert_raises(S::Core::Error) { S::GeometryMotion.validate!(part,[[0,0,0],[110,20,50]],true) }
    assert_raises(S::Core::Error) { S::GeometryMotion.validate!(part,[[0,0,0],[100,0,50]],true) }
  end

  def test_list_visibility_changes_are_still_rejected_and_bad_geometry_is_not_accepted
    data = source
    rule = S::RuleSystem.build(data,S::Core.learn_module([data]))
    assert_raises(S::Core::Error) { S::Core.plan(rule,data,'hghe0m3ihb'=>500) }
    bad = source
    bad['parts'].find { |p| p['name']=='Hộc - Đáy' }['bounds'][1][0] += 5
    assert_raises(S::Core::Error) { S::Core.learn_module([bad]) }
    bad = source
    bad['dc_graph']['nodes'].find { |n| n['name']=='Hộc - Đáy' }['attributes']['_leny_formula'] = '0'
    assert_raises(S::Core::Error) { S::Core.learn_module([bad]) }
  end

  def test_relative_formula_below_a_scaled_container_matches_numeric_and_symbolic_geometry
    data = FormulaFixtures.snapshot
    carrier = data['dc_graph']['nodes'].find { |n| n['id']=='carrier' }
    back = data['dc_graph']['nodes'].find { |n| n['id']=='back' }
    carrier['transform'][0] = 2.0
    carrier['local_bounds'][1][0] /= 2.0
    carrier['attributes']['_w_formula'] = '(parent!lenx-2*parent!t)/2'
    back['transform'][0] = 0.5
    rule = S::Core.learn_module([data])
    plan = S::Core.plan(rule,data,'t'=>20)
    changed = plan['parts'].find { |p| p['key']=='back' }
    assert_in_delta 560,S::Core.dimensions(changed['bounds'])[0],0.000001
    assert_equal 0,S::Core.plan(rule,data,{})['changed_count']
    positions = S::DCFormulas::SymbolicProgram.new(data).symbolic_positions
    assert_in_delta(-1,positions['back'][1][0][1]['t'],0.000001)
  end

  def test_two_drawer_levels_keep_copy_positions_when_panel_thickness_changes
    data = JSON.parse(File.read(File.join(__dir__,'fixtures/drawer_two_levels.json'),encoding:'UTF-8'))
    rule = S::RuleSystem.build(data,S::Core.learn_module([data]))
    assert_equal 0,S::Core.plan(rule,data,{})['changed_count']
    plan = S::Core.plan(rule,data,'e_5rhroeld'=>18.6)
    assert S::Core.bounds_close?(S::Core.union(plan['parts']),data['envelope'],0.001)
    floors = plan['parts'].select { |p| p['name']=='Hộc - Đáy' }.sort_by { |p| p['bounds'][0][2] }
    assert_equal 2,floors.length
    assert_in_delta 300,floors[1]['bounds'][0][2]-floors[0]['bounds'][0][2],0.000001
  end
end

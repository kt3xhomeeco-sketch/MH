# encoding: UTF-8
require 'minitest/autorun'
require_relative 'formula_fixtures'
require_relative '../reader'

class ModuleStudioDerivedEnvelopeTest < Minitest::Test
  S = MH::ModuleStudio

  def source(name)
    JSON.parse(File.read(File.join(__dir__,"fixtures/#{name}.json"),encoding:'UTF-8'))
  end

  def test_duplicate_derived_keys_are_unique_and_stable_without_rewriting_explicit_identity
    counts = {}
    keys = 3.times.map { S::Reader.part_key('',%w[parent panel],counts) }
    assert_equal ['parent / panel','parent / panel [2]','parent / panel [3]'],keys
    assert_equal 'persisted',S::Reader.part_key('persisted',%w[parent panel],counts)
    fresh = {}; assert_equal keys,(3.times.map { S::Reader.part_key('',%w[parent panel],fresh) })
  end

  def test_double_top_height_follows_exact_formulas_and_repeated_edits_keep_width_depth
    data = source('double-top'); before = JSON.generate(data)
    rule = S::RuleSystem.build(data,S::Core.learn_module([data]))
    assert_equal [2],rule.dig('formula_engine','envelope_policy','axes')
    current = S::Core.copy_data(data)
    [17,18.6,20,25,18.6].each do |value|
      plan = S::Core.plan(rule,current,'a1ddtam'=>value)
      assert_equal [400,350],S::Core.dimensions(plan['envelope']).first(2)
      assert_in_delta value*2,S::Core.dimensions(plan['envelope'])[2],0.000001
      current.merge!('parts'=>plan['parts'],'envelope'=>plan['envelope'],'dc_inputs'=>{},'parameter_values'=>plan['target'])
      assert_equal 0,S::Core.plan(rule,current,{})['changed_count']
    end
    loaded = S::Core.rule!(JSON.parse(JSON.generate(rule)))
    assert_equal rule.dig('formula_engine','envelope_policy'),loaded.dig('formula_engine','envelope_policy')
    assert_equal before,JSON.generate(data)
  end

  def test_view_axes_with_self_references_or_unsupported_proof_are_not_exempt
    data = FormulaFixtures.snapshot
    data['dc_inputs'].merge!('_lenx_access'=>'VIEW','_lenz_access'=>'VIEW')
    assert_empty S::EnvelopePolicy.derive(data,S::DCFormulas::Program.new(data))['axes']
    top = source('double-top')
    top['dc_inputs']['_lenz_access'] = 'TEXTBOX'
    assert_empty S::EnvelopePolicy.derive(top,S::DCFormulas::Program.new(top))['axes']
    top['dc_inputs']['_lenz_access'] = 'VIEW'
    top['dc_graph']['nodes'].first['attributes']['_z_formula'] = 'unsupported(parent!lenz)'
    assert_empty S::EnvelopePolicy.derive(top,S::DCFormulas::Program.new(top))['axes']
  end

  def test_serialized_policy_cannot_free_an_axis_using_root_length
    data = source('double-top')
    rule = S::Core.learn_module([data])
    rule['envelope_policy']['axes'] = [0,2]
    assert_raises(S::Core::Error) { S::Core.rule!(rule) }
  end

  def test_manual_cell_cannot_exceed_the_exact_derived_height
    data = source('double-top')
    rule = S::RuleSystem.build(data,S::Core.learn_module([data]))
    part = data['parts'].find { |entry| entry['name']=='Nóc' }
    assert part
    edited = S::Parametric.edit_part_formula(rule,part['key'],'lenz','100')
    assert_match 'phủ bì',assert_raises(S::Core::Error) { S::Core.plan(edited,data,{}) }.message
  end

  def test_hanging_box_intermediate_string_lengths_have_physical_units
    data = source('hanging-box'); before = JSON.generate(data)
    program = S::DCFormulas::Program.new(data)
    program.evaluate(S::Core.formula_values(data,program.controls))
    node = data['dc_graph']['nodes'].find { |entry| entry['name']=='Hop2Day' }
    assert_in_delta 60,program.attribute(node['id'],'cachphai'),0.000001
    assert_equal data['parts'].to_h { |part| [part['key'],part['visible']!=false] },program.visibility
    rule = S::RuleSystem.build(data,S::Core.learn_module([data]))
    [17,18.6,20,25].each do |thickness|
      plan = S::Core.plan(rule,data,'a0van'=>thickness)
      assert plan['changed_count'].positive?
      assert S::Core.bounds_close?(data['envelope'],S::Core.union(plan['parts']),0.001)
    end
    assert_equal before,JSON.generate(data)
  end

  def test_hanging_box_repeated_scale_uses_authored_frames_for_explicit_child_formulas
    data = source('hanging-box')
    rule = S::StudioCalculation.build_system([data])
    current = S::Core.copy_data(data)
    [1.2,0.8].each do |factor|
      current['parts'].each { |part| part['bounds'].each { |point| point[0]*=factor; point[1]*=factor } }
      current['envelope'] = S::Core.union(current['parts'])
      plan = S::ScalePlan.plan(rule,current,S::Core.parameter_values(rule['formula_engine'],data))
      assert S::Core.bounds_close?(S::Core.union(plan['parts']),current['envelope'],0.001)
      current.merge!('parts'=>plan['parts'],'parameter_values'=>plan['target'],'dc_inputs'=>{})
      assert_equal 0,S::Core.plan(rule,current,{})['changed_count']
    end
  end

  def test_numeric_and_editable_cells_share_the_authored_frame_policy
    data = source('hanging-box'); value = 18.6
    program = S::DCFormulas::ParametricProgram.new(data)
    program.symbolic_positions
    values = S::Core.formula_values(data,program.controls).merge('a0van'=>value)
    expected, = program.evaluate(values)
    key = data['parts'].find { |part| part['name']=='Hop2Day' }['key']
    texts = program.cell_formula_texts(values.transform_values(&:to_s))[key]
    expected_values = S::Core.dimensions(expected[key])+expected[key][0]
    texts.each_with_index do |text,index|
      assert text
      %w[LenX LenY LenZ].zip([800,450,500]).each { |field,size| text = text.gsub("Module.#{field}",size.to_s) }
      result = S::Parametric.numeric_expression(S::DCFormulas::Parser.new(text).parse) { |_scope,name| name=='true' ? 1 : name=='false' ? 0 : raise('Unexpected reference') }
      assert_in_delta expected_values[index],result,0.000001
    end
  end

  def test_symbolic_frames_preserve_captured_relative_units_without_reapplying_parent_resize
    data = FormulaFixtures.snapshot
    data['formula_frame_version'] = 2
    carrier = data['dc_graph']['nodes'].find { |node| node['id']=='carrier' }
    back = data['dc_graph']['nodes'].find { |node| node['id']=='back' }
    carrier['transform'][0] = 2.0; carrier['local_bounds'][1][0] /= 2
    carrier['attributes']['_w_formula'] = '(parent!lenx-2*parent!t)/2'
    back['transform'][0] = 0.5
    symbolic = S::DCFormulas::SymbolicProgram.new(data)
    positions = symbolic.symbolic_positions
    bounds, = symbolic.evaluate(S::Core.formula_values(data,symbolic.controls).merge('t'=>20))
    2.times do |side|
      constant,coefficients = positions['back'][side][0]
      result = constant+coefficients.sum { |key,factor| {'t'=>20,'@lenx'=>600}.fetch(key)*factor }
      assert_in_delta bounds['back'][side][0],result,0.000001
    end
  end

  def test_unverified_mesh_cannot_be_deformed_and_flat_surfaces_cannot_be_extruded
    mesh = {'name'=>'surface','bounds'=>[[0,0,0],[10,20,0]],'face_count'=>1,'edge_count'=>4,'visible'=>true,'box_verified'=>false}
    assert_raises(S::Core::Error) { S::GeometryMotion.validate!(mesh,[[0,0,0],[20,20,0]],true) }
    mesh['affine_verified'] = true
    S::GeometryMotion.validate!(mesh,[[0,0,0],[20,20,0]],true)
    assert_raises(S::Core::Error) { S::GeometryMotion.validate!(mesh,[[0,0,0],[20,20,2]],true) }
    assert_raises(S::Core::Error) { S::GeometryMotion.validate!(mesh,[[0,0,0],[0,20,0]],true) }
  end
end

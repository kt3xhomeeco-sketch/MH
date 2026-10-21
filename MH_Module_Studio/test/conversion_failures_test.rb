# encoding: UTF-8
require 'minitest/autorun'
require_relative 'formula_fixtures'
require_relative '../library_catalog'

class ModuleStudioConversionFailuresTest < Minitest::Test
  S=MH::ModuleStudio

  def fixture(name)
    JSON.parse(File.read(File.join(__dir__,'fixtures',name+'.json'),encoding:'UTF-8'))
  end

  def test_unicode_space_and_digit_group_qualifiers_preserve_operators_and_reject_malformed_formulas
    parser=S::DCFormulas::Parser
    assert_equal [:reference,'2tao dot','d1'],parser.new('2Tao Dot!d1').parse
    assert_equal [:reference,'xà nk','lenx'],parser.new('Xà NK ! LenX').parse
    assert_equal [:binary,'!=',[:reference,nil,'a'],[:reference,nil,'b']],parser.new('a != b').parse
    ast=parser.new('2*Xà NK!LenX + 2Tao Dot!d1/3').parse
    assert_equal '+',ast[1]
    assert_equal '*',ast[2][1]
    assert_equal '/',ast[3][1]
    assert_raises(S::Core::Error) { parser.new('if(=parent!t=0,true,false)').parse }
    assert_raises(S::Core::Error) { parser.new('if(parent!t=0,1,if(t=1,1,0,))').parse }
  end

  def test_untyped_intermediate_length_uses_authoring_units_only_on_new_programs
    data=FormulaFixtures.snapshot
    carrier=data['dc_graph']['nodes'].find { |n| n['id']=='carrier' }
    carrier['attributes'].delete('_w_units')
    data['scalar_formula_units_version']=1
    p=S::DCFormulas::Program.new(data)
    values=S::Core.formula_values(data,p.controls)
    bounds,=p.evaluate(values)
    data['parts'].each { |part| assert S::Core.bounds_close?(part['bounds'],bounds[part['key']]) }
    assert_in_delta 56.4,p.attribute('carrier','w'),0.000001
    symbolic=S::DCFormulas::SymbolicProgram.new(data).symbolic_positions
    cell=symbolic['back'][1][0]
    inputs=values.merge('@lenx'=>600,'@leny'=>200,'@lenz'=>500)
    evaluated=cell[0]+cell[1].sum { |key,coefficient| coefficient*inputs.fetch(key) }
    assert_in_delta 582,evaluated,0.000001
    sheet=S::Parametric.sheet(S::StudioCalculation.build_system([data]),data)
    assert sheet['parts'].find { |part| part['key']=='back' }['expressions'][0]['text']
    data.delete('scalar_formula_units_version')
    legacy=S::DCFormulas::Program.new(data);legacy.evaluate(values)
    assert_in_delta 564,legacy.attribute('carrier','w'),0.000001
  end

  def test_actual_intermediate_dc_converts_and_repeated_thickness_changes_do_not_accumulate
    data=fixture('intermediate-units-dc');before=JSON.generate(data)
    rule=S::StudioCalculation.build_system([data])
    assert rule['formula_engine'],rule['warnings'].join(' ')
    assert_equal 0,S::Core.plan(rule,data,S::Parametric.targets(rule))['changed_count']
    row=S::Parametric.variables(rule).find { |item| item['symbol']=='T1' }
    assert row
    current=data
    [20,25,row['value']].each do |thickness|
      values=S::Parametric.targets(rule).merge(row['binding']=>thickness)
      plan=S::Core.plan(rule,current,values)
      current=data.merge('parts'=>plan['parts'],'envelope'=>plan['envelope'],
        'formula_envelope'=>plan['formula_envelope'],'parameter_values'=>plan['target'],'dc_inputs'=>{})
      assert_equal 0,S::Core.plan(rule,current,values)['changed_count']
    end
    assert_equal before,JSON.generate(data)
    data['parts'].each { |part| assert S::Core.bounds_close?(part['bounds'],current['parts'].find { |p| p['key']==part['key'] }['bounds']) }
  end

  def test_nested_cardinal_rebase_proves_source_bounds_and_normalizes_output_thickness
    data=fixture('cardinal-pano-dc');before=JSON.generate(data)
    rebased=S::AxisRebase.enable(data)
    refute_empty rebased['axis_rebases']
    p=S::DCFormulas::Program.new(rebased)
    bounds,=p.evaluate(S::Core.formula_values(rebased,p.controls))
    data['parts'].each { |part| assert S::Core.bounds_close?(part['bounds'],bounds[part['key']]),part['name'] }
    rule=S::StudioCalculation.build_system([data])
    assert rule['formula_engine'],rule['warnings'].join(' ')
    refute_empty rule['parameter_binding_aliases']
    plan=S::Core.plan(rule,data,S::Parametric.targets(rule))
    assert_operator plan['changed_count'],:>,0
    assert_in_delta 24,S::Core.dimensions(plan['envelope'])[1],0.001
    assert_empty Array(rule['thickness_merge_anchors'])
    assert_equal before,JSON.generate(data)
    saved=S::Core.rule!(JSON.parse(JSON.generate(rule)))
    assert_equal plan['parts'],S::Core.plan(saved,data,S::Parametric.targets(saved))['parts']
  end

  def test_arbitrary_rotation_is_retained_as_unsupported_instead_of_approximated
    data=FormulaFixtures.snapshot
    node=data['dc_graph']['nodes'].first
    node['transform'][0]=Math.sqrt(0.5);node['transform'][1]=Math.sqrt(0.5)
    node['transform'][4]=-Math.sqrt(0.5);node['transform'][5]=Math.sqrt(0.5)
    assert_equal data,S::AxisRebase.enable(data)
    assert_raises(S::Core::Error) { S::DCFormulas::Program.new(S::AxisRebase.enable(data)) }
  end

  def test_wire_and_solid_static_modules_have_no_fake_thickness_or_lost_geometry
    [0,5].each do |thickness|
      part={'key'=>'root:mesh','name'=>'Geometry','bounds'=>[[0,0,0],[600,thickness,500]],
        'face_count'=>thickness.zero? ? 0 : 6,'edge_count'=>thickness.zero? ? 4 : 12,
        'visible'=>true,'box_verified'=>thickness.positive?,'thickness_axis'=>thickness.zero? ? nil : 1}
      data=S::Reader.make_snapshot([part],'Geometry',nil,{'kind'=>'test'})
      assert_equal 'no_board_thickness',data.dig('parameter_source','kind') if thickness.zero?
      rule=S::StaticGeometry.build(data)
      assert_empty rule['parameters']
      assert_empty S::Parametric.variables(rule)
      assert_equal 0,S::Core.plan(rule,data,{})['changed_count']
      assert S::LibraryCatalog.payload(JSON.generate('format'=>'mh_module_library','version'=>1,'name'=>'Geometry',
        'rule'=>rule,'values'=>{},'snapshot'=>data))
      scaled=S::ScalePlan.scaled_snapshot(data,[2,1,1])
      plan=S::ScalePlan.plan(S::Core.rule!(JSON.parse(JSON.generate(rule))),scaled,{})
      assert_equal scaled['envelope'],plan['envelope']
    end
    dc=FormulaFixtures.snapshot
    refute S::StaticGeometry.eligible?(dc)
    assert_raises(S::Core::Error) { S::StaticGeometry.build(dc) }
  end

  def test_flat_expression_keeps_a_guide_flat_and_never_extrudes_it_into_a_solid
    data=FormulaFixtures.snapshot
    node=data['dc_graph']['nodes'].find { |item| item['part_key']=='back' }
    node['local_bounds'][1][1]=0
    node['attributes']['_leny_formula']='if(parent!b>0,0,0)'
    part=data['parts'].find { |item| item['key']=='back' }
    part['bounds'][1][1]=part['bounds'][0][1]
    part['thickness_axis']=nil;part['box_verified']=false;part['face_count']=0
    p=S::DCFormulas::Program.new(data)
    bounds,=p.evaluate(S::Core.formula_values(data,p.controls))
    assert S::Core.bounds_close?(part['bounds'],bounds['back'],0.000001)
    positions=S::DCFormulas::SymbolicProgram.new(data).symbolic_positions
    assert positions['back'].flatten(1).all?
    cells=S::DCFormulas::ParametricProgram.new(data);cells.symbolic_positions
    assert(cells.cell_formula_texts({})['back'].all? { |text| text && !text.include?('/ (0)') })
    node['attributes']['_leny_formula']='parent!b'
    p=S::DCFormulas::Program.new(data)
    error=assert_raises(S::Core::Error) { p.evaluate(S::Core.formula_values(data,p.controls)) }
    assert_includes error.message,'suy biến'
  end
end

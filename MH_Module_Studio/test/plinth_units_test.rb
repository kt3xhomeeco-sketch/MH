# encoding: UTF-8
require 'minitest/autorun'
require_relative 'formula_fixtures'

class ModuleStudioPlinthUnitsTest < Minitest::Test
  S = MH::ModuleStudio

  def source
    JSON.parse(File.read(File.join(__dir__,'fixtures/plinth.json'),encoding:'UTF-8'))
  end

  def test_scalar_formula_length_references_follow_declared_authoring_units
    {'CENTIMETERS'=>15.0,'INCHES'=>600.0/25.4/4}.each do |length_unit,expected|
      %w[FLOAT STRING].each do |formula_unit|
        data = FormulaFixtures.snapshot
        data['dc_inputs'].merge!('_lengthunits'=>length_unit,'_probe_units'=>'STRING',
                                 '_probe_formulaunits'=>formula_unit,'_probe_formula'=>'LenX/4',
                                 '_literal_formulaunits'=>formula_unit,'_literal_formula'=>'5')
        program = S::DCFormulas::Program.new(data)
        program.evaluate(S::Core.formula_values(data,program.controls))
        assert_in_delta expected,program.attribute('','probe'),0.000001
        assert_equal 5,program.attribute('','literal')
      end
    end
  end

  def test_plinth_compiles_without_cached_positions_and_preserves_envelope_when_edited
    data = source
    rule = S::RuleSystem.build(data,S::Core.learn_module([data]))
    assert_equal 0,S::Core.plan(rule,data,{})['changed_count']
    plan = S::Core.plan(rule,data,'a5dodayvan'=>17.6,'c4_hut_truoc'=>25)
    assert S::Core.bounds_close?(S::Core.union(plan['parts']),data['envelope'],0.001)
    legs = plan['parts'].select { |p| p['name'].start_with?('chan_doc copy') }.sort_by { |p| p['name'] }
    assert_equal 4,legs.length
    legs.each_with_index do |part,index|
      assert_in_delta((700-17.6)/4*(index+1),part['bounds'][0][0],0.000001)
      assert_in_delta 42.6,part['bounds'][0][1],0.000001
      assert_in_delta 17.6,S::Core.dimensions(part['bounds'])[0],0.000001
    end
  end

  def test_symbolic_positions_and_parametric_rows_use_the_same_scalar_units
    data = source
    program = S::DCFormulas::SymbolicProgram.new(data)
    positions = program.symbolic_positions
    leg = data['parts'].find { |p| p['name']=='chan_doc copy 001' }
    assert_in_delta(-0.25,positions[leg['key']][0][0][1]['a5dodayvan'],0.000001)
    sheet = S::DCFormulas::ParametricProgram.new(data)
    rows = sheet.parametric_attributes(S::Core.formula_values(data,sheet.controls),data['envelope'])
    spacing = rows.find { |row| row['node_id']=='' && row['key']=='b7kcchanphu' }
    assert_in_delta 17.035,spacing['value'],0.000001
    assert_equal '',spacing['unit']
    assert_equal 'computed',spacing['status']
  end

  def test_editable_coordinate_cell_keeps_the_same_spacing_formula
    data = source
    sheet = S::DCFormulas::ParametricProgram.new(data)
    sheet.symbolic_positions
    aliases = S::Core.formula_values(data,sheet.controls).transform_values(&:to_s)
    aliases['a5dodayvan'] = 'T1'
    cells = sheet.cell_formula_texts(aliases)
    leg = data['parts'].find { |part| part['name']=='chan_doc copy 001' }
    ast = S::DCFormulas::Parser.new(cells[leg['key']][3].gsub('Module.LenX','700')).parse
    value = S::Parametric.numeric_expression(ast) do |scope,key|
      !scope && key=='t1' ? 17.6 : raise('Unexpected cell reference')
    end
    assert_in_delta((700-17.6)/4,value,0.000001)
  end
end

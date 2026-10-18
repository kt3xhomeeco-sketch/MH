# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioDCOptionsTest < Minitest::Test
  S = MH::ModuleStudio

  def test_decodes_actual_dc_legacy_utf16_latin1_utf8_and_literal_plus
    assert_equal 'Nóc Lọt',S::DCOptions.decode('N%F3c%20L%u1ECDt')
    assert_equal 'Có Dùng',S::DCOptions.decode('C%F3%20D%F9ng')
    assert_equal 'Có',S::DCOptions.decode('C%C3%B3')
    assert_equal 'A+B',S::DCOptions.decode('A+B')
    assert_equal '😀',S::DCOptions.decode('%uD83D%uDE00')
  end

  def test_list_keeps_labels_separate_from_numeric_values_and_honors_base_length_units
    attrs = {'_kind_access'=>'LIST','_kind_options'=>'&N%F3c%20Tr%F9m=1&N%F3c%20L%u1ECDt=2&'}
    choices = S::DCOptions.choices(attrs,'kind')
    assert_equal ['Nóc Trùm','Nóc Lọt'],(choices.map { |row| row['label'] })
    assert_equal [1,2],(choices.map { |row| row['value'] })
    assert(choices.all? { |row| row['supported'] })
    assert_equal [25.4,50.8],(S::DCOptions.choices(attrs,'kind','mm').map { |row| row['value'] })
    attrs['_kind_access'] = 'TEXTBOX'
    assert_empty S::DCOptions.choices(attrs,'kind')
  end

  def test_keeps_unsupported_list_expressions_disabled_instead_of_executing_them
    attrs = {'_kind_access'=>'LIST','_kind_options'=>'&A=%3DKernel.system%281%29&B=2&'}
    choices = S::DCOptions.choices(attrs,'kind')
    refute choices.first['supported']
    assert_equal '=Kernel.system(1)',choices.first['value']
    assert choices.last['supported']
  end

  def test_old_owned_kitchen_lists_are_present_in_sheet_and_compact_options
    data = JSON.parse(File.read(File.join(__dir__,'fixtures/kitchen-thickness.json'),encoding:'UTF-8'))
    rule = S::Core.rule!(data['rule'])
    rows = S::Parametric.variables(rule)
    rows.find { |row| row['binding']=='icwgdjcq4t' }['exported'] = true
    rule = S::Parametric.edit_variables(rule,rows)
    sheet = S::Parametric.sheet(rule,data['snapshot'])
    choice = sheet['variables'].find { |row| row['binding']=='icwgdjcq4t' }
    assert_equal ['Ngậm Nóc','Trùm Lên Nóc','Dưới Nóc'],(choice['options'].map { |row| row['label'] })
    compact = S::OptionsParameters.rows(rule,data['values']).find { |row| row['id']==choice['id'] }
    assert_equal choice['options'],compact['options']
    assert_equal 'number',choice['category']
  end
end

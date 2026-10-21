# encoding: UTF-8

require 'minitest/autorun'
require_relative '../name_grammar'

class NameGrammarTest < Minitest::Test
  def setup
    MH::NameGrammar.configure(
      'separators' => {
        'sep_sub_prefix' => '-',
        'sep_prefix' => '_',
        'sep_suffix' => ':'
      },
      'prefix' => ['SP', 'AB'],
      'modul' => ['Tam'],
      'suffix' => ['L', 'R']
    )
  end

  def test_dialog_builder_preserves_name_without_edits
    assert_equal 'SP_01_L', MH::NameGrammar.dialog_build_name(
      base: 'SP_01_L', prefixes: ['SP'], modules: ['Tam'], suffixes: ['L', 'R']
    )
  end

  def test_dialog_builder_uses_shared_separator_rules
    assert_equal 'T2-AB_Tam:01_L', MH::NameGrammar.dialog_build_name(
      base: 'SP_01_L', sub_prefix: 'T2', prefix: 'AB', modul: 'Tam', suffix: 'L',
      prefixes: ['SP'], modules: ['Tam'], suffixes: ['L', 'R']
    )
  end

  def test_product_rule_layers_are_the_read_contract
    MH::NameGrammar.configure(
      'product_code_rules' => {
        'segment_separator' => '_',
        'layers' => [
          { 'key' => 'product_code', 'type' => 'text_number', 'required' => true, 'values' => ['SP', 'DW'] },
          { 'key' => 'module_no', 'type' => 'number', 'optional' => true, 'values' => ['number'] },
          { 'key' => 'suffix', 'type' => 'text', 'optional' => true,
            'values' => [{ 'value' => 'Hông' }, { 'value' => 'Cánh Trái' }] }
        ]
      }
    )

    parsed = MH::NameGrammar.parse('SP01_02_Hông')
    assert parsed[:recognized]
    assert_equal 'SP01', parsed[:product]
    assert_equal '02', parsed[:module_no]
    assert_equal 'Hông', parsed[:suffix]
    assert_equal '', parsed[:part]
    assert_nil parsed[:sub_prefix]
  end

  def test_product_rule_layers_do_not_infer_hyphenated_sub_prefix
    MH::NameGrammar.configure(
      'product_code_rules' => {
        'segment_separator' => '_',
        'layers' => [
          { 'key' => 'product_code', 'type' => 'text_number', 'required' => true, 'values' => ['SP', 'DW'] },
          { 'key' => 'module_no', 'type' => 'number', 'optional' => true, 'values' => ['number'] },
          { 'key' => 'suffix', 'type' => 'text', 'optional' => true,
            'values' => [{ 'value' => 'Hông' }] }
        ]
      }
    )

    refute MH::NameGrammar.parse('NT-SP01_02_Hông')[:recognized]
    refute MH::NameGrammar.parse('SP01_02_Hông_L')[:recognized]
  end

  def test_product_rule_builder_uses_product_module_suffix_order
    MH::NameGrammar.configure(
      'product_code_rules' => {
        'segment_separator' => '_',
        'layers' => [
          { 'key' => 'product_code', 'type' => 'text_number', 'required' => true, 'values' => ['SP'] },
          { 'key' => 'module_no', 'type' => 'number', 'optional' => true, 'values' => ['number'] },
          { 'key' => 'suffix', 'type' => 'text', 'optional' => true,
            'values' => [{ 'value' => 'Hông' }] }
        ]
      }
    )

    assert_equal '__12. SP01_02_Hông', MH::NameGrammar.build_name(
      product: 'SP01', module_raw: '02', part: 'Hông', sub_prefix: 'NT', sys_id: 12
    )
  end

  def test_extended_read_rule_maps_four_groups_without_changing_writer
    MH::NameGrammar.configure(
      'product_code_rules' => {
        'segment_separator' => '_',
        'layers' => [
          { 'key' => 'product_code', 'type' => 'text_number', 'required' => true, 'values' => ['SP'] },
          { 'key' => 'module_no', 'type' => 'number', 'optional' => true, 'values' => ['number'] },
          { 'key' => 'suffix', 'type' => 'text', 'optional' => true, 'values' => [{ 'value' => 'Hông' }] }
        ]
      },
      'name_read_rules' => [{
        'key' => 'legacy_four_groups',
        'enabled' => true,
        'groups' => [
          { 'key' => 'product_code', 'target' => 'product', 'type' => 'product', 'required' => true, 'separator_after' => '_' },
          { 'key' => 'module_no', 'target' => 'module', 'type' => 'number', 'required' => true, 'separator_after' => '_' },
          { 'key' => 'suffix', 'target' => 'suffix', 'type' => 'dictionary', 'required' => false, 'separator_after' => '_' },
          { 'key' => 'part', 'target' => 'part', 'type' => 'text', 'required' => false, 'separator_after' => '' }
        ]
      }]
    )

    parsed = MH::NameGrammar.parse('SP01_02_Hông_L')
    assert parsed[:recognized]
    assert_equal 'SP01', parsed[:product]
    assert_equal '02', parsed[:module_no]
    assert_equal 'Hông', parsed[:suffix]
    assert_equal 'L', parsed[:part]
    assert_equal 'L', parsed[:fields]['part']
  end

  def test_extended_read_rule_uses_each_group_separator
    MH::NameGrammar.configure(
      'product_code_rules' => {
        'segment_separator' => '_',
        'layers' => [{ 'key' => 'product_code', 'type' => 'text_number', 'required' => true, 'values' => ['SP'] }]
      },
      'name_read_rules' => [{
        'key' => 'dot_layers',
        'enabled' => true,
        'groups' => [
          { 'key' => 'product_code', 'required' => true, 'separator_after' => '.' },
          { 'key' => 'modul_no', 'required' => true, 'separator_after' => '-' },
          { 'key' => 'suffix', 'required' => false }
        ]
      }]
    )

    parsed = MH::NameGrammar.parse('SP01.02-L')
    assert parsed[:recognized]
    assert_equal 'SP01', parsed[:product]
    assert_equal '02', parsed[:module_no]
    assert_equal 'L', parsed[:suffix]
  end
end

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
end

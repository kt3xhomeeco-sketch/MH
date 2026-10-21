# frozen_string_literal: true
require 'json'
require 'minitest/autorun'
require_relative '../runtime'

class ModuleStudioRuntimeParameterMetadataTest < Minitest::Test
  class Entity
    def initialize
      @attributes = {}
    end

    def persistent_id
      12345
    end

    def get_attribute(dictionary, key, default = nil)
      @attributes.fetch([dictionary, key], default)
    end

    def set_attribute(dictionary, key, value)
      @attributes[[dictionary, key]] = value
    end

    def delete_attribute(dictionary, key)
      @attributes.delete([dictionary, key])
    end
  end

  def test_trial_carries_selected_fields_current_values_and_full_internal_rules
    samples = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'dc_mixed_thickness.json'), encoding: 'UTF-8'))
    core = MH::ModuleStudio::Core
    rule = core.learn_module(samples)
    core.set_exposed_parameters!(rule, %w[ikqikbwfw7 iwc3l3ib0g])
    root = Entity.new
    MH::ModuleStudio::Runtime.stamp(root, rule, {}, 'ba4ulq2qnw' => 18, 'ikqikbwfw7' => 9)
    dictionary = MH::ModuleStudio::Reader::DICT
    public_fields = JSON.parse(root.get_attribute(dictionary, 'exposed_parameters_json'))
    stored_rule = core.rule!(JSON.parse(root.get_attribute(dictionary, 'rule_json')))

    assert_equal %w[ikqikbwfw7 iwc3l3ib0g].sort, (public_fields.map { |field| field['key'] }.sort)
    assert_equal 9, public_fields.find { |field| field['key'] == 'ikqikbwfw7' }['value']
    assert_equal false, public_fields.find { |field| field['key'] == 'iwc3l3ib0g' }['can_edit']
    assert_equal 2, stored_rule['rules'].length
    assert_equal rule['exposed_parameter_keys'], stored_rule['exposed_parameter_keys']
  end
end

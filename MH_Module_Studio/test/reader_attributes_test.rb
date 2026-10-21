# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../reader'

class ModuleStudioReaderAttributesTest < Minitest::Test
  # SketchUp's native dictionary requires a block; a Ruby Hash hides this bug.
  class BlockOnlyDictionary
    def initialize(values)
      @values = values
    end

    def each_pair
      raise LocalJumpError, 'no block given' unless block_given?
      @values.each_pair { |key, value| yield key, value }
      nil
    end
  end

  class Entity
    attr_reader :dictionary_request

    def initialize(dictionary)
      @dictionary = dictionary
    end

    def attribute_dictionary(name, create)
      @dictionary_request = [name, create]
      @dictionary
    end
  end

  def test_reads_native_block_only_dictionary_without_changing_values
    values = { '_name' => 'Hông trái', 'lenx' => 18.0, '_lenx_formula' => 'parent.day', 'hidden' => false }
    entity = Entity.new(BlockOnlyDictionary.new(values))

    assert_equal values, MH::ModuleStudio::Reader.dynamic_attributes(entity)
    assert_equal ['dynamic_attributes', false], entity.dictionary_request
  end

  def test_missing_dictionary_returns_empty_attributes_without_creating_one
    entity = Entity.new(nil)

    assert_equal({}, MH::ModuleStudio::Reader.dynamic_attributes(entity))
    assert_equal ['dynamic_attributes', false], entity.dictionary_request
  end
end

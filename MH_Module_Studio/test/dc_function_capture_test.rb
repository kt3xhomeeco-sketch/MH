# encoding: UTF-8
require 'minitest/autorun'
require_relative '../reader'

class ModuleStudioDCFunctionCaptureTest < Minitest::Test
  Reader = MH::ModuleStudio::Reader
  Functions = MH::ModuleStudio::DCFormulas
  Definition = Struct.new(:source) do
    def get_attribute(*)
      'encoded definition metadata'
    end
  end

  def with_loader(inherited: false)
    skip 'Portable adapter test' if Object.const_defined?(:ABF) || Object.const_defined?(:DCFunctionsV1)
    events = []
    parent = Class.new
    parent.define_singleton_method(:abf_eval) { |_text| events << :executed }
    functions = inherited ? Class.new(parent) : parent
    original = functions.method(:abf_eval)
    loader = Object.new
    loader.define_singleton_method(:load) do |definition|
      events << :load
      raise 'Loader failed' if definition.source == :failure
      functions.abf_eval(definition.source)
      events << :after_eval
    end
    loader_class = Class.new
    loader_class.define_singleton_method(:instance) { loader }
    abf = Module.new
    abf.const_set(:DC_Loader, loader_class)
    Object.const_set(:ABF, abf)
    Object.const_set(:DCFunctionsV1, functions)
    yield functions, original, events
  ensure
    Object.send(:remove_const, :ABF) if defined?(abf) && Object.const_defined?(:ABF) && Object.const_get(:ABF).equal?(abf)
    Object.send(:remove_const, :DCFunctionsV1) if defined?(functions) && Object.const_defined?(:DCFunctionsV1) && Object.const_get(:DCFunctionsV1).equal?(functions)
  end

  def test_source_is_captured_before_eval_and_the_existing_method_is_restored
    with_loader do |functions, original, events|
      source = Functions::NOMINAL_SOURCE.sub('__FUNCTION__', 'new_width').sub('__PRODUCT__', 'fixture').sub('__LENGTH__', 'lenx')
      assert_equal source, Reader.definition_function_source(Definition.new(source))
      assert_equal [:load], events
      assert_equal original, functions.method(:abf_eval)
      assert_equal 'lenx', Functions.source_nominal_aliases(source)['new_width']['attribute']
    end
  end

  def test_failure_and_oversized_source_always_restore_the_hook
    with_loader do |functions, original, events|
      assert_raises(RuntimeError) { Reader.definition_function_source(Definition.new(:failure)) }
      assert_equal original, functions.method(:abf_eval)
      assert_raises(MH::ModuleStudio::Core::Error) { Reader.definition_function_source(Definition.new('x' * (1024 * 1024 + 1))) }
      assert_equal original, functions.method(:abf_eval)
      refute_includes events, :executed
      refute_includes events, :after_eval
    end
  end

  def test_inherited_eval_remains_inherited_and_worker_threads_never_touch_the_loader
    with_loader(inherited: true) do |functions, original, events|
      Reader.definition_function_source(Definition.new('source as data'))
      assert_equal original, functions.method(:abf_eval)
      refute_includes functions.singleton_methods(false), :abf_eval
      events.clear
      result = Thread.new { Reader.definition_function_source(Definition.new('worker')) }.value
      assert_nil result
      assert_empty events
    end
  end

  def test_registered_functions_after_the_display_inventory_limit_are_still_verified
    with_loader do |functions, _original, events|
      functions.class_eval(<<~'RUBY')
        protected
        define_method(:late_width) do |val|
          return if !ABF::StoreData.instance.check_dc 'fixture'
          dict = @source_entity.parent.attribute_dictionaries['dynamic_attributes']
          ret = dict['_lenx_nominal']
          unit = dict['_lengthunits'] || 'CENTIMETERS'
          return (ret.to_f * 2.54) if (unit == 'CENTIMETERS')
          return ret.to_f if (unit == 'INCHES')
          return ret
        end
      RUBY
      attrs=120.times.to_h { |index| ["_field#{index}_formula",'1'] }
      attrs['_late_formula']='late_width()'
      snapshot={'dc_inputs'=>attrs,'dc_graph'=>{'nodes'=>[]},'parts'=>[]}
      assert_equal 120,MH::ModuleStudio::Core.attribute_inventory(snapshot)['formulas'].length
      assert_equal 121,MH::ModuleStudio::Core.attribute_inventory(snapshot,limit:nil)['formulas'].length
      MH::ModuleStudio::DCFunctionCapture.capture_function_aliases!(snapshot)
      assert_equal 'lenx',snapshot.fetch('function_aliases').fetch('late_width')['attribute']
      assert_empty MH::ModuleStudio::Core.attribute_inventory(snapshot)['unknown_functions']
      assert_empty events
    end
  end
end

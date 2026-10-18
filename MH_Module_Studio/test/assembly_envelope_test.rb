# encoding: UTF-8
require 'minitest/autorun'
require 'minitest/mock'
require_relative '../assembly'

class ModuleStudioAssemblyEnvelopeTest < Minitest::Test
  S = MH::ModuleStudio

  def box(depth)
    [[0.0,0.0,0.0],[100.0,depth,100.0]]
  end

  def simulate(sizes,output,target)
    before = sizes.dup
    S::AssemblyEnvelope.stub(:bounds,->(_component) { box(sizes.fetch(:cabinet,0)+output) }) do
      S::AssemblyEnvelope.stub(:candidates,sizes.keys) do
        S::Assembly.stub(:projection,->(entity,_normal) { [0.0,sizes.fetch(entity)] }) do
          S::Assembly.stub(:resize,->(entity,_normal,value) { sizes[entity]=value }) do
            S::Assembly.stub(:solve_ordered,nil) do
              S::AssemblyEnvelope.fit_axis(nil,nil,target,[],1)
            end
          end
        end
      end
    end
    [before,sizes]
  end

  def test_explicit_fixed_target_still_uses_free_module_depths
    target = box(619.4); original = S::Core.copy_data(target)
    sizes = {cabinet:588.4}
    simulate(sizes,41,target)
    assert_in_delta 578.4,sizes[:cabinet],0.000001
    assert_equal original,target
    assert_in_delta 619.4,sizes[:cabinet]+41,0.000001
  end

  def test_zero_response_interior_module_is_restored_without_being_resized_as_a_side_effect
    sizes = {cabinet:588.4,interior:30.0}
    simulate(sizes,41,box(619.4))
    assert_in_delta 578.4,sizes[:cabinet],0.000001
    assert_equal 30.0,sizes[:interior]
  end

  def test_explicit_impossible_fixed_target_rejects_nonpositive_sizes
    sizes = {cabinet:10.0}
    assert_raises(S::AssemblyMath::NoEnvelopeFreedom) { simulate(sizes,1001,box(619.4)) }
    assert_equal 10.0,sizes[:cabinet]
  end

  def test_a_fixed_cluster_without_freedoms_rejects
    assert_raises(S::Core::Error) { simulate({},800,box(619.4)) }
  end

  def apply(sizes,output,depth,fixed: false)
    remembered = nil; target = {'scope'=>box(depth)}
    S::AssemblyContainers.stub(:wrapper,:wrapper) do
      S::AssemblyContainers.stub(:members,[]) do
        S::AssemblyEnvelope.stub(:bounds,->(_component) { box(sizes.fetch(:cabinet,0)+output) }) do
          S::AssemblyEnvelope.stub(:candidates,sizes.keys) do
            S::AssemblyEnvelope.stub(:remember,->(_component,value) { remembered=value }) do
              S::Assembly.stub(:projection,->(entity,_normal) { [0.0,sizes.fetch(entity)] }) do
                S::Assembly.stub(:resize,->(entity,_normal,value) { sizes[entity]=value }) do
                  S::Assembly.stub(:solve_ordered,nil) do
                    S::AssemblyEnvelope.apply(nil,target,[],growth:{'scope'=>[1]},fixed_scopes:fixed ? ['scope'] : [])
                  end
                end
              end
            end
          end
        end
      end
    end
    [target['scope'],remembered]
  end

  def test_thickness_output_uses_free_cabinet_depth_before_growth
    sizes = {cabinet:581.4,interior:30.0}
    [17.6,200,17.6,20,80,17.6].each do |thickness|
      actual,saved = apply(sizes,thickness+1,600)
      assert_equal box(600),actual
      assert_equal box(600),saved
      assert_in_delta 599-thickness,sizes[:cabinet],0.000001
      assert_equal 30.0,sizes[:interior]
    end
  end

  def test_derived_only_fallback_retains_construction_target_through_growth_and_shrink
    [80,200,17.6,20].each do |thickness|
      actual,saved = apply({},thickness,17.6)
      assert_equal box(thickness),actual
      assert_equal box(17.6),saved
    end
    assert_raises(S::AssemblyMath::NoEnvelopeFreedom) { apply({},80,17.6,fixed:true) }
  end

  def test_saved_target_is_independent_of_current_geometry_and_caller_data
    attrs = {}; component = Object.new
    component.define_singleton_method(:get_attribute) { |_dict,key| attrs[key] }
    component.define_singleton_method(:set_attribute) { |_dict,key,value| attrs[key]=value }
    S::AssemblyEnvelope.stub(:bounds,box(602.4)) do
      assert_equal box(602.4),S::AssemblyEnvelope.target(component)
      desired = box(600); S::AssemblyEnvelope.remember(component,desired)
      desired[1][1]=200
      assert_equal box(600),S::AssemblyEnvelope.target(component)
      copy = S::AssemblyEnvelope.target(component);copy[1][1]=800
      assert_equal box(600),S::AssemblyEnvelope.target(component)
    end
  end

  def test_geometry_failure_cannot_be_silently_converted_into_fallback_growth
    S::AssemblyContainers.stub(:wrapper,:wrapper) do
      S::AssemblyEnvelope.stub(:bounds,box(602.4)) do
        S::AssemblyEnvelope.stub(:fit_axis,->(*_args) { raise S::Core::Error,'Hình học không khớp' }) do
          error = assert_raises(S::Core::Error) { S::AssemblyEnvelope.apply(nil,{'scope'=>box(600)},[],growth:{'scope'=>[1]}) }
          assert_equal 'Hình học không khớp',error.message
        end
      end
    end
  end
end

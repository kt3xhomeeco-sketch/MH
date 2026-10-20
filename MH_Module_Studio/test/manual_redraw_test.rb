# encoding: UTF-8
require 'minitest/autorun'
require 'minitest/mock'
require_relative '../module_options'

class ModuleStudioManualRedrawTest < Minitest::Test
  S=MH::ModuleStudio
  Model=Struct.new(:active_path)
  Entity=Struct.new(:persistent_id,:model,:trial) do
    def get_attribute(_dict,key,default=nil);key=='trial' ? trial : default;end
  end

  def test_button_validates_current_selection_and_session_before_redraw
    model=Model.new(nil);root=Entity.new(1,model,true)
    options=S::ModuleOptions.allocate
    options.instance_variable_set(:@root,root);options.instance_variable_set(:@model,model);options.instance_variable_set(:@token,'current')
    refreshed=[];options.define_singleton_method(:refresh) { refreshed << true }
    calls=[]
    S::ModuleOptions.stub(:selected_options_root,root) do
      S::Assembly.stub(:redraw,->(entity) { calls << entity }) do
        assert_raises(S::Core::Error) { options.request('action'=>'redraw','root_pid'=>'1','token'=>'stale') }
        assert_raises(S::Core::Error) { options.request('action'=>'redraw','root_pid'=>'2','token'=>'current') }
        assert_empty calls
        options.request('action'=>'redraw','root_pid'=>'1','token'=>'current')
      end
    end
    assert_equal [root],calls
    assert_equal [true],refreshed
  end

  def test_managed_redraw_submits_scoped_members_to_the_shared_atomic_transaction
    model=Model.new(nil);wrapper=Entity.new(10,model,false);a=Entity.new(1,model,true);b=Entity.new(2,model,true);raw=Entity.new(3,model,false)
    links=[{'id'=>'existing'}];calls=[]
    transaction=lambda do |actual_model,records,mutable_anchors:,redraw:|
      assert_equal model,actual_model;assert_equal links,records
      assert_equal [{'root'=>'1','scope'=>'10'},{'root'=>'2','scope'=>'10'}],mutable_anchors
      assert_same mutable_anchors,redraw
      mutable_anchors[0]['root']='remapped'
      assert_equal 'remapped',redraw.first['root']
      calls << redraw
    end
    S::Runtime.stub(:ensure_assembly_context,nil) do
      S::AssemblyContainers.stub(:managed?,->(entity) { entity==wrapper }) do
        S::AssemblyContainers.stub(:members,[a,b,raw]) do
          S::Assembly.stub(:records,links) do
            S::Assembly.stub(:transact,transaction) do
              S::Assembly.redraw(wrapper)
            end
          end
        end
      end
    end
    assert_equal 1,calls.length
  end
end

# encoding: UTF-8
require 'minitest/autorun'
require 'minitest/mock'
require_relative '../assembly'

class ModuleStudioManualAssemblyTest < Minitest::Test
  S = MH::ModuleStudio

  def test_save_keeps_actual_roots_and_only_explicit_group_requests_reparenting
    record = {'mode'=>'contact','a'=>{'root'=>'1'},'b'=>{'root'=>'2'},'gap'=>3}
    saved = nil
    S::Assembly.stub(:records,[]) do
      S::Assembly.stub(:transact,->(_model,rows,**options) { assert_empty options; saved=rows.first }) do
        S::Assembly.save(nil,record)
      end
    end
    refute saved.key?('scope')
    refute saved.key?('external')
    assert_equal record['a'],saved['a']
    S::Assembly.stub(:records,[saved]) do
      S::Assembly.stub(:transact,->(_model,rows,**options) { assert_same rows.first,options.fetch(:group_record) }) do
        assert_equal saved,S::Assembly.group(nil,saved)
      end
    end
    refute record.key?('id')
  end

  def test_new_module_linked_to_existing_group_uses_world_space_without_automatic_merging
    row = {'mode'=>'contact','a'=>{'root'=>'1','scope'=>'existing'},'b'=>{'root'=>'2'},'gap'=>3}
    S::Assembly.stub(:records,[]) do
      S::Assembly.stub(:transact,->(_model,rows,**options) { assert_empty options; assert rows.first['external']; refute rows.first['scope'] }) do
        S::Assembly.save(nil,row)
      end
    end
    row['b']['scope'] = 'existing'
    S::Assembly.stub(:records,[]) do
      S::Assembly.stub(:transact,->(_model,rows,**_options) { assert_equal 'existing',rows.first['scope']; refute rows.first['external'] }) do
        S::Assembly.save(nil,row)
      end
    end
  end

  def test_display_names_resolve_both_modules_without_changing_saved_anchors
    row = {'a'=>{'root'=>'1','name'=>'old A'},'b'=>{'root'=>'2','name'=>'old B'}}
    before = JSON.generate(row)
    S::Assembly.stub(:module_name,->(_model,anchor) { 'Renamed '+anchor['root'] }) do
      S::Assembly.stub(:root,->(*) { raise S::Core::Error,'stale face' }) do
        display = S::Assembly.display_record(nil,row)
        assert_equal 'Renamed 1',display.dig('a','module_name')
        assert_equal 'Renamed 2',display.dig('b','module_name')
        assert_equal 'old A',display.dig('a','name')
      end
    end
    assert_equal before,JSON.generate(row)
  end

  def test_copied_assembly_remaps_shared_active_anchor_only_once
    component = Object.new
    definition = Struct.new(:instances).new([1,2])
    component.define_singleton_method(:persistent_id) { 99 }
    component.define_singleton_method(:definition) { definition }
    component.define_singleton_method(:make_unique) { @unique = true }
    member = Struct.new(:persistent_id,:key) do
      def get_attribute(_dictionary,_name)
        key
      end
    end
    old = [member.new(1,'A'),member.new(2,'B')]
    fresh = [member.new(11,'A'),member.new(12,'B')]
    anchor = {'root'=>'2','scope'=>'99'}
    record = {'scope'=>'99','a'=>{'root'=>'1','scope'=>'99'},'b'=>anchor,'copies'=>['2']}
    S::AssemblyContainers.stub(:containers,[component]) do
      S::AssemblyContainers.stub(:members,->(entity) { entity.instance_variable_get(:@unique) ? fresh : old }) do
        S::AssemblyContainers.stub(:member_key,->(entity) { entity.key }) do
          S::AssemblyContainers.independent!(nil,[record,{'b'=>anchor,'scope'=>'99'},record])
        end
      end
    end
    assert_equal '12',anchor['root']
    assert_equal '11',record.dig('a','root')
    assert_equal ['12'],record['copies']
  end

  def test_external_batch_stores_remapped_internal_scope_without_solving_geometry
    model = Object.new
    model.define_singleton_method(:start_operation) { |*_args| true }
    model.define_singleton_method(:commit_operation) { true }
    old = {'id'=>'S:old','scope'=>'S','mode'=>'contact','gap'=>3,
      'a'=>{'root'=>'A','scope'=>'S'},'b'=>{'root'=>'B','scope'=>'S'}}
    added = {'id'=>'new','external'=>true,'mode'=>'contact','gap'=>3,
      'a'=>{'root'=>'B','scope'=>'S'},'b'=>{'root'=>'outside'}}
    stored = false
    S::Runtime.stub(:ensure_top_level,nil) do
      S::AssemblyContainers.stub(:independent!,->(_model,rows,scopes:) {
        assert_equal ['S'],scopes
        rows.each { |row| %w[a b].each { |key| row[key]['root']='privateB' if row[key]['scope']=='S' && row[key]['root']=='B' } }
      }) do
        S::AssemblyContainers.stub(:store,->(_model,rows,scopes:) {
          assert_equal ['S'],scopes # external rows have no row-level scope
          assert_equal 'privateB',rows.first.dig('b','root')
          assert_equal 'privateB',rows.last.dig('a','root')
          stored = true
        }) do
          S::Assembly.stub(:verify,nil) do
            S::Assembly.stub(:transact,->(*) { flunk 'Discovery must not move/scale/redraw geometry' }) do
              S::Assembly.store_contacts(model,[old],[added])
            end
          end
        end
      end
    end
    assert stored
  end
end

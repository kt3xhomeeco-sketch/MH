# encoding: UTF-8
require 'minitest/autorun'
require 'minitest/mock'
require_relative '../assembly'
require_relative '../assembly_tree'

class ModuleStudioAssemblyTreeTest < Minitest::Test
  S=MH::ModuleStudio
  Definition=Struct.new(:name,:entities)
  Entity=Struct.new(:persistent_id,:name,:definition,:managed)
  Model=Struct.new(:entities)

  def entity(id,managed=false,members=[])
    Entity.new(id,'Module',Definition.new('Definition',members),managed)
  end

  def ref(root,scope=nil)
    {'root'=>root.to_s,'scope'=>scope}.compact
  end

  def rows(model,records)
    tree=S::AssemblyTree.new(model,nil)
    S::Assembly.stub(:records,records) do
      S::Assembly.stub(:container?,->(item) { item.is_a?(Entity) }) do
        S::AssemblyContainers.stub(:managed?,->(item) { item.managed }) do
          S::AssemblyContainers.stub(:members,->(item) { item.definition.entities }) do
            S::Assembly.stub(:presentation_groups,->(_model,subset) { S::AssemblyPresentation.groups(subset) }) do
              tree.rebuild
            end
          end
        end
      end
    end
    tree.rows
  end

  def test_unlinked_raw_modules_and_empty_assemblies_are_absent
    model=Model.new([entity(1),entity(2,true,[entity(3)])])
    assert_empty rows(model,[])
  end

  def test_only_link_participants_and_repeat_copies_appear_with_distinct_instance_identity
    a=entity(1);b=entity(2);raw=entity(3);copy=entity(4)
    links=[{'id'=>'repeat','mode'=>'repeat','a'=>ref(1),'b'=>ref(2),'copies'=>['4'],'count'=>2}]
    result=rows(Model.new([a,b,raw,copy]),links)
    roots=result.select { |row| row['depth'].zero? && row['kind']=='module' }.map { |row| row['ref']['root'] }
    assert_equal %w[1 2 4],roots
    assert_equal 1,(result.count { |row| row['record']=='repeat' })
    assert_equal %w[1 2],(result.select { |row| row['depth']==2 && row['kind']=='module' }.map { |row| row['ref']['root'] })
    assert_empty rows(Model.new([a,b,raw,copy]),[])
  end

  def test_scoped_members_do_not_leak_to_other_copied_assemblies
    members=[entity(1),entity(2),entity(3)]
    one=entity(10,true,members);other=entity(20,true,members)
    links=[{'id'=>'10:link','scope'=>'10','mode'=>'contact','gap'=>0,'a'=>ref(1,'10'),'b'=>ref(2,'10')}]
    result=rows(Model.new([one,other,entity(1)]),links)
    assert_equal ['scope:10'],(result.select { |row| row['kind']=='assembly' }.map { |row| row['id'] })
    assert_equal %w[1 2],(result.select { |row| row['depth']==1 && row['kind']=='module' }.map { |row| row['ref']['root'] })
    refute(result.any? { |row| row['ref']==ref(3,'10') })
    refute(result.any? { |row| row['ref']==ref(1) })
  end

  def test_whole_wrapper_link_does_not_list_unlinked_children
    wrapper=entity(10,true,[entity(11),entity(12)])
    links=[{'id'=>'external','mode'=>'contact','gap'=>3,'a'=>ref(10),'b'=>ref(30)}]
    result=rows(Model.new([wrapper,entity(30)]),links)
    assert(result.any? { |row| row['id']=='scope:10' })
    refute(result.any? { |row| %w[11 12].include?(row.dig('ref','root')) })
  end
end

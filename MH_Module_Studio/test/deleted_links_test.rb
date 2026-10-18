# encoding: UTF-8
require 'minitest/autorun'
require 'minitest/mock'
require_relative '../assembly'

class ModuleStudioDeletedLinksTest < Minitest::Test
  S=MH::ModuleStudio

  def test_operational_records_hide_missing_modules_without_deleting_undo_history
    model=Object.new
    rows=[{'id'=>'live','a'=>{'root'=>'1'},'b'=>{'root'=>'2'}},
          {'id'=>'deleted','a'=>{'root'=>'1'},'b'=>{'root'=>'3'}}]
    before=JSON.generate(rows)
    existing=%w[1 2]
    S::AssemblyContainers.stub(:read,->(owner) { assert_same model,owner;S::Core.copy_data(rows) }) do
      S::AssemblyContainers.stub(:containers,[]) do
        S::AssemblyContainers.stub(:reference_present?,->(_owner,anchor) { existing.include?(anchor['root']) }) do
          assert_equal ['live'],(S::Assembly.records(model).map { |row| row['id'] })
          existing << '3' # Undo restores the instance; no record was destroyed.
          assert_equal %w[live deleted],(S::Assembly.records(model).map { |row| row['id'] })
        end
      end
    end
    assert_equal before,JSON.generate(rows)
  end

  def test_scoped_and_external_links_are_filtered_by_their_own_reference_scope
    model=Object.new;wrapper=Struct.new(:persistent_id).new(99)
    internal={'id'=>'x','a'=>{'root'=>'1'},'b'=>{'root'=>'2'}}
    external={'id'=>'outside','a'=>{'root'=>'1','scope'=>'99'},'b'=>{'root'=>'3'}}
    present=->(_model,anchor) { anchor['root']!='2' }
    S::AssemblyContainers.stub(:read,->(owner) { S::Core.copy_data(owner.equal?(model) ? [external] : [internal]) }) do
      S::AssemblyContainers.stub(:containers,[wrapper]) do
        S::AssemblyContainers.stub(:reference_present?,present) do
          assert_equal ['outside'],(S::Assembly.records(model).map { |row| row['id'] })
        end
      end
    end
  end
end

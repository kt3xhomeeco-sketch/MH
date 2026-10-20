# encoding: UTF-8
require 'minitest/autorun'
require 'minitest/mock'
require_relative '../assembly'
class ModuleStudioFrontDatumTest < Minitest::Test
  S=MH::ModuleStudio
  def record
    {'id'=>'old','mode'=>'contact','gap'=>100,'external'=>true,
     'a'=>{'root'=>'host','scope'=>'wrapper','part'=>'brace','path'=>['legacy'],'axis'=>1,'side'=>1},
     'b'=>{'root'=>'drawer','axis'=>1,'side'=>0},
     'import_link'=>{'version'=>1,'kind'=>'inside','slot'=>[1,0],'role'=>'module'}}
  end
  def normalize(rows)
    plane=->(_model,ref) { {'normal'=>ref['part'] ? [0,1,0] : [0,-1,0]} }
    S::Assembly.stub(:world_plane,plane) do
      S::Assembly.stub(:module_name,'Host') { S::ImportLinks.normalize_front_datums(nil,rows) }
    end
  end
  def test_old_import_front_uses_host_datum_with_the_same_displayed_clearance
    row=record;repaired=normalize([row])
    assert_equal [row],repaired
    assert_equal(-100,row['gap']);assert_equal 100,S::AssemblyPresentation.gap(row,row['gap'])
    assert_equal({'root'=>'host','scope'=>'wrapper','path'=>[],'axis'=>1,'side'=>0,'level'=>'module','name'=>'Host / Mặt trước phủ bì'},row['a'])
    assert row['external'];assert_equal 'drawer',row['b']['root']
    assert_empty normalize([row])
  end
  def test_manual_other_slots_outside_measurement_bound_and_new_real_front_are_untouched
    rows=[record.tap { |r| r.delete('import_link') },record.tap { |r| r['import_link']['slot']=[2,0] },
          record.tap { |r| r['import_link']['kind']='outside' },record.merge('r1'=>{'root'=>'ruler'}),
          record.tap { |r| r['import_link']['front_datum']='host_front' }]
    before=Marshal.dump(rows)
    assert_empty normalize(rows);assert_equal before,Marshal.dump(rows)
  end
  def test_negative_displayed_clearance_keeps_its_meaning
    row=record.merge('gap'=>-8)
    normalize([row]);assert_equal(-8,S::AssemblyPresentation.gap(row,row['gap']))
  end
  def test_new_import_records_mark_the_front_policy_without_replacing_a_real_face
    placement={'kind'=>'inside','template'=>{'role'=>'module'},'matches'=>[{'slot'=>[1,0],'gap'=>100,'target'=>{'anchor'=>record['a'],'virtual'=>false}}]}
    row=S::ImportLinks.records(placement,Struct.new(:persistent_id,:name).new(2,'Drawer')).first
    assert_equal 'host_front',row.dig('import_link','front_datum')
    before=Marshal.dump(row);assert_empty normalize([row]);assert_equal before,Marshal.dump(row)
  end
end

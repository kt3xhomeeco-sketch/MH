# encoding: UTF-8
require 'minitest/autorun'
require 'minitest/mock'
require_relative '../assembly'

class ModuleStudioDoorModuleLinkTest < Minitest::Test
  S=MH::ModuleStudio

  def test_restore_target_is_applied_even_when_reservation_attribute_was_lost
    script=<<~'RUBY'
      module Geom
        class Vector3d
          def initialize(values);@values=values;end
          def transform(_frame);self;end
          def length;1.0;end
          def normalize;self;end
          def to_a;@values;end
        end
      end
      require ARGV.fetch(0)
      s=MH::ModuleStudio
      host=Object.new;span=580.4
      host.define_singleton_method(:transformation) { nil }
      host.define_singleton_method(:delete_attribute) { |*| }
      s::ImportLinks.define_singleton_method(:roots) { |_| [[host,{'root'=>'host'}]] }
      s::ImportLinks.define_singleton_method(:states) { |_| {} }
      s::Assembly.define_singleton_method(:projection) { |*| [0,span] }
      s::Assembly.define_singleton_method(:resize) { |_,_,wanted| span=wanted }
      s::Assembly.define_singleton_method(:translate) { |*| }
      s::ImportLinks.apply_reservations(nil,[],targets:{[nil,'host','1:0']=>600})
      raise 'Lost restore target' unless (span-600).abs<0.001
    RUBY
    require 'open3'
    require 'rbconfig'
    _output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,File.expand_path('../assembly.rb',__dir__))
    assert status.success?,error
  end

  def test_module_front_highlight_covers_whole_opening_and_links_to_module
    bounds=[[0,18.6,0],[600,200,500]]
    front=S::ImportLinks.module_faces({'root'=>'host'},bounds).find { |face| face['axis']==1 && face['side']==0 }
    assert_equal 'module',front.dig('anchor','level')
    assert_empty front.dig('anchor','path')
    assert front['module_envelope']
    assert_equal 6,front['triangles'].length
    area=front['triangles'].each_slice(3).sum do |a,b,c|
      ((b[0]-a[0])*(c[2]-a[2])-(c[0]-a[0])*(b[2]-a[2])).abs/2.0
    end
    assert_equal 600*500,area
    front['points'].each { |point| assert_in_delta 18.6,point[1],0.000001 }
  end

  def test_exterior_door_contacts_prefer_detail_faces_over_envelope_fallbacks
    anchor={'root'=>'host'}
    bounds=[[0,19.6,0],[600,600,800]]
    faces=S::ImportTemplate.envelope_faces(anchor,bounds).map.with_index do |face,index|
      points=face['points']
      face.merge('virtual'=>false,'triangles'=>[points[0],points[1],points[2],points[0],points[2],points[3]],
                 'anchor'=>anchor.merge('path'=>[index.to_s]))
    end
    faces+=S::ImportTemplate.envelope_faces(anchor,bounds).map do |face|
      points=face['points']
      face.merge('module_envelope'=>true,'triangles'=>[points[0],points[1],points[2],points[0],points[2],points[3]])
    end
    template=S::ImportTemplate.defaults.merge('enabled'=>true,'role'=>'door','mode'=>'outside')
    result=S::ImportTemplate.match(template,[[0,0,0],[600,18.6,800]],bounds,faces,mode:'outside',mount:[1,0])

    assert_equal 5,result['matches'].length
    assert(result['matches'].all? { |match| !match.dig('target','virtual') })
    assert(result['matches'].all? { |match| match.dig('target','anchor','path').any? })
    mount=result['matches'].find { |match| match['mount'] }
    assert_equal 1,mount['gap']
    assert_equal 4,mount.dig('target','points').length
    assert_equal 6,mount.dig('target','triangles').length
  end

  def test_door_link_persists_original_host_target_for_explicit_unlink
    target={'anchor'=>{'root'=>'host','axis'=>1,'side'=>0,'level'=>'module'},'virtual'=>true,
            'module_envelope'=>true,'points'=>[[0,0,0],[1,0,0],[1,0,1],[0,0,1]]}
    placement={'matches'=>[{'slot'=>[1,1],'target'=>target,'gap'=>1,'mount'=>true},
                           {'slot'=>[0,0],'target'=>target,'gap'=>0,'mount'=>false}],
               'template'=>{'role'=>'door'},'kind'=>'outside','host_target_mm'=>600,
               'door_host_face'=>[1,0],'door_clearance_mm'=>1}
    root=Struct.new(:persistent_id,:name).new(22,'Door')
    rows=S::ImportLinks.records(placement,root)
    row=rows.first
    assert(rows.all? { |item| item.dig('import_link','door_relation') })
    assert_equal 1,(rows.count { |item| item.dig('import_link','door_mount') })
    assert(rows.all? { |item| item.dig('import_link','host_face')==[1,0] })
    assert(rows.all? { |item| item.dig('import_link','door_clearance_mm')==1 })
    assert_equal 'module',row.dig('a','level')
    assert_equal 600,row.dig('import_link','host_target_mm')

    host=Object.new
    S::Assembly.stub(:root,host) do
      S::ImportLinks.stub(:states,{'1:0'=>{'target'=>600,'reserved'=>19.6,'applied'=>580.4,'scale'=>1}}) do
        targets=S::ImportLinks.release_targets(nil,[row],[])
        assert_equal 600,targets[[nil,'host','1:0']]
        assert_empty S::ImportLinks.release_targets(nil,[row],[rows.last])
      end
      S::ImportLinks.stub(:states,{}) do
        assert_equal 600,S::ImportLinks.release_targets(nil,[row],[])[[nil,'host','1:0']]
      end
    end
  end

  def test_explicit_host_scale_target_wins_over_original_door_snapshot
    row={'id'=>'door-link','a'=>{'root'=>'host'},'b'=>{'root'=>'door'},
         'import_link'=>{'door_mount'=>true,'host_face'=>[1,0],'host_target_mm'=>600}}
    S::Assembly.stub(:root,Object.new) do
      S::ImportLinks.stub(:states,{'1:0'=>{'target'=>720,'reserved'=>19.6,'applied'=>700.4,'scale'=>1}}) do
        assert_equal 720,S::ImportLinks.release_targets(nil,[row],[])[[nil,'host','1:0']]
      end
    end
  end

  def test_removing_one_of_multiple_doors_does_not_release_shared_host_face
    make_row=lambda do |id|
      {'id'=>id,'a'=>{'root'=>'host'},'b'=>{'root'=>"#{id}-door"},
       'import_link'=>{'door_mount'=>true,'host_face'=>[1,0],'host_target_mm'=>600}}
    end
    first=make_row.call('first');second=make_row.call('second')
    assert_empty S::ImportLinks.release_targets(nil,[first],[second])
  end

  def test_erasing_linked_door_exposes_its_saved_restore_target_to_sync
    model=Object.new
    row={'id'=>'door-link','a'=>{'root'=>'host'},'b'=>{'root'=>'erased-door'},
         'import_link'=>{'door_mount'=>true,'host_face'=>[1,0],'host_target_mm'=>600}}
    present=->(_owner,anchor) { anchor['root']=='host' }
    S::AssemblyContainers.stub(:read,[row]) do
      S::AssemblyContainers.stub(:containers,[]) do
        S::AssemblyContainers.stub(:reference_present?,present) do
          dangling=S::AssemblyContainers.dangling_door_links(model)
          assert_equal ['door-link'],(dangling.map { |item| item['id'] })
          host=Object.new
          S::Assembly.stub(:root,host) do
            S::ImportLinks.stub(:states,{}) do
              assert_equal({[nil,'host','1:0']=>600},S::ImportLinks.release_targets(model,dangling,[]))
            end
          end
        end
      end
    end
  end

  def test_explicit_unlink_passes_restored_target_into_assembly_transaction
    model=Object.new;host=Object.new
    row={'id'=>'door-link','a'=>{'root'=>'host'},'b'=>{'root'=>'door'},
         'import_link'=>{'door_mount'=>true,'host_face'=>[1,0],'host_target_mm'=>600}}
    transaction=lambda do |_model,proposed,**options|
      assert_empty proposed
      assert_equal({[nil,'host','1:0']=>600},options[:reservation_targets])
      :restored
    end
    S::Runtime.stub(:ensure_assembly_context,true) do
      S::Assembly.stub(:records,[row]) do
        S::Assembly.stub(:root,host) do
          S::ImportLinks.stub(:states,{}) do
            S::Assembly.stub(:transact,transaction) do
              assert_equal :restored,S::Assembly.remove(model,'door-link')
            end
          end
        end
      end
    end
  end
end

# encoding: UTF-8
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'json'

class ModuleStudioPairedDepthScaleTest < Minitest::Test
  def test_total_depth_scale_is_inferred_only_when_every_opposed_door_scales_with_the_host
    script=<<~'RUBY'
      require ARGV.fetch(0)
      module Geom
        class Vector
          def initialize(values);@values=values;end
          def length;Math.sqrt(@values.sum { |v| v*v });end
          def normalize;self.class.new(@values.map { |v| v/length });end
          def dot(other);@values.zip(other.instance_variable_get(:@values)).sum { |a,b| a*b };end
        end
        class Transformation
          def initialize(values);@values=values;end
          def to_a;@values;end
          def xaxis;Vector.new(@values[0,3]);end
          def yaxis;Vector.new(@values[4,3]);end
          def zaxis;Vector.new(@values[8,3]);end
        end
        Vector3d=Vector
      end
      s=MH::ModuleStudio
      root=Object.new
      root.define_singleton_method(:get_attribute) do |_dictionary,key,default=nil|
        key=='door_depth_reservations_v1' ? JSON.generate('1:0'=>{'target'=>1000,'reserved'=>18.6,'applied'=>981.4,'scale'=>1}) : default
      end
      s::ImportLinks.define_singleton_method(:states) { |_host| {'1:0'=>{'target'=>1000,'reserved'=>18.6,'applied'=>981.4,'scale'=>1}} }
      s::Assembly.define_singleton_method(:root) { |_model,_anchor| root }
      matrix=lambda do |scale,rotated=false|
        data=s::Frames::IDENTITY.dup
        if rotated
          data[0]=0;data[1]=scale;data[4]=-1;data[5]=0
        else
          data[5]=scale
        end
        data
      end
      current={};s::Assembly.define_singleton_method(:world_transform) { |_model,anchor| Geom::Transformation.new(current.fetch(anchor['root'])) }
      record={'a'=>{'root'=>'host'},'b'=>{'root'=>'door'},'import_link'=>{'door_mount'=>true,'host_face'=>[1,0]}}
      before={[nil,'host']=>matrix.call(1),[nil,'door']=>matrix.call(1),[nil,'door2']=>matrix.call(1)}
      result={}
      current['host']=matrix.call(0.6);current['door']=matrix.call(0.6)
      result['paired']=s::ImportLinks.scaled_reservation_targets(nil,[record],before).values
      current['door']=matrix.call(1)
      result['host_only']=s::ImportLinks.scaled_reservation_targets(nil,[record],before).values
      current['door']=matrix.call(0.6);current['door2']=matrix.call(1)
      second=s::Core.copy_data(record);second['b']['root']='door2'
      result['partial']=s::ImportLinks.scaled_reservation_targets(nil,[record,second],before).values
      current['door2']=matrix.call(0.6)
      result['two_doors']=s::ImportLinks.scaled_reservation_targets(nil,[record,second],before).values
      before[[nil,'door']]=matrix.call(1,true);current['door']=matrix.call(0.6,true)
      result['rotated_door']=s::ImportLinks.scaled_reservation_targets(nil,[record],before).values
      result['missing_baseline']=s::ImportLinks.scaled_reservation_targets(nil,[record],{}).values
      puts JSON.generate(result)
    RUBY
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,File.expand_path('../assembly.rb',__dir__))
    assert status.success?,error
    result=JSON.parse(output)
    %w[paired two_doors rotated_door].each { |key| assert_equal [600.0],result[key],key }
    %w[host_only partial missing_baseline].each { |key| assert_empty result[key],key }
  end
end

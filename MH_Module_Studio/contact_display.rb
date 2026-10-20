# encoding: UTF-8
require_relative 'assembly_math'
module MH
  module ModuleStudio
    # Portable display geometry only; no constraint calculation or host writes.
    module ContactDisplay
      extend self
      FACES=[[0,1,2,3],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]].freeze
      def area(plane)
        p=plane.fetch('points');v=AssemblyMath.cross(AssemblyMath.sub(p[1],p[0]),AssemblyMath.sub(p[3],p[0]))
        Math.sqrt(AssemblyMath.dot(v,v))
      end
      def prism(a,b)
        AssemblyMath.parallel!(a['normal'],b['normal'])
        small,other=area(a)<=area(b) ? [a,b] : [b,a]
        normal=AssemblyMath.unit(a['normal']);base=Core.copy_data(small.fetch('points'))
        distance=AssemblyMath.dot(AssemblyMath.sub(other['point'],base.first),normal)
        vector=AssemblyMath.mul(normal,distance)
        center=3.times.map { |axis| base.sum { |point| point[axis] }/base.length }
        {'points'=>base+base.map { |p| AssemblyMath.add(p,vector) },'ends'=>[center,AssemblyMath.add(center,vector)],
         'volume'=>distance.abs>0.02,'area'=>area(small)}
      end
      def inside?(x,y,polygon)
        inside=false;j=polygon.length-1
        polygon.each_with_index do |point,i|
          a=polygon[j];b=point
          inside=!inside if (a[1]>y)!=(b[1]>y) && x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]
          j=i
        end
        inside
      end
      def hit(items,x,y)
        items.reverse_each do |item|
          r=item['rect'];return ['dimension',item['id']] if x.between?(r[0],r[2]) && y.between?(r[1],r[3])
        end
        items.reverse_each do |item|
          return ['settings',item['id']] if item['volume'] && item['polygons'].any? { |poly| inside?(x,y,poly) }
        end
        nil
      end
    end
  end
end

# encoding: UTF-8
require_relative 'core'
module MH
  module ModuleStudio
    # Native auxiliary geometry follows its owning direct mesh, never descendants.
    module GuideGeometry
      extend self
      KEY='guide_motion_version'.freeze
      def pending?(root,calculation)
        keys=calculation['parts'].map { |part| part['key'] }
        walk=lambda do |item|
          entries=item.definition.entities.to_a
          if keys.include?(item.get_attribute(Reader::DICT,'part_key','root:mesh')) &&
             entries.grep(Sketchup::ConstructionPoint).any? { |point| point.get_attribute(Reader::DICT,KEY)!=1 }
            return true
          end
          entries.any? { |child| child.respond_to?(:definition) && walk.call(child) }
        end
        walk.call(root)
      end
      def inside?(point,bounds,tolerance)
        3.times.all? { |axis| point[axis]>=bounds[0][axis]-tolerance && point[axis]<=bounds[1][axis]+tolerance }
      end
      def recover(bindings,rule,calculation)
        return unless rule && defined?(Sketchup::ConstructionPoint)
        snapshot=rule && (rule.dig('formula_engine','attribute_program') || rule['attribute_program'])
        parts=calculation['parts'].to_h { |part| [part['key'],part] }
        bindings.each do |key,binding|
          part=parts[key];next unless part
          points=binding[:entity].definition.entities.grep(Sketchup::ConstructionPoint)
          next if points.empty?
          legacy=points.none? { |point| point.get_attribute(Reader::DICT,KEY)==1 }
          frame=Geom::Transformation.new(binding[:frame])
          reference=GeometryMotion.guide_reference(snapshot,key)
          points.each do |point|
            next if point.get_attribute(Reader::DICT,KEY)==1
            current=point.position.transform(frame).to_a.map { |v| v*25.4 }
            if legacy && reference && !inside?(current,part['old_bounds'],Core::TOLERANCE) && inside?(point.position.to_a,reference['local_bounds'],0.01/25.4)
              original=point.position.transform(Geom::Transformation.new(reference['frame']))
              delta=Geom::Transformation.new(GeometryMotion.matrix(reference['bounds'],part['old_bounds']))
              restored=original.transform(delta).transform(frame.inverse)
              binding[:entity].definition.entities.transform_entities(Geom::Transformation.translation(restored-point.position),[point])
              binding[:entity].definition.invalidate_bounds
            end
            point.set_attribute(Reader::DICT,KEY,1)
          end
        end
      end
    end
  end
end

# encoding: UTF-8

require 'sketchup'

module MH
  module Geo
    module Util
      module_function

      def is_container?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end

      def get_ents(parent)
        return parent.entities if parent.is_a?(Sketchup::Group)
        return parent.entities if parent.is_a?(Sketchup::ComponentDefinition)
        return parent.definition.entities if parent.is_a?(Sketchup::ComponentInstance)

        nil
      end

      def grep_ents(parent, mode)
        ents = get_ents(parent)
        return [] unless ents

        case mode
        when :face
          ents.grep(Sketchup::Face)
        when :edge
          ents.grep(Sketchup::Edge)
        when :vertex
          ents.grep(Sketchup::Edge).flat_map(&:vertices).uniq
        when :group
          ents.grep(Sketchup::Group)
        else
          []
        end
      end

      def get_transform(instance_path)
        transformation = Geom::Transformation.new
        Array(instance_path).reject { |e| !e.respond_to?(:transformation) }.each do |inst|
          transformation *= inst.transformation
        end
        transformation
      end

      def transform_from_path(path)
        transformation = IDENTITY
        Array(path).reverse_each do |entity|
          transformation = entity.transformation * transformation if entity.respond_to?(:transformation)
        end
        transformation
      end

      def intersect_fix(entities)
        entities.intersect_with(
          false,
          Geom::Transformation.new,
          entities,
          Geom::Transformation.new,
          true,
          entities.grep(Sketchup::Edge)
        )
      end

      def find_face(entities)
        entities.grep(Sketchup::Edge).each { |edge| edge.find_faces if edge.valid? }
      end

      def find_concave_vertex(face, limit_length, limit_angle)
        if defined?(MH::Geo::NativeBridge) && MH::Geo::NativeBridge.respond_to?(:loaded?) && MH::Geo::NativeBridge.loaded?
          begin
            loops = face.loops.map { |loop| loop.vertices.map(&:position) }
            result = MH::Geo::NativeBridge.find_concave_vertices(loops, limit_length, limit_angle, face.normal)
            if result && result.any?
              vertices = face.vertices
              return result.filter_map { |pt| vertices.find { |vtx| vtx.position.distance(pt) < TOL } }
            end
          rescue => e
            MH::Shared.dbg("MH::Geo Native find_concave_vertex error: #{e.message}") if defined?(MH::Shared)
          end
        end

        output = []
        face.loops.each do |loop|
          verts = loop.vertices
          verts.pop if verts.first == verts.last
          verts.each_with_index do |vtx, index|
            prev = verts[index - 1]
            curr = vtx
            nxt = verts[(index + 1) % verts.size]
            vec1 = prev.position.vector_to(curr.position)
            vec2 = nxt.position.vector_to(curr.position)
            next unless vec1.length >= limit_length && vec2.length >= limit_length

            angle = vec1.angle_between(vec2)
            next unless angle.between?(90.degrees - limit_angle.degrees, 90.degrees + limit_angle.degrees)

            vec = vec1.normalize + vec2.normalize
            next if vec.length == 0

            vec.length = 1.mm
            output << curr if face.classify_point(curr.position + vec) == Sketchup::Face::PointInside
          end
        end
        output
      end
    end
  end
end

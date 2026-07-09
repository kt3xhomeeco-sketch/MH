# encoding: UTF-8

require 'sketchup'

module MH
  module Geo
    module BoardBuilder
      module_function

      def from_face(face, entities, offset: 0, thickness: 0)
        return nil unless face && face.valid? && entities

        group = entities.add_group
        hole_faces = []
        Face.inner_loops(face).each do |loop|
          points = loop.vertices.map(&:position)
          hole_face = group.entities.add_face(points)
          hole_faces << hole_face if hole_face && hole_face.valid?
        end

        outer_points = face.outer_loop.vertices.map(&:position)
        new_face = if Offset.respond_to?(:create_face_preserving_curves)
                     Offset.create_face_preserving_curves(group.entities, outer_points, face)
                   else
                     group.entities.add_face(outer_points)
                   end
        unless new_face && new_face.valid?
          group.erase! if group.valid?
          return nil
        end

        hole_faces.each { |hole_face| hole_face.erase! if hole_face.valid? }
        Face.orient_normal(new_face, face)
        build_from_face(new_face, group.entities, offset, thickness)
        group
      end

      def from_points(points, entities, normal:, offset: 0, thickness: 0)
        return nil unless points && points.size >= 3 && entities

        group = entities.add_group
        face = group.entities.add_face(points)
        unless face && face.valid?
          group.erase! if group.valid?
          return nil
        end
        face.reverse! unless face.normal.samedirection?(normal)
        build_from_face(face, group.entities, offset, thickness)
        group
      end

      def from_box(entities, transform:, width_mm:, depth_mm:, thickness_mm:, offset: 0)
        width = width_mm.to_f.mm
        depth = depth_mm.to_f.mm
        thickness = thickness_mm.to_f.mm
        points = [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(width, 0, 0),
          Geom::Point3d.new(width, depth, 0),
          Geom::Point3d.new(0, depth, 0)
        ]
        group = from_points(points, entities, normal: Z_AXIS, offset: offset, thickness: thickness)
        group.transform!(transform) if group && transform
        group
      end

      def build_from_face(face, entities, offset, thickness)
        target_face = face
        if offset && offset != 0
          original_edges = face.edges
          offset_face = Offset.moffset_old(face, offset, entities)
          offset_face = entities.grep(Sketchup::Face).find { |candidate| candidate != face && candidate.valid? } unless offset_face && offset_face.valid?
          if offset_face && offset_face.valid?
            original_edges.each { |edge| edge.erase! if edge.valid? }
            target_face = offset_face
          end
        end
        target_face.pushpull(thickness) if target_face && target_face.valid? && thickness && thickness != 0
        target_face
      end
    end
  end
end

# encoding: UTF-8

require 'sketchup'

module MH
  module Geo
    module BoardAnalyzer
      module_function

      def calc_thickness(group)
        faces = group.definition.entities.grep(Sketchup::Face)
        largest = faces.max_by(2) { |face| face.area }
        return unless largest && largest.size == 2

        face1, face2 = largest
        return if Face.faces_coplanar?(face1, face2)
        return unless (face1.area - face2.area).abs < AREA_TOL

        Face.calc_distance(face1, face2)
      end

      def add_thickness(group, distance)
        faces = group.definition.entities.grep(Sketchup::Face)
        largest = faces.max_by(2) { |face| face.area }
        return unless largest && largest.size == 2

        delta = distance / 2
        largest.each { |face| face.pushpull(delta) }
      end

      def change_thickness(group, target, bounds)
        faces = group.definition.entities.grep(Sketchup::Face)
        largest = faces.max_by(2) { |face| face.area }
        return unless largest && largest.size == 2

        face1, face2 = largest
        distance = Face.calc_distance(face1, face2)
        return unless distance && distance > 0

        delta = target - distance
        if Face.on_outer?(face1, bounds, group) && !Face.on_outer?(face2, bounds, group)
          face2.pushpull(delta)
        elsif Face.on_outer?(face2, bounds, group) && !Face.on_outer?(face1, bounds, group)
          face1.pushpull(delta)
        else
          delta /= 2
          face1.pushpull(delta)
          face2.pushpull(delta)
        end
      end

      def calc_local_size(board)
        bounds = board.definition.bounds
        transform = board.transformation
        [
          (bounds.max.x - bounds.min.x) * transform.xscale,
          (bounds.max.y - bounds.min.y) * transform.yscale,
          (bounds.max.z - bounds.min.z) * transform.zscale
        ]
      end

      def vparallel?(vector1, vector2)
        a = vector1.clone.normalize
        b = vector2.clone.normalize
        a.valid? && b.valid? && a.dot(b).abs > 1.0 - TOL
      end

      def panel?(entity)
        return false unless Util.is_container?(entity)

        entities = Util.get_ents(entity)
        return false if entities.any? { |item| Util.is_container?(item) }

        faces = entities.grep(Sketchup::Face)
        edges = entities.grep(Sketchup::Edge)
        return false unless edges.all? { |edge| edge.faces.length == 2 }

        areas = faces.map { |face| [face, face.area] }.sort_by { |(_, area)| -area }
        face1, area1 = areas[0]
        face2, area2 = areas[1]
        return false unless (area1 - area2).abs < TOL
        return false unless vparallel?(face1.normal, face2.normal)

        side_edge = edges.reject { |edge| ([face1, face2] & edge.faces).any? }.first
        return false unless side_edge

        vector = side_edge.line[1].normalize
        return false unless vparallel?(vector, face1.normal) && vparallel?(vector, face2.normal)

        side_edge.length
      end

      def calc_normal(board)
        entities = board.is_a?(Sketchup::ComponentInstance) ? board.definition.entities : board.entities
        largest_face = entities.grep(Sketchup::Face).max_by(&:area)
        return unless largest_face

        normal = largest_face.normal
        normal.transform!(board.transformation)
        normal.normalize!
        normal
      end

      def group_by_normal(boards)
        groups = []
        boards.each do |board|
          normal = calc_normal(board)
          added = false
          groups.each do |group|
            if normal.dot(group.first[1]).abs > 0.999
              group << [board, normal]
              added = true
              break
            end
          end
          groups << [[board, normal]] unless added
        end
        groups.map { |group| group.map(&:first) }
      end

      def get_cnc_faces(input)
        scale_factor_in_plane = lambda do |plane, transformation|
          normal = plane.size == 2 ? plane[1].normalize : Geom::Vector3d.new(plane[0], plane[1], plane[2]).normalize
          vector0 = normal.parallel?(Z_AXIS) ? X_AXIS : Z_AXIS
          vector1 = normal * vector0
          (vector0.transform(transformation) * vector1.transform(transformation)).length.to_f
        end

        faces = input.is_a?(Array) ? input : Util.grep_ents(input, :face)
        faces.each_with_object({}) do |face, areas|
          next unless face.is_a?(Sketchup::Face) && face.valid?

          areas[face] = face.area * scale_factor_in_plane.call(face.plane, IDENTITY)
        end.sort_by { |(_, area)| -area }.first(2).map(&:first)
      end
    end
  end
end

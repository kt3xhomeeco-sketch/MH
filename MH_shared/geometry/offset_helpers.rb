# encoding: UTF-8

require 'sketchup'

module MH::Geo
  module Offset

    def self.offset_pts(pts, plane_normal, distance)
      return [] if pts.length < 3
      cleaned_pts = pts.dup
      cleaned_pts.pop if cleaned_pts.first.distance(cleaned_pts.last) < 0.001
      return [] if cleaned_pts.length < 3

      offset_lines = []
      cleaned_pts.length.times do |i|
        p1 = cleaned_pts[i]
        p2 = cleaned_pts[(i + 1) % cleaned_pts.length]
        edge_vector = p2 - p1
        next if edge_vector.length < 0.001

        perp_vector = edge_vector.cross(plane_normal).normalize
        translation_vector = perp_vector.clone
        translation_vector.length = distance.abs
        translation_vector.reverse! if distance < 0
        offset_lines << [p1.offset(translation_vector), edge_vector]
      end

      # Each intersection belongs to the vertex at the end of the current
      # offset line. Keep the result aligned with the input vertex indices so
      # curve metadata can be transferred without shifting an arc endpoint.
      num_lines = offset_lines.length
      new_pts = Array.new(num_lines)
      num_lines.times do |i|
        intersection = Geom.intersect_line_line(offset_lines[i], offset_lines[(i + 1) % num_lines])
        new_pts[(i + 1) % num_lines] = (intersection ? intersection : offset_lines[i][0])
      end
      new_pts
    end

    # The radius grows on a convex arc and shrinks on a concave arc for an
    # outward offset. Determine that direction from the ordered boundary.
    def self.offset_arc_radius(center, radius, points, plane_normal, start_index, edge_count, distance)
      return radius + distance unless center && radius && points && points.length >= 2 && plane_normal

      count = points.length
      edges = edge_count.to_i
      return radius + distance if edges <= 0

      direction = 0.0
      edges.times do |offset|
        index = (start_index + offset) % count
        point = points[index]
        following = points[(index + 1) % count]
        tangent = point.vector_to(following)
        next if tangent.length <= 0.001.mm

        outward = tangent.cross(plane_normal)
        next if outward.length <= 0.001.mm
        outward.normalize!
        midpoint = Geom.linear_combination(0.5, point, 0.5, following)
        radial = center.vector_to(midpoint)
        next if radial.length <= 0.001.mm
        radial.normalize!
        direction += outward.dot(radial)
      end

      radius + distance * (direction < 0 ? -1.0 : 1.0)
    rescue
      radius + distance
    end

    def self.offset_chain_pts(pts, plane_normal, distance)
      return [] if pts.length < 2
      num_pts = pts.length
      offset_lines = []

      (num_pts - 1).times do |i|
        p1 = pts[i]
        p2 = pts[i + 1]
        edge_vector = p2 - p1
        next if edge_vector.length < 0.001

        perp_vector = edge_vector.cross(plane_normal).normalize
        translation_vector = perp_vector.clone
        translation_vector.length = distance.abs
        translation_vector.reverse! if distance < 0
        offset_lines << [p1.offset(translation_vector), edge_vector]
      end
      return [] if offset_lines.empty?

      new_pts = []
      new_pts << offset_lines.first[0]
      (offset_lines.length - 1).times do |i|
        intersection = Geom.intersect_line_line(offset_lines[i], offset_lines[i + 1])
        new_pts << (intersection ? intersection : offset_lines[i][0].offset(offset_lines[i][1]))
      end
      new_pts << offset_lines.last[0].offset(offset_lines.last[1])
      new_pts
    end

  end
end




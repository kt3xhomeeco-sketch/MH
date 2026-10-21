# encoding: UTF-8

require 'sketchup'

module MH::Panel
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

      num_lines = offset_lines.length
      # Keep each intersection aligned with the input vertex at the end of
      # the current offset line so curved endpoints are not shifted by one.
      new_pts = Array.new(num_lines)
      num_lines.times do |i|
        intersection = Geom.intersect_line_line(offset_lines[i], offset_lines[(i + 1) % num_lines])
        new_pts[(i + 1) % num_lines] = (intersection ? intersection : offset_lines[i][0])
      end
      new_pts
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



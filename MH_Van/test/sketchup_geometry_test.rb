# encoding: UTF-8
# Read-only regression checks against the real SketchUp geometry API.
# Load in SketchUp's Ruby Console, then call:
# MH::Van::GeometryRegression.run(Sketchup.active_model.selection.first)
module MH
  module Van
    module GeometryRegression
      def self.run(entity, transform = nil, expected_mm: nil)
        raise ArgumentError, 'Choose a board group/component' unless entity && entity.respond_to?(:definition)

        transform ||= entity.transformation
        rotation = Geom::Transformation.rotation(ORIGIN, Geom::Vector3d.new(1, 2, 3), 27.degrees)
        cases = {
          current: transform,
          rotated: rotation * transform,
          scaled_rotated: rotation * Geom::Transformation.scaling(0.61, 1.37, 2.24) * transform,
          mirrored: Geom::Transformation.scaling(-1, 1, -1) * transform,
          uniform_scale: Geom::Transformation.scaling(2.0) * transform,
          shear: Geom::Transformation.new([1, 0, 0, 0, 0, 1, 0, 0, 0.6, 0.3, 2, 0, 0, 0, 0, 1]) * transform
        }
        results = cases.map do |name, instance_transform|
          # This oracle transforms actual vertices and computes their plane
          # distances; it does not use cached normals or affine matrix columns.
          direct = MH::Van.send(:largest_face_thickness_mm, entity, instance_transform)
          actual = MH::Van.send(:thickness_mm, entity, instance_transform)
          raise "#{name}: #{actual} mm != #{direct} mm" unless direct && (actual - direct).abs < 0.001

          { case: name, actual_mm: actual, direct_mm: direct }
        end
        if expected_mm && (results.first[:actual_mm] - expected_mm).abs >= 0.001
          raise "Current board: #{results.first[:actual_mm]} mm != #{expected_mm} mm"
        end
        results
      end
    end
  end
end

# encoding: UTF-8
# Affine geometry regression outside SketchUp. This does not replace a live SketchUp check.
require 'minitest/autorun'
require_relative 'fixtures'

module Geom
  class Transformation
    attr_reader :matrix
    def initialize(matrix = MH::ModuleStudio::Frames::IDENTITY)
      @matrix = matrix.map(&:to_f)
    end
    def *(other)
      self.class.new(MH::ModuleStudio::Frames.multiply(matrix, other.matrix))
    end
    def self.translation(point)
      matrix = MH::ModuleStudio::Frames::IDENTITY.dup
      3.times { |axis| matrix[12 + axis] = point[axis] }
      new(matrix)
    end
    def self.scaling(x, y, z)
      matrix = MH::ModuleStudio::Frames::IDENTITY.dup
      matrix[0], matrix[5], matrix[10] = x, y, z
      new(matrix)
    end
    def inverse
      rows = 4.times.map { |row| 4.times.map { |column| matrix[column * 4 + row] } + 4.times.map { |column| row == column ? 1.0 : 0.0 } }
      4.times do |column|
        pivot = (column...4).max_by { |row| rows[row][column].abs }
        rows[column], rows[pivot] = rows[pivot], rows[column]
        scale = rows[column][column]
        raise 'Singular' if scale.abs < 1.0e-12
        rows[column].map! { |value| value / scale }
        4.times do |row|
          next if row == column
          factor = rows[row][column]
          8.times { |j| rows[row][j] -= factor * rows[column][j] }
        end
      end
      self.class.new(16.times.map { |index| rows[index % 4][4 + index / 4] })
    end
  end
end

require_relative '../runtime'

class ModuleStudioRuntimeTransformTest < Minitest::Test
  Core = MH::ModuleStudio::Core
  Frames = MH::ModuleStudio::Frames
  Runtime = MH::ModuleStudio::Runtime
  MeshFace = Class.new
  MeshEdge = Class.new
  ChildContainer = Class.new

  def setup
    host = Module.new
    host.const_set(:Face,MeshFace); host.const_set(:Edge,MeshEdge)
    Runtime.const_set(:Sketchup,host)
  end

  def teardown
    Runtime.send(:remove_const,:Sketchup)
  end

  class Entities
    attr_reader :points, :calls
    def initialize(points); @points = points; @calls = 0; end
    def to_a; [MeshFace.new,MeshEdge.new,ChildContainer.new]; end
    def transform_entities(transform, entities)
      raise 'Descendant would be transformed twice' unless entities.length==2 && entities.none? { |entity| entity.is_a?(ChildContainer) }
      @calls += 1
      @points = points.map { |point| Frames.point(transform.matrix, point) }
    end
  end
  class Definition
    attr_reader :entities
    def initialize(entities); @entities = entities; end
    def invalidate_bounds; end
  end
  Leaf = Struct.new(:definition)

  def bindings_for(snapshot, frame)
    inverse = Geom::Transformation.new(frame).inverse.matrix
    snapshot['parts'].to_h do |part|
      points = Frames.corners(part['bounds']).map { |point| Frames.point(inverse, point.map { |v| v / 25.4 }) }
      [part['key'], { entity: Leaf.new(Definition.new(Entities.new(points))), frame: frame }]
    end
  end

  def test_geometry_changes_once_with_nested_scale_rotation_and_mirror
    matrices = [Frames::IDENTITY,
                [0, 2, 0, 0, -3, 0, 0, 0, 0, 0, 0.5, 0, 5, -6, 8, 1],
                [-2, 0, 0, 0, 0, 0.5, 0, 0, 0, 0, -3, 0, 12, 4, -5, 1]]
    matrices.each do |matrix|
      current = StudioFixtures.cabinet(18)
      plan = Core.plan(StudioFixtures.rule, current, 25)
      bindings = bindings_for(current, matrix)
      Runtime.apply_plan(bindings, plan)
      plan['parts'].each do |expected|
        entities = bindings[expected['key']][:entity].definition.entities
        actual = Frames.box(entities.points.map { |point| Frames.point(matrix, point).map { |v| v * 25.4 } })
        2.times { |side| 3.times { |axis| assert_in_delta expected['bounds'][side][axis], actual[side][axis], 0.00001 } }
        assert_equal 1, entities.calls, 'Each changed board must be transformed exactly once'
      end
    end
  end

  def test_no_op_does_not_touch_geometry
    current = StudioFixtures.cabinet(18)
    bindings = bindings_for(current, Frames::IDENTITY)
    Runtime.apply_plan(bindings, Core.plan(StudioFixtures.rule, current, 18))
    assert(bindings.values.all? { |binding| binding[:entity].definition.entities.calls.zero? })
  end

  def test_missing_follower_update_creates_collision_and_is_rejected
    rule = StudioFixtures.rule
    top = rule['parts'].find { |part| part['key'] == 'top' }
    top['coefficients'][0][0]['slope'] = 0
    error = assert_raises(Core::Error) { Core.plan(rule, StudioFixtures.cabinet(18), 25) }
    assert_match 'giao vào', error.message
  end

  def test_combined_parameter_plan_transforms_each_board_once
    data = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'dc_mixed_thickness.json'), encoding: 'UTF-8'))
    rule = Core.learn_module(data)
    plan = Core.plan(rule, data.last, 'ba4ulq2qnw' => 18, 'ikqikbwfw7' => 9)
    matrix = [-2, 0, 0, 0, 0, 0.5, 0, 0, 0, 0, -3, 0, 12, 4, -5, 1]
    bindings = bindings_for(data.last, matrix)
    Runtime.apply_plan(bindings, plan)

    plan['parts'].each do |expected|
      entities = bindings[expected['key']][:entity].definition.entities
      actual = Frames.box(entities.points.map { |point| Frames.point(matrix, point).map { |value| value * 25.4 } })
      2.times { |side| 3.times { |axis| assert_in_delta expected['bounds'][side][axis], actual[side][axis], 0.00001 } }
      assert_equal expected['changed'] ? 1 : 0, entities.calls
    end
  end
end

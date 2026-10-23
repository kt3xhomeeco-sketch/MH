# encoding: UTF-8
# Portable replace lock-fit regression; real replace! runs with host doubles.
require 'minitest/autorun'
require 'minitest/mock'

module Sketchup
  class Group; end unless const_defined?(:Group)
  class << self
    attr_accessor :model unless method_defined?(:model)
    def active_model; @model; end unless method_defined?(:active_model)
  end
end

unless defined?(Geom::Point3d)
  module Geom
    class Point3d
      attr_reader :x, :y, :z
      def initialize(x, y, z)
        @x = x; @y = y; @z = z
      end
      def to_a
        [x, y, z]
      end
    end

    class Bounds
      attr_reader :min, :max
      def initialize(minimum, maximum)
        @min = Point3d.new(*minimum)
        @max = Point3d.new(*maximum)
      end
    end

    class Transformation
      IDENTITY = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1].freeze
      attr_reader :matrix
      def initialize(matrix = IDENTITY)
        @matrix = matrix
      end
      def to_a
        matrix.dup
      end
      def *(other)
        self.class.new(MH::ModuleStudio::Frames.multiply(matrix, other.matrix))
      end
    end
  end
end

if defined?(Geom::Transformation) && !Geom::Transformation.method_defined?(:to_a)
  module Geom
    class Transformation
      def to_a
        matrix.dup
      end
    end
  end
end

require_relative '../library_placement'
require_relative '../assembly_file'

class ModuleStudioReplaceLockedFitTest < Minitest::Test
  S = MH::ModuleStudio
  FakeDefinition = Struct.new(:bounds)

  class FakeEntity
    attr_accessor :definition, :transformation, :name, :parent
    attr_reader :persistent_id
    def initialize(definition, transformation, parent: nil, pid: 1)
      @definition = definition; @transformation = transformation; @parent = parent
      @persistent_id = pid; @name = 'MH QA replace'
    end
    def locked?; false; end
    def get_attribute(*); nil; end
    def attribute_dictionary(*); {}; end
    def delete_attribute(*); end
    def set_attribute(*); end
    def erase!; @erased = true; end
    def erased?; !!@erased; end
  end

  class FakeLibrary
    attr_accessor :old
    attr_reader :build_calls
    def initialize(fresh)
      @fresh = fresh; @build_calls = []
    end
    def imports; @imports ||= Object.new; end
    def resolve_fit(data, placement, **)
      [data, placement]
    end
    def build_instance(_data, transform, entities: nil)
      @build_calls << { 'transform'=>transform, 'entities'=>entities,
                        'old_definition'=>old && old.definition }
      @fresh
    end
  end

  class FakeModel
    attr_reader :active_entities, :selection
    def initialize
      @active_entities = Object.new; @selection = []
    end
  end

  def preview_data
    { 'entry_id'=>'preview', 'fingerprint'=>'preview',
      'snapshot'=>{ 'envelope'=>[[0, 0, 0], [999, 9, 999]],
                    'parts'=>[{ 'key'=>'panel', 'thickness_axis'=>1 }] } }
  end

  def built_definition
    minimum = [-12.7, 50.8, 25.4].map { |value| value / 25.4 }
    maximum = [500, 18, 700].each_with_index.map { |value, axis| minimum[axis] + value / 25.4 }
    FakeDefinition.new(Geom::Bounds.new(minimum, maximum))
  end

  def locked_rule
    { 'constraints'=>[{ 'type'=>'thickness', 'enabled'=>true, 'drive'=>true,
                         'face'=>{ 'part'=>'panel', 'axis'=>1 } }] }
  end

  def unlocked_rule
    { 'constraints'=>[] }
  end

  def measured_mm(entity)
    bounds = entity.definition.bounds
    S::Frames.box(S::Frames.corners([bounds.min.to_a, bounds.max.to_a]).map do |point|
      S::Frames.point(entity.transformation.matrix, point).map { |value| value * 25.4 }
    end)
  end

  def install_and_replace(rule:, target_mm:)
    model = FakeModel.new
    initial_old_definition = FakeDefinition.new(
      Geom::Bounds.new([0, 0, 0], target_mm.map { |value| value / 25.4 })
    )
    old = FakeEntity.new(initial_old_definition, Geom::Transformation.new, parent: model, pid: 777)
    fresh = FakeEntity.new(built_definition, Geom::Transformation.new, parent: model, pid: 778)
    library = FakeLibrary.new(fresh)
    library.old = old
    data = preview_data
    resize_calls = []
    resize = lambda do |root, placement, imports: nil, locked_axes: nil|
      resize_calls << { 'root'=>root, 'placement'=>S::Core.copy_data(placement),
                        'imports'=>imports, 'locked_axes'=>locked_axes }
    end
    Sketchup.model = model
    result = nil
    S::Assembly.stub(:root, old) do
      S::AssemblyContainers.stub(:managed?, false) do
        S::AssemblyParameters.stub(:data, [rule, {}]) do
          S::LibraryPlacement.stub(:resize, resize) do
            result = S::LibraryPlacement.replace!(library, data, { 'root'=>'777' }, [])
          end
        end
      end
    end
    [result, old, fresh, library, initial_old_definition, resize_calls]
  end

  def test_locked_native_span_is_measured_after_identity_build_and_fits_other_axes
    result, old, fresh, library, initial_old_definition, resize_calls = install_and_replace(
      rule: locked_rule, target_mm: [542.249, 21.78, 749]
    )
    assert_same old, result
    assert_equal Geom::Transformation::IDENTITY, library.build_calls.first['transform'].matrix,
      'replacement must be built before the snapshot-fit transform'
    assert_same initial_old_definition, library.build_calls.first['old_definition'],
      'fresh must be staged before the old definition is mutated'
    assert_same fresh.definition, old.definition
    assert fresh.erased?, 'staged instance must be erased after adoption'
    assert_equal 1, resize_calls.length
    placement = resize_calls.first['placement']
    assert S::Core.bounds_close?([[0, 0, 0], [542.249, 18, 749]], placement['bounds'], 0.001),
      'locked Y keeps the actual 18 mm span while X/Z fit the target'
    assert S::Core.bounds_close?([[0, 0, 0], [542.249, 18, 749]], measured_mm(fresh), 0.001),
      'fitted world dimensions keep the locked native Y span'
  end

  def test_unlocked_generic_module_fits_every_target_axis
    _result, _old, fresh, library, initial_old_definition, resize_calls = install_and_replace(
      rule: unlocked_rule, target_mm: [542.249, 21.78, 749]
    )
    assert_equal Geom::Transformation::IDENTITY, library.build_calls.first['transform'].matrix
    assert_same initial_old_definition, library.build_calls.first['old_definition']
    placement = resize_calls.first['placement']
    assert S::Core.bounds_close?([[0, 0, 0], [542.249, 21.78, 749]], placement['bounds'], 0.001),
      'unlocked replacement fits the complete concrete target'
    assert S::Core.bounds_close?([[0, 0, 0], [542.249, 21.78, 749]], measured_mm(fresh), 0.001)
  end
end

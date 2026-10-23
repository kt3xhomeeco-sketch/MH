# encoding: UTF-8
require 'minitest/autorun'
require_relative '../../MH_shared/material_code'
require_relative '../../MH_Registry/connectors/dc_import/materials'

# Load only the color engine; the rest of main.rb registers SketchUp UI.
module Sketchup
  Color = Struct.new(:red, :green, :blue)
end
module MH
  module MaterialApp
    DEBUG = false
    MATERIAL_FOLDER = File.join(__dir__, 'no_skm_files')
  end
end
source = File.read(File.expand_path('../main.rb', __dir__), encoding: 'UTF-8')
engine = source[/    module MaterialCreator\n.*?(?=    # ========== MATERIAL ASSIGNER)/m]
raise 'MaterialCreator not found' unless engine
MH::MaterialApp.module_eval(engine)

class MaterialColorsTest < Minitest::Test
  Creator = MH::MaterialApp::MaterialCreator
  Pipeline = MH::RegistryApp::Connectors::DCImportPipeline
  PREFIX = 'MDFCA'
  TAIL = 'ML.MEL.ML6325'

  module Attributes
    def get_attribute(dict, key, default = nil)
      (@attrs ||= {}).fetch([dict, key], default)
    end

    def set_attribute(dict, key, value)
      (@attrs ||= {})[[dict, key]] = value
    end
  end

  class Material
    include Attributes
    attr_accessor :name, :alpha, :texture
    attr_reader :color, :writes
    def initialize(name, rgb)
      @name, @color, @alpha, @writes = name, Sketchup::Color.new(*rgb), 1.0, 0
    end
    def color=(value)
      @writes += 1
      @color = value
    end
    def valid? = true
  end

  class Materials < Array
    def [](name)
      name.is_a?(String) ? find { |m| m.name == name } : super
    end
    def add(name)
      material = Material.new(name, [255, 255, 255])
      self << material
      material
    end
  end

  class Model
    include Attributes
    attr_reader :materials
    def initialize = @materials = Materials.new
    def active_view = self
    def invalidate; end
  end

  def setup
    Creator.instance_variable_set(:@generated_family_hues, {})
    Creator.instance_variable_set(:@resolved_materials, {})
    @model = Model.new
  end

  def add(thickness, rgb, suffix = '')
    mat = Material.new("#{PREFIX}.#{thickness}.#{TAIL}#{suffix}", rgb)
    @model.materials << mat
    mat
  end

  def lightness(mat)
    rgb = [mat.color.red, mat.color.green, mat.color.blue]
    (rgb.min + rgb.max) / 510.0
  end

  def test_repairs_unmarked_dc_colors_and_mixed_new_colors_in_existing_model
    add(6, [101, 255, 255])
    add(9, [0, 102, 102])
    add(17, [0, 153, 153])
    add(12, [233, 121, 12])
    add(15, [174, 91, 9])
    assert_equal 5, Creator.recolor_generated_materials(@model)
    ordered = @model.materials.sort_by { |m| Creator.color_profile(m.name)[:thickness] }
    ordered.each_cons(2) { |a, b| assert_operator lightness(a), :>, lightness(b) }
    ordered.each { |m| assert_in_delta 180, Creator.hue_from_color(m.color), 0.6 }
  end

  def test_superimp_repairs_existing_material_once_and_cache_does_not_rescan
    mat = add(17, [0, 153, 153])
    assert_same mat, Pipeline.material_for(@model, mat.name)
    assert_in_delta 0.28, lightness(mat), 0.003
    writes = mat.writes
    4.times { assert_same mat, Pipeline.material_for(@model, mat.name) }
    4.times { assert_same mat, Creator.load_material_from_file(@model, mat.name) }
    assert_equal writes, mat.writes
  end

  def test_new_thickness_and_runtime_reset_keep_same_family_hue
    old = add(9, [0, 102, 102])
    Creator.recolor_generated_materials(@model)
    name = "#{PREFIX}.12.#{TAIL}"
    fresh = Pipeline.material_for(@model, name)
    assert_in_delta Creator.hue_from_color(old.color), Creator.hue_from_color(fresh.color), 0.6
    before = @model.materials.map { |m| Creator.color_key(m.color) }
    Creator.recolor_generated_materials(@model)
    assert_equal before, @model.materials.map { |m| Creator.color_key(m.color) }
  end

  def test_imported_material_with_current_version_is_reconciled_to_destination_family
    base = add(9, [0, 102, 102])
    Creator.recolor_generated_materials(@model)
    other = Model.new
    imported = Material.new("#{PREFIX}.12.#{TAIL}", [255, 0, 0])
    other.materials << imported
    Creator.recolor_generated_materials(other)
    @model.materials << imported
    assert_same imported, Pipeline.material_for(@model, imported.name)
    assert_in_delta Creator.hue_from_color(base.color), Creator.hue_from_color(imported.color), 0.6
  end

  def test_thickness_order_and_face_count_variants_including_above_20mm
    [3, 8, 9, 11, 14, 17, 18, 20, 21, 25, 30].each do |t|
      %w[1M 2M 1M-BCT 2M-BCT].each { |s| add(t, [90, 130, 7], ".#{s}") }
    end
    Creator.recolor_generated_materials(@model)
    by_t = @model.materials.group_by { |m| Creator.color_profile(m.name)[:thickness] }
    by_t.sort.each_cons(2) do |(thin, a), (thick, b)|
      assert_operator a.map { |m| lightness(m) }.min, :>, b.map { |m| lightness(m) }.max, "#{thin} / #{thick}"
    end
    by_t.each_value do |members|
      one = members.find { |m| m.name.end_with?('.1M') }
      two = members.find { |m| m.name.end_with?('.2M') }
      assert_operator lightness(one), :>, lightness(two)
    end
  end

  def test_model_hue_is_isolated_and_textures_and_generic_materials_are_preserved
    a = add(17, [0, 153, 153])
    textured = add(9, [220, 0, 0])
    textured.texture = Object.new
    generic = Material.new('Transparent', [255, 255, 255])
    generic.alpha = 0.2
    @model.materials << generic
    Creator.recolor_generated_materials(@model)
    assert_equal [220, 0, 0], [textured.color.red, textured.color.green, textured.color.blue]
    assert_equal 0, generic.writes
    assert_equal 0.2, generic.alpha
    other = Model.new
    b = Material.new(a.name, [255, 0, 0])
    other.materials << b
    Creator.recolor_generated_materials(other)
    assert_in_delta 180, Creator.hue_from_color(a.color), 0.6
    assert_in_delta 0, Creator.hue_from_color(b.color), 0.6
  end
end

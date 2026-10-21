# encoding: UTF-8
require 'minitest/autorun'
require_relative '../connectors/dc_import_pipeline'

class ImportProductOwnershipTest < Minitest::Test
  Pipeline = MH::RegistryApp::Connectors::DCImportPipeline
  class Entity
    attr_reader :attributes
    def initialize
      @attributes = {}
    end
    def valid? = true
    def persistent_id = 42
    def set_attribute(dictionary, key, value)
      @attributes[[dictionary, key]] = value
    end
    def get_attribute(dictionary, key, default = nil)
      @attributes.fetch([dictionary, key], default)
    end
  end

  # Replace SketchUp geometry work, retaining the production import coordinator
  # and metadata writer so the test checks their observable writes and handoff.
  class PipelineHarness
    include Pipeline
    attr_reader :child, :applied_profile, :material_context, :resolved
    def initialize
      @child = Entity.new
    end
    def run(entity, context)
      after_import_dc(entity, context)
    end
    def normalize_profile(profile) = profile.dup
    def selected_profile(context) = context.fetch(:material_profile)
    def manual_mode?(context) = context[:material_source] == 'manual'
    def default_profile?(_profile) = false
    def binding_for(_context, _instance) = { 'param_panel' => 'panel', 'param_back' => 'back' }
    def resolve_product_materials(_entity, profile, context)
      @material_context = context.dup
      @resolved = true
      profile.merge('product_code' => context[:product_code], 'panel_material' => 'MDF.17.6')
    end
    def resolve_dc_naming(*) = raise('Import must not assign SP/module labels')
    def apply_dc_naming(*) = raise('Import must not write naming metadata')
    def write_naming_metadata(entity, naming)
      apply_registry_naming_attrs(entity, naming)
    end
    def apply_profile(_entity, profile)
      @applied_profile = profile.dup
    end
    def profile_label(profile) = profile['profile_name']
  end

  def context(source = 'auto')
    { product_code: 'SP05', material_source: source, material_profile: {
      'profile_id' => 'chosen', 'profile_name' => 'MDF 17.6/8', 'product_code' => 'SP05',
      'material_code' => 'MDF.AC', 'panel_thickness_mm' => 17.6, 'back_thickness_mm' => 8.0
    } }
  end

  def test_import_retains_material_thickness_context_without_stamping_root_or_children
    entity = Entity.new
    harness = PipelineHarness.new
    result = harness.run(entity, context)
    assert result['ok'], result['error']
    assert_equal 'SP05', harness.material_context[:product_code]
    assert_equal 'MDF.17.6', harness.applied_profile['panel_material']
    assert_equal 17.6, harness.applied_profile['panel_thickness_mm']
    assert_equal 8.0, harness.applied_profile['back_thickness_mm']
    assert_equal 'MDF.AC', entity.get_attribute('MH_Registry', 'dc_material_code')
    [entity, harness.child].each do |item|
      refute item.attributes.key?(['MH_Registry', 'dc_product_code'])
      refute item.attributes.key?(['MH_ProductContext', 'position_product_code'])
    end
    assert_empty harness.child.attributes
  end

  def test_generic_naming_writer_cannot_recreate_product_code_on_root_or_child
    harness = PipelineHarness.new
    [Entity.new, harness.child].each do |entity|
      harness.write_naming_metadata(entity, { 'product_code' => 'SP05', 'modul_name' => 'Tủ' })
      refute entity.attributes.key?(['MH_Registry', 'dc_product_code'])
      assert_equal 'Tủ', entity.get_attribute('MH_Registry', 'dc_modul')
    end
  end

  def test_manual_profile_still_applies_without_product_stamping
    entity = Entity.new
    harness = PipelineHarness.new
    assert harness.run(entity, context('manual'))['ok']
    refute harness.resolved
    assert_equal 17.6, harness.applied_profile['panel_thickness_mm']
    refute entity.attributes.key?(['MH_Registry', 'dc_product_code'])
  end

  def test_existing_product_metadata_is_not_overwritten_by_import
    entity = Entity.new
    entity.set_attribute('MH_Registry', 'dc_product_code', 'SP04')
    harness = PipelineHarness.new
    assert harness.run(entity, context)['ok']
    assert_equal 'SP04', entity.get_attribute('MH_Registry', 'dc_product_code')
    assert_equal 'SP05', harness.applied_profile['product_code']
  end

  def test_superimp_callback_passes_chosen_profile_without_stamping
    # Evaluate the actual callback alone; loading the interactive tool would
    # require SketchUp's UI. AST boundaries avoid maintaining a copied method.
    source_path = File.expand_path('../../MH_Superimp/src/main.rb', __dir__)
    find_callback = lambda do |node|
      next nil unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)
      next node if node.type == :DEFN && node.children[0] == :after_import_dc
      node.children.lazy.map { |child| find_callback.call(child) }.find(&:itself)
    end
    method = find_callback.call(RubyVM::AbstractSyntaxTree.parse_file(source_path))
    refute_nil method
    callback_source = File.readlines(source_path, encoding: 'UTF-8')[(method.first_lineno - 1)..(method.last_lineno - 1)].join
    klass = Class.new do
      def registry_context(allow_slow_scan:) = { product_code: 'SP05' }
      def remember_imported_product_context(*) = raise('Import must not stamp product ownership')
      def configure(profile) = (@material_profile = profile)
    end
    klass.class_eval(callback_source, source_path, method.first_lineno)
    MH.const_set(:Superimp, Module.new) unless MH.const_defined?(:Superimp)
    received = []
    MH::Superimp.define_singleton_method(:notify_imported_dc) { |entity, supplied| received << [entity, supplied] }
    profile = context[:material_profile]
    entity = Entity.new
    tool = klass.new
    tool.configure(profile)
    tool.after_import_dc(entity)
    assert_equal [[entity, { product_code: 'SP05', material_profile: profile }]], received
    assert_empty entity.attributes
  end
end

# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../settings'

module Sketchup
  class << self
    attr_accessor :model, :preferences

    def active_model
      model
    end

    def read_default(section, key, fallback)
      preferences.fetch([section, key], fallback)
    end

    def write_default(section, key, value)
      preferences[[section, key]] = value
    end
  end
end

class SettingsModel
  def initialize
    @values = {}
  end

  def get_attribute(dict, key, fallback = nil)
    @values.fetch([dict, key], fallback)
  end

  def set_attribute(dict, key, value)
    @values[[dict, key]] = value
  end

  def start_operation(*)
    true
  end

  def commit_operation
    true
  end

  def abort_operation
    true
  end
end

class SettingsTest < Minitest::Test
  def setup
    Sketchup.model = SettingsModel.new
    Sketchup.preferences = {}
  end

  def test_relocation_preserves_sources_and_resolves_old_model_links
    Dir.mktmpdir('mh-cad2module-move-') do |base|
      old = File.join(base, 'old')
      destination = File.join(base, 'new')
      settings = MH::CAD2Module::Settings
      settings.save('library' => old, 'sources' => ['E:/project/source.dwg'])
      FileUtils.mkdir_p(File.join(old, 'sources'))
      File.binwrite(File.join(old, 'sources', 'raw.dwg'), "CAD\x00bytes")
      settings.relocate(destination)
      assert_equal "CAD\x00bytes", File.binread(File.join(destination, 'sources', 'raw.dwg'))
      assert File.file?(File.join(old, 'sources', 'raw.dwg'))
      assert_equal File.realpath(destination), settings.library('library' => old)
      assert_equal File.join(File.realpath(destination), 'sources', 'raw.dwg'), settings.resolve_library(File.join(old, 'sources', 'raw.dwg'))
      assert_equal ['E:/project/source.dwg'], settings.read['sources']
      assert_equal File.expand_path(destination), settings.read['library']
    end
  end

  def test_build_stages_default_to_plan_and_persist_per_model_and_next_session
    settings = MH::CAD2Module::Settings
    assert_equal true, settings.read['build_plan']
    assert_equal false, settings.read['build_elevation']
    Dir.mktmpdir do |root|
      settings.save('library' => root, 'build_plan' => true, 'build_elevation' => true)
      assert_equal true, settings.read['build_elevation']
      Sketchup.model = SettingsModel.new
      assert_equal true, settings.read['build_elevation']
      settings.save('build_elevation' => false)
      assert_equal false, settings.read['build_elevation']
    end
  end

  def test_conflict_does_not_overwrite_destination_or_settings
    Dir.mktmpdir('mh-cad2module-conflict-') do |base|
      old = File.join(base, 'old')
      destination = File.join(base, 'new')
      settings = MH::CAD2Module::Settings
      settings.save('library' => old)
      File.write(File.join(old, 'event.json'), 'old')
      FileUtils.mkdir_p(destination)
      File.write(File.join(destination, 'event.json'), 'different')
      assert_raises(ArgumentError) { settings.relocate(destination) }
      assert_equal 'different', File.read(File.join(destination, 'event.json'))
      assert_equal old, settings.read['library']
    end
  end

  def test_auxiliary_creation_defaults_on_and_remembers_off_without_changing_stages
    settings = MH::CAD2Module::Settings
    assert_equal true, settings.read['build_auxiliary']
    Dir.mktmpdir do |root|
      original = Sketchup.model
      settings.save('library' => root, 'build_auxiliary' => false)
      assert_equal false, settings.read['build_auxiliary']
      Sketchup.model = SettingsModel.new
      assert_equal false, settings.read['build_auxiliary']
      settings.save('build_auxiliary' => true)
      assert_equal true, settings.read['build_auxiliary']
      assert_equal false, settings.read(original)['build_auxiliary']
      assert_equal true, settings.read['build_plan']
      assert_equal false, settings.read['build_elevation']
    end
  end

  def test_plan_reference_defaults_on_and_persists_for_next_session
    settings = MH::CAD2Module::Settings
    assert_equal true, settings.read['import_plan_reference']
    Dir.mktmpdir do |root|
      settings.save('library' => root, 'import_plan_reference' => false)
      assert_equal false, settings.read['import_plan_reference']
      Sketchup.model = SettingsModel.new
      assert_equal false, settings.read['import_plan_reference']
      assert_equal true, settings.read['build_plan']
    end
  end

  def test_local_ai_default_off_and_toggle_persists
    settings = MH::CAD2Module::Settings
    assert_equal false, settings.read['ai_enabled']
    Dir.mktmpdir do |root|
      settings.save('library' => root, 'ai_enabled' => true)
      assert_equal true, settings.read['ai_enabled']
      Sketchup.model = SettingsModel.new
      assert_equal true, settings.read['ai_enabled']
      settings.save('ai_enabled' => false)
      assert_equal false, settings.read['ai_enabled']
    end
  end
end

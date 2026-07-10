# encoding: UTF-8

require 'sketchup'
require 'json'
require File.join(Sketchup.find_support_file('Plugins'), 'MH_shared.rb')

module MH
  module Panel
    ROOT = File.expand_path('..', __dir__).freeze
    SRC = __dir__.freeze
    DEBUG = false unless const_defined?(:DEBUG, false)

    module_function

    def dbg(message)
      puts message if DEBUG
    end

    def require_core
      %w[
        geo_adapter
        base
        model
        settings
        view
        abf
        isolate
        group
        material
        board
        purge
        preset
      ].each { |name| require_relative "core/#{name}" }
      require_relative 'tools/taovan'
      require_relative 'tools/taocanh'
      require_relative 'tools/catvan'
    end

    def reload
      original_verbose = $VERBOSE
      $VERBOSE = nil
      files = Dir.glob(File.join(SRC, '**/*.rb')).sort
      files.each { |file| load file }
      dbg("MH::Panel reloaded #{files.size} file(s)")
      true
    ensure
      $VERBOSE = original_verbose
    end

    def activate_tao_van
      Sketchup.active_model.select_tool(MH::Panel::TaoVan.new)
    end

    def activate_tao_canh
      Sketchup.active_model.select_tool(MH::Panel::TaoCanh.new)
    end

    def activate_cat_van
      Sketchup.active_model.select_tool(MH::Panel::CatVan.new)
    end

    def open_settings(tab = 'cai_dat')
      MH::Panel::Settings.open_settings(tab)
    end
  end
end

MH::Panel.require_core

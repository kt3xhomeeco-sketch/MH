# encoding: utf-8
require 'sketchup.rb'
require 'json'
require File.join(File.dirname(__dir__), 'MH_shared.rb')
raise "MH_PK_Addon requires MH_shared" unless defined?(MH::Shared)

module MH_PK_Addon
  PLUGIN_NAME = 'MH PK Addon'.freeze
  VERSION = '1.0.0'.freeze
  ROOT_DIR = File.dirname(__FILE__).freeze
  DEBUG = false unless const_defined?(:DEBUG, false)

  def self.dbg(message)
    puts message if DEBUG
  end

  Sketchup.require File.join(ROOT_DIR, 'core')
  Sketchup.require File.join(ROOT_DIR, 'length_pk')
  Sketchup.require File.join(ROOT_DIR, 'traceability')
  Sketchup.require File.join(ROOT_DIR, 'picker')
  Sketchup.require File.join(ROOT_DIR, 'hud')
  Sketchup.require File.join(ROOT_DIR, 'hud_settings')
  Sketchup.require File.join(ROOT_DIR, 'leaders')
  Sketchup.require File.join(ROOT_DIR, 'tool')
  Sketchup.require File.join(ROOT_DIR, 'dialog')

  def self.register_ui
    return if @ui_registered

    cmd = UI::Command.new('MH PK') { show_dialog }
    cmd.tooltip = 'MH PK Addon'
    cmd.status_bar_text = 'Tao va add phu kien vao object dang chon'
    icon_path = File.join(ROOT_DIR, 'icon.svg')
    icon_path = File.join(ROOT_DIR, 'icon.png') unless File.exist?(icon_path)
    if File.exist?(icon_path)
      cmd.small_icon = icon_path
      cmd.large_icon = icon_path
    end

    cmd_hud = UI::Command.new('MH PK HUD') { activate_hud_tool }
    cmd_hud.tooltip = 'MH PK HUD — add PK truc tiep trong viewport'
    cmd_hud.status_bar_text = 'Tool tuong tac: chon PK tu bang, click vao mat de add'
    if File.exist?(icon_path)
      cmd_hud.small_icon = icon_path
      cmd_hud.large_icon = icon_path
    end

    toolbar = UI::Toolbar.new('MH PK Addon')
    toolbar.add_item(cmd)
    toolbar.add_item(cmd_hud)
    toolbar.restore

    @ui_registered = true
  end

  unless file_loaded?(__FILE__)
    register_ui
    file_loaded(__FILE__)
  end
end

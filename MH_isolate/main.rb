# encoding: UTF-8

require 'sketchup.rb'
require_relative 'state'
require_relative 'observers'
require_relative 'engine'

module MH
  module Isolate
    unless file_loaded?(__FILE__)
      isolate_command = UI::Command.new('MH Isolate Selected') do
        Engine.isolate
      end
      isolate_command.tooltip = 'MH Isolate Selected Objects'
      isolate_command.status_bar_text = 'Hide visible sibling Groups/Components without traversing nested geometry.'
      isolate_command.set_validation_proc do
        model = Sketchup.active_model
        if model && model.selection.any? { |entity| Engine.send(:container?, entity) }
          MF_ENABLED
        else
          MF_GRAYED
        end
      end

      unisolate_command = UI::Command.new('MH Unisolate') do
        Engine.unisolate
      end
      unisolate_command.tooltip = 'MH Unisolate Objects'
      unisolate_command.status_bar_text = 'Restore objects and their original Tags.'
      unisolate_command.set_validation_proc do
        State.active?(Sketchup.active_model) ? MF_ENABLED : MF_GRAYED
      end

      toggle_command = UI::Command.new('MH Toggle Isolate/Unisolate') do
        Engine.toggle
      end
      toggle_command.tooltip = 'MH Toggle Isolate/Unisolate'
      toggle_command.status_bar_text = 'Isolate selected objects or restore the active isolation.'
      toggle_command.set_validation_proc { MF_ENABLED }
      icon_path = File.join(__dir__, 'icons', 'isolate.svg')
      if File.file?(icon_path)
        toggle_command.small_icon = icon_path
        toggle_command.large_icon = icon_path
      end

      menu = UI.menu('Extensions').add_submenu('MH Isolate')
      menu.add_item(toggle_command)
      menu.add_item(isolate_command)
      menu.add_item(unisolate_command)
      menu.add_separator
      loose_item = menu.add_item('Include Loose Edge/Face (Slower)') do
        Engine.toggle_include_loose_geometry
      end
      menu.set_validation_proc(loose_item) do
        Engine.include_loose_geometry? ? MF_CHECKED : MF_UNCHECKED
      end
      zoom_item = menu.add_item('Zoom to Isolated Objects') do
        Engine.toggle_zoom_on_isolate
      end
      menu.set_validation_proc(zoom_item) do
        Engine.zoom_on_isolate? ? MF_CHECKED : MF_UNCHECKED
      end
      menu.add_item('Force Restore / Cleanup') do
        Engine.force_restore
      end

      toolbar = UI::Toolbar.new('MH Isolate')
      toolbar.add_item(toggle_command)
      toolbar.restore

      # Keep Ruby references alive for the full SketchUp session. This also
      # prevents shortcut callbacks from depending on local-variable lifetime.
      @commands = {
        isolate: isolate_command,
        unisolate: unisolate_command,
        toggle: toggle_command
      }
      @menu = menu
      @toolbar = toolbar

      Observers.install
      State.sync(Sketchup.active_model)
      file_loaded(__FILE__)
    end
  end
end

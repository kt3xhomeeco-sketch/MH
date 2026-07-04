# encoding: UTF-8

module SmartScaleLab
  Sketchup.require File.join(PATH, 'lab_state')
  Sketchup.require File.join(PATH, 'lab_box_model')
  Sketchup.require File.join(PATH, 'lab_planes')
  Sketchup.require File.join(PATH, 'vendor', 'scale_core')
  Sketchup.require File.join(PATH, 'vendor', 'stretch_core')
  Sketchup.require File.join(PATH, 'vendor', 'vector_font')
  Sketchup.require File.join(PATH, 'lab_dc_lengths')
  Sketchup.require File.join(PATH, 'lab_stretch_pro')
  Sketchup.require File.join(PATH, 'lab_stretch_adapter')
  Sketchup.require File.join(PATH, 'lab_dimensions')
  Sketchup.require File.join(PATH, 'lab_hit_test')
  Sketchup.require File.join(PATH, 'lab_overlay')
  Sketchup.require File.join(PATH, 'lab_box_tool')

  module_function

  def activate_tool
    Sketchup.active_model.select_tool(BoxTool.new)
  end

  unless file_loaded?(__FILE__)
    cmd = UI::Command.new('SmartScale Lab Multi-Plane') { activate_tool }
    cmd.tooltip = 'SmartScale Lab -- Multi-Plane'
    cmd.status_bar_text = 'Mở SmartScale Lab multi-plane box stretch.'

    menu = UI.menu('Plugins').add_submenu('SmartScale Lab')
    menu.add_item(cmd)

    toolbar = UI::Toolbar.new('SmartScale Lab')
    toolbar.add_item(cmd)
    toolbar.restore

    file_loaded(__FILE__)
  end
end

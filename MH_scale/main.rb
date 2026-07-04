# encoding: UTF-8

module MH::Scale
  RUNTIME_FILES = %w[
    lab_state
    lab_box_model
    lab_planes
    lab_dc_lengths
    lab_stretch_pro
    mh_engine_legacy/plane_vertex_selector
    mh_engine_legacy/stretch_operation
    lab_stretch_adapter
    lab_dimensions
    lab_hit_test
    lab_overlay
    lab_box_tool
  ].freeze

  Sketchup.require File.join(PATH, 'vendor', 'scale_core')
  Sketchup.require File.join(PATH, 'vendor', 'stretch_core')
  Sketchup.require File.join(PATH, 'vendor', 'vector_font')

  module_function

  def load_runtime
    RUNTIME_FILES.each do |name|
      load File.join(PATH, "#{name}.rb")
    end
  end

  load_runtime


  def activate_tool
    Sketchup.active_model.select_tool(BoxTool.new)
  end

  unless file_loaded?(__FILE__)
    cmd = UI::Command.new('MH Scale Multi-Plane') { activate_tool }
    cmd.tooltip = 'MH Scale -- Multi-Plane'
    cmd.status_bar_text = 'Mở MH Scale multi-plane box stretch.'

    menu = UI.menu('Plugins').add_submenu('MH Scale')
    menu.add_item(cmd)

    toolbar = UI::Toolbar.new('MH Scale')
    toolbar.add_item(cmd)
    toolbar.restore

    file_loaded(__FILE__)
  end
end


# encoding: UTF-8

module MH::Stretch
  RUNTIME_FILES = %w[
    lab_state
    lab_box_model
    lab_planes
    vendor/vector_font
    mh_engine_backup/plane_vertex_selector
    mh_engine_backup/stretch_operation
    mh_engine_backup/between_planes_selector
    mh_engine_backup/between_planes_operation
    lab_ui_adapter
    lab_between_planes_adapter
    lab_dimensions
    lab_hit_test
    lab_overlay
    lab_box_tool
  ].freeze

  module_function

  def load_runtime
    RUNTIME_FILES.each { |name| load File.join(PATH, "#{name}.rb") }
  end

  load_runtime

  ICON_PATH = File.join(PATH, 'icons', 'mh_stretch.svg').freeze


  def activate_tool
    Sketchup.active_model.select_tool(BoxTool.new)
  end

  unless file_loaded?(__FILE__)
    cmd = UI::Command.new('MH Stretch Multi-Plane') { activate_tool }
    cmd.tooltip = 'MH Stretch -- Multi-Plane'
    cmd.status_bar_text = 'Mở MH Stretch grip/plane/dimension stretch.'
    if File.exist?(ICON_PATH)
      cmd.small_icon = ICON_PATH
      cmd.large_icon = ICON_PATH
    end

    menu = UI.menu('Plugins').add_submenu('MH Stretch')
    menu.add_item(cmd)

    toolbar = UI::Toolbar.new('MH Stretch')
    toolbar.add_item(cmd)
    toolbar.restore

    file_loaded(__FILE__)
  end
end




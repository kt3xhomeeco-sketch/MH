require 'sketchup.rb'
require 'extensions.rb'

module MH
  module MaterialApp
    unless file_loaded?(__FILE__)
      ex = SketchupExtension.new('MH Material Assign', 'MH_Material_Assign/main')
      ex.description = 'Assign materials from Excel to SketchUp Groups/Components.'
      ex.version     = '1.0.0'
      ex.copyright   = '© 2026'
      ex.creator     = 'MH'
      Sketchup.register_extension(ex, true)
      
      # Add menu item under Extensions
      menu = UI.menu('Extensions').add_submenu('MH Material')
      menu.add_item('Run Material Assign') {
        unless MH::MaterialApp.respond_to?(:run_agent)
          require File.join(__dir__, 'MH_Material_Assign', 'main')
        end
        MH::MaterialApp.run_agent
      }
      
      file_loaded(__FILE__)
    end
  end
end

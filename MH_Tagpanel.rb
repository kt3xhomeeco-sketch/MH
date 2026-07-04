
require "sketchup.rb"
require "extensions.rb"

module MH
  module Tagpanel
    unless file_loaded?(__FILE__)
      ex = SketchupExtension.new("MH Tagpanel", "MH_Tagpanel/main")
      ex.description = "MH Tagpanel – Tag toggle panel with per-tag commands"
      ex.version     = "1.0.0"
      ex.creator     = "MH"
      Sketchup.register_extension(ex, true)
      file_loaded(__FILE__)
    end
  end
end

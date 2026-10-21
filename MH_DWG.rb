# frozen_string_literal: true

# Loader for MH_DWG
require 'sketchup'
require 'extensions'

module MH
  # Registers the CAD clipboard extension; implementation loads through main.rb.
  module DWG
    unless file_loaded?(__FILE__)
      ex = SketchupExtension.new('MH DWG Clipboard Import', 'MH_DWG/main')
      ex.version     = '1.2.12'
      ex.description = 'Paste CAD (DWG) from clipboard with native mouse-follow placement.'
      Sketchup.register_extension(ex, true)
      file_loaded(__FILE__)
    end
  end
end

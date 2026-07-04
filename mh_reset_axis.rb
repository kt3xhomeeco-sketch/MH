# encoding: UTF-8

require 'sketchup.rb'
require 'extensions.rb'

module MH
  module ResetAxis
    EXTENSION = SketchupExtension.new(
      'MH Reset Axis',
      File.join('mh_reset_axis', 'main')
    )

    EXTENSION.creator = 'MH'
    EXTENSION.description = 'Reset trục Group/Component theo kích thước và phương đứng.'
    EXTENSION.version = '1.0.9'
    EXTENSION.copyright = '2026 MH'

    Sketchup.register_extension(EXTENSION, true)
  end
end

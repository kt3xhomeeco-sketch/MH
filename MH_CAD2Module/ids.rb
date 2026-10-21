# frozen_string_literal: true

module MH
  module CAD2Module
    # Local file identifiers, not authentication tokens; avoid loading OpenSSL in SketchUp.
    module Ids
      module_function

      def hex(bytes = 16)
        Random.bytes(bytes).unpack1('H*')
      end

      def uuid
        text = hex(16)
        [text[0, 8], text[8, 4], text[12, 4], text[16, 4], text[20, 12]].join('-')
      end
    end
  end
end

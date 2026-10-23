# encoding: UTF-8

module MH
  module ModuleStudio
    # Stable area prefixes for user-visible errors. A message shown in the panel
    # starts with e.g. "[MH-LIB] ..." so it maps to one section of ERROR_MAP.md
    # without a Ruby Console stack trace. Codes are added at the UI boundary, so
    # existing raise sites do not need to change.
    module ErrorCodes
      extend self

      AREAS={
        'parametric'=>'MH-PAR',
        'rule'=>'MH-PAR',
        'assembly'=>'MH-ASM',
        'library'=>'MH-LIB',
        'scale'=>'MH-SCL',
        'options'=>'MH-UPD',
        'update'=>'MH-UPD',
        'redraw'=>'MH-UPD',
        'import'=>'MH-UPD'
      }.freeze
      DEFAULT='MH-RUN'
      TAGGED=/\A\[MH-[A-Z]{3}\]/.freeze

      def area_for(action)
        text=action.to_s.downcase
        AREAS.each { |key,code| return code if text.include?(key) }
        DEFAULT
      end

      def tag(code,message)
        text=message.to_s
        return text if text.match?(TAGGED)
        "[#{code}] #{text}"
      end

      def for_action(action,message)
        tag(area_for(action),message)
      end
    end
  end
end

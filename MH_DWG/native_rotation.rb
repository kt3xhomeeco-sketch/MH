# frozen_string_literal: true

module MH
  # Native rotation retains its timer, key handling and preview refresh policy.
  module DWG
    # Binds Windows functions without hooks, cursor warps or simulated clicks.
    class WindowsRotationKeys
      DWG.load_tool_helpers(self, WindowsPreviewRefresh)

      def initialize
        require 'fiddle'
        @dll = Fiddle.dlopen('user32.dll')
        bind_keyboard_api
        bind_window_api
        bind_cursor_api
        allocate_windows_buffers
      end

      def focused?
        window = @foreground.call
        return false if window.to_i.zero?

        @pid_buffer[0, 4] = [0].pack('L<')
        @window_pid.call(window, @pid_buffer)
        @pid_buffer[0, 4].unpack1('L<') == Process.pid && @window_owner.call(window, 4).to_i.zero?
      end

      def snapshot
        { z: down?(0x11), y: down?(0x10), x: down?(0x12),
          mouse: [0x01, 0x02, 0x04].any? { |key| down?(key) } }
      end

      private

      def user32_function(name, arguments, result)
        Fiddle::Function.new(@dll[name], arguments, result)
      end

      def bind_keyboard_api
        @key_state = user32_function('GetAsyncKeyState', [Fiddle::TYPE_INT], Fiddle::TYPE_SHORT)
        @foreground = user32_function('GetForegroundWindow', [], Fiddle::TYPE_VOIDP)
      end

      def bind_window_api
        pointers = [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP]
        window_integer = [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT]
        @window_pid = user32_function('GetWindowThreadProcessId', pointers, Fiddle::TYPE_LONG)
        @window_owner = user32_function('GetWindow', window_integer, Fiddle::TYPE_VOIDP)
        @window_root = user32_function('GetAncestor', window_integer, Fiddle::TYPE_VOIDP)
      end

      def bind_cursor_api
        @cursor_pos = user32_function('GetCursorPos', [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
        @mouse_capture = user32_function('GetCapture', [], Fiddle::TYPE_VOIDP)
        @window_at_point = user32_function('WindowFromPoint', [Fiddle::TYPE_LONG_LONG], Fiddle::TYPE_VOIDP)
        @screen_to_client = user32_function('ScreenToClient', [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
        @client_rect = user32_function('GetClientRect', [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
        arguments = [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_UINTPTR_T, Fiddle::TYPE_INTPTR_T]
        @post_message = user32_function('PostMessageW', arguments, Fiddle::TYPE_INT)
      end

      def allocate_windows_buffers
        @pid_buffer = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
        @point_buffer = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
        @rect_buffer = Fiddle::Pointer.malloc(16, Fiddle::RUBY_FREE)
      end

      def down?(key)
        @key_state.call(key).anybits?(0x8000)
      end
    end

    def self.rotation_key_source
      return nil unless Sketchup.platform == :platform_win

      WindowsRotationKeys.new
    rescue StandardError => e
      log_event('paste.rotation_keys_unavailable', error: "#{e.class}: #{e.message}")
      nil
    end

    def self.start_native_rotation(model, definition)
      keys = rotation_key_source
      return unless keys

      @native_rotation = NativeRotationSession.new(model, definition, keys)
      @native_rotation.start!
    rescue StandardError => e
      @native_rotation&.cancel!
      @native_rotation = nil
      log_event('paste.native_rotation_start_error',
                error: "#{e.class}: #{e.message}", backtrace: e.backtrace&.first(6))
      UI.messagebox("Không bật được phím xoay CAD; vẫn có thể click đặt và gán Tag MH_DWG.\n#{e.message}")
    end

    # Controls native placement using read-only input polling and shared orientations.
    class NativeRotationSession
      DWG.load_tool_helpers(self, NativeRotationInput, NativeRotationState)

      NATIVE_PLACEMENT_ID = 21_013
      CAMERA_IDS = [10_508, 10_525, 10_509].freeze

      def initialize(model, source, keys)
        @model = model
        @source = source
        @keys = keys
        @entities = model.active_entities
        @active_path = model.active_path&.dup
        initialize_rotation_state(source)
      end

      def start!
        @active = true
        @last_keys = @keys.snapshot if @keys.focused?
        @ignore_until_released = @last_keys&.values_at(:x, :y, :z, :mouse)&.any?
        @timer = UI.start_timer(0.04, true) { tick }
        show_prompt
      end

      def cancel!
        @active = false
        @preview_refresh_pending = false
        UI.stop_timer(@timer) if @timer
        @timer = nil
      end

      def tick
        return unless @active
        return cancel! unless context_valid?
        return unless native_rotation_ready?

        process_rotation_keys(@keys.snapshot)
      rescue StandardError => e
        cancel!
        DWG.log_event('paste.native_rotation_error', error: "#{e.class}: #{e.message}",
                                                     backtrace: e.backtrace&.first(6))
        UI.messagebox("Không xoay được CAD: #{e.message}")
      end

      def rotate!(axis)
        return unless @active && context_valid? && native_placement_active?

        @model.select_tool(nil)
        return cancel! unless context_valid?
        return cancel! if native_instance_placed?

        cancel_rotation_tag_callback
        prepare_orientations unless @orientations
        restart_rotated_placement(axis)
      end

      private

      def native_instance_placed?
        @current_definition.instances.any? { |instance| instance.valid? && instance.parent == @entities.parent }
      end

      def restart_rotated_placement(axis)
        turns = advanced_turns(axis)
        definition = @orientations.fetch(turns)
        DWG.start_native_placement(@model, definition)
        set_rotated_definition(definition, turns)
        refresh_immediately_if_ready
        log_native_rotation(axis, definition)
        show_prompt
      end

      def refresh_immediately_if_ready
        return unless native_placement_active? && @keys.focused? && @keys.snapshot.values.none?

        refresh_preview_if_pending
      end

      def log_native_rotation(axis, definition)
        DWG.log_event('paste.native_rotated', axis: axis, degrees: @turns.map { |turn| turn * 90 },
                                              definition: definition.name)
      end

      def refresh_preview_if_pending
        return unless @preview_refresh_pending

        @preview_refresh_pending = false
        queued = @keys.refresh_placement_preview
        DWG.log_event('paste.native_preview_refresh_queued', queued: queued)
      rescue StandardError => e
        DWG.log_event('paste.native_preview_refresh_error', error: "#{e.class}: #{e.message}")
      end

      def native_placement_active?
        [NATIVE_PLACEMENT_ID, 21_126].include?(@model.tools.active_tool_id) &&
          @model.tools.active_tool_name.to_s.match?(/component|paste/i)
      end

      def context_valid?
        @model.valid? && Sketchup.active_model == @model && @source.valid? &&
          @current_definition.valid? && @model.active_entities == @entities && @model.active_path == @active_path
      end

      def show_prompt
        Sketchup.set_status_text('Click đặt | Bấm-thả Ctrl: Z +90° | Shift: Y +90° | Alt: X +90° | Esc hủy', SB_PROMPT)
      end

      def prepare_orientations
        @orientations, count = NativeOrientationBuilder.new(@model, @source).build
        DWG.log_event('paste.native_orientations_ready', unique_directions: count)
      end
    end
  end
end

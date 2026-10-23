# frozen_string_literal: true

module MH
  module DWG
    # Validates the existing Windows target and queues the same-position mouse message.
    module WindowsPreviewRefresh
      def refresh_placement_preview
        return false unless preview_refresh_available?

        foreground = @foreground.call
        window = preview_target_window
        return false unless preview_window_owned?(window, foreground)

        point = preview_client_point(window)
        return false unless point
        return false unless @foreground.call.to_i == foreground.to_i

        !post_preview_move(window, point).zero?
      end

      private

      def preview_refresh_available?
        focused? && snapshot.values.none? && !@cursor_pos.call(@point_buffer).zero?
      end

      def preview_target_window
        window = @mouse_capture.call
        return window unless window.to_i.zero?

        @window_at_point.call(@point_buffer[0, 8].unpack1('q<'))
      end

      def preview_window_owned?(window, foreground)
        return false if window.to_i.zero? || @window_root.call(window, 2).to_i != foreground.to_i
        return false if @window_pid.call(window, @pid_buffer).zero?

        @pid_buffer[0, 4].unpack1('L<') == Process.pid
      end

      def preview_client_point(window)
        return nil if @screen_to_client.call(window, @point_buffer).zero?
        return nil if @client_rect.call(window, @rect_buffer).zero?

        point = @point_buffer[0, 8].unpack('l<l<')
        point if valid_client_point?(*point)
      end

      def valid_client_point?(x, y)
        left, top, right, bottom = @rect_buffer[0, 16].unpack('l<l<l<l<')
        x >= left && x < right && y >= top && y < bottom &&
          [x, y].all? { |value| value.between?(-32_768, 32_767) }
      end

      def post_preview_move(window, point)
        x, y = point
        position = (x & 0xffff) | ((y & 0xffff) << 16)
        @post_message.call(window, 0x0200, 0, position)
      end
    end

    # Retains native activation waiting, focus resets and modifier release priority.
    module NativeRotationInput
      private

      def native_rotation_ready?
        tool_id = @model.tools.active_tool_id
        unless native_placement_active?
          handle_inactive_native_tool(tool_id)
          return false
        end
        @seen_native = true
        rotation_focused?
      end

      def handle_inactive_native_tool(tool_id)
        @last_keys = nil
        unless @seen_native
          @startup_ticks += 1
          cancel! if @startup_ticks >= 50
          return
        end
        return if NativeRotationSession::CAMERA_IDS.include?(tool_id)

        cancel!
      end

      def rotation_focused?
        return true if @keys.focused?

        @last_keys = nil
        false
      end

      def process_rotation_keys(current)
        previous = @last_keys
        @last_keys = current
        refresh_preview_if_pending unless keys_held?(current)
        return unless rotation_keys_ready?(current, previous)
        return if current[:mouse] || current.values_at(:x, :y, :z).any?

        axis = released_rotation_axis(current, previous)
        rotate!(axis) if axis
      end

      def released_rotation_axis(current, previous)
        %i[z y x].find { |name| previous[name] && !current[name] }
      end

      def cancel_rotation_tag_callback
        DWG.instance_variable_get(:@native_tagger)&.cancel!
      end

      def rotation_keys_ready?(current, previous)
        unless previous
          @ignore_until_released = keys_held?(current)
          return false
        end
        if @ignore_until_released
          @ignore_until_released = keys_held?(current)
          return false
        end
        true
      end

      def keys_held?(states)
        states.values_at(:x, :y, :z, :mouse).any?
      end
    end

    # Holds the current definition, orientation and native activation markers.
    module NativeRotationState
      private

      def initialize_rotation_state(source)
        @current_definition = source
        @turns = [0, 0, 0]
        @orientations = @timer = @last_keys = nil
        @active = @seen_native = @preview_refresh_pending = false
        @startup_ticks = 0
      end

      def advanced_turns(axis)
        index = { x: 0, y: 1, z: 2 }.fetch(axis)
        turns = @turns.dup
        turns[index] = (turns[index] + 1) % 4
        turns
      end

      def set_rotated_definition(definition, turns)
        @current_definition = definition
        @turns = turns
        @seen_native = false
        @startup_ticks = 0
        @preview_refresh_pending = true
      end
    end

    # Builds shared wrappers in the original X/Y/Z iteration and Z*Y*X order.
    class NativeOrientationBuilder
      def initialize(model, source)
        @model = model
        @source = source
      end

      def build
        ensure_native_preview_exited!
        raise 'Không mở được operation chuẩn bị hướng CAD.' unless @model.start_operation('Hướng Đặt CAD', true)

        operation_open = true
        result = build_orthogonal_directions
        @model.commit_operation
        operation_open = false
        result
      rescue StandardError
        @model.abort_operation if operation_open
        raise
      end

      private

      def ensure_native_preview_exited!
        return if @model.tools.active_tool.nil? && [0, 21_022].include?(@model.tools.active_tool_id)

        raise 'Công cụ đặt CAD chưa thoát.'
      end

      def build_orthogonal_directions
        by_direction = { orientation_signature(IDENTITY) => @source }
        orientations = {}
        [0, 1, 2, 3].repeated_permutation(3).each do |turns|
          rotation = orientation_transform(turns)
          signature = orientation_signature(rotation)
          by_direction[signature] ||= create_orientation(turns, rotation)
          orientations[turns] = by_direction[signature]
        end
        [orientations, by_direction.length]
      end

      def orientation_transform(turns)
        x, y, z = turns
        quarter_turn_rotation(Z_AXIS, z) * quarter_turn_rotation(Y_AXIS, y) * quarter_turn_rotation(X_AXIS, x)
      end

      def quarter_turn_rotation(axis, turns)
        Geom::Transformation.rotation(ORIGIN, axis, (turns * 90).degrees)
      end

      def orientation_signature(rotation)
        rotation.to_a.map { |value| value.to_f.round(6) }
      end

      def create_orientation(turns, rotation)
        degrees = turns.map { |value| value * 90 }.join(',')
        definition = @model.definitions.add("#{@source.name} [MH #{degrees}]")
        child = definition.entities.add_instance(@source, rotation)
        child.layer = @model.layers[0] if @model.layers[0]
        definition
      end
    end
  end
end

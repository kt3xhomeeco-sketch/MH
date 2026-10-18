# encoding: UTF-8
require 'fiddle'

module MH
  module ModuleStudio
    # The DLL filters only this SketchUp UI thread's model-window messages.
    # Keyboard events are polled by Ruby; native callbacks never enter Ruby.
    module HUDInput
      extend self

      def load_api
        return if @api
        raise Core::Error, 'Chặn phím HUD cần SketchUp Windows 64-bit.' unless Sketchup.platform == :platform_win && Fiddle::SIZEOF_VOIDP == 8
        @dll = Fiddle.dlopen(File.join(__dir__.dup.force_encoding(Encoding::UTF_8), 'native', 'hud_input_v2.dll'))
        int = Fiddle::TYPE_INT
        pointer = Fiddle::TYPE_VOIDP
        signatures = { 'MHInstall' => [[], int], 'MHRemove' => [[], Fiddle::TYPE_VOID],
                       'MHPoll' => [[pointer, pointer, pointer], int], 'MHActive' => [[], int],
                       'MHCursor' => [[int, int, pointer, pointer, pointer, pointer], int], 'MHScale'=>[[],Fiddle::TYPE_DOUBLE] }
        @api = signatures.to_h { |name, (args, result)| [name, Fiddle::Function.new(@dll[name], args, result)] }
      end

      def start(tool)
        stop
        load_api
        raise Core::Error, 'Không khởi tạo được bộ giữ phím HUD.' unless @api['MHInstall'].call == 1
        @tool = tool
        @timer = UI.start_timer(0.02, true) { poll if @tool.equal?(tool) && tool.active }
      end

      def stop(tool = nil)
        return if tool && !@tool.equal?(tool)
        UI.stop_timer(@timer) if @timer
        @timer = nil
        @tool = nil
        @api&.fetch('MHRemove')&.call
      end

      def active?
        @api && @api['MHActive'].call == 1
      end

      def cursor(view)
        return nil unless @api
        factor = UI.scale_factor.to_f
        values = Array.new(4) { Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT, Fiddle::RUBY_FREE) }
        return nil unless @api['MHCursor'].call((view.vpwidth * factor).round, (view.vpheight * factor).round, *values) == 1
        factor *= @api['MHScale'].call
        x, y, left, over = values.map { |value| value[0, Fiddle::SIZEOF_INT].unpack1('i') }
        { 'x' => x / factor, 'y' => y / factor, 'left' => left == 1, 'over' => over == 1 }
      end

      def poll
        tool = @tool
        return unless tool
        key, down, repeat = Array.new(3) { Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT, Fiddle::RUBY_FREE) }
        128.times do
          break unless @api['MHPoll'].call(key, down, repeat) == 1
          view = Sketchup.active_model.active_view
          method = down[0, Fiddle::SIZEOF_INT].unpack1('i') == 1 ? :onKeyDown : :onKeyUp
          tool.public_send(method, key[0, Fiddle::SIZEOF_INT].unpack1('i'), repeat[0, Fiddle::SIZEOF_INT].unpack1('i'), 0, view)
          break unless @tool.equal?(tool) && tool.active
        end
        tool.poll_drag(cursor(Sketchup.active_model.active_view)) if @tool.equal?(tool) && tool.active && tool.drag_active?
      rescue StandardError => error
        tool&.fail_session(error)
        stop(tool)
      end
    end
  end
end

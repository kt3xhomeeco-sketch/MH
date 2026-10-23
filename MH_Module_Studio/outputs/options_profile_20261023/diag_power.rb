# encoding: UTF-8
# Diagnostic artifact (NOT production code). Read-only OS state of the live SketchUp process.
module MH
  module ModuleStudio
    module DiagPower
      extend self

      def run
        require 'fiddle'
        k32 = Fiddle.dlopen('kernel32.dll')
        ntdll = Fiddle.dlopen('ntdll.dll')
        get_proc = Fiddle::Function.new(k32['GetCurrentProcess'], [], Fiddle::TYPE_VOIDP)
        get_info = Fiddle::Function.new(k32['GetProcessInformation'],
                                       [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
                                       Fiddle::TYPE_INT)
        get_class = Fiddle::Function.new(k32['GetPriorityClass'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_LONG)
        nt_query = Fiddle::Function.new(ntdll['NtQueryTimerResolution'],
                                        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
                                        Fiddle::TYPE_LONG)

        h = get_proc.call
        out = {}
        out['priority_class'] = get_class.call(h)

        buf = Fiddle::Pointer.malloc(12, Fiddle::RUBY_FREE)
        buf[0, 12] = [1, 0, 0].pack('L3') # Version=PROCESS_POWER_THROTTLING_CURRENT_VERSION
        ok = get_info.call(h, 4, buf, 12) # 4 = ProcessPowerThrottling
        ver, ctrl, state = buf[0, 12].unpack('L3')
        out['power_throttling'] = {
          'ok' => ok, 'version' => ver, 'control_mask' => ctrl, 'state_mask' => state,
          'execution_speed_ecoqos' => (state & 0x1) != 0,
          'ignore_timer_resolution' => (state & 0x2) != 0
        }

        a = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
        b = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
        c = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
        rc = nt_query.call(a, b, c)
        out['timer_resolution'] = {
          'ntstatus' => rc,
          'min_100ns' => a[0, 4].unpack1('L'),
          'max_100ns' => b[0, 4].unpack1('L'),
          'current_100ns' => c[0, 4].unpack1('L')
        }
        out['foreground_window_pid'] = begin
          fg = Fiddle::Function.new(k32['GetForegroundWindow'], [], Fiddle::TYPE_VOIDP)
          fg_pid = Fiddle::Function.new(k32['GetWindowThreadProcessId'],
                                        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_LONG)
          w = fg.call
          pid = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
          fg_pid.call(w, pid)
          pid[0, 4].unpack1('L')
        rescue StandardError => e
          "#{e.class}: #{e.message}"
        end
        out
      rescue StandardError => e
        { 'error' => "#{e.class}: #{e.message}", 'bt' => e.backtrace.first(4) }
      end
    end
  end
end

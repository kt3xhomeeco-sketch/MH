# encoding: UTF-8
# Diagnostic artifact (NOT production code).
# Isolate where the ~14 ms cost of sleep(0.001) comes from:
#   thread creation/join vs Ruby sleep implementation vs Windows timer resolution vs thread priority.
module MH
  module ModuleStudio
    module DiagTimer2
      extend self

      def clock; Process.clock_gettime(Process::CLOCK_MONOTONIC); end
      def r3(x); (x.to_f * 1000).round / 1000.0; end

      def inside(n, prio: nil)
        t = Thread.new do
          Thread.current.priority = prio if prio
          Array.new(n) do
            a = clock
            sleep(0.001)
            (clock - a) * 1000.0
          end
        end
        t.value
      end

      def on_main(n)
        Array.new(n) do
          a = clock
          sleep(0.001)
          (clock - a) * 1000.0
        end
      end

      def stat(a)
        s = a.sort
        { 'n' => a.length, 'min_ms' => r3(s.first), 'median_ms' => r3(s[s.length / 2]),
          'mean_ms' => r3(a.sum / a.length), 'max_ms' => r3(s.last) }
      end

      def run
        require 'fiddle'
        k32 = Fiddle.dlopen('kernel32.dll')
        sleep_fn = Fiddle::Function.new(k32['Sleep'], [Fiddle::TYPE_INT], Fiddle::TYPE_VOID)
        begin_period = Fiddle::Function.new(k32['timeBeginPeriod'], [Fiddle::TYPE_INT], Fiddle::TYPE_INT)
        end_period = Fiddle::Function.new(k32['timeEndPeriod'], [Fiddle::TYPE_INT], Fiddle::TYPE_INT)

        win_sleep = lambda do |n|
          Array.new(n) do
            a = clock
            sleep_fn.call(1)
            (clock - a) * 1000.0
          end
        end

        out = {}
        out['ruby_sleep_main_default'] = stat(on_main(25))
        out['ruby_sleep_thread_default'] = stat(inside(25))
        out['ruby_sleep_thread_prio_minus2'] = stat(inside(25, prio: -2))
        out['win32_Sleep1_default'] = stat(win_sleep.call(25))
        out['win32_priority_class'] = begin
          get_proc = Fiddle::Function.new(k32['GetCurrentProcess'], [], Fiddle::TYPE_VOIDP)
          get_class = Fiddle::Function.new(k32['GetPriorityClass'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_LONG)
          get_class.call(get_proc.call)
        rescue StandardError => e
          "#{e.class}: #{e.message}"
        end

        begin
          rc = begin_period.call(1)
          out['timeBeginPeriod_rc'] = rc
          out['win32_Sleep1_timer1ms'] = stat(win_sleep.call(25))
          out['ruby_sleep_main_timer1ms'] = stat(on_main(25))
          out['ruby_sleep_thread_timer1ms'] = stat(inside(25))
        ensure
          end_period.call(1)
        end
        out
      rescue StandardError => e
        { 'error' => "#{e.class}: #{e.message}", 'bt' => e.backtrace.first(4) }
      end
    end
  end
end

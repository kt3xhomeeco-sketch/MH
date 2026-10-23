# encoding: UTF-8
# Diagnostic artifact (NOT production code).
# End-to-end job on the existing fixture, WITHOUT the timing hooks:
#   wall vs process CPU (user+sys) vs UI heartbeat gaps.
module MH
  module ModuleStudio
    module DiagJob
      extend self

      def clock; Process.clock_gettime(Process::CLOCK_MONOTONIC); end
      def r3(x); (x.to_f * 1000).round / 1000.0; end

      def run(target = 24.0)
        q = MH::ModuleStudio::NativeOptionsProfile
        raise 'fixture not set up' unless q.instance_variable_get(:@setup)
        raise 'already running' if @poll
        @t0 = clock
        @cpu0 = Process.times
        @hb = { 'n' => 0, 'max_ms' => 0.0 }
        @last = @t0
        @tid = UI.start_timer(0.1, true) do
          t = clock
          g = t - @last
          @last = t
          @hb['n'] += 1
          @hb['max_ms'] = r3(g * 1000.0) if g * 1000.0 > @hb['max_ms']
        end
        @result = nil
        @poll = UI.start_timer(0.05, true) { check }
        started = q.start(profiled: false, target: target)
        { 'started' => started, 'target' => target }
      rescue StandardError => e
        { 'error' => "#{e.class}: #{e.message}", 'bt' => e.backtrace.first(4) }
      end

      def check
        return @result if @result
        q = MH::ModuleStudio::NativeOptionsProfile
        c = q.instance_variable_get(:@case)
        return unless c && c[:done]
        UI.stop_timer(@poll) if @poll
        UI.stop_timer(@tid) if @tid
        @poll = nil
        @tid = nil
        cpu = Process.times
        @result = {
          'status' => c[:status], 'error' => c[:error],
          'wall_ms' => r3((clock - @t0) * 1000.0),
          'cpu_user_ms' => r3((cpu.utime - @cpu0.utime) * 1000.0),
          'cpu_sys_ms' => r3((cpu.stime - @cpu0.stime) * 1000.0),
          'cpu_total_ms' => r3((cpu.utime - @cpu0.utime + cpu.stime - @cpu0.stime) * 1000.0),
          'hb' => @hb, 'metrics' => c[:metrics]
        }
      end

      def result
        check
        @result
      end
    end
  end
end

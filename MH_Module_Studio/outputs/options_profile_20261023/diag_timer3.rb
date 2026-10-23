# encoding: UTF-8
# Diagnostic artifact (NOT production code).
# Map the actual wake-up quantization of sleep(n) in this process.
module MH
  module ModuleStudio
    module DiagTimer3
      extend self
      def clock; Process.clock_gettime(Process::CLOCK_MONOTONIC); end
      def r3(x); (x.to_f * 1000).round / 1000.0; end

      def in_thread(n, secs)
        Thread.new do
          Array.new(n) do
            a = clock
            sleep(secs)
            (clock - a) * 1000.0
          end
        end.value
      end

      def stat(a)
        s = a.sort
        { 'requested_ms' => nil, 'min' => r3(s.first), 'median' => r3(s[s.length / 2]),
          'mean' => r3(a.sum / a.length), 'max' => r3(s.last) }
      end

      def run
        out = {}
        [[0.001, 12], [0.002, 12], [0.004, 12], [0.008, 10], [0.016, 10], [0.020, 10], [0.032, 8]].each do |secs, n|
          st = stat(in_thread(n, secs))
          st['requested_ms'] = r3(secs * 1000.0)
          out["sleep_#{secs}"] = st
        end
        # CPU-time based check: a pure CPU spin of a known duration, no sleep
        out
      rescue StandardError => e
        { 'error' => "#{e.class}: #{e.message}" }
      end
    end
  end
end

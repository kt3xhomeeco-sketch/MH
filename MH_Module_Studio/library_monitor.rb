# encoding: UTF-8
require_relative 'library_catalog'

module MH
  module ModuleStudio
    # Incremental metadata only: no SKP contents, rendering or native model calls.
    # Enumerator yields between paths so the controller can bound each UI tick.
    class LibraryMonitor
      def reset(root,catalog)
        @root = root.dup
        @baseline = catalog
        @candidate = @scan = nil
        @next_scan = 0
      end

      def poll(now: Process.clock_gettime(Process::CLOCK_MONOTONIC))
        if !@scan && now>=@next_scan && @root && !@root.empty?
          root=@root
          @scan=Enumerator.new do |progress|
            if File.directory?(root)
              LibraryCatalog.scan(root) { progress.yield }
            else
              {'root'=>root,'folders'=>[],'entries'=>[]}
            end
          end
          @next_scan=now+(@candidate ? 0.4 : 2.0)
        end
        return unless @scan
        deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+0.004
        while true
          @scan.next
          return if Process.clock_gettime(Process::CLOCK_MONOTONIC)>=deadline
        end
      rescue StopIteration=>finished
        @scan=nil
        observed=finished.result
        if observed==@baseline
          @candidate=nil
        elsif observed==@candidate
          @baseline=observed
          @candidate=nil
          return observed
        else
          @candidate=observed
        end
        nil
      rescue StandardError
        # Concurrent save/rename: discard partial work and retry on the next
        # interval. Never replace the catalog with an incomplete observation.
        @scan=@candidate=nil
        nil
      end
    end
  end
end

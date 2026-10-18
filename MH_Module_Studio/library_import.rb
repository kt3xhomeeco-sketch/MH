# encoding: UTF-8
require 'digest'
require_relative 'library_catalog'

module MH
  module ModuleStudio
    # No live entities in this cache. Placement still validates actual geometry.
    class LibraryImport
      MAX_ITEMS = 16
      MAX_BYTES = 8*1024*1024

      def initialize
        @validated = {}
        @bytes = 0
        @cache_lock = Mutex.new
        @work_lock = Mutex.new
      end

      def payload(raw)
        raise Core::Error,'Bộ quy tắc thư viện không hợp lệ.' unless raw.is_a?(String) && raw.bytesize<=LibraryCatalog::MAX_BYTES
        key = Digest::SHA256.hexdigest(raw)
        stored = cached(key)
        return JSON.parse(stored) if stored
        @foreground_waiting = true if Thread.current==Thread.main
        begin
          @work_lock.synchronize do
            stored = cached(key)
            return JSON.parse(stored) if stored
            data = LibraryCatalog.payload(raw)
            data['rule']=DCCustomAttributes.upgrade(data['rule']) if data['format']=='mh_module_library'
            remember(key,JSON.generate(data))
            data
          end
        ensure
          @foreground_waiting = false if Thread.current==Thread.main
        end
      end

      # Only portable JSON/rule calculations run here. Never pass native objects
      # or call SketchUp/UI from this worker; actual geometry is checked on click.
      def prefetch(raw)
        return unless raw.is_a?(String) && raw.bytesize<=LibraryCatalog::MAX_BYTES
        return if cached(Digest::SHA256.hexdigest(raw)) || @worker&.alive?
        source = raw.dup.freeze
        @worker = Thread.new do
          Thread.current.priority = -2
          # SketchUp shares Ruby's GVL. Yield during long pure calculations so
          # pointer/Tool callbacks can run; trace only this worker, never the UI.
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC)+0.025
          events = 0
          trace = TracePoint.new(:call) do
            if @foreground_waiting
              trace.disable
              Thread.current.priority = 0
              next
            end
            events+=1
            next unless (events%128).zero? && Process.clock_gettime(Process::CLOCK_MONOTONIC)>=deadline
            Thread.pass
            deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC)+0.025
          end
          trace.enable(target_thread:Thread.current) { payload(source) }
          nil
        rescue StandardError
          # Placement repeats failed validation synchronously with its normal error.
          nil
        ensure
          trace&.disable
        end
      end

      def cached(key)
        @cache_lock.synchronize do
          stored = @validated.delete(key)
          @validated[key] = stored if stored
          stored
        end
      end

      def remember(key,stored)
        return if stored.bytesize>MAX_BYTES
        @cache_lock.synchronize do
          while @validated.length>=MAX_ITEMS || @bytes+stored.bytesize>MAX_BYTES
            _old,removed=@validated.shift;@bytes-=removed.bytesize
          end
          @validated[key]=stored;@bytes+=stored.bytesize
        end
      end

      private :cached, :remember

      def preview(raw)
        unless raw.is_a?(String) && !raw.empty? && raw.bytesize<=LibraryCatalog::MAX_BYTES
          raise Core::Error,'SKP thiếu hoặc vượt giới hạn dữ liệu module.'
        end
        data = JSON.parse(raw)
        unless data.is_a?(Hash) && %w[mh_module_library mh_module_assembly].include?(data['format']) && data['version']==1
          raise Core::Error,'Không hỗ trợ phiên bản module thư viện này.'
        end
        snapshot = data.fetch('snapshot')
        if data['format']=='mh_module_assembly'
          envelope=Core.bounds!(snapshot.fetch('envelope'))
          snapshot={'envelope'=>envelope,'parts'=>[{'key'=>'@assembly','bounds'=>envelope,'visible'=>true}]}
        end
        Core.snapshot!(snapshot)
        result={'format'=>data['format'],'version'=>1,'name'=>data['name'].to_s[0,160],'snapshot'=>snapshot}
        result['import_template']=ImportTemplate.validate(data['rule']['import_template']) if data.dig('rule','import_template')
        if result.dig('import_template','enabled') && result.dig('import_template','role')=='door'
          result['door_thickness']=ImportTemplate.door_thickness(data['rule'],data.fetch('values',{}),snapshot['envelope'])
        end
        result
      rescue JSON::ParserError,KeyError,TypeError,NoMethodError => error
        raise Core::Error,"Dữ liệu xem trước không hợp lệ: #{error.message}"
      end
    end
  end
end

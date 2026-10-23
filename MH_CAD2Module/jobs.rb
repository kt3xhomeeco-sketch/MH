# frozen_string_literal: true

require_relative 'settings'
require_relative 'storage'

module MH
  module CAD2Module
    # The worker sees JSON/files only. All SketchUp API calls stay on its main thread.
    module Jobs
      module_function

      def busy?
        !@job.nil?
      end

      def start(action, values = {}, &completion)
        raise ArgumentError, 'Đang có tác vụ CAD chạy; chờ hoàn tất hoặc hủy trước.' if busy?
        model = Sketchup.active_model
        settings = Settings.read(model)
        root = Settings.library(settings)
        id = Ids.uuid
        directory = File.join(root, 'jobs', id)
        FileUtils.mkdir_p(directory)
        request = File.join(directory, 'request.json')
        response = File.join(directory, 'response.json')
        progress = File.join(directory, 'progress.json')
        packet = settings.merge(values).merge('action' => action, 'library' => root, 'progress_file' => progress)
        Storage.write_json(request, packet)
        python = Settings.python(settings)
        windowless = python.sub(/python\.exe\z/i, 'pythonw.exe')
        python = windowless if File.file?(windowless)
        worker = ensure_worker(python, root)
        ticket = File.join(worker[:queue], "#{id}.json")
        Storage.write_json(ticket, 'request' => request, 'response' => response)
        @job = { id: id, pid: worker[:pid], response: response, model: model, root: root,
                 started: Time.now, log: worker[:log], python: python, completion: completion, progress: progress, ticket: ticket }
        @timer = UI.start_timer(0.1, true) { poll }
        id
      end

      def worker_alive?(worker)
        worker && Process.waitpid2(worker[:pid], Process::WNOHANG).nil?
      rescue Errno::ECHILD
        false
      end

      def ensure_worker(python, root)
        fingerprint = Dir.glob(File.join(Settings::ROOT, 'worker', '*.py')).sort.map { |path| [path, File.mtime(path).to_f, File.size(path)] }
        return @worker if @worker && @worker[:root] == root && @worker[:python] == python && @worker[:fingerprint] == fingerprint && worker_alive?(@worker)
        stop_worker
        directory = File.join(root, 'jobs', ".resident-#{Ids.uuid}")
        queue = File.join(directory, 'queue')
        FileUtils.mkdir_p(queue)
        log = File.join(directory, 'worker.log')
        pid = Process.spawn(python, '-X', 'utf8', File.join(Settings::ROOT, 'worker', 'resident.py'), '--queue', queue, '--parent', Process.pid.to_s,
                            out: log, err: [:child, :out], chdir: Settings::ROOT)
        @worker = { pid: pid, root: root, python: python, queue: queue, log: log, fingerprint: fingerprint }
      end

      def stop_worker
        worker = @worker
        @worker = nil
        terminate(worker[:pid], worker[:python]) if worker && worker_alive?(worker)
      end

      def terminate(pid, python)
        if RUBY_PLATFORM.include?('mingw') || RUBY_PLATFORM.include?('mswin')
          code = "import subprocess,sys; s=subprocess.STARTUPINFO(); s.dwFlags|=subprocess.STARTF_USESHOWWINDOW; s.wShowWindow=0; subprocess.run(['taskkill','/PID',sys.argv[1],'/T','/F'],startupinfo=s,creationflags=subprocess.CREATE_NO_WINDOW,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)"
          killer = Process.spawn(python, '-c', code, pid.to_s, out: File::NULL, err: File::NULL)
          Process.detach(killer)
        else
          Process.kill('KILL', pid) rescue nil
        end
        Process.detach(pid) rescue nil
      end

      def poll
        job = @job
        return unless job
        if File.file?(job[:response])
          result = JSON.parse(File.read(job[:response], encoding: 'UTF-8'))
          result['worker'] ||= {}
          result['worker']['roundtrip_seconds'] = (Time.now - job[:started]).round(6)
          finish(job, result)
        elsif Time.now - job[:started] > 600
          cancel
          job[:completion].call({ 'ok' => false, 'error' => 'Đọc CAD quá 10 phút. Xem nhật ký tác vụ.' }, job)
        else
          publish_progress(job)
          status = Process.waitpid2(job[:pid], Process::WNOHANG)
          return unless status
          # The response may have appeared between the first test and process exit.
          if File.file?(job[:response])
            finish(job, JSON.parse(File.read(job[:response], encoding: 'UTF-8')))
          else
            finish(job, { 'ok' => false, 'error' => "Bộ đọc CAD dừng trước khi có kết quả. Nhật ký: #{job[:log]}" })
          end
        end
      rescue Errno::ECHILD
        finish(job, { 'ok' => false, 'error' => 'Mất tiến trình đọc CAD; xem nhật ký trong thư viện.' })
      rescue StandardError => error
        finish(job, { 'ok' => false, 'error' => error.message })
      end

      def publish_progress(job)
        return unless job[:model].equal?(Sketchup.active_model)
        now = Time.now
        return if job[:progress_emitted] && now - job[:progress_emitted] < 1
        progress = if File.file?(job[:progress])
                     JSON.parse(File.read(job[:progress], encoding: 'UTF-8'))
                   else
                     { 'stage' => 'starting', 'message' => 'Đang khởi động bộ đọc CAD…' }
                   end
        if job[:progress_stage] != progress['stage']
          job[:progress_stage] = progress['stage']
          job[:progress_started] = now
          (job[:progress_seen] ||= []) << progress['stage']
        end
        job[:progress_emitted] = now
        elapsed = (now - job[:started]).to_i
        stage_elapsed = (now - job[:progress_started]).to_i
        CAD2Module.publish_progress("#{progress['message']} · Bước này #{stage_elapsed}s · Tổng #{elapsed}s")
      rescue JSON::ParserError, SystemCallError
        nil
      end

      def finish(job, result)
        return unless @job.equal?(job)
        UI.stop_timer(@timer) if @timer
        @timer = nil
        @job = nil
        job[:completion].call(result, job)
      rescue StandardError => error
        CAD2Module.report_error("Không áp dụng được kết quả tác vụ: #{error.message}")
      end

      def cancel
        job = @job
        return unless job
        UI.stop_timer(@timer) if @timer
        @job = nil
        @timer = nil
        File.delete(job[:ticket]) if job[:ticket] && File.file?(job[:ticket])
        @worker = nil
        terminate(job[:pid], job[:python])
      end
    end
  end
end

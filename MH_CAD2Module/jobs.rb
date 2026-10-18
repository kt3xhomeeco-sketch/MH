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
        packet = settings.merge(values).merge('action' => action, 'library' => root)
        Storage.write_json(request, packet)
        python = Settings.python(settings)
        windowless = python.sub(/python\.exe\z/i, 'pythonw.exe')
        python = windowless if File.file?(windowless)
        script = File.join(Settings::ROOT, 'worker', 'main.py')
        log = File.join(directory, 'worker.log')
        pid = Process.spawn(python, '-X', 'utf8', script, '--request', request, '--response', response,
                            out: log, err: [:child, :out], chdir: Settings::ROOT)
        @job = { id: id, pid: pid, response: response, model: model, root: root,
                 started: Time.now, log: log, python: python, completion: completion }
        @timer = UI.start_timer(0.3, true) { poll }
        id
      end

      def poll
        job = @job
        return unless job
        if File.file?(job[:response])
          result = JSON.parse(File.read(job[:response], encoding: 'UTF-8'))
          finish(job, result)
        elsif Time.now - job[:started] > 600
          cancel
          job[:completion].call({ 'ok' => false, 'error' => 'Đọc CAD quá 10 phút. Xem nhật ký tác vụ.' }, job)
        else
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

      def finish(job, result)
        return unless @job.equal?(job)
        UI.stop_timer(@timer) if @timer
        @timer = nil
        @job = nil
        Process.detach(job[:pid]) rescue nil
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
        if RUBY_PLATFORM.include?('mingw') || RUBY_PLATFORM.include?('mswin')
          # A windowless helper stops ODA descendants as well as the worker itself.
          code = "import subprocess,sys; s=subprocess.STARTUPINFO(); s.dwFlags|=subprocess.STARTF_USESHOWWINDOW; s.wShowWindow=0; subprocess.run(['taskkill','/PID',sys.argv[1],'/T','/F'],startupinfo=s,creationflags=subprocess.CREATE_NO_WINDOW,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)"
          killer = Process.spawn(job[:python], '-c', code, job[:pid].to_s, out: File::NULL, err: File::NULL)
          Process.detach(killer)
        else
          Process.kill('KILL', job[:pid]) rescue nil
        end
        Process.detach(job[:pid]) rescue nil
      end
    end
  end
end

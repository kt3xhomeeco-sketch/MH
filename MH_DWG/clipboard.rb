# frozen_string_literal: true

module MH
  # CAD clipboard import and placement for SketchUp.
  module DWG
    def self.clipboard_dwg_path
      dwg = find_clipboard_dwg
      unless dwg
        log_event('paste.no_clipboard_dwg')
        UI.messagebox('Không tìm thấy file DWG!')
        return nil
      end
      log_event('paste.dwg_found', path: dwg, size: diagnostic_value { File.size(dwg) },
                                   mtime: diagnostic_value { File.mtime(dwg).to_s })
      dwg
    end

    def self.find_clipboard_dwg
      # AutoCAD uses A$C*.dwg. VinaCAD creates a regular .dwg (for example
      # 8f0.dwg) and a .tmp file with the same basename. Scan both sources,
      # then use the one copied most recently.
      autocad_files, vinacad_files = clipboard_file_lists
      candidates = (autocad_files + vinacad_files).uniq
      newest, newest_mtime = available_clipboard_files(candidates).max_by { |_, modified_at| modified_at }
      log_clipboard_selection(autocad_files, vinacad_files, newest, newest_mtime)
      newest
    rescue StandardError => e
      log_event('clipboard.dwg_path_error', error: "#{e.class}: #{e.message}")
      nil
    end

    def self.clipboard_file_lists
      temp = ENV.fetch('TEMP').tr('\\', '/')
      autocad_files = Dir.glob(File.join(temp, 'A$C*.dwg'), File::FNM_CASEFOLD)
      vinacad_files = Dir.glob(File.join(temp, '*.dwg'), File::FNM_CASEFOLD)
                         .select { |file| vinacad_clipboard_temp_dwg?(file) }
      [autocad_files, vinacad_files]
    end

    def self.available_clipboard_files(candidates)
      candidates.filter_map do |file|
        next unless File.file?(file)

        [file, File.mtime(file)]
      rescue SystemCallError, IOError => e
        # Temp files can disappear or become locked after directory discovery.
        # One unavailable candidate must not hide the remaining valid drawings.
        log_event('clipboard.dwg_candidate_skipped', path: file, error: "#{e.class}: #{e.message}")
        nil
      end
    end

    def self.log_clipboard_selection(autocad_files, vinacad_files, newest, newest_mtime)
      log_event(
        'clipboard.dwg_path_selected',
        autocad_files: autocad_files,
        vinacad_files: vinacad_files,
        selected_path: newest,
        selected_mtime: newest_mtime&.to_s
      )
    end

    def self.vinacad_clipboard_temp_dwg?(file)
      return false if File.basename(file).match?(/\AA\$C.+\.dwg\z/i)

      basename = File.basename(file, '.dwg')
      File.file?(File.join(File.dirname(file), "#{basename}.tmp"))
    end
  end
end

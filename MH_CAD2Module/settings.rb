# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'digest'
require_relative 'ids'

module MH
  module CAD2Module
    # Paths are preferences; all drawing bytes and history belong in the chosen library.
    module Settings
      DICT = 'MH_CAD2Module'
      source_file = __FILE__.dup
      source_file.force_encoding('UTF-8')
      ROOT = File.dirname(source_file).freeze
      DEFAULTS = { 'sources' => [], 'library' => File.join(ROOT, 'library'), 'python' => '', 'converter' => '',
                   'build_plan' => true, 'build_elevation' => false, 'build_auxiliary' => true }.freeze
      module_function

      def read(model = Sketchup.active_model)
        fallback = Sketchup.read_default(DICT, 'settings', '{}')
        raw = model.get_attribute(DICT, 'settings', fallback)
        DEFAULTS.merge(JSON.parse(raw))
      rescue JSON::ParserError, TypeError
        DEFAULTS.dup
      end

      def save(values, model = Sketchup.active_model)
        data = read(model).merge(values.slice(*DEFAULTS.keys))
        data['sources'] = Array(data['sources']).map(&:to_s).reject(&:empty?).uniq
        library(data) unless data['library'].to_s.empty?
        model.start_operation('CAD2Module: Cấu Hình', true)
        operation = true
        model.set_attribute(DICT, 'settings', JSON.generate(data))
        model.set_attribute(DICT, 'project_id', Ids.uuid) unless model.get_attribute(DICT, 'project_id')
        model.commit_operation
        operation = false
        Sketchup.write_default(DICT, 'settings', JSON.generate(data))
        data
      rescue StandardError
        model.abort_operation if operation
        raise
      end

      def library(data = read)
        path = data.fetch('library', '').to_s.strip
        raise ArgumentError, 'Chọn thư mục thư viện trong bảng Quản lý.' if path.empty?
        root = resolve_library(path)
        FileUtils.mkdir_p(root)
        real = File.realpath(root)
        probe = File.join(real, ".write-#{Ids.hex(6)}")
        File.write(probe, '')
        File.delete(probe)
        real
      end

      def resolve_library(path)
        root = File.expand_path(path)
        aliases = JSON.parse(Sketchup.read_default(DICT, 'library_aliases', '{}'))
        10.times do
          match = aliases.keys.sort_by { |key| -key.length }.find do |key|
            root == key || root.start_with?(key + File::SEPARATOR)
          end
          break unless match
          root = aliases[match] + root.delete_prefix(match)
        end
        root
      end

      def relocate(target)
        old_root = library
        new_root = File.expand_path(target)
        return save('library' => old_root) if new_root.casecmp?(old_root)
        prefix = old_root.tr('\\', '/').downcase + '/'
        if new_root.tr('\\', '/').downcase.start_with?(prefix)
          raise ArgumentError, 'Chọn thư mục mới nằm ngoài thư viện hiện tại.'
        end
        FileUtils.mkdir_p(new_root)
        new_root = File.realpath(new_root)
        raise ArgumentError, 'Thư mục đích đang trỏ vào thư viện hiện tại.' if new_root.tr('\\', '/').downcase.start_with?(prefix)
        # Refuse conflicting bytes before copying anything. Existing matching snapshots are safe.
        files = Dir.glob(File.join(old_root, '**', '*'), File::FNM_DOTMATCH).select { |p| File.file?(p) }
        files.each do |path|
          relative = path.delete_prefix(old_root + File::SEPARATOR)
          destination = File.join(new_root, relative)
          if File.file?(destination) && Digest::SHA256.file(path) != Digest::SHA256.file(destination)
            raise ArgumentError, "Thư mục đích có dữ liệu khác trùng tên: #{relative}"
          end
        end
        files.each do |path|
          relative = path.delete_prefix(old_root + File::SEPARATOR)
          destination = File.join(new_root, relative)
          FileUtils.mkdir_p(File.dirname(destination))
          next if File.file?(destination)
          temporary = "#{destination}.#{Ids.hex(6)}.tmp"
          begin
            FileUtils.cp(path, temporary)
            raise IOError, "Bản sao chưa khớp: #{relative}" unless Digest::SHA256.file(path).hexdigest == Digest::SHA256.file(temporary).hexdigest
            File.rename(temporary, destination)
          ensure
            File.delete(temporary) if File.file?(temporary)
          end
        end
        aliases = JSON.parse(Sketchup.read_default(DICT, 'library_aliases', '{}'))
        aliases[old_root] = File.realpath(new_root)
        save('library' => new_root)
        Sketchup.write_default(DICT, 'library_aliases', JSON.generate(aliases))
        read
      end

      def python(data = read)
        configured = data.fetch('python', '').to_s
        return configured unless configured.empty?
        candidates = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).map { |dir| File.join(dir, 'python.exe') }
        candidates.unshift(File.join(ENV.fetch('ProgramFiles', 'C:/Program Files'), 'Python312', 'python.exe'))
        candidates.find { |path| File.file?(path) && !path.include?('WindowsApps') } || 'python'
      end
    end
  end
end

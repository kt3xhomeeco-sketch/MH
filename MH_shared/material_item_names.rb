# encoding: UTF-8

require 'json'
require 'open3'
require_relative 'material_library'

module MH
  # Both apps execute the Python engine deployed beside the one shared workbook.
  module MaterialItemNames
    module_function

    def directory
      MH::MaterialLibrary.directory
    end

    def config_path
      MH::MaterialLibrary.path
    end

    def engine_path
      File.join(directory, 'material_item_names.py')
    end

    def signature
      [config_path, engine_path].map do |path|
        stat = File.stat(path)
        [path, stat.mtime.to_f, stat.size]
      end
    end

    def names(codes, python:)
      current = signature
      if @signature != current
        @names = {}
        @signature = current
      end
      codes = Array(codes).map { |code| code.to_s.strip }.uniq
      missing = codes.reject { |code| @names.key?(code) }
      unless missing.empty?
        result = request({ codes: missing }, python)
        translated = result.fetch('names')
        raise 'Thư viện tên hàng trả thiếu mã vật liệu' unless missing.all? { |code| translated[code].is_a?(String) }

        @names.merge!(translated)
      end
      codes.to_h { |code| [code, @names.fetch(code)] }
    rescue Errno::ENOENT => error
      raise "Không tìm thấy thư viện tên hàng tại #{directory}: #{error.message}"
    end

    def qualifiers(code, python:)
      request({ codes: [], qualifier_code: code.to_s }, python).fetch('qualifiers')
    end

    def request(payload, python)
      payload = payload.merge(config_path: config_path)
      stdout, stderr, status = Open3.capture3(*python, '-X', 'utf8', engine_path,
                                            stdin_data: JSON.generate(payload), binmode: true)
      unless status.success?
        raise "Lỗi thư viện tên hàng (#{status.exitstatus}): #{stderr.force_encoding('UTF-8').strip}"
      end

      JSON.parse(stdout.force_encoding('UTF-8'))
    end
  end
end

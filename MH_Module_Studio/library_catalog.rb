# encoding: UTF-8
require 'json'
require 'digest'
require 'fileutils'
require_relative 'core'

module MH
  module ModuleStudio
    # No SketchUp API here: folder boundaries, portable SKP payloads and HUD layout.
    module LibraryCatalog
      extend self
      DEFAULTS = { 'root' => '', 'folder' => '', 'view' => 'grid', 'thumbnail_size' => 150,
                   'hud_size' => 86, 'hud_spacing' => 100, 'hud_image_zoom' => 100, 'hud_position' => 'center', 'hud_orders' => {}, 'folder_keys' => {} }.freeze
      PAYLOAD_KEY = 'library_payload_json'.freeze
      MAX_BYTES = 16 * 1024 * 1024

      def settings(raw)
        raw = {} unless raw.is_a?(Hash)
        result = DEFAULTS.merge(raw.slice(*DEFAULTS.keys, *HUDBoards::FIELDS))
        result['root'] = result['root'].to_s
        result['folder'] = result['folder'].to_s
        result['view'] = %w[grid list].include?(result['view']) ? result['view'] : 'grid'
        result['hud_position'] = %w[cursor center].include?(result['hud_position']) ? result['hud_position'] : 'center'
        { 'thumbnail_size' => [80, 260], 'hud_size' => [24, 140], 'hud_image_zoom' => [25, 300], 'hud_spacing' => [80, 200] }.each do |key, limits|
          value = Float(result[key], exception: false)
          result[key] = value && value.finite? ? [[value.round, limits[0]].max, limits[1]].min : DEFAULTS[key]
        end
        keys = result['folder_keys']
        keys = {} unless keys.is_a?(Hash)
        assigned = []
        result['folder_keys'] = keys.first(500).to_h.filter_map do |folder, letter|
          letter = letter.to_s.upcase
          next unless folder.is_a?(String) && letter.match?(/\A[A-Z]\z/) && !assigned.include?(letter)
          assigned << letter
          [folder, letter]
        end.to_h
        orders = result['hud_orders']
        result['hud_orders'] = orders.is_a?(Hash) ? orders.first(500).filter_map do |folder, ids|
          next unless folder.is_a?(String) && folder.length <= 2000 && ids.is_a?(Array)
          [folder, ids.first(5000).select { |id| id.is_a?(String) && id.length.between?(1, 2000) }.uniq]
        end.to_h : {}
        HUDBoards.normalize(result)
      end

      def inside?(root, path)
        base = File.realpath(root).tr('\\', '/').sub(%r{/+\z}, '').downcase
        candidate = File.realpath(path).tr('\\', '/').downcase
        candidate == base || candidate.start_with?(base + '/')
      rescue SystemCallError
        false
      end

      def fingerprint(path,stat: nil,canonical: nil)
        stat ||= File.stat(path)
        Digest::SHA256.hexdigest([(canonical || File.realpath(path)).downcase, stat.size, stat.mtime.to_f].join('|'))
      end

      def scan(root)
        raise Core::Error, 'Folder thư viện không tồn tại. Chọn lại folder.' unless File.directory?(root)
        root = File.realpath(root).tr('\\', '/')
        boundary = root.downcase+'/'
        folders = [{ 'id' => '', 'name' => File.basename(root), 'parent' => nil,'identity'=>identity(File.stat(root)) }]
        entries = []
        visit = lambda do |directory, depth|
          raise Core::Error, 'Thư viện quá sâu (tối đa 20 cấp).' if depth > 20
          Dir.children(directory).sort_by(&:downcase).each do |name|
            yield if block_given?
            path = File.join(directory, name)
            stat=File.lstat(path)
            next if stat.symlink?
            canonical=File.realpath(path).tr('\\','/')
            next unless canonical.downcase.start_with?(boundary)
            relative = path.delete_prefix(root + '/')
            parent = relative.include?('/') ? relative.rpartition('/').first : ''
            if stat.directory?
              next if name.start_with?('.')
              folders << { 'id' => relative, 'name' => name, 'parent' => parent,'identity'=>identity(stat) }
              visit.call(path, depth + 1)
            elsif stat.file? && File.extname(name).downcase == '.skp'
              entries << { 'id' => relative, 'name' => File.basename(name, File.extname(name)), 'folder' => parent,
                           'path' => path, 'fingerprint' => fingerprint(path,stat:stat,canonical:canonical), 'bytes' => stat.size,'identity'=>identity(stat) }
            end
            raise Core::Error, 'Thư viện vượt 5.000 mục. Chọn folder nhỏ hơn.' if entries.length + folders.length > 5000
          end
        end
        visit.call(root, 0)
        { 'root' => root, 'folders' => folders, 'entries' => entries }
      end

      def identity(stat)
        stat.ino>0 ? "#{stat.dev}:#{stat.ino}" : nil
      end

      def payload(raw)
        raise Core::Error, 'SKP chưa có bộ quy tắc MH. Dùng Tạo model rồi Lưu module trong Library.' unless raw.is_a?(String) && !raw.empty?
        raise Core::Error, 'Bộ quy tắc trong SKP vượt 16 MB.' if raw.bytesize > MAX_BYTES
        data = JSON.parse(raw)
        return AssemblyFile.payload(data) if data.is_a?(Hash) && data['format']=='mh_module_assembly'
        unless data.is_a?(Hash) && data['format'] == 'mh_module_library' && data['version'] == 1
          raise Core::Error, 'Không hỗ trợ phiên bản module thư viện này.'
        end
        Core.rule!(data.fetch('rule'))
        data['rule'] = ThicknessSymbols.normalize(data['rule'])
        Core.snapshot!(data.fetch('snapshot'))
        unless data['values'].is_a?(Hash) && data['rule']['kind'] == 'module_rule_system' &&
               (DCCopies.enabled?(data['rule']) || data['snapshot']['parts'].map { |part| part['key'] }.sort == data['rule']['parts'].map { |part| part['key'] }.sort)
          raise Core::Error, 'Bộ quy tắc không khớp các chi tiết trong SKP.'
        end
        if DCCopies.enabled?(data['rule']) && !Core.plan(data['rule'],data['snapshot'],data['values'])['changed_count'].zero?
          raise Core::Error,'Số lượng hoặc vị trí Copies chưa khớp dữ liệu SKP đã lưu.'
        end
        data
      rescue JSON::ParserError, KeyError, TypeError => error
        raise Core::Error, "Dữ liệu module không hợp lệ: #{error.message}"
      end

      def fold(text)
        text.to_s.downcase.tr('đ', 'd').unicode_normalize(:nfd).gsub(/\p{Mn}/, '')
      end

      def filtered(entries, folder, query = '')
        needle = fold(query)
        entries.select { |item| item['folder'] == folder && fold(item['name']).include?(needle) }
      end

      def hud_entries(entries, settings, query = '')
        lookup = entries.to_h { |item| [item['id'], item] }
        ordered = settings.fetch('hud_orders', {}).fetch(settings['folder'], []).filter_map { |id| lookup[id] }
        ids = ordered.to_h { |item| [item['id'], true] }
        ordered += entries.select { |item| item['folder'] == settings['folder'] && !ids.key?(item['id']) }
        needle = fold(query)
        ordered.select { |item| fold(item['name']).include?(needle) }
      end

      def move_hud_item(entries, settings, id, index)
        raise Core::Error, 'Module đã đổi. Làm mới thư viện.' unless entries.any? { |item| item['id'] == id }
        raise Core::Error, 'Vị trí HUD không hợp lệ.' unless index.is_a?(Integer) && index.between?(0, 5000)
        ids = hud_entries(entries, settings).map { |item| item['id'] }
        ids.delete(id)
        ids.insert([index, ids.length].min, id)
        settings.fetch('hud_orders', {}).merge(settings['folder'] => ids)
      end

      # Eight circles remain separated even at the largest size; shrink to fit a small viewport.
      def layout(width, height, size, center: nil, spacing: 100)
        size = [size.to_f, (width - 32) / 4.8, (height - 135) / 4.8].min
        size = [size, 24].max
        radius = [size * 1.65 * spacing / 100.0, [width,height].min/2.0-size/2.0-16].min
        extent = radius + size * 0.5
        cx, cy = center || [width * 0.5, height * 0.5]
        cx = [[cx, extent + 16].max, width - extent - 16].min
        cy = [[cy, extent + 45].max, height - extent - 90].min
        { 'center' => [cx, cy], 'size' => size, 'radius' => radius,
          'items' => 8.times.map do |index|
            angle = -Math::PI / 2 + index * Math::PI / 4
            [cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius]
          end }
      end
    end
  end
end

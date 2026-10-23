# frozen_string_literal: true

require_relative 'storage'

module MH
  module CAD2Module
    # History is immutable; the work log is a read-only, lazy presentation of it.
    module Activity
      module_function

      def key(data)
        return data['activity_id'] unless data['activity_id'].to_s.empty?
        code = data['code'] || data.dig('analysis', 'code')
        "legacy:#{code}" unless code.to_s.empty?
      end

      def indexes(root)
        @indexes ||= {}
        files = Dir.glob(File.join(root, 'history', 'index', '*.json')).sort
        stamp = files.map { |file| [file, File.mtime(file).to_f, File.size(file)] }
        cached = @indexes[root]
        return cached[:rows] if cached && cached[:stamp] == stamp
        rows = files.filter_map do |file|
          row = JSON.parse(File.read(file, encoding: 'UTF-8'))
          row if row.is_a?(Hash) && row['file'].is_a?(String) && row['id']
        rescue JSON::ParserError, SystemCallError
          nil
        end
        @indexes[root] = { stamp: stamp, rows: rows }
        rows
      end

      def rows(root, live)
        roots = ([root] + live.filter_map { |product| product.get_attribute('MH_CAD2Module', 'library') }).uniq
        entries = roots.flat_map { |library| indexes(library).map { |row| row.merge('_library' => library) } }.uniq { |row| row['id'] }
        grouped = entries.select { |row| key(row) }.group_by { |row| key(row) }
        owned = live.group_by do |product|
          key('activity_id' => product.get_attribute('MH_CAD2Module', 'activity_id'),
              'code' => product.get_attribute('MH_CAD2Module', 'code'))
        end
        (grouped.keys | owned.keys).compact.map do |identity|
          events = grouped[identity] || []
          last = events.last || {}
          products = owned[identity] || []
          product = products.first if products.length == 1
          code = last['code'] || product&.get_attribute('MH_CAD2Module', 'code')
          automatic = code.to_s.start_with?('SCAN-') || events.any? { |e| e['automatic_scan'] }
          title = product&.get_attribute('MH_CAD2Module', 'plan_title') || last['plan_title']
          label = automatic ? 'Vừa quét SP không có mã' : "Sản phẩm #{code}"
          label += " · #{title}" if title && !title.empty?
          { 'key' => identity, 'code' => code, 'label' => label,
            'automatic_scan' => automatic, 'time' => last['time'], 'status' => last['status'],
            'last_error' => events.reverse.find { |e| e['error'] }&.fetch('error'),
            'event_count' => events.length, 'product_id' => product&.persistent_id,
            'library' => product&.get_attribute('MH_CAD2Module', 'library') || last['_library'] || root,
            'available' => !!product, 'ambiguous' => products.length > 1 }
        end.sort_by { |row| [row['time'].to_s, row['key']] }.reverse
      end

      def read_event(root, row)
        file = row.fetch('file')
        raise ArgumentError, 'Đường dẫn hồ sơ không hợp lệ.' unless File.basename(file) == file
        path = File.join(root, 'history', file)
        @events ||= {}
        stamp = [File.mtime(path).to_f, File.size(path)]
        cached = @events[path]
        return cached[:event] if cached && cached[:stamp] == stamp
        event = JSON.parse(File.read(path, encoding: 'UTF-8'))
        raise JSON::ParserError, 'Hồ sơ không phải một sự kiện.' unless event.is_a?(Hash)
        @events[path] = { stamp: stamp, event: event }
        event
      rescue JSON::ParserError, SystemCallError => error
        { 'id' => row['id'], 'kind' => 'unreadable', 'error' => "Không đọc được hồ sơ: #{error.message}" }
      end

      def events(root, identity)
        entries = indexes(root)
        chosen = entries.select { |row| key(row) == identity }.map { |row| read_event(root, row) }
        sessions = chosen.filter_map { |event| event['session'] }.uniq
        # Older edit indexes did not include a product code. Bind only by an
        # explicit correction session, never by a similar geometry signature.
        entries.reject { |row| key(row) }.each do |row|
          event = read_event(root, row)
          chosen << event if event['session'] && sessions.include?(event['session'])
        end
        chosen.uniq { |event| event['id'] }.sort_by { |event| [event['time'].to_s, event['id'].to_s] }
      end

      def compact_event(event)
        result = event.slice('id', 'time', 'kind', 'status', 'reason', 'error', 'code', 'job_id', 'session',
                             'source_hash', 'signature', 'skp', 'before', 'after', 'model_path')
        analysis = event['analysis']
        if analysis
          result['analysis'] = analysis.slice('code', 'name', 'automatic_scan', 'status', 'error', 'source_path',
                                             'source_hash', 'signature', 'bounds', 'build_stages', 'placement', 'source_cache', 'worker_timing', 'processing_from_cache', 'current_replay_seconds',
                                             'plan_origin_offset_mm', 'envelope_preview', 'plan_evidence', 'learning', 'local_ai', 'explanation', 'modules', 'trim_parts', 'panel_parts', 'plan_engine', 'processing_times', 'native_times', 'view_analysis')
          result['analysis']['geometry_pipeline'] = analysis['geometry_pipeline'].slice('oy_sweep', 'directional_layout') if analysis['plan_engine'] == 'oy-stock-sweep-v1'
          if analysis['plan_engine'] == 'section-first-v1'
            result['analysis']['geometry_pipeline'] = analysis['geometry_pipeline'].slice('mode', 'order', 'horizontal')
            result['analysis'].merge!(analysis.slice('height_source', 'elevation_pending', 'warnings'))
          end
        end
        result
      end

      def detail(root, row, live)
        product = live.find { |item| item.persistent_id.to_s == row['product_id'].to_s } if row['product_id']
        history = events(root, row['key'])
        analysis = if product
                     JSON.parse(product.get_attribute('MH_CAD2Module', 'analysis'))
                   else
                     history.reverse.find { |event| event['analysis'] }&.fetch('analysis')
                   end
        row.merge('events' => history.map { |event| compact_event(event) }, 'analysis' => analysis)
      end
    end
  end
end

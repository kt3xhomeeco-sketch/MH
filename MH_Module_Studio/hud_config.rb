# encoding: UTF-8
require_relative 'library_catalog'

module MH
  module ModuleStudio
    # JSON layout data only. No native model access and no imported code.
    module HUDConfig
      extend self
      FORMAT='mh_module_hud_config'.freeze
      MAX_BYTES=4*1024*1024
      KEYS=%w[folder view thumbnail_size hud_size hud_spacing hud_image_zoom hud_position hud_orders folder_keys hud_board_version hud_boards hud_board].freeze

      def capture(catalog)
        {'root_identity'=>catalog['folders'].find { |row| row['id']=='' }&.fetch('identity',nil),
         'folders'=>catalog['folders'].map { |row| row.slice('id','identity') },
         'entries'=>catalog['entries'].map { |row| row.slice('id','folder','identity','sha256') }}
      end

      def document(settings,catalog)
        {'format'=>FORMAT,'version'=>1,'settings'=>LibraryCatalog.settings(settings).slice(*KEYS),'library'=>capture(catalog)}
      end

      def parse(raw)
        raise Core::Error,'Config HUD vượt 4 MB.' unless raw.is_a?(String) && raw.bytesize<=MAX_BYTES
        data=JSON.parse(raw)
        unless data.is_a?(Hash) && data['format']==FORMAT && data['version']==1 && data['settings'].is_a?(Hash)
          raise Core::Error,'Không hỗ trợ định dạng config HUD này.'
        end
        validate_catalog!(data['library'])
        data['settings']=LibraryCatalog.settings(data['settings']).slice(*KEYS)
        data
      rescue JSON::ParserError
        raise Core::Error,'Không đọc được JSON config HUD.'
      end

      def relative?(id,empty: false)
        id.is_a?(String) && id.length<=2000 && (empty || !id.empty?) &&
          !id.start_with?('/','\\') && !id.include?('\\') && !id.include?(':') &&
          !id.split('/').any? { |part| %w[. ..].include?(part) }
      end

      def validate_catalog!(data)
        unless data.is_a?(Hash) && (!data['root_identity'] || data['root_identity'].is_a?(String) && data['root_identity'].length<=256) &&
               %w[folders entries].all? { |key| data[key].is_a?(Array) && data[key].length<=5000 }
          raise Core::Error,'Danh sách nhận diện trong config HUD không hợp lệ.'
        end
        %w[folders entries].each do |key|
          rows=data[key]
          unless rows.all? do |row|
            row.is_a?(Hash) && relative?(row['id'],empty:key=='folders') &&
              (!row['identity'] || row['identity'].is_a?(String) && row['identity'].length<=256) &&
              (!row['sha256'] || row['sha256'].is_a?(String) && row['sha256'].match?(/\A[0-9a-f]{64}\z/)) &&
              (key=='folders' || relative?(row['folder'],empty:true))
          end
            raise Core::Error,'Mục nhận diện file/folder trong config HUD không hợp lệ.'
          end
          raise Core::Error,'Config HUD có mục trùng ID.' unless rows.map { |row| row['id'] }.uniq.length==rows.length
        end
        data
      end

      def unique_index(rows,key)
        rows.reject { |row| row[key].to_s.empty? }.group_by { |row| row[key] }.filter_map { |value,items| [value,items.first] if items.length==1 }.to_h
      end

      def remap(settings,previous,catalog)
        previous ||= {'folders'=>[],'entries'=>[]}
        old_entries=previous.fetch('entries',[])
        entries=catalog['entries'];by_id=entries.to_h { |row| [row['id'],row] }
        folders=catalog['folders'];folder_ids=folders.map { |row| row['id'] }
        same_root=previous['root_identity'] && previous['root_identity']==folders.find { |row| row['id']=='' }&.fetch('identity',nil)
        identities=same_root ? unique_index(entries,'identity') : {}
        hashes=unique_index(entries,'sha256')
        old_hashes=unique_index(old_entries,'sha256')
        file_map=old_entries.filter_map do |row|
          found=identities[row['identity']] || by_id[row['id']]
          found ||= hashes[row['sha256']] if old_hashes.key?(row['sha256'])
          [row['id'],found['id']] if found
        end.to_h
        folder_identities=same_root ? unique_index(folders,'identity') : {}
        folder_map={''=>''}
        previous.fetch('folders',[]).each do |row|
          next if row['id']==''
          found=folder_identities[row['identity']]
          name=found ? found['id'] : folder_ids.include?(row['id']) ? row['id'] : nil
          unless name
            candidates=old_entries.filter_map do |item|
              next unless file_map[item['id']] && (item['folder']==row['id'] || item['folder'].start_with?(row['id']+'/'))
              levels=item['folder'].split('/').length-row['id'].split('/').length
              current=by_id.fetch(file_map[item['id']])['folder'].split('/')
              current.first(current.length-levels).join('/') if current.length>=levels
            end.uniq
            name=candidates.first if candidates.length==1
          end
          folder_map[row['id']]=name if name && folder_ids.include?(name)
        end
        result=LibraryCatalog.settings(settings)
        resolve_folder=->(id) { folder_map[id] || (folder_ids.include?(id) ? id : nil) }
        result['folder']=resolve_folder.call(result['folder']) || ''
        result['folder_keys']=result['folder_keys'].filter_map { |id,key| [resolve_folder.call(id),key] if resolve_folder.call(id) }.to_h
        missing=[];orders={}
        result['hud_orders'].each do |folder,ids|
          mapped=resolve_folder.call(folder)
          unless mapped
            missing.concat(ids);next
          end
          orders[mapped] ||= []
          ids.each do |id|
            found=file_map[id] || (by_id.key?(id) ? id : nil)
            found ? orders[mapped] << found : missing << id
          end
          orders[mapped].uniq!
        end
        result['hud_boards'].each do |board|
          resolve=->(id) do
            next unless id
            found=file_map[id] || (by_id.key?(id) ? id : nil)
            missing << id unless found
            found
          end
          board['slots'].map! { |id| resolve.call(id) }
          board['docks'].each_value { |ids| ids.map! { |id| resolve.call(id) } }
          board['free']=board['free'].filter_map { |id,position| found=resolve.call(id);[found,position] if found }.to_h
          board['shortcuts']=board['shortcuts'].filter_map { |id,key| found=resolve.call(id);[found,key] if found }.to_h
        end
        result['hud_orders']=orders
        [LibraryCatalog.settings(result),missing.uniq]
      end
    end
  end
end

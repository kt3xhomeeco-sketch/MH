# encoding: UTF-8
module MH
  module ModuleStudio
    # Sparse, explicit icon slots. Library folder browsing never fills a board.
    module HUDBoards
      extend self
      FIELDS=%w[hud_board_version hud_boards hud_board].freeze
      DOCKS=%w[top bottom left right].freeze
      def normalize(settings)
        boards=settings['hud_boards']
        unless [1,2].include?(settings['hud_board_version'])
          boards=settings.fetch('hud_orders',{}).map.with_index do |(folder,ids),index|
            {'id'=>"legacy-#{index}",'name'=>folder.empty? ? 'Library' : folder,
             'key'=>settings.fetch('folder_keys',{})[folder].to_s,'slots'=>ids.first(128)+Array.new(ids.empty? ? 8 : (8-ids.length%8)%8)}
          end
        end
        unless boards.is_a?(Array) && boards.length<=64
          raise Core::Error,'Tối đa 64 bảng icon HUD.'
        end
        boards=Core.copy_data(boards)
        boards.each do |board|
          unless board.is_a?(Hash) && board['id'].is_a?(String) && board['id'].match?(/\A[\w-]{1,80}\z/) &&
                 board['name'].is_a?(String) && !board['name'].strip.empty? && board['name'].length<=80 &&
                 board['key'].is_a?(String) && board['key'].match?(/\A[A-Za-z]?\z/) &&
                 board['slots'].is_a?(Array) && board['slots'].length.between?(8,128) && (board['slots'].length%8).zero? &&
                 board['slots'].all? { |id| id.nil? || id.is_a?(String) && !id.empty? && id.length<=2000 }
            raise Core::Error,'Bảng HUD cần tên, phím A–Z và các ô icon hợp lệ.'
          end
          board['docks']||=DOCKS.to_h { |zone| [zone,[]] }
          board['shortcuts']||={}
          unless board['docks'].is_a?(Hash) && board['docks'].keys.sort==DOCKS.sort && DOCKS.all? { |zone| valid_slots?(board['docks'][zone],64) } && board['shortcuts'].is_a?(Hash)
            raise Core::Error,'Dải icon hoặc phím số HUD không hợp lệ.'
          end
          board['name']=board['name'].strip;board['key']=board['key'].upcase
          ids=all_ids(board)
          raise Core::Error,'Icon bị lặp trong cùng một bảng.' unless ids.uniq.length==ids.length
          board['shortcuts'].select! { |id,_key| ids.include?(id) }
          digits=board['shortcuts'].values
          raise Core::Error,'Phím icon phải là một số 0–9 và không được trùng trong bảng.' unless digits.all? { |key| key.is_a?(String) && key.match?(/\A[0-9]\z/) } && digits.uniq.length==digits.length
        end
        keys=boards.map { |b| b['key'] }.reject(&:empty?)
        raise Core::Error,'Tên, ID hoặc phím tắt của bảng HUD bị trùng.' unless boards.map { |b| b['id'] }.uniq.length==boards.length && keys.uniq.length==keys.length && boards.map { |b| b['name'].downcase }.uniq.length==boards.length
        active=settings['hud_board']
        active=boards.first&.fetch('id','') || '' unless boards.any? { |b| b['id']==active }
        settings.merge('hud_board_version'=>2,'hud_boards'=>boards,'hud_board'=>active)
      end
      def valid_slots?(slots,maximum)
        slots.is_a?(Array) && slots.length<=maximum && slots.all? { |id| id.nil? || id.is_a?(String) && id.length.between?(1,2000) }
      end
      def all_ids(board)
        (board['slots']+board.fetch('docks',{}).values.flatten).compact
      end
      def slots(board,zone)
        return board['slots'] if zone=='ring'
        raise Core::Error,'Dải HUD không hợp lệ.' unless DOCKS.include?(zone)
        board['docks'][zone]
      end
      def current(settings,id=settings['hud_board'])
        settings.fetch('hud_boards',[]).find { |board| board['id']==id }
      end
      def entries(entries,settings,query='')
        lookup=entries.to_h { |entry| [entry['id'],entry] }
        current(settings)&.fetch('slots')&.map do |id|
          item=lookup[id]
          item if item && fold(item['name']).include?(fold(query))
        end || []
      end
      def fold(value)
        value.to_s.downcase.unicode_normalize(:nfd).gsub(/\p{Mn}/,'').tr('đ','d')
      end
      def put(settings,id,index,board_id,zone: 'ring')
        result=Core.copy_data(settings);board=current(result,board_id)
        raise Core::Error,'Tạo và chọn bảng icon trong Edit trước.' unless board
        target=slots(board,zone)
        maximum=zone=='ring' ? target.length : 64
        raise Core::Error,'Ô icon không hợp lệ.' unless index.is_a?(Integer) && index.between?(0,maximum-1)
        source=([board['slots']]+board['docks'].values).find { |list| list.include?(id) }
        source[source.index(id)]=target[index] if source
        target.fill(nil,target.length...index) if index>target.length
        target[index]=id
        normalize(result)
      end
      def edit(settings,action,data)
        result=Core.copy_data(settings);board=current(result,data['id'])
        if %w[create update].include?(action) && !data['key'].to_s.match?(/\A[A-Za-z]\z/)
          raise Core::Error,'Nhập một phím A–Z cho bảng icon.'
        end
        case action
        when 'create'
          result['hud_boards'] << {'id'=>data.fetch('id'),'name'=>data.fetch('name'),'key'=>data.fetch('key'),'slots'=>Array.new(8)}
          result['hud_board']=data['id']
        when 'update'
          raise Core::Error,'Bảng HUD không còn tồn tại.' unless board
          board['name']=data.fetch('name');board['key']=data.fetch('key')
        when 'delete'
          result['hud_boards'].delete(board)
        when 'page'
          raise Core::Error,'Bảng HUD không còn tồn tại.' unless board
          board['slots']+=Array.new(8)
        when 'clear'
          list=board && slots(board,data.fetch('zone','ring'))
          raise Core::Error,'Ô icon không hợp lệ.' unless list && data['slot'].is_a?(Integer) && data['slot'].between?(0,list.length-1)
          list[data['slot']]=nil
        when 'shortcut'
          raise Core::Error,'Icon không còn trong bảng.' unless board && all_ids(board).include?(data['entry'])
          digit=data.fetch('digit').to_s.strip
          if digit.empty?
            board['shortcuts'].delete(data['entry'])
          else
            board['shortcuts'][data['entry']]=digit
          end
        else
          raise Core::Error,'Thao tác Edit HUD không hợp lệ.'
        end
        normalize(result)
      end
      # Nearest angular sector outside the central dead zone. Controls get first priority.
      def direction(layout,x,y)
        cx,cy=layout['center'];dx=x-cx;dy=y-cy
        return if Math.hypot(dx,dy)<=layout['size']*0.62
        ((Math.atan2(dy,dx)+Math::PI/2)/(Math::PI/4)).round%8
      end
    end
  end
end

# encoding: UTF-8
require_relative 'library'
require_relative 'hud_input'
require_relative 'hud_thumbnail'

module MH
  module ModuleStudio
    # One Tool owns browsing and placement; no switch to place_component/native Move.
    class LibraryHUD
      attr_reader :query, :pending, :active, :error, :editing

      def initialize(library, pending = nil)
        @library = library
        @model = Sketchup.active_model
        @pending = pending
        @query = ''
        @page = 0
        @folders = false
        @textures = {}
        @texture_aspects = {}
        @image_jobs = {}
        @active = false
        @editing = false
        @input = Sketchup::InputPoint.new
        @placement = nil
      end

      def activate
        @active = true
        HUDInput.start(self)
        pointer = HUDInput.cursor(@model.active_view)
        @cursor_anchor = [pointer['x'], pointer['y']] if pointer && pointer['over']
        refresh
        MH::ModuleStudio.instance_variable_get(:@module_options)&.schedule_refresh
      rescue StandardError => detail
        fail_session(detail)
      end

      def refresh
        return unless @active
        @items = if @folders
                   needle = LibraryCatalog.fold(@query)
                   @library.config.fetch('hud_boards',[]).select { |board| LibraryCatalog.fold(board['name']).include?(needle) }
                 else
                   HUDBoards.entries(@library.catalog['entries'], hud_settings, @query)
                 end
        @page = [[@page, 0].max, page_count - 1].min
        load_textures
        Sketchup.status_text = @pending ? (@replace_mode ? 'MH Replace: click các khối cần thay liên tục · Esc: về Library · Space: thoát' : 'MH Library: click đặt theo liên kết · Shift: Fit không liên kết · Ctrl + click: Replace liên tục · Esc: chọn mẫu khác · Space: thoát') : 'MH HUD: chữ để tìm · phím số đã gán: chọn icon · Click giữa đổi bảng · Esc / Space thoát'
        @model.active_view.invalidate
        send_settings if @settings
      end

      def page_count
        [(@items.length / 8.0).ceil, 1].max
      end

      def catalog_changed
        clear_drag
        @edit_folder = @library.config['hud_board'] if @editing
        @pending = nil
        @placement = nil
        @placement_mouse = nil
        @query = ''
        @page = 0
        @folders = false
        refresh
      end

      def catalog_busy?
        !!(@pending || @drag_target || @external_drag)
      end

      def catalog_updated
        @edit_folder = @library.config['hud_board'] if @editing && !HUDBoards.current(@library.config,@edit_folder)
        refresh
      end

      def page_items
        @items.slice(@page * 8, 8) || []
      end

      def load_textures
        view = @model.active_view
        @image_jobs ||= {}
        needed = @folders ? [] : texture_items.map { |item| @library.thumbnail_key(item) }
        @image_jobs.select! { |key,_path| needed.include?(key) }
        (@textures.keys - needed).each do |key|
          view.release_texture(@textures.delete(key))
          @texture_aspects.delete(key)
        end
        return if @folders
        texture_items.each do |item|
          key = @library.thumbnail_key(item)
          next if @textures.key?(key)
          image = HUDThumbnail.cached_image(key)
          unless image
            path = @library.preview_thumbnail(item)
            next unless path
            image = Sketchup::ImageRep.new(path)
            @image_jobs[key] = item
          end
          @textures[key] = view.load_texture(image)
          @texture_aspects[key] = image.width.to_f / image.height
        end
        schedule_image_job
      end

      def texture_items
        board=HUDBoards.current(hud_settings)
        docked=board ? board['docks'].values.flatten.compact : []
        page_items.compact+@library.catalog['entries'].select { |item| docked.include?(item['id']) }
      end

      def schedule_image_job
        return unless @active && !@pending && !@image_timer && @image_jobs && !@image_jobs.empty?
        return unless Sketchup.active_model.equal?(@model)
        @image_timer = UI.start_timer(0.03,false) do
          @image_timer = nil
          process_image_job
        end
      end

      def process_image_job
        return unless @active && !@pending && Sketchup.active_model.equal?(@model)
        key,item = @image_jobs.shift
        return unless key && @textures.key?(key)
        path = @library.thumbnail(item)
        return unless path
        image = HUDThumbnail.prepare(Sketchup::ImageRep.new(path))
        HUDThumbnail.cache_image(key,image)
        view = @model.active_view
        texture = view.load_texture(image)
        view.release_texture(@textures[key])
        @textures[key] = texture
        @texture_aspects[key] = image.width.to_f/image.height
        view.invalidate
      rescue StandardError => detail
        # Retain the immediately displayed raw image if enhancement fails.
        (@image_failures ||= {})[key] = detail.message
      ensure
        schedule_image_job
      end

      def cancel_image_jobs
        UI.stop_timer(@image_timer) if @image_timer
        @image_timer = nil
        @image_jobs&.clear
      end

      def deactivate(view)
        @active = false
        cancel_image_jobs
        HUDInput.stop(self)
        clear_drag
        @editing = false
        @pending = nil
        @placement = nil
        @placement_mouse = nil
        @textures.each_value { |texture| view.release_texture(texture) }
        @textures.clear
        @texture_aspects.clear
        @settings&.close
        @settings = nil
        @library.tool_closed(self)
        @library.publish
        MH::ModuleStudio.instance_variable_get(:@module_options)&.schedule_refresh
        Sketchup.status_text = ''
        view.invalidate
      end

      def suspend(view)
        view.invalidate
      end

      def resume(view)
        refresh
        view.invalidate
      end

      def finish
        return unless @active
        @pending = nil
        @model.select_tool(nil) if Sketchup.active_model.equal?(@model)
        deactivate(@model.active_view) if @active
      end

      def onCancel(reason, view)
        if reason == 2 || (reason == 0 && @pending)
          cancel_placement(view)
        else
          finish
        end
      end

      def cancel_placement(view)
        @pending = nil
        @replace_mode = false
        @placement = nil
        @placement_mouse = nil
        @placement_error = nil
        @hover = nil
        @error = nil
        @input.clear
        view.tooltip = ''
        refresh
      end

      def onKeyDown(key, repeat, flags, view)
        return true unless @active
        if [16,17].include?(key)
          mask=key==17 ? COPY_MODIFIER_MASK : CONSTRAIN_MODIFIER_MASK
          update_placement(view,*@last_mouse,flags|mask) if @pending && @last_mouse
          view.invalidate
          return true
        end
        if key==27
          return true if repeat>1
          @pending ? cancel_placement(view) : finish
          return true
        end
        if key==32
          finish
          return true
        end
        return true if @pending || repeat > 1
        if key.between?(65, 90)
          letter = key.chr
          board = @library.config.fetch('hud_boards',[]).find { |row| row['key']==letter }
          if board
            choose_folder(board['id'])
          else
            @query += letter.downcase if @query.length < 80
            @page = 0
            refresh
          end
        elsif key.between?(48,57) || key.between?(96,105)
          unless @editing || @folders
            digit=(key>=96 ? key-96 : key-48).to_s
            id=HUDBoards.current(hud_settings)&.fetch('shortcuts',{})&.key(digit)
            item=@library.catalog['entries'].find { |row| row['id']==id } if id
            choose(item,replace:(flags&COPY_MODIFIER_MASK)!=0) if item
          end
        elsif key == 8
          @query = @query[0...-1]
          @page = 0
          refresh
        elsif [37, 33, 39, 34].include?(key)
          page(key == 37 || key == 33 ? -1 : 1)
        elsif key == 9
          @folders = !@folders
          @query = ''
          @page = 0
          refresh
        elsif key == 13
          choose(page_items.compact.first)
        end
        view.invalidate if @active
        true
      rescue StandardError => detail
        fail_session(detail)
        true
      end

      def onKeyUp(key, _repeat, flags, view)
        if [16,17].include?(key)
          mask=key==17 ? COPY_MODIFIER_MASK : CONSTRAIN_MODIFIER_MASK
          update_placement(view,*@last_mouse,flags&~mask) if @pending && @last_mouse
          view.invalidate
        end
        true
      end

      def page(delta)
        clear_drag
        @page = (@page + delta) % page_count
        refresh
      end

      def choose_folder(id)
        clear_drag
        @edit_folder = id if @editing
        @library.save_settings('hud_board' => id)
        @folders = false
        @page = 0
        @query = ''
        @pending = nil
        @error = nil
        refresh
        @library.publish
      end

      def choose(item, replace: false)
        return unless item
        return if @editing && !@folders
        if @folders
          choose_folder(item['id'])
        else
          targets=LibraryPlacement.selected_targets(@model) unless @model.selection.empty?
          @pending = @library.preview(item['id'])
          @replace_mode = replace || !targets.nil?
          if targets
            result=LibraryPlacement.replace_many(@library,@pending,targets)
            @library.publish("Đã Replace #{result.length} đối tượng. Esc: về Library.")
          end
          @placement = nil
          @placement_mouse = nil
          @input.clear
          @error = nil
          refresh
        end
      rescue StandardError => detail
        @pending = nil
        @error = detail.message
        refresh
      end

      def geometry(view)
        anchor = @library.config['hud_position'] == 'cursor' ? @cursor_anchor : nil
        ring=LibraryCatalog.layout(view.vpwidth.to_f, view.vpheight.to_f, @library.config['hud_size'], center: anchor,spacing:@library.config.fetch('hud_spacing',100))
        HUDLayout.compose(view.vpwidth.to_f,view.vpheight.to_f,ring,@folders ? nil : HUDBoards.current(hud_settings),editing:@editing && !@folders)
      end

      def hit(x, y, view)
        return nil if @pending
        layout = geometry(view)
        dock=HUDLayout.dock_hit(layout,HUDBoards.current(hud_settings),x,y,editing:@editing) unless @folders
        return dock if dock
        cx, cy = layout['center']
        radius = layout['size'] * 0.5
        return [:center, nil] if Math.hypot(x - cx, y - cy) <= radius
        layout['items'].each_with_index do |(px, py), index|
          return [:item, index] if (page_items[index] || @editing) && Math.hypot(x - px, y - py) <= radius
        end
        extent = layout['radius'] + radius
        if page_count>1 && (y - (cy + extent + 25)).abs < 17
          nav = [70, extent * 0.7].min
          return [:previous, nil] if (x - cx + nav).abs < 20
          return [:next, nil] if (x - cx - nav).abs < 20
        end
        unless @editing
          index=HUDBoards.direction(layout,x,y)
          return [:item,index] if index && page_items[index]
        end
        nil
      end

      def target_item(target)
        return unless target
        return page_items[target[1]] if target[0]==:item
        return unless target[0]==:dock
        zone,index=target[1];id=HUDBoards.current(hud_settings)&.dig('docks',zone,index)
        @library.catalog['entries'].find { |entry| entry['id']==id } if id
      end

      def target_location(target)
        target[0]==:dock ? target[1] : ['ring',drop_index(target[1])]
      end

      def move_to_target(item,target)
        return unless item && target && %i[item dock].include?(target[0])
        zone,index=target_location(target)
        @library.move_hud_item(item['id'],index,folder:hud_folder,zone:zone)
      end

      def assign_shortcut(item)
        return unless item
        board=HUDBoards.current(hud_settings)
        values=UI.inputbox(['Phím số 0–9 (để trống để bỏ)'],[board['shortcuts'].fetch(item['id'],'')],item['name'])
        return unless values
        @library.edit_hud_board('shortcut',{'id'=>hud_folder,'entry'=>item['id'],'digit'=>values.first.to_s})
      rescue Core::Error=>detail
        UI.messagebox(detail.message)
      end

      def replacement?(flags)
        (flags&COPY_MODIFIER_MASK)!=0 || (@replace_mode && (flags&CONSTRAIN_MODIFIER_MASK).zero?)
      end

      def update_placement(view,x,y,flags)
        @placement_error = nil
        @placement_data=@pending
        template=@pending && @pending['import_template']
        @placement = if replacement?(flags)
                       LibraryPlacement.detect(view,x,y,replace:true)
                     elsif (flags&CONSTRAIN_MODIFIER_MASK)!=0
                       LibraryPlacement.detect(view,x,y,cache:(@link_cache||={}))
                     elsif template && template['enabled']
                       ImportLinks.detect(@pending,view,x,y,cache:(@link_cache||={}))
                     end
        if @placement && @library
          @placement_data,@placement=@library.resolve_fit(@pending,@placement)
          if @placement['mode']=='template' && @placement_data['entry_id']!=@pending['entry_id']
            @placement=ImportLinks.detect(@placement_data,view,x,y,cache:(@link_cache||={}))
          end
        end
      rescue Core::Error => detail
        @placement = nil
        @placement_error = detail.message
      end

      def onMouseMove(flags, x, y, view)
        @last_mouse = [x, y]
        @hover = hit(x, y, view)
        if @drag_target && Math.hypot(x - @drag_start[0], y - @drag_start[1]) > 4
          @dragging = true
          @drag_cursor = [x, y]
        end
        if @pending && !@hover
          @input.pick(view, x, y)
          previous = @placement_mouse
          if !previous || Math.hypot(x-previous[0],y-previous[1])>=4 || (flags&(COPY_MODIFIER_MASK|CONSTRAIN_MODIFIER_MASK))!=previous[2]
            update_placement(view,x,y,flags)
            @placement_mouse = [x,y,flags&(COPY_MODIFIER_MASK|CONSTRAIN_MODIFIER_MASK)]
          end
          view.tooltip = @placement_error || (@placement ? (@placement['mode']=='replace' ? 'Ctrl + click: thay module này' : @placement['mode']=='template' ? "#{@placement['kind']=='inside' ? 'Lọt trong' : 'Đối mặt'} · #{@placement['matches'].length} mặt liên kết" : 'Click: Fit vừa khoang, không tạo liên kết') : ((flags&CONSTRAIN_MODIFIER_MASK)!=0 ? 'Shift: ngoài khoang, giữ kích thước mẫu' : 'Không có liên kết: giữ kích thước mẫu'))
        else
          @input.clear
          item = target_item(@hover)
          view.tooltip = @error || (item ? item['name'] : '')
        end
        view.invalidate
      rescue StandardError => detail
        fail_session(detail)
      end

      def onLButtonDown(flags, x, y, view)
        target = hit(x, y, view)
        if target
          case target[0]
          when :item, :dock
            if @editing && !@folders && target_item(target)
              @drag_target = target
              @drag_item = target_item(target)
              @drag_start = [x, y]
            else
              choose(target_item(target),replace: !@folders && (flags&COPY_MODIFIER_MASK)!=0)
            end
          when :center
            return set_editing(false) if @editing
            @folders = !@folders
            @query = ''
            @page = 0
            refresh
          when :previous then page(-1)
          when :next then page(1)
          end
        elsif @pending && !@editing
          @input.pick(view, x, y)
          update_placement(view,x,y,flags)
          raise Core::Error,@placement_error if @placement_error
          raise Core::Error,'Ctrl + click lên module cần thay.' if replacement?(flags) && !@placement
          return unless @input.valid? || @placement
          replacing=@placement && @placement['mode']=='replace'
          @library.place(@placement_data || @pending,@input.valid? ? @input.position : ORIGIN,placement:@placement)
          @error = nil
          if replacing
            @replace_mode=true;@placement=nil;@placement_mouse=nil
            @input.clear;refresh
          else
            finish
          end
        end
      rescue StandardError => detail
        @pending = nil unless @replace_mode
        @placement = nil
        @placement_mouse = nil
        @error = detail.message
        refresh
      end

      def onLButtonUp(_flags, x, y, view)
        if @editing && @drag_target
          if @dragging
            move_to_target(@drag_item,hit(x,y,view))
          else
            assign_shortcut(@drag_item)
          end
        end
      rescue StandardError => detail
        @error = detail.message
      ensure
        clear_drag
        refresh
      end

      def clear_drag
        @drag_target = @drag_item = @drag_start = @drag_cursor = @external_drag = nil
        @dragging = false
      end

      def drag_active?
        !@external_drag.nil?
      end

      def hud_folder
        @editing ? @edit_folder : @library.config['hud_board']
      end

      def hud_settings
        @library.config.merge('hud_board' => hud_folder)
      end

      def drop_index(slot)
        @page * 8 + slot
      end

      def set_editing(enabled)
        @edit_folder = @library.config['hud_board'] if enabled && !@editing
        @editing = enabled == true
        @pending = nil
        @folders = false
        @query = ''
        @cursor_anchor ||= @last_mouse
        clear_drag
        refresh
        @library.publish
      end

      def begin_external_drag(id, root, token)
        raise Core::Error, 'Thư viện đã đổi. Kéo lại module từ Library hiện tại.' unless @editing && !@folders && root == @library.catalog['root']
        raise Core::Error, 'Phiên kéo không hợp lệ.' unless token.is_a?(String) && token.length.between?(1, 120)
        @library.entry(id)
        raise Core::Error,'Tạo và chọn bảng icon trong Cài đặt HUD → Edit trước.' unless HUDBoards.current(@library.config,hud_folder)
        clear_drag
        @external_drag = { 'id' => id, 'root' => root, 'token' => token, 'held' => false, 'started' => Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @library.publish
      end

      def poll_drag(pointer)
        return unless @external_drag
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) - @external_drag['started'] > 60
          clear_drag
          return
        end
        unless pointer
          clear_drag if Process.clock_gettime(Process::CLOCK_MONOTONIC) - @external_drag['started'] > 15
          return
        end
        @external_drag['held'] ||= pointer['left']
        @drag_cursor = pointer['over'] ? [pointer['x'], pointer['y']] : nil
        @hover = @drag_cursor && hit(*@drag_cursor, @model.active_view)
        if @external_drag['held'] && !pointer['left']
          end_external_drag
        else
          @model.active_view.invalidate
        end
      end

      def end_external_drag(token = nil)
        return unless @external_drag
        return if token && token != @external_drag['token']
        complete_external_drag
      end

      def cancel_external_drag(token)
        return unless @external_drag && token == @external_drag['token']
        clear_drag
        refresh
      end

      def complete_external_drag
        pointer = HUDInput.cursor(@model.active_view)
        drag = @external_drag
        if @active && @editing && pointer && !pointer['left'] && pointer['over'] && drag['root'] == @library.catalog['root']
          target = hit(pointer['x'], pointer['y'], @model.active_view)
          move_to_target({'id'=>drag['id']},target)
        end
      rescue StandardError => detail
        @error = detail.message
      ensure
        clear_drag
        refresh
      end

      def getMenu(menu, *_coordinates)
        menu.add_item('Cài đặt HUD…') { show_settings }
        menu.add_item(@editing ? 'Kết thúc Edit HUD' : 'Edit HUD · Sắp xếp icon') { set_editing(!@editing);show_settings if @editing }
        if @editing && !@folders && target_item(@hover)
          zone,slot=target_location(@hover)
          clear_target={'id'=>hud_folder,'slot'=>slot,'zone'=>zone}
          menu.add_item('Xóa icon khỏi ô này') { @library.edit_hud_board('clear',clear_target) }
        end
        menu.add_item('Chọn folder thư viện…') do
          @library.request('action' => 'library_choose')
          @query = ''
          @page = 0
          refresh
          Sketchup.focus
        end
        menu.add_separator
        menu.add_item('Thoát HUD (Esc / Space)') { finish }
      end

      def fail_session(detail)
        @error = detail.message
        @library.publish(@error, error: true)
        finish
      end

      def circle(view, cx, cy, radius, fill, border = '#c3cdd1')
        points = 48.times.map { |i| angle = i * Math::PI / 24; Geom::Point3d.new(cx + radius * Math.cos(angle), cy + radius * Math.sin(angle), 0) }
        if fill
          view.drawing_color = fill
          view.draw2d(GL_POLYGON, points)
        end
        view.drawing_color = border
        view.line_width = 1
        view.draw2d(GL_LINE_LOOP, points)
      end

      def text(view, x, y, value, color = '#34444b', size = 11, center: true)
        options = { color: color, size: size, font: 'Segoe UI' }
        options[:align] = TextAlignCenter if center
        view.draw_text(Geom::Point3d.new(x, y, 0), value, options)
      end

      def draw_thumbnail(view, x, y, size, texture, aspect = 1.0, zoom = 100)
        vertices,coordinates = HUDThumbnail.mesh(aspect,size,zoom)
        points = vertices.map { |dx,dy| Geom::Point3d.new(x+dx,y+dy,0) }
        uvs = coordinates.map { |u,v| Geom::Point3d.new(u,v,0) }
        view.drawing_color = '#ffffff'
        view.draw2d(GL_TRIANGLES, points, texture: texture, uvs: uvs)
      end

      def draw_icon(view,point,item,target,size)
        x,y=point;selected=@hover==target
        circle(view,x,y,size/2.0,selected ? '#329fa4' : '#ffffff',selected ? '#00616b' : '#b9c6cb')
        unless item
          text(view,x,y-7,'+','#008b90',[size*0.35,16].min)
          return
        end
        key=@library.thumbnail_key(item) unless @folders
        texture=@textures[key]
        if texture && !@folders
          draw_thumbnail(view,x,y,size,texture,@texture_aspects.fetch(key,1.0),@library.config.fetch('hud_image_zoom',100))
        else
          label=@folders ? item['name'] : 'SKP'
          text(view,x,y-7,label[0,[size/6,13].min.to_i],'#3e6268',[size*0.22,10].min)
        end
        circle(view,x,y,size/2.0,Sketchup::Color.new(0,105,115,105),'#00616b') if selected
        digit=HUDBoards.current(hud_settings)&.dig('shortcuts',item['id']) unless @folders
        if digit
          badge=[size*0.14,10].min
          circle(view,x-size*0.32,y-size*0.32,badge,'#00747c','#00747c')
          text(view,x-size*0.32,y-size*0.32-badge*0.75,digit,'#ffffff',[size*0.22,9].min)
        end
      end

      def draw_dock_bar(view,points,size)
        pad=size/2.0+3
        left=points.map(&:first).min-pad;right=points.map(&:first).max+pad
        top=points.map(&:last).min-pad;bottom=points.map(&:last).max+pad
        corners=[[left,top],[right,top],[right,bottom],[left,bottom]].map { |x,y| Geom::Point3d.new(x,y,0) }
        view.drawing_color=Sketchup::Color.new(244,247,248,225);view.draw2d(GL_QUADS,corners)
        view.drawing_color='#b9c6cb';view.line_width=1;view.draw2d(GL_LINE_LOOP,corners)
      end

      def draw(view)
        if @pending
          draw_preview(view) if @placement || @input.valid?
          return
        end
        layout = geometry(view)
        cx, cy = layout['center']
        size = layout['size']
        extent = layout['radius'] + size * 0.5
        circle(view, cx, cy, layout['radius'], nil, '#aebfc5')
        (@editing && !@folders ? 8 : page_items.length).times do |index|
          item=page_items[index]
          draw_icon(view,layout['items'][index],item,[:item,index],size) if item || @editing
        end
        unless @folders
          layout.fetch('docks',{}).each do |zone,points|
            occupied=points.each_with_index.filter_map { |point,index| point if target_item([:dock,[zone,index]]) }
            draw_dock_bar(view,occupied,size) unless occupied.empty?
            points.each_with_index do |point,index|
              target=[:dock,[zone,index]];item=target_item(target)
              draw_icon(view,point,item,target,size) if item || @editing && (@dragging || @external_drag || index.zero?)
            end
          end
        end
        circle(view, cx, cy, size * 0.56, '#ffffff', '#aebfc5')
        folder = HUDBoards.current(@library.config,hud_folder)
        label = @editing ? 'EDIT' : @folders ? 'BẢNG ICON' : folder&.fetch('name', 'Library') || 'Chưa có bảng'
        small = size < 44
        text(view, cx, cy - (small ? 5 : 14), label[0, [size / 6, 15].min.to_i], '#24545b', [size * 0.22, 10].min)
        text(view, cx, cy + 5, @editing ? 'Kéo icon' : @query.empty? ? 'Đổi bảng ▾' : "Tìm: #{@query}"[0, 20], '#628086', 9) unless small
        if page_count>1
          nav = [70, extent * 0.7].min
          text(view,cx-nav,cy+extent+15,'‹','#008b90',19)
          text(view,cx,cy+extent+20,"#{@page+1} / #{page_count}",'#47636c',10)
          text(view,cx+nav,cy+extent+15,'›','#008b90',19)
        end
        if @drag_cursor && (@dragging || @external_drag)
          x, y = @drag_cursor
          circle(view, x, y, size * 0.4, '#b8dedc', '#008b90')
          text(view, x, y - 7, '↔', '#00777c', 11)
        end
      rescue StandardError => detail
        # A draw failure must not leave a tool silently capturing the keyboard.
        @draw_error ||= detail
        UI.start_timer(0, false) { fail_session(@draw_error) if @active }
      end

      def draw_preview(view)
        if @placement
          ImportLinks.draw(view,@placement) if @placement['mode']=='template'
          frame = Geom::Transformation.new(@placement['frame'])
          corners = Frames.corners(@placement['bounds']).map { |point| Geom::Point3d.new(point.map { |v| v/25.4 }).transform(frame) }
          segments = (0...8).to_a.combination(2).select { |a,b| [1,2,4].include?(a^b) }.flat_map { |a,b| [corners[a],corners[b]] }
          view.drawing_color = @placement['mode']=='replace' ? '#d08c21' : @placement['mode']=='template' ? '#626d73' : '#008b90'
          view.line_width = @placement['mode']=='template' ? 1 : 3
          view.draw(GL_LINES,segments)
          scales=Frames.scale_frame(frame.to_a).values_at(0,5,10)
          size = Core.dimensions(@placement['bounds']).each_with_index.map { |v,i| (v*scales[i]).round(1) }
          label = if @placement['mode']=='template'
                    "#{@placement['kind']=='inside' ? 'Lọt trong' : 'Đối mặt'} · #{@placement['matches'].length}/#{@placement['template']['faces'].count { |face| face['enabled'] }} mặt"
                  else
                    @placement['mode']=='replace' ? 'Thay module' : 'Lọt lòng'
                  end
          virtual=@placement.fetch('matches',[]).count { |match| match['target']['virtual'] }
          label+=" · #{virtual} mốc phủ bì" if virtual.positive?
          if (drawer=@placement_data && @placement_data['drawer_fit'])
            label+=" · #{drawer['kind']=='concealed' ? 'Ray âm' : 'Ray bi'} #{drawer['size'].round}"
          end
          text(view,18,view.vpheight-38,"#{label}: #{size.join(' × ')} mm",'#00777c',12,center:false)
          return
        end
        position = @input.position
        view.drawing_color = '#008b90'
        view.line_width = 2
        @pending['snapshot']['parts'].each do |part|
          next if part['visible'] == false
          corners = Frames.corners(part['bounds']).map { |point| Geom::Point3d.new(point.map { |value| value / 25.4 }) + position.to_a }
          segments = (0...8).to_a.combination(2).select { |a, b| [1, 2, 4].include?(a ^ b) }.flat_map { |a, b| [corners[a], corners[b]] }
          view.draw(GL_LINES, segments)
        end
        @input.draw(view)
      end

      def getExtents
        box = Geom::BoundingBox.new
        if @pending && @placement
          frame = Geom::Transformation.new(@placement['frame'])
          Frames.corners(@placement['bounds']).each { |point| box.add(Geom::Point3d.new(point.map { |v| v/25.4 }).transform(frame)) }
        elsif @pending && @input.valid?
          @pending['snapshot']['envelope'].each do |point|
            box.add(Geom::Point3d.new(point.map { |value| value / 25.4 }) + @input.position.to_a)
          end
        end
        box
      end

      def show_settings
        return @settings.bring_to_front if @settings
        @settings = UI::HtmlDialog.new(dialog_title: 'Cài đặt HUD', preferences_key: 'MH_Module_Studio_HUD',
          width: 370, height: 550, min_width: 320, min_height: 360, resizable: true, style: UI::HtmlDialog::STYLE_UTILITY)
        @settings.set_file(File.join(__dir__.dup.force_encoding(Encoding::UTF_8), 'ui', 'hud_settings.html'))
        @settings.add_action_callback('hud_request') do |_context, raw|
          begin
            raise Core::Error, 'Yêu cầu quá lớn.' if raw.to_s.bytesize > 64 * 1024
            data = JSON.parse(raw.to_s)
            if data['action'] == 'exit'
              finish
            elsif data['action'] == 'close'
              @settings.close
            elsif data['action'] == 'settings'
              @cursor_anchor = @last_mouse if data.dig('settings', 'hud_position') == 'cursor' && @last_mouse
              @library.save_settings(data.fetch('settings'))
              @library.publish
            elsif data['action']=='select_board'
              raise Core::Error,'Bảng HUD không còn tồn tại.' unless HUDBoards.current(@library.config,data['id'])
              choose_folder(data['id'])
              send_settings
            elsif data['action'] == 'edit'
              set_editing(data['enabled'])
              send_settings
            elsif data['action']=='board'
              @library.edit_hud_board(data.fetch('operation'),data.fetch('board'))
              send_settings
            elsif %w[import_config export_config].include?(data['action'])
              message = @library.transfer_hud_config(data['action'])
              send_settings(nil,message:message)
            else
              send_settings
            end
          rescue StandardError => detail
            send_settings(detail.message)
          end
        end
        @settings.set_on_closed do
          @settings = nil
          UI.start_timer(0, false) { Sketchup.focus if @active && Sketchup.active_model.equal?(@model) }
        end
        @settings.show
      end

      def send_settings(error = nil,message: nil)
        return unless @settings
        state = { 'settings' => @library.config, 'boards' => @library.config.fetch('hud_boards',[]), 'editing' => @editing, 'error' => error,'message'=>message }
        @settings&.execute_script("window.receiveHUDSettings(JSON.parse(#{JSON.generate(JSON.generate(state))}));")
      end
    end

    def self.library
      @library ||= Library.new do |receiver, data|
        dialog = @panel&.instance_variable_get(:@dialog)
        dialog&.execute_script("window.#{receiver}(JSON.parse(#{JSON.generate(JSON.generate(data))}));")
      end
    end

    def self.open_hud
      library.open_hud
    rescue StandardError => error
      UI.messagebox(error.message)
    end
  end
end

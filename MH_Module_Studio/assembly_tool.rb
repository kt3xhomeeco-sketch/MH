# encoding: UTF-8
require_relative 'assembly'
require_relative 'assembly_hud'
require_relative 'assembly_face_picker'
require_relative 'assembly_auto_links'

module MH
  module ModuleStudio
    # A viewport HUD, not the Studio's web preview. Numeric edits use SketchUp's
    # Measurements box; face/body drags operate directly in the model.
    class AssemblyTool
      MODES = { 'contact' => 'Khoảng cách', 'center' => 'Căn giữa', 'fit' => 'Vừa khoang',
                'angle' => 'Góc', 'repeat' => 'Lặp / Chia đều' }.freeze
      DIRECTIONS = { 'right' => 'Phải →', 'left' => '← Trái', 'up' => 'Trên ↑', 'down' => 'Dưới ↓' }.freeze
      attr_reader :record, :active, :error, :hud, :notice

      def initialize
        @model = Sketchup.active_model
        fresh
      end

      def fresh(mode = 'contact')
        @record = { 'mode' => mode, 'gap' => 0.0, 'count' => 2, 'angle' => 90.0,
                    'direction' => 'right', 'equal' => false, 'ends' => true }
        @picking = mode == 'repeat' ? 'b' : 'a'
        @field = mode == 'angle' ? 'angle' : mode == 'repeat' ? 'count' : mode == 'center' ? nil : 'gap'
        @error = nil; @drag = nil; @held = nil; @held_mesh = nil; @held_points = nil; @hover = nil
        @notice = nil
      end

      def activate
        @active = true
        Assembly.watch(@model)
        unless @hud
          selected = @model.selection.to_a.first
          saved = Assembly.records(@model).find { |row| selected && (row.dig('b', 'root') == selected.persistent_id.to_s || row['scope']==selected.persistent_id.to_s) }
          load_record(saved) if saved
          @hud = AssemblyHUD.new(self)
          @hud.show
        end
        refresh
      end

      def deactivate(view)
        @record = @drag['before'] if @drag
        @active = false; @drag = nil; @held = nil; @held_mesh = nil; @held_points = nil; @hover = nil; @picking = nil
        Sketchup.vcb_label = ''; Sketchup.status_text = ''
        view.invalidate
      end

      def detach_hud
        @hud = nil
      end

      def enableVCB?
        !@field.nil?
      end

      def suspend(view)
        view.invalidate
      end

      def resume(view)
        refresh
        view.invalidate
      end

      def getExtents
        bounds = Geom::BoundingBox.new
        %w[a b c r1 r2].each do |key|
          next unless @record[key]
          Assembly.world_plane(@model,@record[key])['points'].each { |point| bounds.add(Geom::Point3d.new(point.map { |value| value/25.4 })) }
        end
        anchor = @drag ? @drag['anchor'] : @record['b']
        if anchor
          entity = Assembly.root(@model,anchor)
          frame = Assembly.world_transform(@model,anchor)
          8.times { |index| bounds.add(entity.definition.bounds.corner(index).transform(frame)) }
          if @drag
            vector = Geom::Vector3d.new(@drag['delta'].map { |value| value/25.4 }).transform(AssemblyContainers.frame(@model,@drag['anchor']))
            8.times { |index| bounds.add(entity.definition.bounds.corner(index).transform(frame)+vector) }
          end
        end
        bounds
      rescue StandardError
        Geom::BoundingBox.new
      end

      def load_record(row)
        fresh(row['mode'])
        @record.merge!(Core.copy_data(row))
        @picking = nil; @drag = nil; @held = nil; @held_mesh = nil; @held_points = nil; @hover = nil; @error = nil
      end

      def refresh
        Sketchup.vcb_label = { 'gap' => 'Khoảng cách', 'angle' => 'Góc', 'count' => 'Số lượng tổng' }.fetch(@field, '')
        Sketchup.vcb_value = @record[@field].to_s
        Sketchup.status_text = @picking ? "Chọn #{@picking.upcase} · Click: mặt tấm · Shift+Click: phủ bì module · Ctrl+Click: phủ bì cụm · Esc hủy chọn" : 'Click: mặt tấm · Shift+Click: module · Ctrl+Click: cụm · Giữ mặt B để đổi khoảng cách · Space thoát'
        @model.active_view.invalidate
        @hud&.publish
      end

      def required
        return @record['equal'] ? %w[b a c] : %w[b] if @record['mode'] == 'repeat'
        %w[center fit].include?(@record['mode']) ? %w[a b c] : %w[a b]
      end

      def complete?
        required.all? { |key| @record[key] } && (!!@record['r1'] == !!@record['r2'])
      end

      def pick(path)
        reference = path.is_a?(Hash) ? Core.copy_data(path) : Assembly.anchor(path)
        raise Core::Error, 'Chọn mặt trên module khác đã chọn.' unless pick_allowed?(reference)
        proposed = Core.copy_data(@record).merge(@picking => reference)
        target = proposed['b'] && AssemblyContainers.identity(proposed['b'])
        if target && %w[a c r1 r2].any? { |key| proposed[key] && AssemblyContainers.identity(proposed[key]) == target }
          raise Core::Error, 'Chọn mặt tham chiếu trên module khác B.'
        end
        @record = proposed
        @picking = required.find { |key| !@record[key] }
        @picking = 'r2' if @record['r1'] && !@record['r2']
        save if (@record['id'] || @record['mode']=='fit') && complete?
        refresh
      end

      # A/C (and measurement R1/R2) may share the surrounding module. B cannot
      # be that module, nor its whole-assembly parent/child envelope.
      def pick_allowed?(anchor)
        return true unless @picking
        keys = @picking=='b' ? %w[a c r1 r2] : %w[b]
        keys.none? do |key|
          other = @record[key]
          other && (AssemblyContainers.identity(anchor)==AssemblyContainers.identity(other) ||
            anchor['level']=='assembly' && anchor['root']==other['scope'] ||
            other['level']=='assembly' && other['root']==anchor['scope'])
        end
      end

      def save
        raise Core::Error, 'Chọn đủ các mặt trước khi lưu liên kết.' unless complete?
        @record = Assembly.save(@model, @record)
        @picking = nil; @error = nil
        refresh
      end

      def changed
        save if @record['id'] && complete?
      end

      def onUserText(text, _view)
        previous = Core.copy_data(@record)
        raise Core::Error, 'Chọn ô giá trị trên HUD trước khi nhập số.' unless @field
        editable_field!(@field)
        numeric = Float(text.tr(',', '.'), exception: false)
        value = @field == 'gap' && !numeric ? Sketchup.parse_length(text) : numeric
        raise Core::Error, 'Nhập một giá trị số hợp lệ.' unless value
        @record[@field] = @field == 'gap' && !numeric ? value.to_f * 25.4 : value.to_f
        validate_input
        changed
        refresh
      rescue StandardError => detail
        @record = previous
        @error = detail.message
        refresh
      end

      def validate_input
        AssemblyMath.repeat_layout(count: @record['count'], size: 1, start: 0, gap: 0)
        raise Core::Error, 'Góc phải từ 0–180°.' unless @record['angle'].between?(0, 180)
        if %w[fit repeat].include?(@record['mode']) && @record['gap'].negative?
          raise Core::Error, 'Khoảng hở phải từ 0 mm.'
        end
      end

      def editable_field!(field)
        return unless field == 'gap'
        raise Core::Error, 'Chọn Nhập số trước khi sửa khoảng cách tham chiếu.' if @record['r1']
        if @record['mode'] == 'repeat' && @record['equal']
          raise Core::Error, 'Khoảng hở đang tự chia đều. Tắt Chia đều để nhập khoảng hở cố định.'
        end
      end

      def action(command, value = nil)
        previous = Core.copy_data(@record)
        @notice = nil
        @hud.activate_tool if @hud && %i[pick bound measure new mode value step fit_size direction toggle manual save group remove flip auto_links].include?(command)
        case command
        when :pick then @picking = value
        when :mode then fresh(value)
        when :field then @field = value
        when :value
          field, number = value
          editable_field!(field)
          raise Core::Error,'Ô giá trị không hợp lệ.' unless %w[gap count angle].include?(field)
          @record[field] = Core.number(number)
          validate_input
          changed
        when :bound
          @record['mode'] = 'fit'
          @picking = 'c'
        when :fit_size
          @record['mode'] = value ? 'fit' : 'center'
          @picking = required.find { |key| !@record[key] }
          changed
        when :step
          field, delta = value
          editable_field!(field)
          @record[field] += delta
          validate_input
          changed
        when :direction
          @record['direction'] = value
          changed
        when :flip
          raise Core::Error,'Đảo phía dùng cho liên kết khoảng cách.' unless @record['mode']=='contact'
          editable_field!('gap')
          @record['gap'] = -@record['gap']
          changed
        when :toggle
          @record[value] = !@record[value]
          @picking = required.find { |key| !@record[key] }
          changed
        when :measure
          @record.delete('r1'); @record.delete('r2'); @picking = 'r1'
        when :manual
          @record.delete('r1'); @record.delete('r2')
          changed
        when :save then save
        when :group then load_record(Assembly.group(@model,@record))
        when :auto_links
          result = AssemblyAutoLinks.create(@model, max_gap: value)
          load_record(result['links'].first) unless result['links'].empty?
          @notice = if result['links'].empty? && result.fetch('removed',0).zero?
                      'Không có liên kết phủ bì mới trong khoảng tìm mặt; kiểm tra vùng chọn hoặc liên kết đã có.'
                    else
                      "Đã tạo #{result['links'].length} liên kết phủ bì; thay #{result.fetch('removed',0)} liên kết tự tạo cũ bám tấm."
                    end
        when :rename
          key,name = value
          raise Core::Error,'Chọn module A hoặc B trước khi đổi tên.' unless %w[a b].include?(key) && @record[key]
          Assembly.rename(@model,@record[key],name,record:@record)
        when :new then fresh
        when :load then load_record(value)
        when :remove
          Assembly.remove(@model, @record['id']) if @record['id']
          fresh
        when :close then @hud ? @hud.close : @model.select_tool(nil)
        end
        @error = nil
        refresh if @active
      rescue StandardError => detail
        @record = previous
        @error = detail.message
        refresh
      end

      def picker
        @picker ||= AssemblyFacePicker.new(@model)
      end

      def hover(flags,x,y,view)
        @pointer = [x,y,flags]
        @hover = picker.hit(flags,x,y,view, accept: @picking ? method(:pick_allowed?) : nil)
        view.invalidate
      rescue Core::Error
        @hover = nil
        view.invalidate
      end

      def onLButtonDown(flags, x, y, view)
        hit = picker.hit(flags,x,y,view, accept: @picking ? method(:pick_allowed?) : nil)
        raise Core::Error, 'Chọn mặt tấm, hoặc giữ Shift/Ctrl để bắt mặt phủ bì.' unless hit
        surface = hit['anchor']
        return pick(surface) if @picking
        anchor = surface.slice('root','scope','level')
        links = Assembly.records(@model)
        saved = links.find { |row| AssemblyMath.same_surface?(surface,row['b']) }
        saved ||= links.find { |row| AssemblyContainers.references(row).any? { |ref| AssemblyContainers.identity(ref)==AssemblyContainers.identity(anchor) } }
        saved ||= links.find { |row| row['scope']==anchor['root'] } if hit['level']=='assembly'
        raise Core::Error,'Chọn mặt hoặc thân của module đã liên kết.' unless saved
        load_record(saved) unless @record['id']==saved['id']
        @held = surface
        @held_mesh = hit['mesh']; @held_frame = hit['frame']; @held_points = hit['plane']['points']
        normal = drag_normal(surface)
        point = hit['plane']['point']
        start_drag(anchor, point, normal, x, y, view)
        @error = nil
        refresh
      rescue StandardError => detail
        @error = detail.message
        refresh
      end

      def drag_normal(surface)
        return unless AssemblyMath.same_surface?(surface,@record['b']) && !@record['r1']
        if %w[contact fit].include?(@record['mode'])
          normal = Assembly.plane(@model,@record['a'])['normal']
          if @record['external']
            world = Assembly.world_plane(@model,@record['a'])['normal']
            normal = Geom::Vector3d.new(world).transform(AssemblyContainers.frame(@model,@record['b']).inverse).normalize.to_a
          end
          return normal
        end
        return unless @record['mode']=='repeat' && !@record['equal']
        normal = Assembly.repeat_axis(Assembly.root(@model,@record['b']),@record)
        face_normal = Assembly.plane(@model,surface)['normal']
        normal if AssemblyMath.dot(normal,face_normal).abs > 0.999999
      end

      def start_drag(anchor, origin, normal, x, y, view)
        @drag = { 'anchor'=>anchor,'point'=>origin,'normal'=>normal,'kind'=>normal ? 'gap' : 'free',
                  'start'=>[x,y],'value'=>@record['gap'],'delta'=>[0,0,0],'before'=>Core.copy_data(@record),'moved'=>false }
        point = Geom::Point3d.new(origin.map { |item| item / 25.4 })
        @drag['plane'] = [point, view.camera.direction]
        @drag['hit'] = Geom.intersect_line_plane(view.pickray(x, y), @drag['plane'])
      end

      def onMouseMove(flags, x, y, view)
        return hover(flags,x,y,view) unless @drag
        return if !@drag['moved'] && Math.hypot(x-@drag['start'][0],y-@drag['start'][1]) < 4
        @drag['moved'] = true
        frame = AssemblyContainers.frame(@model,@drag['anchor'])
        if @drag['kind'] == 'free'
          point = Geom.intersect_line_plane(view.pickray(x, y), @drag['plane'])
          return unless point && @drag['hit']
          delta = (point - @drag['hit']).transform(frame.inverse).to_a.map { |value| value * 25.4 }
        else
          normal = @drag['normal']
          origin = Geom::Point3d.new(@drag['point'].map { |value| value / 25.4 })
          finish = origin + Geom::Vector3d.new(normal).transform(frame).tap { |vector| vector.length = 100.0 / 25.4 }
          a = view.screen_coords(origin); b = view.screen_coords(finish)
          dx = b.x-a.x; dy = b.y-a.y
          raise Core::Error, 'Đổi góc nhìn để kéo theo phương này.' if dx*dx+dy*dy < 4
          amount = ((x-@drag['start'][0])*dx+(y-@drag['start'][1])*dy) * 100 / (dx*dx+dy*dy)
          delta = AssemblyMath.mul(normal, amount)
        end
        if @drag['kind'] == 'gap'
          @record['gap'] = @drag['value'] + AssemblyMath.dot(delta, @drag['normal'])
          @record['gap'] = [@record['gap'], 0].max if %w[fit repeat].include?(@record['mode'])
          @drag['delta'] = AssemblyMath.mul(@drag['normal'], @record['gap'] - @drag['value'])
        else
          _links, @drag['delta'] = Assembly.move(@model, @drag['anchor'], delta)
        end
        refresh
      rescue StandardError => detail
        @record = @drag['before'] if @drag
        @drag = nil; @held = nil; @held_mesh = nil
        @error = detail.message
        view.invalidate
      end

      def onLButtonUp(_flags, _x, _y, _view)
        return unless @drag
        drag = @drag
        @drag = nil
        return refresh unless drag['moved']
        if drag['kind'] == 'gap'
          changed
        else
          links, allowed = Assembly.move(@model, drag['anchor'], drag['delta'])
          Assembly.transact(@model, links, motion: [drag['anchor'], allowed])
          updated = links.find { |row| row['id']==@record['id'] }
          @record = Core.copy_data(updated) if updated
        end
        @held = nil; @held_mesh = nil
        @error = nil
        refresh
      rescue StandardError => detail
        @record = drag['before']
        @held = nil; @held_mesh = nil
        @error = detail.message
        refresh
      end

      def cancel_gesture
        @record = @drag['before'] if @drag
        @drag = nil; @picking = nil; @held = nil; @held_mesh = nil
        refresh
      end

      def onCancel(reason, _view)
        if reason == 2 && !@drag
          saved = Assembly.records(@model).find { |row| row['id'] == @record['id'] } if @record['id']
          saved ? load_record(saved) : fresh
          refresh
        else
          cancel_gesture
        end
      end

      def onKeyDown(key, _repeat, flags, view)
        if [16,17].include?(key) && @pointer && !@drag
          hover(flags | (key==16 ? CONSTRAIN_MODIFIER_MASK : COPY_MODIFIER_MASK),*@pointer.first(2),view)
          return true
        end
        if key == 27
          @drag || @picking ? cancel_gesture : action(:close)
        elsif key == 32
          @model.select_tool(nil)
        end
        [27,32].include?(key)
      end

      def onKeyUp(key,_repeat,flags,view)
        return false unless [16,17].include?(key)
        hover(flags & ~(key==16 ? CONSTRAIN_MODIFIER_MASK : COPY_MODIFIER_MASK),*@pointer.first(2),view) if @pointer && !@drag
        true
      end

      def onMouseLeave(view)
        @hover = nil; @pointer = nil
        view.invalidate
      end

      def getMenu(menu, *_coordinates)
        menu.add_item('Liên kết mới') { action(:new) }
        MODES.each { |mode, title| menu.add_item(title) { action(:mode, mode) } }
        menu.add_separator
        menu.add_item('Xóa liên kết · Giữ các module') { action(:remove) } if @record['id']
        menu.add_item('Thoát HUD') { action(:close) }
      end

      def label(view, x, y, text, color = '#34454f', size = 11)
        view.draw_text(Geom::Point3d.new(x,y,0), text.to_s, color: color, size: size, font: 'Segoe UI')
      end

      def draw(view)
        begin
          draw_geometry(view)
          draw_held(view)
          draw_hover(view) unless @drag
        rescue StandardError => detail
          @error = detail.message
        end
        message = @error || 'Click: mặt tấm · Shift+Click: phủ bì module · Ctrl+Click: phủ bì cụm'
        label(view,18,view.vpheight-32,message,'#007f84',11)
      end

      def draw_hover(view)
        return unless @hover
        mesh = @hover['mesh']
        points = if mesh
                   mesh.points.map { |point| point.transform(@hover['frame']) }
                 else
                   @hover['plane']['points'].map { |point| Geom::Point3d.new(point.map { |value| value/25.4 }) }
                 end
        lift = view.camera.direction.reverse
        lift.length = view.pixels_to_model(0.5,points.first)
        points.map! { |point| point+lift }
        color = {'part'=>[0,120,128,185],'module'=>[30,116,210,175],'assembly'=>[222,146,20,185]}.fetch(@hover['level'])
        view.drawing_color = Sketchup::Color.new(*color)
        polygons = mesh ? mesh.polygons.map { |polygon| polygon.map { |index| points[index.abs-1] } } : [points]
        polygons.each do |polygon|
          triangles = (1...polygon.length-1).flat_map { |index| [polygon[0],polygon[index],polygon[index+1]] }
          view.draw(GL_TRIANGLES,triangles)
          view.line_width = 1; view.draw(GL_LINE_LOOP,polygon)
        end
        x,y = @pointer
        label(view,x+14,y+16,AssemblyFacePicker.label(@hover['anchor']),'#244858',11)
      end

      def draw_geometry(view)
        %w[a b c r1 r2].each do |key|
          next unless @record[key]
          face = Assembly.world_plane(@model,@record[key])
          lift = view.camera.direction.reverse
          lift.length = view.pixels_to_model(0.4,view.camera.target)
          points = face['points'].map { |point| Geom::Point3d.new(point.map { |value| value / 25.4 })+lift }
          view.drawing_color = key=='b' ? Sketchup::Color.new(215,143,35,190) : Sketchup::Color.new(0,120,128,175)
          view.draw(GL_TRIANGLES,[points[0],points[1],points[2],points[0],points[2],points[3]])
          view.drawing_color = key == 'b' ? '#e3a033' : '#008f94'
          view.line_width = 1
          view.draw(GL_LINE_LOOP,points)
          screen = view.screen_coords(Geom::Point3d.new(face['point'].map { |value| value/25.4 }))
          label(view,screen.x,screen.y,key.upcase,key=='b' ? '#a46516' : '#007f84',13)
        end
        return unless @drag && @drag['moved']
        anchor = @drag['anchor']
        entity = Assembly.root(@model,anchor)
        frame = AssemblyContainers.frame(@model,anchor)
        points = 8.times.map do |i|
          point = entity.definition.bounds.corner(i).transform(entity.transformation)
          preview_point(point,entity).transform(frame)
        end
        view.drawing_color = '#008f94'; view.line_width = 2
        wireframe(view,points)
        if @drag['kind']=='gap' && @record['mode']=='repeat'
          normal = @drag['normal']
          current = Assembly.projection(entity,normal)
          step = current[1]-current[0]+@record['gap']
          (@record['count'].to_i-1).times do |index|
            vector = Geom::Vector3d.new(AssemblyMath.mul(normal,(index+1)*step/25.4)).transform(frame)
            wireframe(view,points.map { |point| point+vector })
          end
        end
        screen = view.screen_coords(points.last)
        value = @drag['kind']=='gap' ? @record['gap'] : Math.sqrt(AssemblyMath.dot(@drag['delta'],@drag['delta']))
        label(view,screen.x+8,screen.y-20,"#{value.round(2)} mm",'#007f84',12)
      end

      def preview_point(point, entity)
        return point unless @drag && @drag['moved']
        if @drag['kind']=='gap' && @record['mode']=='fit'
          normal = @drag['normal']
          low,high = Assembly.projection(entity,normal)
          relative = AssemblyMath.dot(point.to_a.map { |value| value*25.4 },normal)-(low+high)*0.5
          change = -2*(@record['gap']-@drag['value'])*relative/(high-low)
          point + Geom::Vector3d.new(AssemblyMath.mul(normal,change/25.4))
        elsif @drag['kind']=='gap' && @record['mode']=='repeat'
          point
        else
          point + Geom::Vector3d.new(@drag['delta'].map { |value| value/25.4 })
        end
      end

      def draw_held(view)
        return unless @held && (@held_mesh || @held_points)
        frame = @held_frame
        entity = @drag && Assembly.root(@model,@drag['anchor'])
        scope = @drag && AssemblyContainers.frame(@model,@drag['anchor'])
        # A small camera-facing lift keeps the overlay clear of coincident faces.
        lift = view.camera.direction.reverse
        lift.length = view.pixels_to_model(1,view.camera.target)
        source = @held_mesh ? @held_mesh.points : @held_points.map { |point| Geom::Point3d.new(point.map { |value| value/25.4 }) }
        polygons = @held_mesh ? @held_mesh.polygons : [[1,2,3,4]]
        points = source.map do |point|
          world = @held_mesh ? point.transform(frame) : point
          world = preview_point(world.transform(scope.inverse),entity).transform(scope) if entity
          world+lift
        end
        triangles = polygons.flat_map do |polygon|
          polygon = polygon.map { |index| points[index.abs-1] }
          (1...polygon.length-1).flat_map { |i| [polygon[0],polygon[i],polygon[i+1]] }
        end
        view.drawing_color = Sketchup::Color.new(0,83,92,225)
        view.draw(GL_TRIANGLES,triangles)
        view.line_width = 1
        view.drawing_color = '#004c53'
        polygons.each { |polygon| view.draw(GL_LINE_LOOP,polygon.map { |index| points[index.abs-1] }) }
      end

      def wireframe(view,points)
        lines = (0...8).to_a.combination(2).select { |a,b| [1,2,4].include?(a^b) }.flat_map { |a,b| [points[a],points[b]] }
        view.draw(GL_LINES,lines)
      end
    end

    def self.open_assembly
      Runtime.ensure_top_level(Sketchup.active_model)
      @assembly_tool&.hud&.close
      @assembly_tool = AssemblyTool.new
      Sketchup.active_model.select_tool(@assembly_tool)
      Sketchup.focus
    rescue StandardError => detail
      UI.messagebox(detail.message)
    end
  end
end

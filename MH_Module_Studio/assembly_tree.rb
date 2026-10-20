# encoding: UTF-8
module MH
  module ModuleStudio
    # Native tree data and viewport drawing; no geometry writes.
    class AssemblyTree
      attr_reader :rows, :reference

      def initialize(model, tool)
        @model = model; @tool = tool; @open = {}; @offset = 0; @rows = []
      end

      def expanded?(id, default = false)
        @open.fetch(id,default)
      end

      def toggle(id)
        row = @rows.find { |item| item['id']==id }
        @open[id] = !row['open'] if row
      end

      def panel_rows(parent, anchor, depth, prefix, ancestors = [])
        return if depth>12 || ancestors.include?(parent.definition)
        parent.definition.entities.each do |child|
          next unless Assembly.container?(child)
          ref = anchor.reject { |key,_value| key=='part' }.merge('path'=>anchor.fetch('path',[])+[child.persistent_id.to_s])
          part = child.get_attribute(Reader::DICT,'part_key')
          ref['part'] = part if part
          id = prefix+'/'+child.persistent_id.to_s
          children = child.definition.entities.any? { |item| Assembly.container?(item) }
          row = {'id'=>id,'name'=>title(child),'depth'=>depth,'kind'=>'panel','ref'=>ref,'children'=>children,'open'=>expanded?(id)}
          @rows << row
          return nil if @rows.length>=600
          panel_rows(child,ref,depth+1,id,ancestors+[parent.definition]) if children && row['open']
        end
      end

      def title(entity)
        entity.name.to_s.strip.empty? ? entity.definition.name.to_s : entity.name.to_s
      end

      def module_row(entity, scope, depth)
        anchor = {'root'=>entity.persistent_id.to_s,'scope'=>scope,'path'=>[]}.compact
        id = [scope,anchor['root']].compact.join('/')
        children = entity.definition.entities.any? { |item| Assembly.container?(item) }
        row = {'id'=>id,'name'=>title(entity),'depth'=>depth,'kind'=>'module','ref'=>anchor,'children'=>children,'open'=>expanded?(id)}
        @rows << row
        panel_rows(entity,anchor,depth+1,id) if row['open']
      end

      def links(records, scope, depth)
        id = 'links:'+scope.to_s
        subset = records.select { |row| row['scope']==scope }
        return if subset.empty?
        row = {'id'=>id,'name'=>'Liên kết','depth'=>depth,'kind'=>'folder','children'=>true,'open'=>expanded?(id,true)}
        @rows << row
        return unless row['open']
        Assembly.presentation_groups(@model,subset).each do |group|
          group_id = 'links:'+group['id']
          opened = expanded?(group_id,true)
          @rows << {'id'=>group_id,'name'=>group['name'] || "#{group['modules'].length} module",'depth'=>depth+1,'kind'=>'folder','children'=>true,'open'=>opened}
          next unless opened
          group['modules'].each_with_index do |member,index|
            next unless @linked[AssemblyMath.root_identity(member['ref'])]
            @rows << {'id'=>group_id+":module:#{index}",'name'=>member['name'],'depth'=>depth+2,'kind'=>'module','ref'=>member['ref']}
          end
          group['links'].each do |link|
            @rows << {'id'=>'link:'+link['id'],'name'=>link['label'],'depth'=>depth+2,'kind'=>'link','record'=>link['id']}
          end
        end
      end

      def rebuild
        @rows = []
        records = Assembly.records(@model)
        @linked = records.each_with_object({}) do |record,result|
          AssemblyContainers::REFS.each { |key| result[AssemblyMath.root_identity(record[key])] = true if record[key] }
          record.fetch('copies',[]).each { |pid| result[[record['scope'],pid.to_s]] = true }
        end
        @model.entities.each do |entity| # rubocop:disable SketchupSuggestions/ModelEntities -- The tree deliberately lists model-level assemblies.
          next unless Assembly.container?(entity)
          if AssemblyContainers.managed?(entity)
            scope = entity.persistent_id.to_s; id = 'scope:'+scope
            members = AssemblyContainers.members(entity).select { |member| @linked[[scope,member.persistent_id.to_s]] }
            next if members.empty? && !@linked[[nil,scope]]
            row = {'id'=>id,'name'=>title(entity),'depth'=>0,'kind'=>'assembly','children'=>true,'open'=>expanded?(id,true),'ref'=>{'root'=>scope}}
            @rows << row
            if row['open']
              members.each { |member| module_row(member,scope,1) }
              links(records,scope,1)
            end
          else
            next unless @linked[[nil,entity.persistent_id.to_s]]
            module_row(entity,nil,0)
          end
          break if @rows.length>=600
        end
        links(records,nil,0)
      end

      def layout(view)
        height = [[view.vpheight-70,120].max,500].min
        width = [230,[view.vpwidth-330,150].max].min
        {'rect'=>[14,18,14+width,18+height],'count'=>[(height-90)/25,1].max.floor,'row_top'=>60}
      end

      def visible(view)
        count = layout(view)['count']
        @offset = [[@offset,0].max,[@rows.length-count,0].max].min
        @rows.slice(@offset,count) || []
      end

      def click(x,y,view)
        rect = layout(view)['rect']
        return @tool.hud.close if y<rect[1]+28 && x>rect[2]-26
        if y>=rect[1]+31 && y<rect[1]+54
          @tool.action(:auto_links,20)
          return
        end
        return if y<rect[1]+layout(view)['row_top'] || y>=rect[3]-22
        row = visible(view)[((y-rect[1]-layout(view)['row_top'])/25).floor]
        return unless row
        if row['children'] && x<rect[0]+27+row['depth']*13
          toggle(row['id'])
        elsif row['kind']=='link'
          record = Assembly.records(@model).find { |item| item['id']==row['record'] }
          @tool.action(:load,record) if record
          @selected = row['id']; @reference = nil
        elsif row['ref']
          @selected = row['id']; @reference = row['ref']
          selected = @reference['scope'] ? AssemblyContainers.wrapper(@model,@reference['scope']) : Assembly.root(@model,@reference)
          @model.selection.clear; @model.selection.add(selected)
        elsif row['children']
          toggle(row['id'])
        end
        rebuild
        @model.active_view.invalidate
        @tool.hud.publish
        Sketchup.focus
      end

      def scroll(direction)
        @offset += direction*3
      end

      def box(view,rect,fill,border)
        points = [[rect[0],rect[1],0],[rect[2],rect[1],0],[rect[2],rect[3],0],[rect[0],rect[3],0]]
        view.drawing_color = fill; view.draw2d(GL_QUADS,points)
        view.drawing_color = border; view.line_width = 1; view.draw2d(GL_LINE_LOOP,points)
      end

      def draw(view)
        rect = layout(view)['rect']
        box(view,rect,Sketchup::Color.new(250,252,254,245),'#bbcbd4')
        @tool.label(view,rect[0]+10,rect[1]+7,'Cụm / Module','#2a414e',11)
        @tool.label(view,rect[2]-20,rect[1]+6,'×','#6d838e',13)
        box(view,[rect[0]+5,rect[1]+31,rect[2]-5,rect[1]+54],'#dcefee','#9fc8c7')
        button_label = rect[2]-rect[0]<190 ? 'Tự tạo liên kết' : 'Tự tạo liên kết từ vùng chọn'
        @tool.label(view,rect[0]+12,rect[1]+35,button_label,'#147a80',10)
        visible(view).each_with_index do |row,index|
          top = rect[1]+layout(view)['row_top']+index*25
          selected = row['id']==@selected || row['record'] && row['record']==@tool.record['id']
          box(view,[rect[0]+3,top,rect[2]-3,top+24],'#e1eff6','#e1eff6') if selected
          x = rect[0]+8+row['depth']*13
          @tool.label(view,x,top+3,row['open'] ? '▾' : '▸','#5c7684',10) if row['children']
          icon = row['kind']=='link' ? '↔' : row['kind']=='panel' ? '▯' : '▣'
          @tool.label(view,x+14,top+3,icon,row['kind']=='link' ? '#008b90' : '#6f93a9',11)
          remaining = [((rect[2]-x-42)/6).floor,5].max
          text = row['name']
          text = text[0,remaining-1]+'…' if text.length>remaining
          @tool.label(view,x+31,top+3,text,'#344e5c',10)
        end
        @tool.label(view,rect[0]+9,rect[3]-18,@rows.empty? ? 'Chưa có module được liên kết' : 'Cuộn để xem · M: Move · S: Scale','#7a929e',9)
      end

      def draw_selection(view)
        return unless @reference
        entity,frame = Assembly.panel(@model,@reference)
        frame = AssemblyContainers.frame(@model,@reference)*frame
        points = 8.times.map { |i| entity.definition.bounds.corner(i).transform(frame) }
        view.drawing_color = '#159caa'; view.line_width = 1
        @tool.wireframe(view,points)
      rescue Core::Error, TypeError
        @reference = nil
      end
    end
  end
end

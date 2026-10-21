# encoding: UTF-8
require_relative 'contact_display'
module MH
  module ModuleStudio
    # Native contact prisms and editable dimensions. Existing Assembly owns edits.
    class ContactView
      attr_reader :items,:last_error
      def initialize(model,tool)
        @model=model;@tool=tool;@items=[]
      end
      def rows
        selected=@model.selection.select { |e| Assembly.container?(e) }.map { |e| e.persistent_id.to_s }
        Assembly.records(@model).select do |r|
          r['mode']=='contact' && (selected.empty? || %w[a b].any? { |key| selected.include?(r.dig(key,'root')) || selected.include?(r.dig(key,'scope')) })
        end
      end
      def entries
        records=rows
        frames=records.flat_map { |r| %w[a b].map { |key| r[key] } }.uniq { |ref| AssemblyMath.root_identity(ref) }.map do |ref|
          root=Assembly.root(@model,ref);[Assembly.world_transform(@model,ref).to_a,root.definition.bounds.min.to_a,root.definition.bounds.max.to_a]
        end
        key=[ImportLinks.revision(@model),records,frames]
        return @entries if @key==key
        @key=key
        @entries=records.filter_map do |record|
          shape=ContactDisplay.prism(Assembly.world_plane(@model,record['a']),Assembly.world_plane(@model,record['b']))
          shape.merge('id'=>record['id'],'record'=>record)
        rescue Core::Error
          nil
        end
      end
      def extents
        box=Geom::BoundingBox.new
        entries.each { |entry| entry['points'].each { |p| box.add(Geom::Point3d.new(p.map { |v| v/25.4 })) } }
        box
      end
      def draw(view)
        @items=[];@last_error=nil
        entries.each do |entry|
          points=entry['points'].map { |p| Geom::Point3d.new(p.map { |v| v/25.4 }) }
          screen=points.map { |p| view.screen_coords(p).to_a }
          next if screen.map(&:first).max<0 || screen.map(&:first).min>view.vpwidth || screen.map { |p| p[1] }.max<0 || screen.map { |p| p[1] }.min>view.vpheight
          polygons=ContactDisplay::FACES.map { |face| face.map { |i| points[i] } }
          if entry['volume']
            selected=entry['id']==@tool.record['id']
            view.drawing_color=selected ? Sketchup::Color.new(232,154,38,105) : Sketchup::Color.new(0,139,149,85)
            view.draw(GL_TRIANGLES,polygons.flat_map { |p| [p[0],p[1],p[2],p[0],p[2],p[3]] })
            view.drawing_color=selected ? '#a86a10' : '#006973';view.line_width=1
            polygons.each { |p| view.draw(GL_LINE_LOOP,p) }
          end
          ends=entry['ends'].map { |p| view.screen_coords(Geom::Point3d.new(p.map { |v| v/25.4 })).to_a }
          dx=ends[1][0]-ends[0][0];dy=ends[1][1]-ends[0][1];length=Math.hypot(dx,dy)
          offset=length>4 ? [-dy/length*28,dx/length*28] : [26,-26]
          line=ends.map { |p| [p[0]+offset[0],p[1]+offset[1],0] }
          line[1]=[line[0][0]+24,line[0][1],0] if length<2
          value=AssemblyPresentation.gap(entry['record'],Assembly.distance(@model,entry['record']))
          text="#{value.round(2)} mm";width=[text.length*7+14,48].max
          x=(line[0][0]+line[1][0])/2;y=(line[0][1]+line[1][1])/2
          x=[[x,width/2+8].max,view.vpwidth-width/2-8].min;y=[[y,20].max,view.vpheight-20].min
          rect=[x-width/2,y-12,x+width/2,y+12]
          12.times do
            break unless @items.any? { |item| r=item['rect'];rect[0]<r[2]+3 && rect[2]>r[0]-3 && rect[1]<r[3]+3 && rect[3]>r[1]-3 }
            rect=rect.map.with_index { |v,i| i.odd? ? v+26 : v }
          end
          view.drawing_color='#158c9c';view.line_width=1
          segments=[ends[0],line[0],ends[1],line[1],line[0],line[1]]
          line.each { |p| segments.concat([[p[0]-4,p[1]-4,0],[p[0]+4,p[1]+4,0]]) }
          view.draw2d(GL_LINES,segments)
          view.draw2d(GL_LINES,[[x,y,0],[(rect[0]+rect[2])/2,(rect[1]+rect[3])/2,0]])
          quad=[[rect[0],rect[1],0],[rect[2],rect[1],0],[rect[2],rect[3],0],[rect[0],rect[3],0]]
          view.drawing_color=Sketchup::Color.new(248,253,255,245);view.draw2d(GL_QUADS,quad)
          view.drawing_color='#83b8c4';view.draw2d(GL_LINE_LOOP,quad)
          @tool.label(view,rect[0]+7,rect[1]+4,text,'#006d83',12)
          @items << entry.merge('rect'=>rect,'polygons'=>polygons.map { |poly| poly.map { |p| view.screen_coords(p).to_a } })
        end
      rescue StandardError=>error
        @last_error=error.message
      end
      def hit(x,y)
        ContactDisplay.hit(@items,x,y)
      end
      def click(x,y)
        target=hit(x,y);return false unless target
        row=Assembly.records(@model).find { |r| r['id']==target[1] }
        return false unless row
        @tool.action(:load,row)
        if target[0]=='dimension'
          value=AssemblyPresentation.gap(row,Assembly.distance(@model,row))
          result=UI.inputbox(['Khoảng cách (mm):'],[value.to_s],'Liên kết module · Khoảng cách')
          if result
            raise Core::Error,'Model hoặc liên kết đã đổi; chọn lại dim.' unless Sketchup.active_model.equal?(@model) && Assembly.records(@model).find { |r| r['id']==row['id'] }==row
            @tool.onUserText(result.first.to_s,@model.active_view)
            UI.messagebox(@tool.error) if @tool.error
          end
        else
          @tool.hud.open_settings
        end
        @model.active_view.invalidate;true
      rescue Core::Error=>error
        UI.messagebox(error.message);true
      end
    end
  end
end

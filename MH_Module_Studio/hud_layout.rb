# encoding: UTF-8
module MH
  module ModuleStudio
    # Viewport pixels only; no native model objects or file access.
    module HUDLayout
      extend self
      def compose(width,height,ring,board,editing: false)
        result=Core.copy_data(ring);size=ring['size'];step=size+8;pad=10+size/2.0
        result['docks']={}
        HUDBoards::DOCKS.each do |zone|
          values=board ? board['docks'].fetch(zone,[]) : []
          horizontal=%w[top bottom].include?(zone)
          top_count=[board&.dig('docks','top')&.length || 0,1].max
          bottom_count=[board&.dig('docks','bottom')&.length || 0,1].max
          top=result['docks'].fetch('top',[]).first(top_count).map(&:last).max || pad
          bottom=result['docks'].fetch('bottom',[]).first(bottom_count).map(&:last).min || height-pad
          start=horizontal ? pad : top+step
          finish=horizontal ? width-pad : bottom-step
          capacity=[((finish-start)/step).floor+1,1].max
          count=editing ? [[values.length+1,capacity].max,64].min : values.length
          points=count.times.map do |index|
            lane,cell=index.divmod(capacity)
            case zone
            when 'top' then [pad+cell*step,pad+lane*step]
            when 'bottom' then [pad+cell*step,height-pad-lane*step]
            when 'left' then [pad+lane*step,start+cell*step]
            when 'right' then [width-pad-lane*step,start+cell*step]
            end
          end
          result['docks'][zone]=points
        end
        extent=ring['radius']+size/2+8
        insets=HUDBoards::DOCKS.to_h do |zone|
          points=result['docks'][zone].each_with_index.filter_map { |point,index| point if editing || board && board['docks'][zone][index] }
          depth=points.map { |point| %w[top bottom].include?(zone) ? (zone=='top' ? point[1] : height-point[1]) : (zone=='left' ? point[0] : width-point[0]) }.max
          [zone,depth ? depth+size/2+8 : 0]
        end
        cx,cy=ring['center']
        cx=clamp(cx,insets['left']+extent,width-insets['right']-extent)
        cy=clamp(cy,insets['top']+extent,height-insets['bottom']-extent)
        result['center']=[cx,cy]
        result['items']=8.times.map { |i| angle=-Math::PI/2+i*Math::PI/4;[cx+Math.cos(angle)*ring['radius'],cy+Math.sin(angle)*ring['radius']] }
        result
      end
      def clamp(value,low,high)
        low<=high ? [[value,low].max,high].min : (low+high)/2
      end
      def dock_hit(layout,board,x,y,editing: false)
        return unless board
        layout.fetch('docks',{}).each do |zone,points|
          points.each_with_index do |(px,py),index|
            next unless editing || board['docks'][zone][index]
            return [:dock,[zone,index]] if Math.hypot(x-px,y-py)<=layout['size']/2.0+ (editing ? 4 : 0)
          end
        end
        nil
      end
    end
  end
end

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
        insets=HUDBoards::DOCKS.to_h do |zone|
          points=result['docks'][zone].each_with_index.filter_map { |point,index| point if editing || board && board['docks'][zone][index] }
          depth=points.map { |point| %w[top bottom].include?(zone) ? (zone=='top' ? point[1] : height-point[1]) : (zone=='left' ? point[0] : width-point[0]) }.max
          [zone,depth ? depth+size/2+8 : 0]
        end
        cx,cy=ring['center'];free=board ? board.fetch('free',{}) : {}
        relative=free.select { |_id,position| position['relative'] }
        radius=ring['radius']+size/2.0+8;icon_pad=size/2.0+4
        offsets=[[-radius,radius,-radius,radius]]
        relative.each_value do |position|
          x=position.key?('snap_x') ? Math.cos(-Math::PI/2+position['snap_x']*Math::PI/4)*ring['radius'] : position['x']
          y=position.key?('snap_y') ? Math.sin(-Math::PI/2+position['snap_y']*Math::PI/4)*ring['radius'] : position['y']
          offsets << [x-icon_pad,x+icon_pad,y-icon_pad,y+icon_pad]
        end
        min_x=offsets.map(&:first).min;max_x=offsets.map { |item| item[1] }.max
        min_y=offsets.map { |item| item[2] }.min;max_y=offsets.map(&:last).max
        left,right,top,bottom=insets.fetch('left',0),insets.fetch('right',0),insets.fetch('top',0),insets.fetch('bottom',0)
        cx=cluster_center(cx,min_x,max_x,left,width-right)
        cy=cluster_center(cy,min_y,max_y,top,height-bottom)
        result['center']=[cx,cy]
        result['items']=8.times.map { |i| angle=-Math::PI/2+i*Math::PI/4;[cx+Math.cos(angle)*ring['radius'],cy+Math.sin(angle)*ring['radius']] }
        result['free']=free.to_h do |id,position|
          point=position['relative'] ? free_xy(position,result,width,height) : free_point(position,result,width,height)
          [id,point]
        end
        result
      end
      def free_point(position,layout,width,height)
        x,y=free_xy(position,layout,width,height)
        pad=layout['size']/2.0+4
        [clamp(x,pad,width-pad),clamp(y,pad,height-pad)]
      end
      def free_xy(position,layout,width,height)
        cx,cy=layout['center']
        x=position.key?('snap_x') ? layout['items'][position['snap_x']][0] : position['relative'] ? cx+position['x'] : position['x']*width
        y=position.key?('snap_y') ? layout['items'][position['snap_y']][1] : position['relative'] ? cy+position['y'] : position['y']*height
        [x,y]
      end
      def cluster_center(center,minimum_offset,maximum_offset,start,finish)
        low=start-minimum_offset;high=finish-maximum_offset
        low<=high ? clamp(center,low,high) : (start+finish-minimum_offset-maximum_offset)/2.0
      end
      def anchor_legacy_free(board,layout)
        cx,cy=layout['center']
        board.fetch('free',{}).filter_map do |id,position|
          next if position['relative']
          x,y=layout['free'][id]
          [id,position.merge('x'=>x-cx,'y'=>y-cy,'relative'=>true)]
        end.to_h
      end
      def free_hit(layout,x,y)
        layout.fetch('free',{}).to_a.reverse_each do |id,(px,py)|
          return [:free,id] if Math.hypot(x-px,y-py)<=layout['size']/2.0
        end
        nil
      end
      def free_drop(layout,board,x,y,width,height,moving:nil)
        pad=layout['size']/2.0+4
        point=[clamp(x,pad,width-pad),clamp(y,pad,height-pad)]
        references=layout['items'].each_with_index.map { |p,index| [p,index] }
        references+=layout.fetch('free',{}).filter_map { |id,p| [p,nil] if id!=moving }
        if board
          references+=layout.fetch('docks',{}).flat_map do |zone,points|
            points.each_with_index.filter_map { |p,index| [p,nil] if board['docks'][zone][index] && board['docks'][zone][index]!=moving }
          end
        end
        position={};guides=[]
        %w[x y].each_with_index do |axis,index|
          near=references.min_by { |p,_slot| (p[index]-point[index]).abs }
          if near && (near[0][index]-point[index]).abs<=10 && near[0][index].between?(pad,(index.zero? ? width : height)-pad)
            point[index]=near[0][index];guides << [axis,point[index]]
            position['snap_'+axis]=near[1] unless near[1].nil?
          end
          position[axis]=point[index]-layout['center'][index]
        end
        position['relative']=true
        {'position'=>position,'point'=>point,'guides'=>guides}
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

# encoding: UTF-8
require_relative 'assembly_math'

module MH
  module ModuleStudio
    # Portable plane discovery. Automatic links use six oriented module envelope
    # planes in world millimetres, independent of internal panel topology.
    module AssemblyInference
      extend self

      def cross2(a,b)
        a[0]*b[1]-a[1]*b[0]
      end

      def clip(subject,border)
        border.each_with_index do |start,index|
          finish = border[(index+1)%border.length]
          edge = finish.zip(start).map { |a,b| a-b }
          output = []
          subject.each_with_index do |point,i|
            previous = subject[(i-1)%subject.length]
            a = cross2(edge,previous.zip(start).map { |x,y| x-y })
            b = cross2(edge,point.zip(start).map { |x,y| x-y })
            if (a>=0)!=(b>=0)
              ratio = a/(a-b)
              output << previous.zip(point).map { |x,y| x+ratio*(y-x) }
            end
            output << point if b>=0
          end
          subject = output
          break if subject.empty?
        end
        subject
      end

      def signed_area(points)
        points.each_with_index.sum { |point,index| cross2(point,points[(index+1)%points.length]) }/2.0
      end

      def contact(a,b,max_gap:)
        an = a.fetch('normal'); bn = b.fetch('normal')
        return unless AssemblyMath.dot(an,bn)<-0.999999
        gap = AssemblyMath.dot(AssemblyMath.sub(b['point'],a['point']),an)
        return if gap < -0.0001 || gap > max_gap+0.0001
        origin,u,v,polygons = projected(a,b)
        overlap = clip(polygons[1],polygons[0])
        return if overlap.length<3 || signed_area(overlap).abs<1.0
        center = 2.times.map { |axis| overlap.sum { |point| point[axis] }/overlap.length }
        point = AssemblyMath.add(origin,AssemblyMath.add(AssemblyMath.mul(u,center[0]),AssemblyMath.mul(v,center[1])))
        {'gap'=>gap,'area'=>signed_area(overlap).abs,'point'=>point,'normal'=>an,'relation'=>'contact'}
      end

      def projected(a,b)
        origin = a['points'].first
        u = AssemblyMath.unit(AssemblyMath.sub(a['points'][1],origin))
        v = AssemblyMath.unit(AssemblyMath.cross(a['normal'],u))
        polygons = [a,b].map do |plane|
          points = plane['points'].map do |point|
            relative = AssemblyMath.sub(point,origin)
            [AssemblyMath.dot(relative,u),AssemblyMath.dot(relative,v)]
          end
          signed_area(points).negative? ? points.reverse : points
        end
        [origin,u,v,polygons]
      end

      def segment_distance2(point,a,b)
        edge = b.zip(a).map { |x,y| x-y }; delta = point.zip(a).map { |x,y| x-y }
        length = edge.sum { |x| x*x }
        t = length.zero? ? 0 : [[delta.zip(edge).sum { |x,y| x*y }/length.to_f,0].max,1].min
        delta.zip(edge).sum { |x,y| (x-t*y)**2 }
      end

      def coplanar(a,b,max_gap:)
        aligned(a,b,max_gap:max_gap,plane_gap:0.02,relation:'coplanar')
      end

      def parallel(a,b,max_gap:)
        facing=AssemblyMath.dot(a.fetch('normal'),b.fetch('normal'))
        return unless facing.abs>0.999999
        return if facing.negative? && AssemblyMath.dot(AssemblyMath.sub(b['point'],a['point']),a['normal']) < -0.0001
        aligned(a,b,max_gap:max_gap,plane_gap:max_gap,relation:'parallel')
      end

      def aligned(a,b,max_gap:,plane_gap:,relation:)
        normal = a.fetch('normal')
        return unless AssemblyMath.dot(normal,b.fetch('normal')).abs>0.999999
        gap = AssemblyMath.dot(AssemblyMath.sub(b['point'],a['point']),normal)
        return if gap.abs>plane_gap+0.0000001
        _origin,_u,_v,polygons = projected(a,b)
        overlap = clip(polygons[1],polygons[0])
        area = overlap.length<3 ? 0 : signed_area(overlap).abs
        distance = if area>0.000001
                     0.0
                   else
                     [polygons,polygons.reverse].flat_map do |left,right|
                       left.flat_map { |point| right.each_with_index.map { |start,i| segment_distance2(point,start,right[(i+1)%right.length]) } }
                     end.min
                   end
        return if distance>(max_gap+0.0001)**2
        {'gap'=>gap,'area'=>area,'point'=>a['point'],'normal'=>normal,'b_normal'=>b['normal'],'relation'=>relation,'separation'=>Math.sqrt(distance)}
      end

      def candidates(modules,max_gap:)
        max_gap = Core.number(max_gap)
        raise Core::Error,'Khoảng tìm mặt phải từ 0 đến 1000 mm.' unless max_gap.between?(0,1000)
        result = []
        modules.combination(2) do |a,b|
          a.fetch('faces').each do |af|
            b.fetch('faces').each do |bf|
              geometry = contact(af['plane'],bf['plane'],max_gap:max_gap) || coplanar(af['plane'],bf['plane'],max_gap:max_gap) || parallel(af['plane'],bf['plane'],max_gap:max_gap)
              result << geometry.merge('a'=>af['anchor'],'b'=>bf['anchor']) if geometry
            end
          end
        end
        result.sort_by { |row| [{'contact'=>0,'coplanar'=>1,'parallel'=>2}.fetch(row['relation']),row.fetch('separation',row['gap']), -row['area'],JSON.generate([row['a'],row['b']])] }
      end

      def duplicate?(records,a,b)
        records.any? do |row|
          next false unless row['mode']=='contact'
          (AssemblyMath.same_surface?(row['a'],a) && AssemblyMath.same_surface?(row['b'],b)) ||
            (AssemblyMath.same_surface?(row['a'],b) && AssemblyMath.same_surface?(row['b'],a))
        end
      end

      def legacy_panel_links(records,selected)
        records.select do |row|
          refs=%w[a b c r1 r2].filter_map { |key| row[key] }
          row['inferred']==true && !refs.empty? && refs.all? { |ref| selected.include?(AssemblyMath.root_identity(ref)) } &&
            refs.any? { |ref| ref['part'] || ref['panel'] || !ref.fetch('path',[]).empty? }
        end
      end

      def unobstructed?(candidate,modules)
        return true if candidate['relation']!='contact' || candidate['gap']<=0.02
        endpoints=[candidate['a'],candidate['b']].map { |ref| AssemblyMath.root_identity(ref) }
        modules.none? do |mod|
          faces=mod.fetch('faces')
          next false if faces.empty? || endpoints.include?(AssemblyMath.root_identity(faces.first['anchor']))
          low=0.005;high=candidate['gap']-0.005
          faces.all? do |face|
            plane=face['plane']
            distance=AssemblyMath.dot(AssemblyMath.sub(plane['point'],candidate['point']),plane['normal'])
            speed=AssemblyMath.dot(candidate['normal'],plane['normal'])
            if speed.abs<1.0e-9
              distance>=-0.0001
            else
              boundary=distance/speed
              speed.positive? ? high=[high,boundary].min : low=[low,boundary].max
              high-low>0.0001
            end
          end
        end
      end

      def record(a,b,gap)
        row = {'id'=>Core::Ids.uuid,'mode'=>'contact','gap'=>gap,'a'=>Core.copy_data(a),'b'=>Core.copy_data(b),'inferred'=>true}
        scopes = [a['scope'],b['scope']].uniq
        if a['level']=='assembly' || b['level']=='assembly' || scopes.length>1
          row['external'] = true
        elsif scopes.first
          row['scope'] = scopes.first
          row['id'] = scopes.first+':'+row['id']
        end
        row
      end

      def choose(candidates,existing)
        result = []
        # Repeated/copied modules remain controlled by their original source.
        copies = existing.flat_map { |row| row.fetch('copies',[]).map { |pid| [row['scope'],pid] } }
        candidates.each do |candidate|
          a = candidate['a']; b = candidate['b']
          next if [a,b].any? { |ref| copies.include?(AssemblyMath.root_identity(ref)) }
          next if duplicate?(existing+result,a,b)
          next if candidate['visible']==false
          # Prefer one direction for the pair. If an existing dependency requires
          # the reverse, both outward normals reverse, retaining the same gap.
          reverse_gap = %w[coplanar parallel].include?(candidate['relation']) ? -candidate['gap']*AssemblyMath.dot(candidate['normal'],candidate['b_normal']) : candidate['gap']
          [record(a,b,candidate['gap']),record(b,a,reverse_gap)].each do |row|
            row['relation'] = candidate.fetch('relation','contact')
            begin
              AssemblyMath.ordered(existing+result+[row])
              yield(existing+result+[row]) if block_given?
            rescue Core::Error
              next
            end
            result << row
            break
          end
        end
        result
      end
    end
  end
end

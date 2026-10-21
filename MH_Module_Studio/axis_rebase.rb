# encoding: UTF-8
module MH
  module ModuleStudio
    # Canonical axes for cardinally rotated trees. Only calculation data changes;
    # native mesh bindings keep their original transforms and world geometry.
    module AxisRebase
      extend self
      LENGTHS=%w[lenx leny lenz].freeze
      POSITIONS=%w[x y z].freeze
      IDENTITY=[[0,1.0],[1,1.0],[2,1.0]].freeze

      def enable(snapshot)
        data=Core.copy_data(snapshot);graph=data['dc_graph'];return data unless graph
        nodes={''=>{'name'=>'Module','attributes'=>data.fetch('dc_inputs',{}),'path'=>[]}}
        graph['nodes'].each { |n| nodes[n.key?('parent_id') ? n['id'] : n['path'].join(' / ')]=n }
        bases={''=>IDENTITY};columns={};build=nil
        build=lambda do |id,stack|
          next bases[id] if bases.key?(id)
          raise Core::Error,'Cây hệ trục vòng.' if stack.include?(id) || stack.length>30
          node=nodes.fetch(id);frame=node['transform'];up=build.call(parent(nodes,id),stack+[id])
          axis=3.times.map do |j|
            indices=3.times.select { |i| frame[j*4+i].abs>1.0e-7 }
            raise Core::Error,'Chưa đổi hệ trục không vuông góc.' unless indices.length==1
            k=indices.first;[k,frame[j*4+k]]
          end
          raise Core::Error,'Hệ trục suy biến.' unless axis.map(&:first).uniq.length==3
          columns[id]=axis
          bases[id]=axis.map { |k,value| [up[k][0],up[k][1]*(value.negative? ? -1.0 : 1.0)] }
        end
        nodes.keys.reject(&:empty?).each { |id| build.call(id,[]) }
        return data if bases.values.all? { |basis| basis==IDENTITY }
        aliases=DCFormulas.function_aliases(data)
        nodes.each do |id,node|
          own=bases[id];up=id.empty? ? IDENTITY : bases.fetch(parent(nodes,id))
          rewritten={}
          node['attributes'].each do |key,original|
            value=original;fresh=key;sign=1.0
            field=key[/\A_?(len[xyz]|[xyz])(?:_|\z)/,1]
            if field
              index=LENGTHS.index(field)
              mapping=index ? own[index] : up[POSITIONS.index(field)]
              mapped=index ? LENGTHS[mapping[0]] : POSITIONS[mapping[0]]
              sign=index ? 1.0 : mapping[1]
              fresh=key.sub(field,mapped)
            end
            if key.end_with?('_formula') && original.is_a?(String) && !original.strip.empty?
              begin
                ast=DCFormulas::Parser.new(original,aliases:aliases).parse
                value=text(ast,nodes,bases,id)
                value="-(#{value})" if sign.negative?
              rescue Core::Error
                value=original
              end
            elsif field && POSITIONS.include?(field) && key==field && sign.negative?
              value=-Core.number(original)
            end
            rewritten[fresh]=value
          end
          node['attributes']=rewritten
        end
        nodes.each do |id,node|
          next if id.empty?
          own=bases[id];up=bases.fetch(parent(nodes,id));old=node['transform'];fresh=Frames::IDENTITY.dup
          up.each_with_index { |(i,sign),j| fresh[12+i]=sign*old[12+j] }
          columns.fetch(id).each_with_index { |(_k,scale),j| fresh[own[j][0]*5]=scale.abs }
          points=Frames.corners(node['local_bounds']).map do |point|
            result=[0.0,0.0,0.0];own.each_with_index { |(i,sign),j| result[i]=sign*point[j] };result
          end
          node['transform']=fresh;node['local_bounds']=Frames.box(points)
        end
        data['dc_inputs']=nodes['']['attributes']
        data['axis_rebases']=bases.reject { |id,basis| id.empty? || basis==IDENTITY }
        data
      rescue Core::Error,KeyError
        Core.copy_data(snapshot)
      end

      def text(ast,nodes,bases,path)
        kind,name,left,right=ast
        case kind
        when :number then name.to_s
        when :unary then "#{name}(#{text(left,nodes,bases,path)})"
        when :binary then "(#{text(left,nodes,bases,path)}) #{name} (#{text(right,nodes,bases,path)})"
        when :call then "#{name}(#{left.map { |arg| text(arg,nodes,bases,path) }.join(', ')})"
        when :nominal
          target=resolve(nodes,path,name);axis=LENGTHS.index(left)
          "mh_parent_#{LENGTHS[bases.fetch(target)[axis][0]]}()"
        when :reference
          return left if name.nil? && %w[true false].include?(left)
          target=resolve(nodes,path,name);field=left;sign=1.0
          if LENGTHS.include?(field)
            field=LENGTHS[bases.fetch(target)[LENGTHS.index(field)][0]]
          elsif POSITIONS.include?(field)
            up=target.empty? ? IDENTITY : bases.fetch(parent(nodes,target))
            index,sign=up[POSITIONS.index(field)];field=POSITIONS[index]
          end
          value=(name ? name+'!' : '')+field
          sign.negative? ? "-(#{value})" : value
        else raise Core::Error,'Không đổi được tham chiếu hệ trục.'
        end
      end

      def parent(nodes,id)
        node=nodes.fetch(id)
        node.key?('parent_id') ? node['parent_id'] : node['path'][0...-1].join(' / ')
      end

      def resolve(nodes,path,qualifier)
        return path unless qualifier
        return parent(nodes,path) if qualifier=='parent' && !path.empty?
        scope=path
        loop do
          node=nodes.fetch(scope)
          return scope if [node['name'],node['attributes']['_name']].any? { |name| name.to_s.downcase==qualifier }
          break if scope.empty?
          scope=parent(nodes,scope)
        end
        matches=nodes.keys.select { |id| [nodes[id]['name'],nodes[id]['attributes']['_name']].any? { |name| name.to_s.downcase==qualifier } }
        raise Core::Error,"Tham chiếu ATT không rõ group: #{qualifier}" unless matches.length==1
        matches.first
      end
    end
  end
end

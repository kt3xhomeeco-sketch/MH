# encoding: UTF-8
module MH
  module ModuleStudio
    # Portable selection policy; native SKP reads and fitting stay in adapters.
    module DrawerVariants
      extend self
      def info(item)
        name=item.fetch('name','').unicode_normalize(:nfd).gsub(/\p{Mn}/,'').downcase.tr('đ','d')
        name=name.gsub(/(?<=\d)(?=[a-z])|(?<=[a-z])(?=\d)/,' ').gsub(/\s+/,' ').strip
        return unless name.include?('ngan keo') && !name.match?(/\b(?:khung|mat)\b/)
        numbers=name.to_enum(:scan,/\b\d+(?:[.,]\d+)?\b/).map { Regexp.last_match }
        size=numbers.reverse.find { |match| match[0].tr(',','.').to_f.between?(200,700) }
        family=size ? name[0...size.begin(0)]+name[size.end(0)..] : name
        kind=name.match?(/\b(?:ray am|ngan keo am)\b/) ? 'concealed' : 'ball'
        {'family'=>[item['folder'],family.gsub(/\s+/,' ').strip],'kind'=>kind,
         'size'=>size && size[0].tr(',','.').to_f,'clearance'=>kind=='concealed' ? 15.0 : 5.0}
      end
      def choose(entries,id,depth)
        source=entries.find { |item| item['id']==id };own=source && info(source);return unless own
        candidates=entries.filter_map do |item|
          spec=info(item)
          [item,spec] if spec && spec['size'] && spec['family']==own['family'] && spec['kind']==own['kind']
        end
        return if candidates.empty?
        usable=Core.number(depth)-own['clearance']
        chosen=candidates.select { |_item,spec| spec['size']<=usable+0.5 }.sort_by { |item,spec| [-spec['size'],item['id']==id ? 0 : 1,item['id']] }.first
        unless chosen
          minimum=candidates.map { |_item,spec| spec['size'] }.min+own['clearance']
          raise Core::Error,"Khoang sâu #{depth.round(2)} mm không đủ cho ray nhỏ nhất; cần ít nhất #{minimum.round(2)} mm."
        end
        {'id'=>chosen[0]['id'],'size'=>chosen[1]['size'],'kind'=>own['kind'],'clearance'=>own['clearance'],'available_depth'=>depth}
      end
      def fit_bounds(data,placement)
        return placement unless data['drawer_fit'] && %w[cavity replace].include?(placement['mode'])
        result=Core.copy_data(placement)
        result['fit_depth_mm']=data['drawer_fit']['available_depth']
        scale=Frames.scale_frame(result['frame'])[5]
        depth=Core.dimensions(data['snapshot']['envelope'])[1]/scale
        raise Core::Error,'Chiều sâu mẫu ngăn kéo vượt quá vùng Fit.' if depth>Core.dimensions(result['bounds'])[1]+0.02/scale
        result['bounds'][1][1]=result['bounds'][0][1]+depth
        result
      end
    end
  end
end

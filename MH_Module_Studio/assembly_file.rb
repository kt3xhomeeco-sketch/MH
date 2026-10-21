# encoding: UTF-8
require_relative 'assembly'

module MH
  module ModuleStudio
    # SKP assembly payloads keep member programs independent and contacts local.
    # Temporary export/load work always aborts before the output is replaced.
    module AssemblyFile
      extend self
      FORMAT = 'mh_module_assembly'.freeze

      def payload(data)
        unless data.is_a?(Hash) && data['format']==FORMAT && data['version']==1 && data['members'].is_a?(Array) &&
               data['members'].length.between?(1,100) && data['links'].is_a?(Array) && data['links'].length<=200
          raise Core::Error,'Dữ liệu cụm module không hợp lệ.'
        end
        keys = data['members'].map { |member| member['key'] }
        raise Core::Error,'Khóa module trong cụm không hợp lệ.' unless keys.all? { |key| key.is_a?(String) && !key.empty? } && keys.uniq==keys
        Core.bounds!(data.fetch('snapshot').fetch('envelope'))
        Core.bounds!(data['construction_envelope']) if data['construction_envelope']
        data['members'].each do |member|
          frame = member['frame']
          raise Core::Error,'Thiếu phép đặt module con.' unless frame.is_a?(Array) && frame.length==16 && frame.all? { |value| value.is_a?(Numeric) && value.finite? }
          Frames.scale_frame(frame)
          next unless member['rule']
          Core.rule!(member['rule']); Core.snapshot!(member.fetch('snapshot'))
          raise Core::Error,'Thiếu giá trị tham số module con.' unless member['values'].is_a?(Hash)
        end
        data['links'].each do |row|
          raise Core::Error,'Kiểu liên kết trong file không hợp lệ.' unless row.is_a?(Hash) && AssemblyMath::MODES.include?(row['mode']) && row['id'].is_a?(String)
          raise Core::Error,'Liên kết ngoài cụm không thể lưu độc lập.' if row['scope'] || row['external']
          required = row['mode']=='repeat' ? (row['equal'] ? %w[a b c] : %w[b]) : %w[center fit].include?(row['mode']) ? %w[a b c] : %w[a b]
          raise Core::Error,'Thiếu mặt của liên kết.' unless required.all? { |key| row[key].is_a?(Hash) }
          Core.number(row.fetch('gap',0))
          AssemblyContainers.references(row).each do |ref|
            raise Core::Error,'Mặt tham chiếu không thuộc cụm.' unless keys.include?(ref['root']) && !ref['scope']
            next if row.fetch('copies',[]).include?(ref['root']) && !ref['axis']
            raise Core::Error,'Mặt tham chiếu không hợp lệ.' unless [0,1,2].include?(ref['axis']) && [0,1].include?(ref['side'])
          end
        end
        if data['master_member'] && !keys.include?(data['master_member'])
          raise Core::Error,'Module chủ không thuộc cụm đã lưu.'
        end
        AssemblyMath.ordered(data['links'])
        data
      end

      def local_links(model,root)
        scope = root.persistent_id.to_s
        all = Assembly.records(model)
        if all.any? { |row| row['external'] && AssemblyContainers.references(row).any? { |ref| ref['scope']==scope || ref['root']==scope } }
          raise Core::Error,'Cụm còn liên kết với đối tượng bên ngoài; tách liên kết ngoài trước khi lưu riêng.'
        end
        mapping = AssemblyContainers.members(root).to_h { |child| [child.persistent_id.to_s,AssemblyContainers.member_key(child)] }
        all.select { |row| row['scope']==scope }.map do |row|
          copy = Core.copy_data(row); copy.delete('scope'); copy['id'] = AssemblyContainers.local_id(copy['id'])
          AssemblyContainers::REFS.each do |key|
            ref = copy[key]; next unless ref
            if !ref['part'] && !ref['panel'] && !ref.fetch('path',[]).empty?
              item, = Assembly.panel(model,row[key])
              panel_key = item.get_attribute(Reader::DICT,AssemblyContainers::PANEL) || Core::Ids.uuid
              item.set_attribute(Reader::DICT,AssemblyContainers::PANEL,panel_key)
              ref['panel'] = panel_key
            end
            ref['root'] = mapping.fetch(ref['root']); ref.delete('scope'); ref['path'] = []
          end
          copy['copies']&.map! { |pid| mapping.fetch(pid) }
          copy
        end
      end

      def restore(root,data,validate:true)
        payload(data)
        root.set_attribute(Reader::DICT,AssemblyContainers::FLAG,true)
        root.set_attribute(Reader::DICT,AssemblyParameters::KEY,data['master_member']) if data['master_member']
        root.name = data['name'].to_s
        AssemblyEnvelope.remember(root,data['construction_envelope'] || data['snapshot']['envelope'])
        children = AssemblyContainers.members(root)
        mapping = children.to_h { |child| [child.get_attribute(Reader::DICT,AssemblyContainers::MEMBER),child] }
        raise Core::Error,'Các module con trong SKP không khớp cụm.' unless mapping.keys.sort==data['members'].map { |member| member['key'] }.sort
        rows = Core.copy_data(data['links'])
        rows.each do |row|
          AssemblyContainers::REFS.each { |key| row[key]['root']=mapping.fetch(row[key]['root']).persistent_id.to_s if row[key] }
          row['copies']&.map! { |key| mapping.fetch(key).persistent_id.to_s }
        end
        root.set_attribute(Reader::DICT,AssemblyContainers::KEY,JSON.generate(rows))
        return root unless validate
        raise Core::Error,'Phủ bì cụm SKP không khớp dữ liệu.' unless Core.bounds_close?(AssemblyEnvelope.bounds(root),data['snapshot']['envelope'],0.02)
        data['members'].each do |entry|
          child = mapping.fetch(entry['key'])
          unless child.transformation.to_a.zip(entry['frame']).all? { |a,b| (a-b).abs<0.000001 }
            raise Core::Error,'Vị trí hoặc tỷ lệ module con không khớp file cụm.'
          end
          next unless entry['rule']
          rule = ThicknessSymbols.normalize(Core.rule!(Core.copy_data(entry['rule'])))
          Runtime.store_formula_envelope(child,entry['snapshot']['formula_envelope']) if entry['snapshot']['formula_envelope']
          current,bindings = Reader.live(child,label:child.name,parameter:Runtime.read_parameter(rule,entry['values']))
          expected = entry['snapshot']['parts'].to_h { |part| [part['key'],part] }
          raise Core::Error,'Hình học module con không khớp file cụm.' unless current['parts'].length==expected.length && current['parts'].all? do |part|
            expected[part['key']] && Core.bounds_close?(part['bounds'],expected[part['key']]['bounds'])
          end
          raise Core::Error,'Công thức module con chưa khớp hình học.' unless Core.plan(rule,current,entry['values'])['changed_count'].zero?
          Runtime.stamp(child,rule,bindings,entry['values'])
        end
        scoped = rows.map do |row|
          record = Core.copy_data(row); record['scope'] = root.persistent_id.to_s
          AssemblyContainers::REFS.each { |key| record[key]['scope']=root.persistent_id.to_s if record[key] }
          record
        end
        scoped.each { |row| Assembly.verify(root.model,row) }
        root
      end

      def save(root,path)
        model = root.model
        Runtime.ensure_top_level(model)
        raise Core::Error,'Chọn component cụm đã Gộp.' unless AssemblyContainers.managed?(root) && root.is_a?(Sketchup::ComponentInstance) && !root.locked?
        path = File.expand_path(path)
        raise Core::Error,'Chọn file SKP riêng cho cụm.' if File.extname(path).downcase!='.skp' || !model.path.empty? && File.expand_path(model.path).casecmp?(path)
        temporary = File.join(File.dirname(path),'.mh-assembly-'+Core::Ids.hex(6)+'.skp')
        before = File.file?(path) ? Digest::SHA256.file(path).hexdigest : nil
        Assembly.instance_variable_set(:@busy,true)
        model.start_operation('MH Lưu Cụm Module',true); operation = true
        links = local_links(model,root)
        copy = model.active_entities.add_instance(root.definition,Geom::Transformation.new)
        copy.name = root.name
        copy.material = root.material
        Runtime.private_tree(copy)
        scale = Geom::Transformation.new(Frames.scale_frame(root.transformation.to_a))
        copy.definition.entities.transform_entities(scale,copy.definition.entities.to_a)
        members = AssemblyContainers.members(copy).map do |child|
          child.material = copy.material if copy.material && child.material.nil?
          entry = {'key'=>AssemblyContainers.member_key(child),'name'=>child.name,'frame'=>child.transformation.to_a}
          raw = child.get_attribute(Reader::DICT,'rule_json')
          if raw
            rule = ThicknessSymbols.normalize(Core.rule!(JSON.parse(raw)))
            values = JSON.parse(child.get_attribute(Reader::DICT,'parameter_values_json','{}'))
            rule = Parametric.with_values(rule,values)
            snapshot,bindings = Reader.live(child,label:child.name,parameter:Runtime.read_parameter(rule,values))
            raise Core::Error,'Module con cần cập nhật hình học trước khi lưu cụm.' unless Core.plan(rule,snapshot,values)['changed_count'].zero?
            Runtime.stamp(child,rule,bindings,values)
            entry.merge!('rule'=>rule,'values'=>values,'snapshot'=>snapshot)
          end
          entry
        end
        construction = Frames.box(Frames.corners(AssemblyEnvelope.target(root)).map { |point| Frames.point(scale.to_a,point) })
        data = payload({'format'=>FORMAT,'version'=>1,'name'=>root.name,'members'=>members,'links'=>links,'snapshot'=>{'envelope'=>AssemblyEnvelope.bounds(copy)},'construction_envelope'=>construction})
        master=root.get_attribute(Reader::DICT,AssemblyParameters::KEY)
        data['master_member']=master if master
        payload(data)
        restore(copy,data)
        copy.definition.set_attribute(Reader::DICT,LibraryCatalog::PAYLOAD_KEY,JSON.generate(data))
        copy.definition.name = root.name
        copy.definition.refresh_thumbnail
        raise Core::Error,'Không ghi được file cụm SKP.' unless copy.definition.save_copy(temporary)
        model.abort_operation; operation = false
        # Re-open the exact saved file before replacing any existing destination.
        model.start_operation('MH Kiểm Tra File Cụm',true); operation = true
        definition = model.definitions.load(temporary)
        probe = model.active_entities.add_instance(definition,Geom::Transformation.new)
        saved = LibraryCatalog.payload(definition.get_attribute(Reader::DICT,LibraryCatalog::PAYLOAD_KEY))
        restore(probe,saved)
        model.abort_operation; operation = false
        raise Core::Error,'File đã đổi trong lúc lưu; chưa ghi đè.' if before && Digest::SHA256.file(path).hexdigest!=before
        if File.file?(path)
          directory = File.join(File.dirname(path),'.mh-backups'); FileUtils.mkdir_p(directory)
          FileUtils.cp(path,File.join(directory,File.basename(path,'.skp')+'-'+Core::Ids.hex(8)+'.skp'))
        end
        FileUtils.mv(temporary,path,force:true)
        path
      ensure
        model.abort_operation if operation
        File.delete(temporary) if temporary && File.file?(temporary)
        Assembly.instance_variable_set(:@busy,false)
        Assembly.watch(model).reset if model
        ScaleRedraw.watch(model).reset if model
      end
    end
  end
end

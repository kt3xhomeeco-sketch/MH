# encoding: UTF-8
require_relative 'library'

module MH
  module ModuleStudio
    # Explicit file writes only. A component is patched in an aborted native
    # transaction, verified and then replaces the selected SKP with a backup.
    module ModuleFile
      extend self

      def signature(path)
        Digest::SHA256.file(path).hexdigest
      end

      def with_root(path)
        model = Sketchup.active_model
        Runtime.ensure_top_level(model)
        Dir.mktmpdir('mh-module-file-') do |directory|
          input = File.join(directory,'input.skp')
          FileUtils.cp(path,input)
          model.start_operation('MH Đọc File Module',true)
          operation = true
          definition = model.definitions.load(input)
          root = model.active_entities.add_instance(definition,Geom::Transformation.new)
          yield root
        ensure
          model.abort_operation if operation
        end
      end

      def read(path)
        with_root(path) do |root|
          raw = root.definition.get_attribute(Reader::DICT,LibraryCatalog::PAYLOAD_KEY)
          raw ? LibraryCatalog.payload(raw) : nil
        end
      end

      def save(path, rule, snapshot, expected: nil, source_root: nil, source_path: nil, source_expected: nil)
        rule = ThicknessSymbols.normalize(rule)
        path = File.expand_path(path)
        raise Core::Error, 'Chỉ lưu file .skp.' unless File.extname(path).downcase == '.skp'
        model = Sketchup.active_model
        if !model.path.empty? && File.expand_path(model.path).casecmp?(path)
          raise Core::Error, 'Đây là toàn bộ model đang mở. Chọn file module riêng trong folder.'
        end
        existed = File.file?(path)
        before = existed ? signature(path) : nil
        raise Core::Error, 'File đã đổi bên ngoài. Đọc lại SKP trước khi ghi đè.' if expected && before != expected
        origin = File.expand_path(source_path) if source_path
        origin_signature = signature(origin) if origin
        raise Core::Error,'File nguồn đã đổi; đọc lại SKP trước khi lưu tên mới.' if source_expected && origin_signature!=source_expected
        values = Parametric.targets(rule)
        plan = Core.plan(rule,snapshot,values)
        temporary = File.join(File.dirname(path),'.mh-save-'+Core::Ids.hex(6)+'.skp')
        if source_root
          Library.new.require_owned(source_root)
          model.start_operation('MH Lưu Module',true)
          operation = true
          copy = model.active_entities.add_instance(source_root.definition,Geom::Transformation.new)
          copy.name = source_root.name
          copy.material = source_root.material
          Runtime.private_tree(copy)
          if copy.material
            copy.definition.entities.each do |entity|
              entity.material = copy.material if entity.respond_to?(:material) && entity.material.nil?
            end
          end
          frame = Geom::Transformation.new(Frames.scale_frame(source_root.transformation.to_a))
          copy.definition.entities.transform_entities(frame,copy.definition.entities.to_a)
          Runtime.store_formula_envelope(copy,snapshot['formula_envelope']) if snapshot['formula_envelope']
          saved_values = JSON.parse(source_root.get_attribute(Reader::DICT,'parameter_values_json','{}'))
          write_root(copy,rule,values,temporary,saved_values:saved_values)
          model.abort_operation
          operation = false
        elsif origin
          with_root(origin) { |root| write_root(root,rule,values,temporary) }
        elsif existed
          with_root(path) { |root| write_root(root,rule,values,temporary) }
        else
          raise Core::Error, 'Tạo file mới cần các tấm hộp đã xác minh.' unless plan['parts'].all? { |part| part['box_verified'] }
          model.start_operation('MH Chuẩn Bị File SKP',true)
          operation = true
          definition = model.definitions.add('MH File Module')
          root = model.active_entities.add_instance(definition,Geom::Transformation.new)
          Runtime.populate_parts(definition,plan)
          root.name = rule['module_name'] || snapshot['label'].to_s
          root.set_attribute(Reader::DICT,'parameter_values_json',JSON.generate(plan['target']))
          Runtime.store_formula_envelope(root,plan['formula_envelope']) if plan['formula_envelope']
          write_root(root,rule,values,temporary)
          model.abort_operation
          operation = false
        end
        verified = Library.new.verify_file(temporary)
        raise Core::Error, 'File vừa ghi không giữ đúng quy tắc.' unless verified && verified['rule'] == rule
        raise Core::Error, 'File đã đổi trong lúc lưu. Chưa ghi đè.' if existed && signature(path) != before
        raise Core::Error,'File nguồn đã đổi trong lúc lưu; chưa ghi file mới.' if origin && signature(origin)!=origin_signature
        backup = nil
        if existed
          directory = File.join(File.dirname(path),'.mh-backups')
          FileUtils.mkdir_p(directory)
          backup = File.join(directory,File.basename(path,'.skp')+'-'+Time.now.strftime('%Y%m%d-%H%M%S')+'-'+Core::Ids.hex(3)+'.skp')
          FileUtils.cp(path,backup)
        end
        FileUtils.mv(temporary,path,force:true)
        { 'path'=>path,'signature'=>signature(path),'backup'=>backup,'snapshot'=>verified['snapshot'],'rule'=>rule }
      ensure
        model.abort_operation if operation
        File.delete(temporary) if temporary && File.file?(temporary)
      end

      def write_root(root, rule, values, path, saved_values: nil)
        root.name = rule['module_name'] if rule['module_name']
        root.definition.name = root.name unless root.name.empty?
        payload = root.definition.get_attribute(Reader::DICT,LibraryCatalog::PAYLOAD_KEY)
        data = payload ? LibraryCatalog.payload(payload) : nil
        saved = saved_values || (data ? data['values'] : values)
        root.name = data['name'].to_s if data && root.name.empty?
        root.set_attribute(Reader::DICT,'parameter_values_json',JSON.generate(saved))
        Runtime.store_formula_envelope(root,data['snapshot']['formula_envelope']) if data&.dig('snapshot','formula_envelope') && !saved_values
        current, bindings = Reader.live(root,label:root.name,parameter:Runtime.read_parameter(rule,saved))
        keys = current['parts'].map { |part| part['key'] }.sort
        raise Core::Error, 'Chi tiết của file không khớp module đang sửa; chưa ghi đè.' unless DCCopies.enabled?(rule) || keys == rule['parts'].map { |part| part['key'] }.sort
        plan = Core.plan(rule,current,values)
        Runtime.apply_plan(bindings,plan,rule:rule)
        Runtime.stamp(root,rule,bindings,plan['target'])
        Runtime.verify_result(root,plan)
        result, = Reader.live(root,label:current['label'],parameter:Runtime.read_parameter(rule,values))
        data = { 'format'=>'mh_module_library','version'=>1,'name'=>root.name.empty? ? root.definition.name : root.name,
                 'rule'=>rule,'values'=>plan['target'],'snapshot'=>result }
        Library.new.validate_geometry(root,data)
        root.definition.set_attribute(Reader::DICT,LibraryCatalog::PAYLOAD_KEY,JSON.generate(data))
        root.definition.refresh_thumbnail
        raise Core::Error, 'Không ghi được file SKP.' unless root.definition.save_copy(path)
      end
    end
  end
end

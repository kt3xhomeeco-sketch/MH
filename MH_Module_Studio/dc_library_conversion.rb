# encoding: UTF-8
# Native file conversion; never redraw or modify the user's source DCs.
require 'json'
require 'csv'
require 'digest'
require 'fileutils'
require 'time'
require_relative 'runtime'
require_relative 'library_catalog'

module MH
  module ModuleStudio
    class DCLibraryConversion
      PROFILE = 'conversion-070'.freeze
      attr_reader :report

      def initialize(source:, destination:, paths: nil, update: false, &publisher)
        raise Core::Error, 'Folder nguồn không tồn tại.' unless File.directory?(source)
        raise Core::Error,'Chọn folder đích để lưu thư viện.' unless File.directory?(destination)
        @source=File.realpath(source).tr('\\','/')
        @destination=File.realpath(destination).tr('\\','/')
        if LibraryCatalog.inside?(@source,@destination) || LibraryCatalog.inside?(@destination,@source)
          raise Core::Error,'Folder nguồn và đích phải tách riêng, không nằm trong nhau.'
        end
        @model=Sketchup.active_model
        Runtime.ensure_top_level(@model)
        raise Core::Error,'Đóng HUD trước khi chuyển thư viện.' if MH::ModuleStudio.library.tool
        @roots=@model.active_entities.to_a;@definitions=@model.definitions.to_a;@selection=@model.selection.to_a
        @library=Library.new
        @update=update;@publisher=publisher
        @folder=File.join(@destination,'.conversion');FileUtils.mkdir_p(@folder)
        raise Core::Error,'Folder báo cáo nằm ngoài thư viện đích.' unless LibraryCatalog.inside?(@destination,@folder)
        previous=File.join(@folder,'report.json')
        @previous_rows={}
        if File.file?(previous)
          raise Core::Error,'Báo cáo cũ vượt 16 MB.' if File.size(previous)>16*1024*1024
          begin
            prior=JSON.parse(File.read(previous,encoding:'UTF-8'))
            rows=prior.fetch('files',[])
            known=prior.fetch('known_outputs',{})
            @previous_rows=rows.to_h { |row| [row['relative'],row] }.merge(known)
          rescue JSON::ParserError,KeyError,TypeError
            @previous_rows={}
          end
          FileUtils.cp(previous,File.join(@folder,'report-before-'+Core::Ids.hex(6)+'.json'))
        end
        all=LibraryCatalog.scan(@source)['entries'].map { |row| row['path'] }
        @paths=paths ? all.select { |path| paths.include?(relative(path)) } : all
        @hashes={}
        @report={'source'=>@source,'destination'=>@destination,'profile'=>PROFILE,'total'=>@paths.length,
                 'started_at'=>Time.now.utc.iso8601,'status'=>'ready','files'=>[]}
      end

      def running?
        @report['status']=='running'
      end

      def cancel
        return unless running?
        finish(status:'cancelled') unless @working
        @cancel_requested=true
      end

      def relative(path)
        path.tr('\\', '/').delete_prefix(@source + '/')
      end

      def start
        @report['status']='running'
        write_report
        @timer = UI.start_timer(0.1, true) { tick }
        self
      end

      def tick
        return if @working || !running?
        @working = true
        unless Sketchup.active_model.equal?(@model) && !@model.active_path
          raise Core::Error, 'Model thử đã đổi hoặc đang sửa group; dừng chuyển đổi.'
        end
        path = @paths[@report['files'].length]
        unless path
          finish
          return
        end
        row = convert(path)
        @report['files'] << row
        if @cancel_requested
          finish(status:'cancelled')
          return
        end
        write_report
        Sketchup.status_text = "MH chuyển thư viện: #{@report['files'].length}/#{@paths.length} · #{@report['converted']} thành công"
      rescue StandardError => error
        @report['status'] = 'stopped'
        @report['fatal_error'] = "#{error.class}: #{error.message}"
        UI.stop_timer(@timer) if @timer
        write_report
      ensure
        @working = false
      end

      def dictionary_copy(source, target)
        attrs = Reader.dynamic_attributes(source)
        attrs.each { |key, value| target.set_attribute('dynamic_attributes', key, value) }
      end

      # Keep formulas on private copies until the program has been validated.
      def normalize(root, depth = 0)
        raise Core::Error, 'Cây chi tiết quá sâu hoặc có chi tiết khóa.' if depth > 30 || root.locked?
        root.make_unique
        entities = root.definition.entities
        entities.to_a.each do |child|
          next unless child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)
          raise Core::Error, 'Chi tiết nguồn bị khóa.' if child.locked?
          if child.is_a?(Sketchup::ComponentInstance)
            attrs = DCFrames.merge_attributes(Reader.dynamic_attributes(child.definition),Reader.dynamic_attributes(child))
            group = entities.add_group
            instance = group.entities.add_instance(child.definition, Geom::Transformation.new)
            raise Core::Error, 'Không chuyển được component con thành group.' unless instance.explode
            group.name = child.name.to_s.strip.empty? ? attrs.fetch('_name', child.definition.name).to_s : child.name
            group.transformation = child.transformation
            group.material = child.material
            group.layer = child.layer
            group.hidden = child.hidden?
            group.casts_shadows = child.casts_shadows?
            group.receives_shadows = child.receives_shadows?
            attrs.each { |key, value| group.set_attribute('dynamic_attributes', key, value) }
            child.erase!
            child = group
          end
          normalize(child, depth + 1)
        end
      end

      def assign_part_keys(root)
        serial = 0
        visit = lambda do |entity|
          items = entity.definition.entities.to_a
          if items.any? { |item| item.is_a?(Sketchup::Face) || item.is_a?(Sketchup::Edge) }
            serial += 1
            entity.set_attribute(Reader::DICT, 'part_key', format('part:%04d', serial))
          end
          items.each { |child| visit.call(child) if child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance) }
        end
        root.definition.entities.each do |child|
          visit.call(child) if child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)
        end
      end

      def bake_static_scale(root, snapshot)
        return false unless StaticGeometry.eligible?(snapshot)
        frame=snapshot.fetch('dc_graph').fetch('root_frame')
        return false if frame==Frames::IDENTITY
        scale=Geom::Transformation.new(frame)
        root.definition.entities.transform_entities(scale,root.definition.entities.to_a)
        root.transformation=root.transformation*scale.inverse
        root.definition.invalidate_bounds
        true
      end

      def unwrap(root)
        10.times do
          attrs = DCFrames.merge_attributes(Reader.dynamic_attributes(root.definition),Reader.dynamic_attributes(root))
          break unless Core.dc_controls('dc_inputs' => attrs).empty?
          break if attrs.keys.any? { |key| DCCustomInputs.candidate?(attrs,key) }
          children = root.definition.entities.to_a
          break unless children.length == 1 && (children.first.is_a?(Sketchup::Group) || children.first.is_a?(Sketchup::ComponentInstance))
          child = children.first
          instance = @model.active_entities.add_instance(child.definition, root.transformation * child.transformation)
          instance.name = child.name
          instance.material = child.material || root.material
          dictionary_copy(child, instance)
          root = instance
        end
        root
      end

      def convert(path, target_path: nil)
        raise Core::Error,'File nguồn ngoài danh sách chuyển.' unless @paths.include?(path) && LibraryCatalog.inside?(@source,path)
        @roots=@model.active_entities.to_a;@definitions=@model.definitions.to_a;@selection=@model.selection.to_a
        @hashes[path] ||= Digest::SHA256.file(path).hexdigest
        row = { 'relative' => relative(path), 'source_sha256' => @hashes.fetch(path), 'status' => 'failed' }
        target = target_path || File.join(@destination, relative(path))
        if target_path && (!LibraryCatalog.inside?(@destination,File.dirname(target)) || File.extname(target).downcase!='.skp')
          raise Core::Error,'File nâng cấp phải nằm trong thư viện đích.'
        end
        operation = false
        temporary = nil
        begin
          existing_hash=File.file?(target) ? Digest::SHA256.file(target).hexdigest : nil
          if File.exist?(target)
            prior=@previous_rows[row['relative']]
            verified=prior && (prior['status']=='converted' || prior['verified_export']==true) && prior['output_sha256']==existing_hash
            row.merge!('verified_export'=>true,'output_sha256'=>existing_hash) if verified
            unless @update && verified
              row['status']='existing'
              row['error']=verified ? 'File đã có; bật Cập nhật bản đã chuyển để nâng cấp.' : 'File đích đã có hoặc đã sửa; giữ nguyên file.'
              return row
            end
            row['replaced_existing']=true
          end
          raise Core::Error, 'Nguồn đổi từ khi bắt đầu.' unless Digest::SHA256.file(path).hexdigest == row['source_sha256']
          @model.start_operation('MH Chuyển Thư Viện', true)
          operation = true
          definition = @model.definitions.load(path)
          root = @model.active_entities.add_instance(definition, Geom::Transformation.new)
          root = unwrap(root)
          root=root.to_component if root.is_a?(Sketchup::Group)
          root.name = File.basename(path, File.extname(path))
          normalize(root)
          assign_part_keys(root)
          snapshot, bindings = Reader.live(root, label: root.name, parameter: nil)
          snapshot,bindings=Reader.live(root,label:root.name,parameter:nil) if bake_static_scale(root,snapshot)
          rule=StaticGeometry.eligible?(snapshot) ? StaticGeometry.build(snapshot) : StudioCalculation.build_system([snapshot])
          engine=rule['formula_engine']
          raise Core::Error,'Chưa dịch được ATT: '+rule['warnings'].join(' ') unless engine || rule['static_geometry']
          rule['module_name']=root.name
          rule['module_name_source']='source_file'

          values = Parametric.targets(rule)
          canonical_plan=Core.plan(rule,snapshot,values)
          checks = rule['parameters'].select { |param| param['editable'] }.map do |param|
            accepted = false
            message = nil
            current_value=values.fetch(param['key'],param['value'])
            candidates = [current_value+0.1,current_value-0.1,engine.dig('rules',param['key'],'probe_value')].compact.uniq
            candidates.each do |candidate|
              begin
                value = candidate
                next unless value.between?(*param.fetch('input_range', [0.2, 100]))
                plan = Core.plan(rule, snapshot, param['key'] => value)
                accepted ||= plan['changed_count'].positive?
              rescue Core::Error => error
                message = error.message
              end
            end
            { 'key' => param['key'], 'label' => param['label'], 'edit_verified' => accepted, 'diagnostic' => accepted ? nil : message }
          end
          raise Core::Error, 'Có ATT nhưng chưa có đầu vào đổi hình an toàn.' unless rule['static_geometry'] || checks.any? { |check| check['edit_verified'] }
          unverified=checks.find { |check| !check['edit_verified'] && ThicknessSymbols.thickness?(rule,check['key']) }
          if unverified
            raise Core::Error,"#{unverified['label']}: chưa đổi được độ dày an toàn. #{unverified['diagnostic']}"
          end
          canonical=snapshot.merge('parts'=>canonical_plan['parts'],'envelope'=>canonical_plan['envelope'],
            'parameter_values'=>canonical_plan['target'],'formula_envelope'=>canonical_plan['formula_envelope'],'dc_inputs'=>{})
          begin
            ScalePlan.plan(rule,ScalePlan.scaled_snapshot(canonical,[1.03,1.03,1.03]),values)
          rescue Core::Error=>error
            raise Core::Error,"Chưa tính lại được sau Scale: #{error.message}"
          end
          Runtime.private_tree(root)
          Runtime.apply_plan(bindings,canonical_plan)
          Runtime.stamp(root, rule, bindings, values)
          Runtime.verify_result(root,canonical_plan)
          root.set_attribute(Reader::DICT, 'generated', true)
          @library.require_owned(root)
          actual, = Reader.live(root, label: root.name, parameter: snapshot['parameter'])
          data = { 'format' => 'mh_module_library', 'version' => 1, 'name' => root.name,
                   'rule' => rule, 'values' => values, 'snapshot' => actual,
                   'conversion_source' => row.slice('relative', 'source_sha256') }
          encoded = JSON.generate(data)
          LibraryCatalog.payload(encoded)
          @library.validate_geometry(root, data)
          root.definition.set_attribute(Reader::DICT, LibraryCatalog::PAYLOAD_KEY, encoded)
          bounds = root.definition.bounds
          distance = [bounds.diagonal, 1.0].max * 2
          root.definition.thumbnail_camera = Sketchup::Camera.new(bounds.center + Geom::Vector3d.new(distance, -distance, distance), bounds.center, Z_AXIS, false)
          root.definition.refresh_thumbnail
          ancestor=File.dirname(target)
          ancestor=File.dirname(ancestor) until File.exist?(ancestor)
          raise Core::Error,'Folder đích vượt thư viện hoặc chứa liên kết ngoài.' unless LibraryCatalog.inside?(@destination,ancestor)
          FileUtils.mkdir_p(File.dirname(target))
          raise Core::Error,'File đích vượt thư viện.' unless LibraryCatalog.inside?(@destination,File.dirname(target))
          raise Core::Error,'File đích trỏ ra ngoài thư viện.' if File.exist?(target) && !LibraryCatalog.inside?(@destination,target)
          temporary = File.join(File.dirname(target), '.mh-convert-' + Core::Ids.hex(6) + '.skp')
          raise Core::Error, 'Không lưu được SKP chuyển đổi.' unless root.definition.save_copy(temporary)
          @model.abort_operation
          operation = false
          # Verify the actual on-disk file before publishing it in the Library.
          @model.start_operation('MH Kiểm Tra Bản Chuyển', true)
          operation = true
          saved = @model.definitions.load(temporary)
          payload = LibraryCatalog.payload(saved.get_attribute(Reader::DICT, LibraryCatalog::PAYLOAD_KEY))
          copy = @model.active_entities.add_instance(saved, Geom::Transformation.new)
          @library.validate_geometry(copy, payload)
          @model.abort_operation
          operation = false
          raise Core::Error,'Nguồn đổi trong lúc chuyển.' unless Digest::SHA256.file(path).hexdigest==row['source_sha256']
          current_hash=File.file?(target) ? Digest::SHA256.file(target).hexdigest : nil
          raise Core::Error,'File đích đã đổi trong lúc chuyển; giữ nguyên.' unless current_hash==existing_hash
          if existing_hash
            backup=File.join(@folder,'backups',Core::Ids.hex(8),row['relative'])
            FileUtils.mkdir_p(File.dirname(backup));FileUtils.cp(target,backup)
            raise Core::Error,'Bản sao lưu không khớp.' unless Digest::SHA256.file(backup).hexdigest==existing_hash
            row['backup']=backup
          end
          FileUtils.mv(temporary,target,force:true)
          row.merge!('status' => 'converted', 'parts' => actual['parts'].length,
                     'verified_export'=>true,
                     'module_kind'=>rule['static_geometry'] ? 'geometry' : 'parametric',
                     'scale_verified'=>true,
                     'editable_parameters' => values.length, 'parameter_checks' => checks,
                     'output_sha256' => Digest::SHA256.file(target).hexdigest, 'output_bytes' => File.size(target))
        rescue StandardError => error
          row['error'] = "#{error.class}: #{error.message}"
          row['backtrace'] = error.backtrace.first(3)
        ensure
          @model.abort_operation if operation
          File.delete(temporary) if temporary && File.file?(temporary)
          row['source_unchanged'] = Digest::SHA256.file(path).hexdigest == row['source_sha256']
          unless @model.active_entities.to_a == @roots && @model.definitions.to_a == @definitions && @model.selection.to_a == @selection
            raise Core::Error, 'Model thử/definition/selection thay đổi; dừng để giữ trạng thái người dùng.'
          end
        end
        row
      end

      def write_report
        @report['processed'] = @report['files'].length
        %w[converted failed existing].each { |kind| @report[kind] = @report['files'].count { |row| row['status'] == kind } }
        @report['updated_at'] = Time.now.utc.iso8601
        @report['files'].each do |row|
          @previous_rows[row['relative']]=row if row['status']=='converted' || row['verified_export']==true
        end
        @report['known_outputs']=@previous_rows.filter_map do |name,row|
          next unless (row['status']=='converted' || row['verified_export']==true) && row['output_sha256']
          [name,row.slice('relative','status','source_sha256','output_sha256','verified_export')]
        end.to_h
        path=File.join(@folder,'report.json');temporary=path+'.tmp'
        File.write(temporary,JSON.pretty_generate(@report));FileUtils.mv(temporary,path,force:true)
        @publisher&.call(@report)
      end

      def finish(status: 'complete')
        UI.stop_timer(@timer) if @timer
        @report['status'] = status
        @report['source_hashes_verified'] = @hashes.all? { |path, sha| Digest::SHA256.file(path).hexdigest == sha }
        @report['user_model_retained'] = @model.active_entities.to_a == @roots && @model.definitions.to_a == @definitions && @model.selection.to_a == @selection
        write_report
        CSV.open(File.join(@folder, 'report.csv'), 'wb', encoding: 'bom|utf-8') do |csv|
          csv << %w[file status parts editable_parameters source_unchanged diagnostic]
          @report['files'].each { |row| csv << row.values_at('relative', 'status', 'parts', 'editable_parameters', 'source_unchanged', 'error') }
        end
        lines = ["# Kết quả chuyển thư viện DC", '', "Nguồn: #{@source}", "Đích: #{@destination}", '',
                 "Đã xử lý #{@report['total']} SKP: #{@report['converted']} chuyển thành công, #{@report['failed']} chưa chuyển được, #{@report['existing']} file đích có sẵn.",
                 "SHA-256 nguồn giữ nguyên: #{@report['source_hashes_verified']}. Model/selection/definitions giữ nguyên: #{@report['user_model_retained']}.", '',
                 '| File | Kết quả | Tham số sửa | Chi tiết |', '|---|---|---:|---|']
        @report['files'].each do |row|
          lines << "| #{row['relative'].gsub('|', '/')} | #{row['status']} | #{row['editable_parameters']} | #{row['error'].to_s.gsub('|', '/').gsub(/\s+/, ' ')} |"
        end
        File.write(File.join(@folder, 'report.md'), lines.join("\n"))
        Sketchup.status_text = "MH: chuyển #{@report['converted']}/#{@report['total']} module; xem .conversion/report.md."
      end
    end
  end
end

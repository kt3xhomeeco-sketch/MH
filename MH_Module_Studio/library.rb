# encoding: UTF-8
require 'base64'
require 'tmpdir'
require_relative 'library_catalog'
require_relative 'runtime'
require_relative 'parametric'
require_relative 'library_placement'
require_relative 'assembly_file'
require_relative 'library_thumbnails'
require_relative 'library_import'
require_relative 'library_monitor'
require_relative 'hud_config'
require_relative 'library_conversion'

module MH
  module ModuleStudio
    class Library
      include LibraryConversionUI
      attr_reader :config, :catalog, :tool

      def initialize(&publisher)
        raw = Sketchup.read_default('MH_Module_Studio', 'library_v1', '').to_s
        @config = LibraryCatalog.settings(raw.empty? ? {} : JSON.parse(Base64.strict_decode64(raw)))
        @catalog = { 'root' => '', 'folders' => [], 'entries' => [] }
        @publisher = publisher
      rescue JSON::ParserError, ArgumentError
        @config = LibraryCatalog.settings({})
        @catalog = { 'root' => '', 'folders' => [], 'entries' => [] }
        @publisher = publisher
      end

      def save_settings(changes)
        proposed = LibraryCatalog.settings(@config.merge(changes.slice('view', 'thumbnail_size', 'hud_size', 'hud_image_zoom', 'hud_position', 'hud_orders', 'folder', 'folder_keys')))
        unless @catalog['folders'].empty? || @catalog['folders'].any? { |folder| folder['id'] == proposed['folder'] }
          raise Core::Error, 'Folder đã thay đổi. Làm mới thư viện.'
        end
        @config = proposed
        persist
        @tool&.refresh
      end

      def persist
        # Windows preferences can interpret embedded quotes; store plain Base64.
        Sketchup.write_default('MH_Module_Studio', 'library_v1', Base64.strict_encode64(JSON.generate(@config)))
      end

      def refresh
        @catalog = @config['root'].empty? ? { 'root' => '', 'folders' => [], 'entries' => [] } : LibraryCatalog.scan(@config['root'])
        reconcile_catalog
        reset_monitor
        @tool&.catalog_changed
      end

      def reconcile_catalog
        @hud_bindings ||= read_hud_bindings
        previous_config = @config
        @config, = HUDConfig.remap(@config,@hud_bindings,@catalog)
        bindings = HUDConfig.capture(@catalog)
        persist unless @config==previous_config
        unless bindings==@hud_bindings
          Sketchup.write_default('MH_Module_Studio','hud_catalog_v1',Base64.strict_encode64(JSON.generate(bindings)))
          @hud_bindings = bindings
        end
      end

      def read_hud_bindings
        raw = Sketchup.read_default('MH_Module_Studio','hud_catalog_v1','').to_s
        return nil if raw.empty? || raw.bytesize>HUDConfig::MAX_BYTES*2
        HUDConfig.validate_catalog!(JSON.parse(Base64.strict_decode64(raw)))
      rescue JSON::ParserError, ArgumentError, Core::Error
        nil
      end

      # Content hashing is limited to explicit config transfer, never HUD paint/poll.
      def config_catalog
        @catalog.merge('entries'=>@catalog['entries'].map do |item|
          current = entry(item['id'])
          row = current.merge('sha256'=>Digest::SHA256.file(current['path']).hexdigest)
          entry(item['id'])
          row
        end)
      end

      def export_hud_config(path)
        refresh
        raise Core::Error,'Chọn folder Library trước khi xuất config.' if @catalog['root'].empty?
        text = JSON.pretty_generate(HUDConfig.document(@config,config_catalog))
        raise Core::Error,'Config HUD vượt 4 MB.' if text.bytesize>HUDConfig::MAX_BYTES
        temporary = path+'.tmp-'+Core::Ids.hex(5)
        begin
          File.write(temporary,text,encoding:'UTF-8')
          FileUtils.mv(temporary,path)
        ensure
          File.delete(temporary) if File.file?(temporary)
        end
        'Đã xuất config HUD.'
      end

      def import_hud_config(path)
        raise Core::Error,'Config HUD vượt 4 MB.' if File.size(path)>HUDConfig::MAX_BYTES
        data = HUDConfig.parse(File.read(path,encoding:'UTF-8'))
        refresh
        raise Core::Error,'Chọn folder Library trước khi nhập config.' if @catalog['root'].empty?
        settings,missing = HUDConfig.remap(data['settings'].merge('root'=>@config['root']),data['library'],config_catalog)
        @config = settings
        persist
        @tool&.catalog_changed
        publish('Đã nhập config HUD.')
        missing.empty? ? 'Đã nhập config HUD.' : "Đã nhập config; #{missing.length} icon không có file khớp trong Library."
      end

      def transfer_hud_config(action)
        if action=='import_config'
          path = UI.openpanel('Import config HUD',nil,'JSON|*.json||')
          path ? import_hud_config(path) : nil
        else
          path = UI.savepanel('Export config HUD',nil,'MH-HUD-config.json')
          path += '.json' if path && File.extname(path).downcase!='.json'
          path ? export_hud_config(path) : nil
        end
      end

      def reset_monitor
        @monitor ||= LibraryMonitor.new
        @monitor.reset(@config['root'],@catalog)
      end

      def browser_visible=(visible)
        reset_monitor if visible && !@browser_visible
        @browser_visible = visible
        update_monitor
      end

      def update_monitor
        visible = @browser_visible || @tool&.active
        if !visible || @config['root'].empty?
          UI.stop_timer(@monitor_timer) if @monitor_timer
          @monitor_timer = nil
        elsif !@monitor_timer
          reset_monitor unless @monitor
          @monitor_timer = UI.start_timer(0.1,true) { poll_catalog }
        end
      end

      def poll_catalog
        return if @tool&.catalog_busy?
        changed = @monitor.poll
        return unless changed
        @catalog = changed
        reconcile_catalog
        @tool&.catalog_updated
        publish(background:true)
      end

      def entry(id)
        item = @catalog['entries'].find { |row| row['id'] == id }
        unless item && LibraryCatalog.inside?(@catalog['root'], item['path']) &&
               LibraryCatalog.fingerprint(item['path']) == item['fingerprint']
          raise Core::Error, 'File đã đổi hoặc bị di chuyển. Làm mới thư viện trước khi đặt.'
        end
        item
      end

      def thumbnail(item)
        thumbnails.path(item)
      rescue StandardError
        nil
      end

      def preview_thumbnail(item)
        thumbnails.preview_path(item)
      rescue StandardError
        nil
      end

      def thumbnails
        @thumbnails = LibraryThumbnails.new(@config['root']) unless @thumbnails && @thumbnails.root==@config['root']
        @thumbnails
      end

      def thumbnail_key(item)
        thumbnails.key(item)
      end

      def thumbnail_view(item)
        thumbnails.view(item)
      end

      def update_thumbnail(id,view)
        item = entry(id)
        thumbnails.update(item,view)
        @tool&.refresh
        publish("Đã cập nhật icon #{item['name']} · #{LibraryThumbnails::VIEWS[view]}.")
      end

      def publish(message = nil, error: false, background: false)
        state = { 'settings' => @config, 'root' => @catalog['root'], 'folders' => @catalog['folders'],
                  'entries' => @catalog['entries'].map { |item| item.reject { |key, _| key == 'path' }.merge('thumbnail_key'=>thumbnail_key(item),'thumbnail_view'=>thumbnail_view(item)) },
                  'thumbnail_views'=>LibraryThumbnails::VIEWS,
                  'message' => message, 'error' => error, 'background'=>background, 'hud_editing' => @tool&.editing == true, 'hud_active' => @tool&.active == true }
        state['conversion']=conversion_state
        @publisher&.call('receiveLibrary', state)
      end

      def request(data)
        return conversion_request(data) if data['action'].to_s.start_with?('library_conversion_')
        case data['action']
        when 'library_visibility'
          self.browser_visible = data['visible']==true
          return
        when 'library_ready', 'library_refresh'
          refresh
          self.browser_visible = true
        when 'library_choose'
          path = UI.select_directory(title: 'Chọn folder thư viện module SKP', directory: @config['root'])
          if path
            catalog = LibraryCatalog.scan(path)
            @config['root'] = catalog['root']
            @catalog = catalog
            reconcile_catalog
            persist
            reset_monitor
            update_monitor
            @tool&.catalog_changed
          end
        when 'library_settings'
          save_settings(data.fetch('settings'))
        when 'library_thumbnails'
          ids = data.fetch('ids').first(12)
          images = ids.filter_map do |id|
            begin
              item = entry(id)
              path = thumbnail(item)
              [id, { 'fingerprint' => item['fingerprint'], 'key'=>thumbnail_key(item), 'url' => path ? 'data:image/png;base64,' + Base64.strict_encode64(File.binread(path)) : nil }]
            rescue Core::Error, SystemCallError
              [id,{'fingerprint'=>nil,'key'=>nil,'url'=>nil}]
            end
          end.to_h
          @publisher&.call('receiveLibraryThumbnails', images)
          return
        when 'library_thumbnail_view'
          update_thumbnail(data.fetch('id'),data.fetch('view'))
          return
        when 'library_save'
          save_selected
          return publish
        when 'library_place'
          open_hud(data.fetch('id'))
          return publish('Click để đặt và thoát HUD. Esc hủy lượt đặt để chọn mẫu khác; Space thoát HUD.')
        when 'library_hud'
          open_hud
          return publish('HUD đang mở trong màn hình SketchUp. Esc / Space để thoát.')
        when 'library_hud_edit'
          open_hud unless @tool&.active
          @tool.set_editing(true)
          return publish('Edit HUD: kéo icon trên vòng để đổi chỗ; kéo module từ Library thả vào một ô HUD.')
        when 'library_hud_exit'
          @tool&.finish
          return publish('Đã thoát HUD.')
        when 'library_hud_drag'
          raise Core::Error, 'Bật Edit HUD trước khi kéo module.' unless @tool&.active && @tool.editing
          @tool.begin_external_drag(data.fetch('id'), data.fetch('root'), data.fetch('token'))
          return
        when 'library_hud_drop'
          @tool&.end_external_drag(data['token'])
          return
        when 'library_hud_cancel'
          @tool&.cancel_external_drag(data['token'])
          return
        else
          raise Core::Error, 'Thao tác thư viện không hỗ trợ.'
        end
        publish
      rescue StandardError => error
        publish(error.message, error: true)
      end

      def move_hud_item(id, index, folder: @config['folder'])
        entry(id)
        raise Core::Error, 'Folder HUD đã thay đổi.' unless @catalog['folders'].any? { |row| row['id'] == folder }
        orders = LibraryCatalog.move_hud_item(@catalog['entries'], @config.merge('folder' => folder), id, index)
        save_settings('hud_orders' => orders)
        publish('Đã lưu vị trí icon HUD.')
      end

      def require_owned(root)
        unless root.is_a?(Sketchup::ComponentInstance) && root.get_attribute(Reader::DICT, 'trial', false)
          raise Core::Error, 'Chọn component đã Tạo model bằng MH Module Studio để lưu thư viện.'
        end
        Runtime.ensure_top_level(root.model)
      end

      def save_selected(root = Runtime.selected_root)
        AssemblyContainers.managed?(root) ? Runtime.ensure_top_level(root.model) : require_owned(root)
        name = root.name.to_s.strip.empty? ? 'MH Module' : root.name
        directory = @config['root'].empty? ? nil : File.join(@config['root'],@config['folder'])
        path = UI.savepanel('Lưu module / cụm SKP kèm quy tắc',directory,Parametric.filename(name))
        return nil unless path
        path += '.skp' unless File.extname(path).downcase=='.skp'
        export(root,path)
        root.model.start_operation('MH Gắn File Thư Viện',true)
        operation = true
        root.set_attribute(Reader::DICT,'library_source_path',File.expand_path(path))
        root.set_attribute(Reader::DICT,'library_source_signature',Digest::SHA256.file(path).hexdigest)
        root.model.commit_operation
        operation = false
        refresh unless @config['root'].empty?
        publish("Đã lưu #{File.basename(path)} kèm công thức và liên kết.")
        path
      rescue StandardError
        root.model.abort_operation if operation
        raise
      end

      def validate_geometry(root, data, recover: false)
        return AssemblyFile.restore(root,data) if data['format']==AssemblyFile::FORMAT
        root.set_attribute(Reader::DICT, 'parameter_values_json', JSON.generate(data['values']))
        Runtime.store_formula_envelope(root,data['snapshot']['formula_envelope']) if data['snapshot']['formula_envelope']
        snapshot, bindings = Reader.live(root, label: data['name'], parameter: Runtime.read_parameter(data['rule'], data['values']))
        expected = data['snapshot']['parts'].to_h { |part| [part['key'], part] }
        unless snapshot['parts'].length == expected.length && snapshot['parts'].all? do |part|
          stored = expected[part['key']]
          stored && Core.bounds_close?(stored['bounds'], part['bounds']) && stored['visible'] == part['visible']
        end
          if recover
            plan=ImportRecovery.plan(data,snapshot)
            Runtime.apply_plan(bindings,plan)
            Runtime.stamp(root,data['rule'],bindings,plan['target'])
            Runtime.verify_result(root,plan)
            return validate_geometry(root,data)
          end
          raise Core::Error, 'Hình học SKP không khớp bộ quy tắc đã lưu. Lưu lại module từ Studio.'
        end
        plan = Core.plan(data['rule'], snapshot, {})
        raise Core::Error, 'Giá trị đã lưu chưa khớp công thức. Cập nhật module rồi lưu lại.' unless plan['changed_count'].zero?
        [snapshot, bindings, plan]
      end

      def export(root, path)
        return AssemblyFile.save(root,path) if AssemblyContainers.managed?(root)
        require_owned(root)
        path = File.expand_path(path)
        if File.expand_path(root.model.path).casecmp?(path)
          raise Core::Error, 'Chọn tên khác với model SketchUp đang mở.'
        end
        rule = ThicknessSymbols.normalize(Core.rule!(JSON.parse(root.get_attribute(Reader::DICT, 'rule_json').to_s)))
        raise Core::Error, 'Module cần hệ quy tắc Parametric trước khi lưu thư viện.' unless rule['kind'] == RuleSystem::KIND
        values = JSON.parse(root.get_attribute(Reader::DICT, 'parameter_values_json').to_s)
        rule = Parametric.with_values(rule,values)
        temporary = File.join(File.dirname(path), '.mh-export-' + Core::Ids.hex(6) + '.skp')
        before = File.file?(path) ? Digest::SHA256.file(path).hexdigest : nil
        model = root.model
        operation = false
        model.start_operation('MH Chuẩn Bị Thư Viện', true)
        operation = true
        original, = Reader.live(root,label:root.name,parameter:Runtime.read_parameter(rule,values))
        copy = model.active_entities.add_instance(root.definition, Geom::Transformation.new)
        copy.name = root.name
        copy.material = root.material
        Runtime.private_tree(copy)
        if copy.material
          copy.definition.entities.each do |entity|
            entity.material = copy.material if entity.respond_to?(:material) && entity.material.nil?
          end
        end
        frame = Geom::Transformation.new(Frames.scale_frame(root.transformation.to_a))
        copy.definition.entities.transform_entities(frame, copy.definition.entities.to_a)
        Runtime.store_formula_envelope(copy,original['formula_envelope']) if original['formula_envelope']
        copy.set_attribute(Reader::DICT, 'parameter_values_json', JSON.generate(values))
        snapshot, bindings = Reader.live(copy, label: root.name, parameter: Runtime.read_parameter(rule, values))
        data = { 'format' => 'mh_module_library', 'version' => 1, 'name' => root.name,
                 'rule' => rule, 'values' => values, 'snapshot' => snapshot }
        encoded = JSON.generate(data)
        LibraryCatalog.payload(encoded)
        validate_geometry(copy, data)
        Runtime.stamp(copy, rule, bindings, values)
        copy.definition.set_attribute(Reader::DICT, LibraryCatalog::PAYLOAD_KEY, encoded)
        bounds = copy.definition.bounds
        center = bounds.center
        distance = [bounds.diagonal, 1.0].max * 2
        eye = center + Geom::Vector3d.new(distance, -distance, distance)
        copy.definition.thumbnail_camera = Sketchup::Camera.new(eye, center, Z_AXIS, false)
        copy.definition.refresh_thumbnail
        raise Core::Error, 'Không ghi được SKP.' unless copy.definition.save_copy(temporary)
        model.abort_operation
        operation = false
        verify_file(temporary)
        raise Core::Error,'File đã đổi trong lúc lưu; chưa ghi đè.' if before && Digest::SHA256.file(path).hexdigest!=before
        if before
          directory = File.join(File.dirname(path),'.mh-backups'); FileUtils.mkdir_p(directory)
          FileUtils.cp(path,File.join(directory,File.basename(path,'.skp')+'-'+Core::Ids.hex(8)+'.skp'))
        end
        FileUtils.mv(temporary, path, force: true)
        path
      ensure
        model.abort_operation if operation
        File.delete(temporary) if temporary && File.file?(temporary)
      end

      # Verify serialized native geometry, not only the embedded JSON. Call only
      # after the export preparation transaction has finished, before replacing
      # the destination. Source files and existing definitions remain unchanged.
      def verify_file(path)
        model=Sketchup.active_model
        Runtime.ensure_top_level(model)
        model.start_operation('MH Kiểm Tra File Vừa Lưu',true)
        operation=true
        definition=model.definitions.load(path)
        root=model.active_entities.add_instance(definition,Geom::Transformation.new)
        data=imports.payload(definition.get_attribute(Reader::DICT,LibraryCatalog::PAYLOAD_KEY))
        validate_geometry(root,data)
        data
      ensure
        model.abort_operation if operation
      end

      # Preflight in an aborted operation: browsing never leaves loaded definitions in the user's model.
      def prepare(id)
        item = entry(id)
        model = Sketchup.active_model
        Runtime.ensure_top_level(model)
        operation = false
        model.start_operation('MH Kiểm Tra Thư Viện', true)
        operation = true
        definition = model.definitions.load(item['path'])
        data = imports.payload(definition.get_attribute(Reader::DICT, LibraryCatalog::PAYLOAD_KEY))
        root = model.active_entities.add_instance(definition, Geom::Transformation.new)
        Runtime.private_tree(root)
        validate_geometry(root, data,recover:true)
        data.merge('entry_id' => id, 'fingerprint' => item['fingerprint'])
      ensure
        model.abort_operation if operation
      end

      def imports
        @imports ||= LibraryImport.new
      end

      def preview(id)
        item = entry(id)
        model = Sketchup.active_model
        Runtime.ensure_top_level(model)
        begin
          model.start_operation('MH Xem Trước Thư Viện',true);operation = true
          definition = model.definitions.load(item['path'])
          raw = definition.get_attribute(Reader::DICT,LibraryCatalog::PAYLOAD_KEY)
          data = imports.preview(raw)
        ensure
          model.abort_operation if operation
        end
        imports.prefetch(raw)
        data.merge('entry_id'=>id,'fingerprint'=>item['fingerprint'])
      end

      def build_instance(data, transform, entities: Sketchup.active_model.active_entities)
        item = entry(data.fetch('entry_id'))
        raise Core::Error, 'File thư viện đã thay đổi. Chọn lại module.' unless item['fingerprint'] == data['fingerprint']
        model = Sketchup.active_model
        Runtime.ensure_top_level(model)
        definition = model.definitions.load(item['path'])
        current = imports.payload(definition.get_attribute(Reader::DICT, LibraryCatalog::PAYLOAD_KEY))
        root = entities.add_instance(definition, Geom::Transformation.new)
        root.name = current['name'].to_s
        Runtime.private_tree(root)
        if current['format']==AssemblyFile::FORMAT
          AssemblyFile.restore(root,current)
          root.set_attribute(Reader::DICT,'generated',true)
          root.set_attribute(Reader::DICT,'library_source_path',item['path'])
          root.set_attribute(Reader::DICT,'library_source_signature',Digest::SHA256.file(item['path']).hexdigest)
          root.transformation = transform
          return root
        end
        snapshot, bindings, normalization = validate_geometry(root, current,recover:true)
        targets = Parametric.targets(current['rule'])
        if targets.any? { |key,value| normalization['target'][key]!=value }
          normalization = Core.plan(current['rule'],snapshot,targets)
        end
        Runtime.apply_plan(bindings,normalization)
        Runtime.stamp(root,current['rule'],bindings,normalization['target'])
        Runtime.verify_result(root,normalization)
        root.set_attribute(Reader::DICT, 'generated', true)
        root.set_attribute(Reader::DICT, 'library_source_path', item['path'])
        root.set_attribute(Reader::DICT, 'library_source_signature', Digest::SHA256.file(item['path']).hexdigest)
        root.transformation = transform
        root
      end

      def place(data, point, placement: nil)
        return LibraryPlacement.place(self,data,point,placement) if placement
        model = Sketchup.active_model
        Runtime.ensure_top_level(model)
        operation = false
        model.start_operation('MH Đặt Module', true)
        operation = true
        root = build_instance(data,Geom::Transformation.translation(point.to_a))
        model.selection.clear
        model.selection.add(root)
        model.commit_operation
        operation = false
        root
      rescue StandardError
        model.abort_operation if operation
        raise
      end

      def open_hud(id = nil)
        raise Core::Error,'Đợi chuyển đổi xong hoặc bấm Dừng trước khi mở HUD.' if @conversion&.running?
        refresh if @catalog['root'].empty?
        raise Core::Error, 'Chọn folder trong tab Library trước khi mở HUD.' if @catalog['root'].empty?
        Runtime.ensure_top_level(Sketchup.active_model)
        data = id ? preview(id) : nil
        @tool&.finish
        @tool = LibraryHUD.new(self, data)
        Sketchup.active_model.select_tool(@tool)
        reset_monitor
        update_monitor
        Sketchup.focus
      end

      def tool_closed(tool)
        @tool = nil if @tool.equal?(tool)
        update_monitor
      end
    end
  end
end

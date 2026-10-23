# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require 'fileutils'
require_relative 'core'
require_relative 'reader'
require_relative 'runtime'
require_relative 'parametric'
require_relative 'module_options'
require_relative 'library_hud'
require_relative 'scale_redraw'
require_relative 'assembly_tool'
require_relative 'module_file'
require_relative 'parametric_model'
require_relative 'library_adoption'

module MH
  module ModuleStudio
    ScaleRedraw.install
    Assembly.install
    LibraryAdoption.install
    class Panel
      def initialize
        @snapshots = []
        @rule = nil
        @plan = nil
        @selected_dc_key = nil
        @exposed_parameter_keys = nil
        @dialog = nil
        @parametric_dialog = nil
        @parametric_revision = 0
        @busy = false
        @model_context=Sketchup.active_model if defined?(Sketchup) && Sketchup.respond_to?(:active_model)
        @session_generation=0
        @message = 'Chọn module trong SketchUp hoặc mở file SKP để đọc trạng thái đầu tiên.'
      end

      def show
        if @dialog && @dialog.visible?
          @dialog.bring_to_front
          return
        end
        @dialog = UI::HtmlDialog.new(dialog_title: 'MH Module Studio',
                                     preferences_key: 'MH_Module_Studio_Learning', width: 1340, height: 900,
                                     min_width: 1000, min_height: 650, resizable: true,
                                     style: UI::HtmlDialog::STYLE_DIALOG)
        directory = __dir__
        directory.force_encoding(Encoding::UTF_8)
        @dialog.set_file(File.join(directory, 'ui', 'index.html'))
        @dialog.add_action_callback('request') do |_context, raw|
          begin
            raise Core::Error, 'Yêu cầu quá lớn.' if raw.to_s.bytesize > 1024 * 1024
            request(JSON.parse(raw.to_s))
          rescue StandardError => error
            @message = error.message
            publish(error: true)
          end
        end
        current_dialog = @dialog
        @dialog.set_on_closed do
          if @dialog.equal?(current_dialog)
            @dialog = nil
            MH::ModuleStudio.instance_variable_get(:@library)&.browser_visible = false
          end
        end
        @dialog.show
      end

      def show_library_tab
        show
        dialog = @dialog
        UI.start_timer(0.2, false) do
          next unless @dialog.equal?(dialog) && dialog&.visible?

          dialog.execute_script('window.openLibraryTab?.()')
        end
      end

      def request(data)
        synchronize_model
        action = data['action']
        if action == 'assembly_hud'
          MH::ModuleStudio.open_assembly
          return publish
        end
        return MH::ModuleStudio.library.request(data) if action.to_s.start_with?('library_')
        if action == 'ready'
          @parametric_ready = true if data['surface'] == 'parametric'
          return publish
        end
        raise Core::Error, 'Đang đọc file. Đợi hoàn tất trước khi tiếp tục.' if @busy
        case action
        when 'open_parametric'
          @parametric_focus = data['parameter_key']
          show_parametric
        when 'capture_parametric'
          capture_parametric_root(Runtime.selected_root)
        when 'rename_model'
          unless data['snapshot_id']==@snapshots.last&.fetch('id') && data['revision']==@parametric_revision
            raise Core::Error,'Module đã đổi; đọc lại trước khi đổi tên.'
          end
          previous_name = @module_name
          previous_snapshot_id = @snapshots.last['id']
          if !@captured_root_pid && @rule && !@assembly_root_pid
            @rule = Parametric.rename_display(@rule,data['name'],part_key:data['part_key'])
            @module_name = @rule['module_name'] || previous_name || @snapshots.last['label']
            @parametric_revision += 1
            @message = 'Đã đổi tên trong bảng. Lưu SKP để ghi tên vào file.'
            return publish
          end
          root = captured_root!
          anchor = {'root'=>root.persistent_id.to_s,'scope'=>@captured_scope}.compact
          if @assembly_root_pid && data['part_key']
            child = AssemblyContainers.members(root).find { |member| member.persistent_id.to_s==data['part_key'] }
            raise Core::Error,'Module con đã thay đổi.' unless child
            anchor = {'root'=>child.persistent_id.to_s,'scope'=>root.persistent_id.to_s}
            raw = child.get_attribute(Reader::DICT,'rule_json')
            ParametricModel.rename(Sketchup.active_model,anchor,raw && Core.rule!(JSON.parse(raw)),data['name'])
          else
            @rule = ParametricModel.rename(Sketchup.active_model,anchor,@rule,data['name'],part_key:data['part_key'])
            @captured_root_pid = anchor['root'].to_i
          end
          root = captured_root!
          @snapshots[-1] = @assembly_root_pid ? ParametricModel.assembly_snapshot(root) : Reader.live(root,label:root.name,parameter:nil).first
          @snapshots[-1]['id'] = previous_snapshot_id
          @module_name = @rule&.fetch('module_name',nil) || (data['part_key'] ? previous_name : root.name)
          @module_name = root.definition.name if @module_name.to_s.strip.empty?
          @parametric_revision += 1; @plan = nil
          @message = 'Đã đổi tên. Lưu SKP để lưu vào thư viện theo tên module.'
        when 'save_skp'
          if @assembly_root_pid
            raise Core::Error,'Bảng cụm đã đổi; đọc lại trước khi lưu.' unless data['snapshot_id']==@snapshots.last['id'] && data['revision']==@parametric_revision
            path = MH::ModuleStudio.library.save_selected(captured_root!)
            @source_file = path if path
            @message = path ? "Đã lưu cụm cùng các module con và liên kết vào #{path}." : 'Đã hủy lưu SKP.'
            return publish
          end
          unless @rule && @snapshots.last && data['rule_id'] == @rule['id'] && data['snapshot_id'] == @snapshots.last['id'] && data['revision'] == @parametric_revision
            raise Core::Error, 'Bảng đã đổi. Đọc lại trước khi lưu SKP.'
          end
          edited = data['variables'] ? Parametric.edit_variables(@rule,data['variables']) : @rule
          edited=ImportTemplate.edit(edited,data['import_template']) if data['import_template']
          edited = Parametric.rename_display(edited,@module_name) if @module_name && !@module_name.empty?
          path = @source_file
          filename = Parametric.filename(edited['module_name'] || @snapshots.last['label'])
          if path && File.basename(path)!=filename
            destination = File.join(File.dirname(path),filename)
            path = File.file?(destination) ? UI.savepanel('Tên đã có; chọn file lưu module',File.dirname(path),filename) : destination
          else
            path ||= UI.savepanel('Lưu module Parametric trực tiếp vào SKP',MH::ModuleStudio.library.config['root'],filename)
          end
          return publish unless path
          path += '.skp' unless File.extname(path).downcase == '.skp'
          root = Sketchup.active_model.find_entity_by_persistent_id(@captured_root_pid) if @captured_root_pid
          root = nil unless root && root.get_attribute(Reader::DICT,'trial',false) && root.get_attribute(Reader::DICT,'rule_id') == edited['id']
          expected = @source_signature if @source_file && File.expand_path(path).casecmp?(File.expand_path(@source_file))
          result = ModuleFile.save(path,edited,@snapshots.last,expected:expected,source_root:root,
            source_path:root ? nil : @source_file,source_expected:root ? nil : @source_signature)
          @source_file = result['path']; @source_signature = result['signature']
          @rule = result['rule']; @parametric_revision += 1
          @snapshots[-1] = result['snapshot']
          @plan = nil
          @message = "Đã lưu công thức, ký hiệu và hình học vào #{@source_file}."
          if root
            begin
              Runtime.update_trial(root,@rule,Parametric.targets(@rule),source:result)
            rescue StandardError => detail
              @message += " File đã lưu; model đang mở chưa cập nhật: #{detail.message}"
            end
          end
          unless MH::ModuleStudio.library.config['root'].empty?
            MH::ModuleStudio.library.refresh
            MH::ModuleStudio.library.publish('Đã cập nhật file SKP.')
          end
        when 'save_variables'
          unless @rule && @rule['kind'] == RuleSystem::KIND && data['rule_id'] == @rule['id'] &&
                 data['snapshot_id'] == @snapshots.last&.fetch('id') && data['revision'] == (@parametric_revision || 0)
            raise Core::Error, 'Module hoặc bảng biến đã thay đổi. Đọc lại bảng trước khi lưu.'
          end
          edited = Parametric.edit_variables(@rule, data.fetch('variables'))
          edited=ImportTemplate.edit(edited,data['import_template']) if data['import_template']
          ModuleOptions.sync_visibility(edited)
          @rule = edited
          @exposed_parameter_keys = @rule['exposed_parameter_keys'].dup
          @parametric_revision = (@parametric_revision || 0) + 1
          @plan = nil
          @message = 'Đã lưu bảng biến vào bộ quy tắc. Xem trước để kiểm tra hình học.'
        when 'save_part_formula'
          unless @rule && @rule['kind'] == RuleSystem::KIND && data['rule_id'] == @rule['id'] &&
                 data['snapshot_id'] == @snapshots.last&.fetch('id') && data['revision'] == (@parametric_revision || 0)
            raise Core::Error, 'Module hoặc bảng đã thay đổi. Đọc lại bảng trước khi sửa công thức.'
          end
          edited = Parametric.edit_part_formula(@rule, data['part_key'], data['field'], data['formula'])
          preview = Core.plan(edited, @snapshots.last, Parametric.targets(edited))
          @rule = edited
          @plan = preview
          @parametric_revision = (@parametric_revision || 0) + 1
          @message = 'Đã lưu công thức và tính lại bản xem trước. Model SketchUp chưa thay đổi.'
        when 'capture'
          return capture_parametric_root(Runtime.selected_root).then { publish } if AssemblyContainers.managed?(Runtime.selected_root)
          @assembly_root_pid = nil
          @source_file = nil; @source_signature = nil
          root = Runtime.selected_root
          @captured_model=root.model;@captured_scope=nil
          @captured_root_pid = root.persistent_id
          @source_file = root.get_attribute(Reader::DICT,'library_source_path')
          @source_signature = root.get_attribute(Reader::DICT,'library_source_signature')
          snapshot, = Reader.live(root, label: data['label'], parameter: data['parameter'])
          add_snapshot(snapshot, parameter_mode: data['parameter_mode'])
          saved_rule = root.get_attribute(Reader::DICT, 'rule_json')
          if saved_rule.is_a?(String) && saved_rule.bytesize <= 16 * 1024 * 1024
            restored = Core.rule!(JSON.parse(saved_rule))
            if DCCopies.enabled?(restored) || restored['parts'].map { |part| part['key'] }.sort == snapshot['parts'].map { |part| part['key'] }.sort
              @rule = ThicknessSymbols.normalize(DCCustomAttributes.upgrade(RuleSystem.migrate(snapshot, restored)))
              if @rule['kind'] == RuleSystem::KIND && snapshot['parameter_values']
                @rule['parameters'].each { |param| param['value'] = snapshot['parameter_values'].fetch(param['key'], param['value']) }
                @rule.fetch('parametric_variables', []).each do |row|
                  row['value'] = snapshot['parameter_values'].fetch(row['binding'], row['value']) if row['formula'].empty?
                end
              end
              @message = 'Đã đọc hình học và khôi phục hệ quy tắc đi cùng module.'
            end
          end
        when 'open_skp'
          @assembly_root_pid = nil
          path = UI.openpanel('Đọc một trạng thái module từ SKP', nil, 'SketchUp|*.skp||')
          return publish unless path
          @captured_root_pid = nil
          @captured_model=nil;@captured_scope=nil
          payload = ModuleFile.read(path)
          if payload
            if payload['format']==AssemblyFile::FORMAT
              @message = 'Cụm đã lưu đầy đủ module con và liên kết. Import từ Library để sửa thông số hoặc đổi tên.'
              return publish
            end
            @snapshots = [payload['snapshot']]
            @snapshots.last['module_name'] ||= payload['name']
            @rule = DCCustomAttributes.upgrade(payload['rule']); @plan = nil
            @source_file = path; @source_signature = ModuleFile.signature(path)
            @module_name = @rule['module_name'] || File.basename(path,'.skp')
            @parametric_revision += 1
            @message = 'Đã đọc SKP cùng toàn bộ biến, ký hiệu và công thức đã lưu.'
            return publish
          end
          @busy = true
          @message = 'Đang đọc SKP…'
          publish
          queue = Queue.new
          generation=@session_generation
          Thread.new do
            begin
              label = data['label'].to_s.strip
              label = File.basename(path, '.skp') if label.empty?
              queue << [:ok, Reader.read_file(path, label: label, parameter: data['parameter'])]
            rescue StandardError => error
              queue << [:error, error.message]
            end
          end
          @read_timer = UI.start_timer(0.1, true) do
            next unless generation==@session_generation
            next if queue.empty?
            UI.stop_timer(@read_timer)
            @read_timer = nil
            kind, value = queue.pop
            @busy = false
            if kind == :ok
              begin
                Reader.enrich_file_functions!(value, path)
                add_snapshot(value, parameter_mode: data['parameter_mode'])
                @source_file = path; @source_signature = ModuleFile.signature(path)
              rescue StandardError => error
                @message = error.message
                publish(error: true)
              end
            else
              @message = value
              publish(error: true)
            end
          end
          return
        when 'remove'
          @snapshots.reject! { |snapshot| snapshot['id'] == data['id'] }
          invalidate
          refresh_dc_selection
          @message = 'Đã bỏ trạng thái. Phân tích lại bộ mẫu còn lại.'
        when 'clear'
          @captured_root_pid = nil
          @source_file = nil; @source_signature = nil
          @snapshots = []
          invalidate
          @selected_dc_key = nil
          @exposed_parameter_keys = nil
          @message = 'Đã tạo bộ mẫu mới.'
        when 'set_exposed_parameters'
          raise Core::Error, 'Tổng hợp bộ tham số module trước khi chọn.' unless @rule && %w[module_parameter_set module_rule_system].include?(@rule['kind'])
          Core.set_exposed_parameters!(@rule, data['keys'])
          ModuleOptions.sync_visibility(@rule)
          @exposed_parameter_keys = @rule['exposed_parameter_keys'].dup
          @parametric_revision = (@parametric_revision || 0) + 1
          @plan = nil
          @message = "Hiện #{@rule['exposed_parameter_keys'].length} tham số trong bảng Thông số module. Tham số ẩn vẫn tham gia tính toán."
        when 'select_parameter'
          key = data['dc_key'].to_s
          if !key.empty? && !Core.dc_thickness_parameters(@snapshots).any? { |choice| choice['dc_key'] == key }
            raise Core::Error, 'Tham số DC này chưa khớp hình học của các mẫu.'
          end
          @selected_dc_key = key.empty? ? nil : key
          invalidate unless @rule && %w[module_parameter_set module_rule_system].include?(@rule['kind'])
          @message = 'Đã đổi mục xem chi tiết. Bộ tham số chung của module được giữ nguyên.'
        when 'detect_rules', 'save_constraint', 'remove_constraint'
          if action == 'detect_rules'
            @rule = build_system
            @message = "Đã nhận diện #{@rule['constraints'].length} quy tắc; kiểm tra mặt và hướng trước khi thử."
          else
            raise Core::Error, 'Tự nhận diện quy tắc trước khi sửa.' unless @rule && @rule['kind'] == RuleSystem::KIND
            @rule = RuleSystem.edit(@rule, data['constraint'], remove: action == 'remove_constraint' ? data.fetch('id') : nil)
            @parametric_revision = (@parametric_revision || 0) + 1
            @message = 'Đã cập nhật quy tắc. Xem trước để kiểm tra; model chưa thay đổi.'
          end
          @plan = nil
        when 'analyze'
          if @snapshots.last && @snapshots.last.dig('parameter_source', 'kind') != 'manual'
            @rule = build_system
            @plan = nil
            @message = "Đã tổng hợp #{@rule['parameters'].length} tham số và #{@rule['constraints'].length} quy tắc trong cùng hệ."
            return publish
          end
          previous_exposed = @exposed_parameter_keys || (@rule && @rule['kind'] == 'module_parameter_set' ? @rule['exposed_parameter_keys'] : nil)
          dc_module = @snapshots.last && (!@snapshots.last.fetch('dc_inputs', {}).empty? || !Core.dc_thickness_parameters(@snapshots).empty?) && @snapshots.last.dig('parameter_source', 'kind') != 'manual'
          @rule = dc_module ? Core.learn_module(@snapshots) : Core.learn(@snapshots, data['parameter_label'])
          if dc_module && previous_exposed
            keys = @rule['parameters'].map { |parameter| parameter['key'] }
            kept = previous_exposed & keys
            # Settings from a different module must not disable all new inputs.
            Core.set_exposed_parameters!(@rule, kept) unless !previous_exposed.empty? && kept.empty?
          end
          @exposed_parameter_keys = dc_module ? @rule['exposed_parameter_keys'].dup : nil
          @selected_dc_key = nil if dc_module
          @plan = nil
          @message = if @rule['kind'] == 'module_parameter_set'
                       att_count = @rule['rules'].values.count { |entry| entry['rule_source'] == 'dc_attributes' }
                       "Đã tổng hợp #{@rule['parameters'].length} thông số: #{att_count} quy tắc từ ATT, #{@rule['rules'].length - att_count} quy tắc từ so sánh mẫu."
                     else
                       "Đã học #{@rule['parameter_label']} từ #{@rule['sample_count']}/#{@snapshots.length} trạng thái."
                     end
          @rule = RuleSystem.migrate(@snapshots.last, @rule)
          @exposed_parameter_keys = @rule['exposed_parameter_keys'].dup
        when 'save'
          raise Core::Error, 'Chưa có bộ quy tắc. Phân tích các trạng thái trước.' unless @rule
          path = UI.savepanel('Lưu bộ mẫu và quy tắc MH Module Studio', nil, 'module.mhmodule.json')
          return publish unless path
          path += '.json' unless File.extname(path).downcase == '.json'
          project = { 'format' => Core::FORMAT, 'version' => 1, 'snapshots' => @snapshots, 'rule' => @rule, 'selected_dc_key' => @selected_dc_key }
          atomic_write(path, JSON.pretty_generate(project))
          @message = "Đã lưu #{File.basename(path)}."
        when 'open_project'
          path = UI.openpanel('Mở bộ mẫu MH Module Studio', nil, 'MH Module|*.json||')
          return publish unless path
          raise Core::Error, 'File dự án vượt 32 MB.' if File.size(path) > 32 * 1024 * 1024
          project = JSON.parse(File.read(path, encoding: 'UTF-8').sub(/\A\uFEFF/, ''))
          raise Core::Error, 'Không phải bộ mẫu MH Module Studio v1.' unless project['format'] == Core::FORMAT && project['version'] == 1
          rule = Core.rule!(project.fetch('rule'))
          snapshots = project.fetch('snapshots')
          raise Core::Error, 'Bộ mẫu phải có 1–20 trạng thái.' unless snapshots.is_a?(Array) && snapshots.length.between?(1, 20)
          snapshots.each { |snapshot| Core.snapshot!(snapshot) }
          snapshots.each { |snapshot| snapshot['parameter'] = Core.number(snapshot['parameter']) }
          raise Core::Error, 'Các trạng thái bị trùng hoặc thiếu ID.' if snapshots.any? { |snapshot| snapshot['id'].to_s.empty? } || snapshots.map { |snapshot| snapshot['id'] }.uniq.length != snapshots.length
          converted_rule = RuleSystem.migrate(snapshots.last, rule)
          @captured_root_pid = nil
          @source_file = nil; @source_signature = nil
          @snapshots = snapshots
          @rule = converted_rule
          @parametric_revision = (@parametric_revision || 0) + 1
          @plan = nil
          @selected_dc_key = project['selected_dc_key'] || rule.dig('dc_parameter', 'dc_key')
          @exposed_parameter_keys = %w[module_parameter_set module_rule_system].include?(@rule['kind']) ? @rule['exposed_parameter_keys'].dup : nil
          @message = "Đã mở #{File.basename(path)}. Chọn module tương ứng để thử độ dày."
        when 'create_model'
          unless @rule && @snapshots.last && data['rule_id'] == @rule['id'] &&
                 data['snapshot_id'] == @snapshots.last['id'] && data['revision'] == (@parametric_revision || 0)
            raise Core::Error, 'Module hoặc quy tắc đã đổi. Đọc lại bảng trước khi tạo model.'
          end
          target = %w[module_parameter_set module_rule_system].include?(@rule['kind']) ? Parametric.targets(@rule) : data['target']
          @plan = Runtime.create_model(@snapshots.last, @rule, target)
          MH::ModuleStudio.show_options
          @message = 'Đã tạo và chọn model mới trong SketchUp, kèm công thức và bộ quy tắc riêng.'
        when 'preview', 'trial', 'update'
          raise Core::Error, 'Phân tích hoặc mở bộ quy tắc trước.' unless @rule
          root = Runtime.selected_root
          target = if data['parametric']
            unless data['rule_id'] == @rule['id'] && data['snapshot_id'] == @snapshots.last&.fetch('id')
              raise Core::Error, 'Bảng này thuộc module khác.'
            end
            Parametric.targets(@rule)
          else
            %w[module_parameter_set module_rule_system].include?(@rule['kind']) ? data.fetch('targets') : data['target']
          end
          case action
          when 'preview'
            @plan = Runtime.preview(root, @rule, target)
            @message = "Xem trước: #{@plan['changed_count']} tấm thay đổi; chưa sửa model."
          when 'trial'
            @plan = Runtime.make_trial(root, @rule, target)
            @message = 'Đã tạo và chọn bản thử bên cạnh. DC nguồn giữ nguyên. Có thể Undo một lần.'
          when 'update'
            @plan = Runtime.update_trial(root, @rule, target)
            @message = 'Đã cập nhật bản thử và các tấm liên quan cùng một thao tác Undo.'
          end
        else
          raise Core::Error, 'Thao tác không hỗ trợ.'
        end
        publish
      end

      def add_snapshot(snapshot, parameter_mode: 'manual')
        @assembly_root_pid = nil
        @module_name = Parametric.module_title(snapshot)
        raise Core::Error, 'Một bộ mẫu tối đa 20 trạng thái.' if @snapshots.length >= 20
        if parameter_mode == 'auto'
          Core.capture_parameter!(snapshot, multiple: true)
        else
          snapshot['parameter_source'] = { 'kind' => 'manual' }
        end
        @snapshots << snapshot
        invalidate
        if parameter_mode == 'auto'
          refresh_dc_selection(prefer_latest_change: true)
        else
          @selected_dc_key = nil
        end
        source = snapshot['parameter_source']
        detail = case source['kind']
                 when 'geometry_thickness_group' then "tự đọc nhóm #{source['part_keys'].length} tấm"
                 when 'dc_parameter_set' then 'đọc các tham số DC và đối chiếu hình học'
                 else 'nhập thủ công'
                 end
        detail += ', ước lượng từ hộp bao SKP' if source['kind'] == 'geometry_thickness_group' && !source['box_verified']
        @message = "Đã đọc #{snapshot['parts'].length} chi tiết. Độ dày mẫu #{snapshot['parameter']} mm (#{detail})."
        if @selected_dc_key
          choice = Core.dc_thickness_parameters(@snapshots).find { |item| item['dc_key'] == @selected_dc_key }
          @message = "Đã đọc #{snapshot['parts'].length} chi tiết. Tham số DC đang theo dõi: #{choice['label']} = #{choice['values'][snapshot['id']]} mm."
        end
        if parameter_mode == 'auto'
          @rule = build_system
          @message += " Đã quy đổi #{@rule['constraints'].length} quy tắc vào hệ chung."
        end
        publish
      end

      def build_system
        StudioCalculation.build_system(@snapshots, exposed_parameter_keys: @exposed_parameter_keys)
      end

      def refresh_dc_selection(prefer_latest_change: false)
        choices = Core.dc_thickness_parameters(@snapshots)
        @selected_dc_key = nil unless choices.any? { |choice| choice['dc_key'] == @selected_dc_key }
        @selected_dc_key ||= choices.max_by { |choice| choice['part_keys'].length }&.fetch('dc_key')
        return unless prefer_latest_change && @snapshots.length >= 2
        previous, latest = @snapshots.last(2)
        changed = choices.select do |choice|
          (choice['values'].fetch(latest['id']) - choice['values'].fetch(previous['id'])).abs > 0.02
        end
        @selected_dc_key = changed.first['dc_key'] if changed.length == 1
      end

      def invalidate
        @rule = nil
        @plan = nil
      end

      def captured_root!
        model = Sketchup.active_model
        raise Core::Error,'Model đã đổi; đọc lại SketchUp.' if @captured_model && !@captured_model.equal?(model)
        root = @captured_root_pid && model.find_entity_by_persistent_id(@captured_root_pid)
        raise Core::Error,'Module đã bị xóa hoặc đổi cấu trúc; đọc lại SketchUp.' unless root && root.valid? && Assembly.container?(root)
        root
      end

      def synchronize_model
        return unless defined?(Sketchup) && Sketchup.respond_to?(:active_model)
        model_changed(Sketchup.active_model)
      end

      def model_changed(model, force: false)
        return if !force && @model_context.equal?(model)
        UI.stop_timer(@read_timer) if @read_timer
        @read_timer=nil;@busy=false;@session_generation=(@session_generation || 0)+1
        @model_context=model
        @captured_model=nil;@captured_root_pid=nil;@captured_scope=nil;@assembly_root_pid=nil
        @source_file=nil;@source_signature=nil;@module_name=nil;@parametric_focus=nil
        @snapshots=[];@rule=nil;@plan=nil;@selected_dc_key=nil;@exposed_parameter_keys=nil
        @parametric_revision=(@parametric_revision || 0)+1
        @message='Đã chuyển model. Chọn module và bấm Đọc SketchUp để nạp quy tắc của model này.'
        publish
      end

      def capture_parametric_root(root)
        @captured_model = root.model; @captured_root_pid = root.persistent_id
        owner = root.model.active_path&.first
        @captured_scope = AssemblyContainers.managed?(owner) ? owner.persistent_id.to_s : nil
        @assembly_root_pid = AssemblyContainers.managed?(root) ? root.persistent_id : nil
        snapshot = @assembly_root_pid ? ParametricModel.assembly_snapshot(root) : Reader.live(root,label:root.name,parameter:nil).first
        if @assembly_root_pid
          @rule = nil
        else
          saved = root.get_attribute(Reader::DICT,'rule_json')
          rule = saved ? RuleSystem.migrate(snapshot,Core.rule!(JSON.parse(saved))) : StudioCalculation.build_system([snapshot])
          if snapshot['parameter_values']
            rule['parameters'].each { |param| param['value'] = snapshot['parameter_values'].fetch(param['key'],param['value']) }
            rule.fetch('parametric_variables',[]).each do |row|
              row['value'] = snapshot['parameter_values'].fetch(row['binding'],row['value']) if row['formula'].empty?
            end
          end
          @rule = ThicknessSymbols.normalize(DCCustomAttributes.upgrade(rule))
        end
        @snapshots = [snapshot]; @plan = nil
        @source_file = root.get_attribute(Reader::DICT,'library_source_path')
        @source_signature = root.get_attribute(Reader::DICT,'library_source_signature')
        @module_name = Parametric.module_title(snapshot,rule:@rule,fallback:Reader.module_name(root))
        @module_name = root.definition.name if @module_name.to_s.strip.empty?
        @module_name = File.basename(@source_file,'.skp') if @source_file && @module_name.match?(/\AMH (?:File )?Module\z/i)
        @parametric_revision += 1
        @message = @assembly_root_pid ? 'Đã đọc cụm. Đổi tên cụm / module con và Lưu SKP tại đây; chỉnh tham số chung trong Thông số module.' : 'Đã đọc module đang chọn vào bảng Parametric.'
      end

      def publish(error: false)
        return unless @dialog || @parametric_dialog
        RuleSystem.validate!(@rule) if @rule && @rule['kind'] == RuleSystem::KIND
        choices = Core.dc_thickness_parameters(@snapshots)
        selected = choices.find { |choice| choice['dc_key'] == @selected_dc_key }
        controls = if @rule && @rule['control_context']
                     @rule['control_context']
                   elsif @snapshots.last
                     Core.dc_controls(@snapshots.last, selected ? selected['factor'] : 25.4).reject { |key, _value| key == @selected_dc_key }
                   else
                     {}
                   end
        state = { 'snapshots' => @snapshots, 'rule' => @rule, 'plan' => @plan,
                  'source_file' => @source_file,
                  'parameter_choices' => choices, 'selected_dc_key' => @selected_dc_key,
                  'fixed_controls' => controls, 'fixed_controls_source' => @rule ? 'rule' : 'latest',
                  'message' => @message, 'error' => error, 'busy' => @busy }
        snapshot=@snapshots.last
        if snapshot && !snapshot['module_name'] && @captured_root_pid && (!@captured_model || @captured_model.equal?(Sketchup.active_model))
          root=Sketchup.active_model.find_entity_by_persistent_id(@captured_root_pid)
          snapshot['module_name']=Reader.module_name(root) if root && root.valid? && Assembly.container?(root)
        end
        @module_name = Parametric.module_title(snapshot,rule:@rule,fallback:@module_name)
        if @rule && Parametric.capture_label?(@rule['module_name']) && @rule['module_name_source']!='user'
          @rule['module_name']=@module_name
          @rule['module_name_source']='source'
        end
        state['module_name'] = @module_name
        if @rule && @rule['kind'] == RuleSystem::KIND && @snapshots.last
          begin
            state['parametric_sheet'] = Parametric.sheet(@rule, @snapshots.last, @plan)
            state['parametric_revision'] = @parametric_revision || 0
            state['parametric_focus'] = @parametric_focus
            state['parametric_rows'] = Parametric.describe(@rule, @snapshots.last)
            state['parametric_preview_rows'] = @plan ? Parametric.describe(@rule, @snapshots.last, @plan['target'], envelope: @plan['envelope']) : nil
          rescue Core::Error => detail_error
            state['parametric_diagnostic'] = detail_error.message
          end
        end
        if @assembly_root_pid
          begin
            state['parametric_sheet'] = ParametricModel.assembly_sheet(captured_root!)
            state['parametric_revision'] = @parametric_revision
          rescue Core::Error => detail_error
            state['parametric_diagnostic'] = detail_error.message
          end
        end
        # JSON string passed through JSON.parse: imported names cannot inject JavaScript or markup.
        json = JSON.generate(JSON.generate(state))
        [@dialog, @parametric_dialog].compact.each do |dialog|
          dialog.execute_script("window.receive(JSON.parse(#{json}));")
        end
        @parametric_focus = nil if @parametric_ready
      end

      def show_parametric
        synchronize_model
        root=ModuleOptions.selected_options_root if @snapshots.empty? && defined?(Sketchup) && Sketchup.respond_to?(:active_model)
        capture_parametric_root(root) if root
        if @parametric_dialog && @parametric_dialog.visible?
          @parametric_dialog.bring_to_front
          return publish
        end
        @parametric_dialog = UI::HtmlDialog.new(dialog_title: 'MH Module Studio · Parametric',
          preferences_key: 'MH_Module_Studio_Parametric', width: 1200, height: 850,
          min_width: 850, min_height: 600, resizable: true, style: UI::HtmlDialog::STYLE_DIALOG)
        @parametric_ready = false
        @parametric_dialog.set_file(File.join(__dir__.dup.force_encoding(Encoding::UTF_8), 'ui', 'parametric.html'))
        @parametric_dialog.add_action_callback('request') do |_context, raw|
          begin
            raise Core::Error, 'Yêu cầu quá lớn.' if raw.to_s.bytesize > 1024 * 1024
            request(JSON.parse(raw.to_s))
          rescue StandardError => error
            @message = error.message
            publish(error: true)
          end
        end
        current_dialog = @parametric_dialog
        @parametric_dialog.set_on_closed { @parametric_dialog = nil if @parametric_dialog.equal?(current_dialog) }
        @parametric_dialog.show
      end

      def atomic_write(path, text)
        temporary = path + '.tmp-' + Core::Ids.hex(5)
        begin
          File.write(temporary, text, mode: 'w', encoding: 'UTF-8')
          FileUtils.mv(temporary, path)
        ensure
          File.delete(temporary) if File.file?(temporary)
        end
      end
    end

    def self.open
      @panel ||= Panel.new
      @panel.show
    end

    def self.show_library_tab
      @panel ||= Panel.new
      @panel.show_library_tab
    end

    def self.sync_hud_board_commands
      return unless defined?(Sketchup) && Sketchup.respond_to?(:active_model) && Sketchup.active_model && UI.respond_to?(:menu) && defined?(UI::Command)

      @hud_board_commands ||= {}
      @hud_board_menu ||= UI.menu('Extensions').add_submenu('MH Module Studio · Bảng icon')
      boards = library.config.fetch('hud_boards', [])
      boards.each do |board|
        id = board.fetch('id')
        label = "MH Module Studio · Bảng icon · #{board.fetch('name')}"
        command = @hud_board_commands[id]
        if command
          command.menu_text = label
          next
        end
        command = UI::Command.new(label) { open_hud_board(id) }
        command.tooltip = "Mở bảng icon #{board.fetch('name')}"
        command.status_bar_text = "Gán phím tại Preferences → Shortcuts → #{label}"
        command.set_validation_proc do
          HUDBoards.current(library.config, id) ? MF_ENABLED : MF_GRAYED
        end
        @hud_board_menu.add_item(command)
        @hud_board_commands[id] = command
      end
    end

    def self.open_hud_board(id)
      board = HUDBoards.current(library.config, id)
      raise Core::Error, 'Bảng icon không còn tồn tại.' unless board

      library.save_settings('hud_board' => id)
      library.open_hud
    rescue StandardError => error
      UI.messagebox(error.message)
    end

    if defined?(Sketchup::AppObserver)
      class StudioSessionObserver < Sketchup::AppObserver
        %i[onNewModel onOpenModel].each do |event|
          define_method(event) do |model|
            MH::ModuleStudio.instance_variable_get(:@panel)&.model_changed(model,force:true)
            MH::ModuleStudio.sync_hud_board_commands
            MH::ModuleStudio.instance_variable_get(:@module_options)&.model_changed
            MH::ModuleStudio.instance_variable_get(:@assembly_tool)&.hud&.close
            MH::ModuleStudio.instance_variable_get(:@library)&.tool&.finish
          end
        end
        def onActivateModel(model)
          MH::ModuleStudio.instance_variable_get(:@panel)&.model_changed(model)
        end
      end
      unless @studio_session_observer
        @studio_session_observer=StudioSessionObserver.new
        Sketchup.add_observer(@studio_session_observer)
      end
    end

    def self.open_parametric
      @panel ||= Panel.new
      @panel.show_parametric
    end

    if defined?(Sketchup) && Sketchup.respond_to?(:active_model) && !@parametric_commands_registered
      @parametric_command = UI::Command.new('MH Module Studio · Parametric') { open_parametric }
      @parametric_command.tooltip = 'Mở bảng Parametric'
      @parametric_command.status_bar_text = 'Gán phím tại Preferences → Shortcuts → MH Module Studio · Parametric'
      UI.menu('Extensions').add_item(@parametric_command)
      @parametric_commands_registered = true
    end

    if defined?(Sketchup) && Sketchup.respond_to?(:active_model) && !@redraw_command_registered
      @redraw_command=UI::Command.new('MH Module Studio · Redraw') { redraw_selected }
      @redraw_command.tooltip='Tính lại module/cụm đang chọn theo quy tắc đã lưu'
      @redraw_command.status_bar_text='Gán phím tại Preferences → Shortcuts → MH Module Studio · Redraw'
      UI.menu('Extensions').add_item(@redraw_command)
      @redraw_command_registered=true
    end

    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions').add_submenu('MH Module Studio')
      menu.add_item('Học từ mẫu / Thử độ dày') { open }
      file_loaded(__FILE__)
    end
    if defined?(Sketchup) && UI.respond_to?(:add_context_menu_handler) && !@options_commands_registered
      @options_command = UI::Command.new('MH Module Studio · Thông số module') { show_options }
      @options_command.tooltip = 'Mở bảng Thông số module đang chọn'
      @options_command.status_bar_text = 'Gán phím tại Preferences → Shortcuts → MH Module Studio · Thông số module'
      UI.menu('Extensions').add_item(@options_command)
      UI.add_context_menu_handler do |menu|
        menu.add_item('Thông số module') { show_options } if ModuleOptions.selected_owned_root
      end
      @options_commands_registered = true
    end
    if defined?(Sketchup) && UI.respond_to?(:add_context_menu_handler) && !@assembly_options_context_registered
      UI.add_context_menu_handler do |menu|
        menu.add_item('Thông số module') { show_options } if AssemblyContainers.managed?(ModuleOptions.selected_options_root)
      end
      @assembly_options_context_registered = true
    end
    if defined?(Sketchup) && Sketchup.respond_to?(:active_model) && !@library_commands_registered
      @hud_command = UI::Command.new('MH Module Studio · Mở HUD') { open_hud }
      @hud_command.tooltip = 'Mở thư viện HUD; Esc / Space để thoát'
      @hud_command.status_bar_text = 'Gán phím tại Preferences → Shortcuts → MH Module Studio · Mở HUD'
      UI.menu('Extensions').add_item(@hud_command)
      @library_commands_registered = true
    end
    sync_hud_board_commands
    if defined?(Sketchup) && Sketchup.respond_to?(:active_model) && !@assembly_commands_registered
      @assembly_command = UI::Command.new('MH Module Studio · Liên kết module HUD') { open_assembly }
      @assembly_command.tooltip = 'Liên kết mặt, căn giữa, lặp và kéo trực tiếp trên model'
      @assembly_command.status_bar_text = 'Chọn mặt A/B; giữ mặt B để đổi khoảng cách, giữ thân module để di chuyển theo liên kết'
      UI.menu('Extensions').add_item(@assembly_command)
      if Sketchup.respond_to?(:add_context_menu_handler)
        Sketchup.add_context_menu_handler { |menu| menu.add_item('Liên kết module · HUD') { open_assembly } }
      end
      @assembly_commands_registered = true
    end
  end
end

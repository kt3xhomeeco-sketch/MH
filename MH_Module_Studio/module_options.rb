# encoding: UTF-8
require 'json'
require 'base64'
require 'tmpdir'
require_relative 'runtime'
require_relative 'parametric'
require_relative 'assembly'
require_relative 'options_parameters'

module MH
  module ModuleStudio
    if defined?(Sketchup::SelectionObserver)
      class OptionsSelectionObserver < Sketchup::SelectionObserver
        def initialize(window)
          super()
          @window = window
        end
        %i[onSelectionBulkChange onSelectionAdded onSelectionRemoved onSelectionCleared].each do |event|
          define_method(event) { |*_args| @window.schedule_refresh }
        end
      end
      class OptionsModelObserver < Sketchup::ModelObserver
        def initialize(window)
          super()
          @window = window
        end
        %i[onTransactionUndo onTransactionRedo onTransactionCommit onActivePathChanged].each do |event|
          define_method(event) { |*_args| @window.schedule_refresh }
        end
      end
      class OptionsAppObserver < Sketchup::AppObserver
        def initialize(window)
          super()
          @window = window
        end
        %i[onNewModel onOpenModel onActivateModel].each do |event|
          define_method(event) { |*_args| @window.schedule_refresh }
        end
      end
    end

    class ModuleOptions
      def self.selected_owned_root
        root = Runtime.selected_root
        return nil unless root.get_attribute(Reader::DICT, 'trial', false)
        root
      rescue Core::Error
        nil
      end

      def self.selected_options_root
        root = Runtime.selected_root
        root if root.get_attribute(Reader::DICT,'trial',false) || AssemblyContainers.managed?(root)
      rescue Core::Error
        nil
      end

      def self.sync_visibility(template)
        return unless defined?(Sketchup) && Sketchup.respond_to?(:active_model)
        root = selected_owned_root
        return unless root && root.get_attribute(Reader::DICT, 'rule_id') == template['id'] && template['kind'] == RuleSystem::KIND
        original = root.get_attribute(Reader::DICT, 'rule_json')
        rule = DCCustomAttributes.upgrade(Core.rule!(JSON.parse(original)))
        flags = Parametric.variables(template).to_h { |row| [row['id'], row['exported']] }
        rows = Parametric.variables(rule)
        rows.each { |row| row['exported'] = flags.fetch(row['id'], row['exported']) }
        rule = Parametric.edit_variables(rule, rows)
        return if JSON.generate(rule) == original
        operation = false
        root.model.start_operation('MH Hiện Tham Số Module', true)
        operation = true
        root.set_attribute(Reader::DICT, 'rule_json', JSON.generate(rule))
        values = JSON.parse(root.get_attribute(Reader::DICT, 'parameter_values_json', '{}'))
        root.set_attribute(Reader::DICT, 'exposed_parameters_json', JSON.generate(Core.exposed_parameters(rule, values)))
        root.model.commit_operation
        operation = false
      rescue StandardError
        root.model.abort_operation if operation
        raise
      end

      def show
        if @dialog && @dialog.visible?
          @dialog.bring_to_front
          return refresh
        end
        @dialog = UI::HtmlDialog.new(dialog_title: 'Thông số module', preferences_key: 'MH_Module_Studio_Options',
          width: 320, height: 285, min_width: 285, min_height: 130, resizable: true, style: UI::HtmlDialog::STYLE_UTILITY)
        @height = nil
        @thumbnail_key = nil
        @dialog.set_file(File.join(__dir__.dup.force_encoding(Encoding::UTF_8), 'ui', 'module_options.html'))
        @dialog.add_action_callback('request') do |_context, raw|
          begin
            raise Core::Error, 'Yêu cầu quá lớn.' if raw.to_s.bytesize > 16384
            request(JSON.parse(raw.to_s))
          rescue StandardError => error
            refresh(error: error.message)
          end
        end
        current = @dialog
        @dialog.set_on_closed do
          if @dialog.equal?(current)
            @dialog = nil
            detach
            @root = nil
          end
        end
        attach
        @dialog.show
      end

      def attach
        model = Sketchup.active_model
        return if @model.equal?(model)
        detach
        @model = model
        @session_token=Core::Ids.uuid
        @selection_observer = OptionsSelectionObserver.new(self)
        @model_observer = OptionsModelObserver.new(self)
        @app_observer = OptionsAppObserver.new(self)
        model.selection.add_observer(@selection_observer)
        model.add_observer(@model_observer)
        Sketchup.add_observer(@app_observer)
      end

      def detach
        model=@model
        @model=nil
        if model && (!model.respond_to?(:valid?) || model.valid?)
          model.selection.remove_observer(@selection_observer) if @selection_observer
          model.remove_observer(@model_observer) if @model_observer
        end
      ensure
        Sketchup.remove_observer(@app_observer) if @app_observer
        @model=nil;@root=nil;@members=nil;@display_rows=nil
        @selection_observer=nil;@model_observer=nil;@app_observer=nil
      end

      def model_changed
        @refresh_scheduled=nil
        @thumbnail_key=nil;@thumbnail=nil
        detach
        @token=Core::Ids.uuid
        attach if @dialog
        schedule_refresh
      end

      def schedule_refresh
        return unless @dialog && !@refresh_scheduled
        token = @refresh_scheduled = Object.new
        UI.start_timer(0.08, false) do
          next unless @refresh_scheduled.equal?(token)
          @refresh_scheduled = nil
          refresh if @dialog
        end
      end

      def request(data)
        case data['action']
        when 'ready' then refresh
        when 'close' then @dialog.close
        when 'close_hud'
          MH::ModuleStudio.instance_variable_get(:@library)&.tool&.finish
          refresh
        when 'change', 'changes'
          root = self.class.selected_options_root
          unless root && root.equal?(@root) && root.model.equal?(@model) && root.persistent_id.to_s == data['root_pid'] && data['token'] == @token
            raise Core::Error, 'Module đang chọn đã đổi. Nhập lại thông số trên module hiện tại.'
          end
          data['action']=='changes' ? apply_changes(data.fetch('changes')) : apply_change(data)
          refresh
        when 'save_skp'
          root = self.class.selected_options_root
          raise Core::Error,'Chọn lại module cần lưu.' unless root && root.equal?(@root) && (!data['root_pid'] || data['root_pid']==root.persistent_id.to_s)
          MH::ModuleStudio.library.save_selected(root)
          refresh
        else
          raise Core::Error, 'Thao tác không hỗ trợ.'
        end
      end

      def apply_change(data)
        apply_changes([data])
      end

      def apply_changes(changes)
        raise Core::Error,'Danh sách thay đổi không hợp lệ.' unless changes.is_a?(Array) && changes.length.between?(1,100)
        edits = {}
        changes.each do |data|
          display = @display_rows.flat_map { |row| [row,row['manual_input']].compact }.find { |row| row['id']==data['variable_id'] }
          raise Core::Error,'Tham số đã ẩn hoặc không được sửa trực tiếp.' unless display && display['editable']
          refs = display['targets'] || [{'pid'=>@root.persistent_id.to_s,'variable_id'=>display['id']}]
          refs.each { |ref| (edits[ref['pid']] ||= {})[ref['variable_id']] = data['value'] }
        end
        jobs = edits.filter_map do |pid,requested|
          member = @members.fetch(pid)
          entity = Assembly.root(@model,member['anchor'])
          unless entity.get_attribute(Reader::DICT,'rule_json')==member['raw'] && entity.get_attribute(Reader::DICT,'parameter_values_json')==member['values_raw']
            raise Core::Error,'Quy tắc hoặc thông số đã đổi. Bảng được đọc lại.'
          end
          rows = Parametric.variables(member['rule'])
          changed = false
          requested.each do |id,input|
            row = rows.find { |item| item['id']==id }
            raise Core::Error,'Tham số không còn trong module.' unless row
            before=Core.copy_data(row)
            DCOptions.assign!(member['rule'],rows,id,input)
            changed ||= before!=row
          end
          next unless changed
          edited = Parametric.edit_variables(member['rule'],rows)
          [Core.copy_data(member['anchor']),edited,Parametric.targets(edited)]
        end
        return if jobs.empty?
        if jobs.any? { |anchor,_rule,_values| anchor['scope'] } || Assembly.records(@model).any? do |record|
             AssemblyContainers.references(record).any? { |anchor| jobs.any? { |job| AssemblyContainers.identity(job[0])==AssemblyContainers.identity(anchor) } }
           end
          Assembly.transact(@model,Assembly.records(@model),updates:jobs)
        else
          anchor,rule,values = jobs.fetch(0)
          Runtime.update_trial(Assembly.root(@model,anchor),rule,values)
        end
      end

      def thumbnail(root)
        key = [root.model.object_id,root.persistent_id]
        return @thumbnail if @thumbnail_key == key
        path = File.join(Dir.tmpdir, "mh-module-thumbnail-#{Process.pid}-#{Core::Ids.hex(5)}.png")
        @thumbnail = root.definition.save_thumbnail(path) ? "data:image/png;base64,#{Base64.strict_encode64(File.binread(path))}" : nil
        @thumbnail_key = key
        @thumbnail
      rescue StandardError
        nil
      ensure
        File.delete(path) if path && File.file?(path)
      end

      def refresh(error: nil)
        return unless @dialog
        @refresh_scheduled = nil
        attach
        root = self.class.selected_options_root
        @token = Core::Ids.uuid
        if root
          @root = root
          grouped = AssemblyContainers.managed?(root)
          children = grouped ? AssemblyContainers.members(root).select { |item| item.get_attribute(Reader::DICT,'trial',false) } : [root]
          scope = grouped ? root.persistent_id.to_s : @model.active_path&.first&.get_attribute(Reader::DICT,'assembly_component',false) && @model.active_path.first.persistent_id.to_s
          @members = children.to_h do |child|
            raw = child.get_attribute(Reader::DICT,'rule_json')
            raise Core::Error,'Module chưa lưu bộ quy tắc hợp lệ.' unless raw.is_a?(String) && raw.bytesize<=16*1024*1024
            rule = ThicknessSymbols.normalize(DCCustomAttributes.upgrade(Core.rule!(JSON.parse(raw))))
            raise Core::Error,'Module cần hệ quy tắc Parametric.' unless rule['kind']==RuleSystem::KIND
            values_raw = child.get_attribute(Reader::DICT,'parameter_values_json')
            values = values_raw ? JSON.parse(values_raw) : {}
            # Draft values must reflect this instance, including prior option edits.
            rule['parameters'].each { |param| param['value'] = values.fetch(param['key'],param['value']) if param['editable'] }
            rule.fetch('parametric_variables',[]).each { |row| row['value'] = values.fetch(row['binding'],row['value']) if row['binding'] && row['formula'].empty? }
            [child.persistent_id.to_s,{'pid'=>child.persistent_id.to_s,'name'=>child.name,'rule'=>rule,'values'=>values,
              'anchor'=>{'root'=>child.persistent_id.to_s,'scope'=>scope || nil}.compact,'raw'=>raw,'values_raw'=>values_raw}]
          end
          @display_rows = grouped ? OptionsParameters.grouped(@members.values) : OptionsParameters.rows(@members.values.first['rule'],@members.values.first['values'])
          payload = { 'root_pid' => root.persistent_id.to_s, 'token' => @token, 'name' => root.name.to_s,
                      'thumbnail' => thumbnail(root), 'error' => error,'rows'=>@display_rows.map { |row| row.reject { |key,_value| key=='targets' } } }
        else
          @root = nil
          payload = { 'token' => @token, 'name' => 'Chọn module', 'rows' => [], 'empty' => true,
                      'error' => error, 'message' => 'Chọn một module đã tạo để sửa thông số.' }
        end
        send_state(payload)
      rescue StandardError => detail
        @root = nil
        send_state('token' => @token, 'name' => 'Thông số module', 'rows' => [], 'error' => detail.message)
      end

      def send_state(payload)
        payload['session']=@session_token
        payload['hud_active'] = MH::ModuleStudio.instance_variable_get(:@library)&.tool&.active == true
        @dialog.execute_script("window.receive(JSON.parse(#{JSON.generate(JSON.generate(payload))}));")
        sections = payload['rows'].filter_map { |row| row['section_id'] }.uniq.length
        manual=payload['rows'].count { |row| row['manual_input'] }
        height = [[125 + payload['rows'].length * 28 + manual*27 + sections*23 + (payload['error'] ? 30 : 0), 160].max, 580].min
        @dialog.set_size(320, height) unless @height == height
        @height = height
      end
    end

    def self.show_options
      @module_options ||= ModuleOptions.new
      @module_options.show
    end
  end
end

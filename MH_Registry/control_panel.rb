# encoding: UTF-8
#
# MH Control Panel — bảng điều khiển hợp nhất phong cách OpenZSU cho toàn hệ MH.
#  - Sidebar: panel cài đặt NHÚNG của MH_panel (Thiết lập chung / Tạo ván / Tạo cánh)
#    + launcher cho các app khác (lệnh đã đăng ký qua MH::RegistryApp::Menu).
#  - Cài đặt nhúng được định tuyến lưu/đọc/preset về MH::Panel::Settings.

require 'fileutils'

module MH
  module RegistryApp
    module ControlPanel
      module_function

      HTML_FILE = File.join(PATH, 'control_panel', 'html', 'index.html').freeze
      # Section cài đặt nhúng -> đều thuộc MH::Panel::Settings.
      PANEL_SECTIONS = %w[cai_dat tao_van tao_canh].freeze
      REGISTRY_SECTIONS = %w[reg_main reg_superimp reg_naming reg_ma_vat_lieu].freeze
      NATIVE_SECTIONS = %w[
        thongke_panel viewport_names_settings fast_rename_settings
        select_similar_settings assemble_settings pk_settings
      ].freeze
      CONTROL_PANEL_SECTIONS = (PANEL_SECTIONS + REGISTRY_SECTIONS + NATIVE_SECTIONS).freeze

      @dialog = nil unless instance_variable_defined?(:@dialog)

      FAST_RENAME_SETTING_DEFAULTS = {
        'gap_threshold_mm' => 1000.0,
        'default_sp_start_num' => 1,
        'default_split_axis' => 'x',
        'split_all_default' => false,
        'auto_contact_split' => true,
        'cp_tolerance_mm' => 0.05,
        'cp_penetration_tolerance_mm' => 0.05,
        'cp_max_pass' => 20,
        'cp_separator_axes' => %w[x z],
        'exempt_keywords' => [
          'phào nóc', 'phao noc', 'len chân', 'len chan', 'xương nẹp', 'xuong nep',
          'chân bệ', 'chan be', 'len bệ chân', 'len be chan', 'len bệ', 'len be',
          'bệ chân', 'be chan', 'chặn cánh', 'chan canh'
        ],
        'sp_base_only_keywords' => [
          'xương nẹp', 'xuong nep', 'phào nóc', 'phao noc', 'len chân', 'len chan',
          'chân bệ', 'chan be', 'len bệ chân', 'len be chan', 'len bệ', 'len be',
          'bệ chân', 'be chan', 'chặn cánh', 'chan canh'
        ],
        'modul_contact_keywords' => [],
        'base_accessory_keywords' => [
          'len chân', 'len chan', 'len bệ chân', 'len be chan',
          'len bệ', 'len be', 'bệ chân', 'be chan'
        ],
        'named_contact_split_pairs' => [
          { 'a' => ['hông trái', 'hong trai'], 'b' => ['hông phải', 'hong phai'], 'axis' => 'x' },
          { 'a' => ['đáy', 'day'], 'b' => ['nóc', 'noc'], 'axis' => 'z' }
        ]
      }.freeze

      def default_bool(value, fallback = false)
        return fallback if value.nil?
        return value if value == true || value == false
        text = value.to_s.strip.downcase
        return true if %w[true 1 yes on].include?(text)
        return false if %w[false 0 no off].include?(text)
        fallback
      end

      # ---- Nạp MH_panel khi cần -------------------------------------------
      def ensure_panel_loaded
        return true if defined?(MH::Panel::Settings)
        path = File.join(Sketchup.find_support_file('Plugins'), 'MH_panel', 'src', 'main.rb')
        load path if File.exist?(path)
        defined?(MH::Panel::Settings) ? true : false
      rescue
        false
      end

      def panel_settings
        ensure_panel_loaded
        defined?(MH::Panel::Settings) ? MH::Panel::Settings : nil
      end

      def ensure_settings_facade
        return true if defined?(MH::Settings)
        path = File.join(Sketchup.find_support_file('Plugins'), 'MH_shared.rb')
        load path if File.exist?(path)
        defined?(MH::Settings)
      rescue => e
        MH::RegistryApp.dbg("[MH_Registry::ControlPanel] load Settings facade error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
        false
      end

      def ensure_pk_loaded
        return true if defined?(::MH_PK_Addon) && ::MH_PK_Addon.respond_to?(:save_settings)
        path = File.join(Sketchup.find_support_file('Plugins'), 'MH_PK_Addon', 'main.rb')
        load path if File.exist?(path)
        defined?(::MH_PK_Addon) && ::MH_PK_Addon.respond_to?(:save_settings)
      rescue => e
        MH::RegistryApp.dbg("[MH_Registry::ControlPanel] load PK Addon error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
        false
      end

      def pk_settings_data
        return { 'ok' => false, 'error' => 'MH_PK_Addon chưa sẵn sàng.' } unless ensure_pk_loaded

        labels = if ::MH_PK_Addon.const_defined?(:FACE_MODE_LABELS)
                   ::MH_PK_Addon::FACE_MODE_LABELS
                 else
                   { 'largest' => 'Mặt lớn nhất', 'smallest' => 'Mặt nhỏ nhất' }
                 end
        path = ::MH_PK_Addon.default_xlsx_path.to_s
        path = settings_read('pk_addon', 'library_path', path, :global).to_s
        {
          'ok' => true,
          'path' => path,
          'shape' => settings_read('pk_addon', 'shape', ::MH_PK_Addon.default_shape.to_s, :global).to_s,
          'size_mm' => settings_read('pk_addon', 'size_mm', ::MH_PK_Addon.default_size_mm.to_f, :global).to_f,
          'face_mode' => settings_read('pk_addon', 'face_mode', ::MH_PK_Addon.default_face_mode.to_s, :global).to_s,
          'face_modes' => labels,
          'library_exists' => !path.empty? && File.file?(path),
          'library_count' => ::MH_PK_Addon.accessory_names_from_file(path).length
        }
      rescue => e
        { 'ok' => false, 'error' => "#{e.class}: #{e.message}" }
      end

      def ensure_thongke_loaded
        return true if defined?(::MH_Thongke) && ::MH_Thongke.respond_to?(:save_preferences)
        path = File.join(Sketchup.find_support_file('Plugins'), 'MH_Thongke', 'main.rb')
        load path if File.exist?(path)
        defined?(::MH_Thongke) && ::MH_Thongke.respond_to?(:save_preferences)
      rescue => e
        MH::RegistryApp.dbg("[MH_Registry::ControlPanel] load Thongke error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
        false
      end

      def thongke_panel_data
        return { 'ok' => false, 'error' => 'MH_Thongke chưa sẵn sàng.' } unless ensure_thongke_loaded

        ::MH_Thongke.load_preferences if ::MH_Thongke.respond_to?(:load_preferences)
        status = if ::MH_Thongke.respond_to?(:import_excel_current_status)
                   ::MH_Thongke.import_excel_current_status
                 else
                   { 'ok' => true, 'path' => '', 'rows' => 0, 'material_rows' => 0 }
                 end
        session = ::MH_Thongke.respond_to?(:session) ? ::MH_Thongke.session : nil
        legacy_hidden = if ::MH_Thongke.respond_to?(:hidden_list)
                          ::MH_Thongke.hidden_list
                        elsif session && session.respond_to?(:hidden_list)
                          session.hidden_list
                        else
                          []
                        end
        hidden = settings_read('thongke', 'hidden_list', legacy_hidden, :project)
        {
          'ok' => true,
          'excel' => status,
          'hidden_list' => Array(hidden),
          'main_visible' => (::MH_Thongke.respond_to?(:main_dialog_visible?) && ::MH_Thongke.main_dialog_visible?),
          'mini_visible' => (::MH_Thongke.respond_to?(:mini_import_visible?) && ::MH_Thongke.mini_import_visible?),
          'hud_visible' => (::MH_Thongke.respond_to?(:material_hud_visible?) && ::MH_Thongke.material_hud_visible?),
          'info_hud_visible' => (::MH_Thongke.respond_to?(:info_hud_visible?) && ::MH_Thongke.info_hud_visible?)
        }
      rescue => e
        { 'ok' => false, 'error' => "#{e.class}: #{e.message}" }
      end

      def push_thongke_panel(dialog, message = nil, error = false)
        data = thongke_panel_data
        data['message'] = message if message
        data['message_error'] = error
        dialog.execute_script("if(window.loadThongkePanel){window.loadThongkePanel(#{data.to_json});}")
      end

      def settings_write(app, key, value, scope)
        return false unless ensure_settings_facade
        MH::Settings.write(app, key, value, scope: scope)
        true
      rescue => e
        MH::RegistryApp.dbg("[MH_Registry::ControlPanel] settings_write #{app}.#{key} error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
        false
      end

      def settings_read(app, key, fallback, scope = :auto)
        return fallback unless ensure_settings_facade
        MH::Settings.read(app, key, fallback, scope: scope)
      rescue => e
        MH::RegistryApp.dbg("[MH_Registry::ControlPanel] settings_read #{app}.#{key} error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
        fallback
      end

      def list_from_payload(value)
        list = value.is_a?(Array) ? value : value.to_s.split(/\r?\n|,/)
        list.map(&:to_s).map(&:strip).reject(&:empty?).uniq
      end

      def sanitize_named_contact_pairs(rows)
        Array(rows).map do |row|
          next unless row.is_a?(Hash)
          a = list_from_payload(row['a'] || row[:a])
          b = list_from_payload(row['b'] || row[:b])
          axis = (row['axis'] || row[:axis]).to_s.downcase
          next if a.empty? || b.empty? || !%w[x y z].include?(axis)
          { 'a' => a, 'b' => b, 'axis' => axis }
        end.compact
      end

      def ensure_fast_rename_loaded
        return true if defined?(MH::FastRename)
        path = File.join(Sketchup.find_support_file('Plugins'), 'MH_fast_rename', 'main.rb')
        load path if File.exist?(path)
        defined?(MH::FastRename)
      rescue => e
        MH::RegistryApp.dbg("[MH_Registry::ControlPanel] load Fast Rename error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
        false
      end

      def fast_rename_settings_data
        settings = {}
        FAST_RENAME_SETTING_DEFAULTS.each do |key, fallback|
          settings[key] = settings_read('fast_rename', key, fallback, :global)
        end
        {
          'ok' => true,
          'settings' => settings,
          'available_settings' => [
            'Khoảng cách gộp mặc định',
            'Số SP bắt đầu mặc định',
            'Trục cắt mặc định',
            'Mặt cắt xuyên một khối hay xuyên toàn bộ zone',
            'Tự tách modul bằng mặt tiếp xúc khi đánh số lại',
            'Dung sai tiếp xúc mặt cắt',
            'Dung sai xuyên/lấn cho mặt cắt',
            'Số vòng tách contact-plane tối đa',
            'Trục được phép dò mặt cắt',
            'Keyword miễn cắt',
            'Keyword chỉ bám mã SP gốc',
            'Keyword bám modul theo tiếp xúc',
            'Keyword phụ kiện bệ/len chân',
            'Cặp tên chi tiết dùng để sinh mặt cắt'
          ]
        }
      rescue => e
        { 'ok' => false, 'error' => "#{e.class}: #{e.message}" }
      end

      def push_fast_rename_settings(dialog, message = nil, error = false)
        data = fast_rename_settings_data
        data['message'] = message if message
        data['message_error'] = error
        dialog.execute_script("if(window.loadFastRenameSettings){window.loadFastRenameSettings(#{data.to_json});}")
      end

      def save_fast_rename_settings_payload(payload)
        return false unless payload.is_a?(Hash)
        values = {}
        values['gap_threshold_mm'] = [[payload['gap_threshold_mm'].to_f, 1.0].max, 100_000.0].min
        values['default_sp_start_num'] = [[payload['default_sp_start_num'].to_i, 1].max, 9999].min
        axis = payload['default_split_axis'].to_s.downcase
        values['default_split_axis'] = %w[x y z].include?(axis) ? axis : 'x'
        values['split_all_default'] = !!payload['split_all_default']
        values['auto_contact_split'] = !!payload['auto_contact_split']
        values['cp_tolerance_mm'] = [[payload['cp_tolerance_mm'].to_f, 0.001].max, 10.0].min
        values['cp_penetration_tolerance_mm'] = [[payload['cp_penetration_tolerance_mm'].to_f, 0.0].max, 10.0].min
        values['cp_max_pass'] = [[payload['cp_max_pass'].to_i, 1].max, 200].min
        axes = list_from_payload(payload['cp_separator_axes']).map(&:downcase).select { |a| %w[x y z].include?(a) }.uniq
        values['cp_separator_axes'] = axes.empty? ? %w[x z] : axes
        %w[exempt_keywords sp_base_only_keywords modul_contact_keywords base_accessory_keywords].each do |key|
          values[key] = list_from_payload(payload[key])
        end
        pairs = sanitize_named_contact_pairs(payload['named_contact_split_pairs'])
        values['named_contact_split_pairs'] = pairs.empty? ? FAST_RENAME_SETTING_DEFAULTS['named_contact_split_pairs'] : pairs
        values.each { |key, value| settings_write('fast_rename', key, value, :global) }
        MH::FastRename.invalidate_settings_cache if defined?(MH::FastRename) && MH::FastRename.respond_to?(:invalidate_settings_cache)
        true
      end

      def ensure_assemble_loaded
        return true if defined?(MH::Assemble) && MH::Assemble.respond_to?(:save_config)
        path = File.join(Sketchup.find_support_file('Plugins'), 'MH_assemble', 'main.rb')
        load path if File.exist?(path)
        defined?(MH::Assemble) && MH::Assemble.respond_to?(:save_config)
      rescue => e
        MH::RegistryApp.dbg("[MH_Registry::ControlPanel] load Assemble error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
        false
      end

      def assemble_panel_data
        return { 'ok' => false, 'error' => 'MH Assemble chưa sẵn sàng.' } unless ensure_assemble_loaded

        cfg = MH::Assemble.config
        profiles = MH::Assemble.profiles
        scope = cfg['no_door_scope'].is_a?(Hash) ? cfg['no_door_scope'] : {}
        scope = settings_read('assemble', 'no_door_scope', scope, :project)
        legacy_no_door = Array((profiles['no_door'] || {})['hide'])
        {
          'ok' => true,
          'no_door_product' => Array(scope['product'] || legacy_no_door).map(&:to_s),
          'no_door_module' => Array(scope['module'] || legacy_no_door).map(&:to_s),
          'hide_common' => Array(settings_read('assemble', 'hide_common', cfg['hide_common'], :project)).map(&:to_s),
          'hidden_tags' => Array(settings_read('assemble', 'hidden_tags', cfg['hidden_tags'], :project)).map(&:to_s),
          'no_number' => Array(settings_read('assemble', 'no_number', cfg['no_number'], :project)).map(&:to_s),
          'draw_ratio' => settings_read('assemble', 'draw_ratio', (cfg['draw_ratio'] || 'auto'), :global),
          'draw_ratios' => Array(settings_read('assemble', 'draw_ratios', (cfg['draw_ratios'] || [5, 10, 15, 20, 25, 50, 100]), :global)).map(&:to_i).select { |n| n.between?(1, 1000) }.uniq,
          'sub_modules' => Array(settings_read('assemble', 'sub_modules', cfg['sub_modules'], :project)).map do |row|
            next unless row.is_a?(Hash)
            {
              'enabled' => row.key?('enabled') ? !!row['enabled'] : true,
              'key' => row['key'].to_s,
              'label' => row['label'].to_s
            }
          end.compact,
          'config_path' => (MH::Assemble.const_defined?(:CONFIG_PATH) ? MH::Assemble::CONFIG_PATH.to_s : '')
        }
      rescue => e
        { 'ok' => false, 'error' => "#{e.class}: #{e.message}" }
      end

      def push_assemble_panel(dialog, message = nil, error = false)
        data = assemble_panel_data
        data['message'] = message if message
        data['message_error'] = error
        dialog.execute_script("if(window.loadAssemblePanel){window.loadAssemblePanel(#{data.to_json});}")
      end

      # Tên có thật trong model để chọn nhanh: parts (definition + instance names), tags (layers).
      def assemble_model_names
        model = (defined?(Sketchup) ? Sketchup.active_model : nil)
        return { 'ok' => true, 'parts' => [], 'tags' => [] } unless model
        parts = {}
        model.definitions.each do |d|
          next if d.respond_to?(:image?) && d.image?
          nm = d.name.to_s.strip
          parts[nm] = true unless nm.empty?
          d.instances.each do |inst|
            inm = inst.name.to_s.strip
            parts[inm] = true unless inm.empty?
          end
        end
        tags = model.layers.map { |l| l.name.to_s.strip }.reject(&:empty?).uniq
        { 'ok' => true, 'parts' => parts.keys.sort, 'tags' => tags.sort }
      rescue => e
        { 'ok' => false, 'error' => "#{e.class}: #{e.message}", 'parts' => [], 'tags' => [] }
      end

      def ensure_select_similar_loaded
        return true if defined?(MH::SelectSimilar) && MH::SelectSimilar.respond_to?(:settings)
        path = File.join(Sketchup.find_support_file('Plugins'), 'MH_SelectSimilar', 'main.rb')
        load path if File.exist?(path)
        defined?(MH::SelectSimilar) && MH::SelectSimilar.respond_to?(:settings)
      rescue => e
        MH::RegistryApp.dbg("[MH_Registry::ControlPanel] load Select Similar error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
        false
      end

      def select_similar_panel_data
        return { 'ok' => false, 'error' => 'MH Select Similar chưa sẵn sàng.' } unless ensure_select_similar_loaded

        MH::SelectSimilar.load_settings if MH::SelectSimilar.respond_to?(:load_settings)
        settings = {}
        MH::SelectSimilar.settings.each { |key, value| settings[key.to_s] = value }
        settings.keys.each do |key|
          settings[key] = settings_read('select_similar', key, settings[key], :global)
        end
        settings['key_isolate'] ||= 'I'
        settings['key_settings'] ||= 'TAB'
        quick_search_items = settings_read('select_similar', 'quick_search_items', nil, :global)
        quick_search_items = nil unless quick_search_items.is_a?(Array) && quick_search_items.any?
        apply_select_similar_quick_search_items(quick_search_items) if quick_search_items
        {
          'ok' => true,
          'settings' => settings,
          'quick_search_items' => quick_search_items || (MH::SelectSimilar.respond_to?(:quick_search_items) ? MH::SelectSimilar.quick_search_items : []),
          'search_suggestions' => (MH::SelectSimilar.respond_to?(:search_suggestions) ? MH::SelectSimilar.search_suggestions : [])
        }
      rescue => e
        { 'ok' => false, 'error' => "#{e.class}: #{e.message}" }
      end

      def push_select_similar_panel(dialog, message = nil, error = false)
        data = select_similar_panel_data
        data['message'] = message if message
        data['message_error'] = error
        dialog.execute_script("if(window.loadSelectSimilarPanel){window.loadSelectSimilarPanel(#{data.to_json});}")
      end

      def apply_select_similar_quick_search_items(items)
        return false unless ensure_select_similar_loaded
        if MH::SelectSimilar.respond_to?(:quick_search_items=)
          MH::SelectSimilar.quick_search_items = items
        else
          texts = Array(items).map { |item| item.is_a?(Hash) ? (item['text'] || item[:text]).to_s : item.to_s }
          MH::SelectSimilar.search_suggestions = texts if MH::SelectSimilar.respond_to?(:search_suggestions=)
        end
        true
      end

      def save_select_similar_quick_search_items(items)
        return false unless ensure_select_similar_loaded
        rows = []
        Array(items).first(1000).each_with_index do |item, index|
          next unless item.is_a?(Hash)
          text = (item['text'] || item['value']).to_s.strip
          next if text.empty?
          shortcut = if MH::SelectSimilar.respond_to?(:normalize_quick_search_shortcut)
                       MH::SelectSimilar.normalize_quick_search_shortcut(item['shortcut'])
                     end
          shortcut ||= format('%03d', index)
          rows << { 'shortcut' => shortcut, 'text' => text }
        end
        settings_write('select_similar', 'quick_search_items', rows, :global)
        apply_select_similar_quick_search_items(rows)
        rows
      end

      def ensure_rename_loaded
        return true if defined?(MH::Rename)
        path = File.join(Sketchup.find_support_file('Plugins'), 'MH_Rename', 'main.rb')
        load path if File.exist?(path)
        defined?(MH::Rename)
      rescue => e
        MH::RegistryApp.dbg("[MH_Registry::ControlPanel] load Rename error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
        false
      end

      def viewport_names_data
        key = 'MH_Rename_Viewport'
        {
          'ok' => true,
          'line_spacing' => settings_read('viewport_names', 'line_spacing', Sketchup.read_default(key, 'line_spacing', 28), :global).to_i,
          'text_gap' => settings_read('viewport_names', 'text_gap', Sketchup.read_default(key, 'text_gap', 150), :global).to_i,
          'text_display_mode' => settings_read('viewport_names', 'text_display_mode', Sketchup.read_default(key, 'text_display_mode', 'all'), :global).to_s,
          'show_hidden_lines' => default_bool(settings_read('viewport_names', 'show_hidden_lines', Sketchup.read_default(key, 'show_hidden_lines', true), :global), true),
          'label_style' => settings_read('viewport_names', 'label_style', Sketchup.read_default(key, 'label_style', 'leader'), :global).to_s,
          'show_part_id' => default_bool(settings_read('viewport_names', 'show_part_id', Sketchup.read_default(key, 'show_part_id', true), :global), true),
          'show_part_prefix' => default_bool(settings_read('viewport_names', 'show_part_prefix', Sketchup.read_default(key, 'show_part_prefix', true), :global), true),
          'show_part_suffix' => default_bool(settings_read('viewport_names', 'show_part_suffix', Sketchup.read_default(key, 'show_part_suffix', true), :global), true),
          'show_label_bg' => default_bool(settings_read('viewport_names', 'show_label_bg', Sketchup.read_default(key, 'show_label_bg', false), :global), false),
          'hidden_layers' => Array(settings_read('viewport_names', 'hidden_layers', Sketchup.read_default(key, 'hidden_layers', '').to_s.split(';;').reject(&:empty?), :global)),
          'tool_active' => (defined?(MH::Rename::ViewportNameTool) && MH::Rename::ViewportNameTool.instance ? true : false)
        }
      rescue => e
        { 'ok' => false, 'error' => "#{e.class}: #{e.message}" }
      end

      def push_viewport_names_panel(dialog, message = nil, error = false)
        data = viewport_names_data
        data['message'] = message if message
        data['message_error'] = error
        dialog.execute_script("if(window.loadViewportNamesPanel){window.loadViewportNamesPanel(#{data.to_json});}")
      end

      def refresh_viewport_names_tool
        return unless ensure_rename_loaded
        tool = (defined?(MH::Rename::ViewportNameTool) ? MH::Rename::ViewportNameTool.instance : nil)
        return unless tool
        if tool.respond_to?(:reload_config)
          tool.reload_config
        else
          Sketchup.active_model.active_view.invalidate rescue nil
        end
      rescue => e
        MH::RegistryApp.dbg("[MH_Registry::ControlPanel] refresh Viewport Names error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
      end

      def refresh_fast_rename_tool
        return unless ensure_fast_rename_loaded
        tool = Sketchup.active_model.tools.active_tool rescue nil
        return unless defined?(MH::FastRename::FastRenameTool) && tool.is_a?(MH::FastRename::FastRenameTool)
        tool.reload_user_settings if tool.respond_to?(:reload_user_settings)
      rescue => e
        MH::RegistryApp.dbg("[MH_Registry::ControlPanel] refresh Fast Rename error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
      end

      def attach_registry_bridge(dialog)
        return if dialog.instance_variable_get(:@mh_cp_registry_attached)

        MH::RegistryApp.ensure_runtime_ready if MH::RegistryApp.respond_to?(:ensure_runtime_ready)
        MH::Shared::Bridge.decorate(dialog) unless dialog.instance_variable_get(:@bridge)
        MH::RegistryApp.attach_callbacks(dialog)
        dialog.instance_variable_set(:@mh_cp_registry_attached, true)
      rescue => e
        MH::RegistryApp.dbg("[MH_Registry::ControlPanel] registry attach error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
      end

      # ---- Danh sách app launcher (trừ Panel — đã nhúng settings) ---------
      EMBEDDED_APP_LAUNCHERS = ['Panel', 'Registry', 'Superimp', 'Assemble', 'PK Addon', 'Fast Rename'].freeze

      def apps_data
        order = []
        grouped = {}
        Menu.entries.each do |e|
          name = e[:app].to_s
          next if name.empty? || EMBEDDED_APP_LAUNCHERS.include?(name)
          next if name == 'PK Addon' && e[:key].to_s == 'settings'
          unless grouped.key?(name)
            grouped[name] = []
            order << name
          end
          grouped[name] << { 'key' => e[:key].to_s, 'label' => e[:label].to_s }
        end
        order.map { |name| { 'name' => name, 'actions' => grouped[name] } }
      end

      # ---- Mở dialog ------------------------------------------------------
      def open(section = nil)
        if @dialog && (@dialog.visible? rescue false)
          @dialog.bring_to_front
          switch_section(section) if section
          return @dialog
        end
        ensure_panel_loaded

        dialog = UI::HtmlDialog.new(
          dialog_title: 'MH Control Panel',
          preferences_key: 'mh_control_panel',
          scrollable: false,
          resizable: true,
          width: 860,
          height: 640,
          min_width: 680,
          min_height: 520
        )
        @dialog = dialog
        dialog.set_file(HTML_FILE)
        register_callbacks(dialog)
        dialog.set_on_closed { @dialog = nil if @dialog.equal?(dialog) }
        dialog.show
        switch_section(section) if section
        dialog
      rescue => e
        MH::RegistryApp.dbg("[MH_Registry::ControlPanel] open error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
        nil
      end

      def open?
        !!(@dialog && (@dialog.visible? rescue false))
      end

      def switch_section(section)
        return unless @dialog
        id = section.to_s
        id = 'cai_dat' unless CONTROL_PANEL_SECTIONS.include?(id)
        script = "(function(){var n=#{id.to_json},k=0,t=setInterval(function(){k+=1;" \
                 "if(typeof switchTo==='function'){switchTo(n);clearInterval(t);}" \
                 "else if(k>80){clearInterval(t);}},80);})();"
        UI.start_timer(0.2, false) { @dialog.execute_script(script) rescue nil }
      rescue => e
        MH::RegistryApp.dbg("[MH_Registry::ControlPanel] switch_section error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
      end

      def close
        @dialog.close if @dialog
      end

      def refresh_active_tool
        tool = Sketchup.active_model.tools.active_tool
        if tool.respond_to?(:init_var)
          tool.init_var
          MH::Panel::View.invalidate if defined?(MH::Panel::View)
        end
      rescue
      end

      def push_presets(dialog, section)
        s = panel_settings
        return unless s
        data = s.read_all
        presets = (data[section] && data[section]['presets']) || []
        collapsed = (data[section] && data[section]['collapsed_groups']) || {}
        dialog.execute_script("if(window.sendPresetsToIframe){window.sendPresetsToIframe('#{section}', #{presets.to_json}, #{collapsed.to_json});}")
      end

      def register_callbacks(dialog)
        # --- Launcher ---
        dialog.add_action_callback('load_apps') do |_c|
          dialog.execute_script("if(window.loadApps){window.loadApps(#{apps_data.to_json});}")
        end
        dialog.add_action_callback('invoke') do |_c, params|
          app, key = params.to_s.split('@', 2)
          Menu.invoke(app, key)
        end
        dialog.add_action_callback('activate_panel_tool') do |_c, tool|
          if ensure_panel_loaded
            case tool.to_s
            when 'tao_van'
              MH::Panel.activate_tao_van
            when 'tao_canh'
              MH::Panel.activate_tao_canh
            end
          end
        end

        dialog.add_action_callback('export_config_backup') do |_c|
          if ensure_settings_facade
            path = UI.savepanel('Sao lưu MH Config', nil, 'MH_Config_Backup.xlsx')
            if path
              path += '.xlsx' unless path.downcase.end_with?('.xlsx')
              MH::Settings.export_backup_xlsx(path, source: :all)
              dialog.execute_script("if(window.showFooterStatus){window.showFooterStatus(#{("Đã sao lưu: #{File.basename(path)}").to_json}, false);}")
            end
          end
        rescue => e
          dialog.execute_script("if(window.showFooterStatus){window.showFooterStatus(#{e.message.to_json}, true);}")
        end

        dialog.add_action_callback('restore_config_backup') do |_c|
          if ensure_settings_facade
            path = UI.openpanel('Phục hồi MH Config từ XLSX', nil, 'Excel|*.xlsx||')
            if path && File.file?(path)
              preview = MH::Settings.import_backup_preview(path)
              unless preview[:ok]
                dialog.execute_script("if(window.showFooterStatus){window.showFooterStatus(#{preview[:error].to_s.to_json}, true);}")
                next
              end
              rows = Array(preview[:sheets]).map { |s| "#{s['sheet']}: #{s['rows']} dòng" }.join("\n")
              if UI.messagebox("Phục hồi config từ:\n#{path}\n\n#{rows}\n\nTiếp tục?", MB_YESNO) == IDYES
                result = MH::Settings.restore_backup_xlsx(path, scopes: [:global, :project])
                if result[:ok]
                  dialog.execute_script("if(window.showFooterStatus){window.showFooterStatus('Đã phục hồi config từ XLSX.', false);}")
                else
                  dialog.execute_script("if(window.showFooterStatus){window.showFooterStatus(#{result[:error].to_s.to_json}, true);}")
                end
              end
            end
          end
        rescue => e
          dialog.execute_script("if(window.showFooterStatus){window.showFooterStatus(#{e.message.to_json}, true);}")
        end

        # Registry iframe dùng sketchup-bridge, nên callback Registry được gắn
        # lên chính Control Panel dialog.
        attach_registry_bridge(dialog)

        # --- PK Addon settings nhúng nhẹ ---
        dialog.add_action_callback('load_pk_settings') do |_c|
          dialog.execute_script("if(window.loadPkSettings){window.loadPkSettings(#{pk_settings_data.to_json});}")
        end
        dialog.add_action_callback('choose_pk_library') do |_c|
          path = UI.openpanel('Chọn thư viện phụ kiện', nil, 'Excel/CSV|*.xlsx;*.xls;*.csv||')
          data = pk_settings_data
          data['path'] = path.to_s if path
          data['library_exists'] = !data['path'].to_s.empty? && File.file?(data['path'].to_s)
          if ensure_pk_loaded
            data['library_count'] = ::MH_PK_Addon.accessory_names_from_file(data['path']).length
          end
          dialog.execute_script("if(window.loadPkSettings){window.loadPkSettings(#{data.to_json});}")
        end
        dialog.add_action_callback('save_pk_settings') do |_c, payload_json|
          payload = JSON.parse(payload_json.to_s) rescue {}
          if ensure_pk_loaded && payload.is_a?(Hash)
            path = payload['path'].to_s.strip
            shape = payload['shape'].to_s.strip.downcase
            size_mm = payload['size_mm'].to_f
            face_mode = payload['face_mode'].to_s
            if !path.empty? && !File.file?(path)
              dialog.execute_script("if(window.showPkSettingsStatus){window.showPkSettingsStatus('Đường dẫn thư viện không tồn tại.', true);}")
            else
              settings_write('pk_addon', 'library_path', path, :global)
              settings_write('pk_addon', 'shape', shape, :global)
              settings_write('pk_addon', 'size_mm', size_mm, :global)
              settings_write('pk_addon', 'face_mode', face_mode, :global)
              data = pk_settings_data
              data['message'] = 'Đã lưu cài đặt PK Addon.'
              dialog.execute_script("if(window.loadPkSettings){window.loadPkSettings(#{data.to_json});}")
            end
          end
        rescue => e
          dialog.execute_script("if(window.showPkSettingsStatus){window.showPkSettingsStatus(#{e.message.to_json}, true);}")
        end

        # --- Fast Rename settings nhúng ---
        dialog.add_action_callback('load_fast_rename_settings') do |_c|
          push_fast_rename_settings(dialog)
        end
        dialog.add_action_callback('save_fast_rename_settings') do |_c, payload_json|
          payload = JSON.parse(payload_json.to_s) rescue {}
          if save_fast_rename_settings_payload(payload)
            refresh_fast_rename_tool
            push_fast_rename_settings(dialog, 'Đã lưu cài đặt Fast Rename.')
          else
            push_fast_rename_settings(dialog, 'Không lưu được cài đặt Fast Rename.', true)
          end
        rescue => e
          push_fast_rename_settings(dialog, e.message, true)
        end

        # --- Thongke panel: settings nhẹ + launcher điều khiển ---
        dialog.add_action_callback('load_thongke_panel') do |_c|
          push_thongke_panel(dialog)
        end
        dialog.add_action_callback('save_thongke_hidden') do |_c, payload_json|
          payload = JSON.parse(payload_json.to_s) rescue {}
          if ensure_thongke_loaded && payload.is_a?(Hash)
            names = payload['hidden_list'].to_s.split(/\r?\n/).map(&:strip).reject(&:empty?)
            names = ::MH_Thongke.normalize_hidden_names(names) if ::MH_Thongke.respond_to?(:normalize_hidden_names)
            ::MH_Thongke.hidden_list = names if ::MH_Thongke.respond_to?(:hidden_list=)
            ::MH_Thongke.instance_variable_set(:@hidden_list, names)
            ::MH_Thongke.instance_variable_set(:@hidden_name_set_sig, nil)
            ::MH_Thongke.hidden_items_invalidate_caches if ::MH_Thongke.respond_to?(:hidden_items_invalidate_caches)
            ::MH_Thongke.save_preferences if ::MH_Thongke.respond_to?(:save_preferences)
            settings_write('thongke', 'hidden_list', names, :project)
            ::MH_Thongke.update_html(false) if ::MH_Thongke.respond_to?(:update_html) && ::MH_Thongke.respond_to?(:main_dialog_visible?) && ::MH_Thongke.main_dialog_visible?
            push_thongke_panel(dialog, 'Đã lưu danh sách ẩn.')
          end
        rescue => e
          push_thongke_panel(dialog, e.message, true)
        end
        dialog.add_action_callback('thongke_action') do |_c, action|
          if ensure_thongke_loaded
            case action.to_s
            when 'main'
              ::MH_Thongke.process_selection if ::MH_Thongke.respond_to?(:process_selection)
              ::MH_Thongke.show_dialog if ::MH_Thongke.respond_to?(:show_dialog)
            when 'mini'
              ::MH_Thongke.force_show_import_mini_dialog if ::MH_Thongke.respond_to?(:force_show_import_mini_dialog)
            when 'mini_reset'
              ::MH_Thongke.reset_import_mini_dialog_position if ::MH_Thongke.respond_to?(:reset_import_mini_dialog_position)
              ::MH_Thongke.force_show_import_mini_dialog(nil, true) if ::MH_Thongke.respond_to?(:force_show_import_mini_dialog)
            when 'material_hud'
              ::MH_Thongke.show_import_material_hud if ::MH_Thongke.respond_to?(:show_import_material_hud)
            when 'info_hud'
              ::MH_Thongke.toggle_info_hud if ::MH_Thongke.respond_to?(:toggle_info_hud)
            when 'reload_excel'
              if ::MH_Thongke.respond_to?(:main_dialog_refresh_excel_data)
                ::MH_Thongke.main_dialog_refresh_excel_data
              elsif ::MH_Thongke.respond_to?(:load_import_excel_snapshot_only)
                ::MH_Thongke.load_import_excel_snapshot_only
              end
            end
            push_thongke_panel(dialog)
          end
        rescue => e
          push_thongke_panel(dialog, e.message, true)
        end

        # --- Assemble settings nhúng nhẹ ---
        dialog.add_action_callback('load_assemble_panel') do |_c|
          push_assemble_panel(dialog)
        end
        dialog.add_action_callback('load_assemble_model_names') do |_c|
          dialog.execute_script("if(window.loadAssembleModelNames){window.loadAssembleModelNames(#{assemble_model_names.to_json});}")
        end
        dialog.add_action_callback('save_assemble_settings') do |_c, payload_json|
          payload = JSON.parse(payload_json.to_s) rescue {}
          if ensure_assemble_loaded && payload.is_a?(Hash)
            cfg = MH::Assemble.config
            (cfg['profiles'] ||= {})['no_door'] ||= { 'label' => 'Không cánh', 'hide' => [] }
            cfg['profiles']['no_door']['hide'] = Array(payload['no_door_module']).map(&:to_s)
            cfg['no_door_scope'] = {
              'product' => Array(payload['no_door_product']).map(&:to_s),
              'module' => Array(payload['no_door_module']).map(&:to_s)
            }
            cfg['hide_common'] = Array(payload['hide_common']).map(&:to_s) if payload.key?('hide_common')
            cfg['hidden_tags'] = Array(payload['hidden_tags']).map(&:to_s) if payload.key?('hidden_tags')
            cfg['no_number'] = Array(payload['no_number']).map(&:to_s) if payload.key?('no_number')
            ratio = payload['draw_ratio'].to_s
            cfg['draw_ratio'] = ratio == 'auto' ? 'auto' : ratio.to_i
            ratios = Array(payload['draw_ratios']).map(&:to_i).select { |n| n.between?(1, 1000) }.uniq
            cfg['draw_ratios'] = ratios.empty? ? [5, 10, 15, 20, 25, 50, 100] : ratios
            cfg['sub_modules'] = Array(payload['sub_modules']).map do |row|
              next unless row.is_a?(Hash)
              key = row['key'].to_s.strip
              label = row['label'].to_s.strip
              next if key.empty? || label.empty?
              { 'key' => key, 'label' => label, 'enabled' => row.key?('enabled') ? !!row['enabled'] : true }
            end.compact
            if MH::Assemble.instance_variable_defined?(:@config)
              MH::Assemble.instance_variable_set(:@config, cfg)
            end
            MH::Assemble.save_config
            settings_write('assemble', 'draw_ratio', cfg['draw_ratio'], :global)
            settings_write('assemble', 'draw_ratios', cfg['draw_ratios'], :global)
            settings_write('assemble', 'no_door_scope', cfg['no_door_scope'], :project)
            settings_write('assemble', 'hide_common', cfg['hide_common'], :project)
            settings_write('assemble', 'hidden_tags', cfg['hidden_tags'], :project)
            settings_write('assemble', 'no_number', cfg['no_number'], :project)
            settings_write('assemble', 'sub_modules', cfg['sub_modules'], :project)
            push_assemble_panel(dialog, 'Đã lưu cài đặt Assemble.')
          end
        rescue => e
          push_assemble_panel(dialog, e.message, true)
        end

        # --- Select Similar settings nhúng nhẹ ---
        dialog.add_action_callback('load_select_similar_panel') do |_c|
          push_select_similar_panel(dialog)
        end
        dialog.add_action_callback('save_select_similar_settings') do |_c, payload_json|
          payload = JSON.parse(payload_json.to_s) rescue {}
          if ensure_select_similar_loaded && payload.is_a?(Hash)
            save_select_similar_quick_search_items(payload['quick_search_items']) if payload.key?('quick_search_items')
            settings = MH::SelectSimilar.settings.dup
            {
              partial_name: :bool,
              name_group: :bool,
              bounding_size: :bool,
              bounding_volume: :bool,
              min_thickness: :bool,
              same_material: :bool,
              same_tag: :bool,
              name_search: :string,
              type_filter: :string,
              scope_filter: :string,
              nesting_filter: :string,
              key_isolate: :upcase,
              key_settings: :upcase,
              size_tolerance: :float,
              volume_tolerance: :float,
              thickness_tolerance: :float,
              min_size_threshold: :int,
              min_all_size_threshold: :int
            }.each do |key, type|
              next unless payload.key?(key.to_s)
              value = payload[key.to_s]
              settings[key] = case type
                              when :bool then !!value
                              when :float then value.to_f
                              when :int then value.to_i
                              when :upcase then value.to_s.upcase
                              else value.to_s
                              end
            end
            if MH::SelectSimilar.respond_to?(:apply_settings)
              MH::SelectSimilar.apply_settings(settings, persist: false)
            else
              MH::SelectSimilar.instance_variable_set(:@settings, settings)
            end
            settings.each { |key, value| settings_write('select_similar', key.to_s, value, :global) }
            push_select_similar_panel(dialog, 'Đã lưu cài đặt Select Similar.')
          end
        rescue => e
          push_select_similar_panel(dialog, e.message, true)
        end

        # --- Rename / Viewport Names settings nhúng nhẹ ---
        dialog.add_action_callback('load_viewport_names_panel') do |_c|
          push_viewport_names_panel(dialog)
        end
        dialog.add_action_callback('save_viewport_names_settings') do |_c, payload_json|
          payload = JSON.parse(payload_json.to_s) rescue {}
          if payload.is_a?(Hash)
            payload['hidden_layers'] = Array(payload['hidden_layers']).map(&:to_s).map(&:strip).reject(&:empty?) if payload.key?('hidden_layers')
            %w[
              line_spacing text_gap text_display_mode show_hidden_lines label_style
              show_part_id show_part_prefix show_part_suffix show_label_bg hidden_layers
            ].each do |setting_key|
              settings_write('viewport_names', setting_key, payload[setting_key], :global) if payload.key?(setting_key)
            end
            Sketchup.active_model.rendering_options['DrawBackEdges'] = !!payload['show_hidden_lines'] if payload.key?('show_hidden_lines')
            refresh_viewport_names_tool
            push_viewport_names_panel(dialog, 'Đã lưu cài đặt Viewport Names.')
          end
        rescue => e
          push_viewport_names_panel(dialog, e.message, true)
        end

        # --- Settings nhúng (MH::Panel::Settings) ---
        dialog.add_action_callback('load_settings') do |_c|
          s = panel_settings
          data = s ? s.load_all_settings : {}
          data['cai_dat'] ||= {}
          data['cai_dat'].merge!(s.read_startup) if s
          dialog.execute_script("if(window.loadAllSettings){window.loadAllSettings(#{data.to_json});}")
        end

        dialog.add_action_callback('save_setting') do |_c, params|
          s = panel_settings
          if s
            section, key, value_str = params.to_s.split('@', 3)
            value = s.parse_value(value_str)
            if section == 'cai_dat' && MH::Panel::Settings::STARTUP_KEYS.include?(key)
              s.write_startup(key, value)
            else
              s.write(key, value, section)
            end
            refresh_active_tool
          end
        end

        dialog.add_action_callback('load_presets') do |_c, section|
          push_presets(dialog, section.to_s)
        end
        dialog.add_action_callback('save_preset') do |_c, params|
          s = panel_settings
          if s
            section, name, json = params.to_s.split('@', 3)
            s.save_preset(section, name, JSON.parse(json))
            push_presets(dialog, section)
            refresh_active_tool
          end
        end
        dialog.add_action_callback('delete_preset') do |_c, params|
          s = panel_settings
          if s
            section, name = params.to_s.split('@', 2)
            s.delete_preset(section, name)
            push_presets(dialog, section)
            refresh_active_tool
          end
        end
        dialog.add_action_callback('load_preset') do |_c, params|
          s = panel_settings
          if s
            section, name = params.to_s.split('@', 2)
            settings = s.load_preset(section, name)
            if settings
              dialog.execute_script("if(window.sendSettingsToIframeData){window.sendSettingsToIframeData('#{section}', #{settings.to_json});}")
            end
          end
        end
        dialog.add_action_callback('save_presets_order') do |_c, params|
          s = panel_settings
          if s
            section, json = params.to_s.split('@', 2)
            data = s.read_all
            data[section] ||= {}
            data[section]['presets'] = JSON.parse(json)
            s.write_all(data)
          end
        end
        dialog.add_action_callback('save_collapsed_groups') do |_c, params|
          s = panel_settings
          if s
            section, json = params.to_s.split('@', 2)
            data = s.read_all
            data[section] ||= {}
            data[section]['collapsed_groups'] = JSON.parse(json)
            s.write_all(data)
          end
        end

        # --- Sao lưu / phục hồi / reset ---
        dialog.add_action_callback('export_settings') do |_c|
          s = panel_settings
          if s
            path = UI.savepanel('Sao lưu cài đặt MH Panel', nil, 'mh_panel_settings.json')
            if path
              path += '.json' unless path.downcase.end_with?('.json')
              FileUtils.cp(MH::Panel::Settings::SETTINGS_FILE, path) rescue nil
            end
          end
        end
        dialog.add_action_callback('import_settings') do |_c|
          s = panel_settings
          if s
            path = UI.openpanel('Phục hồi cài đặt MH Panel', nil, 'JSON Files|*.json||')
            if path && File.exist?(path)
              FileUtils.cp(path, MH::Panel::Settings::SETTINGS_FILE) rescue nil
              dialog.execute_script("location.reload();")
            end
          end
        end
        dialog.add_action_callback('reset_settings') do |_c|
          s = panel_settings
          if s && UI.messagebox('Đặt lại toàn bộ cài đặt MH Panel về mặc định?', MB_YESNO) == IDYES
            s.write_all({})
            refresh_active_tool
            dialog.execute_script("location.reload();")
          end
        end
        dialog.add_action_callback('reset_section') do |_c, section|
          s = panel_settings
          if s
            data = s.read_all
            data.delete(section.to_s)
            s.write_all(data)
            refresh_active_tool
            dialog.execute_script("location.reload();")
          end
        end
      end
    end
  end
end

# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require File.join(Sketchup.find_support_file('Plugins'), 'MH_shared.rb')
raise "[MH_Rename] requires MH_shared" unless defined?(MH::Shared) && defined?(MH::ModelHub)
require File.join(__dir__, 'name_parser.rb')
require File.join(__dir__, 'viewport_name.rb')

module MH
  module Rename

    # =========================================================================
    # CONSTANTS
    # =========================================================================
    PREFS_KEY    = 'MH_Rename'.freeze
    SYS_PFX_RE   = /^(_+\d+)\.?\s*/
    DEBUG        = false

    # =========================================================================
    # SETTINGS
    # =========================================================================
    @settings = { min_size_threshold: 0 }

    @prefix_suggestions = []
    @modul_suggestions  = ['Tấm Đứng', 'Tấm Ngang', 'Vách', 'Kệ', 'Ngăn Kéo', 'Cửa']
    @suffix_suggestions = %w[_L _R _A _B _Top _Bot _NEW]

    @shortcut_map = {}
    @sub_prefix_suggestions = []
    @name_separators = {}

    class << self
      attr_accessor :prefix_suggestions, :modul_suggestions, :suffix_suggestions, :shortcut_map,
                    :sub_prefix_suggestions, :name_separators

      def dbg(msg)
        puts msg if DEBUG
      end

      def module_suggestions
        @modul_suggestions
      end

      def module_suggestions=(values)
        @modul_suggestions = values
      end

      def save_settings
        @settings.each { |k, v| Sketchup.write_default(PREFS_KEY, k.to_s, v) }
      end

      def load_settings
        @settings.each_key do |k|
          v = Sketchup.read_default(PREFS_KEY, k.to_s, nil)
          @settings[k] = v.to_i if v
        end
      end

      # Đọc config từ MH_Registry Config.xlsx (primary)
      # Fallback: MH_Rename/Config.xlsx (legacy pure-Ruby xlsx)
      def auto_load_suggestions
        @shortcut_map = {}

        # --- Primary: MH_Registry Config.xlsx ---
        if defined?(MH::RegistryApp) && MH::RegistryApp.respond_to?(:load_config)
          begin
            data = MH::RegistryApp.load_config
            @prefix_suggestions     = data['prefix'] || []
            @modul_suggestions      = data['modul'] || []
            @sub_prefix_suggestions = data['sub_prefix'] || []
            @name_separators        = data['separators'] || {}
            @all_prefix     = data['all_prefix'] || @prefix_suggestions
            @all_modul      = data['all_modul'] || @modul_suggestions
            @all_sub_prefix = data['all_sub_prefix'] || @sub_prefix_suggestions

            @suffix_suggestions = []
            (data['suffix'] || []).each do |s|
              if s.is_a?(Hash)
                val = s['value'].to_s
                sc  = s['shortcut']
                next if val.empty?
                @suffix_suggestions << val
                @shortcut_map[sc.to_s] = val if sc && sc.to_i > 0
              else
                @suffix_suggestions << s.to_s unless s.to_s.empty?
              end
            end

            dbg "[MH_Rename] Config loaded from MH_Registry"
            return
          rescue => e
            dbg "[MH_Rename] MH_Registry load failed: #{e.message}, falling back to Excel"
          end
        end

        # --- Fallback: MH_Rename/Config.xlsx (legacy xlsx) ---
        load_from_legacy_excel
      end

      def load_from_legacy_excel
        base_dir = Sketchup.find_support_file("Plugins")
        mh_rename_dir = File.join(base_dir, "MH_Rename")
        Dir.mkdir(mh_rename_dir) unless Dir.exist?(mh_rename_dir)
        xlsx_path = File.join(mh_rename_dir, "Config.xlsx")

        begin
          unless File.exist?(xlsx_path)
            MH::ExcelBridge.write(
              xlsx_path,
              sheets: {
                'prefix' => [],
                'suffix' => %w[_L _R _A _B _Top _Bot _NEW].map { |v| [v] },
                'modul' => ['Tấm Đứng', 'Tấm Ngang', 'Vách', 'Kệ', 'Ngăn Kéo', 'Cửa'].map { |v| [v] }
              }
            )
          end

          sheets = MH::ExcelBridge.read_all(xlsx_path)
          suffix_rows = sheets['suffix'] || []
          modul_rows = sheets['modul'] || []

          @prefix_suggestions = []

          unless suffix_rows.empty?
            @suffix_suggestions = []
            suffix_rows.each do |row|
              cells = Array(row)
              val = cells[0].to_s.strip
              shortcut = cells[1].to_s.strip.to_i rescue 0
              next if val.empty?
              @suffix_suggestions << val
              @shortcut_map[shortcut.to_s] = val if shortcut > 0
            end
          end

          @modul_suggestions = modul_rows.map { |r| Array(r)[0].to_s.strip }.reject(&:empty?) unless modul_rows.empty?
          dbg "[MH_Rename] Config loaded from legacy ExcelBridge"
        rescue => e
          dbg "[MH_Rename] Error loading ExcelBridge: #{e.message}"
        end
      end
    end

    # =========================================================================
    # HELPERS
    # =========================================================================

    # Remove SketchUp internal ID prefix e.g. "_956. "
    def self.clean_name(raw)
      NameParser.strip_sys_prefix(raw)
    end

    def self.strip_leading_module_tokens(text)
      value = text.to_s.strip
      separators = ['_', '.', '-', ' ']
      if defined?(MH::NameGrammar)
        separators << MH::NameGrammar.module_separator.to_s if MH::NameGrammar.respond_to?(:module_separator)
        separators << MH::NameGrammar.part_separator.to_s if MH::NameGrammar.respond_to?(:part_separator)
      end
      sep_class = Regexp.escape(separators.reject(&:empty?).uniq.join)

      loop do
        next_value = value.sub(/\A(?:MD)?\d+[\s#{sep_class}]+/i, '')
        break if next_value == value
        value = next_value.strip
      end
      value
    end

    def self.strip_product_module_prefix(raw)
      clean = clean_name(raw).to_s.strip
      if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:parse)
        parsed = MH::NameGrammar.parse(clean)
        return strip_leading_module_tokens(parsed[:part].to_s) if parsed && parsed[:recognized]
      end

      if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:first_product)
        code = MH::NameGrammar.first_product(clean).to_s
        unless code.empty?
          clean = clean.sub(/\A#{Regexp.escape(code)}[\s._-]*/i, '')
          return strip_leading_module_tokens(clean)
        end
      end

      extracted = NameParser.extract_prefix(clean, @prefix_suggestions)
      strip_leading_module_tokens(extracted[:remaining].to_s)
    rescue
      clean_name(raw).to_s.strip
    end

    # Extract system prefix to re-attach after rename
    def self.sys_prefix(raw)
      NameParser.sys_prefix(raw)
    end

    # Serialize one entity to a data hash for the dialog
    def self.entity_data(entity, unique_part = '')
      raw  = entity.respond_to?(:name) ? entity.name : ''
      tag  = entity.respond_to?(:layer)    && entity.layer     ? entity.layer.name    : 'Untagged'
      mat  = entity.respond_to?(:material) && entity.material  ? entity.material.name : 'Default'
      { id: entity.entityID, name: clean_name(raw), tag: tag, material: mat,
        unique_part: unique_part }
    end

    # Find entities in model by IDs quickly using a Hash lookup
    def self.entities_by_id(model)
      map = {}
      source = MH::ModelHub.scan(root: model.active_entities, types: %i[group component], depth: 1, include_hidden: true)
      source.each do |e|
        map[e.entityID] = e if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      end
      map
    end

    # =========================================================================
    # NAME TEMPLATE  (keyed by entityID — never mixes up order)
    # =========================================================================
    # Returns { template:, unique_parts_by_id: { entityID => String } }
    def self.name_template(entities)
      by_id = {}
      entities.each do |e|
        by_id[e.entityID] = clean_name(entity_raw_name(e))
      end
      names = by_id.values

      return empty_template(entities) if names.all?(&:empty?)

      if names.uniq.length == 1
        return { template: names.first, unique_parts_by_id: entities.each_with_object({}) { |e, h| h[e.entityID] = '' } }
      end

      pfx = common_prefix(names)
      names_no_pfx = names.map { |n| n[pfx.length..-1] }
      sfx = common_suffix(names_no_pfx)
      
      if pfx.empty? && sfx.empty?
        template = '[original name]'
        unique = by_id
      else
        template = pfx + '[original name]' + sfx
        unique = {}
        by_id.each { |id, n| unique[id] = n[pfx.length..-(sfx.length + 1)] }
      end

      { template: template, unique_parts_by_id: unique }
    end

    def self.entity_raw_name(e)
      e.respond_to?(:name) ? e.name : e.definition.name
    end

    def self.registry_values(*sources)
      sources.flat_map do |source|
        values = source.is_a?(Symbol) ? instance_variable_get(source) : source
        Array(values)
      end.compact.map(&:to_s).map(&:strip).reject(&:empty?).uniq
    end

    def self.separator_value(key, fallback)
      value = (name_separators || {})[key].to_s
      value.empty? ? fallback : value
    end

    def self.name_module_separator
      defined?(MH::NameGrammar) ? MH::NameGrammar.module_separator : separator_value('sep_prefix', '.')
    end

    def self.name_part_separator
      defined?(MH::NameGrammar) ? MH::NameGrammar.part_separator : separator_value('sep_suffix', '_')
    end

    def self.strip_registry_suffix(clean)
      text = clean.to_s
      suffixes = registry_values(@suffix_suggestions).sort_by { |s| -s.length }
      separators = [
        separator_value('sep_suffix', '_'),
        separator_value('sep_prefix', '_'),
        '_', '-', '.', ' '
      ].uniq

      suffixes.each do |suffix|
        return '' if text.casecmp?(suffix)

        separators.each do |sep|
          token = "#{sep}#{suffix}"
          next if sep.empty? || text.length <= token.length
          return text[0...-token.length] if text.downcase.end_with?(token.downcase)
        end

        if suffix.match?(/\A[.\-_\s]/) && text.downcase.end_with?(suffix.downcase)
          return text[0...-suffix.length]
        end
      end

      text
    end

    def self.registry_head_has_module?(head)
      modules = registry_values(:@all_modul, @modul_suggestions).sort_by { |m| -m.length }
      sep_prefix = separator_value('sep_prefix', '_')
      modules.any? do |mod|
        head.casecmp?(mod) ||
          head.downcase.end_with?("#{sep_prefix}#{mod}".downcase) ||
          head.downcase.end_with?("_#{mod}".downcase) ||
          head.downcase.end_with?("-#{mod}".downcase) ||
          head.downcase.end_with?(".#{mod}".downcase)
      end
    end

    def self.shortcut_rename_name(raw_name, new_suffix)
      sys = sys_prefix(raw_name)
      suffix = new_suffix.to_s.strip
      clean = clean_name(raw_name).to_s.strip
      head = strip_registry_suffix(clean).to_s.sub(/[.\-_\s]+\z/, '')
      return sys + suffix if head.empty?

      return sys + head + suffix if suffix.match?(/\A[.\-_\s]/)

      sys + head + name_part_separator + suffix
    end

    def self.normalize_quick_prefix_value(value)
      text = value.to_s.strip
      text = text.sub(/[.\-_\s]+\z/, '')
      return '' if text.empty?

      dpfx = quick_prefix_product_family

      if text =~ /\A(\d+[A-Za-z]?)(?:#{Regexp.escape(name_module_separator)}([A-Za-z0-9]+))?\z/i ||
         text =~ /\A(\d+[A-Za-z]?)(?:\.([A-Za-z0-9]+))?\z/i
        product_no = $1.to_s
        mod = $2.to_s
        product_no = "0#{product_no}" if product_no =~ /\A\d[A-Za-z]?\z/
        code = "#{dpfx}#{product_no}"
        code += "#{name_module_separator}#{mod}" unless mod.empty?
        return code
      end

      text
    end

    def self.quick_prefix_product_family
      if defined?(MH::NameGrammar)
        if MH::NameGrammar.respond_to?(:product_families)
          family = Array(MH::NameGrammar.product_families(active: true)).map(&:to_s).map(&:strip).find { |v| v =~ /\A[A-Za-z]+\z/ }
          return family.upcase if family && !family.empty?
        end
        family = Array(MH::NameGrammar.prefixes(active: true)).map(&:to_s).map(&:strip).find { |v| v =~ /\A[A-Za-z]+\z/ }
        return family.upcase if family && !family.empty?
        default = MH::NameGrammar.default_prefix.to_s.strip
        return default.upcase unless default.empty?
      end
      separator_value('default_prefix', 'SP').to_s.strip.upcase
    end

    def self.quick_prefix_parts(value)
      code = normalize_quick_prefix_value(value)
      return nil if code.empty?

      probe = "#{code}#{name_part_separator}__PART__"
      parsed = defined?(MH::NameGrammar) ? MH::NameGrammar.parse(probe) : nil
      if parsed && parsed[:recognized]
        return {
          product: parsed[:product],
          module_raw: parsed[:module_raw],
          code: parsed[:module_code]
        }
      end

      { product: code, module_raw: nil, code: code }
    end

    def self.quick_prefix_part_from_name(raw_name)
      clean = clean_name(raw_name).to_s.strip
      parsed = defined?(MH::NameGrammar) ? MH::NameGrammar.parse(clean) : nil
      return parsed[:part].to_s if parsed && parsed[:recognized]

      legacy = NameParser.parse_name(raw_name, prefixes: @prefix_suggestions)
      legacy[:core].to_s.strip
    rescue
      clean_name(raw_name).to_s.strip
    end

    def self.quick_prefix_name(raw_name, value)
      parts = quick_prefix_parts(value)
      return '' unless parts

      part = quick_prefix_part_from_name(raw_name)
      if defined?(MH::NameGrammar)
        sys = NameParser.sys_token(raw_name).to_s
        sys_id = sys[/\d+/]
        built = MH::NameGrammar.build_name(
          product: parts[:product],
          module_raw: parts[:module_raw],
          part: part,
          sys_id: sys_id
        )
        return built.sub(/\A__#{Regexp.escape(sys_id.to_s)}\. /, sys_prefix(raw_name)) if sys_id

        built
      else
        code = parts[:code].to_s
        part.empty? ? code : "#{code}#{name_part_separator}#{part}"
      end
    end

    def self.apply_shortcut_suffix(entities, new_suffix)
      model = Sketchup.active_model
      valid_entities = Array(entities).compact.select { |e| e.valid? && (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) }
      return { renamed: 0, skipped: 0 } if valid_entities.empty?

      model.start_operation('Rename Shortcut', true)
      renamed_count = 0
      valid_entities.each do |entity|
        final_name = shortcut_rename_name(entity_raw_name(entity), new_suffix)
        next if final_name.empty?
        entity.name = final_name
        renamed_count += 1
      end
      model.commit_operation

      { renamed: renamed_count, skipped: valid_entities.length - renamed_count }
    rescue => e
      model.abort_operation rescue nil
      dbg "Rename shortcut error: #{e.message}"
      { renamed: 0, skipped: valid_entities.length }
    end

    def self.empty_template(entities)
      { template: '[original name]',
        unique_parts_by_id: entities.each_with_object({}) { |e, h| h[e.entityID] = '' } }
    end

    def self.common_prefix(names)
      shortest = names.min_by(&:length)
      prefix   = ''
      shortest.each_char.with_index do |c, i|
        break unless names.all? { |n| n[i]&.downcase == c.downcase }
        prefix += shortest[i]
      end
      prefix
    end

    def self.common_suffix(names)
      # names already have the common prefix removed
      shortest = names.min_by(&:length)
      return '' if shortest.empty?
      suffix = ''
      shortest.reverse.each_char.with_index do |c, i|
        pos = i + 1
        break unless names.all? { |n| n.length >= pos && n[-pos]&.downcase == c.downcase }
        suffix = shortest[-pos] + suffix
      end
      suffix
    end

    # =========================================================================
    # HIGHLIGHT TOOL  (2D bounding box drawn over viewport, no real geometry)
    # =========================================================================
    class HighlightTool
      COLOR = Sketchup::Color.new(255, 220, 50)
      EDGES = [[0,1],[1,2],[2,3],[3,0], [4,5],[5,6],[6,7],[7,4],
               [0,4],[1,5],[2,6],[3,7]].freeze

      def initialize;  @pts = nil; end

      def set(entity)
        if entity&.valid?
          b = entity.bounds; mn = b.min; mx = b.max
          @pts = [
            Geom::Point3d.new(mn.x,mn.y,mn.z), Geom::Point3d.new(mx.x,mn.y,mn.z),
            Geom::Point3d.new(mx.x,mx.y,mn.z), Geom::Point3d.new(mn.x,mx.y,mn.z),
            Geom::Point3d.new(mn.x,mn.y,mx.z), Geom::Point3d.new(mx.x,mn.y,mx.z),
            Geom::Point3d.new(mx.x,mx.y,mx.z), Geom::Point3d.new(mn.x,mx.y,mx.z)
          ]
        else
          @pts = nil
        end
        Sketchup.active_model.active_view.invalidate
      end

      def clear; @pts = nil; Sketchup.active_model.active_view.invalidate; end

      def draw(view)
        return unless @pts
        s = @pts.map { |p| view.screen_coords(p) }
        view.line_stipple = '-'
        view.line_width   = 3
        view.drawing_color = COLOR
        EDGES.each { |a, b| view.draw2d(GL_LINES, [s[a], s[b]]) }
      end

      def deactivate(view); view.invalidate; end
      def suspend(view);    view.invalidate; end
      def resume(view)
        view.invalidate
        d = MH::Rename.instance_variable_get(:@dialog)
        d.bring_to_front if d&.visible?
      end
      def getExtents
        bb = Geom::BoundingBox.new
        @pts&.each { |p| bb.add(p) }
        bb
      end
    end

    @hl_tool = nil
    def self.hl_tool; @hl_tool ||= HighlightTool.new; end

    # =========================================================================
    # RENAME SHORTCUT TOOL (multi-digit: 1-999)
    # =========================================================================
    class RenameShortcutTool
      SHIFT_FLAG = 0x0004
      DIGIT_TIMEOUT = 0.7  # giây - thời gian chờ giữa các lần nhấn số

      def initialize
        @shortcut_map = MH::Rename.shortcut_map
        @prefix_list = MH::Rename.prefix_suggestions
        @buffer = ""
        @buffer_timer = nil
        @last_applied = nil
      end

      def activate
        @model = Sketchup.active_model
        @selection = @model.selection
        @buffer = ""
        @last_applied = nil
        update_status
        @model.active_view.invalidate
      end

      def deactivate(view)
        UI.stop_timer(@buffer_timer) if @buffer_timer
        @buffer_timer = nil
        @buffer = ""
        view.invalidate
      end

      def onLButtonDown(flags, x, y, view)
        ph = view.pick_helper
        ph.do_pick(x, y)
        
        entity = nil
        path = ph.path_at(0)
        if path
          entity = path.find { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
        end
        
        shift = (flags & SHIFT_FLAG) != 0
        if entity
          @selection.clear unless shift
          @selection.add(entity)
        else
          @selection.clear unless shift
        end
        view.invalidate
      end

      def onKeyUp(key, repeat, flags, view)
        # Phím số 0-9 (key 48-57)
        if key >= 48 && key <= 57
          digit = (key - 48).to_s
          
          # Không cho phép bắt đầu bằng 0
          return false if digit == "0" && @buffer.empty?
          
          @buffer += digit
          
          # Hủy timer cũ nếu có
          UI.stop_timer(@buffer_timer) if @buffer_timer
          
          # Đặt timer mới - sau DIGIT_TIMEOUT giây sẽ áp dụng
          @buffer_timer = UI.start_timer(DIGIT_TIMEOUT, false) do
            @buffer_timer = nil
            try_apply_buffer(view)
          end
          
          Sketchup.status_text = "Đang nhập: #{@buffer}_ (chờ #{DIGIT_TIMEOUT}s...)"
          view.invalidate
          return true
        end
        
        false
      end

      def try_apply_buffer(view)
        return if @buffer.empty?
        
        code = @buffer
        @buffer = ""
        
        suffix = @shortcut_map[code]
        if suffix
          apply_suffix(suffix, code)
        else
          Sketchup.status_text = "Không tìm thấy shortcut: #{code}"
          @last_applied = "✗ #{code}"
        end
        view.invalidate
      end
      def apply_suffix(new_suffix, code = "")
        entities = @selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
        if entities.empty?
          Sketchup.status_text = "Vui long click chon doi tuong truoc."
          @last_applied = "x Chua chon obj"
          return
        end

        result = MH::Rename.apply_shortcut_suffix(entities, new_suffix)
        renamed_count = result[:renamed]
        skipped_count = result[:skipped]
        @last_applied = "OK [#{code}] #{new_suffix} (#{renamed_count} obj, skip #{skipped_count})"
        Sketchup.status_text = "Doi suffix theo Registry: #{renamed_count} obj | Bo qua: #{skipped_count}"
        @model.active_view.invalidate
      end
      def update_status
        map_str = @shortcut_map.sort_by { |k, _| k.to_i }.map { |k, v| "#{k}:#{v}" }.join(", ")
        Sketchup.status_text = "Rename Shortcut: Click chọn, nhấn số để đổi tên. { #{map_str} }"
      end

      def draw(view)
        y = 40
        
        # Hiện buffer nếu đang nhập
        if !@buffer.empty?
          view.draw_text([20, y, 0], "Đang nhập: #{@buffer}_ ...", color: "Black", size: 13, bold: true)
          y += 22
        end
        
        # Hiện kết quả vừa áp dụng
        if @last_applied
          view.draw_text([20, y, 0], @last_applied, color: "Black", size: 12)
          y += 22
        end
        
        y += 5
        
        # Danh sách shortcut
        @shortcut_map.sort_by { |k, _| k.to_i }.each do |k, v|
          view.draw_text([20, y, 0], "  #{k}  =>  #{v}", color: "Black")
          y += 18
        end
      end

      def onSetCursor
        UI.set_cursor(632)
      end
    end


    def self.sync_dialog_selection(dialog, sel = Sketchup.active_model.selection)
      return unless dialog&.visible?

      entities = selected_rename_entities(sel)
      tmpl     = entities.empty? ? { template: '', unique_parts_by_id: {} } : name_template(entities)
      data     = entities.map { |e| entity_data(e, tmpl[:unique_parts_by_id][e.entityID] || '') }
      dialog.execute_script(<<~JS)
        try {
          objectsData   = #{data.to_json};
          initialTmpl   = #{tmpl[:template].to_json};
          document.getElementById('new_name').value = initialTmpl;
          document.querySelector('.count').textContent = '#{entities.length} object(s)';
          rebuildTable(objectsData);
          schedPreview();
        } catch(e) { console.error(e); }
      JS
    rescue => e
      MH::Rename.dbg "SelectionObserver sync error: #{e.message}"
    end

    def self.selected_rename_entities(sel = Sketchup.active_model.selection)
      sel.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
    rescue
      []
    end

    def self.queue_dialog_selection_sync(dialog = @dialog)
      return unless dialog && (dialog.visible? rescue false)
      return if @dialog_sync_pending

      @dialog_sync_pending = true
      UI.start_timer(0.05, false) do
        @dialog_sync_pending = false
        sync_dialog_selection(dialog, Sketchup.active_model.selection)
      end
    rescue => e
      @dialog_sync_pending = false
      MH::Rename.dbg "queue dialog sync: #{e.message}"
    end

    def self.refresh_model_hub_observers(model = Sketchup.active_model)
      return false unless defined?(MH::ModelHub) && model

      MH::ModelHub.detach_from_model rescue nil
      MH::ModelHub.attach_to_model(model)
      true
    rescue => e
      MH::Rename.dbg "refresh model hub observers: #{e.message}"
      false
    end

    # =========================================================================
    # DIALOG STATE
    # =========================================================================
    @dialog   = nil
    @observer = nil
    @dialog_sync_pending = false

    # =========================================================================
    # GLOBAL OBSERVERS FOR QUICK TOOLS
    # =========================================================================

    # Neutralize zombie observers from previous script versions
    class MHToolsObserver < Sketchup::ToolsObserver
      def onActiveToolChanged(tools, tool_name, tool_id)
        # Do nothing. This kills the old observer logic that was calling deactivate_quick_tools
      end
    end

    @qp_active = false
    @qr_active = false
    @qp_dialog = nil
    @qr_dialog = nil
    @hide_timer = nil
    @skip_observer = false

    @programmatic_close_qp = false
    @programmatic_close_qr = false

    def self.close_qp_dialog
      return unless @qp_dialog
      @programmatic_close_qp = true
      @qp_dialog.close rescue nil
      @qp_dialog = nil
    end

    def self.close_qr_dialog
      return unless @qr_dialog
      @programmatic_close_qr = true
      @qr_dialog.close rescue nil
      @qr_dialog = nil
    end

    def self.deactivate_quick_tools
      UI.stop_timer(@hide_timer) if @hide_timer
      @hide_timer = nil
      @qp_active = false
      @qr_active = false
      UI.start_timer(0.01, false) do
        close_qp_dialog
        close_qr_dialog
        Sketchup.active_model.select_tool(nil) rescue nil
        @dialog.close if @dialog&.visible? rescue nil
      end
    end

    def self.attach_global_observers
      @selection_observers ||= {}
      @selection_observers[:model_hub] = MH::ModelHub.subscribe(
        :rename_quick_tools,
        on_selection: ->(_kind) { MH::Rename.on_selection_change(Sketchup.active_model.selection) },
        visible: -> { MH::Rename.instance_variable_get(:@qp_active) || MH::Rename.instance_variable_get(:@qr_active) }
      )
      true
    rescue
      nil
    end

    def self.on_selection_change(sel)
      return if @skip_observer
      
      ents = sel.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
      if @qp_active
        if ents.empty?
          @qp_dialog.execute_script("document.body.style.opacity='0.2';") if @qp_dialog && @qp_dialog.visible? rescue nil
        else
          if @qp_dialog && @qp_dialog.visible?
            @qp_dialog.execute_script("document.body.style.opacity='1';") rescue nil
            @qp_dialog.bring_to_front rescue nil
            @qp_dialog.execute_script("setTimeout(function(){var i=document.getElementById('pfx');if(i){i.value='';i.focus();}},50);") rescue nil
          end
        end
      elsif @qr_active
        if ents.empty?
          @qr_dialog.execute_script("document.body.style.opacity='0.2';") if @qr_dialog && @qr_dialog.visible? rescue nil
        else
          if @qr_dialog && @qr_dialog.visible?
            show_qr_dialog(ents)
            @qr_dialog.execute_script("document.body.style.opacity='1';") rescue nil
            @qr_dialog.bring_to_front rescue nil
            @qr_dialog.execute_script("setTimeout(function(){var i=document.getElementById('name');if(i){i.value='';i.focus();}},50);") rescue nil
          end
        end
      end
    end

    # =========================================================================
    # MAIN ENTRY
    # =========================================================================
    def self.rename_selected
      model     = Sketchup.active_model
      selection = model.selection
      entities  = selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }

      if entities.empty?
        UI.messagebox('No groups/components selected.')
        return
      end

      tmpl    = name_template(entities)
      objects = entities.map { |e| entity_data(e, tmpl[:unique_parts_by_id][e.entityID] || '') }
      tags    = model.layers.map(&:name).sort
      mats    = ['Default'] + model.materials.map(&:name).sort

      @dialog.close if @dialog&.visible?

      @dialog = UI::HtmlDialog.new(
        dialog_title:    'MH Rename',
        preferences_key: 'MH_Rename_v5',
        width: 440, height: 400,
        resizable: true,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(build_html(tmpl[:template], objects, tags, mats))

      register_callbacks(model, selection)
      refresh_model_hub_observers(model)

      @observer = MH::ModelHub.subscribe(
        :rename_dialog,
        on_selection: ->(_kind) { MH::Rename.queue_dialog_selection_sync(@dialog) },
        visible: -> { @dialog && (@dialog.visible? rescue false) }
      )

      @dialog.set_on_closed do
        MH::ModelHub.unsubscribe(:rename_dialog)
        hl_tool.clear rescue nil
      end

      @dialog.show
      @dialog.set_size(440, 400)
    end

    # =========================================================================
    # CALLBACKS
    # =========================================================================
    def self.register_callbacks(model, selection)
      # ---- apply_rename ----
      # JS sends { rows: [{id, name}] } — already computed final names, bound by entityID
      @dialog.add_action_callback('apply_rename') do |_, param|
        rows   = JSON.parse(param)['rows'] || []
        model  = Sketchup.active_model
        
        # Build map một lần, không duyệt lại
        id_map = entities_by_id(model)
        
        model.start_operation('Rename Objects', true)  # one operation for all
        rows.each do |r|
          e = id_map[r['id'].to_i]
          next unless e&.valid?
          raw = entity_raw_name(e)
          sys = sys_prefix(raw)
          new_name = r['name'].to_s
          final_name = sys + new_name
          e.name = final_name if e.name != final_name
        end
        model.commit_operation
        Sketchup.status_text = "Renamed #{rows.length} object(s)"
        queue_dialog_selection_sync
      rescue => e
        model.abort_operation rescue nil
        MH::Rename.dbg "apply_rename: #{e.message}"
      end

      # ---- clear_prefixes (Strip all prefixes from selected objects) ----
      @dialog.add_action_callback('clear_prefixes') do |_, param|
        d = JSON.parse(param)
        ids = d['ids'] || []
        model = Sketchup.active_model
        
        ents = ids.map { |id| entities_by_id(model)[id] }.compact.select(&:valid?)
        next if ents.empty?
        
        model.start_operation('Clear Prefixes', true)
        ents.each do |e|
          raw_name = e.respond_to?(:name) ? e.name : ''
          sys = sys_prefix(raw_name)
          clean = strip_product_module_prefix(raw_name)

          e.name = sys + clean
        end
        model.commit_operation
        ents  = selected_rename_entities(model.selection)
        tmpl  = name_template(ents)
        data  = ents.map { |e| entity_data(e, tmpl[:unique_parts_by_id][e.entityID] || '') }
        @dialog.execute_script(<<~JS)
          try {
            objectsData = #{data.to_json};
            initialTmpl = #{tmpl[:template].to_json};
            document.getElementById('new_name').value = initialTmpl;
            rebuildTable(objectsData);
            schedPreview();
          } catch(e){}
        JS
      rescue; end

      # ---- refresh_objects (called after apply so table shows new names) ----
      @dialog.add_action_callback('refresh_objects') do |_|
        model = Sketchup.active_model
        ents  = selected_rename_entities(model.selection)
        tmpl  = name_template(ents)
        data  = ents.map { |e| entity_data(e, tmpl[:unique_parts_by_id][e.entityID] || '') }
        @dialog.execute_script(<<~JS)
          try {
            objectsData = #{data.to_json};
            initialTmpl = #{tmpl[:template].to_json};
            document.getElementById('new_name').value = initialTmpl;
            rebuildTable(objectsData);
            schedPreview();
          } catch(e){}
        JS
      rescue; end

      # ---- update_object_name (inline table edit → immediate save) ----
      @dialog.add_action_callback('update_object_name') do |_, param|
        d  = JSON.parse(param)
        model = Sketchup.active_model
        e  = entities_by_id(model)[d['id'].to_i]
        next unless e&.valid?
        model.start_operation('Rename', true)
        e.name = sys_prefix(entity_raw_name(e)) + d['name'].to_s
        model.commit_operation
        queue_dialog_selection_sync
      rescue; end

      # ---- update_object_tag ----
      @dialog.add_action_callback('update_object_tag') do |_, param|
        d = JSON.parse(param)
        model = Sketchup.active_model
        e = entities_by_id(model)[d['id'].to_i]
        l = model.layers[d['tag'].to_s]
        next unless e && l
        model.start_operation('Change Tag', true)
        e.layer = l
        model.commit_operation
      rescue; end

      # ---- update_object_material ----
      @dialog.add_action_callback('update_object_material') do |_, param|
        d = JSON.parse(param)
        model = Sketchup.active_model
        e = entities_by_id(model)[d['id'].to_i]
        next unless e
        model.start_operation('Change Material', true)
        e.material = d['material'] == 'Default' ? nil : model.materials[d['material'].to_s]
        model.commit_operation
      rescue; end

      # ---- delete_object ----
      @dialog.add_action_callback('delete_object') do |_, param|
        eid = JSON.parse(param)['id'].to_i
        model = Sketchup.active_model
        e   = entities_by_id(model)[eid]
        next unless e&.valid?
        model.start_operation('Delete', true)
        e.erase!
        model.commit_operation
      rescue; end

      # ---- highlight_object ----
      @dialog.add_action_callback('highlight_object') do |_, param|
        eid = JSON.parse(param)['id'].to_i
        model = Sketchup.active_model
        e   = entities_by_id(model)[eid]
        next unless e
        hl_tool.set(e)
        Sketchup.active_model.select_tool(hl_tool)
      rescue; end

      # ---- resize_dialog ----
      @dialog.add_action_callback('resize_dialog') do |_, param|
        d = JSON.parse(param)
        @dialog.set_size(d['width'].to_i, d['height'].to_i)
      rescue; end

      # ---- close_dialog ----
      @dialog.add_action_callback('close_dialog') do |_|
        MH::ModelHub.unsubscribe(:rename_dialog)
        @dialog.close
      end

      # ---- hide_selected ----
      @dialog.add_action_callback('hide_selected') do |_|
        model = Sketchup.active_model
        model.start_operation('Hide Selected', true)
        model.selection.each { |e| e.hidden = true if e.respond_to?(:hidden=) }
        model.selection.clear
        model.commit_operation
      end

      # ---- focus_sketchup ----
      @dialog.add_action_callback('focus_sketchup') do |_|
        begin
          Sketchup.send_action("selectSelectionTool:")
        rescue
        end
      end

      # ---- request_focus (bring dialog to front for OS focus) ----
      @dialog.add_action_callback('request_focus') do |_|
        @dialog.bring_to_front if @dialog&.visible?
      end
    end

    # =========================================================================
    # HTML  (CSS + HTML + JS in one heredoc)
    # =========================================================================
    def self.build_html(template, objects, tags, mats)
      tag_opts = tags.map { |t| %(<option value="#{esc_attr(t)}">#{esc_html(t)}</option>) }.join
      mat_opts = mats.map { |m| %(<option value="#{esc_attr(m)}">#{esc_html(m)}</option>) }.join
      rows_html = objects.map { |o| build_row(o, tag_opts, mat_opts) }.join
      spfx_items = sub_prefix_suggestions.map { |s| %(<div class="ddi" onclick="pick('sub_prefix','#{esc_js(s)}')">#{esc_html(s)}</div>) }.join
      pfx_items = prefix_suggestions.map { |p| %(<div class="ddi" onclick="pick('prefix','#{esc_js(p)}')">#{esc_html(p)}</div>) }.join
      mod_items = modul_suggestions.map  { |m| %(<div class="ddi" onclick="pick('modul','#{esc_js(m)}')">#{esc_html(m)}</div>) }.join
      sfx_items = suffix_suggestions.map { |s| %(<div class="ddi" onclick="pick('suffix','#{esc_js(s)}')">#{esc_html(s)}</div>) }.join
      tmpl_esc  = esc_attr(template)
      tmpl_js   = esc_js(template)
      count     = objects.length

      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <style>
          :root{
            --bg0:#0d0f18;--bg1:#13162a;--bg2:#1c2040;--bg3:#232848;
            --acc:#5b8cff;--acc2:#7fd4e8;--ok:#55e5a0;--warn:#ffcc55;
            --danger:#ff5f5f;--txt:#d8dff0;--txt2:#7a8ab0;
            --border:rgba(91,140,255,.2);--r:5px;
          }
          *{box-sizing:border-box;margin:0;padding:0}
          body{font-family:'Segoe UI','Tahoma','Arial','Noto Sans',sans-serif;background:var(--bg0);color:var(--txt);
               font-size:12px;padding:10px;overflow-y:auto}
          /* layout */
          .topbar{display:flex;align-items:center;justify-content:space-between;margin-bottom:8px}
          .title{font-family:monospace;font-size:13px;font-weight:700;color:var(--acc);letter-spacing:.5px}
          .count{font-size:11px;color:var(--txt2);background:var(--bg2);padding:2px 8px;border-radius:20px}
          .card{background:var(--bg1);border:1px solid var(--border);border-radius:6px;
                padding:8px 10px;margin-bottom:8px}
          .lbl{font-family:monospace;font-size:9px;text-transform:uppercase;letter-spacing:1.5px;
               color:var(--acc2);margin-bottom:4px}
          /* inputs */
          .ci,.cs{width:100%;background:var(--bg2);border:1px solid var(--border);
                  border-radius:var(--r);color:var(--txt);padding:4px 7px;
                  font-size:12px;outline:none;transition:border-color .15s}
          .ci:focus,.cs:focus{border-color:var(--acc)}
          .cs option{background:var(--bg1)}
          #new_name{font-family:monospace;font-size:13px;background:var(--bg2);
                    border:1px solid var(--border);border-radius:var(--r);
                    color:var(--acc2);padding:5px 8px;width:100%;outline:none}
          #new_name:focus{border-color:var(--acc);box-shadow:0 0 0 2px rgba(91,140,255,.15)}
          /* pms row */
          .pms{display:flex;gap:5px;margin-top:6px}
          .pms-c{flex:1;position:relative}
          .pms-c label{font-size:9px;color:var(--txt2);text-transform:uppercase;
                       letter-spacing:1px;display:block;margin-bottom:2px}
          .pms-i{width:calc(100% - 24px);background:var(--bg3);border:1px solid var(--border);
                 border-radius:var(--r) 0 0 var(--r);color:var(--txt);
                 padding:3px 6px;font-size:11px;outline:none}
          .pms-i:focus{border-color:var(--acc)}
          .dbtn{width:24px;background:var(--bg3);border:1px solid var(--border);border-left:none;
                border-radius:0 var(--r) var(--r) 0;color:var(--txt2);
                cursor:pointer;font-size:9px}
          /* dropdown */
          .dd{display:none;position:absolute;top:100%;left:0;right:0;z-index:200;
              background:var(--bg1);border:1px solid var(--acc);border-radius:var(--r);
              max-height:130px;overflow-y:auto;box-shadow:0 4px 16px rgba(0,0,0,.5)}
          .dd.open{display:block}
          .ddi{padding:4px 8px;cursor:pointer;font-size:11px;color:var(--txt);
               border-bottom:1px solid var(--bg2)}
          .ddi:hover{background:var(--bg3);color:var(--acc2)}
          /* numbering */
          .numrow{display:flex;align-items:center;gap:6px;margin-top:6px;
                  padding-top:6px;border-top:1px solid var(--border)}
          .numrow label{font-size:11px;color:var(--txt2)}
          .numrow input[type=checkbox]{accent-color:var(--acc);width:13px;height:13px;cursor:pointer}
          .numstart{width:44px;text-align:center;font-family:monospace}
          /* preview bar */
          .pbar{margin-top:6px;padding:4px 8px;background:var(--bg2);
                border-left:3px solid var(--ok);border-radius:0 var(--r) var(--r) 0;
                font-family:monospace;font-size:11px;color:var(--ok);
                word-break:break-all;min-height:20px}
          .pbar.empty{color:var(--txt2);border-color:var(--txt2)}
          /* action buttons */
          .arow{display:flex;gap:6px;margin-top:6px}
          .bclear{flex:1;padding:4px 8px;background:var(--bg3);border:1px solid var(--border);
                  border-radius:var(--r);color:var(--txt2);cursor:pointer;font-size:11px;font-weight:600}
          .breset{flex:1;padding:4px 8px;background:rgba(255,95,95,.12);
                  border:1px solid rgba(255,95,95,.3);border-radius:var(--r);
                  color:var(--danger);cursor:pointer;font-size:11px;font-weight:600}
          .bclear:hover{background:var(--bg2);color:var(--txt)}
          .breset:hover{background:rgba(255,95,95,.22)}
          /* table */
          .thdr{display:flex;align-items:center;justify-content:space-between;
                cursor:pointer;padding:4px 0 6px;border-bottom:1px solid var(--border);
                user-select:none}
          .thdr:hover{opacity:.8}
          .ttitle{font-size:10px;font-weight:600;text-transform:uppercase;
                  letter-spacing:1px;color:var(--acc2)}
          .ticon{color:var(--acc2);font-size:11px;transition:transform .2s}
          .ticon.open{transform:rotate(180deg)}
          .tbody{display:none;margin-top:6px}
          .tbody.open{display:block}
          #obj-search{width:100%;margin-bottom:6px;background:var(--bg2);
                      border:1px solid var(--border);border-radius:var(--r);
                      color:var(--txt);padding:4px 8px;font-size:11px;outline:none}
          #obj-search:focus{border-color:var(--acc)}
          .tscroll{max-height:360px;overflow-y:auto;padding-right:4px}
          .gcontainer{display:grid;grid-template-columns:repeat(auto-fill, minmax(325px, 1fr));gap:6px;}
          .grow{display:flex;align-items:center;background:var(--bg2);border:1px solid transparent;border-radius:var(--r);padding:2px;}
          .grow:hover{background:rgba(91,140,255,.08);border-color:var(--border);}
          .grow.active{background:rgba(255,204,85,.1);border-color:rgba(255,204,85,.3);}
          .gcell-name{flex:1;min-width:0;position:relative;}
          .tc{text-align:center;width:22px;flex-shrink:0;}
          .eye{cursor:pointer;font-size:12px;opacity:.5;padding:0 2px}
          .eye:hover{opacity:1}
          .dbtn2{background:rgba(255,95,95,.2);border:1px solid rgba(255,95,95,.35);
                 border-radius:3px;color:var(--danger);cursor:pointer;
                 font-size:10px;padding:1px 4px}
          .dbtn2:hover{background:rgba(255,95,95,.4)}
          .bapply{flex:1;background:rgba(91,140,255,.2);color:#5b8cff;border:1px solid rgba(91,140,255,.3);border-radius:3px;cursor:pointer;padding:4px;font-weight:bold;}
          .bapply:hover{background:rgba(91,140,255,.4)}
          .nwrap{position:relative}
          .pbadge{display:block;font-family:monospace;font-size:9px;color:var(--ok);
                  white-space:nowrap;overflow:hidden;text-overflow:ellipsis;
                  padding:0 2px;line-height:13px;min-height:13px}
          ::-webkit-scrollbar{width:4px}
          ::-webkit-scrollbar-track{background:var(--bg0)}
          ::-webkit-scrollbar-thumb{background:var(--bg3);border-radius:2px}
        </style>
        </head>
        <body>

        <div class="topbar">
          <span class="title">MH Rename</span>
          <span class="count">#{count} object(s)</span>
        </div>

        <div class="card">
          <div class="lbl">Name Template</div>
          <input id="new_name" type="text" value="#{tmpl_esc}"
            placeholder="[original name] or type new name…"
            oninput="schedPreview()">

          <div class="pms">
            #{%w[sub_prefix prefix modul suffix].map { |t|
              label = case t
                      when 'sub_prefix' then 'Sub-Pfx'
                      when 'modul' then 'Modul'
                      else t.capitalize
                      end
              ph = case t
                   when 'sub_prefix' then 'T2S5A'
                   when 'prefix' then 'SP'
                   when 'modul' then 'Tam Dung'
                   else 'L'
                   end
              items = case t
                      when 'sub_prefix' then spfx_items
                      when 'prefix' then pfx_items
                      when 'modul' then mod_items
                      else sfx_items
                      end
              <<~CELL
                <div class="pms-c">
                  <label>#{label}</label>
                  <input id="#{t}" class="pms-i" type="text" placeholder="#{ph}"
                    oninput="onPms('#{t}')" onfocus="openDd('#{t}')">
                  <button class="dbtn" onclick="togDd('#{t}')">▾</button>
                  <div id="#{t}_dd" class="dd">#{items}</div>
                </div>
              CELL
            }.join}
          </div>

          <div class="numrow">
            <input type="checkbox" id="add_num" onchange="schedPreview()">
            <label for="add_num">Numbering from</label>
            <input id="start_num" class="ci numstart" type="text" value="01" oninput="schedPreview()">
          </div>

          <div id="pbar" class="pbar empty">[preview]</div>

          <div class="arow">
            <button class="bclear" onclick="restoreTmpl()">Restore</button>
            <button class="breset" onclick="clearAll()">Clear</button>
            <button class="bapply" onclick="applyNow()">Apply</button>
          </div>
        </div>

        <div class="card">
          <div class="thdr" onclick="togTable()">
            <span class="ttitle" id="ttitle">Objects (#{count})</span>
            <span id="ticon" class="ticon">?</span>
          </div>
          <div id="tbody" class="tbody">
            <input id="obj-search" type="text"
              placeholder="Filter..." oninput="filterTable()">
            <div class="tscroll">
              <div id="rows" class="gcontainer">#{rows_html}</div>
            </div>
          </div>
        </div>

        <script>
        // ── STATE ─────────────────────────────────────────────────────────
        const TOKEN = '[original name]';
        let objectsData  = #{objects.to_json};
        let initialTmpl  = "#{tmpl_js}";
        let tableOpen    = false;
        let tagOptHtml   = '';
        let matOptHtml   = '';

        const SPFXS = #{sub_prefix_suggestions.to_json};
        const PFXS = #{prefix_suggestions.to_json};
        const MODS = #{modul_suggestions.to_json};
        const SFXS = #{suffix_suggestions.to_json};
        const SEPS = #{(name_separators || {}).to_json};

        // ── INIT ──────────────────────────────────────────────────────────
        window.addEventListener('load', () => {
          const ts = document.querySelector('.cst'); // tag select
          const ms = document.querySelector('.csm'); // mat select
          if(ts) tagOptHtml = ts.innerHTML;
          if(ms) matOptHtml = ms.innerHTML;
          schedPreview();
        });

        // ── FOCUS MANAGEMENT ─────────────────────────────────────────────
        let lastFocusedInput = null;
        let tabNavigating = false;
        const MAIN_INPUT_IDS = ['new_name', 'sub_prefix', 'prefix', 'modul', 'suffix'];
        function getMainInputs(){ return MAIN_INPUT_IDS.map(id=>document.getElementById(id)).filter(Boolean); }

        document.addEventListener('focusin', e=>{
          if(e.target&&(e.target.tagName==='INPUT'||e.target.tagName==='SELECT')) lastFocusedInput=e.target;
        });

        // Click vùng trống → restore focus
        document.addEventListener('click', e=>{
          if(!e.target.closest('input,select,button,.ddi,.eye,.dbtn2')){
            setTimeout(()=>{
              if(!document.activeElement||document.activeElement===document.body){
                const t=lastFocusedInput&&document.contains(lastFocusedInput)?lastFocusedInput:document.getElementById('new_name');
                if(t) t.focus();
              }
            },10);
          }
        });

        // ── GLOBAL TAB (khi KHÔNG ở trong bảng) ──────────────────────────
        function doTabFocus(target){
          tabNavigating=true; closeAllDd();
          target.focus(); target.select();
          setTimeout(()=>{tabNavigating=false;},50);
        }
        document.addEventListener('keydown', e=>{
          if(e.key!=='Tab') return;
          if(e.target.closest('#rows')) return; // navTable xử lý
          e.preventDefault();
          const mi=getMainInputs(), ci=mi.indexOf(e.target);
          if(ci===-1){ if(mi[0]) doTabFocus(mi[0]); return; }
          if(e.shiftKey){
            if(ci===0&&tableOpen){
              const ti=[...document.querySelectorAll('#rows .grow:not([style*="display:none"]) .obj-name')];
              if(ti.length){const l=ti[ti.length-1];doTabFocus(l);const r=l.closest('.grow');if(r)hlRow(parseInt(r.getAttribute('data-id')),r);return;}
            }
            const p=ci<=0?mi.length-1:ci-1; doTabFocus(mi[p]);
          } else {
            if(ci===mi.length-1&&tableOpen){
              const ti=[...document.querySelectorAll('#rows .grow:not([style*="display:none"]) .obj-name')];
              if(ti.length){const f=ti[0];doTabFocus(f);const r=f.closest('.grow');if(r)hlRow(parseInt(r.getAttribute('data-id')),r);return;}
            }
            const n=ci>=mi.length-1?0:ci+1; doTabFocus(mi[n]);
          }
        });

        let lastEsc = 0;
        document.addEventListener('keydown', e => {
          if (e.key === 'F4') {
            e.preventDefault();
            sketchup.hide_selected();
            return;
          }
          if (e.key === 'Escape') {
            e.preventDefault();
            const now = Date.now();
            if (now - lastEsc < 500) {
              sketchup.close_dialog();
            } else {
              if (e.target && e.target.blur) e.target.blur();
              if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
              window.getSelection().removeAllRanges();
              sketchup.focus_sketchup();
              lastEsc = now;
            }
          }
        });

        // ── DROPDOWN ─────────────────────────────────────────────────────
        function togDd(t) {
          const dd = document.getElementById(t+'_dd');
          const was = dd.classList.contains('open');
          closeAllDd();
          if(!was){ filterDd(t); dd.classList.add('open'); }
        }
        function openDd(t){ if(tabNavigating) return; closeAllDd(); filterDd(t); document.getElementById(t+'_dd').classList.add('open'); }
        function closeAllDd(){ document.querySelectorAll('.dd').forEach(d=>d.classList.remove('open')); }
        function filterDd(t){
          const v = document.getElementById(t).value.toLowerCase();
          const sugg = t==='sub_prefix'?SPFXS:(t==='prefix'?PFXS:(t==='modul'?MODS:SFXS));
          document.getElementById(t+'_dd').innerHTML =
            sugg.filter(s=>s.toLowerCase().includes(v))
                .map(s=>`<div class="ddi" onclick="pick('${t}','${s.replace(/'/g,"\\'")}')"> ${s}</div>`)
                .join('');
        }
        function pick(t,v){ document.getElementById(t).value=v; closeAllDd(); schedPreview(); }
        function onPms(t){ filterDd(t); document.getElementById(t+'_dd').classList.add('open'); schedPreview(); }
        document.addEventListener('click', e=>{ if(!e.target.closest('.pms-c')) closeAllDd(); });

        // ── PREVIEW ENGINE ────────────────────────────────────────────────
        // buildName: resolve final name for one entity (base already has token replaced)
        function buildName(base, spfx, pfx, mod, sfx){
          if(!base && !spfx && !pfx && !mod && !sfx) return '';
          const sepSpfx = SEPS.sep_sub_prefix || '-';
          const sepPfx  = SEPS.sep_prefix || '_';
          const sepSfx  = SEPS.sep_suffix || '_';
          
          let noPfx = base||'';
          let detPfx = '';
          let pfxSep = '';

          let foundConfig = false;
          const bl = noPfx.toLowerCase();
          for(const p of PFXS) {
            if(bl.startsWith(p.toLowerCase())){ 
              detPfx = noPfx.slice(0, p.length);
              noPfx = noPfx.slice(p.length);
              const sm = noPfx.match(/^[.\\-_\\s]*/);
              if(sm) { pfxSep = sm[0]; noPfx = noPfx.slice(sm[0].length); }
              foundConfig = true;
              break; 
            }
          }
          
          if(!foundConfig) {
            // regex khắt khe hơn: bắt buộc có số \d+
            const match = noPfx.match(/^([A-Za-z]+\d+(?:\.[A-Za-z0-9]+)*)([.\-_\s]*)/);
            if(match && match[1]) {
              detPfx = match[1];
              pfxSep = match[2];
              noPfx = noPfx.slice(match[0].length);
            }
          }

          // detect/strip old modul
          let noMod=noPfx, detMod='';
          if(noPfx){
            const nl=noPfx.toLowerCase();
            for(const m of MODS){
              if(nl.startsWith(m.toLowerCase()+'_') || nl.startsWith(m.toLowerCase()+'.')){ 
                detMod=noPfx.slice(0,m.length); noMod=noPfx.slice(m.length+1); break; 
              }
              if(nl.startsWith(m.toLowerCase())){
                const rest=noPfx.slice(m.length);
                if(rest===''||rest.startsWith('_')||rest.startsWith('.')){ 
                  detMod=noPfx.slice(0,m.length); 
                  noMod=(rest.startsWith('_')||rest.startsWith('.'))?rest.slice(1):rest; 
                  break; 
                }
              }
            }
          }

          // strip old known suffix if adding new one
          let noSfx=noMod;
          if(sfx && noMod){ const nl=noMod.toLowerCase(); for(const s of SFXS) if(nl.endsWith(s.toLowerCase())){ noSfx=noMod.slice(0,-s.length); break; } }
          
          let finalPfx = (pfx !== undefined && pfx !== null && pfx !== '') ? pfx : detPfx;
          const activeMod = (mod !== undefined && mod !== null && mod !== '') ? mod : detMod;

          // Sub-prefix: T2S5A-SP01
          let subPart = '';
          if (spfx) {
            subPart = spfx + sepSpfx;
          }

          // Prefix separator: chỉ thêm khi có phần sau
          let pfxPart = '';
          if (finalPfx !== '') {
            const hasAfter = activeMod || noSfx || sfx;
            pfxPart = finalPfx + (hasAfter ? (pfxSep || sepPfx) : '');
          }

          // Modul separator
          const modPart = activeMod ? (activeMod + sepSfx) : '';

          return subPart + pfxPart + modPart + noSfx + (sfx||'');
        }

        // resolve base string for one entity given current template
        function resolveBase(eid, tmpl){
          const od = objectsData.find(o=>o.id===eid);
          if(tmpl.includes(TOKEN)){
            let uniq = '';
            if (od) {
              uniq = (od.unique_part !== undefined && od.unique_part !== null) ? od.unique_part : (od.name || '');
            }
            return tmpl.replace(TOKEN, uniq);
          }
          if(tmpl==='') return od?(od.name||''):'';
          return tmpl;
        }

        let prevTmr=null;
        function schedPreview(){ if(prevTmr)clearTimeout(prevTmr); prevTmr=setTimeout(doPreview,30); }

        function doPreview(){
          const tmpl=v('new_name'), spfx=v('sub_prefix'), pfx=v('prefix'), mod=v('modul'), sfx=v('suffix');
          const addN=document.getElementById('add_num').checked, sn=v('start_num');
          const bar=document.getElementById('pbar');
          // top bar: use first visible entity for demo
          const firstRow = document.querySelector('#rows .grow:not([style*="display:none"])');
          const firstEid = firstRow?parseInt(firstRow.getAttribute('data-id')):null;
          let demo = firstEid!==null ? resolveBase(firstEid,tmpl) : (tmpl.replace(TOKEN,'…'));
          let built = buildName(demo,spfx,pfx,mod,sfx);
          if(addN&&sn) built+=sn;
          bar.textContent = built?('→ '+built):'[empty]';
          bar.className   = built?'pbar':'pbar empty';
          // per-row badges
          const rows = [...document.querySelectorAll('#rows .grow')].filter(r=>r.style.display!=='none');
          rows.forEach((row,i)=>{
            const eid  = parseInt(row.getAttribute('data-id'));
            const base = resolveBase(eid,tmpl);
            let fn     = buildName(base,spfx,pfx,mod,sfx);
            if(addN&&sn) fn += String(parseInt(sn)+i).padStart(sn.length,'0');
            const badge = row.querySelector('.pbadge');
            if(badge) badge.textContent = fn?('→ '+fn):'';
          });
        }

        function applyNow() {
          const tmpl=v('new_name'), spfx=v('sub_prefix'), pfx=v('prefix'), mod=v('modul'), sfx=v('suffix');
          const addN=document.getElementById('add_num').checked, sn=v('start_num');
          const visRows=[...document.querySelectorAll('#rows .grow')].filter(r=>r.style.display!=='none');
          const rows=[];
          visRows.forEach((row,i)=>{
            const eid  = parseInt(row.getAttribute('data-id'));
            let base;
            if(tmpl.includes(TOKEN)||tmpl!==''){
              base = resolveBase(eid,tmpl);
            } else {
              const inp=row.querySelector('.obj-name');
              base=inp?(inp.getAttribute('data-saved')||inp.value||''):'';
            }
            let fn = buildName(base,spfx,pfx,mod,sfx);
            if(addN&&sn) fn+=String(parseInt(sn)+i).padStart(sn.length,'0');
            if(fn) rows.push({id:eid,name:fn});
          });
          if(rows.length) sketchup.apply_rename(JSON.stringify({rows}));
        }

        function v(id){ return document.getElementById(id).value; }

        // ── CLEAR / RESTORE ───────────────────────────────────────────────
        function restoreTmpl(){
          document.getElementById('new_name').value=initialTmpl;
          ['prefix','modul','suffix'].forEach(t=>document.getElementById(t).value='');
          document.getElementById('add_num').checked=false;
          document.getElementById('start_num').value='01';
          schedPreview();
        }
        function clearAll(){
          // Call sketchup to clear prefixes for all filtered objects
          const visRows=[...document.querySelectorAll('#rows .grow')].filter(r=>r.style.display!=='none');
          const ids = visRows.map(r => parseInt(r.getAttribute('data-id')));
          if(ids.length > 0) {
            sketchup.clear_prefixes(JSON.stringify({ids}));
          }
          document.getElementById('new_name').value='';
          ['prefix','modul','suffix'].forEach(t=>document.getElementById(t).value='');
          document.getElementById('add_num').checked=false;
          document.getElementById('start_num').value='01';
          // Do not call schedPreview() here, let Ruby's update_dialog_data trigger the refresh
        }



        // ── TABLE ─────────────────────────────────────────────────────────
        function togTable(){
          tableOpen=!tableOpen;
          document.getElementById('tbody').classList.toggle('open',tableOpen);
          document.getElementById('ticon').classList.toggle('open',tableOpen);
          if(tableOpen){
            sketchup.resize_dialog(JSON.stringify({width:440,height:720}));
          } else {
            sketchup.resize_dialog(JSON.stringify({width:440,height:400}));
          }
        }

        function filterTable(){
          const term=document.getElementById('obj-search').value.toLowerCase().trim();
          const allRows=document.querySelectorAll('#rows .grow');
          let vis=0;
          let visRows=[];
          allRows.forEach(r=>{
            const inp=r.querySelector('.obj-name');
            const nm=(inp?inp.value:'').toLowerCase();
            const show=!term||nm.includes(term);
            r.style.display=show?'':'none';
            if(show){
              vis++;
              visRows.push(r);
            }
          });
          const total=allRows.length;
          document.getElementById('ttitle').textContent=
            term?`📋 Objects (${vis}/${total} filtered)`:`📋 Objects (${total})`;
            
          // RECALCULATE NAME TEMPLATE FOR VISIBLE ROWS
          if (visRows.length > 0) {
            const names = visRows.map(r => r.querySelector('.obj-name').value || '');
            if (names.every(n => n === names[0])) {
              document.getElementById('new_name').value = names[0];
              visRows.forEach(r => {
                let id = parseInt(r.getAttribute('data-id'));
                let od = objectsData.find(o => o.id === id);
                if (od) od.unique_part = '';
              });
            } else {
              let pfx = names[0];
              for (let i = 1; i < names.length; i++) {
                while (names[i].indexOf(pfx) !== 0) {
                  pfx = pfx.substring(0, pfx.length - 1);
                  if (!pfx) break;
                }
              }
              let sfx = names[0].substring(pfx.length);
              for (let i = 1; i < names.length; i++) {
                let s = names[i].substring(pfx.length);
                while (sfx && !s.endsWith(sfx)) {
                  sfx = sfx.substring(1);
                }
              }
              document.getElementById('new_name').value = pfx + '[original name]' + sfx;
              visRows.forEach(r => {
                let id = parseInt(r.getAttribute('data-id'));
                let od = objectsData.find(o => o.id === id);
                if (od) {
                  let name = r.querySelector('.obj-name').value || '';
                  od.unique_part = name.substring(pfx.length, name.length - sfx.length);
                }
              });
            }
          }
          schedPreview();
        }

        // ── ROW ACTIONS ───────────────────────────────────────────────────
        function hlRow(id,row){
          document.querySelectorAll('#rows .grow').forEach(r=>r.classList.remove('active'));
          row?.classList.add('active');
          sketchup.highlight_object(JSON.stringify({id}));
        }

        function commitName(id,inp){
          inp.setAttribute('data-saved',inp.value);
          const od=objectsData.find(o=>o.id===id);
          if(od) od.name=inp.value;
          sketchup.update_object_name(JSON.stringify({id,name:inp.value}));
        }

        function delRow(id,row){
          row.style.cssText='transition:opacity .15s,transform .15s;opacity:0;transform:translateX(14px)';
          sketchup.delete_object(JSON.stringify({id}));
          setTimeout(()=>{
            row.remove();
            const n=document.querySelectorAll('#rows .grow').length;
            document.getElementById('ttitle').textContent=`📋 Objects (${n})`;
            document.querySelector('.count').textContent=`${n} object(s)`;
          },160);
        }

        // ── TABLE NAV (Tab / ArrowUp / ArrowDown between name inputs) ─────
        function navTable(e){
          if(!['Tab','ArrowDown','ArrowUp','Enter'].includes(e.key)) return;
          e.preventDefault();
          if(e.key==='Enter'){ e.target.blur(); return; }
          const ins=[...document.querySelectorAll('#rows .grow:not([style*="display:none"]) .obj-name')];
          const cur=ins.indexOf(e.target);
          const back=(e.key==='Tab'&&e.shiftKey)||e.key==='ArrowUp'||e.key==='ArrowLeft';
          // Tab boundary: thoát bảng → main inputs
          if(e.key==='Tab'){
            if(!back&&cur>=ins.length-1){const nn=document.getElementById('new_name');if(nn){nn.focus();nn.select();}return;}
            if(back&&cur<=0){const sfx=document.getElementById('suffix');if(sfx){sfx.focus();sfx.select();}return;}
          }
          const nxt=back?(cur<=0?ins.length-1:cur-1):(cur>=ins.length-1?0:cur+1);
          if(ins[nxt]){ ins[nxt].focus(); ins[nxt].select(); const r=ins[nxt].closest('.grow'); if(r)hlRow(parseInt(r.getAttribute('data-id')),r); }
        }

        // ── REBUILD TABLE (from SelectionObserver) ────────────────────────
        function rebuildTable(data){
          // snapshot current tag/mat option html from any live select
          const et=document.querySelector('.cst'), em=document.querySelector('.csm');
          if(et&&et.innerHTML) tagOptHtml=et.innerHTML;
          if(em&&em.innerHTML) matOptHtml=em.innerHTML;

          const frag=document.createDocumentFragment();
          data.forEach(obj=>{
            const tr=document.createElement('div');
            tr.className='grow';
            tr.setAttribute('data-id',obj.id);

            // eye cell
            const td0=document.createElement('div'); td0.className='tc';
            td0.innerHTML=`<div class="eye" onclick="hlRow(${obj.id},this.closest('.grow'))" title="Highlight">👁</div>`;
            tr.appendChild(td0);

            // name + badge
            const td1=document.createElement('div'); td1.className='gcell-name nwrap';
            const inp=document.createElement('input');
            inp.type='text'; inp.className='obj-name ci';
            inp.value=obj.name||'';
            inp.setAttribute('data-saved',obj.name||'');
            inp.onchange=function(){commitName(obj.id,this)};
            inp.onkeydown=navTable;
            inp.onfocus=function(){hlRow(obj.id,this.closest('.grow'))};
            inp.onclick=function(e){e.stopPropagation()};
            const badge=document.createElement('span'); badge.className='pbadge';
            td1.appendChild(inp); td1.appendChild(badge); tr.appendChild(td1);

            // delete
            const td4=document.createElement('div'); td4.className='tc';
            td4.innerHTML=`<button class="dbtn2" onclick="event.stopPropagation();delRow(${obj.id},this.closest('.grow'))" title="Delete">✕</button>`;
            tr.appendChild(td4);

            frag.appendChild(tr);
          });
          const tbody=document.getElementById('rows');
          tbody.innerHTML=''; tbody.appendChild(frag);
          document.getElementById('ttitle').textContent=`📋 Objects (${data.length})`;
          document.querySelector('.count').textContent=`${data.length} object(s)`;
          filterTable();
        }

        // ── KEYBOARD SHORTCUT ─────────────────────────────────────────────
        let lastEnter=0;
        document.addEventListener('keydown',e=>{
          if(e.key==='Enter') {
            if(!e.target.closest('#rows')) {
              e.preventDefault();
              applyNow();
            }
            return;
          }
        });
        </script>
        </body>
        </html>
      HTML
    end

    # =========================================================================
    # HTML HELPERS
    # =========================================================================
    def self.esc_attr(s); s.to_s.gsub('"','&quot;').gsub("'",'&#39;'); end
    def self.esc_html(s); s.to_s.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;'); end
    def self.esc_js(s);   s.to_s.gsub("\\","\\\\").gsub("'","\\'").gsub('"','\\"'); end

    def self.build_row(obj, tag_opts, mat_opts)
      name  = esc_attr(obj[:name].to_s)
      uniq  = esc_attr(obj[:unique_part].to_s)
      id    = obj[:id]
      <<~ROW
        <div class="grow" data-id="#{id}">
          <div class="tc"><div class="eye" onclick="hlRow(#{id},this.closest('.grow'))" title="Highlight">👁</div></div>
          <div class="gcell-name nwrap">
            <input class="obj-name ci" type="text" value="#{name}" data-saved="#{name}"
              onchange="commitName(#{id},this)" onkeydown="navTable(event)"
              onfocus="hlRow(#{id},this.closest('.grow'))" onclick="event.stopPropagation()">
            <span class="pbadge"></span>
          </div>
          <div class="tc"><button class="dbtn2" onclick="event.stopPropagation();delRow(#{id},this.closest('.grow'))" title="Delete">✕</button></div>
        </div>
      ROW
    end

    # =========================================================================
    # QUICK PREFIX
    # =========================================================================
    def self.quick_prefix
      attach_global_observers
      @qp_active = true
      @qr_active = false
      close_qr_dialog
      
      Sketchup.active_model.select_tool(nil) # Switch to selection tool safely
      
      ents = Sketchup.active_model.selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
      show_qp_dialog(ents)
      @qp_dialog.execute_script("document.body.style.opacity='0.2';") if ents.empty? rescue nil
    end

    def self.create_qp_dialog
      return if @qp_dialog
      @programmatic_close_qp = false
      @qp_dialog = UI::HtmlDialog.new(
        dialog_title: "Quick Prefix",
        preferences_key: "MH_Quick_Prefix_v2",
        width: 224, height: 70,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      
      html = <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <style>
            body { font-family: 'Segoe UI', sans-serif; background: #2b2b2b; color: #eee; margin: 0; padding: 10px; display: flex; align-items: center; justify-content: center; height: 100vh; box-sizing: border-box; overflow:hidden;}
            input { width: 100%; padding: 6px; font-size: 13px; border: 1px solid #555; border-radius: 4px; background: #1e1e1e; color: #fff; outline: none; }
            input:focus { border-color: #5b8cff; box-shadow: 0 0 5px rgba(91,140,255,0.3); }
          </style>
        </head>
        <body>
            <input type="text" id="pfx" placeholder="01 -> mã theo họ đang đứng đầu">
          <script>
            const inp = document.getElementById('pfx');
            inp.focus();
            inp.addEventListener('keydown', e => {
              if (e.key === 'Enter') {
                sketchup.apply(inp.value);
              } else if (e.key === 'Escape') {
                e.preventDefault();
                sketchup.deactivate('');
              }
            });
            document.addEventListener('keydown', e => {
              if (e.key === 'F4') {
                e.preventDefault();
                sketchup.hide_selected('');
              } else if (e.key === 'Escape') {
                sketchup.deactivate('');
              }
            });
            window.addEventListener('keyup', e => {
              if (e.key === 'Escape') sketchup.deactivate('');
            });
            document.addEventListener('click', e => {
              if(!e.target.closest('input')) setTimeout(()=>{ inp.focus(); },10);
            });
          </script>
        </body>
        </html>
      HTML
      @qp_dialog.set_html(html)
      
      @qp_dialog.add_action_callback('apply') do |_, val|
        @skip_observer = true
        UI.start_timer(0.05, false) do
          begin
            val = val.to_s.strip
            
            model = Sketchup.active_model
            model.start_operation('Quick Prefix', true)
            current_sel = model.selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
            
            current_sel.each do |e|
              raw_name = e.respond_to?(:name) ? e.name : ''
              final_name = quick_prefix_name(raw_name, val)
              e.name = final_name unless final_name.empty?
            end
            model.commit_operation
          ensure
            @skip_observer = false
            deactivate_quick_tools
          end
        end
      end
      
      @qp_dialog.add_action_callback('deactivate') { |_| deactivate_quick_tools }
      @qp_dialog.add_action_callback('request_focus') { |_| @qp_dialog.bring_to_front if @qp_dialog&.visible? }
      @qp_dialog.add_action_callback('hide_selected') do |_|
        model = Sketchup.active_model
        model.start_operation('Hide Selected', true)
        model.selection.each { |e| e.hidden = true if e.respond_to?(:hidden=) }
        model.selection.clear
        model.commit_operation
      end
      
      @qp_dialog.set_on_closed do
        unless @programmatic_close_qp
          @qp_dialog = nil
          deactivate_quick_tools
        end
      end
    end

    def self.show_qp_dialog(sel)
      create_qp_dialog
      
      if @qp_dialog.visible?
        @qp_dialog.bring_to_front
        @qp_dialog.execute_script("setTimeout(function(){var i=document.getElementById('pfx');i.value='';i.focus();},50);")
      else
        @qp_dialog.show
      end
    end

    # =========================================================================
    # QUICK RENAME (SUFFIX)
    # =========================================================================
    def self.quick_rename
      attach_global_observers
      @qr_active = true
      @qp_active = false
      close_qp_dialog
      
      Sketchup.active_model.select_tool(nil)
      
      ents = Sketchup.active_model.selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
      show_qr_dialog(ents)
      @qr_dialog.execute_script("document.body.style.opacity='0.2';") if ents.empty? rescue nil
    end

    def self.create_qr_dialog
      return if @qr_dialog
      @programmatic_close_qr = false
      @qr_dialog = UI::HtmlDialog.new(
        dialog_title: "Quick Rename",
        preferences_key: "MH_Quick_Rename_v2",
        width: 280, height: 252,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      
      @qr_dialog.add_action_callback('apply') do |_, val|
        @skip_observer = true
        UI.start_timer(0.05, false) do
          begin
            val = val.to_s.strip
            model = Sketchup.active_model
            model.start_operation('Quick Rename Suffix', true)
            current_sel = model.selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
            
            current_sel.each do |e|
              raw_name = e.respond_to?(:name) ? e.name : ''
              raw = clean_name(raw_name)
              sys = sys_prefix(raw_name)
              
              parsed = NameParser.parse_name(raw_name, prefixes: @prefix_suggestions)
              pfx = parsed[:prefix_with_separator]
              
              e.name = sys + pfx + val
            end
            model.commit_operation
          ensure
            @skip_observer = false
            deactivate_quick_tools
          end
        end
      end
      
      @qr_dialog.add_action_callback('deactivate') { |_| deactivate_quick_tools }
      @qr_dialog.add_action_callback('request_focus') { |_| @qr_dialog.bring_to_front if @qr_dialog&.visible? }
      @qr_dialog.add_action_callback('hide_selected') do |_|
        model = Sketchup.active_model
        model.start_operation('Hide Selected', true)
        model.selection.each { |e| e.hidden = true if e.respond_to?(:hidden=) }
        model.selection.clear
        model.commit_operation
      end
      
      @qr_dialog.set_on_closed do
        unless @programmatic_close_qr
          @qr_dialog = nil
          deactivate_quick_tools
        end
      end
    end

    def self.show_qr_dialog(sel)
      prefixes = []
      moduls = []
      suffixes = []
      
      sel.each do |e|
        raw_name = e.respond_to?(:name) ? e.name : ''
        raw = clean_name(raw_name)
        
        parsed = NameParser.parse_name(raw_name, prefixes: @prefix_suggestions)
        pfx = parsed[:prefix_with_separator]
        no_pfx = parsed[:core]
        
        prefixes << pfx
        suffixes << no_pfx
      end
      
      common_pfx = prefixes.uniq.length == 1 ? prefixes.first : "[Multi-Prefix]"
      common_sfx = suffixes.uniq.length == 1 ? suffixes.first : ""
      
      display_label = common_pfx
      display_label = "" if display_label == "[Multi-Prefix]"
      
      create_qr_dialog
      
      html = build_qr_html(display_label, common_sfx)
      @qr_dialog.set_html(html)
      
      if @qr_dialog.visible?
        @qr_dialog.bring_to_front
        @qr_dialog.execute_script("setTimeout(function(){document.getElementById('name').focus();document.getElementById('name').select();},50);")
      else
        @qr_dialog.show
      end
    end

    def self.build_qr_html(display_label, common_sfx)
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <style>
            body { font-family: 'Segoe UI', sans-serif; background: #2b2b2b; color: #eee; margin: 0; padding: 10px; box-sizing: border-box; overflow:visible;}
            .wrap { display: flex; align-items: center; background: #1e1e1e; border: 1px solid #555; border-radius: 4px; padding: 0 8px; position:relative; }
            .wrap:focus-within { border-color: #5b8cff; box-shadow: 0 0 5px rgba(91,140,255,0.3); }
            .pfx { color: #aaa; white-space: pre; font-size: 11px; user-select: none; }
            input { flex: 1; padding: 8px 0 8px 4px; font-size: 13px; border: none; background: transparent; color: #fff; outline: none; }
            .sugg { position: absolute; top: 100%; left: 0; right: 0; background: #333; border: 1px solid #555; border-top: none; border-radius: 0 0 4px 4px; max-height: 180px; overflow-y: auto; display: none; z-index: 100; box-shadow: 0 4px 8px rgba(0,0,0,0.3);}
            .sugg.open { display: block; }
            .si { padding: 6px 8px; cursor: pointer; border-bottom: 1px solid #444; font-size: 12px; }
            .si:hover, .si.sel { background: #5b8cff; color: #fff; }
          </style>
        </head>
        <body>
          <div style="margin-bottom:6px; color:#aaa; font-size:11px;">Đổi Hậu Tố (Suffix)</div>
          <div class="wrap">
            <div class="pfx" id="pfxL">#{esc_html(display_label)}</div>
            <input type="text" id="name" placeholder="Nhập hậu tố mới..." value="#{esc_attr(common_sfx)}">
            <div class="sugg" id="sugg"></div>
          </div>
          <script>
            const inp = document.getElementById('name');
            const sugg = document.getElementById('sugg');
            const pfxL = document.getElementById('pfxL');
            const SFXS = #{@suffix_suggestions.to_json};
            
            if(!pfxL.textContent.trim() || pfxL.textContent.trim().includes('[Multi')) {
              if (pfxL.textContent.trim() === '') pfxL.style.display = 'none';
            }
            
            let selIdx = -1;
            let items = [];
            
            function showSugg() {
              const v = inp.value.toLowerCase().trim();
              items = SFXS.filter(m => m.toLowerCase().includes(v));
              if(items.length===0) { sugg.classList.remove('open'); return; }
              sugg.innerHTML = items.map((m,i) => `<div class="si" onmousedown="pick('${m.replace(/'/g,"\\\\'")}')">${m}</div>`).join('');
              sugg.classList.add('open');
              selIdx = -1;
            }
            
            function pick(v) {
              inp.value = v;
              sugg.classList.remove('open');
              sketchup.apply(v);
            }
            
            inp.addEventListener('input', showSugg);
            inp.addEventListener('focus', showSugg);
            // Removed blur event to keep suggestions open during Pan/Orbit
            
            inp.addEventListener('keydown', e => {
              if (e.key === 'ArrowDown') {
                e.preventDefault();
                if(selIdx < items.length - 1) selIdx++;
                updateSel();
              } else if (e.key === 'ArrowUp') {
                e.preventDefault();
                if(selIdx > 0) selIdx--;
                updateSel();
              } else if (e.key === 'Enter') {
                e.preventDefault();
                if(sugg.classList.contains('open') && selIdx >= 0) {
                  pick(items[selIdx]);
                } else {
                  sketchup.apply(inp.value);
                }
              } else if (e.key === 'Tab') {
                e.preventDefault();
                if(sugg.classList.contains('open') && items.length > 0) {
                  if (e.shiftKey) {
                    selIdx = selIdx > 0 ? selIdx - 1 : items.length - 1;
                  } else {
                    selIdx = selIdx < items.length - 1 ? selIdx + 1 : 0;
                  }
                  updateSel();
                }
              } else if (e.key === 'Escape') {
                e.preventDefault();
                sketchup.deactivate('');
              }
            });
            
            document.addEventListener('keydown', e => {
              if (e.key === 'F4') {
                e.preventDefault();
                sketchup.hide_selected('');
              } else if (e.key === 'Escape') {
                sketchup.deactivate('');
              }
            });
            window.addEventListener('keyup', e => {
              if (e.key === 'Escape') sketchup.deactivate('');
            });
            // Click vùng trống → restore focus
            document.addEventListener('click', e => {
              if(!e.target.closest('input,.si')) {
                setTimeout(()=>{ inp.focus(); },10);
              }
            });
            
            function updateSel() {
              const divs = sugg.querySelectorAll('.si');
              divs.forEach((d,i) => d.classList.toggle('sel', i === selIdx));
              if(selIdx >= 0) divs[selIdx].scrollIntoView({block:'nearest'});
            }
            
            setTimeout(() => { inp.focus(); inp.select(); }, 50);
          </script>
        </body>
        </html>
      HTML
    end

    # =========================================================================
    # MENU & TOOLBAR
    # =========================================================================
    unless defined?(@mh_rename_loaded)
      @mh_rename_loaded = true

      toolbar = UI::Toolbar.new('MH Rename')
      icons_dir = File.join(__dir__, 'icons')
      
      cmd1 = UI::Command.new('Rename Selected') { MH::Rename.rename_selected }
      cmd1.tooltip = 'Rename Selected Objects'
      icon1 = File.join(icons_dir, 'rename_selected.svg')
      if File.exist?(icon1)
        cmd1.small_icon = icon1
        cmd1.large_icon = icon1
      end
      toolbar.add_item(cmd1)

      cmd2 = UI::Command.new('Quick Prefix') { MH::Rename.quick_prefix }
      cmd2.tooltip = 'Quick Prefix (Shortcut)'
      icon2 = File.join(icons_dir, 'quick_prefix.svg')
      if File.exist?(icon2)
        cmd2.small_icon = icon2
        cmd2.large_icon = icon2
      end
      toolbar.add_item(cmd2)

      cmd3 = UI::Command.new('Quick Rename') { MH::Rename.quick_rename }
      cmd3.tooltip = 'Quick Rename (Shortcut)'
      icon3 = File.join(icons_dir, 'quick_rename.svg')
      if File.exist?(icon3)
        cmd3.small_icon = icon3
        cmd3.large_icon = icon3
      end
      toolbar.add_item(cmd3)

      cmd4 = UI::Command.new('Reload Excel') do
        MH::Rename.auto_load_suggestions
        if defined?(MH::Rename::ViewportNameTool) && MH::Rename::ViewportNameTool.instance
          MH::Rename::ViewportNameTool.instance.reload_config
        end
        UI.messagebox("Đã tải lại Config (MH_Registry / Excel)")
      end
      cmd4.tooltip = 'Reload Excel Config'
      icon4 = File.join(icons_dir, 'reload_excel.svg')
      if File.exist?(icon4)
        cmd4.small_icon = icon4
        cmd4.large_icon = icon4
      end
      toolbar.add_item(cmd4)

      cmd5 = UI::Command.new('Viewport Names') { Sketchup.active_model.select_tool(MH::Rename::ViewportNameTool.new) }
      cmd5.tooltip = 'Show and Edit Names in Viewport'
      icon5 = File.join(icons_dir, 'viewport_names.svg')
      if File.exist?(icon5)
        cmd5.small_icon = icon5
        cmd5.large_icon = icon5
      end
      toolbar.add_item(cmd5)

      cmd6 = UI::Command.new('Rename Shortcut') { Sketchup.active_model.select_tool(MH::Rename::RenameShortcutTool.new) }
      cmd6.tooltip = 'Rename objects using shortcuts (1-9)'
      icon6 = File.join(icons_dir, 'rename_shortcut.svg')
      if File.exist?(icon6)
        cmd6.small_icon = icon6
        cmd6.large_icon = icon6
      end
      toolbar.add_item(cmd6)

      toolbar.restore
    end

    def self.focus_active_dialog
      # Ưu tiên focus vào rename dialog của Viewport Name Tool nếu đang mở
      vpt = ViewportNameTool.instance rescue nil
      if vpt
        rd = vpt.instance_variable_get(:@rename_dialog) rescue nil
        if rd && rd.visible?
          rd.bring_to_front
          rd.execute_script("setTimeout(function(){var t=document.getElementById('sfx')||document.getElementById('pfx'); if(t){t.focus();t.select();}}, 150);")
          return
        end
        
        md = vpt.instance_variable_get(:@dialog) rescue nil
        if md && md.visible?
          md.bring_to_front
          md.execute_script("setTimeout(function(){var t=document.getElementById('searchInput'); if(t){t.focus();t.select();}}, 150);")
          return
        end
      end
      
      if @dialog&.visible?
        @dialog.bring_to_front
        @dialog.execute_script("setTimeout(function(){var t=document.getElementById('suffix')||document.getElementById('new_name'); if(t) t.focus();}, 150);")
      elsif @qp_dialog&.visible?
        @qp_dialog.bring_to_front
        @qp_dialog.execute_script("setTimeout(function(){var t=document.getElementById('pfx'); if(t) t.focus();}, 150);")
      elsif @qr_dialog&.visible?
        @qr_dialog.bring_to_front
        @qr_dialog.execute_script("setTimeout(function(){var t=document.getElementById('name'); if(t) t.focus();}, 150);")
      end
    end

    def self.reload
      load File.join(__dir__, 'name_parser.rb')
      load File.join(__dir__, 'viewport_name.rb')
      load File.join(__dir__, File.basename(__FILE__))
      dbg 'MH::Rename reloaded'
    end

    # ── startup ──────────────────────────────────────────────────────────────
    auto_load_suggestions
    load_settings

  end
end

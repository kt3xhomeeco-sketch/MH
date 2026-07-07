# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require 'set'
require File.join(Sketchup.find_support_file('Plugins'), 'MH_shared.rb')
raise "MH::SelectSimilar requires MH_shared" unless defined?(MH::Shared) && defined?(MH::ModelHub) && defined?(MH::Bounds)

module MH
  module SelectSimilar
    DEBUG = false unless const_defined?(:DEBUG, false)

    def self.dbg(message)
      puts message if DEBUG
    end

    class << self
      old_bounds_method = %w[get_world_bounds cached].join('_').to_sym
      remove_method(old_bounds_method) if method_defined?(old_bounds_method)
    end

    class << self
      attr_accessor :current_tool

      # Global isolate state
      def isolated?; @isolated ||= false; end
      def hidden_entities; @hidden_entities ||= []; end
      
      def toggle_isolate
        @last_isolate_time ||= 0
        return if Time.now.to_f - @last_isolate_time < 0.2
        @last_isolate_time = Time.now.to_f
        
        isolated? ? unisolate : isolate
      end
      
      def isolate
        model = Sketchup.active_model
        return unless model
        
        selected_set = model.selection.to_a.to_set
        return if selected_set.empty?
        
        model.start_operation("Isolate Objects", true)
        
        @hidden_entities = []
        model.active_entities.each do |e|
          next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          next if selected_set.include?(e)
          next if e.hidden?
          
          e.hidden = true
          @hidden_entities << e
        end
        
        model.commit_operation
        @isolated = true
        Sketchup.status_text = "Isolated #{selected_set.length} objects (#{@hidden_entities.length} hidden)"
      end
      
      def unisolate
        return unless isolated?
        
        model = Sketchup.active_model
        model.start_operation("Unisolate Objects", true)
        
        @hidden_entities ||= []
        @hidden_entities.each do |e|
          begin
            e.hidden = false if e.valid?
          rescue
          end
        end
        
        model.commit_operation
        @hidden_entities = []
        @isolated = false
        Sketchup.status_text = "Unisolated - all objects visible"
      end
    end

    # =========================================================================
    # BOUNDS CACHE - Avoid redundant geometry calculations
    # =========================================================================
    @bounds_cache = {}

    def self.bounds_dims(entity)
      eid = MH::Bounds.entity_key(entity)
      return @bounds_cache[eid] if @bounds_cache.key?(eid)
      dims = MH::Bounds.dims(entity)
      @bounds_cache[eid] = dims
      dims
    end

    def self.invalidate_bounds_cache
      @bounds_cache.clear
      MH::Bounds.clear!
    end

    # =========================================================================
    # SETTINGS STORAGE
    # =========================================================================
    @settings = {
      partial_name: true,
      name_search: '',          # Text to search for in names
      bounding_size: true,
      bounding_volume: false,
      min_thickness: true,
      same_material: true,
      same_tag: true,
      size_tolerance: 5.0,
      volume_tolerance: 5.0,
      thickness_tolerance: 2.0,  # mm absolute tolerance for min thickness
      type_filter: 'both',      # 'group', 'component', 'both'
      scope_filter: 'all',      # 'visible', 'all', 'viewport', 'viewport_visible'
      nesting_filter: 'nested', # 'toplevel', 'nested'
      size_mode: 0,             # 0=dim1, 1=dim2, 2=both (cycles on shift+click)
      min_size_threshold: 0,    # mm, 0=disabled, objects with largest dim >= this value
      min_all_size_threshold: 0, # mm, 0=disabled, objects with ALL dims >= this value
      name_group: false         # If true, includes prefix and suffix in progressive search
    }
    
    # Editable suggestions for prefix/modul/suffix/search
    @prefix_suggestions = []
    @modul_suggestions = ['T?m  ?ng', 'T?m Ngang', 'V ch', 'K?', 'Ngan K o', 'C?a']
    @suffix_suggestions = ['_L', '_R', '_A', '_B', '_Top', '_Bot', '_NEW']
    @search_suggestions = ['Tấm, (Hậu)', 'Hậu, *T<7*', 'Cánh, *T>15*']
    @quick_search_items = []
    @quick_search_shortcuts = {}
    
    def self.search_suggestions
      @search_suggestions
    end
    
    def self.search_suggestions=(val)
      rebuild_quick_search_items(Array(val).map(&:to_s))
    end

    def self.quick_search_items
      rebuild_quick_search_items(@search_suggestions || []) if @quick_search_items.nil? || @quick_search_items.empty?
      @quick_search_items
    end

    def self.quick_search_items=(items)
      normalized = []
      Array(items).first(1000).each_with_index do |item, index|
        if item.is_a?(Hash)
          text = (item[:text] || item['text'] || item[:value] || item['value']).to_s.strip
          shortcut = normalize_quick_search_shortcut(item[:shortcut] || item['shortcut'])
        else
          text = item.to_s.strip
          shortcut = nil
        end
        next if text.empty?
        shortcut ||= format('%03d', index)
        normalized << { shortcut: shortcut, text: text }
      end
      @quick_search_items = normalized
      @search_suggestions = normalized.map { |item| item[:text] }
      rebuild_quick_search_shortcuts
    end

    def self.quick_search_shortcuts
      quick_search_items
      @quick_search_shortcuts
    end

    def self.normalize_quick_search_shortcut(value)
      text = value.to_s.strip
      return nil unless text =~ /\A\d{1,3}\z/
      number = text.to_i
      return nil unless number >= 0 && number <= 999
      format('%03d', number)
    end

    def self.quick_search_label(item_or_index, text = nil)
      if item_or_index.is_a?(Hash)
        shortcut = item_or_index[:shortcut] || item_or_index['shortcut']
        value = item_or_index[:text] || item_or_index['text']
      else
        shortcut = format('%03d', item_or_index.to_i)
        value = text
      end
      "#{shortcut}  #{value}"
    end

    def self.rebuild_quick_search_items(lines)
      @search_suggestions = Array(lines).map(&:to_s).map(&:strip).reject(&:empty?)
      @quick_search_items = @search_suggestions.first(1000).each_with_index.map do |text, index|
        { shortcut: format('%03d', index), text: text }
      end
      rebuild_quick_search_shortcuts
    end

    def self.rebuild_quick_search_shortcuts
      @quick_search_shortcuts = {}
      Array(@quick_search_items).each do |item|
        shortcut = normalize_quick_search_shortcut(item[:shortcut])
        next unless shortcut
        @quick_search_shortcuts[shortcut] ||= item[:text].to_s
      end
      @quick_search_shortcuts
    end

    def self.quick_search_header_row?(row)
      cells = Array(row).map { |cell| cell.to_s.strip.downcase }
      return false if cells.empty?
      first = cells[0]
      second = cells[1]
      first =~ /\A(shortcut|key|phim|số|so|stt|index)\z/ ||
        second =~ /\A(search|quick search|name_search|name search|keyword|noi dung|nội dung)\z/
    end

    def self.parse_quick_search_rows(rows)
      items = []
      fallback_index = 0

      Array(rows).each do |row|
        cells = Array(row).map { |cell| cell.to_s.strip }
        next if cells.all?(&:empty?)
        next if quick_search_header_row?(cells)

        shortcut = normalize_quick_search_shortcut(cells[0])
        if shortcut && !cells[1].to_s.empty?
          text = cells[1].to_s
        else
          text = cells[0].to_s
          shortcut = format('%03d', fallback_index)
        end

        next if text.empty?
        items << { shortcut: shortcut, text: text }
        fallback_index += 1
      end

      items.first(1000)
    end
    
    def self.prefix_suggestions
      @prefix_suggestions
    end
    
    def self.prefix_suggestions=(val)
      @prefix_suggestions = val
    end
    
    def self.modul_suggestions
      @modul_suggestions
    end
    
    def self.modul_suggestions=(val)
      @modul_suggestions = val
    end
    
    def self.suffix_suggestions
      @suffix_suggestions
    end
    
    def self.suffix_suggestions=(val)
      @suffix_suggestions = val
    end
    
    def self.ensure_settings_facade
      return true if defined?(MH::Settings)
      plugins_dir = defined?(Sketchup) ? Sketchup.find_support_file('Plugins') : File.dirname(File.dirname(__FILE__))
      path = File.join(plugins_dir, 'MH_shared.rb')
      load path if File.exist?(path)
      defined?(MH::Settings)
    rescue => e
      dbg("MH::SelectSimilar: Settings facade error: #{e.message}")
      false
    end

    def self.load_suggestions_from_settings
      return false unless ensure_settings_facade
      items = MH::Settings.read('select_similar', 'quick_search_items', [], scope: :global)
      return false unless items.is_a?(Array) && items.any?
      self.quick_search_items = items
      dbg("MH::SelectSimilar: Loaded #{quick_search_items.length} suggestions from JSON settings")
      true
    rescue => e
      dbg("MH::SelectSimilar: Error loading JSON suggestions: #{e.message}")
      false
    end

    # Load suggestions from JSON settings first, then legacy Excel (sheet 'suggestions').
    def self.load_suggestions_from_excel
      return true if load_suggestions_from_settings

      excel_path = File.join(File.dirname(__FILE__), 'config.xlsx')
      unless File.exist?(excel_path)
        dbg("MH::SelectSimilar: Excel config not found at #{excel_path}")
        return false
      end

      dbg("MH::SelectSimilar: Loading suggestions from Excel...")
      
      begin
        rows = MH::ExcelBridge.read_sheet(excel_path, sheet: 'suggestions')
        items = parse_quick_search_rows(rows)
        if items.any?
          @quick_search_items = items
          @search_suggestions = items.map { |item| item[:text] }
          rebuild_quick_search_shortcuts
          dbg("MH::SelectSimilar: Loaded #{items.length} suggestions from Excel")
          return true
        end
      rescue => e
        dbg("MH::SelectSimilar: Error loading from Excel: #{e.message}")
      end
      false
    end

    # Load suggestions from txt file (one item per line)
    def self.load_prefix_from_file(filepath = nil)
      filepath ||= File.join(File.dirname(__FILE__), 'prefix_suggestions.txt')
      load_suggestions_from_file(filepath, :prefix)
    end
    
    def self.load_suffix_from_file(filepath = nil)
      filepath ||= File.join(File.dirname(__FILE__), 'suffix_suggestions.txt')
      load_suggestions_from_file(filepath, :suffix)
    end
    
    def self.load_modul_from_file(filepath = nil)
      filepath ||= File.join(File.dirname(__FILE__), 'modul_suggestions.txt')
      load_suggestions_from_file(filepath, :modul)
    end
    
    def self.load_suggestions_from_file(filepath, type)
      unless File.exist?(filepath)
        dbg("File not found: #{filepath}")
        return false
      end
      
      lines = File.readlines(filepath, encoding: 'UTF-8').map(&:strip).reject(&:empty?)
      
      case type
      when :prefix
        @prefix_suggestions = []
        dbg("Ignored prefix suggestions from #{filepath}; product code uses MH::NameGrammar")
      when :modul
        @modul_suggestions = lines
        dbg("Loaded #{lines.length} modul suggestions from #{filepath}")
      when :search
        rebuild_quick_search_items(lines)
        dbg("Loaded #{lines.length} search suggestions from #{filepath}")
      else
        @suffix_suggestions = lines
        dbg("Loaded #{lines.length} suffix suggestions from #{filepath}")
      end
      true
    end
    
    # Import from file via dialog
    def self.import_prefix_file
      filepath = UI.openpanel("Select Prefix Suggestions File", "", "Text Files|*.txt||")
      load_prefix_from_file(filepath) if filepath
    end
    
    def self.import_suffix_file
      filepath = UI.openpanel("Select Suffix Suggestions File", "", "Text Files|*.txt||")
      load_suffix_from_file(filepath) if filepath
    end
    
    def self.import_modul_file
      filepath = UI.openpanel("Select Modul Suggestions File", "", "Text Files|*.txt||")
      load_modul_from_file(filepath) if filepath
    end
    
    # Auto-load suggestions from default files on startup
    def self.auto_load_suggestions
      prefix_file = File.join(File.dirname(__FILE__), 'prefix_suggestions.txt')
      modul_file = File.join(File.dirname(__FILE__), 'modul_suggestions.txt')
      suffix_file = File.join(File.dirname(__FILE__), 'suffix_suggestions.txt')
      search_file = File.join(File.dirname(__FILE__), 'search_suggestions.txt')
      
      load_prefix_from_file(prefix_file) if File.exist?(prefix_file)
      load_modul_from_file(modul_file) if File.exist?(modul_file)
      load_suffix_from_file(suffix_file) if File.exist?(suffix_file)
      
      # Try Excel first for search suggestions
      unless load_suggestions_from_excel
        load_suggestions_from_file(search_file, :search) if File.exist?(search_file)
      end
    end

    def self.settings
      @settings
    end

    def self.settings=(val)
      apply_settings(val, persist: true)
    end

    def self.apply_settings(val, persist: true)
      @settings = val
      save_settings if persist
    end
    
    # Preferences key for storing settings
    PREFS_KEY = 'MH_Test6'
    
    # Save settings to SketchUp defaults (persistent)
    def self.save_settings
      @settings.each do |key, value|
        Sketchup.write_default(PREFS_KEY, key.to_s, value)
      end
    end
    
    # Load settings from SketchUp defaults
    def self.load_settings
      @settings.each_key do |key|
        saved_value = Sketchup.read_default(PREFS_KEY, key.to_s, nil)
        if saved_value != nil
          # Convert back to correct type
          case @settings[key]
          when TrueClass, FalseClass
            @settings[key] = (saved_value == true || saved_value == 'true')
          when Integer
            @settings[key] = saved_value.to_i
          when Float
            @settings[key] = saved_value.to_f
          else
            @settings[key] = saved_value
          end
        end
      end
      dbg("MH::SelectSimilar: Settings loaded from preferences")
    end

    # =========================================================================
    # HELPER METHODS
    # =========================================================================

    # Clean name by removing ID prefix like "_956. " or "__001. " or "__001."
    def self.clean_name(name)
      return '' if name.nil?
      MH::Text.strip_sys_prefix(name)
    end

    # Extract keyword for searching by removing prefix and ID
    def self.extract_search_keyword(name)
      return '' if name.nil?
      
      clean = clean_name(name)
      
      # 1. Strip Prefix
      loop do
        found = false
        (@prefix_suggestions || []).each do |p|
          if clean.downcase.start_with?(p.downcase)
            clean = clean[p.length..-1]
            sm = clean.match(/^[.\-_\s]+/)
            clean = clean[sm[0].length..-1] if sm
            found = true
            break
          end
        end
        
        unless found
          code = defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:first_product) ? MH::NameGrammar.first_product(clean).to_s : ''
          if !code.empty? && clean.upcase.start_with?(code.upcase)
            clean = clean[code.length..-1].to_s.sub(/\A[.\-_\s]+/, '')
            found = true
          end
        end
        break unless found
      end
      
      # 2. Strip IDs (numeric tokens like '01', '02' and their preceding separators)
      # Exception: Preserve numeric tokens preceded by a dot (e.g. .1, .2) as they are likely module indices, not instance IDs
      tokens = clean.split(/([.\-_\s]+)/)
      res = []
      tokens.each do |tok|
        if tok.match?(/^\d+$/)
          if res.last == '.'
            res << tok
          else
            res.pop if res.last && res.last.match?(/^[.\-_\s]+$/)
          end
        else
          res << tok
        end
      end
      
      clean = res.join
      clean.sub!(/^[.\-_\s]+/, '')
      clean.sub!(/[.\-_\s]+$/, '')
      
      clean
    end

    # Similar to extract_search_keyword but KEEPS the prefix
    def self.extract_name_group_keyword(name)
      return '' if name.nil?
      
      clean = clean_name(name)
      
      # Strip IDs (numeric tokens like '01', '02' and their preceding separators)
      # Exception: Preserve numeric tokens preceded by a dot (e.g. .1, .2) as they are likely module indices, not instance IDs
      tokens = clean.split(/([.\-_\s]+)/)
      res = []
      tokens.each do |tok|
        if tok.match?(/^\d+$/)
          if res.last == '.'
            res << tok
          else
            res.pop if res.last && res.last.match?(/^[.\-_\s]+$/)
          end
        else
          res << tok
        end
      end
      
      clean = res.join
      clean.sub!(/^[.\-_\s]+/, '')
      clean.sub!(/[.\-_\s]+$/, '')
      
      clean
    end

    # Get LOCAL bounding box dimensions (actual size, not affected by rotation)
    # For panels: analyzes faces to find actual solid dimensions
    # For components: uses definition bounds with proper scale extraction
    # For groups: uses local_bounds with proper scale extraction
    def self.get_world_bounds(entity, debug = false)
      entity_name = entity.respond_to?(:name) ? entity.name : (entity.definition.name rescue "unknown")
      
      # Try to get panel dimensions from face analysis first
      panel_dims = get_panel_dimensions_from_faces(entity)
      
      if panel_dims && panel_dims[0] > 0
        if debug
          dbg("[BOUNDS DEBUG] #{entity_name} - Using FACE ANALYSIS")
          dbg("  panel dims: #{panel_dims[0].to_mm.round(1)}, #{panel_dims[1].to_mm.round(1)}, #{panel_dims[2].to_mm.round(1)} mm")
        end
        return panel_dims.sort
      end
      
      # Fallback to bounding box method
      if entity.is_a?(Sketchup::ComponentInstance)
        bounds = entity.definition.bounds
        return nil if bounds.empty?
        
        transformation = entity.transformation
        min_pt = bounds.min
        max_pt = bounds.max
        
        local_x = max_pt.x - min_pt.x
        local_y = max_pt.y - min_pt.y
        local_z = max_pt.z - min_pt.z
        
        scale_x = Geom::Vector3d.new(transformation.xaxis).length
        scale_y = Geom::Vector3d.new(transformation.yaxis).length
        scale_z = Geom::Vector3d.new(transformation.zaxis).length
        
        dim1 = local_x * scale_x
        dim2 = local_y * scale_y
        dim3 = local_z * scale_z
        
        if debug
          dbg("[BOUNDS DEBUG] #{entity_name} (Component) - Using BOUNDS")
          dbg("  final dims: #{dim1.to_mm.round(1)}, #{dim2.to_mm.round(1)}, #{dim3.to_mm.round(1)} mm")
        end
        
      elsif entity.is_a?(Sketchup::Group)
        bounds = entity.local_bounds
        return nil if bounds.empty?
        
        min_pt = bounds.min
        max_pt = bounds.max
        
        local_x = max_pt.x - min_pt.x
        local_y = max_pt.y - min_pt.y
        local_z = max_pt.z - min_pt.z
        
        transformation = entity.transformation
        scale_x = Geom::Vector3d.new(transformation.xaxis).length
        scale_y = Geom::Vector3d.new(transformation.yaxis).length
        scale_z = Geom::Vector3d.new(transformation.zaxis).length
        
        dim1 = local_x * scale_x
        dim2 = local_y * scale_y
        dim3 = local_z * scale_z
        
        if debug
          dbg("[BOUNDS DEBUG] #{entity_name} (Group) - Using BOUNDS")
          dbg("  final dims: #{dim1.to_mm.round(1)}, #{dim2.to_mm.round(1)}, #{dim3.to_mm.round(1)} mm")
        end
        
      else
        bounds = entity.bounds
        return nil if bounds.empty?
        
        dim1 = bounds.width
        dim2 = bounds.depth
        dim3 = bounds.height
      end
      
      [dim1, dim2, dim3].sort
    end
    
    # Analyze faces to get actual panel dimensions
    # Returns [thickness, width, length] or nil if cannot determine
    def self.get_panel_dimensions_from_faces(entity)
      # Collect all faces from the entity
      faces = collect_all_faces(entity)
      return nil if faces.empty? || faces.length < 2
      
      # Group faces by their normal direction (parallel faces)
      # We're looking for pairs of parallel faces to determine thickness
      face_groups = {}
      
      faces.each do |face|
        normal = face[:normal]
        # Round normal to handle floating point precision
        key = [normal.x.round(4), normal.y.round(4), normal.z.round(4)]
        # Also consider opposite normal (parallel but facing opposite)
        neg_key = [(-normal.x).round(4), (-normal.y).round(4), (-normal.z).round(4)]
        
        if face_groups[neg_key]
          # Add to existing group (opposite direction)
          face_groups[neg_key] << face
        elsif face_groups[key]
          face_groups[key] << face
        else
          face_groups[key] = [face]
        end
      end
      
      # Find the largest faces (main panel faces) and their thickness
      largest_face_area = 0
      panel_thickness = nil
      panel_face = nil
      
      face_groups.each do |key, group_faces|
        next if group_faces.length < 2
        
        # Sort by area to find largest faces
        sorted = group_faces.sort_by { |f| -f[:area] }
        
        # Use the two largest parallel/opposite faces
        if sorted[0][:area] > largest_face_area
          # Calculate distance between these parallel faces
          f1_center = sorted[0][:center]
          f2_center = sorted[1][:center] if sorted[1]
          
          if f2_center
            # Distance along the normal direction
            normal = sorted[0][:normal]
            dist = ((f1_center.x - f2_center.x) * normal.x +
                    (f1_center.y - f2_center.y) * normal.y +
                    (f1_center.z - f2_center.z) * normal.z).abs
            
            if dist > 0.001  # More than 0.001 inches (avoid zero)
              largest_face_area = sorted[0][:area]
              panel_thickness = dist
              panel_face = sorted[0]
            end
          end
        end
      end
      
      return nil unless panel_thickness && panel_face
      
      # Get the dimensions from the largest face's bounding box
      face_bounds = panel_face[:bounds]
      dims = [face_bounds[:width], face_bounds[:height], panel_thickness]
      
      dims.sort
    end
    
    # Collect all faces from an entity (recursive)
    def self.collect_all_faces(entity, transform = nil)
      faces = []
      transform ||= Geom::Transformation.new
      
      entities = if entity.is_a?(Sketchup::ComponentInstance)
                   entity.definition.entities
                 elsif entity.is_a?(Sketchup::Group)
                   entity.entities
                 else
                   return faces
                 end
      
      # Apply entity transformation
      if entity.respond_to?(:transformation)
        transform = transform * entity.transformation
      end
      
      entities.each do |e|
        if e.is_a?(Sketchup::Face)
          # Transform face data to world coordinates
          normal = e.normal.transform(transform)
          normal.normalize!
          
          # Get face center
          center = e.bounds.center.transform(transform)
          
          # Get face bounds for width/height
          corners = [e.bounds.corner(0), e.bounds.corner(1), 
                     e.bounds.corner(2), e.bounds.corner(3),
                     e.bounds.corner(4), e.bounds.corner(5),
                     e.bounds.corner(6), e.bounds.corner(7)]
          
          transformed_corners = corners.map { |c| c.transform(transform) }
          
          min_x = transformed_corners.map(&:x).min
          max_x = transformed_corners.map(&:x).max
          min_y = transformed_corners.map(&:y).min
          max_y = transformed_corners.map(&:y).max
          min_z = transformed_corners.map(&:z).min
          max_z = transformed_corners.map(&:z).max
          
          face_width = [max_x - min_x, max_y - min_y, max_z - min_z].sort[1]  # middle dimension
          face_height = [max_x - min_x, max_y - min_y, max_z - min_z].max
          
          faces << {
            normal: normal,
            center: center,
            area: e.area,
            bounds: { width: face_width, height: face_height }
          }
        elsif e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          # Recurse into nested groups/components
          faces.concat(collect_all_faces(e, transform))
        end
      end
      
      faces
    end

    # Get material of entity
    def self.get_material(entity)
      return entity.material if entity.respond_to?(:material)
      nil
    end

    # Get tag/layer of entity
    def self.get_tag(entity)
      return entity.layer if entity.respond_to?(:layer)
      nil
    end

    # Check if entity's bounding box is visible in the current viewport
    def self.entity_in_viewport?(entity, view)
      return false unless entity.respond_to?(:bounds)
      bounds = entity.bounds
      return false if bounds.empty?
      
      # Get the 8 corners of the bounding box
      corners = [
        bounds.corner(0), bounds.corner(1), bounds.corner(2), bounds.corner(3),
        bounds.corner(4), bounds.corner(5), bounds.corner(6), bounds.corner(7)
      ]
      
      # Check if any corner is within the viewport
      vp_width = view.vpwidth
      vp_height = view.vpheight
      
      corners.each do |corner|
        screen_pt = view.screen_coords(corner)
        x, y = screen_pt.x, screen_pt.y
        
        # Check if the point is in front of camera and within viewport bounds
        if x >= 0 && x <= vp_width && y >= 0 && y <= vp_height
          # Additional check: ensure point is in front of camera
          eye = view.camera.eye
          direction = view.camera.direction
          to_point = corner - eye
          dot = to_point.x * direction.x + to_point.y * direction.y + to_point.z * direction.z
          return true if dot > 0
        end
      end
      
      # Also check if the center is visible
      center = bounds.center
      screen_center = view.screen_coords(center)
      cx, cy = screen_center.x, screen_center.y
      if cx >= 0 && cx <= vp_width && cy >= 0 && cy <= vp_height
        eye = view.camera.eye
        direction = view.camera.direction
        to_center = center - eye
        dot = to_center.x * direction.x + to_center.y * direction.y + to_center.z * direction.z
        return true if dot > 0
      end
      
      false
    end

    # Collect all groups/components from model
    def self.collect_entities(scope, nesting, model)
      entities = []
      
      # Determine if we need visible-only filtering
      visible_only = (scope == 'visible' || scope == 'viewport_visible')
      
      if visible_only
        source = model.active_entities
      else
        source = model.entities
      end
      
      entities = MH::ModelHub.scan(
        root: source,
        types: %i[group component],
        depth: nesting == 'toplevel' ? 1 : -1,
        include_hidden: true
      )
      entities = entities.reject { |e| e.respond_to?(:hidden?) && e.hidden? } if visible_only
      
      # Filter by viewport if scope includes viewport
      if scope == 'viewport' || scope == 'viewport_visible'
        view = model.active_view
        entities = entities.select { |e| entity_in_viewport?(e, view) }
      end
      
      # Filter by min size threshold if enabled (largest dim >= threshold)
      min_size = @settings[:min_size_threshold].to_f
      if min_size > 0
        entities = entities.select do |e|
          dims = bounds_dims(e)
          next false unless dims
          largest_dim = dims[2]  # Sorted, so [2] is largest
          largest_dim.to_mm >= min_size
        end
      end
      
      # Filter by min ALL size threshold if enabled (ALL dims >= threshold)
      min_all_size = @settings[:min_all_size_threshold].to_f
      if min_all_size > 0
        entities = entities.select do |e|
          dims = bounds_dims(e)
          next false unless dims
          # All dimensions must be >= min_all_size
          dims.all? { |d| d.to_mm >= min_all_size }
        end
      end
      
      entities
    end

    # Check if two values match within tolerance (percentage-based)
    def self.within_tolerance?(val1, val2, tolerance_percent)
      return true if val1 == 0 && val2 == 0
      return false if val1 == 0 || val2 == 0
      diff = (val1 - val2).abs / [val1, val2].max.to_f
      diff <= (tolerance_percent / 100.0)
    end
    
    # Check if two thickness values match within absolute tolerance (mm)
    def self.thickness_matches?(val1_inches, val2_inches, tolerance_mm)
      val1_mm = val1_inches.to_mm
      val2_mm = val2_inches.to_mm
      diff_mm = (val1_mm - val2_mm).abs
      diff_mm <= tolerance_mm
    end

    # Find longest common prefix (characters matching from start)
    def self.find_common_name(objects)
      names = objects.map { |o| clean_name(o.respond_to?(:name) ? o.name : o.definition.name) }
      names = names.reject(&:empty?)
      return '' if names.empty?
      return names.first if names.length == 1
      
      # Find longest common prefix character by character
      shortest = names.min_by(&:length)
      common_prefix = ''
      
      shortest.each_char.with_index do |char, idx|
        # Check if all names have this character at this position
        if names.all? { |n| n[idx] && n[idx].downcase == char.downcase }
          common_prefix += shortest[idx]  # Use original case from shortest
        else
          break  # Stop at first mismatch
        end
      end
      
      # Only trim trailing spaces (keep underscore for prefixes like SP44_)
      common_prefix.sub(/\s+$/, '')
    end
    
    # Find name template with common prefix, common suffix and [original name] for different parts
    # Returns: { template: "SP_T?m  ?ng_[original name]", common_prefix: "SP_T?m  ?ng_", common_suffix: "", unique_parts: ["A", "B", "C"] }
    def self.find_name_template(objects)
      names = objects.map { |o| clean_name(o.respond_to?(:name) ? o.name : o.definition.name) }
      names = names.reject(&:empty?)
      
      return { template: '[original name]', common_prefix: '', common_suffix: '', unique_parts: names } if names.empty?
      return { template: names.first, common_prefix: names.first, common_suffix: '', unique_parts: [''] } if names.length == 1
      
      # Find longest common prefix
      shortest = names.min_by(&:length)
      common_prefix = ''
      
      shortest.each_char.with_index do |char, idx|
        if names.all? { |n| n[idx] && n[idx].downcase == char.downcase }
          common_prefix += shortest[idx]
        else
          break
        end
      end
      
      # Find longest common suffix (from end)
      # First, remove common prefix from all names
      names_without_prefix = names.map { |n| n[common_prefix.length..-1] || '' }
      
      # Now find common suffix from the end
      shortest_remaining = names_without_prefix.min_by(&:length)
      common_suffix = ''
      
      if shortest_remaining && !shortest_remaining.empty?
        shortest_remaining.reverse.each_char.with_index do |char, idx|
          pos_from_end = idx + 1
          if names_without_prefix.all? { |n| 
               n.length >= pos_from_end && n[-pos_from_end] && n[-pos_from_end].downcase == char.downcase 
             }
            common_suffix = shortest_remaining[-pos_from_end] + common_suffix
          else
            break
          end
        end
      end
      
      # Calculate unique parts for each name
      unique_parts = names.map do |name|
        after_prefix = name[common_prefix.length..-1] || ''
        if common_suffix.empty?
          after_prefix
        else
          # Remove suffix from end
          after_prefix.length > common_suffix.length ? after_prefix[0..-(common_suffix.length + 1)] : ''
        end
      end
      
      # Build template
      if unique_parts.all?(&:empty?)
        # All names are identical
        template = common_prefix + common_suffix
      else
        template = common_prefix + '[original name]' + common_suffix
      end
      
      { 
        template: template, 
        common_prefix: common_prefix, 
        common_suffix: common_suffix, 
        unique_parts: unique_parts 
      }
    end

    def self.matches_criteria?(ref, target, settings, ref_dims: nil, target_dims: nil)
      return false if ref == target
      
      # === CHEAP CHECKS FIRST (no geometry calculation needed) ===
      
      # Type filter
      case settings[:type_filter]
      when 'group'
        return false unless target.is_a?(Sketchup::Group)
      when 'component'
        return false unless target.is_a?(Sketchup::ComponentInstance)
      end
      
      # Advanced Name search (Global) - only when partial_name is enabled
      if settings[:partial_name] && !settings[:name_search].to_s.strip.empty?
        return false unless advanced_match?(target, settings[:name_search])
      end
      
      # Same material (cheap - object comparison)
      if settings[:same_material]
        return false unless get_material(ref) == get_material(target)
      end
      
      # Same tag (cheap - object comparison)
      if settings[:same_tag]
        return false unless get_tag(ref) == get_tag(target)
      end
      
      # === EXPENSIVE CHECKS (bounds - compute once, reuse) ===
      needs_bounds = settings[:bounding_size] || settings[:bounding_volume] || settings[:min_thickness]
      
      if needs_bounds
        ref_dims ||= bounds_dims(ref)
        target_dims ||= bounds_dims(target)
      end
      
      # Min thickness
      if settings[:min_thickness]
        if ref_dims && target_dims
          diff = (ref_dims[0].to_mm - target_dims[0].to_mm).abs
          return false unless diff <= settings[:thickness_tolerance]
        end
      end
      
      # Bounding size - match based on size_mode
      if settings[:bounding_size]
        if ref_dims && target_dims
          size_mode = settings[:size_mode] || 0
          tol = settings[:size_tolerance]
          
          case size_mode
          when 0
            return false unless target_dims.any? { |d| within_tolerance?(ref_dims[1], d, tol) }
          when 1
            return false unless target_dims.any? { |d| within_tolerance?(ref_dims[2], d, tol) }
          when 2
            found_mid = target_dims.any? { |d| within_tolerance?(ref_dims[1], d, tol) }
            found_max = target_dims.any? { |d| within_tolerance?(ref_dims[2], d, tol) }
            return false unless found_mid && found_max
          when 3
            found_mid = target_dims.any? { |d| within_tolerance?(ref_dims[1], d, tol) }
            found_max = target_dims.any? { |d| within_tolerance?(ref_dims[2], d, tol) }
            return false unless found_mid || found_max
          end
        end
      end
      
      # Bounding volume
      if settings[:bounding_volume]
        if ref_dims && target_dims
          ref_vol = ref_dims.reduce(:*)
          target_vol = target_dims.reduce(:*)
          return false unless within_tolerance?(ref_vol, target_vol, settings[:volume_tolerance])
        end
      end
      
      true
    end

    # Advanced Search Logic
    # query: "từ1, từ2, (loại trừ), *T>7*, *6<L<500*"
    def self.advanced_match?(target, query_string)
      return true if query_string.to_s.strip.empty?
      
      # Get dimensions for formula checks
      dims = bounds_dims(target) # [T, W, L]
      return false unless dims
      
      t_val = dims[0].to_mm
      w_val = dims[1].to_mm
      l_val = dims[2].to_mm
      
      target_name = clean_name(target.respond_to?(:name) ? target.name : target.definition.name).downcase
      
      segments = query_string.split(',').map(&:strip).reject(&:empty?)
      
      include_terms = []
      exclude_terms = []
      exact_exclude_terms = []
      formulas = []
      
      segments.each do |seg|
        if seg.start_with?('(') && seg.end_with?(')')
          term = seg[1...-1].strip.downcase
          if term.start_with?('=')
            exact_exclude_terms << term[1..-1].to_s.strip
          else
            exclude_terms << term
          end
        elsif seg.start_with?('*') && seg.end_with?('*')
          formulas << seg[1...-1].strip.upcase
        else
          include_terms << seg.downcase
        end
      end
      
      # 1. Check Exclusions (Must NOT match any)
      exclude_terms.each do |term|
        return false if target_name.include?(term)
      end

      exact_exclude_terms.each do |term|
        return false if target_name == term
      end
      
      # 2. Check Formulas (Must match ALL)
      formulas.each do |formula|
        return false unless evaluate_formula(formula, t_val, w_val, l_val)
      end
      
      # 3. Check Include terms (Must match at least one if any exist)
      if !include_terms.empty?
        return include_terms.any? { |term| target_name.include?(term) }
      end
      
      true
    end

    def self.evaluate_formula(formula, t, w, l)
      # Normalize L, W, T and D (as requested in example *6>D>500*)
      # Map D to L (longest)
      vars = { 'T' => t, 'W' => w, 'L' => l, 'D' => l }
      
      # Case 1: Double comparison like *6<L<500* or *500>L>6*
      if formula =~ /^(\d+\.?\d*)\s*([<>]=?|=)\s*([LWTD])\s*([<>]=?|=)\s*(\d+\.?\d*)$/
        val1 = $1.to_f
        op1 = $2
        var = vars[$3]
        op2 = $4
        val2 = $5.to_f
        
        return (compare(val1, op1, var) && compare(var, op2, val2))
      end
      
      # Case 2: Simple comparison like *T>7*
      if formula =~ /^([LWTD])\s*([<>]=?|=)\s*(\d+\.?\d*)$/
        var = vars[$1]
        op = $2
        val = $3.to_f
        return compare(var, op, val)
      end

      # Case 3: Reversed simple like *7<T*
      if formula =~ /^(\d+\.?\d*)\s*([<>]=?|=)\s*([LWTD])$/
        val = $1.to_f
        op = $2
        var = vars[$3]
        return compare(val, op, var)
      end
      
      false
    rescue
      false
    end

    def self.compare(v1, op, v2)
      case op
      when '>'  then v1 > v2
      when '<'  then v1 < v2
      when '>=' then v1 >= v2
      when '<=' then v1 <= v2
      when '='  then (v1 - v2).abs < 0.001
      else false
      end
    end


    # =========================================================================
    # SELECT SIMILAR TOOL
    # =========================================================================
    class SelectSimilarTool
      def initialize
        @model = Sketchup.active_model
        @cursor_id = nil
        @settings_dialog = nil
        @rename_dialog = nil
        @mini_settings = nil
        @quick_search_buffer = ''
        @quick_search_token = 0
        
        # Progressive name search state
        @last_clicked_entity = nil       # Track last clicked entity
        @last_clicked_entity_id = nil    # Track entity ID for reliable comparison
        @click_depth = 0                 # Current depth of word search
        @name_tokens = []                # Parsed name tokens for progressive search
        
        # Cached entities for performance
        @cached_entities = nil
        @cache_time = nil
        @cache_max_age = 10  # Cache valid for 10 seconds
        
        # Overlay interaction state
        @overlay_hitboxes = []           # Clickable regions in overlay
        @hover_index = nil               # Index of hovered overlay item
        @mouse_x = 0
        @mouse_y = 0
        
        # Overlay filter state
        @overlay_snapshot = nil          # Frozen display lines (kept after filter)
        @active_filter = nil             # { type: :material, value: "MDF" } or nil
        
        # Overlay draw cache
        @overlay_dirty = true
        @cached_overlay_lines = nil
        @cached_overlay_count = 0
      end

      def activate
        MH::SelectSimilar.current_tool = self
        @model = Sketchup.active_model
        @selection = @model.selection
        
        # Pre-cache entities on activation and clear bounds cache
        MH::SelectSimilar.invalidate_bounds_cache
        refresh_entity_cache
        
        s = MH::SelectSimilar.settings
        
        # Auto-set name_search based on current selection (only if name search is enabled)
        refs = @selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
        if s[:partial_name] && refs.length > 0
          names = refs.map { |e| MH::SelectSimilar.extract_search_keyword(e.respond_to?(:name) ? e.name : e.definition.name) }
          names = names.reject(&:empty?).uniq
          if names.length > 0
            s[:name_search] = names.join(", ")
          end
        end
        
        search_term = s[:name_search].to_s.strip
        
        # If name search is enabled and has a value, auto-apply it immediately on activation
        if s[:partial_name] && !search_term.empty?
          trigger_live_search
        else
          # If objects already selected but name search is off, or no names found
          if refs.length > 0
            select_similar_multi(refs)
          end
        end
        
        Sketchup.status_text = "Select Similar: Click=select | Ctrl+Click=add ref | Shift+Click=size mode | Tab=settings | R=rename"
      end

      def deactivate(view)
        @settings_dialog.close if @settings_dialog && @settings_dialog.visible?
        @rename_dialog.close if @rename_dialog && @rename_dialog.visible?
        @mini_settings.close if @mini_settings && @mini_settings.visible?
        @cached_entities = nil  # Clear cache
        @similarity_index = nil
        @similarity_index_key = nil
        MH::SelectSimilar.invalidate_bounds_cache
        MH::SelectSimilar.unisolate if MH::SelectSimilar.isolated?  # Restore hidden objects on deactivate
        MH::SelectSimilar.current_tool = nil
      end
      
      # Refresh entity cache
      def refresh_entity_cache
        settings = MH::SelectSimilar.settings
        MH::SelectSimilar.invalidate_bounds_cache
        @cached_entities = MH::SelectSimilar.collect_entities(
          settings[:scope_filter],
          settings[:nesting_filter],
          @model
        )
        @cache_time = Time.now
        @similarity_index = nil
        @similarity_index_key = nil
        @overlay_dirty = true
      end
      
      # Get cached entities (refresh if too old)
      def get_cached_entities
        if @cached_entities.nil? || @cache_time.nil? || (Time.now - @cache_time) > @cache_max_age
          refresh_entity_cache
        end
        @cached_entities
      end

      def get_similarity_index(settings = MH::SelectSimilar.settings)
        entities = get_cached_entities
        needs_dimensions = settings[:bounding_size] || settings[:bounding_volume] || settings[:min_thickness]
        index_key = [entities.object_id, !!needs_dimensions]
        if @similarity_index.nil? || @similarity_index_key != index_key
          @similarity_index = MH::SimilarityIndex.new(
            entities,
            dimensions: (needs_dimensions ? ->(entity) { MH::SelectSimilar.bounds_dims(entity) } : nil),
            material: ->(entity) { MH::SelectSimilar.get_material(entity) },
            tag: ->(entity) { MH::SelectSimilar.get_tag(entity) },
            name: ->(entity) { entity.respond_to?(:name) ? entity.name : entity.definition.name }
          )
          @similarity_index_key = index_key
        end
        @similarity_index
      end

      def onLButtonDown(flags, x, y, view)
        # Check if click is on overlay hitbox first
        if @overlay_hitboxes && !@overlay_hitboxes.empty?
          @overlay_hitboxes.each do |hb|
            if x >= hb[:x] && x <= hb[:x] + hb[:w] && y >= hb[:y] && y <= hb[:y] + hb[:h]
              if hb[:type] == :isolate
                toggle_isolate
              else
                filter_by_overlay_value(hb[:type], hb[:value])
              end
              view.invalidate
              return
            end
          end
        end
        
        ph = view.pick_helper
        ph.do_pick(x, y)
        
        entity = nil
        path = ph.path_at(0)
        if path
          entity = path.reverse.find { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
        end
        entity ||= ph.best_picked
        
        return unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        
        # Normal object click - clear overlay filter snapshot
        @overlay_snapshot = nil
        @active_filter = nil
        
        settings = MH::SelectSimilar.settings
        ctrl_pressed = (flags & COPY_MODIFIER_MASK) != 0  # Ctrl key
        shift_pressed = (flags & CONSTRAIN_MODIFIER_MASK) != 0  # Shift key
        
        # Ctrl+Click: Add to current selection and select similar based on NEW entity only (incremental)
        if ctrl_pressed
          # Incremental mode: only find matches for the new clicked entity
          # Keep current selection and add new matches
          add_similar_incremental(entity)
          return
        end
        
        # Use progressive name search mode if enabled
        if settings[:partial_name]
          handle_progressive_name_search(entity, flags)
        else
          # Normal behavior - use existing name_search value
          if shift_pressed  # Shift pressed - cycle size mode
            if MH::SelectSimilar.settings[:bounding_size]
              current_mode = MH::SelectSimilar.settings[:size_mode] || 0
              new_mode = (current_mode + 1) % 4
              MH::SelectSimilar.settings[:size_mode] = new_mode
              
              mode_names = ['Dim1 (mid)', 'Dim2 (max)', 'Both dims', 'All (OR)']
              Sketchup.status_text = "Size mode: #{mode_names[new_mode]} - Click to select"
            end
            select_similar_multi([entity])
          else
            select_similar_multi([entity])
          end
        end
      end
      
      # Handle progressive name search based on click depth
      def handle_progressive_name_search(entity, flags)
        # Use entity_id for reliable comparison
        current_entity_id = entity.entityID rescue nil
        
        # If clicked on a different object, always reset to depth 0 and use the new object's name
        if @last_clicked_entity_id != current_entity_id
          @last_clicked_entity_id = current_entity_id
          @last_clicked_entity = entity
          @click_depth = 0
          
          # Get entity name and parse tokens from the newly clicked entity
          entity_name = entity.respond_to?(:name) ? entity.name : entity.definition.name
          s = MH::SelectSimilar.settings
          if s[:name_group]
            cleaned_name = MH::SelectSimilar.extract_name_group_keyword(entity_name)
          else
            cleaned_name = MH::SelectSimilar.extract_search_keyword(entity_name)
          end
          @name_tokens = parse_name_tokens(cleaned_name)
        else
          # They clicked the exact same object
          # Advance to next depth level
          @click_depth += 1
          
          # Wrap around if exceeded max depth
          if @click_depth >= @name_tokens.length
            @click_depth = 0
          end
        end
        
        # Build search term based on current depth
        if @name_tokens.nil? || @name_tokens.empty?
          Sketchup.status_text = "No name tokens found in object name"
          return
        end
        
        # Get search term up to current depth + 1
        search_depth = [@click_depth + 1, @name_tokens.length].min
        search_term = build_search_term(@name_tokens, search_depth)
        
        # Display current search info
        Sketchup.status_text = "Searching: '#{search_term}' (level #{@click_depth + 1}/#{@name_tokens.length})"
        
        # Temporarily disable size/thickness checks for progressive search to select whole name group
        s = MH::SelectSimilar.settings
        orig_size = s[:bounding_size]
        orig_vol = s[:bounding_volume]
        orig_thick = s[:min_thickness]
        
        begin
          s[:bounding_size] = false
          s[:bounding_volume] = false
          s[:min_thickness] = false
          
          # Perform search with this term
          select_by_name_pattern(@last_clicked_entity, search_term)
        ensure
          # Restore settings
          s[:bounding_size] = orig_size
          s[:bounding_volume] = orig_vol
          s[:min_thickness] = orig_thick
        end
      end
      
      # Parse name into tokens and find separator positions
      # Returns array of cut positions for progressive search
      # Example: SP39_H?c - Th nh Sau
      # Progressive levels:
      # - depth 1: "SP39"
      # - depth 2: "SP39_H?c"
      # - depth 3: "SP39_H?c - Th nh"
      # - depth 4: "SP39_H?c - Th nh Sau" (full name)
      def parse_name_tokens(name)
        return [] if name.nil? || name.empty?
        
        # Find all separator positions
        # Separators: . (dot), - (dash), _ (underscore), " " (space)
        # Example: "SP54.1_Cánh Phải" → cuts at positions of . _ and space
        #   depth 1: "SP54"
        #   depth 2: "SP54.1"
        #   depth 3: "SP54.1_Cánh"
        #   depth 4: "SP54.1_Cánh Phải" (full)
        # Example: "SP53-54_Mặt Trước_Chân Bệ" → cuts at - _ space _ space
        #   depth 1: "SP53"
        #   depth 2: "SP53-54"
        #   depth 3: "SP53-54_Mặt"
        #   depth 4: "SP53-54_Mặt Trước"
        #   depth 5: "SP53-54_Mặt Trước_Chân"
        #   depth 6: "SP53-54_Mặt Trước_Chân Bệ" (full)
        separators = []
        i = 0
        
        while i < name.length
          if name[i] == '.' || name[i] == '-' || name[i] == '_' || name[i] == ' '
            separators << i
            i += 1
          else
            i += 1
          end
        end
        
        # Add end of string as final position
        separators << name.length
        
        # Count tokens based on separator count
        token_count = separators.length
        
        # Store both the original name and separator positions
        @original_cleaned_name = name
        @separator_positions = separators.uniq.sort
        
        # Return array with token_count elements (used for depth counting)
        (1..token_count).to_a
      end
      
      # Build search term from original name up to specified depth
      # depth=1: "SP01"
      # depth=2: "SP01_T?m  ?ng" (full name if only 2 underscore-separated parts)
      def build_search_term(tokens, depth)
        return '' if @original_cleaned_name.nil? || @original_cleaned_name.empty? || depth < 1
        
        # If depth exceeds available separators, return full name
        if depth > @separator_positions.length
          return @original_cleaned_name
        end
        
        # Get substring up to the separator at (depth-1) position
        cut_pos = @separator_positions[depth - 1]
        result = @original_cleaned_name[0, cut_pos]
        result
      end
      
      # Select objects by name pattern (search in cleaned name)
      def select_by_name_pattern(reference, search_term)
        settings = MH::SelectSimilar.settings.dup
        all_entities = get_cached_entities
        
        matches = []
        
        all_entities.each do |entity|
          if MH::SelectSimilar.advanced_match?(entity, search_term)
            # Also apply other criteria if enabled (material, tag, etc.)
            if passes_other_criteria?(reference, entity, settings)
              matches << entity
            end
          end
        end
        
        @model.selection.clear
        @model.selection.add(matches)
        
        Sketchup.status_text = "Selected #{matches.length} objects matching '#{search_term}' (click again to narrow/expand)"
      end
      
      # Check if entity passes non-name criteria
      def passes_other_criteria?(ref, target, settings)
        # Apply global advanced name_search filter if it exists
        search_term = settings[:name_search].to_s.strip
        unless search_term.empty?
          return false unless MH::SelectSimilar.advanced_match?(target, search_term)
        end


        # Always include the reference object itself
        return true if ref && ref == target
        
        # Type filter
        case settings[:type_filter]
        when 'group'
          return false unless target.is_a?(Sketchup::Group)
        when 'component'
          return false unless target.is_a?(Sketchup::ComponentInstance)
        end
        
        # If no reference object (e.g., from live search), we skip material, tag, and bounds checks!
        return true if ref.nil?
        
        # Same material
        if settings[:same_material]
          return false unless MH::SelectSimilar.get_material(ref) == MH::SelectSimilar.get_material(target)
        end
        
        # Same tag
        if settings[:same_tag]
          return false unless MH::SelectSimilar.get_tag(ref) == MH::SelectSimilar.get_tag(target)
        end
        
        # Expensive checks - compute bounds once
        needs_bounds = settings[:min_thickness] || settings[:bounding_size] || settings[:bounding_volume]
        if needs_bounds
          ref_dims = MH::SelectSimilar.bounds_dims(ref)
          target_dims = MH::SelectSimilar.bounds_dims(target)
        end
        
        # Min thickness
        if settings[:min_thickness]
          if ref_dims && target_dims
            return false unless MH::SelectSimilar.thickness_matches?(ref_dims[0], target_dims[0], settings[:thickness_tolerance])
          end
        end
        
        # Bounding size
        if settings[:bounding_size]
          if ref_dims && target_dims
            size_mode = settings[:size_mode] || 0
            tol = settings[:size_tolerance]
            
            case size_mode
            when 0
              return false unless target_dims.any? { |d| MH::SelectSimilar.within_tolerance?(ref_dims[1], d, tol) }
            when 1
              return false unless target_dims.any? { |d| MH::SelectSimilar.within_tolerance?(ref_dims[2], d, tol) }
            when 2
              found_mid = target_dims.any? { |d| MH::SelectSimilar.within_tolerance?(ref_dims[1], d, tol) }
              found_max = target_dims.any? { |d| MH::SelectSimilar.within_tolerance?(ref_dims[2], d, tol) }
              return false unless found_mid && found_max
            when 3
              found_mid = target_dims.any? { |d| MH::SelectSimilar.within_tolerance?(ref_dims[1], d, tol) }
              found_max = target_dims.any? { |d| MH::SelectSimilar.within_tolerance?(ref_dims[2], d, tol) }
              return false unless found_mid || found_max
            end
          end
        end
        
        # Bounding volume
        if settings[:bounding_volume]
          if ref_dims && target_dims
            ref_vol = ref_dims.reduce(:*)
            target_vol = target_dims.reduce(:*)
            return false unless MH::SelectSimilar.within_tolerance?(ref_vol, target_vol, settings[:volume_tolerance])
          end
        end
        
        true
      end


      def onKeyDown(key, repeat, flags, view)
        if key == 9  # Tab key
          show_settings_dialog
          return true
        end
        
        # Numeric shortcuts 0-999 for Quick Search rows.
        digit = quick_search_digit_from_key(key)
        if digit
          queue_quick_search_digit(digit)
          return true
        end
        
        # Windows SketchUp bug workaround: active Ruby tools swallow single-key native shortcuts.
        # Dynamically check if the pressed key matches the user's native shortcut for Isolate.
        shortcuts = Sketchup.get_shortcuts
        isolate_shortcuts = shortcuts.select { |s| s.include?("Isolate/Unisolate Selected") }
        
        isolate_shortcuts.each do |isolate_s|
          key_str = isolate_s.split("\t").first.strip.upcase
          
          # Map modifiers from shortcut string to Sketchup flags
          has_ctrl = (flags & COPY_MODIFIER_MASK) != 0 || (flags & 8) != 0
          has_shift = (flags & CONSTRAIN_MODIFIER_MASK) != 0 || (flags & 4) != 0
          has_alt = (flags & ALT_MODIFIER_MASK) != 0 || (flags & 32) != 0
          
          needs_ctrl = key_str.include?("CTRL+")
          needs_shift = key_str.include?("SHIFT+")
          needs_alt = key_str.include?("ALT+")
          
          next if needs_ctrl != has_ctrl
          next if needs_shift != has_shift
          next if needs_alt != has_alt
          
          base_key = key_str.split('+').last.strip
          
          # Match standard letters/numbers
          if base_key.length == 1 && key == base_key.ord
            MH::SelectSimilar.toggle_isolate
            view.invalidate
            return true
          end
          
          # Match F-keys
          if base_key =~ /^F(\d+)$/
            if key == 111 + $1.to_i
              MH::SelectSimilar.toggle_isolate
              view.invalidate
              return true
            end
          end
          
          # Match Space
          if base_key == "SPACE" && key == 32
            MH::SelectSimilar.toggle_isolate
            view.invalidate
            return true
          end
        end
        

        false
      end

      def quick_search_digit_from_key(key)
        return key - 48 if key >= 48 && key <= 57 # 0-9 keyboard
        return key - 96 if key >= 96 && key <= 105 # Numpad 0-9
        nil
      end

      def queue_quick_search_digit(digit)
        shortcuts = MH::SelectSimilar.quick_search_shortcuts
        unless shortcuts && !shortcuts.empty?
          Sketchup.status_text = "Quick Search: no suggestions loaded"
          return
        end

        @quick_search_buffer = '' if @quick_search_buffer.to_s.length >= 3
        @quick_search_buffer << digit.to_s
        @quick_search_token += 1
        token = @quick_search_token

        shortcut = MH::SelectSimilar.normalize_quick_search_shortcut(@quick_search_buffer)
        Sketchup.status_text = "Quick Search ##{shortcut || @quick_search_buffer} pending..."

        if @quick_search_buffer.length >= 3
          apply_quick_search_buffer(token)
        else
          UI.start_timer(0.55, false) do
            apply_quick_search_buffer(token)
          end
        end
      end

      def apply_quick_search_buffer(token)
        return unless token == @quick_search_token

        buffer = @quick_search_buffer.to_s
        @quick_search_buffer = ''
        return if buffer.empty?

        shortcut = MH::SelectSimilar.normalize_quick_search_shortcut(buffer)
        unless shortcut
          Sketchup.status_text = "Quick Search: number must be 000-999"
          return
        end

        shortcuts = MH::SelectSimilar.quick_search_shortcuts
        unless shortcuts.key?(shortcut)
          Sketchup.status_text = "Quick Search ##{shortcut} not found"
          return
        end

        apply_quick_search_shortcut(shortcut)
      end

      def apply_quick_search_index(index)
        item = MH::SelectSimilar.quick_search_items[index]
        text = item && item[:text]
        return unless text

        apply_quick_search_text(text, item[:shortcut])
      end

      def apply_quick_search_shortcut(shortcut)
        shortcut = MH::SelectSimilar.normalize_quick_search_shortcut(shortcut)
        return unless shortcut

        text = MH::SelectSimilar.quick_search_shortcuts[shortcut]
        return unless text

        apply_quick_search_text(text, shortcut)
      end

      def apply_quick_search_text(text, shortcut)
        s = MH::SelectSimilar.settings
        s[:name_search] = text
        MH::SelectSimilar.save_settings

        # Use a timer to prevent selection changes from stealing viewport focus.
        UI.start_timer(0.0, false) do
          trigger_live_search

          if @mini_settings && @mini_settings.visible?
            update_js = "document.getElementById('name_search').value = #{text.to_json};"
            @mini_settings.execute_script(update_js)
          end

          Sketchup.status_text = "Quick Search ##{shortcut} applied: #{text}"
        end
      end

      def onUserText(text, view)
        shortcut = MH::SelectSimilar.normalize_quick_search_shortcut(text)
        return false unless shortcut

        if MH::SelectSimilar.quick_search_shortcuts.key?(shortcut)
          @quick_search_buffer = ''
          @quick_search_token += 1
          apply_quick_search_shortcut(shortcut)
          view.invalidate if view
          true
        else
          Sketchup.status_text = "Quick Search ##{shortcut} not found"
          false
        end
      end
      
      # Store last mouse position for dialogs + overlay hover detection
      def onMouseMove(flags, x, y, view)
        @last_x = x
        @last_y = y
        @mouse_x = x
        @mouse_y = y
        
        # Check hover on overlay hitboxes
        old_hover = @hover_index
        @hover_index = nil
        if @overlay_hitboxes && !@overlay_hitboxes.empty?
          @overlay_hitboxes.each_with_index do |hb, idx|
            if x >= hb[:x] && x <= hb[:x] + hb[:w] && y >= hb[:y] && y <= hb[:y] + hb[:h]
              @hover_index = idx
              break
            end
          end
        end
        
        # Redraw if hover state changed
        view.invalidate if @hover_index != old_hover
      end
      

      
      def trigger_reselect
        MH::SelectSimilar.save_settings
        if @model.selection.length > 0
          refs = @model.selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
          select_similar_multi(refs) if refs.length > 0
        end
      end

      # Add items to right-click context menu
      def getMenu(menu, flags, x, y, view)
        @last_x = x
        @last_y = y
        
        s = MH::SelectSimilar.settings
        
        # Add Search input box directly from context menu
        menu.add_item("Search by Name...") {
          prompts = ["Search Name:"]
          defaults = [s[:name_search].to_s]
          input = UI.inputbox(prompts, defaults, "Select Similar")
          if input && input[0]
            MH::SelectSimilar.settings[:name_search] = input[0]
            MH::SelectSimilar.save_settings
            trigger_live_search
            # Already cleared inside trigger_live_search
          end
        }
        
        menu.add_item("Reload Search Config") {
          if MH::SelectSimilar.load_suggestions_from_excel
            Sketchup.status_text = "Reloaded search suggestions."
          else
            Sketchup.status_text = "No search suggestions found."
          end
        }
        
        # Add Suggestions submenu
        quick_items = MH::SelectSimilar.quick_search_items
        if quick_items && !quick_items.empty?
          search_menu = menu.add_submenu("Quick Search")
          quick_items.each_with_index do |item, index|
            search_menu.add_item(MH::SelectSimilar.quick_search_label(item)) {
              apply_quick_search_index(index)
            }
          end
        end
        
        menu.add_separator
        
        item0 = menu.add_item("Name Search (Progressive)") { s[:partial_name] = !s[:partial_name]; trigger_reselect }
        menu.set_validation_proc(item0) { s[:partial_name] ? MF_CHECKED : MF_UNCHECKED }

        item0b = menu.add_item("Name Group (incl. Prefix)") { s[:name_group] = !s[:name_group]; trigger_reselect }
        menu.set_validation_proc(item0b) { s[:name_group] ? MF_CHECKED : MF_UNCHECKED }
        
        item1 = menu.add_item("Bounding Size") { s[:bounding_size] = !s[:bounding_size]; trigger_reselect }
        menu.set_validation_proc(item1) { s[:bounding_size] ? MF_CHECKED : MF_UNCHECKED }
        
        item1b = menu.add_item("Bounding Volume") { s[:bounding_volume] = !s[:bounding_volume]; trigger_reselect }
        menu.set_validation_proc(item1b) { s[:bounding_volume] ? MF_CHECKED : MF_UNCHECKED }
        
        item2 = menu.add_item("Same Material") { s[:same_material] = !s[:same_material]; trigger_reselect }
        menu.set_validation_proc(item2) { s[:same_material] ? MF_CHECKED : MF_UNCHECKED }
        
        item3 = menu.add_item("Min Thickness") { s[:min_thickness] = !s[:min_thickness]; trigger_reselect }
        menu.set_validation_proc(item3) { s[:min_thickness] ? MF_CHECKED : MF_UNCHECKED }
        
        item4 = menu.add_item("Same Tag") { s[:same_tag] = !s[:same_tag]; trigger_reselect }
        menu.set_validation_proc(item4) { s[:same_tag] ? MF_CHECKED : MF_UNCHECKED }
        
        menu.add_separator
        scope_menu = menu.add_submenu("Scope")
        
        s1 = scope_menu.add_item("All Objects") { s[:scope_filter] = 'all'; trigger_reselect }
        scope_menu.set_validation_proc(s1) { s[:scope_filter] == 'all' ? MF_CHECKED : MF_UNCHECKED }
        
        s2 = scope_menu.add_item("Visible Only") { s[:scope_filter] = 'visible'; trigger_reselect }
        scope_menu.set_validation_proc(s2) { s[:scope_filter] == 'visible' ? MF_CHECKED : MF_UNCHECKED }
        
        s3 = scope_menu.add_item("In Viewport") { s[:scope_filter] = 'viewport'; trigger_reselect }
        scope_menu.set_validation_proc(s3) { s[:scope_filter] == 'viewport' ? MF_CHECKED : MF_UNCHECKED }
        
        s4 = scope_menu.add_item("Viewport + Visible") { s[:scope_filter] = 'viewport_visible'; trigger_reselect }
        scope_menu.set_validation_proc(s4) { s[:scope_filter] == 'viewport_visible' ? MF_CHECKED : MF_UNCHECKED }
      end
      
      def show_mini_settings_at_cursor
        # Get window position and convert to screen coordinates
        view = Sketchup.active_model.active_view
        # We need to calculate the actual screen position  
        screen_x = @last_x || 100
        screen_y = @last_y || 100
        
        show_mini_settings(screen_x, screen_y, view)
      end
      
      def show_mini_settings(x, y, view)
        @mini_settings.close if @mini_settings && @mini_settings.visible?
        
        s = MH::SelectSimilar.settings
        suggestions = MH::SelectSimilar.quick_search_items.to_json
        
        @mini_settings = UI::HtmlDialog.new(
          dialog_title: "MH Select Similar - Advanced",
          preferences_key: "MH_SelectSimilar_QuickSettings_V3",
          width: 280,
          height: 480,
          resizable: false,
          style: UI::HtmlDialog::STYLE_UTILITY
        )
        
        html = <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="UTF-8">
            <style>
              @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600&display=swap');
              * { box-sizing: border-box; margin: 0; padding: 0; }
              body {
                font-family: 'Inter', 'Segoe UI', sans-serif;
                background: linear-gradient(135deg, #0f172a 0%, #1e293b 100%);
                color: #f1f5f9;
                padding: 12px;
                font-size: 12px;
                overflow: hidden;
              }
              .container {
                display: flex;
                flex-direction: column;
                height: 100%;
              }
              .section-title {
                color: #38bdf8;
                font-size: 10px;
                font-weight: 600;
                text-transform: uppercase;
                letter-spacing: 0.05em;
                margin: 8px 0 6px 0;
                display: flex;
                align-items: center;
              }
              .section-title::after {
                content: '';
                flex: 1;
                height: 1px;
                background: rgba(56, 189, 248, 0.2);
                margin-left: 8px;
              }
              .search-container {
                background: rgba(255, 255, 255, 0.05);
                border: 1px solid rgba(255, 255, 255, 0.1);
                border-radius: 8px;
                padding: 10px;
                margin-bottom: 12px;
                box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
              }
              .input-group {
                position: relative;
                margin-bottom: 8px;
              }
              input[type="text"] {
                width: 100%;
                background: rgba(15, 23, 42, 0.8);
                border: 1px solid rgba(56, 189, 248, 0.4);
                border-radius: 6px;
                color: #fff;
                padding: 8px 12px;
                font-size: 12px;
                transition: all 0.2s;
              }
              input[type="text"]:focus {
                outline: none;
                border-color: #38bdf8;
                box-shadow: 0 0 0 2px rgba(56, 189, 248, 0.2);
              }
              .suggestion-list {
                max-height: 100px;
                overflow-y: auto;
                background: rgba(15, 23, 42, 0.5);
                border-radius: 6px;
                margin-top: 4px;
              }
              .suggestion-item {
                padding: 6px 10px;
                cursor: pointer;
                border-bottom: 1px solid rgba(255, 255, 255, 0.03);
                transition: background 0.2s;
                font-size: 11px;
                color: #94a3b8;
              }
              .suggestion-item:hover {
                background: rgba(56, 189, 248, 0.15);
                color: #fff;
              }
              .options-grid {
                display: grid;
                grid-template-columns: 1fr;
                gap: 4px;
              }
              .option-row {
                display: flex;
                align-items: center;
                padding: 8px 10px;
                background: rgba(255, 255, 255, 0.03);
                border-radius: 6px;
                cursor: pointer;
                transition: all 0.2s;
                border: 1px solid transparent;
              }
              .option-row:hover {
                background: rgba(255, 255, 255, 0.07);
              }
              .option-row.active {
                border-color: rgba(56, 189, 248, 0.3);
                background: rgba(56, 189, 248, 0.05);
              }
              .option-row input[type="checkbox"] {
                margin-right: 10px;
                accent-color: #38bdf8;
                width: 14px;
                height: 14px;
              }
              .option-label {
                flex: 1;
                font-weight: 400;
              }
              select {
                width: 100%;
                background: rgba(15, 23, 42, 0.8);
                border: 1px solid rgba(56, 189, 248, 0.4);
                border-radius: 6px;
                color: #fff;
                padding: 6px 10px;
                font-size: 11px;
                cursor: pointer;
              }
              .footer-hint {
                margin-top: auto;
                font-size: 9px;
                color: #64748b;
                text-align: center;
                padding-top: 12px;
              }
              ::-webkit-scrollbar { width: 4px; }
              ::-webkit-scrollbar-track { background: transparent; }
              ::-webkit-scrollbar-thumb { background: rgba(56, 189, 248, 0.3); border-radius: 10px; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="section-title">Advanced Search</div>
              <div class="search-container">
                <div class="input-group">
                  <input type="text" id="name_search" value="#{s[:name_search]}" 
                         placeholder="vd: mã sản phẩm, (Hậu), *T&gt;7*" oninput="updateNameSearch()">
                </div>
                <div class="section-title" style="margin-top:4px; justify-content: space-between;">
                  <span>Suggestions</span>
                  <button onclick="refreshConfig()" style="background:none; border:none; color:#38bdf8; cursor:pointer; font-size:10px;">&#x21BB; Refresh</button>
                </div>
                <div class="suggestion-list" id="suggestion_list">
                  <!-- Suggestions injected here -->
                </div>
              </div>

              <div class="section-title">Filters</div>
              <div class="options-grid">
                <div class="option-row #{s[:partial_name] ? 'active' : ''}" onclick="toggle('partial_name')">
                  <input type="checkbox" id="partial_name" #{s[:partial_name] ? 'checked' : ''}>
                  <div class="option-label">Progressive Search</div>
                </div>
                <div class="option-row #{s[:bounding_size] ? 'active' : ''}" onclick="toggle('bounding_size')">
                  <input type="checkbox" id="bounding_size" #{s[:bounding_size] ? 'checked' : ''}>
                  <div class="option-label">Bounding Size</div>
                </div>
                <div class="option-row #{s[:same_material] ? 'active' : ''}" onclick="toggle('same_material')">
                  <input type="checkbox" id="same_material" #{s[:same_material] ? 'checked' : ''}>
                  <div class="option-label">Same Material</div>
                </div>
                <div class="option-row #{s[:min_thickness] ? 'active' : ''}" onclick="toggle('min_thickness')">
                  <input type="checkbox" id="min_thickness" #{s[:min_thickness] ? 'checked' : ''}>
                  <div class="option-label">Min Thickness</div>
                </div>
                <div class="option-row #{s[:same_tag] ? 'active' : ''}" onclick="toggle('same_tag')">
                  <input type="checkbox" id="same_tag" #{s[:same_tag] ? 'checked' : ''}>
                  <div class="option-label">Same Tag</div>
                </div>
              </div>

              <div class="section-title">Scope</div>
              <div style="padding: 0 4px">
                <select id="scope_filter" onchange="updateScope()">
                  <option value="all" #{s[:scope_filter] == 'all' ? 'selected' : ''}>All Objects</option>
                  <option value="visible" #{s[:scope_filter] == 'visible' ? 'selected' : ''}>Visible Only</option>
                  <option value="viewport" #{s[:scope_filter] == 'viewport' ? 'selected' : ''}>In Viewport</option>
                  <option value="viewport_visible" #{s[:scope_filter] == 'viewport_visible' ? 'selected' : ''}>Viewport + Visible</option>
                </select>
              </div>

              <div class="footer-hint">
                *formula* | (exclude) | , multi-keywords<br>
                TAB opens settings - type 000-999 for Quick Search
              </div>
            </div>

            <script>
              const suggestions = #{suggestions};
              const list = document.getElementById('suggestion_list');
              
              function renderSuggestions(sugs) {
                list.innerHTML = '';
                sugs.slice(0, 1000).forEach((entry, index) => {
                  const text = (typeof entry === 'object' && entry !== null) ? entry.text : entry;
                  const shortcut = (typeof entry === 'object' && entry !== null && entry.shortcut)
                    ? entry.shortcut
                    : String(index).padStart(3, '0');
                  const item = document.createElement('div');
                  item.className = 'suggestion-item';
                  item.innerText = shortcut + '  ' + text;
                  item.onclick = () => {
                    const input = document.getElementById('name_search');
                    input.value = text;
                    updateNameSearch();
                  };
                  list.appendChild(item);
                });
              }
              renderSuggestions(suggestions);
              
              function refreshConfig() {
                sketchup.refresh_config();
              }

              function toggle(id) {
                const cb = document.getElementById(id);
                cb.checked = !cb.checked;
                const row = cb.parentElement;
                if (cb.checked) row.classList.add('active');
                else row.classList.remove('active');
                
                sketchup.update_setting(JSON.stringify({key: id, value: cb.checked}));
              }

              let searchTimeout;
              function updateNameSearch() {
                const val = document.getElementById('name_search').value;
                // Use a small debounce for typing
                clearTimeout(searchTimeout);
                searchTimeout = setTimeout(() => {
                  sketchup.update_setting(JSON.stringify({key: 'name_search', value: val}));
                }, 300);
              }

              function updateScope() {
                const val = document.getElementById('scope_filter').value;
                sketchup.update_setting(JSON.stringify({key: 'scope_filter', value: val}));
              }
              
              document.addEventListener('keydown', function(e) {
                if (e.key === 'Escape') sketchup.close_dialog();
              });
              
              window.onload = () => {
                const input = document.getElementById('name_search');
                input.focus();
                input.setSelectionRange(input.value.length, input.value.length);
              };
            </script>
          </body>
          </html>
        HTML
        
        @mini_settings.set_html(html)
        
        @mini_settings.add_action_callback("refresh_config") do |_|
          ok = MH::SelectSimilar.load_suggestions_from_excel
          new_sugs = MH::SelectSimilar.quick_search_items.to_json
          update_js = "renderSuggestions(#{new_sugs});"
          @mini_settings.execute_script(update_js)
          Sketchup.status_text = ok ? "Reloaded search suggestions." : "No search suggestions found."
        end
        
        @mini_settings.add_action_callback("close_dialog") do |_|
          @mini_settings.close
        end
        
        @mini_settings.add_action_callback("update_setting") do |_, param|
          begin
            data = JSON.parse(param)
            key = data['key'].to_sym
            val = data['value']
            MH::SelectSimilar.settings[key] = val
            MH::SelectSimilar.save_settings  # Persist settings
            
            # Re-evaluate live search immediately
            if key == :name_search || !MH::SelectSimilar.settings[:name_search].to_s.strip.empty?
              trigger_live_search
            elsif @model.selection.length > 0
              # Re-select similar if other settings changed and we have a selection
              refs = @model.selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
              select_similar_multi(refs) if refs.length > 0
            end
          rescue => e
            MH::SelectSimilar.dbg("Error: #{e.message}")
          end
        end
        
        @mini_settings.show
      end

      # Live Search based on Name Input
      def trigger_live_search
        s = MH::SelectSimilar.settings
        search_term = s[:name_search].to_s.strip
        
        if search_term.empty?
          # If search cleared, we clear the selection if nothing selected
          @overlay_dirty = true
          @model.active_view.invalidate
          Sketchup.status_text = "Search cleared"
          return
        end

        search_terms = search_term.split(',').map(&:strip).reject(&:empty?).map(&:downcase)
        return if search_terms.empty?

        # SEARCH ALL in scope (based on scope_filter)
        all_entities = get_cached_entities
        matches = all_entities.select do |entity|
          MH::SelectSimilar.advanced_match?(entity, search_term)
        end
        
        @model.start_operation("Live Search", true)
        @model.selection.clear
        @model.selection.add(matches)
        @model.commit_operation
        
        @overlay_dirty = true
        @model.active_view.invalidate
        Sketchup.status_text = "Live Search: Selected #{matches.length} objects matching '#{search_term}'"
        
        # Clear the search pattern after execution so it doesn't filter subsequent clicks
        MH::SelectSimilar.settings[:name_search] = ""
        # We don't necessarily need to save_settings to disk here if we want it to persist across sessions 
        # but the user said "clear after search", which implies resetting the state.
      end

      # Select similar for multiple reference objects
      def select_similar_multi(references)
        settings = MH::SelectSimilar.settings
        similarity_index = get_similarity_index(settings)
        
        # Pre-compute reference bounds for performance
        needs_bounds = settings[:bounding_size] || settings[:bounding_volume] || settings[:min_thickness]
        ref_dims_map = {}
        if needs_bounds
          references.each do |ref|
            ref_dims_map[ref.object_id] = MH::SelectSimilar.bounds_dims(ref)
          end
        end
        
        # Use Set for faster lookup
        ref_set = references.to_set
        matches = references.dup
        
        matched_set = ref_set.dup
        references.each do |ref|
          ref_dims = needs_bounds ? ref_dims_map[ref.object_id] : nil
          similarity_index.candidates(ref, settings).each do |entity|
            next if matched_set.include?(entity)

            feature = similarity_index.feature(entity)
            target_dims = needs_bounds && feature ? feature.dimensions : nil
            if MH::SelectSimilar.matches_criteria?(ref, entity, settings, ref_dims: ref_dims, target_dims: target_dims)
              matches << entity
              matched_set.add(entity)
            end
          end
        end
        
        @model.start_operation("Select Similar", true)
        @model.selection.clear
        @model.selection.add(matches)
        @model.commit_operation
        @overlay_dirty = true
        
        Sketchup.status_text = "Selected #{matches.length} objects. Press R to rename, Tab for settings"
      end
      
      # Incremental add: only find matches for new entity and add to current selection
      # Much faster than recalculating everything
      def add_similar_incremental(new_ref)
        settings = MH::SelectSimilar.settings
        
        # Auto-append new_ref's name to the global name_search if partial_name is active
        if settings[:partial_name]
          new_name = MH::SelectSimilar.clean_name(new_ref.respond_to?(:name) ? new_ref.name : new_ref.definition.name)
          unless new_name.empty?
            current_search = settings[:name_search].to_s.strip
            if current_search.empty?
              settings[:name_search] = new_name
            else
              terms = current_search.split(',').map(&:strip)
              unless terms.include?(new_name)
                settings[:name_search] = current_search + ", " + new_name
              end
            end
            
            # Update UI if open
            if @mini_settings && @mini_settings.visible?
               escaped_str = settings[:name_search].gsub("'", "\\\\'")
               update_js = "document.getElementById('name_search').value = '#{escaped_str}';"
               @mini_settings.execute_script(update_js)
            end
          end
        end

        similarity_index = get_similarity_index(settings)
        
        # Keep current selection
        current_selection = @selection.to_a
        current_set = current_selection.to_set
        
        # Pre-compute reference bounds
        needs_bounds = settings[:bounding_size] || settings[:bounding_volume] || settings[:min_thickness]
        ref_dims = needs_bounds ? MH::SelectSimilar.bounds_dims(new_ref) : nil
        
        # Find new matches for the new reference only
        new_matches = [new_ref]
        
        similarity_index.candidates(new_ref, settings).each do |entity|
          next if current_set.include?(entity)  # Skip if already selected
          next if entity == new_ref
          
          feature = similarity_index.feature(entity)
          target_dims = needs_bounds && feature ? feature.dimensions : nil
          if MH::SelectSimilar.matches_criteria?(new_ref, entity, settings, ref_dims: ref_dims, target_dims: target_dims)
            new_matches << entity
          end
        end
        
        # Add new matches to selection (don't clear)
        @model.selection.add(new_matches)
        @overlay_dirty = true
        
        ref_count = current_selection.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }.length + 1
        Sketchup.status_text = "Added #{new_matches.length} objects. Total: #{@selection.length} (#{ref_count} refs). Search: '#{settings[:name_search]}'"
      end

      # -----------------------------------------------------------------------
      # SETTINGS DIALOG
      # -----------------------------------------------------------------------
      def show_settings_dialog
        if @settings_dialog && @settings_dialog.visible?
          @settings_dialog.bring_to_front
          return
        end

        @settings_dialog = UI::HtmlDialog.new(
          dialog_title: "Select Similar - Settings",
          preferences_key: "MH_Test6_Settings",
          width: 380,
          height: 580,
          resizable: false,
          style: UI::HtmlDialog::STYLE_DIALOG
        )

        html = build_settings_html
        @settings_dialog.set_html(html)

        @settings_dialog.add_action_callback("apply_settings") do |_, param|
          begin
            data = JSON.parse(param)
            MH::SelectSimilar.settings = {
              partial_name: data['partial_name'],
              name_search: data['name_search'].to_s,
              bounding_size: data['bounding_size'],
              bounding_volume: data['bounding_volume'],
              min_thickness: data['min_thickness'],
              same_material: data['same_material'],
              same_tag: data['same_tag'],
              name_group: data['name_group'],
              size_tolerance: data['size_tolerance'].to_f,
              volume_tolerance: data['volume_tolerance'].to_f,
              thickness_tolerance: data['thickness_tolerance'].to_f,
              type_filter: data['type_filter'],
              scope_filter: data['scope_filter'],
              nesting_filter: data['nesting_filter'],
              min_size_threshold: data['min_size_threshold'].to_i,
              min_all_size_threshold: data['min_all_size_threshold'].to_i,
              key_isolate: data['key_isolate'].to_s.upcase,
              key_settings: data['key_settings'].to_s.upcase
            }
            
            # Re-select if there's a selection
            if @selection.length > 0
              ref = @selection.find { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
              select_similar_multi([ref]) if ref
            end
            
            @settings_dialog.close
          rescue => e
            MH::SelectSimilar.dbg("Error applying settings: #{e.message}")
          end
        end

        @settings_dialog.add_action_callback("close_dialog") do |_|
          @settings_dialog.close
        end

        @settings_dialog.show
      end

      def build_settings_html
        s = MH::SelectSimilar.settings
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="UTF-8">
            <style>
              * { box-sizing: border-box; margin: 0; padding: 0; }
              body {
                font-family: 'Segoe UI', Arial, sans-serif;
                background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
                color: #e0e0e0;
                padding: 16px;
                font-size: 13px;
              }
              h2 {
                color: #00d4ff;
                font-size: 16px;
                margin-bottom: 16px;
                text-align: center;
                text-transform: uppercase;
                letter-spacing: 2px;
              }
              .section {
                background: rgba(255,255,255,0.05);
                border-radius: 8px;
                padding: 12px;
                margin-bottom: 12px;
              }
              .section-title {
                color: #00d4ff;
                font-size: 11px;
                text-transform: uppercase;
                letter-spacing: 1px;
                margin-bottom: 10px;
                border-bottom: 1px solid rgba(0,212,255,0.3);
                padding-bottom: 6px;
              }
              .row {
                display: flex;
                align-items: center;
                margin-bottom: 8px;
              }
              .row label {
                flex: 1;
                cursor: pointer;
              }
              .row input[type="checkbox"] {
                width: 18px;
                height: 18px;
                margin-right: 10px;
                accent-color: #00d4ff;
              }
              .row input[type="number"] {
                width: 50px;
                background: rgba(255,255,255,0.1);
                border: 1px solid rgba(0,212,255,0.3);
                border-radius: 4px;
                color: #fff;
                padding: 4px 6px;
                text-align: center;
              }
              .tolerance {
                color: #888;
                font-size: 11px;
                margin-left: 8px;
              }
              .radio-group {
                display: flex;
                gap: 12px;
                flex-wrap: wrap;
              }
              .radio-group label {
                display: flex;
                align-items: center;
                cursor: pointer;
              }
              .radio-group input[type="radio"] {
                margin-right: 6px;
                accent-color: #00d4ff;
              }
              .btn-row {
                display: flex;
                gap: 10px;
                margin-top: 16px;
              }
              button {
                flex: 1;
                padding: 10px;
                border: none;
                border-radius: 6px;
                cursor: pointer;
                font-weight: 600;
                text-transform: uppercase;
                letter-spacing: 1px;
                transition: all 0.2s;
              }
              .btn-apply {
                background: linear-gradient(135deg, #00d4ff, #0099cc);
                color: #000;
              }
              .btn-apply:hover { transform: translateY(-2px); box-shadow: 0 4px 15px rgba(0,212,255,0.4); }
              .btn-cancel {
                background: rgba(255,255,255,0.1);
                color: #e0e0e0;
              }
              .btn-cancel:hover { background: rgba(255,255,255,0.2); }
            </style>
          </head>
          <body>
            <h2>? Select Similar</h2>
            
            <div class="section">
              <div class="section-title">Matching Criteria</div>
              <div class="row">
                <input type="checkbox" id="partial_name" #{s[:partial_name] ? 'checked' : ''}>
                <label for="partial_name">Name Search (Progressive)</label>
              </div>
              <div class="row">
                <input type="checkbox" id="name_group" #{s[:name_group] ? 'checked' : ''}>
                <label for="name_group">Name Group (incl. Prefix & Suffix)</label>
              </div>
              <div class="row" style="margin-left:28px;margin-top:-4px;margin-bottom:12px">
                <input type="text" id="name_search" value="#{s[:name_search]}" placeholder="Enter name to search..." style="flex:1;background:rgba(255,255,255,0.1);border:1px solid rgba(0,212,255,0.3);border-radius:4px;color:#fff;padding:6px 10px;font-size:12px">
              </div>
              <div class="row">
                <input type="checkbox" id="bounding_size" #{s[:bounding_size] ? 'checked' : ''}>
                <label for="bounding_size">Bounding Size</label>
                <span class="tolerance"> </span>
                <input type="number" id="size_tolerance" value="#{s[:size_tolerance]}" min="0" max="100" step="0.001">
                <span class="tolerance">%</span>
              </div>
              <div class="row">
                <input type="checkbox" id="bounding_volume" #{s[:bounding_volume] ? 'checked' : ''}>
                <label for="bounding_volume">Bounding Volume</label>
                <span class="tolerance"> </span>
                <input type="number" id="volume_tolerance" value="#{s[:volume_tolerance]}" min="0" max="100" step="0.001">
                <span class="tolerance">%</span>
              </div>
              <div class="row">
                <input type="checkbox" id="min_thickness" #{s[:min_thickness] ? 'checked' : ''}>
                <label for="min_thickness">Min Thickness</label>
                <span class="tolerance"> </span>
                <input type="number" id="thickness_tolerance" value="#{s[:thickness_tolerance]}" min="0" max="100" step="0.001">
                <span class="tolerance">%</span>
              </div>
              <div class="row">
                <input type="checkbox" id="same_material" #{s[:same_material] ? 'checked' : ''}>
                <label for="same_material">Same Material</label>
              </div>
              <div class="row">
                <input type="checkbox" id="same_tag" #{s[:same_tag] ? 'checked' : ''}>
                <label for="same_tag">Same Tag</label>
              </div>
            </div>

            <div class="section">
              <div class="section-title">Type Filter</div>
              <div class="radio-group">
                <label><input type="radio" name="type_filter" value="group" #{s[:type_filter] == 'group' ? 'checked' : ''}> Group</label>
                <label><input type="radio" name="type_filter" value="component" #{s[:type_filter] == 'component' ? 'checked' : ''}> Component</label>
                <label><input type="radio" name="type_filter" value="both" #{s[:type_filter] == 'both' ? 'checked' : ''}> Both</label>
              </div>
            </div>

            <div class="section">
              <div class="section-title">Scope</div>
              <div class="radio-group">
                <label><input type="radio" name="scope_filter" value="all" #{s[:scope_filter] == 'all' ? 'checked' : ''}> All Objects</label>
                <label><input type="radio" name="scope_filter" value="visible" #{s[:scope_filter] == 'visible' ? 'checked' : ''}> Visible Only</label>
                <label><input type="radio" name="scope_filter" value="viewport" #{s[:scope_filter] == 'viewport' ? 'checked' : ''}> In Viewport</label>
                <label><input type="radio" name="scope_filter" value="viewport_visible" #{s[:scope_filter] == 'viewport_visible' ? 'checked' : ''}> Viewport + Visible</label>
              </div>
              <div class="row" style="margin-top:8px">
                <label style="flex:1">Min Size (mm)</label>
                <input type="number" id="min_size_threshold" value="#{s[:min_size_threshold]}" min="0" step="100" placeholder="0=off" style="width:80px">
              </div>
              <div class="row" style="margin-top:4px">
                <label style="flex:1">Min All Size (mm)</label>
                <input type="number" id="min_all_size_threshold" value="#{s[:min_all_size_threshold]}" min="0" step="10" placeholder="0=off" style="width:80px">
              </div>
            </div>

            <div class="section">
              <div class="section-title">Nesting Level</div>
              <div class="radio-group">
                <label><input type="radio" name="nesting_filter" value="toplevel" #{s[:nesting_filter] == 'toplevel' ? 'checked' : ''}> Top-level Only</label>
                <label><input type="radio" name="nesting_filter" value="nested" #{s[:nesting_filter] == 'nested' ? 'checked' : ''}> Include Nested</label>
              </div>
            </div>

            <div class="section">
              <div class="section-title">Keyboard Shortcuts</div>
              <div class="row">
                <label style="flex:1">Isolate/Unisolate</label>
                <input type="text" id="key_isolate" value="#{s[:key_isolate]}" maxlength="3" style="width:60px;text-align:center;text-transform:uppercase">
              </div>
              <div class="row">
                <label style="flex:1">Settings Dialog</label>
                <input type="text" id="key_settings" value="#{s[:key_settings]}" maxlength="3" style="width:60px;text-align:center;text-transform:uppercase">
              </div>
            </div>

            <div class="btn-row">
              <button class="btn-cancel" onclick="sketchup.close_dialog()">Cancel</button>
              <button class="btn-apply" onclick="applySettings()">Apply</button>
            </div>

            <script>
              function applySettings() {
                const data = {
                partial_name: document.getElementById('partial_name').checked,
                name_group: document.getElementById('name_group').checked,
                name_search: document.getElementById('name_search').value,
                  bounding_size: document.getElementById('bounding_size').checked,
                  bounding_volume: document.getElementById('bounding_volume').checked,
                  min_thickness: document.getElementById('min_thickness').checked,
                  same_material: document.getElementById('same_material').checked,
                  same_tag: document.getElementById('same_tag').checked,
                  size_tolerance: document.getElementById('size_tolerance').value,
                  volume_tolerance: document.getElementById('volume_tolerance').value,
                  thickness_tolerance: document.getElementById('thickness_tolerance').value,
                  type_filter: document.querySelector('input[name="type_filter"]:checked').value,
                  scope_filter: document.querySelector('input[name="scope_filter"]:checked').value,
                  nesting_filter: document.querySelector('input[name="nesting_filter"]:checked').value,
                  min_size_threshold: parseInt(document.getElementById('min_size_threshold').value) || 0,
                  min_all_size_threshold: parseInt(document.getElementById('min_all_size_threshold').value) || 0,
                  key_isolate: document.getElementById('key_isolate').value.toUpperCase() || 'I',
                  key_settings: document.getElementById('key_settings').value.toUpperCase() || 'TAB'
                };
                sketchup.apply_settings(JSON.stringify(data));
              }
            </script>
          </body>
          </html>
        HTML
      end

      # -----------------------------------------------------------------------
      # RENAME DIALOG
      # -----------------------------------------------------------------------
      def show_rename_dialog(reference)
        # Use the shared rename_selected function for consistent UI
        MH::SelectSimilar.rename_selected
      end

      def build_rename_html(common_name, count)
        # Generate datalist options dynamically - include text content for display
        prefix_opts = MH::SelectSimilar.prefix_suggestions.map { |p| "<option value=\"#{p}\" style=\"background:#1a1a2e;color:#fff\">#{p}</option>" }.join("\n                    ")
        suffix_opts = MH::SelectSimilar.suffix_suggestions.map { |s| "<option value=\"#{s}\" style=\"background:#1a1a2e;color:#fff\">#{s}</option>" }.join("\n                    ")
        
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="UTF-8">
            <style>
              * { box-sizing: border-box; margin: 0; padding: 0; }
              body {
                font-family: 'Segoe UI', Arial, sans-serif;
                background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
                color: #e0e0e0;
                padding: 8px;
                font-size: 11px;
              }
              h2 {
                color: #ff6b6b;
                font-size: 12px;
                margin-bottom: 4px;
                text-align: center;
              }
              .count {
                text-align: center;
                color: #888;
                font-size: 10px;
                margin-bottom: 8px;
              }
              .section {
                background: rgba(255,255,255,0.05);
                border-radius: 4px;
                padding: 6px;
                margin-bottom: 6px;
              }
              .field {
                margin-bottom: 6px;
              }
              .field label {
                display: block;
                color: #00d4ff;
                font-size: 9px;
                text-transform: uppercase;
                margin-bottom: 2px;
              }
              .field input[type="text"] {
                width: 100%;
                background: rgba(255,255,255,0.1);
                border: 1px solid rgba(0,212,255,0.3);
                border-radius: 3px;
                color: #fff;
                padding: 4px 6px;
                font-size: 11px;
              }
              .field input[type="text"]:focus {
                outline: none;
                border-color: #00d4ff;
              }
              .inline-row {
                display: flex;
                gap: 6px;
              }
              .inline-row .field {
                flex: 1;
              }
              .numbering {
                display: flex;
                align-items: center;
                gap: 6px;
                font-size: 10px;
              }
              .numbering input[type="checkbox"] {
                width: 12px;
                height: 12px;
                accent-color: #ff6b6b;
              }
              .numbering input[type="text"] {
                width: 40px;
                text-align: center;
                padding: 2px 4px;
              }
              .btn-row {
                display: flex;
                gap: 6px;
                margin-top: 8px;
              }
              button {
                flex: 1;
                padding: 5px;
                border: none;
                border-radius: 3px;
                cursor: pointer;
                font-weight: 600;
                font-size: 10px;
                text-transform: uppercase;
              }
              .btn-apply {
                background: linear-gradient(135deg, #ff6b6b, #ee5a5a);
                color: #fff;
              }
              .btn-cancel {
                background: rgba(255,255,255,0.1);
                color: #e0e0e0;
              }
              select {
                background: #1a1a2e !important;
                color: #fff !important;
              }
              select option {
                background: #1a1a2e;
                color: #fff;
                padding: 4px;
              }
            </style>
          </head>
          <body>
            <div class="count">#{count} object(s)</div>
            
            <div class="section">
              <div class="field">
                <label>New Name</label>
                <input type="text" id="new_name" value="#{common_name}" placeholder="Enter new name..." oninput="updatePreview()">
              </div>
              <div class="inline-row">
                <div class="field">
                  <label>Prefix</label>
                  <div style="display:flex;gap:4px">
                    <input type="text" id="prefix" value="" placeholder="Prefix..." oninput="updatePreview()" style="flex:1">
                    <select id="prefix_select" onchange="selectPrefix()" style="width:80px;background:rgba(0,212,255,0.2);border:1px solid rgba(0,212,255,0.5);border-radius:3px;color:#fff;cursor:pointer;font-size:10px">
                      <option value="">Ch?n...</option>
                      #{prefix_opts}
                    </select>
                  </div>
                </div>
                <div class="field">
                  <label>Suffix</label>
                  <div style="display:flex;gap:4px">
                    <input type="text" id="suffix" value="" placeholder="Suffix..." oninput="updatePreview()" style="flex:1">
                    <select id="suffix_select" onchange="selectSuffix()" style="width:80px;background:rgba(0,212,255,0.2);border:1px solid rgba(0,212,255,0.5);border-radius:3px;color:#fff;cursor:pointer;font-size:10px">
                      <option value="">Ch?n...</option>
                      #{suffix_opts}
                    </select>
                  </div>
                </div>
              </div>
              <div class="field">
                <div class="numbering">
                  <input type="checkbox" id="add_numbering" onchange="updatePreview()">
                  <label for="add_numbering" style="margin:0;text-transform:none;color:#e0e0e0">Numbering:</label>
                  <input type="text" id="start_number" value="01" style="width:40px" oninput="updatePreview()">
                </div>
              </div>
              <div class="field" style="margin-top:6px;padding-top:6px;border-top:1px solid rgba(255,255,255,0.1)">
                <label style="color:#888">Preview</label>
                <div id="preview" style="color:#4ecdc4;font-size:11px;word-break:break-all;"></div>
              </div>
            </div>

            <div class="btn-row">
              <button class="btn-cancel" onclick="sketchup.close_dialog()">Cancel</button>
              <button class="btn-apply" onclick="applyRename()">Apply</button>
            </div>

            <script>
              const originalName = "#{common_name}";
              
              function updatePreview() {
                const newName = document.getElementById('new_name').value;
                const prefix = document.getElementById('prefix').value;
                const suffix = document.getElementById('suffix').value;
                const addNum = document.getElementById('add_numbering').checked;
                const startNum = document.getElementById('start_number').value;
                
                let base = newName || originalName || '[original name]';
                let preview = prefix + base + suffix;
                
                if (addNum && startNum) {
                  preview += startNum;
                }
                
                document.getElementById('preview').textContent = preview;
              }
              
              function applyRename() {
                const data = {
                  new_name: document.getElementById('new_name').value,
                  prefix: document.getElementById('prefix').value,
                  suffix: document.getElementById('suffix').value,
                  add_numbering: document.getElementById('add_numbering').checked,
                  start_number: document.getElementById('start_number').value
                };
                sketchup.apply_rename(JSON.stringify(data));
              }
              
              // Enter key to apply
              document.addEventListener('keydown', function(e) {
                if (e.key === 'Enter') {
                  applyRename();
                }
              });
              
              function selectPrefix() {
                const sel = document.getElementById('prefix_select');
                if (sel.value) {
                  document.getElementById('prefix').value = sel.value;
                  sel.selectedIndex = 0;
                  updatePreview();
                }
              }
              
              function selectSuffix() {
                const sel = document.getElementById('suffix_select');
                if (sel.value) {
                  document.getElementById('suffix').value = sel.value;
                  sel.selectedIndex = 0;
                  updatePreview();
                }
              }
              
              updatePreview();
            </script>
          </body>
          </html>
        HTML
      end

      def apply_rename(entities, data)
        @model.start_operation("Rename Objects", true)
        
        start_num = data['start_number'].to_i
        pad_length = data['start_number'].to_s.length
        prefix = data['prefix'].to_s
        suffix = data['suffix'].to_s
        new_base = data['new_name'].to_s.strip
        
        entities.each_with_index do |entity, idx|
          # Get current name and preserve __xxxx. prefix
          current_full_name = entity.respond_to?(:name) ? entity.name : ''
          original_prefix = ''
          if current_full_name =~ /^(__\d+\.\s*)/
            original_prefix = $1
          end
          current_name = MH::SelectSimilar.clean_name(current_full_name)
          
          # If new_name is empty, keep original name
          base_name = new_base.empty? ? current_name : new_base
          
          # Build final name: preserve original __xxxx. prefix
          final_name = original_prefix + prefix + base_name + suffix
          
          if data['add_numbering']
            num_str = (start_num + idx).to_s.rjust(pad_length, '0')
            final_name = final_name + num_str
          end
          
          entity.name = final_name
        end
        
        @model.commit_operation
        Sketchup.status_text = "Renamed #{entities.length} objects"
      end

      def getExtents
        Sketchup.active_model.bounds
      end
      
      # Filter/select objects by a specific overlay value
      def filter_by_overlay_value(type, value)
        # Toggle: clicking the same filter again clears it
        if @active_filter && @active_filter[:type] == type && @active_filter[:value] == value
          # Clear filter - re-select all objects that match the snapshot
          @active_filter = nil
          if @overlay_snapshot
            restore_snapshot_selection
          end
          Sketchup.status_text = "Filter cleared - showing all"
          return
        end
        
        # Save snapshot of current overlay lines before filtering (only if not already saved)
        @overlay_snapshot ||= @current_overlay_lines
        
        # Set active filter
        @active_filter = { type: type, value: value }
        
        # Find matching objects from ALL cached entities
        all_entities = get_cached_entities
        matches = []
        
        all_entities.each do |e|
          case type
          when :material
            mat = MH::SelectSimilar.get_material(e)
            mat_name = mat ? mat.display_name : "None"
            matches << e if mat_name == value
          when :thickness
            dims = MH::SelectSimilar.bounds_dims(e)
            if dims
              thickness = dims[0].to_mm.round(1)
              matches << e if thickness == value
            end
          when :tag
            tag = MH::SelectSimilar.get_tag(e)
            tag_name = tag ? tag.display_name : "Untagged"
            matches << e if tag_name == value
          end
        end
        
        @model.selection.clear
        @model.selection.add(matches)
        
        type_label = type.to_s.capitalize
        display_val = type == :thickness ? "#{value}mm" : value
        Sketchup.status_text = "Filtered: #{matches.length} objects with #{type_label} = #{display_val} (click again to clear)"
      end
      
      # Restore selection to all objects that were visible in the snapshot
      def restore_snapshot_selection
        return unless @overlay_snapshot
        all_entities = get_cached_entities
        
        # Collect all values from snapshot
        snap_materials = @overlay_snapshot.select { |l| l[:type] == :material }.map { |l| l[:value] }
        snap_thicknesses = @overlay_snapshot.select { |l| l[:type] == :thickness }.map { |l| l[:value] }
        snap_tags = @overlay_snapshot.select { |l| l[:type] == :tag }.map { |l| l[:value] }
        
        matches = all_entities.select do |e|
          mat = MH::SelectSimilar.get_material(e)
          mat_name = mat ? mat.display_name : "None"
          
          dims = MH::SelectSimilar.bounds_dims(e)
          thickness = dims ? dims[0].to_mm.round(1) : nil
          
          tag = MH::SelectSimilar.get_tag(e)
          tag_name = tag ? tag.display_name : "Untagged"
          
          snap_materials.include?(mat_name) || 
          (thickness && snap_thicknesses.include?(thickness)) ||
          snap_tags.include?(tag_name)
        end
        
        @model.selection.clear
        @model.selection.add(matches)
      end
      
      # Draw selection info overlay in top right corner (right-aligned, interactive)
      def draw(view)
        selection = @selection || Sketchup.active_model.selection
        selected = selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
        count = selected.length
        
        if count == 0 && !@overlay_snapshot
          @overlay_hitboxes = []
          @cached_overlay_lines = nil
          @overlay_dirty = true
          return
        end
        
        # Detect selection change by count (fast check)
        if count != @cached_overlay_count
          @overlay_dirty = true
          @cached_overlay_count = count
        end
        
        # Use snapshot lines if a filter is active, otherwise build from selection
        if @overlay_snapshot && @active_filter
          lines = @overlay_snapshot.map { |l| l.dup }
          # Update the Selected count to reflect current filtered selection
          lines[0] = { text: MH::SelectSimilar.isolated? ? "[Unisolate]" : "[Isolate]", header: false, type: :isolate, value: nil }
          lines[1] = { text: "Selected: #{count}", header: true, type: nil, value: nil }
        elsif @overlay_dirty || @cached_overlay_lines.nil?
          # Only recompute when dirty (selection changed)
          materials = []
          thicknesses = []
          tags = []
          
          selected.each do |e|
            mat = MH::SelectSimilar.get_material(e)
            materials << (mat ? mat.display_name : "None")
            
            dims = MH::SelectSimilar.bounds_dims(e)
            if dims
              thicknesses << dims[0].to_mm.round(1)
            else
              thicknesses << nil
            end
            
            tag = MH::SelectSimilar.get_tag(e)
            tags << (tag ? tag.display_name : "Untagged")
          end
          
          unique_materials = materials.uniq
          unique_thicknesses = thicknesses.compact.uniq.sort
          unique_tags = tags.uniq
          
          lines = []
          lines << { text: MH::SelectSimilar.isolated? ? "[Unisolate]" : "[Isolate]", header: false, type: :isolate, value: nil }
          lines << { text: "Selected: #{count}", header: true, type: nil, value: nil }
          lines << { text: "Material:", header: true, type: nil, value: nil }
          unique_materials.each { |m| lines << { text: m, header: false, type: :material, value: m } }
          lines << { text: "Thickness:", header: true, type: nil, value: nil }
          if unique_thicknesses.empty?
            lines << { text: "N/A", header: true, type: nil, value: nil }
          else
            unique_thicknesses.each { |t| lines << { text: "#{t}mm", header: false, type: :thickness, value: t } }
          end
          lines << { text: "Tag:", header: true, type: nil, value: nil }
          unique_tags.each { |t| lines << { text: t, header: false, type: :tag, value: t } }
          
          # Cache and store for potential snapshot
          @cached_overlay_lines = lines.map { |l| l.dup }
          @current_overlay_lines = @cached_overlay_lines
          @overlay_dirty = false
        else
          # Use cached lines (fast path - no recomputation)
          lines = @cached_overlay_lines.map { |l| l.dup }
          # Always update isolate button text and count
          lines[0] = { text: MH::SelectSimilar.isolated? ? "[Unisolate]" : "[Isolate]", header: false, type: :isolate, value: nil }
          lines[1] = { text: "Selected: #{count}", header: true, type: nil, value: nil }
        end
        
        # Text styles
        header_opts = {
          font: "Arial",
          size: 12,
          bold: true,
          color: Sketchup::Color.new(0, 0, 0)
        }
        value_opts = {
          font: "Arial",
          size: 12,
          bold: true,
          color: Sketchup::Color.new(150, 75, 0)
        }
        hover_opts = {
          font: "Arial",
          size: 12,
          bold: true,
          color: Sketchup::Color.new(0, 100, 220)
        }
        active_opts = {
          font: "Arial",
          size: 12,
          bold: true,
          color: Sketchup::Color.new(0, 160, 0)
        }
        dimmed_opts = {
          font: "Arial",
          size: 12,
          bold: false,
          color: Sketchup::Color.new(180, 180, 180)
        }
        
        # Layout
        char_width = 10
        vp_width = view.vpwidth
        anchor_right = vp_width - 10
        y_start = 14
        line_height = 18
        
        # Collect values present in the CURRENT selection (for highlighting)
        sel_materials = Set.new
        sel_thicknesses = Set.new
        sel_tags = Set.new
        if @active_filter
          selected.each do |e|
            mat = MH::SelectSimilar.get_material(e)
            sel_materials << (mat ? mat.display_name : "None")
            
            dims = MH::SelectSimilar.bounds_dims(e)
            sel_thicknesses << dims[0].to_mm.round(1) if dims
            
            tag = MH::SelectSimilar.get_tag(e)
            sel_tags << (tag ? tag.display_name : "Untagged")
          end
        end
        
        # Build hitboxes and draw
        new_hitboxes = []
        
        lines.each_with_index do |item, idx|
          text_len = item[:text].length
          text_w = text_len * char_width
          x = anchor_right - text_w
          y = y_start + idx * line_height
          
          if item[:type] == :isolate
            # Isolate button styling
            is_hovered = (@mouse_x >= x && @mouse_x <= x + text_w &&
                          @mouse_y >= y && @mouse_y <= y + line_height)
            
            if is_hovered
              opts = hover_opts
              MH::OverlayEngine.line2d(view, [[x, y + line_height - 2, 0], [x + text_w, y + line_height - 2, 0]], color: Sketchup::Color.new(0, 100, 220), width: 1)
            elsif MH::SelectSimilar.isolated?
              opts = active_opts
            else
              opts = value_opts
            end
            
            new_hitboxes << { x: x, y: y, w: text_w, h: line_height, type: :isolate, value: nil }
          elsif item[:type]
            is_active = @active_filter && 
                        @active_filter[:type] == item[:type] && 
                        @active_filter[:value] == item[:value]
            
            is_hovered = (@mouse_x >= x && @mouse_x <= x + text_w &&
                          @mouse_y >= y && @mouse_y <= y + line_height)
            
            # Check if this value is present in the current selection
            in_selection = case item[:type]
                           when :material then sel_materials.include?(item[:value])
                           when :thickness then sel_thicknesses.include?(item[:value])
                           when :tag then sel_tags.include?(item[:value])
                           else false
                           end
            
            if is_active
              opts = active_opts
              MH::OverlayEngine.line2d(view, [[x, y + line_height - 2, 0], [x + text_w, y + line_height - 2, 0]], color: Sketchup::Color.new(0, 160, 0), width: 2)
            elsif is_hovered
              opts = hover_opts
              MH::OverlayEngine.line2d(view, [[x, y + line_height - 2, 0], [x + text_w, y + line_height - 2, 0]], color: Sketchup::Color.new(0, 100, 220), width: 1)
            elsif @active_filter && !in_selection
              opts = dimmed_opts
            else
              opts = value_opts
            end
            
            new_hitboxes << { x: x, y: y, w: text_w, h: line_height, type: item[:type], value: item[:value] }
          else
            opts = header_opts
          end
          
          MH::OverlayEngine.text(view, x, y, item[:text], options: opts)
        end
        
        @overlay_hitboxes = new_hitboxes
      end
    end

    # =========================================================================
    # MENU & TOOLBAR
    # =========================================================================
    unless defined?(@mh_select_similar_loaded)
      @mh_select_similar_loaded = true

      # Toolbar
      toolbar = UI::Toolbar.new("MH Select Tools")
      icons_dir = File.join(__dir__, 'icons')
      
      # Select Similar command
      cmd1 = UI::Command.new("Select Similar") {
        Sketchup.active_model.select_tool(SelectSimilarTool.new)
      }
      cmd1.tooltip = "Select Similar Objects"
      cmd1.status_bar_text = "Click to select similar objects"
      icon1 = File.join(icons_dir, 'select_similar.svg')
      if File.exist?(icon1)
        cmd1.small_icon = icon1
        cmd1.large_icon = icon1
      end
      toolbar.add_item(cmd1)
      
      # Isolate command
      cmd2 = UI::Command.new("Isolate/Unisolate") {
        MH::SelectSimilar.toggle_isolate
        Sketchup.active_model.active_view.invalidate
      }
      cmd2.tooltip = "Isolate/Unisolate Selected Objects"
      cmd2.status_bar_text = "Toggle visibility of non-selected objects"
      icon2 = File.join(icons_dir, 'isolate.svg')
      if File.exist?(icon2)
        cmd2.small_icon = icon2
        cmd2.large_icon = icon2
      end
      toolbar.add_item(cmd2)
      
      toolbar.restore
    end

    # Reload method for development
    def self.reload
      load File.join(__dir__, 'main.rb')
      dbg("MH::SelectSimilar reloaded")
    end

    # Auto-load settings and suggestions on startup
    load_settings
    auto_load_suggestions

  end
end


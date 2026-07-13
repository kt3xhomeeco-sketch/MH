# encoding: UTF-8
# frozen_string_literal: true

require 'sketchup.rb'
require 'json'
require 'base64'

module MH
  module Highlight
    PLUGIN_ID = 'mh.highlight'.freeze
    OVERLAY_ID = 'mh.highlight.edges'.freeze
    OVERLAY_NAME = 'MH Highlight Edges'.freeze
    PREF_SECTION = 'MH_highlight'.freeze
    # SketchUp Preferences evaluates persisted values as Ruby. Store Base64
    # instead of JSON so the value contains no embedded quotes or braces.
    PREF_KEY = 'tag_styles_v3'.freeze
    DEFAULT_COLOR = '#ff3b30'.freeze
    DEFAULT_WIDTH = 3
    MAX_WIDTH = 10
    EDGES_PER_CHUNK = 2_000
    EDGES_PER_TIMER_TICK = 1_000
    REBUILD_DEBOUNCE_SECONDS = 0.35

    # Every configured tag is active. The checkbox in the dialog controls this
    # per-tag X-ray mode instead of enabling/disabling the tag.
    TagStyle = Struct.new(:xray, :color, :width, keyword_init: true)
    Chunk = Struct.new(:points, :bounds, keyword_init: true)

    # A Sketchup::Overlay does not activate a Tool, so normal SketchUp tools and
    # third-party commands remain usable while the highlight is enabled.
    class EdgeOverlay < Sketchup::Overlay
      def initialize
        super(OVERLAY_ID, OVERLAY_NAME)
      end

      def start
        MH::Highlight.invalidate_view
      end

      def stop
        MH::Highlight.invalidate_view
      end

      def draw(view)
        MH::Highlight.draw(view)
      rescue => error
        puts "[MH Highlight] draw failed: #{error.class}: #{error.message}"
      end
    end

    class ModelChangeObserver < Sketchup::ModelObserver
      def onTransactionCommit(_model)
        MH::Highlight.model_changed
      end

      def onTransactionUndo(_model)
        MH::Highlight.model_changed
      end

      def onTransactionRedo(_model)
        MH::Highlight.model_changed
      end

      def onEraseAll(_model)
        MH::Highlight.model_changed
      end
    end

    class AppChangeObserver < Sketchup::AppObserver
      def onNewModel(model)
        MH::Highlight.model_opened(model)
      end

      def onOpenModel(model)
        MH::Highlight.model_opened(model)
      end
    end

    class ViewChangeObserver < Sketchup::ViewObserver
      def onViewChanged(_view)
        # Camera movement only redraws/culls cached chunks. It never scans model
        # entities or rebuilds edge coordinates.
        MH::Highlight.invalidate_view
      end
    end

    class << self
      def start
        return if @started

        @started = true
        @styles = load_styles
        @cache = {} # { tag_name => [Chunk, ...] }
        @cache_model = nil
        @cache_dirty = true
        @scan_generation = 0
        install_commands
        attach_app_observer
      rescue => error
        puts "[MH Highlight] start failed: #{error.class}: #{error.message}"
      end

      def toggle
        start
        ensure_overlay
        return unless @overlay

        @overlay.enabled = !@overlay.enabled?
        if @overlay.enabled?
          attach_model_observers(Sketchup.active_model)
          request_rebuild(0.0) if cache_stale?
        else
          cancel_rebuild
        end
        invalidate_view
        refresh_dialog
      rescue => error
        UI.messagebox("MH Highlight loi: #{error.message}")
      end

      def show_dialog
        start
        ensure_overlay
        build_dialog unless @dialog && @dialog.visible?
        @dialog.show
        refresh_dialog
      rescue => error
        UI.messagebox("Khong mo duoc MH Highlight: #{error.message}")
      end

      def refresh_cache
        start
        ensure_overlay
        attach_model_observers(Sketchup.active_model)
        request_rebuild(0.0, force: true)
      end

      def model_opened(model)
        @cache = {}
        @cache_model = nil
        @cache_dirty = true
        @scan_generation = @scan_generation.to_i + 1
        attach_model_observers(model) if enabled?
        refresh_dialog
      end

      def model_changed
        @cache_dirty = true
        return unless enabled?

        request_rebuild(REBUILD_DEBOUNCE_SECONDS)
      end

      def invalidate_view
        Sketchup.active_model.active_view.invalidate
      rescue
        nil
      end

      def enabled?
        @overlay && @overlay.respond_to?(:enabled?) && @overlay.enabled?
      rescue
        false
      end

      # Called by EdgeOverlay. This deliberately contains no entity traversal.
      def draw(view)
        return unless enabled?

        @cache.each do |tag_name, chunks|
          style = style_for(tag_name)
          color = sketchup_color(style.color)
          view.drawing_color = color
          view.line_width = style.width
          chunks.each do |chunk|
            next unless chunk_visible?(view, chunk.bounds)

            if style.xray
              # draw2d is not depth-tested. Coordinates are projected from the
              # cached world points only; no entity/model traversal happens here.
              view.draw2d(GL_LINES, screen_points(view, chunk))
            else
              view.draw(GL_LINES, chunk.points)
            end
          end
        end
      ensure
        view.line_width = 1 if view
      end

      private

      def install_commands
        toggle_command = UI::Command.new('Bat/tat MH Highlight') { toggle }
        toggle_command.tooltip = 'Bat/tat highlight edge theo Tag'
        toggle_command.status_bar_text = 'Bat/tat overlay highlight edge theo Tag'
        icon = File.join(__dir__, 'icons', 'mh_highlight.svg')
        toggle_command.small_icon = icon
        toggle_command.large_icon = icon
        toggle_command.set_validation_proc { enabled? ? MF_CHECKED : MF_UNCHECKED }

        dialog_command = UI::Command.new('Cau hinh MH Highlight') { show_dialog }
        dialog_command.tooltip = 'Cau hinh Tag, mau va do day highlight'

        refresh_command = UI::Command.new('Lam moi cache MH Highlight') { refresh_cache }

        menu = UI.menu('Extensions').add_submenu('MH Highlight')
        menu.add_item(toggle_command)
        menu.add_item(dialog_command)
        menu.add_item(refresh_command)

        toolbar = UI::Toolbar.new('MH Highlight')
        toolbar.add_item(toggle_command)
        toolbar.add_item(dialog_command)
        toolbar.show
      end

      def attach_app_observer
        return if @app_observer

        @app_observer = AppChangeObserver.new
        Sketchup.add_observer(@app_observer)
      end

      def attach_model_observers(model)
        return unless model
        return if @observed_model == model && @model_observer && @view_observer

        detach_model_observers
        @observed_model = model
        @model_observer = ModelChangeObserver.new
        model.add_observer(@model_observer)
        @view_observer = ViewChangeObserver.new
        model.active_view.add_observer(@view_observer)
      rescue => error
        puts "[MH Highlight] observer attach failed: #{error.message}"
      end

      def detach_model_observers
        if @observed_model && @model_observer
          @observed_model.remove_observer(@model_observer)
        end
        if @observed_model && @view_observer
          @observed_model.active_view.remove_observer(@view_observer)
        end
      rescue
        nil
      ensure
        @observed_model = @model_observer = @view_observer = nil
      end

      def ensure_overlay
        return nil unless defined?(Sketchup::Overlay)

        model = Sketchup.active_model
        if @overlay.nil? || @overlay_model != model
          @overlay = EdgeOverlay.new
          model.overlays.add(@overlay)
          @overlay_model = model
        end
        @overlay
      rescue => error
        puts "[MH Highlight] overlay unavailable: #{error.message}"
        nil
      end

      def cache_stale?
        @cache_dirty || @cache_model != Sketchup.active_model || @cache.nil? || @cache.empty?
      end

      def request_rebuild(delay = REBUILD_DEBOUNCE_SECONDS, force: false)
        return unless enabled?

        @scan_generation = @scan_generation.to_i + 1
        generation = @scan_generation
        stop_timer(@rebuild_timer)
        @rebuild_timer = UI.start_timer(delay, false) do
          next unless enabled? && generation == @scan_generation

          begin_rebuild(generation, force)
        end
      end

      def cancel_rebuild
        @scan_generation = @scan_generation.to_i + 1
        stop_timer(@rebuild_timer)
        stop_timer(@scan_timer)
        @rebuild_timer = @scan_timer = nil
      rescue
        nil
      end

      def begin_rebuild(generation, _force = false)
        model = Sketchup.active_model
        selected_tags = active_tag_names
        if selected_tags.empty?
          @cache = {}
          @cache_model = model
          @cache_dirty = false
          invalidate_view
          refresh_dialog
          return
        end

        @scan_started_at = Time.now
        @scan_edge_count = 0
        @scan_builder = Hash.new { |hash, key| hash[key] = { chunks: [], points: [], bounds: nil } }
        @scan_enumerator = edge_enumerator(model, selected_tags)
        scan_next_batch(generation, model)
      rescue => error
        puts "[MH Highlight] cache setup failed: #{error.class}: #{error.message}"
      end

      def scan_next_batch(generation, model)
        return unless enabled? && generation == @scan_generation && Sketchup.active_model == model

        processed = 0
        begin
          while processed < EDGES_PER_TIMER_TICK
            tag_name, first, second = @scan_enumerator.next
            append_edge(tag_name, first, second)
            processed += 1
          end
          @scan_timer = UI.start_timer(0.0, false) { scan_next_batch(generation, model) }
        rescue StopIteration
          finalize_rebuild(model)
        rescue => error
          puts "[MH Highlight] cache scan failed: #{error.class}: #{error.message}"
        end
      end

      def append_edge(tag_name, first, second)
        entry = @scan_builder[tag_name]
        entry[:points] << first << second
        bounds_add(entry, first)
        bounds_add(entry, second)
        @scan_edge_count += 1
        return unless entry[:points].length >= EDGES_PER_CHUNK * 2

        entry[:chunks] << Chunk.new(points: entry[:points], bounds: entry[:bounds])
        entry[:points] = []
        entry[:bounds] = nil
      end

      def bounds_add(entry, point)
        bounds = entry[:bounds] ||= Geom::BoundingBox.new
        bounds.add(point)
      end

      def finalize_rebuild(model)
        next_cache = {}
        @scan_builder.each do |tag_name, entry|
          entry[:chunks] << Chunk.new(points: entry[:points], bounds: entry[:bounds]) unless entry[:points].empty?
          next_cache[tag_name] = entry[:chunks] unless entry[:chunks].empty?
        end
        @cache = next_cache
        @cache_model = model
        @cache_dirty = false
        elapsed = Time.now - @scan_started_at
        puts format('[MH Highlight] cached %d edges in %.2fs', @scan_edge_count, elapsed)
        @scan_enumerator = @scan_builder = @scan_timer = nil
        invalidate_view
        refresh_dialog
      end

      # Traverses only while rebuilding. A selected tagged instance supplies the
      # effective tag to all nested raw edges; a nested selected tag takes over.
      def edge_enumerator(model, selected_tags)
        Enumerator.new do |yielded|
          walk_entities(model.entities, Geom::Transformation.new, nil, selected_tags, yielded)
        end
      end

      def walk_entities(entities, transform, inherited_tag, selected_tags, yielded)
        entities.each do |entity|
          next unless entity.valid?
          next if entity.hidden?
          next unless entity_layer_visible?(entity)

          if entity.is_a?(Sketchup::Edge)
            next unless inherited_tag
            next if entity.soft? || entity.smooth?

            yielded << [inherited_tag, entity.start.position.transform(transform), entity.end.position.transform(transform)]
          elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
            tag_name = entity.layer ? entity.layer.name.to_s : ''
            effective_tag = selected_tags.include?(tag_name) ? tag_name : inherited_tag
            child_entities = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
            walk_entities(child_entities, transform * entity.transformation, effective_tag, selected_tags, yielded)
          end
        end
      rescue => error
        puts "[MH Highlight] entity traversal warning: #{error.message}"
      end

      def entity_layer_visible?(entity)
        layer = entity.layer
        !layer || !layer.respond_to?(:visible?) || layer.visible?
      rescue
        true
      end

      # Conservative chunk culling: test only eight cached bounding-box corners.
      # It never touches model entities and deliberately keeps partly-visible
      # chunks rather than risk hiding a highlight at the viewport border.
      def chunk_visible?(view, bounds)
        return true unless bounds && bounds.valid?

        screen = 8.times.map do |index|
          point = bounds.corner(index)
          view.screen_coords(point)
        end
        width = view.vpwidth.to_f
        height = view.vpheight.to_f
        return false if screen.all? { |point| point.x < 0 }
        return false if screen.all? { |point| point.x > width }
        return false if screen.all? { |point| point.y < 0 }
        return false if screen.all? { |point| point.y > height }

        true
      rescue
        true
      end

      def screen_points(view, chunk)
        # Reuse one mutable screen buffer per chunk. Camera changes only update
        # x/y values; the cached world-coordinate array stays untouched.
        buffer = chunk.instance_variable_get(:@mh_screen_points)
        unless buffer && buffer.length == chunk.points.length
          buffer = Array.new(chunk.points.length) { Geom::Point3d.new }
          chunk.instance_variable_set(:@mh_screen_points, buffer)
        end
        chunk.points.each_with_index do |point, index|
          screen = view.screen_coords(point)
          target = buffer[index]
          target.x = screen.x
          target.y = screen.y
          target.z = 0
        end
        buffer
      end

      def build_dialog
        @dialog = UI::HtmlDialog.new(
          dialog_title: 'MH Highlight',
          preferences_key: 'MH_Highlight_Dialog',
          scrollable: true,
          resizable: true,
          width: 570,
          height: 540,
          min_width: 430,
          min_height: 320,
          style: UI::HtmlDialog::STYLE_UTILITY
        )
        @dialog.set_html(dialog_html)
        @dialog.add_action_callback('ready') { |_dialog| refresh_dialog }
        @dialog.add_action_callback('upsertTag') do |_dialog, old_name, tag_name, xray, color, width|
          upsert_style(old_name, tag_name, xray == 'true', color, width)
        end
        @dialog.add_action_callback('removeTag') { |_dialog, tag_name| remove_style(tag_name) }
        @dialog.add_action_callback('toggleOverlay') { |_dialog| toggle }
        @dialog.add_action_callback('refreshCache') { |_dialog| refresh_cache }
        @dialog.set_on_closed { @dialog = nil }
      end

      def refresh_dialog
        return unless @dialog && @dialog.visible?

        data = {
          enabled: enabled?,
          scanning: !@scan_enumerator.nil?,
          edge_count: @scan_edge_count || cache_edge_count,
          tags: configured_tag_names.map do |name|
            style = style_for(name)
            { name: name, xray: style.xray, color: style.color, width: style.width }
          end
        }
        @dialog.execute_script("window.MHHighlight && window.MHHighlight.render(#{JSON.generate(data)});")
      rescue => error
        puts "[MH Highlight] dialog refresh failed: #{error.message}"
      end

      def upsert_style(old_name, tag_name, xray, color, width)
        old_name = old_name.to_s.strip
        name = tag_name.to_s.strip
        if name.empty?
          remove_style(old_name) unless old_name.empty?
          return
        end

        @styles.delete(old_name) if !old_name.empty? && old_name != name
        old = @styles[name]
        style = TagStyle.new(xray: !!xray, color: normalize_color(color), width: normalize_width(width))
        @styles[name] = style
        save_styles
        # Editing the tag name changes cache membership. Color/width/X-ray only
        # alter drawing and do not scan the model again.
        membership_changed = old_name != name || old.nil?
        @cache_dirty = true if membership_changed
        request_rebuild(0.0) if membership_changed && enabled?
        invalidate_view
        refresh_dialog
      end

      def remove_style(tag_name)
        name = tag_name.to_s.strip
        return if name.empty?

        removed = @styles.delete(name)
        return unless removed

        save_styles
        @cache_dirty = true
        request_rebuild(0.0) if enabled?
        invalidate_view
        refresh_dialog
      end

      def configured_tag_names
        (@styles || {}).keys.map(&:to_s).reject(&:empty?).sort
      end

      def active_tag_names
        configured_tag_names
      end

      def style_for(tag_name)
        @styles ||= load_styles
        key = tag_name.to_s
        stored = @styles[key]
        # Hot reload can retain Struct instances created by the prior version.
        # Convert the old enabled/color/width form before the new draw/dialog
        # code reads xray from it.
        if stored && !stored.respond_to?(:xray)
          stored = TagStyle.new(
            xray: stored.respond_to?(:enabled) ? !!stored.enabled : true,
            color: stored.respond_to?(:color) ? normalize_color(stored.color) : DEFAULT_COLOR,
            width: stored.respond_to?(:width) ? normalize_width(stored.width) : DEFAULT_WIDTH
          )
          @styles[key] = stored
        end
        @styles[key] ||= TagStyle.new(xray: true, color: DEFAULT_COLOR, width: DEFAULT_WIDTH)
      end

      def load_styles
        encoded = Sketchup.read_default(PREF_SECTION, PREF_KEY, Base64.strict_encode64('{}')).to_s
        parsed = JSON.parse(Base64.strict_decode64(encoded))
        parsed.each_with_object({}) do |(name, value), styles|
          value = {} unless value.is_a?(Hash)
          styles[name.to_s] = TagStyle.new(
            # Existing configurations used enabled. They are migrated as active
            # tags, with their old checkbox state becoming the X-ray state.
            xray: value.key?('xray') ? !!value['xray'] : !!value['enabled'],
            color: normalize_color(value['color']),
            width: normalize_width(value['width'])
          )
        end
      rescue
        {}
      end

      def save_styles
        serializable = @styles.each_with_object({}) do |(name, style), data|
          data[name] = { xray: style.xray, color: style.color, width: style.width }
        end
        Sketchup.write_default(PREF_SECTION, PREF_KEY, Base64.strict_encode64(JSON.generate(serializable)))
      rescue => error
        puts "[MH Highlight] settings save failed: #{error.message}"
      end

      def normalize_color(value)
        color = value.to_s.strip
        color.match?(/\A#[0-9a-fA-F]{6}\z/) ? color.downcase : DEFAULT_COLOR
      end

      def normalize_width(value)
        [[value.to_i, 1].max, MAX_WIDTH].min
      end

      def sketchup_color(hex)
        value = normalize_color(hex)
        Sketchup::Color.new(value[1..2].to_i(16), value[3..4].to_i(16), value[5..6].to_i(16))
      end

      def cache_edge_count
        @cache.values.flatten.sum { |chunk| chunk.points.length / 2 }
      rescue
        0
      end

      def stop_timer(timer_id)
        UI.stop_timer(timer_id) if timer_id && UI.respond_to?(:stop_timer)
      rescue
        nil
      end

      def dialog_html
        <<~HTML
          <!doctype html>
          <html><head><meta charset="utf-8"><style>
            * { box-sizing: border-box; } body { margin: 0; padding: 16px; font: 13px 'Segoe UI', Arial, sans-serif; color: #202124; background: #f7f8fa; }
            header { display:flex; align-items:center; justify-content:space-between; gap:12px; margin-bottom:14px; } h2 { margin:0; font-size:18px; } .status { color:#5f6368; font-size:12px; }
            .actions { display:flex; gap:8px; margin-bottom:12px; } button { border:0; border-radius:5px; padding:8px 12px; color:white; background:#1769e0; cursor:pointer; } button.secondary { background:#5f6368; } button.remove { color:#b3261e; background:transparent; padding:3px 6px; font-size:18px; line-height:16px; }
            table { width:100%; border-collapse:collapse; background:white; border:1px solid #dfe3e8; } th { text-align:left; font-size:12px; color:#5f6368; background:#f1f3f4; padding:9px; } td { border-top:1px solid #edf0f2; padding:7px 9px; } th:nth-child(1) { width:58%; } th:nth-child(2) { width:22%; } th:nth-child(3) { width:20%; }
            .tag { display:flex; align-items:center; gap:7px; } .tag-name { min-width:0; flex:1; padding:5px; border:1px solid #c7ccd1; border-radius:4px; } .xray { accent-color:#1769e0; } .xray-label { color:#5f6368; font-size:11px; white-space:nowrap; } input[type=color] { width:42px; height:26px; padding:0; border:0; background:transparent; cursor:pointer; } input[type=number] { width:58px; padding:5px; border:1px solid #c7ccd1; border-radius:4px; } .hint { color:#6f757b; font-size:12px; margin:0 0 10px; }
          </style></head><body>
            <header><div><h2>MH Highlight</h2><div id="status" class="status">Dang tai...</div></div></header>
            <p class="hint">Nhap ten Tag thu cong. Tag da nhap se luon highlight; tick <em>Xuyen obj</em> de hien ca phan bi che.</p>
            <div class="actions"><button id="toggle">Bat overlay</button><button id="add">+ Them Tag</button><button id="refresh" class="secondary">Lam moi cache</button></div>
            <table><thead><tr><th>Ten Tag</th><th>Mau highlight</th><th>Do day (px)</th></tr></thead><tbody id="rows"></tbody></table>
            <script>
              const bridge = (name, ...args) => window.sketchup && window.sketchup[name] && window.sketchup[name](...args);
              const rows = document.getElementById('rows');
              function send(row) { const name=row.querySelector('.tag-name').value.trim(); bridge('upsertTag', row.dataset.name || '', name, row.querySelector('.xray').checked ? 'true' : 'false', row.querySelector('.color').value, row.querySelector('.width').value); row.dataset.name=name; }
              function addRow(tag={name:'',xray:true,color:'#ff3b30',width:3}) { const tr=document.createElement('tr'); tr.dataset.name=tag.name || ''; tr.innerHTML='<td><div class="tag"><input class="tag-name" type="text" placeholder="Nhap ten Tag"><label class="xray-label" title="Hien highlight xuyen qua vat the"><input class="xray" type="checkbox"> Xuyen obj</label><button class="remove" title="Xoa Tag">×</button></div></td><td><input class="color" type="color"></td><td><input class="width" type="number" min="1" max="10" step="1"></td>'; tr.querySelector('.tag-name').value=tag.name || ''; tr.querySelector('.xray').checked=tag.xray !== false; tr.querySelector('.color').value=tag.color || '#ff3b30'; tr.querySelector('.width').value=tag.width || 3; tr.querySelectorAll('input').forEach(input => input.addEventListener('change', () => send(tr))); tr.querySelector('.remove').addEventListener('click', () => { if(tr.dataset.name) bridge('removeTag', tr.dataset.name); else tr.remove(); }); rows.appendChild(tr); }
              window.MHHighlight = { render(data) {
                document.getElementById('toggle').textContent = data.enabled ? 'Tat overlay' : 'Bat overlay';
                document.getElementById('status').textContent = data.scanning ? 'Dang cap nhat cache...' : (data.edge_count || 0).toLocaleString() + ' edge da cache';
                rows.innerHTML = '';
                data.tags.forEach(addRow);
              }};
              document.getElementById('toggle').addEventListener('click', () => bridge('toggleOverlay'));
              document.getElementById('add').addEventListener('click', () => addRow());
              document.getElementById('refresh').addEventListener('click', () => bridge('refreshCache'));
              bridge('ready');
            </script>
          </body></html>
        HTML
      end
    end

    start
  end
end

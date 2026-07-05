# encoding: UTF-8
# Experimental visibility overlays for MH_fast_rename.
# This file is intentionally separate from main.rb and does not modify model data.

require File.join(Sketchup.find_support_file('Plugins'), 'MH_shared.rb')
raise "[MH_fast_rename::VisibilityLab] requires MH_shared" unless defined?(MH::Shared) && defined?(MH::OverlayEngine)

module MH
  module FastRenameVisibilityLab
    EDGES = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],
             [0,4],[1,5],[2,6],[3,7]].freeze unless defined?(EDGES)
    FACES = [[0,1,2,3],[4,5,6,7],[0,1,5,4],[3,2,6,7],[0,3,7,4],[1,2,6,5]].freeze unless defined?(FACES)
    LabZone = Struct.new(:id, :label, :bounds, :entities, :zone_type) do
      def center
        mn, mx = bounds
        Geom::Point3d.new((mn.x + mx.x) / 2.0, (mn.y + mx.y) / 2.0, (mn.z + mx.z) / 2.0)
      end

      def corners
        mn, mx = bounds
        [
          Geom::Point3d.new(mn.x,mn.y,mn.z), Geom::Point3d.new(mx.x,mn.y,mn.z),
          Geom::Point3d.new(mx.x,mx.y,mn.z), Geom::Point3d.new(mn.x,mx.y,mn.z),
          Geom::Point3d.new(mn.x,mn.y,mx.z), Geom::Point3d.new(mx.x,mn.y,mx.z),
          Geom::Point3d.new(mx.x,mx.y,mx.z), Geom::Point3d.new(mn.x,mx.y,mx.z)
        ]
      end

      def volume
        mn, mx = bounds
        (mx.x - mn.x).abs * (mx.y - mn.y).abs * (mx.z - mn.z).abs
      end
    end unless defined?(LabZone)

    def self.activate(mode)
      Sketchup.active_model.select_tool(VisibilityTool.new(mode, capture_zones))
    end

    def self.capture_zones
      from_fast_rename_tool || from_selection
    end

    def self.from_fast_rename_tool
      tool = Sketchup.active_model.tools.active_tool rescue nil
      return nil unless defined?(MH::FastRename::FastRenameTool)
      return nil unless tool.is_a?(MH::FastRename::FastRenameTool)

      zones = tool.instance_variable_get(:@zones) rescue nil
      return nil unless zones && !zones.empty?
      zones.each_with_index.map do |zone, idx|
        mn, mx = zone.bounds
        LabZone.new(idx, zone.label.to_s, [mn, mx], zone.entities, zone.zone_type)
      end
    end

    def self.from_selection
      ents = Sketchup.active_model.selection.grep(Sketchup::Drawingelement).select { |entity|
        entity.respond_to?(:bounds) && (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
      }
      ents.each_with_index.map { |entity, idx| zone_from_entity(entity, idx) }
    end

    def self.zone_from_entity(entity, idx)
      bb = entity.bounds
      label = ""
      if entity.respond_to?(:name)
        if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:code_from_entity)
          label = MH::ProductContext.code_from_entity(entity).to_s
        end
        if label.empty?
          code = defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:first_product) ? MH::NameGrammar.first_product(entity.name.to_s).to_s : ''
          label = code.empty? ? entity.name.to_s : code.upcase
        end
      end
      label = "Z#{idx + 1}" if label.empty?
      type = label.include?('.') ? :modul : :sp
      LabZone.new(idx, label, [bb.min, bb.max], [entity], type)
    end

    class VisibilityTool
      def initialize(mode, zones)
        @mode = mode
        @zones = (zones || []).sort_by { |zone| -zone.volume }
        @outer_zones = detect_outer_zones
      end

      def activate
        update_status
      end

      def deactivate(view)
        view.invalidate if view
      end

      def onCancel(_reason, view)
        Sketchup.active_model.select_tool(nil)
        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        case key
        when 27
          Sketchup.active_model.select_tool(nil)
        when 49
          @mode = :xray
        when 50
          @mode = :auto_fade
        when 51
          @mode = :top_edges
        else
          return false
        end
        update_status
        view.invalidate
        true
      end

      def draw(view)
        if @zones.empty?
          draw_empty(view)
          return
        end

        case @mode
        when :xray
          draw_xray(view)
        when :auto_fade
          draw_auto_fade(view)
        when :top_edges
          draw_top_edges(view)
        end
        draw_labels(view)
      end

      private

      def update_status
        name = case @mode
        when :xray then "X-Ray Overlay"
        when :auto_fade then "Auto Fade Outer"
        when :top_edges then "Always-On-Top Edges"
        else "Visibility Lab"
        end
        Sketchup.status_text = "#{name} | 1/2/3: switch | ESC: exit"
      end

      def draw_empty(view)
        text = "Visibility Lab: activate MH Fast Rename first or select groups/components"
        draw_screen_label(view, Geom::Point3d.new(260, 24, 0), text, Sketchup::Color.new(30,30,50,220))
      end

      def draw_xray(view)
        @zones.each do |zone|
          draw_zone_fill(view, zone, zone_color(zone, 22))
          draw_zone_edges_3d(view, zone, zone_edge_color(zone, 230), 3, "")
        end
      end

      def draw_auto_fade(view)
        @zones.each do |zone|
          outer = @outer_zones.include?(zone)
          alpha = outer ? 8 : 38
          line_alpha = outer ? 90 : 245
          stipple = outer ? "." : ""
          draw_zone_fill(view, zone, zone_color(zone, alpha))
          draw_zone_edges_3d(view, zone, zone_edge_color(zone, line_alpha), outer ? 2 : 4, stipple)
        end
      end

      def draw_top_edges(view)
        @zones.each { |zone| draw_zone_fill(view, zone, zone_color(zone, 8)) }
        @zones.each do |zone|
          width = @outer_zones.include?(zone) ? 2 : 4
          draw_zone_edges_2d(view, zone, zone_edge_color(zone, 255), width)
        end
      end

      def draw_zone_fill(view, zone, color)
        pts = zone.corners
        view.drawing_color = color
        FACES.each { |face| view.draw(GL_QUADS, pts.values_at(*face)) }
      end

      def draw_zone_edges_3d(view, zone, color, width, stipple)
        pts = zone.corners
        view.line_width = width
        view.line_stipple = stipple
        view.drawing_color = color
        EDGES.each { |a, b| view.draw(GL_LINES, [pts[a], pts[b]]) }
        view.line_stipple = ""
      end

      def draw_zone_edges_2d(view, zone, color, width)
        pts = zone.corners.map { |point| view.screen_coords(point) }
        EDGES.each { |a, b| MH::OverlayEngine.line2d(view, [pts[a], pts[b]], color: color, stipple: "", width: width) }
      end

      def draw_labels(view)
        @zones.each do |zone|
          text = zone.label.to_s
          next if text.empty?
          screen = view.screen_coords(zone.center)
          draw_screen_label(view, screen, text, Sketchup::Color.new(30,30,50,190))
        end
      end

      def draw_screen_label(view, screen, text, bg_color)
        tw = text.length * 8 + 16
        th = 22
        sx = screen.x - tw / 2
        sy = screen.y - th / 2
        pts = [
          Geom::Point3d.new(sx,sy,0), Geom::Point3d.new(sx+tw,sy,0),
          Geom::Point3d.new(sx+tw,sy+th,0), Geom::Point3d.new(sx,sy+th,0)
        ]
        MH::OverlayEngine.rect(view, sx, sy, tw, th, bg_color, pts)
        MH::OverlayEngine.text(view, screen.x, sy + 4, text, size: 14, bold: true, color: Sketchup::Color.new(255,255,255), align: 1)
      end

      def zone_color(zone, alpha)
        zone.zone_type == :modul ? Sketchup::Color.new(127,212,232,alpha) : Sketchup::Color.new(91,140,255,alpha)
      end

      def zone_edge_color(zone, alpha)
        zone.zone_type == :modul ? Sketchup::Color.new(0,180,220,alpha) : Sketchup::Color.new(255,210,70,alpha)
      end

      def detect_outer_zones
        @zones.select do |candidate|
          @zones.any? { |other| other != candidate && contains_zone?(candidate, other) }
        end
      end

      def contains_zone?(outer, inner)
        omn, omx = outer.bounds
        imn, imx = inner.bounds
        omn.x <= imn.x && omn.y <= imn.y && omn.z <= imn.z &&
          omx.x >= imx.x && omx.y >= imx.y && omx.z >= imx.z
      end
    end

    def self.install_menu
      return if @menu_installed
      return false unless defined?(MH::RegistryApp::Menu)

      MH::RegistryApp::Menu.add(app: 'Fast Rename', key: 'visibility_lab_xray', label: 'Visibility Lab - X-Ray Overlay') { activate(:xray) }
      MH::RegistryApp::Menu.add(app: 'Fast Rename', key: 'visibility_lab_auto_fade', label: 'Visibility Lab - Auto Fade Outer') { activate(:auto_fade) }
      MH::RegistryApp::Menu.add(app: 'Fast Rename', key: 'visibility_lab_top_edges', label: 'Visibility Lab - Always-On-Top Edges') { activate(:top_edges) }
      @menu_installed = true
    end
  end
end

MH::FastRenameVisibilityLab.install_menu
MH::FastRename.dbg("MH::FastRenameVisibilityLab loaded") if defined?(MH::FastRename) && MH::FastRename.respond_to?(:dbg)

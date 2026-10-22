# encoding: UTF-8
require_relative 'assembly_inspector'
require_relative 'assembly_hud_input'
require_relative 'assembly_tree'
require_relative 'contact_view'

module MH
  module ModuleStudio
    if defined?(Sketchup::Overlay)
      class AssemblyOverlay < Sketchup::Overlay
        def initialize(hud)
          super('mh.module_studio.assembly','MH Liên kết module')
          @hud = hud
        end

        def draw(view)
          @hud.draw(view)
        end

        def getExtents
          @hud.visible? ? @hud.contacts.extents : Geom::BoundingBox.new
        end
      end
    end

    # Retain session data across Tool changes; draw only while linking is active.
    class AssemblyHUD
      attr_reader :tool, :tree, :inspector, :contacts

      def initialize(tool)
        @tool = tool; @model = Sketchup.active_model
        @tree = AssemblyTree.new(@model,tool)
        @inspector = AssemblyInspector.new(tool,self,close_session:false)
        @contacts=ContactView.new(@model,tool)
      end

      def show
        return if @started
        @started = true; @closed = false
        @overlay = AssemblyOverlay.new(self)
        @model.overlays.add(@overlay)
        @overlay.enabled = true
        @timer = UI.start_timer(0.15,true) { tick }
        tick
      rescue StandardError
        close
        raise
      end

      def visible?
        !@closed && @tool.active && Sketchup.active_model.equal?(@model) && !MH::ModuleStudio.instance_variable_get(:@library)&.tool&.active
      end

      def publish(error = nil)
        @inspector.publish(error)
      end

      def open_settings
        @inspector.show
        publish
      end

      def activate_tool
        Runtime.ensure_top_level(@model)
        @model.select_tool(@tool) unless @tool.active
      end

      def tick
        return close unless Sketchup.active_model.equal?(@model)
        view = @model.active_view
        if @tool.record['id'] && !@tool.instance_variable_get(:@drag) && !@tool.instance_variable_get(:@picking)
          saved = Assembly.records(@model).find { |row| row['id']==@tool.record['id'] }
          if saved
            @tool.load_record(saved) if saved!=@tool.record
          else
            @tool.fresh
            @tool.instance_variable_set(:@picking,nil) unless @tool.active
          end
        end
        state = JSON.generate([ImportLinks.revision(@model),@tool.record,@tool.active,@model.selection.map(&:persistent_id)])
        if state!=@state
          @state = state
          view.invalidate
        end
        publish
      rescue StandardError => detail
        publish(detail.message)
      end

      def draw(view)
        return unless visible?
        @contacts.draw(view)
      rescue StandardError => detail
        @draw_error = detail.message
      end

      def close
        return if @closed
        @closed = true
        UI.stop_timer(@timer) if @timer
        @timer = nil
        AssemblyHUDInput.stop
        @model.overlays.remove(@overlay) if @overlay&.valid?
        @inspector.close
        @tool.detach_hud
        @model.select_tool(nil) if @tool.active && Sketchup.active_model.equal?(@model)
        @model.active_view.invalidate if Sketchup.active_model.equal?(@model)
      end
    end
  end
end

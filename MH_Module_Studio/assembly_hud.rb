# encoding: UTF-8
require_relative 'assembly_inspector'
require_relative 'assembly_hud_input'
require_relative 'assembly_tree'

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
          @hud.tool.getExtents
        end
      end
    end

    # Session persists when SketchUp replaces the picking Tool with Move/Scale.
    class AssemblyHUD
      attr_reader :tool, :tree, :inspector

      def initialize(tool)
        @tool = tool; @model = Sketchup.active_model
        @tree = AssemblyTree.new(@model,tool)
        @inspector = AssemblyInspector.new(tool,self)
      end

      def show
        return if @started
        @started = true; @closed = false
        @tree.rebuild
        @overlay = AssemblyOverlay.new(self)
        @model.overlays.add(@overlay)
        @overlay.enabled = true
        AssemblyHUDInput.start(@model.active_view)
        @inspector.show
        @timer = UI.start_timer(0.15,true) { tick }
        tick
      rescue StandardError
        close
        raise
      end

      def visible?
        !@closed && Sketchup.active_model.equal?(@model) && !MH::ModuleStudio.instance_variable_get(:@library)&.tool&.active
      end

      def publish(error = nil)
        @inspector.publish(error)
      end

      def activate_tool
        Runtime.ensure_top_level(@model)
        @model.select_tool(@tool) unless @tool.active
      end

      def tick
        return close unless Sketchup.active_model.equal?(@model)
        view = @model.active_view
        AssemblyHUDInput.region(visible? && @overlay.enabled? ? @tree.layout(view)['rect'] : [0,0,0,0])
        32.times do
          event = AssemblyHUDInput.poll
          break unless event
          next unless visible?
          kind,x,y = event
          kind==1 ? @tree.click(x,y,view) : @tree.scroll(kind==2 ? -1 : 1)
          view.invalidate
          break if @closed
        end
        return if @closed
        if @tool.record['id'] && !@tool.instance_variable_get(:@drag) && !@tool.instance_variable_get(:@picking)
          saved = Assembly.records(@model).find { |row| row['id']==@tool.record['id'] }
          if saved
            @tool.load_record(saved) if saved!=@tool.record
          else
            @tool.fresh
            @tool.instance_variable_set(:@picking,nil) unless @tool.active
          end
        end
        @tree.rebuild
        state = JSON.generate([@tree.rows,@tool.record,@tool.active,@model.selection.map(&:persistent_id)])
        if state!=@state
          @state = state
          view.invalidate
        end
        @inspector.position(AssemblyHUDInput.viewport) if visible?
        publish
      rescue StandardError => detail
        publish(detail.message)
      end

      def draw(view)
        return unless visible?
        @tree.draw(view)
        @tree.draw_selection(view)
        @tool.draw_geometry(view) unless @tool.active
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

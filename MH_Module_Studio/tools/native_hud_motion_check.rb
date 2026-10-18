# encoding: UTF-8
require_relative 'native_component_drag_check'

module MH
  module ModuleStudio
    # Event-loop checks use the actual native Move/Scale tools and observer ticks.
    module NativeHUDMotionCheck
      include NativeComponentDragCheck
      extend self

      def stage(&block)
        @queue << block
      end

      def advance
        job = @queue.shift
        return cleanup unless job
        job.call
        @timer = UI.start_timer(0.45,false) { advance }
      rescue StandardError => detail
        @report['error'] = [detail.message,*detail.backtrace.first(6)]
        cleanup
      end

      def hud_visible
        @tool.hud && @tool.hud.inspector.instance_variable_get(:@dialog)&.visible? &&
          @model.overlays.any? { |overlay| overlay.overlay_id=='mh.module_studio.assembly' && overlay.enabled? }
      end

      def start(expected_pid:)
        @base = File.dirname(Panel.instance_method(:request).source_location.first)
        @report_path = File.join(@base,'outputs/assembly-035/motion.json')
        @model = Sketchup.active_model
        raise 'Pinned session and top-level only' unless Process.pid==expected_pid && @model.active_path.nil?
        @originals = @model.entities.to_a
        raise 'Refuse existing managed assemblies' if @originals.any? { |e| AssemblyContainers.managed?(e) }
        @definitions = @model.definitions.to_a; @before = state(@originals)
        @selection = @model.selection.to_a; @camera = @model.active_view.camera
        @links = @model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        @checks = []; @queue = []; @report = {'ok'=>false,'checks'=>@checks,'pid'=>Process.pid}
        @a = own('MH QA Native Move A'); b = own('MH QA Native Scale B')
        @record = Assembly.save(@model,{'mode'=>'fit','a'=>own_anchor(@a,'Hông Trái',1),'c'=>own_anchor(@a,'Hông Phải',0),'b'=>own_anchor(b,'Hông Trái',0),'gap'=>3})
        @wrapper = AssemblyContainers.wrapper(@model,@record['scope'])
        @model.selection.clear; @model.selection.add(@wrapper)
        @model.active_view.zoom(@wrapper)
        @tool = AssemblyTool.new; @model.select_tool(@tool)
        stage { Sketchup.send_action('selectMoveTool:') }
        stage do
          check(@model.tools.active_tool_name.include?('Move') && !@tool.active && hud_visible,'Actual native Move Tool leaves the overlay tree and compact controls visible')
          @position = @wrapper.transformation.origin.to_a
          @model.start_operation('MH QA native Move',true)
          @wrapper.transform!(Geom::Transformation.translation([100.0/25.4,50.0/25.4,0]))
          @model.commit_operation
        end
        stage do
          check((@wrapper.transformation.origin.x-@position[0]-100.0/25.4).abs<0.001 && hud_visible,'Moving a linked component preserves native tool and persistent HUD')
          Assembly.records(@model).each { |row| Assembly.verify(@model,row) }
          check(@record['gap']==3,'Native Move preserves assembly fit clearance')
          Sketchup.send_action('selectScaleTool:')
        end
        stage do
          check(@model.tools.active_tool_name.include?('Scale') && !@tool.active && hud_visible,'Actual native Scale Tool leaves tree and controls visible')
          @before_scale = @wrapper.transformation.to_a
          @model.start_operation('MH QA native Scale',true)
          @wrapper.transformation *= Geom::Transformation.scaling(1.2,1,1)
          @model.commit_operation
        end
        stage do
          check((@wrapper.transformation.xaxis.length-1).abs<0.000001 && hud_visible,'Scale observer normalizes the assembly while keeping persistent HUD')
          current = Assembly.records(@model).find { |row| row['id']==@record['id'] }
          Assembly.verify(@model,current)
          a = Assembly.root(@model,current['a'])
          width = Assembly.projection(a,[1,0,0]).then { |low,high| high-low }
          part = Assembly.plane(@model,current['a'])
          outer = Assembly.plane(@model,current['a'].merge('side'=>0))
          thickness = AssemblyMath.dot(AssemblyMath.sub(part['point'],outer['point']),part['normal']).abs
          check((width-720).abs<0.02 && (thickness-18.6).abs<0.02,'Actual Scale observation updates outer width to 720 mm and retains 18.6 mm panel thickness')
          Sketchup.undo
        end
        stage do
          check(@wrapper.transformation.to_a==@before_scale && hud_visible,'One Undo restores native Scale with HUD still present')
          id = @model.tools.active_tool_id
          @tool.hud.close
          check(@model.tools.active_tool_id==id && !AssemblyHUDInput.active?,'Closing HUD while native Scale is active preserves Scale and restores all viewport clicks')
          @report['ok'] = true
        end
        advance
      end

      def cleanup
        UI.stop_timer(@timer) if @timer
        @tool&.hud&.close
        Assembly.instance_variable_set(:@busy,true)
        @model.start_operation('MH QA motion cleanup',true)
        added = @model.entities.to_a-@originals
        @model.active_entities.erase_entities(added) unless added.empty?
        @links.nil? ? @model.delete_attribute(Reader::DICT,AssemblyContainers::KEY) : @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,@links)
        loop do
          unused = (@model.definitions.to_a-@definitions).select { |d| d.instances.empty? }
          break if unused.empty?
          unused.each { |d| @model.definitions.remove(d) }
        end
        @model.selection.clear; @model.selection.add(@selection.select(&:valid?))
        @model.active_view.camera = @camera
        @model.commit_operation
        Assembly.instance_variable_set(:@busy,false)
        Assembly.watch(@model).reset; ScaleRedraw.watch(@model).reset
        @report['originals_retained'] = @before==state(@originals) && (@model.entities.to_a-@originals).empty?
        @report['definitions_retained'] = @definitions==@model.definitions.to_a
        @report['ok'] &&= @report['originals_retained'] && @report['definitions_retained']
        File.write(@report_path,JSON.pretty_generate(@report))
      end
    end
  end
end

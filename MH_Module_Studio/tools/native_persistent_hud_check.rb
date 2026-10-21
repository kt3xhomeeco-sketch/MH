# encoding: UTF-8
require_relative 'native_library_placement_check'

module MH
  module ModuleStudio
    module NativePersistentHUDCheck
      include NativeLibraryPlacementCheck
      extend self

      def persistent_checks
        a = own('MH QA HUD Module A'); b = own('MH QA HUD Module B')
        record = Assembly.save(@model,{'mode'=>'contact','a'=>own_anchor(a,'Hông Phải',1),'b'=>own_anchor(b,'Hông Trái',0),'gap'=>3})
        wrapper = AssemblyContainers.wrapper(@model,record['scope'])
        @model.selection.clear; @model.selection.add(wrapper)
        tool = AssemblyTool.new
        @model.select_tool(tool)
        hud = tool.hud; tree = hud.tree; view = @model.active_view
        check(hud && AssemblyHUDInput.active? && @model.overlays.any? { |overlay| overlay.overlay_id=='mh.module_studio.assembly' && overlay.enabled? },'Assembly HUD installs an enabled persistent overlay and a bounded mouse filter')
        hud.tick
        check(tree.rows.any? { |row| row['name']=='MH QA HUD Module A' } && tree.rows.any? { |row| row['record']==record['id'] },'Viewport tree contains actual grouped modules and saved relationship rows')
        row = tree.rows.find { |item| item['ref'] && item['ref']['root']==record['b']['root'] }
        tree.toggle(row['id']); tree.rebuild
        child = tree.rows.find { |item| item.dig('ref','root')==record['b']['root'] && item['kind']=='panel' && item['name']=='Hông Trái' }
        check(child,'Expanded module branch includes actual panel groups')
        before = state([wrapper])
        tree.instance_variable_set(:@offset,tree.rows.index(child))
        rect = tree.layout(view)['rect']
        first = tree.visible(view).index(child)
        tree.click(rect[0]+130,rect[1]+33+first*25+10,view)
        check(tree.reference && tree.reference['part']==child['ref']['part'] && @model.selection.first==wrapper && before==state([wrapper]),'Tree panel selection highlights its real instance without changing geometry or entering edit mode')
        hud.draw(view)
        check(hud.instance_variable_get(:@draw_error).nil?,'Tree and panel outline render through actual SketchUp Overlay')
        @model.select_tool(nil)
        hud.tick
        check(!tool.active && tool.hud==hud && AssemblyHUDInput.active? && hud.inspector.instance_variable_get(:@dialog).visible?,'Switching away from assembly Tool keeps tree, controls and mouse input alive')
        tool.action(:pick,'b')
        check(tool.active && tool.hud==hud && tool.instance_variable_get(:@picking)=='b','Clicking a face field reactivates the same picking Tool without losing the HUD')
        tool.cancel_gesture
        tool.action(:value,['gap',7])
        current = Assembly.records(@model).find { |item| item['id']==record['id'] }
        check(tool.error.nil? && current['gap']==7,'Compact relationship input still applies geometry and saved gap')
        tool.action(:flip)
        current = Assembly.records(@model).find { |item| item['id']==record['id'] }
        check(tool.error.nil? && current['gap']==-7,'Flip side reverses signed contact gap using the existing solver')
        Sketchup.undo
        hud.tick
        check(tool.record['gap']==7,'Persistent HUD synchronizes its selected record after Undo')
        @model.select_tool(nil)
        before_tool = @model.tools.active_tool_id
        hud.close
        check(!AssemblyHUDInput.active? && @model.tools.active_tool_id==before_tool && !@model.overlays.any? { |overlay| overlay.overlay_id=='mh.module_studio.assembly' },'Closing HUD releases overlay and mouse input without replacing the current native Tool')
      ensure
        hud&.close
      end

      def additional_checks
        super
        persistent_checks
      end
    end
  end
end

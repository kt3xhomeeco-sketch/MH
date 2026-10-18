# encoding: UTF-8
require_relative 'native_hud_motion_check'

module MH
  module ModuleStudio
    module NativeHUDClickCheck
      include NativeHUDMotionCheck
      extend self

      def prepare(expected_pid:)
        @base = File.dirname(Panel.instance_method(:request).source_location.first)
        @report_path = File.join(@base,'outputs/assembly-035/input.json')
        @model = Sketchup.active_model
        raise 'Pinned empty test session only' unless Process.pid==expected_pid && @model.active_path.nil? && @model.entities.length.zero?
        @originals = @model.entities.to_a; @definitions = @model.definitions.to_a; @before = state(@originals)
        @selection = @model.selection.to_a; @camera = @model.active_view.camera
        @links = @model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        @checks = []; @report = {'pid'=>Process.pid,'ok'=>false,'checks'=>@checks}
        a = own('Module A'); b = own('Module B')
        @model.start_operation('MH QA scrollable tree branches',true)
        20.times do |i|
          group = a.definition.entities.add_group
          group.name = "Chi tiết QA #{i+1}"
          group.entities.add_line([0,0,0],[1,0,0])
        end
        @model.commit_operation
        @record = Assembly.save(@model,{'mode'=>'contact','a'=>own_anchor(a,'Hông Phải',1),'b'=>own_anchor(b,'Hông Trái',0),'gap'=>3})
        @wrapper = AssemblyContainers.wrapper(@model,@record['scope'])
        @model.selection.clear; @model.selection.add(@wrapper)
        @model.active_view.zoom(@wrapper)
        @tool = AssemblyTool.new; @model.select_tool(@tool)
        @geometry = state(AssemblyContainers.members(@wrapper))
        @row_id = @tool.hud.tree.rows.find { |row| row['name']=='Module A' }['id']
        Sketchup.send_action('selectMoveTool:')
        UI.start_timer(0.3,false) do
          tree = @tool.hud.tree; view = @model.active_view
          row = tree.rows.find { |item| item['id']==@row_id }
          index = tree.visible(view).index(row); rect = tree.layout(view)['rect']; viewport = AssemblyHUDInput.viewport
          target = [viewport[0]+rect[0]+8+row['depth']*13+5,viewport[1]+rect[1]+33+index*25+12]
          File.write(File.join(@base,'outputs/assembly-035/input-target.json'),JSON.generate({'pid'=>Process.pid,'point'=>target,'viewport'=>viewport,'row'=>@row_id}))
        end
      end

      def finish
        @tool.hud.tick
        row = @tool.hud.tree.rows.find { |item| item['id']==@row_id }
        check(row['open'] && @tool.hud.tree.rows.any? { |item| item['kind']=='panel' },'A real Windows mouse click expands the viewport tree while Move is active')
        check(@model.tools.active_tool_name.include?('Move') && @geometry==state(AssemblyContainers.members(@wrapper)),'Tree click is consumed without switching native Move or changing module geometry')
        check(@tool.hud.tree.instance_variable_get(:@offset)>0,'Real mouse wheel scrolls the expanded HUD tree while Move remains active')
        @report['ok'] = true
      rescue StandardError => detail
        @report['error'] = [detail.message,*detail.backtrace.first(5)]
      ensure
        cleanup
      end
    end
  end
end

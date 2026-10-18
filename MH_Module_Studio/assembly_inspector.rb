# encoding: UTF-8
module MH
  module ModuleStudio
    # Compact native utility window. Picking and face/body drags remain in SketchUp.
    class AssemblyInspector
      def initialize(tool, hud = nil)
        @tool = tool; @hud = hud
      end

      def show
        @closing = false
        @dialog = UI::HtmlDialog.new(dialog_title:'Liên kết module',preferences_key:'MH_Module_Studio_Assembly_HUD_v1',
          width:286,height:490,min_width:270,min_height:350,resizable:true,style:UI::HtmlDialog::STYLE_UTILITY)
        @dialog.set_file(File.join(__dir__.dup.force_encoding(Encoding::UTF_8),'ui','assembly.html'))
        bind_requests
        @dialog.set_on_closed do
          UI.stop_timer(@timer) if @timer
          @timer = nil
          @dialog = nil
          @hud ? @hud.close : Sketchup.active_model.select_tool(nil) if !@closing
        end
        @dialog.show
        @timer = UI.start_timer(0.2,true) { publish } unless @hud
      end

      def bind_requests
        @dialog.add_action_callback('assembly_request') do |_context,raw|
          begin
            raise Core::Error,'Yêu cầu quá lớn.' if raw.to_s.bytesize > 16384
            packet = JSON.parse(raw.to_s)
            if packet['action']=='ready'
              next close if @closing
              @last_state = nil
              publish
            else
              command = { 'pick'=>:pick,'mode'=>:mode,'field'=>:field,'step'=>:step,'value'=>:value,
                          'direction'=>:direction,'toggle'=>:toggle,'measure'=>:measure,'manual'=>:manual,
                          'bound'=>:bound,'fit_size'=>:fit_size,'save'=>:save,'new'=>:new,'remove'=>:remove,
                          'load'=>:load,'close'=>:close,'flip'=>:flip,'group'=>:group,'rename'=>:rename,'auto_links'=>:auto_links }.fetch(packet['action'])
              value = packet['value']
              if command == :load
                value = Assembly.records(Sketchup.active_model).find { |row| row['id']==value }
                raise Core::Error,'Liên kết đã đổi.' unless value
              end
              @tool.action(command,value)
              Sketchup.focus if %i[pick bound measure].include?(command)
            end
          rescue StandardError => detail
            publish(detail.message)
          end
        end
      end

      def position(viewport)
        return unless @dialog && viewport && @viewport!=viewport
        @viewport = viewport
        width = @dialog.get_size.first
        @dialog.set_position([viewport[0],viewport[2]-width-14].max.round,(viewport[1]+18).round)
      end

      def close
        @closing = true
        dialog = @dialog
        dialog&.close
        # HtmlDialog may still be creating its native window during synchronous
        # Tool changes. The ready callback and this retry close that late window.
        UI.start_timer(0.1,false) { dialog.close if dialog&.visible? }
      end

      def publish(error = nil)
        return unless @dialog
        record = @tool.record
        model = Sketchup.active_model
        distance = begin
          if record['mode']=='repeat' && record['equal'] && @tool.complete?
            Assembly.repeat_plan(model,record)[2]['gap']
          elsif record['r1'] && record['r2']
            Assembly.distance(model,record)
          else
            record['gap']
          end
        rescue Core::Error
          nil
        end
        display = Assembly.display_record(model,record)
        state = { 'record'=>display,'picking'=>@tool.instance_variable_get(:@picking),'gap'=>distance,'tool_active'=>@tool.active,
                  'complete'=>@tool.complete?,'error'=>error || @tool.error || Assembly.last_error,'notice'=>@tool.notice,
                  'link_groups'=>Assembly.presentation_groups(model),
                  'links'=>Assembly.records(model).map { |row| Assembly.display_record(model,row).slice('id','mode','relation','scope','a','b','c','gap','count','angle') } }
        serialized = JSON.generate(state)
        return if @last_state == serialized
        @last_state = serialized
        @dialog.execute_script("window.receiveAssembly(JSON.parse(#{JSON.generate(serialized)}));")
      end
    end
  end
end

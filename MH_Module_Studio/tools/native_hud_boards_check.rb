# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeHUDBoardsCheck
      extend self
      class Overlay < Sketchup::Overlay
        attr_reader :draw_count
        def initialize(hud)
          super('mh.module_studio.qa081','MH HUD boards QA');@hud=hud;@draw_count=0
        end
        def draw(view)
          @draw_count+=1;@hud.draw(view)
        end
      end
      def run
        @model=Sketchup.active_model;Runtime.ensure_top_level(@model)
        @before=@model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] };@defs=@model.definitions.to_a;@selection=@model.selection.to_a
        @links=@model.get_attribute(Reader::DICT,AssemblyContainers::KEY);@report={'checks'=>[]}
        @library=Library.new
        @library.instance_variable_set(:@config,LibraryCatalog.settings('root'=>'D:/Cong viec/Sketchup/DC/Modul_studio','hud_size'=>60,'hud_position'=>'center'))
        @library.instance_variable_set(:@catalog,LibraryCatalog.scan(@library.config['root']))
        @library.define_singleton_method(:persist) {};@library.define_singleton_method(:publish) { |*_args,**_options| }
        @library.define_singleton_method(:tool_closed) { |_tool| @tool=nil }
        @hud=LibraryHUD.new(@library);@library.instance_variable_set(:@tool,@hud);@hud.instance_variable_set(:@active,true)
        @hud.set_editing(true);@library.edit_hud_board('create',{'name'=>'QA Tấm đứng','key'=>'D'})
        board=@library.config['hud_board'];items=@library.catalog['entries'].select { |e| e['id'].include?('Ngan keo am 1 tang ') }.first(2)
        raise 'Actual Library has too few icons' unless items.length==2
        view=@model.active_view;layout=@hud.geometry(view);point=layout['items'][5]
        original=HUDInput.method(:cursor);owned=HUDInput.singleton_class.instance_methods(false).include?(:cursor)
        HUDInput.define_singleton_method(:cursor) { |_view| {'x'=>point[0],'y'=>point[1],'left'=>false,'over'=>true} }
        @hud.begin_external_drag(items.first['id'],@library.catalog['root'],'native081');@hud.end_external_drag('native081')
        check(HUDBoards.current(@library.config)['slots']==[nil,nil,nil,nil,nil,items.first['id'],nil,nil],'External Library drop occupies exactly slot 6 and leaves every other slot blank')
        @library.move_hud_item(items.last['id'],1,folder:board)
        @hud.onLButtonDown(0,*layout['items'][5],view);@hud.onMouseMove(0,*layout['items'][1],view);@hud.onLButtonUp(0,*layout['items'][1],view)
        slots=HUDBoards.current(@library.config)['slots']
        check(slots[1]==items.first['id'] && slots[5]==items.last['id'] && slots.compact.length==2,'Native HUD internal drag swaps icons without filling the six blank slots')
        folder=@library.catalog['folders'].find { |f| !f['id'].empty? }['id'];@library.save_settings('folder'=>folder)
        check(@hud.hud_folder==board && @hud.page_items[1]['id']==items.first['id'],'Browsing another Library folder preserves the destination board and its slots')
        @hud.set_editing(false);cx,cy=layout['center'];angle=-Math::PI/2+Math::PI/4+0.15
        point=[cx+Math.cos(angle)*layout['radius']*1.8,cy+Math.sin(angle)*layout['radius']*1.8]
        check(@hud.hit(*point,view)==[:item,1] && Math.hypot(point[0]-layout['items'][1][0],point[1]-layout['items'][1][1])>layout['size']/2,'Angular hit selects an icon beyond its actual circular target')
        @hud.onMouseMove(0,*point,view);check(@hud.instance_variable_get(:@hover)==[:item,1],'Directional hover highlights the same icon that click will choose')
        @fills=[];original_circle=@hud.method(:circle);fills=@fills
        @hud.define_singleton_method(:circle) { |*args| fills << args[4];original_circle.call(*args) }
        @overlay=Overlay.new(@hud);@model.overlays.add(@overlay);@overlay.enabled=true;view.invalidate;view.refresh
        check(@overlay.draw_count.positive? && !@hud.instance_variable_get(:@draw_error),'Real native overlay renders sparse icons and directional highlighting without draw errors')
        check(@fills.first.nil?,'Large ring renders an outline without a polygon fill')
        @model.selection.clear;@hud.onLButtonDown(0,*point,view)
        check(@hud.pending && @hud.pending['entry_id']==items.first['id'],'Click outside the icon circle chooses the highlighted source')
        @hud.cancel_placement(view);@hud.onKeyDown('D'.ord,1,0,view)
        check(@library.config['hud_board']==board && @hud.page_items[1]['id']==items.first['id'],'Board shortcut restores its exact sparse layout')
        @model.overlays.remove(@overlay);@overlay=nil;@hud.deactivate(view)
        @hud=LibraryHUD.new(@library);@library.instance_variable_set(:@tool,@hud);@hud.instance_variable_set(:@active,true);@hud.refresh
        check(@hud.page_items[1]['id']==items.first['id'] && @hud.page_items[5]['id']==items.last['id'] && @hud.page_items.compact.length==2,'Reopening HUD retains manual positions without loading folder contents')
        @hud.set_editing(true);@library.edit_hud_board('create',{'name'=>'QA Bếp','key'=>'B'});@hud.set_editing(false)
        @hud.onKeyDown('D'.ord,1,0,view);check(@library.config['hud_board']==board,'Letter shortcuts switch independently named boards')
        check(@library.config['folder']==folder,'Board switching does not alter Library folder browsing')
      rescue StandardError=>error
        @report||={'checks'=>[]};@report['error']=[error.message,*error.backtrace.first(8)]
      ensure
        if original
          owned ? HUDInput.define_singleton_method(:cursor,original) : HUDInput.singleton_class.remove_method(:cursor)
        end
        @model.overlays.remove(@overlay) if @overlay
        @hud.deactivate(@model.active_view) if @hud&.active
        @model.selection.clear;@selection.each { |e| @model.selection.add(e) if e.valid? }
        @report['model_retained']=@before==@model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] } && @defs==@model.definitions.to_a && @links==@model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        @report['status']=@report['error'] || !@report['model_retained'] ? 'failed' : 'passed'
        folder=File.join(File.dirname(__dir__),'outputs/hud-boards-081');FileUtils.mkdir_p(folder);File.write(File.join(folder,'native.json'),JSON.pretty_generate(@report));puts JSON.generate(@report)
      end
      def check(value,label)
        raise label unless value
        @report['checks'] << label
      end
    end
  end
end

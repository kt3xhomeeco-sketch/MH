# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeHUDDocksCheck
      extend self
      def run
        @model=Sketchup.active_model;Runtime.ensure_top_level(@model)
        @before=@model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] };@defs=@model.definitions.to_a;@selection=@model.selection.to_a
        @links=@model.get_attribute(Reader::DICT,AssemblyContainers::KEY);@report={'checks'=>[]}
        @library=Library.new;@library.instance_variable_set(:@config,LibraryCatalog.settings('root'=>'D:/Cong viec/Sketchup/DC/Modul_studio','hud_size'=>60,'hud_position'=>'center'))
        @library.instance_variable_set(:@catalog,LibraryCatalog.scan(@library.config['root']))
        @library.define_singleton_method(:persist) {};@library.define_singleton_method(:publish) { |*_args,**_kwargs| };@library.define_singleton_method(:tool_closed) { |_tool| @tool=nil }
        @hud=LibraryHUD.new(@library);@library.instance_variable_set(:@tool,@hud);@hud.instance_variable_set(:@active,true);@hud.set_editing(true)
        @library.edit_hud_board('create',{'name'=>'QA docks','key'=>'D'});@board=@library.config['hud_board']
        @items=@library.catalog['entries'].select { |r| r['id'].include?('Ngan keo am 1 tang ') }.first(6)
        @items.each_with_index { |item,index| @library.move_hud_item(item['id'],index,folder:@board) }
        view=@model.active_view;near=@hud.geometry(view);@library.save_settings('hud_spacing'=>160);far=@hud.geometry(view)
        check(near['size']==far['size'] && far['radius']>near['radius'],'Spacing changes the ring radius independently of icon diameter')
        input_original=UI.method(:inputbox);message_original=UI.method(:messagebox);messages=[]
        UI.define_singleton_method(:inputbox) { |*_args| ['9'] };UI.define_singleton_method(:messagebox) { |message,*_args| messages << message }
        point=far['items'][0];@hud.onLButtonDown(0,*point,view);@hud.onLButtonUp(0,*point,view)
        check(current['shortcuts'][@items.first['id']]=='9','Edit click-release assigns the explicitly entered number to that icon')
        point=@hud.geometry(view)['items'][1];@hud.onLButtonDown(0,*point,view);@hud.onLButtonUp(0,*point,view)
        check(messages.length==1 && !current['shortcuts'].key?(@items[1]['id']),'Duplicate digit is reported without reassigning another icon')
        move([:item,0],[:dock,['left',3]],view)
        check(current['slots'][0].nil? && current['docks']['left'][3]==@items.first['id'] && current['shortcuts'][@items.first['id']]=='9','Drag moves ring icon to an exact left dock slot and preserves its number')
        move([:dock,['left',3]],[:dock,['bottom',2]],view)
        check(current['docks']['left'][3].nil? && current['docks']['bottom'][2]==@items.first['id'],'Drag between edge docks preserves empty slots')
        move([:dock,['bottom',2]],[:item,4],view)
        check(current['slots'][4]==@items.first['id'] && current['docks']['bottom'][2]==@items[4]['id'],'Occupied destination swaps dock and ring icons')
        @library.move_hud_item(@items[2]['id'],2,folder:@board,zone:'top')
        @library.move_hud_item(@items[3]['id'],4,folder:@board,zone:'right')
        @hud.set_editing(false);@model.selection.clear;@hud.onKeyDown('1'.ord,1,0,view)
        check(!@hud.pending,'An unassigned digit does not import the first slot')
        @hud.onKeyDown('9'.ord,1,0,view);check(@hud.pending && @hud.pending['entry_id']==@items.first['id'],'Assigned digit chooses its icon after moving across layouts')
        @hud.cancel_placement(view)
        point=@hud.geometry(view)['docks']['right'][4]
        check(@hud.hit(*point,view)==[:dock,['right',4]],'Exact edge icon picking takes priority over ring directional selection')
        @hud.onMouseMove(0,*point,view)
        circles=[];texts=[];original_circle=@hud.method(:circle);original_text=@hud.method(:text)
        @hud.define_singleton_method(:circle) { |*args| circles << args[4];original_circle.call(*args) }
        @hud.define_singleton_method(:text) { |*args,**kwargs| texts << args[3];original_text.call(*args,**kwargs) }
        @overlay=NativeHUDBoardsCheck::Overlay.new(@hud);@model.overlays.add(@overlay);@overlay.enabled=true;view.invalidate;view.refresh
        check(@overlay.draw_count.positive? && !@hud.instance_variable_get(:@draw_error),'Native HUD renders ring plus four sparse docks without draw failures')
        check(circles.any? { |fill| fill.is_a?(Sketchup::Color) && fill.alpha>0 && fill.alpha<255 },'Highlight draws a strong translucent tint above the thumbnail')
        check(texts.none? { |value| value=='×' || value=='MH LIBRARY' || value.include?('Chuột phải:') || value.include?('Chữ: tìm') },'HUD omits close X, title and lower guidance text')
        saved=Core.copy_data(@library.config);@model.overlays.remove(@overlay);@overlay=nil;@hud.deactivate(view)
        @hud=LibraryHUD.new(@library);@library.instance_variable_set(:@tool,@hud);@hud.instance_variable_set(:@active,true);@hud.refresh
        check(@library.config==saved && current['docks']['right'][4]==@items[3]['id'] && current['shortcuts'][@items.first['id']]=='9','Reopen retains dock layout, spacing and explicit numeric mapping')
      rescue StandardError=>error
        @report||={'checks'=>[]};@report['error']=[error.message,*error.backtrace.first(8)]
      ensure
        UI.define_singleton_method(:inputbox,input_original) if input_original
        UI.define_singleton_method(:messagebox,message_original) if message_original
        @model.overlays.remove(@overlay) if @overlay
        @hud.deactivate(@model.active_view) if @hud&.active
        @model.selection.clear;@selection.each { |e| @model.selection.add(e) if e.valid? }
        @report['model_retained']=@before==@model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] } && @defs==@model.definitions.to_a && @links==@model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        @report['status']=@report['error'] || !@report['model_retained'] ? 'failed' : 'passed'
        folder=File.join(File.dirname(__dir__),'outputs/hud-docks-082');FileUtils.mkdir_p(folder);File.write(File.join(folder,'native.json'),JSON.pretty_generate(@report));puts JSON.generate(@report)
      end
      def current
        HUDBoards.current(@library.config)
      end
      def point(target,view)
        layout=@hud.geometry(view)
        target[0]==:item ? layout['items'][target[1]] : layout['docks'][target[1][0]][target[1][1]]
      end
      def move(source,destination,view)
        a=point(source,view);b=point(destination,view)
        @hud.onLButtonDown(0,*a,view);@hud.onMouseMove(0,*b,view);@hud.onLButtonUp(0,*b,view)
      end
      def check(value,label)
        raise label unless value
        @report['checks'] << label
      end
    end
  end
end

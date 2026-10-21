# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeHUDFreeCheck
      extend self
      def run
        @model=Sketchup.active_model;Runtime.ensure_top_level(@model)
        @before=@model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] };@defs=@model.definitions.to_a;@selection=@model.selection.to_a
        @links=@model.get_attribute(Reader::DICT,AssemblyContainers::KEY);@prefs=Sketchup.read_default('MH_Module_Studio','library_v1','');@report={'checks'=>[]}
        @library=Library.new;@library.instance_variable_set(:@config,LibraryCatalog.settings('root'=>'D:/Cong viec/Sketchup/DC/Modul_studio','hud_size'=>60,'hud_position'=>'center'))
        @library.instance_variable_set(:@catalog,LibraryCatalog.scan(@library.config['root']))
        @library.define_singleton_method(:persist) {};@library.define_singleton_method(:publish) { |*_args,**_kwargs| };@library.define_singleton_method(:tool_closed) { |_tool| @tool=nil }
        @hud=LibraryHUD.new(@library);@library.instance_variable_set(:@tool,@hud);@hud.instance_variable_set(:@active,true);@hud.set_editing(true)
        @library.edit_hud_board('create',{'name'=>'QA free','key'=>'F'});@board=@library.config['hud_board']
        @items=@library.catalog['entries'].select { |r| r['id'].include?('Ngan keo am 1 tang ') }.first(7)
        raise 'Too few QA Library icons' unless @items.length==7
        @items.first(6).each_with_index { |item,index| @library.move_hud_item(item['id'],index,folder:@board) }
        @library.edit_hud_board('shortcut',{'id'=>@board,'entry'=>@items[0]['id'],'digit'=>'9'})
        view=@model.active_view;layout=@hud.geometry(view);cx,cy=layout['center'];size=layout['size']
        target=[cx+layout['radius']+size*2.4,layout['items'][0][1]+6]
        @hud.onLButtonDown(0,*layout['items'][0],view);@hud.onMouseMove(0,*target,view)
        preview=@hud.instance_variable_get(:@free_preview)
        check(preview && preview['position']['snap_y']==0 && preview['guides'].any? { |axis,_value| axis=='y' },'Native drag previews a horizontal guide snapped to the ring icon')
        @overlay=NativeHUDBoardsCheck::Overlay.new(@hud);@model.overlays.add(@overlay);@overlay.enabled=true;view.invalidate;view.refresh
        check(@overlay.draw_count.positive? && !@hud.instance_variable_get(:@draw_error),'Native viewport draws snap guides and the free drag preview')
        @hud.onLButtonUp(0,*target,view)
        check(current['slots'][0].nil? && current['free'][@items[0]['id']]['snap_y']==0 && current['shortcuts'][@items[0]['id']]=='9','Free drop leaves a ring hole and preserves the icon digit')
        check(@hud.instance_variable_get(:@textures).key?(@library.thumbnail_key(@items[0])),'Free icons retain their actual thumbnail texture')
        @hud.set_editing(false);point=@hud.geometry(view)['free'][@items[0]['id']]
        check(@hud.hit(*point,view)==[:free,@items[0]['id']],'Free icon direct picking takes priority over radial selection')
        @model.selection.clear;@hud.onLButtonDown(0,*point,view)
        check(@hud.pending && @hud.pending['entry_id']==@items[0]['id'],'Clicking a free icon chooses the correct source without placing geometry')
        @hud.cancel_placement(view);@hud.onKeyDown('9'.ord,1,0,view)
        check(@hud.pending && @hud.pending['entry_id']==@items[0]['id'],'Assigned digit imports a free-position icon')
        @hud.cancel_placement(view);@hud.set_editing(true)
        move(point,@hud.geometry(view)['docks']['right'][3],view)
        check(!current['free'].key?(@items[0]['id']) && current['docks']['right'][3]==@items[0]['id'],'Free icon moves into an exact dock slot')
        layout=@hud.geometry(view);vertical=[layout['items'][2][0]+5,cy+layout['radius']+size*2]
        move(layout['docks']['right'][3],vertical,view)
        check(current['free'][@items[0]['id']]['snap_x']==2 && current['docks']['right'][3].nil?,'Dock icon moves to a free position aligned vertically to the ring')
        @library.save_settings('hud_spacing'=>150);layout=@hud.geometry(view)
        check((layout['free'][@items[0]['id']][0]-layout['items'][2][0]).abs<0.001,'Saved vertical alignment follows a changed ring radius')
        external=[layout['free'][@items[0]['id']][0]+size*2.2,layout['free'][@items[0]['id']][1]+4]
        original_cursor=HUDInput.method(:cursor);cursor_owned=HUDInput.singleton_class.instance_methods(false).include?(:cursor)
        cursor={'x'=>external[0],'y'=>external[1],'left'=>false,'over'=>true};HUDInput.define_singleton_method(:cursor) { |_view| cursor }
        @hud.begin_external_drag(@items[6]['id'],@library.catalog['root'],'native083');@hud.end_external_drag('native083')
        layout=@hud.geometry(view)
        check(current['free'].key?(@items[6]['id']) && (layout['free'][@items[6]['id']][1]-layout['free'][@items[0]['id']][1]).abs<0.001,'External Library drop adds a free icon aligned with an existing free row')
        move(layout['free'][@items[0]['id']],layout['items'][1],view)
        check(current['slots'][1]==@items[0]['id'] && current['free'].key?(@items[1]['id']),'Dropping a free icon onto an occupied ring slot swaps both locations')
        saved=Core.copy_data(@library.config);parsed=HUDConfig.parse(JSON.generate(HUDConfig.document(saved,@library.catalog)))
        check(parsed['settings']['hud_boards']==saved['hud_boards'],'Config transfer retains free positions, axes and digit mappings')
        check_relative_cluster_edges(view)
        @model.overlays.remove(@overlay);@overlay=nil;@hud.deactivate(view)
        @hud=LibraryHUD.new(@library);@library.instance_variable_set(:@tool,@hud);@hud.instance_variable_set(:@active,true);@hud.refresh
        check(@hud.geometry(view)['free'].keys.sort==current['free'].keys.sort && @library.config==saved,'Reopened HUD restores free icons without touching the saved ring/docks')
      rescue StandardError=>error
        @report||={'checks'=>[]};@report['error']=[error.message,*error.backtrace.first(8)]
      ensure
        if original_cursor
          cursor_owned ? HUDInput.define_singleton_method(:cursor,original_cursor) : HUDInput.singleton_class.remove_method(:cursor)
        end
        @model.overlays.remove(@overlay) if @overlay
        @hud.deactivate(@model.active_view) if @hud&.active
        @model.selection.clear;@selection.each { |e| @model.selection.add(e) if e.valid? }
        @report['model_retained']=@before==@model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] } && @defs==@model.definitions.to_a && @links==@model.get_attribute(Reader::DICT,AssemblyContainers::KEY) && @prefs==Sketchup.read_default('MH_Module_Studio','library_v1','')
        @report['status']=@report['error'] || !@report['model_retained'] ? 'failed' : 'passed'
        folder=File.join(File.dirname(__dir__),'outputs/hud-free-083');FileUtils.mkdir_p(folder);File.write(File.join(folder,'native.json'),JSON.pretty_generate(@report));puts JSON.generate(@report)
      end
      def current
        HUDBoards.current(@library.config)
      end
      def move(a,b,view)
        @hud.onLButtonDown(0,*a,view);@hud.onMouseMove(0,*b,view);@hud.onLButtonUp(0,*b,view)
      end
      def check_relative_cluster_edges(view)
        width=view.vpwidth.to_f;height=view.vpheight.to_f;size=@library.config['hud_size'].to_f
        board=Core.copy_data(current);board['docks']=HUDBoards::DOCKS.to_h { |zone| [zone,[]] }
        board['free']={'qa_relative'=>{'x'=>220.0,'y'=>-140.0,'relative'=>true}}
        [[12,height/2.0],[width-12,height/2.0],[width/2.0,12],[width/2.0,height-12]].each do |x,y|
          ring=LibraryCatalog.layout(width,height,size,center:[x,y],spacing:@library.config.fetch('hud_spacing',100))
          layout=HUDLayout.compose(width,height,ring,board)
          cx,cy=layout['center'];fx,fy=layout['free']['qa_relative']
          check((fx-cx-220.0).abs<0.001 && (fy-cy+140.0).abs<0.001,'At viewport edges the entire ring and free icon preserve their relative offset')
        end
      end
      def check(value,label)
        raise label unless value
        @report['checks'] << label
      end
    end
  end
end

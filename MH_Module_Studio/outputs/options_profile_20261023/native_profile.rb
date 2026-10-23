# Q15 coarse measurement harness. No production edits, no disk I/O during a case.
require 'json'
require 'digest'
module MH;module ModuleStudio;module NativeOptionsProfile;extend self
V='2026-10-23.3';JOB=:qa_profile_options;MAIN=%w[part:0001 part:0002 part:0003 part:0004];TOL=0.02;TAG='qa_profile_q15'
LIB='D:/Cong viec/Sketchup/DC/Modul_studio';ID='qa-profile-khung';SIZE=80098
ASSET='D:/Cong viec/Sketchup/DC/Modul_studio/Khung/Khung noc lot.skp'
HOOKS=[[ :UpdateWork,:calculate,:kind],[:UpdateWork,:dispatch,:kind],[:UpdateWork,:advance,:scope],[:UpdateWork,:compute,:scope],[:UpdateWork,:sleep],[:Reader,:live],[:Runtime,:preview],[:Runtime,:private_tree],[:Runtime,:apply_trial_update],[:Runtime,:apply_plan],[:Runtime,:stamp],[:Runtime,:stamp_prepared],[:Runtime,:verify_result],[:Core,:rule!],[:Core,:plan],[:Core,:copy_data],[:Core,:plan_parameters],[:Core,:validate_geometry_plan!],[:Parametric,:edit_variables],[:Parametric,:targets],[:Parametric,:stamp_metadata],[:RuleSystem,:validate!],[:RuleSystem,:plan]]
def c(n);MH::ModuleStudio.const_defined?(n,false) ? MH::ModuleStudio.const_get(n) : nil;rescue NameError;nil;end
def nowm;Process.clock_gettime(Process::CLOCK_MONOTONIC)*1000.0;end
def r3(x);(x.to_f*1000).round/1000.0;end
def dk(d);d.respond_to?(:guid) ? d.guid.to_s : d.object_id.to_s;end
def busy?(m);return false unless m;%i[pending? busy? active?].each{|k|next unless m.respond_to?(k,true);v=(begin;m.send(k,@m);rescue ArgumentError,TypeError;(begin;m.send(k);rescue StandardError;nil;end);end);return true if v==true};false;rescue StandardError;false;end
def setup(profiled:false,target:nil)
 raise 'g0' unless Process.pid==16624
 @m=Sketchup.active_model;@main=Thread.main;@prof=profiled;@target=target
 raise 'g0b' unless @m&&Sketchup.active_model.equal?(@m)
 @hist||=[];@case=nil;@recs=[];@errs=[];@fixture=nil;@setup=nil
 raise 'g1' unless @m.active_path.nil?||@m.active_path.empty?
 raise 'g2' unless @m.path.to_s.empty?
 raise 'g3' unless @m.entities.size==0
 raise 'g4' if busy?(c(:UpdateWork))||busy?(c(:ScaleRedraw))
 rd=c(:Reader);@dict=(rd&&rd.const_defined?(:DICT)) ? rd.const_get(:DICT) : 'MH'
 cm=@m.active_view.camera rescue nil
 @base={ids:@m.entities.map(&:entityID),defs:@m.definitions.map{|d|dk(d)},mats:(@m.materials.map{|x|x.name.to_s}.sort rescue []),sel:@m.selection.map(&:entityID),cam:(cm ? [cm.eye.to_a,cm.target.to_a,cm.up.to_a] : nil),ds:@m.definitions.size,es:@m.entities.size,path:@m.path.to_s}
 build!
 @setup={'ok'=>true,'pid'=>Process.pid,'path'=>@m.path.to_s,'root'=>@fixture[:eid],'defs'=>@base[:defs].size,'preview_ms'=>r3(@fixture[:pm]),'build_ms'=>r3(@fixture[:bm]),'asset'=>SIZE,'cold'=>@fixture[:cold]}
end
def build!
 raise 'g5' unless File.file?(ASSET)&&File.size(ASSET)==SIZE
 k=c(:Library);raise 'g6' unless k
 l=k.respond_to?(:allocate) ? k.allocate : k.new
 l.instance_variable_set(:@config,{});l.instance_variable_set(:@publisher,nil)
 l.instance_variable_set(:@catalog,{'root'=>LIB,'folders'=>[],'entries'=>[{'id'=>ID,'name'=>'QA Khung noc lot','folder'=>'Khung','path'=>ASSET,'fingerprint'=>((c(:LibraryCatalog).fingerprint(ASSET)) rescue Digest::SHA256.file(ASSET).hexdigest),'bytes'=>SIZE}]})
 cold=!(l.instance_variable_defined?(:@cache)&&Array(l.instance_variable_get(:@cache)).any?)
 t=nowm;d=l.preview(ID);pm=nowm-t
 @m.start_operation('MH QA fixture',true)
 begin
  t=nowm;b=l.build_instance(d,Geom::Transformation.new);bm=nowm-t
  r=root!(b);raise 'g7' unless r
  rt=c(:Runtime);rt.send(:private_tree,r) if rt&&rt.respond_to?(:private_tree,true)
  r.name='QA Khung noc lot';r.set_attribute(@dict,'trial',true);r.set_attribute(@dict,'qa_tag',TAG)
  cm=c(:ComponentMetadata);cm.send(:store,r) if cm&&cm.respond_to?(:store,true)
  @m.commit_operation;@fixture={inst:r,eid:r.entityID,dg:dk(r.definition),pm:pm,bm:bm,cold:cold}
  @owned_def_keys=@m.definitions.map{|x|dk(x)}.reject{|x|@base[:defs].include?(x)}
 rescue StandardError;@m.abort_operation;raise;end
end
def root!(b);a=b.is_a?(Array) ? b : [b];a.find{|e|e.is_a?(Sketchup::ComponentInstance)}||@m.entities.to_a.reverse.find{|e|e.is_a?(Sketchup::ComponentInstance)};end
def start(profiled:nil,target:nil)
 raise 'g0' unless Process.pid==16624&&Sketchup.active_model.equal?(@m)
 raise 'g8' unless @setup
 raise 'g9' if @case&&!@case[:done]
 raise 'g10' if busy?(c(:UpdateWork))||busy?(c(:ScaleRedraw))
 profiled=@prof if profiled.nil?;target=@target if target.nil?;raise 'g11' if target.nil?
 raise 'g12' unless @m.path.to_s==@base[:path]&&(@base[:ids]+[@fixture[:eid]]).uniq.sort==@m.entities.map(&:entityID).sort
 r=@fixture[:inst];raise 'g13' unless r&&r.valid?&&r.get_attribute(@dict,'trial',false)
 mo=c(:ModuleOptions);raise 'g14' unless mo
 raw=r.get_attribute(@dict,'rule_json');raise 'g15' if raw.nil?||raw.to_s.strip.empty?
 vraw=r.get_attribute(@dict,'parameter_values_json')
 rule=ThicknessSymbols.normalize(DCCustomAttributes.upgrade(Core.rule!(JSON.parse(raw))))
 vals=vraw ? JSON.parse(vraw) : {}
 rule['parameters'].each{|p|p['value']=vals.fetch(p['key'],p['value']) if p['editable']}
 rule.fetch('parametric_variables',[]).each{|x|x['value']=vals.fetch(x['binding'],x['value']) if x['binding']&&x['formula'].to_s.empty?}
 rows=OptionsParameters.rows(rule,vals)
 row=rows.find{|x|x['symbol']=='T1'};raise 'g16' unless row
 rid=row.fetch('id');pid=r.persistent_id.to_s
 o=mo.allocate;o.instance_variable_set(:@model,@m);o.instance_variable_set(:@root,r)
 o.instance_variable_set(:@members,{pid=>{'anchor'=>{'root'=>pid},'rule'=>rule,'raw'=>raw,'values_raw'=>vraw}})
 o.instance_variable_set(:@display_rows,rows)
 @rule=rule
 @agg={};@sleep={'n'=>0,'act'=>0.0,'req'=>0.0,'max'=>0.0};@hb={'n'=>0,'max'=>0.0}
 @case={profiled:!!profiled,target:target.to_f,t0:nowm,done:false,status:nil,error:nil,wall:nil,steps:0,probe:false}
 install if profiled;hb(true) if profiled
 uw=c(:UpdateWork);raise 'g18' unless uw&&uw.respond_to?(:submit)
 uw.submit(@m,key:JOB,guard:->{r.valid?},complete:->(st,er){NativeOptionsProfile.fin(st,er)}){o.apply_changes([{'variable_id'=>rid,'value'=>target}])}
 {'ok'=>true,'profiled'=>!!profiled,'target'=>target.to_f,'hooks'=>@recs.size,'row'=>rid,'pid'=>pid}
rescue StandardError=>e
 fin(:error,e);raise
end
def fin(st,e)
 return if @case.nil?||@case[:done]
 @case[:done]=true;@case[:wall]=r3(nowm-@case[:t0]);@case[:status]=(e ? :error : (st||:done)).to_s;@case[:error]=e ? "#{e.class}: #{e.message}" : nil
 uw=c(:UpdateWork);@case[:metrics]=(uw.last_metrics rescue nil) if uw&&uw.respond_to?(:last_metrics)
 uninstall;hb(false);@case[:stacks]=stacks;@case[:agg]=aggv
 @case[:sleep]=@sleep.dup;@case[:hb]=@hb.dup;@hist<<@case
end
def aggv;(@agg||{}).map{|k,v|{'label'=>k.split('|')[0],'thread'=>k.split('|')[1],'n'=>v[0],'total_ms'=>r3(v[1]),'self_ms'=>r3(v[2]),'max_ms'=>r3(v[3])}}.sort_by{|x|-x['total_ms']};end
def install
 HOOKS.each{|s|o=c(s[0]);next unless o;hook(o,s[1],s[2]||:plain,false)}
end
def hook(o,n,k,inst)
 if inst
  org=o.instance_method(n);rec=[o,n,k,true,:private,org,true]
  o.send(:define_method,n,swrap(rec));o.send(:private,n)
 else
  sc=o.singleton_class
  return unless sc.method_defined?(n)||sc.private_method_defined?(n)
  own=sc.instance_methods(false).include?(n)||sc.private_instance_methods(false).include?(n)||sc.protected_instance_methods(false).include?(n)
  vis=sc.private_method_defined?(n) ? :private : (sc.protected_method_defined?(n) ? :protected : :public)
  org=o.method(n);rec=[o,n,k,own,vis,org,false]
  sc.send(:define_method,n,wraps(rec));sc.send(vis,n) unless vis==:public
 end
 @recs<<rec
end
def wraps(r)
 o,n,k,ow,vi,org,ins=r;lab="#{o.name}.#{n}"
 proc do |*a,**kw,&b|
  if k==:scope&&a.first.is_a?(Hash)&&(a.first[:key]==JOB||a.first['key']==JOB)
   pr=Thread.current[:mhq];Thread.current[:mhq]=true
   begin
    NativeOptionsProfile.timed(lab,org,a,kw,b)
   ensure
    Thread.current[:mhq]=pr
   end
  elsif k!=:scope&&Thread.current[:mhq]
   NativeOptionsProfile.timed(k==:kind ? "#{lab}[#{a.first}]" : lab,org,a,kw,b)
  else
   org.call(*a,**kw,&b)
  end
 end
end
def swrap(r)
 org=r[5]
 proc do |*a,**kw,&b|
  if Thread.current[:mhq]
   q=a.first.is_a?(Numeric) ? a.first.to_f*1000.0 : 0.0;t=nowm
   begin;org.bind_call(self,*a,**kw,&b)
   ensure;d=nowm-t;s=@sleep;s['n']+=1;s['act']+=d;s['req']+=q;s['max']=d if d>s['max'];end
  else
   org.bind_call(self,*a,**kw,&b)
  end
 end
end
def timed(l,org,a,kw,b)
 s=(Thread.current[:mhst]||=[]);t=nowm;tk=[l,t,0.0];pa=s.last;s<<tk
 begin;org.call(*a,**kw,&b)
 ensure
  s.pop;d=nowm-t;ex=d-tk[2];ex=0.0 if ex<0;pa[2]+=d if pa
  if l.end_with?('.sleep')
   q=a.first.is_a?(Numeric) ? a.first.to_f*1000.0 : 0.0;sl=@sleep;sl['n']+=1;sl['act']+=d;sl['req']+=q;sl['max']=d if d>sl['max']
  end
  key="#{l}|#{Thread.current.equal?(@main) ? 'main' : 'worker'}";g=(@agg[key]||=[0,0.0,0.0,0.0]);g[0]+=1;g[1]+=d;g[2]+=ex;g[3]=d if d>g[3]
 end
end
def uninstall
 (@recs||[]).reverse_each do |r|
  o,n,k,ow,vi,org,ins=r
  begin
   if ins;o.send(:define_method,n,org);o.send(:private,n)
   elsif ow;o.define_singleton_method(n,org);o.singleton_class.send(vi,n) unless vi==:public
   else;o.singleton_class.send(:remove_method,n);end
  rescue StandardError=>x
   @errs<<"restore #{n}: #{x.class}: #{x.message}"
  end
 end
 @recs=[]
end
def hb(on)
 if on
  return unless defined?(UI)&&UI.respond_to?(:start_timer)
  @tl=nowm;@tid=UI.start_timer(0.1,true){t=nowm;g=t-(@tl||t);@tl=t;@hb['n']+=1;@hb['max']=g if g>@hb['max']}
 else
  (UI.stop_timer(@tid) rescue nil) if @tid&&defined?(UI)&&UI.respond_to?(:stop_timer);@tid=nil
 end
rescue StandardError=>x
 @errs<<"hb: #{x.class}: #{x.message}"
end
def stacks;o=[];Thread.list.each{|t|s=t[:mhst];o<<[t.equal?(@main) ? 'main' : 'worker',s.size] if s&&!s.empty?};o;end
def report
 return {'ok'=>false,'why'=>'pid'} unless Process.pid==16624&&Sketchup.active_model.equal?(@m)
 uw=c(:UpdateWork)
 return {'ok'=>false,'why'=>'pending','pending'=>true} if uw&&uw.respond_to?(:pending?)&&uw.pending?(@m)
 if @case&&@case[:done];@case[:agg]=aggv;@case[:stacks]=stacks;end
 uninstall;hb(false)
 {'version'=>V,'pid'=>Process.pid,'path'=>@m ? @m.path.to_s : nil,'setup'=>@setup,'cases'=>(@hist||[]),'errors'=>@errs,'geometry'=>geo,'stack_clear'=>stacks.empty?}
end
def geo
 r=@fixture&&@fixture[:inst];t=(@case&&@case[:target])||@target
 return {'ok'=>false,'why'=>'no root'} unless r&&r.valid?
 rd=c(:Reader);return {'ok'=>false,'why'=>'Reader'} unless rd&&rd.respond_to?(:live)
 sn=(begin;rd.live(r,label:'QA',parameter:t);rescue ArgumentError;rd.live(r,label:'QA');end)
 pt=ext(sn);mn=pt.select{|x|MAIN.include?(x['key'].to_s)}
 {'ok'=>true,'parts'=>pt,'main_n'=>mn.size,'main_t1_ok'=>(t&&mn.size==4 ? mn.all?{|x|(x['dims'].min-t.to_f).abs<=TOL} : false),'back'=>pt.select{|x|x['key'].to_s=='part:0007'}}
rescue StandardError=>x
 {'ok'=>false,'error'=>"#{x.class}: #{x.message}"}
end
def ext(n,o=[],d=0)
 return o if d>8||o.size>=7
 if n.is_a?(Hash)
  if %w[bounds dimensions size bbox].any?{|k|n.key?(k)}&&(n.key?('key')||n.key?('name'))
   v=n['bounds']||n['dimensions']||n['size']||n['bbox']
   dm=case v
      when Array
       if v.size==6&&v.all?{|x|x.is_a?(Numeric)};[(v[3]-v[0]).abs,(v[4]-v[1]).abs,(v[5]-v[2]).abs]
       elsif v.size==2&&v.all?{|x|x.is_a?(Array)&&x.size==3};[(v[1][0]-v[0][0]).abs,(v[1][1]-v[0][1]).abs,(v[1][2]-v[0][2]).abs]
       elsif v.size==3&&v.all?{|x|x.is_a?(Numeric)};v.map{|x|x.abs};end
      when Hash
       (v['min']&&v['max']) ? [(v['max'][0]-v['min'][0]).abs,(v['max'][1]-v['min'][1]).abs,(v['max'][2]-v['min'][2]).abs] : nil
      end
   o<<{'key'=>n['key'],'name'=>n['name'],'dims'=>dm.map{|x|r3(x)}} if dm
  end
  n.each_value{|x|ext(x,o,d+1)}
 elsif n.is_a?(Array)
  n.each{|x|ext(x,o,d+1) unless x.is_a?(Numeric)||x.is_a?(String)}
 end
 o
end
def cleanup
 return {'ok'=>false,'why'=>'pid'} unless Process.pid==16624&&Sketchup.active_model.equal?(@m)
 return {'ok'=>false,'why'=>'pending'} if (@case&&!@case[:done])||busy?(c(:UpdateWork))
 uninstall;hb(false)
 er=@errs.dup;r=@fixture&&@fixture[:inst]
 return {'ok'=>false,'why'=>'no fixture'} unless r&&r.valid?
 return {'ok'=>false,'why'=>'not qa fixture'} unless r.get_attribute(@dict,'qa_tag')==TAG
 return {'ok'=>false,'why'=>'user objects present'} unless @m.entities.map(&:entityID).sort==(@base[:ids]+[r.entityID]).uniq.sort
 return {'ok'=>false,'why'=>'user selected fixture'} if @m.selection.include?(r)
 @m.start_operation('MH QA cleanup',true)
 begin
  @m.entities.erase_entities(r)
  loop do
   prgs=false
   (@owned_def_keys||[]).each do |k|
    d=@m.definitions.to_a.find{|x|dk(x)==k}
    next unless d&&d.count_used_instances.to_i==0
    @m.definitions.remove(d);prgs=true
   end
   break unless prgs
  end
  @m.commit_operation
 rescue StandardError=>x
  (@m.abort_operation rescue nil);er<<"cleanup: #{x.class}: #{x.message}"
 end
 @fixture=nil;cm=@m.active_view.camera rescue nil
 {'ok'=>er.empty?,'errors'=>er,'defs'=>@m.definitions.size,'entities'=>@m.entities.size,'same'=>@m.definitions.size==@base[:ds]&&@m.entities.size==@base[:es],'camera'=>(cm ? [cm.eye.to_a,cm.target.to_a,cm.up.to_a] : nil)==@base[:cam],'selection'=>@m.selection.map(&:entityID)==@base[:sel],'materials'=>((@m.materials.map{|x|x.name.to_s}.sort rescue [])==@base[:mats]),'path'=>@m.path.to_s==@base[:path]}
end
end;end;end

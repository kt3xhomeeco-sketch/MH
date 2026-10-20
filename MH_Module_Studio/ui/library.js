'use strict';
(() => {
  let catalog={settings:{view:'grid',thumbnail_size:150,folder:''},folders:[],entries:[],root:''};
  let selected=null, loaded=false, busy=false, query='', lastSignature='', detailSignature='';
  const images=new Map(), queued=new Set(), inflight=new Set();
  let imageTimer=null;
  let conversion={setup:{source:'',destination:'',update:false},running:false,report:null};
  const $=id=>document.getElementById(id);
  const node=(tag,text,className)=>{const n=document.createElement(tag);if(text!=null)n.textContent=text;if(className)n.className=className;return n;};
  const status=(message,error=false)=>{if(message!=null)$('library-status').textContent=message;$('library-status').classList.toggle('error',error);};
  function send(action,extra={}) {
    if(!window.sketchup?.request){status('Mở Library từ MH Module Studio trong SketchUp.',true);return false;}
    window.sketchup.request(JSON.stringify({action,...extra}));return true;
  }
  function command(action,extra={}) {
    if(busy)return;busy=true;controls();
    if(!send(action,extra)){busy=false;controls();}
  }
  function controls() {
    const blocked=busy||pending||state.busy||conversion.running;
    ['library-choose','library-refresh','library-save','library-open-hud','library-edit-hud'].forEach(id=>{$(id).disabled=blocked;});
    $('library-convert').disabled=Boolean(pending||state.busy);
    for(const id of ['conversion-source-pick','conversion-destination-pick','conversion-update'])$(id).disabled=blocked;
    $('conversion-start').disabled=blocked||!conversion.setup.source||!conversion.setup.destination;
    $('conversion-cancel').disabled=!conversion.running;
    $('conversion-open').disabled=blocked||!conversion.report||!['complete','cancelled','stopped'].includes(conversion.report.status);
    $('library-place').disabled=blocked||!selected;
    $('library-replace-selection').disabled=blocked||!selected;
    $('library-image-view').disabled=blocked||!selected;$('library-update-image').disabled=blocked||!selected;
    document.querySelectorAll('.library-card').forEach(card=>{card.dataset.hudDraggable=String(Boolean(catalog.hud_editing)&&!blocked);});
    $('library-edit-hud').classList.toggle('active',Boolean(catalog.hud_editing));
  }
  function tab(open) {
    document.body.classList.toggle('library-mode',open);$('library-workspace').hidden=!open;
    $('library-tab').classList.toggle('active',open);$('learn-tab').classList.toggle('active',!open);
    if(open&&!loaded)command('library_ready');
    send('library_visibility',{visible:open});
    if(!open)mainViewer.schedule();
  }
  $('library-tab').addEventListener('click',()=>tab(true));
  $('learn-tab').addEventListener('click',()=>tab(false));
  $('library-choose').addEventListener('click',()=>command('library_choose'));
  $('library-refresh').addEventListener('click',()=>command('library_refresh'));
  $('library-save').addEventListener('click',()=>command('library_save'));
  $('library-convert').addEventListener('click',()=>{$('library-conversion').hidden=!$('library-conversion').hidden;if(!$('library-conversion').hidden)command('library_conversion_ready');});
  $('conversion-close').addEventListener('click',()=>{$('library-conversion').hidden=true;});
  $('conversion-source-pick').addEventListener('click',()=>command('library_conversion_source'));
  $('conversion-destination-pick').addEventListener('click',()=>command('library_conversion_destination'));
  $('conversion-start').addEventListener('click',()=>command('library_conversion_start',{update:$('conversion-update').checked}));
  $('conversion-update').addEventListener('change',()=>send('library_conversion_update',{update:$('conversion-update').checked}));
  $('conversion-cancel').addEventListener('click',()=>send('library_conversion_cancel'));
  $('conversion-open').addEventListener('click',()=>command('library_conversion_open'));
  $('library-open-hud').addEventListener('click',()=>command('library_hud'));
  $('library-place').addEventListener('click',()=>command('library_place',{id:selected}));
  $('library-replace-selection').addEventListener('click',()=>command('library_replace_selection',{id:selected}));
  $('library-edit-hud').addEventListener('click',()=>command('library_hud_edit'));
  $('library-update-image').addEventListener('click',()=>command('library_thumbnail_view',{id:selected,view:$('library-image-view').value}));
  document.addEventListener('keydown',event=>{if(catalog.hud_active&&document.body.classList.contains('library-mode')&&(event.key==='Escape'||event.code==='Space')){event.preventDefault();event.stopPropagation();send('library_hud_exit');}},true);
  $('library-search').addEventListener('input',()=>{query=$('library-search').value;renderItems();});
  ['grid','list'].forEach(view=>$('library-'+view).addEventListener('click',()=>{
    catalog.settings.view=view;renderItems();send('library_settings',{settings:{view}});
  }));
  let sizeTimer;
  $('library-size').addEventListener('input',()=>{
    catalog.settings.thumbnail_size=Number($('library-size').value);applySize();
    clearTimeout(sizeTimer);sizeTimer=setTimeout(()=>send('library_settings',{settings:{thumbnail_size:catalog.settings.thumbnail_size}}),160);
  });
  const fold=text=>String(text).toLowerCase().replace(/đ/g,'d').normalize('NFD').replace(/[\u0300-\u036f]/g,'');
  function applySize(){const size=catalog.settings.thumbnail_size;$('library-items').style.setProperty('--thumb',size+'px');$('library-size').value=size;$('library-size-value').value=size;}
  function requestImage(item) {
    if((images.get(item.id)?.key||images.get(item.id)?.fingerprint)===(item.thumbnail_key||item.fingerprint))return;
    if(inflight.has(item.id))return;
    queued.add(item.id);clearTimeout(imageTimer);imageTimer=setTimeout(flushImages,30);
  }
  function flushImages(){
    if(inflight.size||!queued.size)return;
    const ids=[...queued].slice(0,8);ids.forEach(id=>{queued.delete(id);inflight.add(id);});
    if(!send('library_thumbnails',{ids})){inflight.clear();}
  }
  const observer=new IntersectionObserver(entries=>entries.forEach(entry=>{
    if(entry.isIntersecting){const item=catalog.entries.find(row=>row.id===entry.target.dataset.id);if(item)requestImage(item);observer.unobserve(entry.target);}
  }),{root:$('library-items').parentElement,rootMargin:'200px'});
  function fillImage(container,item){
    container.replaceChildren();const image=images.get(item.id);
    if((image?.key||image?.fingerprint)===(item.thumbnail_key||item.fingerprint)&&image.url){const img=node('img');img.src=image.url;img.alt=item.name;img.draggable=false;container.append(img);}
    else container.append(node('span',image?.url===null?'Chưa có thumbnail':'SKP','library-placeholder'));
  }
  function select(id){selected=id;document.querySelectorAll('.library-card').forEach(card=>{card.classList.toggle('selected',card.dataset.id===id);card.setAttribute('aria-selected',String(card.dataset.id===id));});renderDetail();controls();}
  function renderDetail(){
    const item=catalog.entries.find(row=>row.id===selected);$('library-preview').replaceChildren();
    $('library-selected-name').textContent=item?.name||'Chọn module';$('library-selected-path').textContent=item?.id||'';
    $('library-selected-size').textContent=item?`${(item.bytes/1024).toLocaleString('vi-VN',{maximumFractionDigits:0})} KB · SKP`:'';
    const selector=$('library-image-view'),views=catalog.thumbnail_views||{saved:'Ảnh gốc SKP',iso:'3D',front:'Mặt đứng',top:'Mặt bằng',left:'Mặt trái',right:'Mặt phải',back:'Mặt sau',bottom:'Mặt dưới'};
    const signature=JSON.stringify([catalog.root,item?.id,item?.thumbnail_key,item?.thumbnail_view,views]);
    if(signature!==detailSignature){detailSignature=signature;selector.replaceChildren();for(const [value,label]of Object.entries(views)){const option=node('option',label);option.value=value;selector.append(option);}selector.value=item?.thumbnail_view||'front';}
    if(item){fillImage($('library-preview'),item);requestImage(item);}
  }
  function renderFolders(){
    const target=$('library-folders');const expanded=new Set([...target.querySelectorAll('details[open]')].map(n=>n.dataset.folder));target.replaceChildren();
    function branch(folder,parent){
      const children=catalog.folders.filter(row=>row.parent===folder.id);let container=parent;
      const count=catalog.entries.filter(row=>row.folder===folder.id).length;
      const button=node('button',`▱ ${folder.name}`,'library-folder');button.classList.toggle('selected',catalog.settings.folder===folder.id);button.append(node('small',count));
      button.addEventListener('click',event=>{event.preventDefault();event.stopPropagation();catalog.settings.folder=folder.id;query='';$('library-search').value='';selected=null;renderFolders();renderItems();send('library_settings',{settings:{folder:folder.id}});});
      if(children.length){container=node('details',null,'library-folder-branch');container.dataset.folder=folder.id;container.open=expanded.has(folder.id)||!folder.id||catalog.settings.folder.startsWith(folder.id+'/');const summary=node('summary');summary.append(button);container.append(summary);parent.append(container);}else parent.append(button);
      children.forEach(child=>branch(child,container));
    }
    catalog.folders.filter(folder=>folder.parent===null).forEach(folder=>branch(folder,target));
    $('library-folder-help').hidden=Boolean(catalog.root);
  }
  function renderItems(){
    observer.disconnect();const target=$('library-items');target.replaceChildren();
    target.classList.toggle('library-list-view',catalog.settings.view==='list');['grid','list'].forEach(view=>$('library-'+view).classList.toggle('active',view===catalog.settings.view));applySize();
    const folder=catalog.folders.find(row=>row.id===catalog.settings.folder);$('library-folder-name').textContent=folder?.name||'Library';
    const items=catalog.entries.filter(item=>item.folder===catalog.settings.folder&&fold(item.name).includes(fold(query)));
    $('library-count').textContent=`${items.length} module`;$('library-empty').hidden=items.length>0;
    $('library-empty').textContent=!catalog.root?'Chưa có thư viện. Bấm Chọn folder để bắt đầu.':query?'Không tìm thấy module.':'Folder này chưa có SKP. Chọn module đã tạo rồi bấm Lưu module.';
    for(const item of items){const card=node('button',null,'library-card');card.dataset.id=item.id;card.title=item.id;card.setAttribute('role','listitem');
      const picture=node('div',null,'library-image');fillImage(picture,item);const info=node('div',null,'library-card-info');info.append(node('strong',item.name),node('small',item.id));card.append(picture,info);
      let gesture=null,suppressClick=false,pickToken=null;
      card.draggable=false;
      card.addEventListener('dragstart',event=>event.preventDefault());
      card.addEventListener('click',event=>{if(suppressClick){suppressClick=false;event.preventDefault();return;}if(event.detail>1)return;select(item.id);if(!catalog.hud_editing&&!busy){pickToken=crypto.randomUUID();send('library_pick',{id:item.id,gesture:pickToken});}});
      card.addEventListener('dblclick',()=>{if(!catalog.hud_editing)command('library_place',{id:item.id,gesture:pickToken});});
      card.addEventListener('pointerdown',event=>{
        if(event.button!==0||!catalog.hud_editing||busy)return;
        gesture={x:event.clientX,y:event.clientY,pointer:event.pointerId,root:catalog.root,token:null};
        try{card.setPointerCapture(event.pointerId);}catch(_error){/* Synthetic UI tests have no active pointer. */}
      });
      card.addEventListener('pointermove',event=>{
        if(!gesture||event.pointerId!==gesture.pointer)return;
        if(!gesture.token&&Math.hypot(event.clientX-gesture.x,event.clientY-gesture.y)>5){
          gesture.token=crypto.randomUUID();send('library_hud_drag',{id:item.id,root:gesture.root,token:gesture.token});
          card.classList.add('hud-dragging');status('Thả module vào một ô icon trên HUD.');
        }
        if(gesture.token)event.preventDefault();
      });
      function endGesture(cancel){
        const active=gesture;gesture=null;card.classList.remove('hud-dragging');
        if(active?.token){suppressClick=!cancel;send(cancel?'library_hud_cancel':'library_hud_drop',{token:active.token});}
        if(active&&card.hasPointerCapture(active.pointer))card.releasePointerCapture(active.pointer);
      }
      card.addEventListener('pointerup',()=>endGesture(false));
      card.addEventListener('pointercancel',()=>endGesture(true));
      card.addEventListener('lostpointercapture',()=>endGesture(true));
      target.append(card);observer.observe(card);
    }
    if(!items.some(item=>item.id===selected))selected=null;
    if(!selected&&items.length)selected=items[0].id;
    select(selected);
  }
  window.receiveLibrary=next=>{
    if(next.conversion)renderConversion(next.conversion);
    if(!next.background)busy=false;loaded=true;catalog=next;status(next.message||`${next.entries.length} module trong thư viện.`,Boolean(next.error));
    const valid=new Set(catalog.entries.map(item=>item.id));
    for(const id of images.keys())if(!valid.has(id))images.delete(id);
    for(const id of queued)if(!valid.has(id))queued.delete(id);
    $('library-path').textContent=catalog.root||'Chưa chọn folder';$('library-path').title=catalog.root||'';
    const signature=JSON.stringify([catalog.root,catalog.entries,catalog.folders,catalog.settings.folder,catalog.settings.view]);
    if(signature!==lastSignature){lastSignature=signature;renderFolders();renderItems();}else{applySize();controls();}
    // Main Studio receives separate updates and may reset generic button states.
    controls();
    if(next.error){inflight.clear();flushImages();}
  };
  window.receiveLibraryThumbnails=next=>{
    for(const [id,image] of Object.entries(next)){const item=catalog.entries.find(row=>row.id===id);const key=image.key||image.fingerprint;if(item&&key===(item.thumbnail_key||item.fingerprint))images.set(id,image);inflight.delete(id);if(item&&key&&key!==(item.thumbnail_key||item.fingerprint))requestImage(item);}
    document.querySelectorAll('.library-card').forEach(card=>{const item=catalog.entries.find(row=>row.id===card.dataset.id);if(item&&next[item.id])fillImage(card.querySelector('.library-image'),item);});
    renderDetail();flushImages();
  };
  window.refreshLibraryButtons=controls;
  function renderConversion(next){
    conversion=next;
    $('conversion-source').value=next.setup.source||'';$('conversion-destination').value=next.setup.destination||'';
    $('conversion-update').checked=Boolean(next.setup.update);
    const report=next.report,processed=report?.processed??0,total=report?.total??0;
    $('conversion-progress').max=total||1;$('conversion-progress').value=processed;
    const label={ready:'Sẵn sàng',running:'Đang chuyển',complete:'Hoàn tất',cancelled:'Đã dừng',stopped:'Đã dừng do lỗi'};
    $('conversion-status').textContent=next.message||report?.fatal_error||(report?`${label[report.status]||report.status} · ${processed}/${total} file · ${report.converted||0} thành công · ${report.failed||0} lỗi · ${report.existing||0} giữ nguyên`:'Chọn folder nguồn và đích để bắt đầu.');
    $('conversion-status').classList.toggle('error',Boolean(next.error||report?.fatal_error));
    $('conversion-files').replaceChildren();
    for(const row of report?.files||[]){const item=node('div',null,'conversion-file');item.append(node('strong',row.relative),node('span',row.status==='converted'?'Đã chuyển':row.status==='existing'?'Giữ nguyên':'Chưa chuyển được'),node('small',row.error||`${row.editable_parameters||0} tham số sửa được`));$('conversion-files').append(item);}
    $('conversion-report-path').textContent=report?`Báo cáo đầy đủ: ${report.destination}/.conversion/report.json`:'';
  }
  window.receiveLibraryConversion=next=>{busy=false;renderConversion(next);controls();};
})();

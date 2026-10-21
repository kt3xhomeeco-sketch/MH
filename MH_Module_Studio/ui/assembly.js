'use strict';
(()=>{
  const $=id=>document.getElementById(id);
  const modes={contact:'Khoảng cách',center:'Căn giữa',fit:'Vừa khoang',angle:'Góc',repeat:'Lặp / Chia đều'};
  let current=null;
  function send(action,value){if(window.sketchup?.assembly_request)window.sketchup.assembly_request(JSON.stringify({action,value}));}
  const focusInput=id=>document.activeElement===$(id);
  window.receiveAssembly=state=>{
    current=state;const r=state.record,repeat=r.mode==='repeat',between=['center','fit'].includes(r.mode),measured=Boolean(r.r1),automatic=repeat&&r.equal;
    $('mode').value=r.mode;
    document.querySelectorAll('.badge').forEach(node=>node.hidden=r.mode==='contact');
    $('flip').hidden=r.mode!=='contact';
    $('flip').disabled=measured;
    $('contact-mode').classList.toggle('selected',r.mode==='contact');
    $('right-angle').classList.toggle('selected',r.mode==='angle'&&r.angle===90);
    $('angle-mode').classList.toggle('selected',r.mode==='angle'&&r.angle!==90);
    ['a','b','c'].forEach(key=>{const button=$('pick-'+key),ref=r[key];button.classList.toggle('picking',state.picking===key);button.classList.toggle('done',Boolean(ref));$('name-'+key).textContent=ref?.name||'Click để chọn trên model';$('check-'+key).textContent=ref?'✓':'›';});
    ['a','b'].forEach(key=>{const input=$('rename-'+key);input.disabled=!r[key];if(!focusInput('rename-'+key))input.value=r[key]?.module_name||r[key]?.name?.split(' / ')[0]||'';});
    $('label-a').textContent=repeat?'Biên đầu của khoang':'Mặt tham chiếu';$('label-b').textContent=repeat?'Module cần lặp':'Mặt điều chỉnh';
    $('pick-a').hidden=repeat&&!r.equal;$('pick-c').hidden=!between&&!(repeat&&r.equal);
    $('bound').hidden=r.mode!=='contact';$('fit-row').hidden=!between;$('fit-size').checked=r.mode==='fit';
    $('gap-row').hidden=['center','angle'].includes(r.mode);$('angle-row').hidden=r.mode!=='angle';$('repeat-row').hidden=!repeat;
    $('gap-label').textContent=r.mode==='fit'?'Khe hở mỗi bên':repeat?'Khoảng hở giữa các module':'Khoảng cách giữa hai mặt';
    if(!focusInput('gap'))$('gap').value=state.gap==null?'':Number(state.gap.toFixed(3));
    $('gap').readOnly=measured||automatic;
    for(const key of ['angle','count'])if(!focusInput(key))$(key).value=r[key];
    $('equal').checked=Boolean(r.equal);$('ends').checked=Boolean(r.ends);$('ends-row').hidden=!r.equal;
    document.querySelectorAll('[data-direction]').forEach(button=>button.classList.toggle('selected',button.dataset.direction===r.direction));
    document.querySelectorAll('[data-step^="gap:"]').forEach(button=>button.disabled=measured||automatic);
    $('measure').hidden=automatic;$('manual').hidden=!measured||automatic;$('measured').hidden=!measured&&!automatic;
    $('measured').textContent=automatic?'Khoảng hở tự tính từ khoang A–C.':r.r2?'Đang lấy khoảng cách thực giữa R1 và R2.':'Chọn lần lượt mặt R1 và R2 trong model.';
    $('save').textContent=r.id?'Cập nhật liên kết':'Tạo liên kết';$('save').disabled=!state.complete;
    $('group').disabled=!r.id;
    $('hint').textContent=state.picking?'Đang chọn mặt '+state.picking.toUpperCase()+'. Click trực tiếp trên tấm trong model SketchUp.':r.id?'Có thể thêm liên kết mới. Bấm Gộp khi đã hoàn tất các liên kết.':between?'Chọn hai mặt giới hạn A–C và một mặt trên B. B sẽ tự vừa khi chọn đủ biên.':'Chọn các mặt, kiểm tra giá trị rồi tạo liên kết. Bấm Gộp khi hoàn tất.';
    $('status').textContent=state.error||state.notice||(state.tool_active===false?'M / S: Move / Scale · Click A/B để chọn mặt':'Esc: hủy chọn / kéo · Space: về Select, giữ HUD');$('status').classList.toggle('error',Boolean(state.error));
    if(state.notice)$('saved').open=true;
    $('link-count').textContent=state.links.length;$('remove').hidden=!r.id;
    const container=$('links');container.replaceChildren();
    const groups=state.link_groups||state.links.map(row=>({modules:[row.a,row.b,row.c].filter(Boolean).map(ref=>({name:ref.module_name||ref.name})),links:[{...row,label:modes[row.mode]+(row.mode==='repeat'?' · '+row.count+' bản':row.mode==='angle'?' · '+row.angle+'°':row.mode==='center'?'':' · '+Number(Number(row.gap).toFixed(3))+' mm')}]}));
    for(const group of groups){
      const section=document.createElement('section');section.className='link-group';
      if(group.name){const heading=document.createElement('strong');heading.className='group-name';heading.textContent=group.name;section.append(heading);}
      const members=document.createElement('div');members.className='linked-modules';
      for(const member of group.modules){const name=document.createElement('div');name.className='linked-module';name.textContent=member.name;name.title=member.name;members.append(name);}
      section.append(members);
      for(const row of group.links){const button=document.createElement('button');button.className='link'+(row.id===r.id?' selected':'');button.textContent=row.label;button.title=[row.a?.name,row.b?.name].filter(Boolean).join(' → ');button.addEventListener('click',()=>send('load',row.id));section.append(button);}
      container.append(section);
    }
  };
  $('mode').addEventListener('change',()=>send('mode',$('mode').value));
  ['a','b','c'].forEach(key=>$('pick-'+key).addEventListener('click',()=>send('pick',key)));
  ['gap','angle','count'].forEach(key=>{$(key).addEventListener('change',()=>send('value',[key,Number($(key).value)]));$(key).addEventListener('keydown',event=>{if(event.key==='Enter')$(key).blur();});});
  document.querySelectorAll('[data-step]').forEach(button=>button.addEventListener('click',()=>{const [key,value]=button.dataset.step.split(':');send('step',[key,Number(value)]);}));
  document.querySelectorAll('[data-direction]').forEach(button=>button.addEventListener('click',()=>send('direction',button.dataset.direction)));
  ['equal','ends'].forEach(key=>$(key).addEventListener('change',()=>send('toggle',key)));
  $('fit-size').addEventListener('change',()=>send('fit_size',$('fit-size').checked));
  $('auto-links').addEventListener('click',()=>send('auto_links',Number($('auto-gap').value)));
  for(const id of ['new','save','group','remove','measure','manual','bound','close','flip'])$(id).addEventListener('click',()=>send(id));
  ['a','b'].forEach(key=>{$('rename-'+key).addEventListener('change',()=>send('rename',[key,$('rename-'+key).value]));$('rename-'+key).addEventListener('keydown',event=>{if(event.key==='Enter')event.currentTarget.blur();});});
  $('contact-mode').addEventListener('click',()=>send('mode','contact'));
  $('angle-mode').addEventListener('click',()=>send('mode','angle'));
  $('right-angle').addEventListener('click',()=>{send('mode','angle');send('value',['angle',90]);});
  $('perpendicular').addEventListener('click',()=>send('value',['angle',90]));
  if(window.sketchup?.assembly_request)send('ready');
})();

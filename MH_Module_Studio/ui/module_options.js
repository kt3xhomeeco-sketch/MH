'use strict';
let state={rows:[]},pending=null,queue=new Map(),drafts=new Map(),timer=null,rendering=false,structure=null,nodes=new Map();
const byId=id=>document.getElementById(id),textTypes=['material','information','behavior','text'];
function send(action,extra={}){if(window.sketchup?.request)window.sketchup.request(JSON.stringify({action,...extra}));}
const editableRows=rows=>rows.flatMap(row=>row.manual_input?[row,row.manual_input]:[row]);
function progress(){byId('updating').hidden=!(pending||queue.size);byId('save-skp').disabled=Boolean(pending||queue.size);}
function flush(){
  clearTimeout(timer);timer=null;
  if(pending||!state.root_pid||!queue.size)return;
  pending=[...queue].map(([id,value])=>({id,value,text:drafts.get(id)}));queue.clear();progress();
  const base={root_pid:state.root_pid,token:state.token};
  if(pending.length===1)send('change',{...base,variable_id:pending[0].id,value:pending[0].value});
  else send('changes',{...base,changes:pending.map(row=>({variable_id:row.id,value:row.value}))});
}
function mark(id,input,immediate=false){
  const row=editableRows(state.rows).find(r=>r.id===id);
  if(rendering||!input.isConnected||input.dataset.rootPid!==state.root_pid||!row?.editable)return;
  const text=input.value;drafts.set(id,text);
  const choice=row.options?.find(option=>String(option.value)===text);
  const value=choice?.formula?text:textTypes.includes(row.category)?text:Number(text.replace(',','.'));
  if(typeof value==='number'&&(!text.trim()||!Number.isFinite(value)||row.range&&(value<row.range[0]||value>row.range[1]))){input.setAttribute('aria-invalid','true');queue.delete(id);progress();return;}
  input.removeAttribute('aria-invalid');
  if(pending?.some(entry=>entry.id===id&&entry.value===value)){queue.delete(id);progress();return;}
  if(!row.mixed&&value===(row.selection??row.value)&&!pending?.some(entry=>entry.id===id&&entry.value!==value)){queue.delete(id);drafts.delete(id);progress();return;}
  queue.set(id,value);clearTimeout(timer);progress();
  if(immediate)flush();else timer=setTimeout(flush,300);
}
function build(rows){
  byId('fields').replaceChildren();nodes.clear();let section=null;
  for(const row of rows){
    if(row.section_id&&row.section_id!==section){const heading=document.createElement('div');heading.className='section';heading.textContent=row.section;byId('fields').append(heading);section=row.section_id;}
    const label=document.createElement('label');label.className='field';const name=document.createElement('span');
    const listed=Boolean(row.options?.length),input=document.createElement(listed?'select':'input'),unit=document.createElement('span');unit.className='unit';
    if(listed){for(const choice of row.options){const option=document.createElement('option');option.textContent=choice.label;option.value=String(choice.value);option.disabled=choice.supported===false;input.append(option);}}
    else input.type='text';
    bindInput(row,input);
    const control=document.createElement('div');control.className='value-control';control.append(input);
    if(row.manual_input){
      const source=row.manual_input,manual=document.createElement('input');manual.type='text';manual.className='manual-value';bindInput(source,manual);control.append(manual);
      nodes.set(source.id,{input:manual});
    }
    label.append(name,control,unit);byId('fields').append(label);nodes.set(row.id,{name,input,unit});
  }
}
function bindInput(row,input){
  input.dataset.variableId=row.id;
  input.addEventListener('input',()=>mark(row.id,input));input.addEventListener('change',()=>mark(row.id,input,true));
  input.addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();mark(row.id,input,true);}if(event.key==='Escape'){event.preventDefault();queue.delete(row.id);drafts.delete(row.id);const current=editableRows(state.rows).find(r=>r.id===row.id);input.value=String(current?.selection??current?.value??'');input.removeAttribute('aria-invalid');progress();}});
}
window.receive=next=>{
  rendering=true;
  const switched=state.root_pid!==next.root_pid||state.session!==next.session,previous=state,active=document.activeElement,focusId=active?.dataset.variableId,start=active?.selectionStart,end=active?.selectionEnd;
  if(switched){queue.clear();drafts.clear();clearTimeout(timer);timer=null;pending=null;structure=null;}
  else if(pending){for(const ack of pending)if(!next.error&&!queue.has(ack.id)&&drafts.get(ack.id)===ack.text)drafts.delete(ack.id);pending=null;}
  state=next;byId('module-name').textContent=next.name||'Chọn module';
  const signature=JSON.stringify(next.rows.map(row=>[row.id,row.section_id,row.section,Boolean(row.options?.length),row.options,row.manual_input?.id]));
  const rebuilt=signature!==structure;
  if(rebuilt){build(next.rows);structure=signature;}
  const available=new Set(editableRows(next.rows).filter(row=>row.editable).map(row=>row.id));
  for(const key of queue.keys())if(!available.has(key)){queue.delete(key);drafts.delete(key);}
  for(const row of editableRows(next.rows)){
    const {name,input,unit}=nodes.get(row.id),listed=input.tagName==='SELECT';
    if(name)name.textContent=row.name;if(unit)unit.textContent=row.unit||'';
    const desired=drafts.get(row.id)??String(row.selection??row.value??'');
    if(listed){input.querySelectorAll('[data-current]').forEach(option=>option.remove());if(!row.options.some(choice=>String(choice.value)===desired)){const option=document.createElement('option');option.dataset.current='true';option.textContent=row.mixed?'Khác nhau':`Giá trị hiện tại: ${desired}`;option.value=desired;input.prepend(option);}input.disabled=!row.editable;}
    else{input.inputMode=textTypes.includes(row.category)?'text':'decimal';input.readOnly=!row.editable;}
    const old=editableRows(previous.rows).find(r=>r.id===row.id);
    if(input.value!==desired&&!(document.activeElement===input&&!drafts.has(row.id)&&old?.value===row.value))input.value=desired;
    input.placeholder=row.mixed?'Khác nhau':'';input.dataset.rootPid=next.root_pid;input.setAttribute('aria-label',row.name);input.title=row.formula||row.reason||row.symbol||'';
  }
  const thumbnail=byId('thumbnail');thumbnail.hidden=!next.thumbnail;byId('thumbnail-placeholder').hidden=Boolean(next.thumbnail);if(next.thumbnail&&thumbnail.getAttribute('src')!==next.thumbnail)thumbnail.src=next.thumbnail;
  byId('selection-label').hidden=Boolean(next.empty);byId('save-skp').hidden=Boolean(next.empty||!next.root_pid);
  byId('message').textContent=next.message||(!next.rows.length&&!next.error&&!next.empty?'Không có tham số được hiển thị.':'');byId('message').hidden=!byId('message').textContent;
  byId('error').textContent=next.error||'';byId('error').hidden=!next.error;
  if(rebuilt&&!switched&&focusId){const field=nodes.get(focusId)?.input;field?.focus();if(field?.tagName==='INPUT'&&start!=null)field.setSelectionRange(start,end);}
  rendering=false;progress();
  if(!next.error&&queue.size&&!switched)flush();
};
byId('save-skp').addEventListener('click',()=>send('save_skp',{root_pid:state.root_pid}));
document.addEventListener('keydown',event=>{if(state.hud_active&&(event.key==='Escape'||event.code==='Space')){event.preventDefault();event.stopPropagation();send('close_hud');}},true);
send('ready');

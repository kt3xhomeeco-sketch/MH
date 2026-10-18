'use strict';
let state={snapshots:[],rule:null,busy:false},draft=[],dirty=false,pending=false,ruleId=null,snapshotId=null,revision=0,cellEdit=null;
let nameEdit=null,afterRename=null;
const partFields=['lenx','leny','lenz','x','y','z'];
const byId=id=>document.getElementById(id),el=(tag,text)=>{const n=document.createElement(tag);if(text!=null)n.textContent=text;return n;};
const fmt=value=>typeof value==='number'?(Math.abs(value)<0.0005?0:value).toLocaleString('vi-VN',{maximumFractionDigits:3}):String(value??'');
function setGroup(name,expanded){
  byId(`${name}-content`).hidden=!expanded;
  const button=byId(`toggle-${name}`);button.textContent=expanded?'▼':'▶';button.setAttribute('aria-expanded',String(expanded));
}
['variables','parts'].forEach(name=>byId(`toggle-${name}`).addEventListener('click',()=>setGroup(name,byId(`${name}-content`).hidden)));
function markDirty(){dirty=true;document.body.classList.add('dirty');refreshButtons();}
function notify(text,error=false){byId('notice').textContent=text;byId('notice').classList.toggle('error',error);}
function request(action,extra={}){
  if(pending||state.busy)return;
  if(!window.sketchup?.request){notify('Mở Parametric từ MH Module Studio trong SketchUp.',true);return;}
  pending=action;refreshButtons();window.sketchup.request(JSON.stringify({action,...extra}));
}
function refreshButtons(){
  const blocked=pending||state.busy,available=Boolean(state.parametric_sheet),assembly=Boolean(state.parametric_sheet?.assembly);
  document.querySelectorAll('button').forEach(button=>button.disabled=blocked);
  ['save-variables','add-variable','revert-variables'].forEach(id=>byId(id).disabled=blocked||!available||assembly||Boolean(cellEdit));
  ['preview','trial','update'].forEach(id=>byId(id).disabled=blocked||!available||assembly||dirty||Boolean(cellEdit));
  byId('module-title').disabled=blocked||!available||Boolean(cellEdit);
  window.ImportTemplateUI?.refresh(blocked,available,assembly,cellEdit);
  document.querySelectorAll('[data-part-name]').forEach(input=>input.disabled=blocked||Boolean(cellEdit));
  byId('save-project').disabled=blocked||!state.rule||dirty||Boolean(cellEdit);
  byId('save-skp').disabled=Boolean(state.busy||pending&&pending!=='rename_model')||!available||Boolean(cellEdit);
  byId('capture-sketchup').disabled=blocked||dirty||Boolean(cellEdit);
  document.querySelectorAll('.cell-editor input').forEach(input=>input.disabled=blocked);
  document.querySelectorAll('#variables-table input,#variables-table select').forEach(field=>field.disabled=blocked||Boolean(cellEdit)||field.dataset.locked==='true');
  document.querySelectorAll('[data-remove-variable]').forEach(button=>{
    const row=draft.find(r=>r.id===button.dataset.removeVariable),symbol=row?.symbol.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
    const referenced=row&&draft.some(r=>r.id!==row.id&&new RegExp(`\\b${symbol}\\b`,'i').test(r.formula));
    button.disabled=blocked||Boolean(cellEdit)||Boolean(row?.binding)||referenced;
    if(referenced)button.title='Biến đang được công thức sử dụng; sửa công thức trước khi xóa.';
  });
}
function field(row,key,locked=false){
  const input=el('input');input.value=row[key]??'';input.dataset.field=key;input.readOnly=locked;
  if(key==='value'&&['copies','copy'].includes(row.category)){input.type='number';input.min='0';input.step='1';}
  input.setAttribute('aria-label',`${row.name} · ${key}`);
  input.addEventListener('input',()=>{row[key]=key==='value'&&!['material','information','behavior','text'].includes(row.category)&&input.value.trim()!==''?Number(input.value):input.value;markDirty();});return input;
}
function renderVariables(){
  const body=byId('variables-table').querySelector('tbody');body.replaceChildren();
  const sheet=state.parametric_sheet;byId('variable-count').textContent=`(${draft.length})`;if(!sheet)return;
  for(const row of draft){
    const imported=sheet.variables.find(r=>r.id===row.id),locked=Boolean(row.binding&&!imported?.editable),tr=el('tr');tr.dataset.variableId=row.id;
    const tick=el('input');tick.type='checkbox';tick.checked=row.exported;tick.title='Hiện trong Thông số module';tick.addEventListener('change',()=>{row.exported=tick.checked;markDirty();});
    tick.setAttribute('aria-label',`Hiện ${row.name} trong Thông số module`);
    const category=el('select');for(const [key,label]of Object.entries(sheet.categories)){const option=el('option',label);option.value=key;category.append(option);}category.value=row.category;
    category.dataset.field='category';category.dataset.locked=String(locked);category.addEventListener('change',()=>{row.category=category.value;if(!row.binding&&['dimension','position'].includes(row.category))row.unit='mm';if(['material','information','behavior','text'].includes(row.category))row.value=String(row.value);else if(!Number.isFinite(Number(row.value)))row.value=0;markDirty();renderVariables();refreshButtons();});
    const manual=imported?.options?.find(choice=>choice.formula?.toLowerCase()===row.formula.trim().replace(/^=/,'').trim().toLowerCase());
    const listed=imported?.options?.length&&(!row.formula.trim()||manual);
    const value=listed?el('select'):field(row,'value',locked||Boolean(row.formula.trim())),formula=field(row,'formula',locked),unit=field(row,'unit',Boolean(row.binding));
    if(listed){
      for(const choice of imported.options){const option=el('option',choice.label);option.value=String(choice.value);option.disabled=choice.supported===false;value.append(option);}
      const selection=manual?.value??row.value;
      if(!imported.options.some(c=>String(c.value)===String(selection))){const option=el('option',`Giá trị hiện tại: ${fmt(row.value)}`);option.value=String(row.value);value.prepend(option);}
      value.value=String(selection);value.dataset.field='value';value.dataset.locked=String(locked);value.title=imported.reason||row.name;value.setAttribute('aria-label',`${row.name} · value`);
      value.addEventListener('change',()=>{const choice=imported.options.find(item=>String(item.value)===value.value);row.formula=choice?.formula||'';if(!choice?.formula)row.value=Number(value.value);markDirty();renderVariables();refreshButtons();if(choice?.input_id)byId('variables-table').querySelector(`[data-variable-id="${choice.input_id}"] input[data-field="value"]`)?.focus();});
    }
    formula.placeholder='—';formula.title='Công thức riêng, ví dụ co_so + 0.6. Để trống để nhập giá trị.';
    if(!listed&&row.formula.trim()&&imported?.computed_value!=null)value.value=imported.computed_value;
    if(imported?.source==='dc_custom_attribute'){
      value.value=imported.computed_value??row.value;
      formula.value=imported.source_formula||'';formula.title='Công thức ATT gốc · chỉ đọc';
    }
    formula.addEventListener('input',()=>{value.readOnly=locked||Boolean(formula.value.trim());if(listed){value.dataset.locked=String(value.readOnly);value.disabled=value.readOnly;}});
    const status=row.binding?(imported?.editable?'Điều khiển hình học · '+(imported.source==='dc_attributes'?'ATT':'Hình học / mẫu'):imported?.reason||'ATT · Giữ cố định'):['rotation','copies','copy','hidden','material','behavior'].includes(row.category)?'Lưu dữ liệu · Chưa điều khiển 3D':'Biến nội bộ · Dùng trong công thức';
    const remove=el('button','×');remove.title=row.binding?'Biến gắn quy tắc gốc; không thể xóa trực tiếp':'Xóa biến';remove.dataset.removeVariable=row.id;
    remove.addEventListener('click',()=>{draft=draft.filter(r=>r.id!==row.id);markDirty();renderVariables();refreshButtons();});
    for(const node of[tick,field(row,'name'),field(row,'symbol'),category,value,unit,formula,el('span',status),remove]){const cell=el('td');cell.append(node);tr.append(cell);}
    tr.children[7].className='row-status';
    if(row.formula)value.title=`Giá trị tính từ công thức ${row.formula}`;
    body.append(tr);
  }
}
function renderParts(){
  const body=byId('parts-table').querySelector('tbody');body.replaceChildren();const sheet=state.parametric_sheet;
  byId('part-count').textContent=`(${sheet?.parts.length||0})`;byId('scene-label').textContent=state.plan?'Kết quả xem trước':'Module đã đọc';
  for(const part of sheet?.parts||[]){
    const tr=el('tr');tr.dataset.partKey=part.key;const label=el('td'),name=el('input'),icon=el('span','▧');icon.className='part-icon';icon.setAttribute('aria-hidden','true');name.value=part.name||part.key;name.dataset.partName=part.key;name.maxLength=120;name.setAttribute('aria-label','Tên chi tiết '+(part.name||part.key));name.title='Đổi tên chi tiết · Enter hoặc click ra ngoài để lưu tên';name.addEventListener('change',()=>renameModel(name.value,part.key));name.addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();commitName(name);name.blur();}});label.append(icon,name);label.title=Array.isArray(part.path)?part.path.join(' / '):String(part.path||part.key);tr.append(label);
    part.values.forEach((value,index)=>{
      const td=el('td'),button=el('button'),entry=part.expressions?.[index];
      const expression=entry?.text||'',hasFormula=Boolean(expression&&expression!=='Quy tắc module'||part.formulas[index]);
      button.className='part-cell'+(hasFormula?' has-formula':'');
      button.append(el('span',fmt(value)));
      if(hasFormula){const f=el('span','ƒ');f.className='formula-mark';f.setAttribute('aria-label','Có công thức');button.append(f);}
      button.dataset.value=String(value);button.dataset.expressionKind=entry?.kind||'measured';
      button.title=(sheet.assembly?'Kích thước / vị trí module con · ':'Double click để sửa công thức · ')+(expression?expression+' · ':'')+(part.formulas[index]||'Đo từ hình học');
      button.addEventListener('click',()=>{byId('cell-formula').textContent=`${part.name} · ${['LenX','LenY','LenZ','X','Y','Z'][index]}${expression?' = '+expression:''} → ${fmt(value)} mm · ${part.formulas[index]?'ATT gốc: '+part.formulas[index]:'Quy tắc / Hình học trong trục module'}`;});
      button.addEventListener('dblclick',()=>{
        if(pending||state.busy||sheet.assembly)return;
        if(dirty){notify('Áp dụng hoặc đọc lại bảng biến trước khi sửa công thức chi tiết.',true);return;}
        const executable=expression&&expression!=='Quy tắc module';
        cellEdit={key:part.key,index,text:executable?expression:String(value),fallback:hasFormula&&!executable};
        renderParts();refreshButtons();focusCellEditor();
      });
      if(cellEdit?.key===part.key&&cellEdit.index===index){
        const editor=el('div');editor.className='cell-editor';const input=el('input');input.value=cellEdit.text;input.setAttribute('aria-label',`${part.name} · ${partFields[index]} · Công thức`);input.placeholder='Để trống để khôi phục quy tắc gốc';
        input.addEventListener('input',()=>{cellEdit.text=input.value;});
        input.addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();saveCellFormula();}if(event.key==='Escape'){event.preventDefault();cancelCellFormula();}});
        const save=el('button','✓'),cancel=el('button','×');save.title='Áp dụng công thức (Enter)';cancel.title='Hủy (Esc)';save.addEventListener('click',saveCellFormula);cancel.addEventListener('click',cancelCellFormula);editor.append(input,save,cancel);td.append(editor);
        byId('cell-formula').textContent=`${part.name} · ${partFields[index]} · Công thức dùng mm, biến module, Module.LenX/LenY/LenZ và LenX/LenY/LenZ/X/Y/Z của chi tiết. Enter: áp dụng; Esc: hủy; để trống: khôi phục quy tắc gốc.${cellEdit.fallback?' ATT gốc / quy tắc mặt chưa chuyển thành biểu thức trong trục module; nhập công thức thay thế. '+(part.formulas[index]||''):''}`;
      }else td.append(button);
      tr.append(td);
    });body.append(tr);
  }
  const attrs=byId('attributes-list');attrs.replaceChildren();for(const attr of sheet?.attributes||[])attrs.append(el('p',`${attr.path} [${attr.node_id||'module'}] · ${attr.label} (${attr.key}) = ${fmt(attr.value)} ${attr.unit} · ${attr.formula||'Cố định'}${attr.diagnostic?' · '+attr.diagnostic:''}`));
}
function focusCellEditor(){const input=document.querySelector('.cell-editor input');input?.focus();input?.select();}
function cancelCellFormula(){if(pending)return;cellEdit=null;renderParts();refreshButtons();}
function saveCellFormula(){
  if(!cellEdit||pending||state.busy||dirty)return;
  request('save_part_formula',{rule_id:ruleId,snapshot_id:snapshotId,revision,part_key:cellEdit.key,field:partFields[cellEdit.index],formula:cellEdit.text});
}
function resetDraft(){draft=structuredClone(state.parametric_sheet?.variables||[]);dirty=false;document.body.classList.remove('dirty');revision=state.parametric_revision||0;window.ImportTemplateUI?.reset(state);renderVariables();refreshButtons();}
function moduleTitle(value){const source=value.snapshots?.at(-1);return String(value.module_name||value.rule?.module_name||source?.module_name||source?.dc_inputs?._name||source?.label||'').replace(/<[^>]*>/g,'');}
window.receive=next=>{
  const previousTitle=moduleTitle(state);
  const action=pending;pending=false;
  const changedModule=ruleId!==next.rule?.id||snapshotId!==next.snapshots?.at(-1)?.id,changedRevision=revision!==(next.parametric_revision||0);
  const hadDraft=dirty,hadCellEdit=Boolean(cellEdit);
  state=next;ruleId=next.rule?.id||null;snapshotId=next.snapshots?.at(-1)?.id||null;
  if(changedModule||changedRevision&&!next.error||action==='save_part_formula'&&!next.error)cellEdit=null;
  const renameAck=action==='rename_model'&&!changedModule;
  if(changedModule||changedRevision&&!renameAck||!dirty)resetDraft();
  else revision=next.parametric_revision||0;
  renderParts();if(document.activeElement!==byId('module-title')||byId('module-title').value===previousTitle)byId('module-title').value=moduleTitle(next);
  notify(next.message||(!state.parametric_sheet?'Đọc và tổng hợp module ở cửa sổ chính.':''),Boolean(next.error));
  if(changedModule&&hadDraft)notify('Module đã đổi; bảng biến đã đọc lại.');
  if(hadCellEdit&&(changedModule||changedRevision)&&action!=='save_part_formula')notify('Module hoặc quy tắc đã đổi; ô công thức được đọc lại.');
  if(action&&next.error&&dirty)notify(next.message+' Bản nhập vẫn được giữ để sửa.',true);
  refreshButtons();
  if(action==='rename_model'){
    if(next.error&&nameEdit){const input=nameEdit.part_key===null?byId('module-title'):Array.from(document.querySelectorAll('[data-part-name]')).find(n=>n.dataset.partName===nameEdit.part_key);if(input)input.value=nameEdit.name;}
    nameEdit=null;
    const follow=afterRename;afterRename=null;
    if(follow&&!next.error&&!changedModule)queueMicrotask(follow);
  }
  if(cellEdit)focusCellEditor();
  if(next.parametric_focus){const row=draft.find(r=>r.binding===next.parametric_focus);if(row){setGroup('variables',true);const field=document.querySelector(`[data-variable-id="${CSS.escape(row.id)}"] [data-field="value"]`);field?.focus();field?.scrollIntoView({block:'nearest'});}}
};
byId('add-variable').addEventListener('click',()=>{
  setGroup('variables',true);
  let n=1;while(draft.some(r=>r.symbol.toLowerCase()===`bien_${n}`))n++;
  draft.push({id:'custom:'+crypto.randomUUID(),binding:null,name:`Biến ${n}`,symbol:`bien_${n}`,category:'number',unit:'',value:0,formula:'',exported:true});markDirty();renderVariables();refreshButtons();
});
byId('revert-variables').addEventListener('click',resetDraft);
byId('save-variables').addEventListener('click',()=>request('save_variables',{rule_id:ruleId,snapshot_id:snapshotId,revision,variables:draft,import_template:window.ImportTemplateUI?.value()}));
function saveAfterRename(callback){if(pending==='rename_model'){afterRename=callback;return;}callback();}
const saveProject=()=>request('save'),saveSkp=()=>request('save_skp',{rule_id:ruleId,snapshot_id:snapshotId,revision,variables:draft,import_template:window.ImportTemplateUI?.value()});
for(const [id,callback]of [['save-project',saveProject],['save-skp',saveSkp]]){
  const button=byId(id);
  button.addEventListener('pointerdown',()=>{
    const active=document.activeElement,key=active===byId('module-title')?null:active?.dataset.partName;
    if(key===undefined)return;
    commitName(active);active.blur();if(pending==='rename_model')afterRename=callback;
  });
  button.addEventListener('click',()=>saveAfterRename(callback));
}
byId('capture-sketchup').addEventListener('click',()=>request('capture_parametric'));
function renameModel(name,part_key=null){if(cellEdit||pending)return;nameEdit={name,part_key};request('rename_model',{name,part_key,rule_id:ruleId,snapshot_id:snapshotId,revision});}
function commitName(input){const key=input===byId('module-title')?null:input.dataset.partName;const current=key===null?moduleTitle(state):state.parametric_sheet?.parts.find(part=>part.key===key)?.name;if(input.value.trim()!==String(current).trim())renameModel(input.value,key);}
byId('module-title').addEventListener('change',()=>renameModel(byId('module-title').value));
byId('module-title').addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();commitName(event.currentTarget);event.currentTarget.blur();}});
['preview','trial','update'].forEach(action=>byId(action).addEventListener('click',()=>request(action,{parametric:true,rule_id:ruleId,snapshot_id:snapshotId})));
refreshButtons();if(window.sketchup?.request)request('ready',{surface:'parametric'});else notify('Parametric · Giao diện kiểm chứng');

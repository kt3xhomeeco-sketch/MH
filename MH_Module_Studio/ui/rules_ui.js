'use strict';
let selectedConstraintId=null, selectedPartKey=null, pickingField=null, newConstraint=null;
const hiddenPartKeys=new Set(), branchState=new Map();
window.isPartHidden=key=>hiddenPartKeys.has(key);
const typeLabels={thickness:'Độ dày / Giữ mặt',fix:'Giữ mặt',contact:'Áp mặt',offset:'Khoảng lệch',align:'Căn mặt',between:'Nằm giữa',center:'Căn giữa',formula:'Công thức ATT',position:'Khoảng cách / Kích thước'};
const sourceLabel=source=>source==='dc_attributes'?'ATT':source==='geometry'?'Tự nhận diện':source==='observations'?'So sánh mẫu':'Đã sửa';
const workspaceRule=()=>state.rule?.kind==='module_rule_system'?state.rule:null;
const activeConstraint=()=>newConstraint || workspaceRule()?.constraints.find(entry=>entry.id===selectedConstraintId);
const partLabel=key=>key==='@module'?'Module':workspaceRule()?.parts.find(part=>part.key===key)?.name || key;
const faceLabel=ref=>ref ? `${partLabel(ref.part)} · ${ref.side?'＋':'−'}${['X','Y','Z'][ref.axis]}` : '';

function treeBranch(id,label,opened=false){
  const details=el('details',null,'browser-branch');details.dataset.branch=id;details.open=branchState.has(id)?branchState.get(id):opened;
  const summary=el('summary',label);details.append(summary);
  details.addEventListener('toggle',()=>{if(details.isConnected)branchState.set(id,details.open);});return details;
}
window.renderRuleWorkspace=()=>{
  const root=byId('module-browser-body');if(!root)return;
  root.querySelectorAll('details[data-branch]').forEach(node=>branchState.set(node.dataset.branch,node.open));root.replaceChildren();
  const snapshot=state.snapshots.at(-1),rule=workspaceRule();
  if(!snapshot){root.append(el('p','Đọc group/component từ SketchUp.','help'));renderConstraintEditor();return;}
  const module=treeBranch('module',CoreName(snapshot),true);root.append(module);
  const parts=treeBranch('parts',`Chi tiết (${snapshot.parts.length})`,true);module.append(parts);
  const pathNodes=new Map();
  for(const part of snapshot.parts){
    let parent=parts;const path=part.key.split('/');
    for(let n=1;n<path.length;n++){
      const key=path.slice(0,n).join('/');
      if(!pathNodes.has(key)){const branch=treeBranch(`part/${key}`,path[n-1],false);parent.append(branch);pathNodes.set(key,branch);}
      parent=pathNodes.get(key);
    }
    const row=el('div',null,'browser-row');row.classList.toggle('selected',selectedPartKey===part.key);
    const eye=el('button',hiddenPartKeys.has(part.key)?'○':'●','eye-button');eye.title='Ẩn/hiện trong khung 3D';eye.setAttribute('aria-label',`Ẩn/hiện ${part.name}`);
    eye.addEventListener('click',()=>{hiddenPartKeys.has(part.key)?hiddenPartKeys.delete(part.key):hiddenPartKeys.add(part.key);renderPlan();window.renderRuleWorkspace();});
    const label=el('button',part.name,'tree-item');label.title=sizeText(part.bounds)+' mm';label.addEventListener('click',()=>selectRulePart(part.key));
    row.append(eye,label);parent.append(row);
  }
  if(rule){
    const params=treeBranch('params',`Tham số (${rule.parameters.length})`);module.append(params);
    rule.parameters.forEach(param=>{
      const branch=treeBranch(`parameter/${param.key}`,`${param.label} · ${typeof param.value==='number'?fmt(param.value):param.value} ${param.unit||''}`);params.append(branch);
      const button=el('button','Sửa giá trị','tree-item');button.addEventListener('click',()=>{request('open_parametric',{parameter_key:param.key});});branch.append(button);
      for(const entry of rule.constraints.filter(c=>c.type==='thickness'&&c.parameter===param.key)){const child=el('button',`${entry.label} · ${entry.anchor==='low'?'Giữ −':entry.anchor==='high'?'Giữ ＋':'Giữ giữa'}${['X','Y','Z'][entry.face.axis]}`,'tree-item');child.addEventListener('click',()=>selectConstraint(entry.id));branch.append(child);}
    });
    const relationships=rule.constraints.filter(entry=>!['formula','thickness'].includes(entry.type)), formulas=rule.constraints.filter(entry=>entry.type==='formula');
    const relations=treeBranch('relations',`Quy tắc module (${relationships.length})`,true);module.append(relations);
    for(const part of rule.parts.filter(p=>p.visible!==false)){
      const group=treeBranch(`relations/${part.key}`,part.name,selectedPartKey===part.key);relations.append(group);
      for(const entry of relationships.filter(c=>c.face?.part===part.key || (c.type!=='position'&&c.other?.part===part.key))){
        const line=el('button',entry.type==='position'?`${entry.label}${entry.measure==='distance'?' '+partLabel(entry.other.part):''} · ${fmt(positionMeasurement(entry))} mm`:entry.label||`${typeLabels[entry.type]} · ${faceLabel(entry.face)}`,'tree-item');line.classList.toggle('selected',entry.id===selectedConstraintId);line.dataset.ruleId=entry.id;
        line.addEventListener('click',()=>selectConstraint(entry.id,part.key));group.append(line);
      }
    }
    if(formulas.length){const att=treeBranch('att',`Công thức / Quy tắc nguồn (${formulas.length})`);module.append(att);for(const entry of formulas){const button=el('button',entry.label,'tree-item');button.title=entry.formula;button.addEventListener('click',()=>selectConstraint(entry.id));att.append(button);}}
    const unsupported=formulas.filter(entry=>!entry.translated).length;
    const hasATT=Object.values(rule.rules).some(entry=>entry.rule_source==='dc_attributes');
    root.append(el('p',hasATT?'ATT → Hệ quy tắc chung':rule.formula_engine?'So sánh mẫu → Hệ quy tắc chung':unsupported?'ATT chưa dịch · Đề xuất từ hình học':'Group thường · Quy tắc từ hình học','browser-source'));
  }else root.append(el('p','Bấm Tự nhận diện để dựng quy tắc.','help'));
  renderConstraintEditor();window.applyRuleSelection();refreshButtons();
};
function selectConstraint(id,partKey=null){selectedConstraintId=id;selectedPartKey=partKey;newConstraint=null;pickingField=null;setTab(false);window.renderRuleWorkspace();}
function selectRulePart(key){selectedPartKey=key;selectedConstraintId=null;newConstraint=null;pickingField=null;branchState.set(`relations/${key}`,true);setTab(false);window.renderRuleWorkspace();}
function populateFace(id,ref){
  const part=byId(`${id}-part`),face=byId(`${id}-face`);part.replaceChildren();
  for(const item of workspaceRule()?.parts||[]){const option=el('option',item.name);option.value=item.key;part.append(option);}
  part.value=ref?.part || part.options[0]?.value || '';face.value=ref?`${ref.axis}:${ref.side}`:'0:0';
}
function readFace(id){const [axis,side]=byId(`${id}-face`).value.split(':').map(Number);return {part:byId(`${id}-part`).value,axis,side};}
function ruleScene(){return byId('scene-mode').value==='result'&&state.plan ? state.plan : state.snapshots.find(s=>s.id===inspectedSnapshotId)||state.snapshots.at(-1);}
function positionMeasurement(entry){
  const data=ruleScene(),lookup=new Map((data?.parts||[]).map(p=>[p.key,p.bounds]));
  const value=ref=>{const box=ref.part==='@module'?data?.envelope:lookup.get(ref.part);return box?.[ref.side]?.[ref.axis];};
  const a=value(entry.face),b=value(entry.other),sign=entry.measure==='dimension'||entry.face.side===0?1:-1;
  const result=Number.isFinite(a)&&Number.isFinite(b)?(a-b)*sign:NaN;return Math.abs(result)<0.001?0:result;
}
const friendlyParameter=p=>{const label=p?.label||p?.key||'';return label===label.toLocaleUpperCase('vi')?label[0]+label.slice(1).toLocaleLowerCase('vi'):label;};
function positionExpression(entry){
  if(!entry.expression)return entry.source==='dc_attributes'?'Theo công thức ATT gốc':'Đo từ hình học hiện tại';
  const dimensionLabels={'@lenx':'Rộng module','@leny':'Sâu module','@lenz':'Cao module'},terms=[];
  for(const [key,value] of Object.entries(entry.expression.coefficients||{})){
    if(Math.abs(value)<1e-8)continue;
    const name=dimensionLabels[key]||friendlyParameter(workspaceRule().parameters.find(p=>p.key===key))||key;
    terms.push({negative:value<0,text:(Math.abs(Math.abs(value)-1)<1e-8?'':fmt(Math.abs(value))+' × ')+name});
  }
  const constant=entry.expression.constant||0;if(Math.abs(constant)>1e-8)terms.push({negative:constant<0,text:fmt(Math.abs(constant))});
  if(!terms.length)return '0';
  return terms.map((term,index)=>(index?term.negative?' − ':' + ':term.negative?'−':'')+term.text).join('');
}
function jumpToParameter(key){
  request('open_parametric',{parameter_key:key});
}
function renderPositionSummary(key,selected){
  const section=byId('module-position-rules'),rows=byId('position-rule-list');rows.replaceChildren();
  const entries=(workspaceRule()?.constraints||[]).filter(c=>c.type==='position'&&c.face.part===key);
  section.hidden=!entries.length;if(!entries.length)return;
  byId('position-part-name').textContent=partLabel(key);section.open=!selected||selected.type==='position';
  for(const entry of entries){
    const card=el('div',null,'position-rule-card');card.dataset.positionId=entry.id;card.classList.toggle('focused',selected?.id===entry.id);
    const heading=el('div',null,'position-rule-heading'),button=el('button',entry.measure==='dimension'?entry.label:`Cách mép ${['trái','phải','trước','sau','dưới','trên'][entry.face.axis*2+entry.face.side]}`,'position-rule-title');
    button.addEventListener('click',()=>selectConstraint(entry.id,key));heading.append(button,el('strong',`${fmt(positionMeasurement(entry))} mm`,'position-value'));card.append(heading);
    if(entry.measure==='distance')card.append(el('p',`${entry.label} ${partLabel(entry.other.part)}`,'position-reference'));
    card.append(el('p',positionExpression(entry),'position-expression'));
    const dependencies=Object.keys(entry.expression?.coefficients||{}).filter(name=>!name.startsWith('@'));
    if(dependencies.length){
      const controls=el('div',null,'position-controls');dependencies.forEach(name=>{
        const parameter=workspaceRule().parameters.find(p=>p.key===name);if(!parameter)return;
        const value=ruleScene()===state.plan?state.plan.target[name]??parameter.value:ruleScene()?.parameter_values?.[name]??parameter.value;
        const link=el('button',`${friendlyParameter(parameter)}: ${typeof value==='number'?fmt(value):value}`,'parameter-link');link.dataset.jumpParameter=name;link.disabled=!parameter.editable||!workspaceRule().exposed_parameter_keys.includes(name);
        link.title=link.disabled?'Thông số đang cố định hoặc chưa được tick cho phép sửa':'Sửa tham số điều khiển';link.addEventListener('click',()=>jumpToParameter(name));controls.append(link);
      });card.append(controls);
    }
    card.append(el('small',entry.source==='dc_attributes'?'ATT · Cập nhật theo tham số':'Hình học · Quan sát hiện tại','rule-provenance'));
    const originals=(entry.formula_indices||[]).map(index=>workspaceRule().attribute_formulas[index]).filter(Boolean);
    if(originals.length){const details=el('details',null,'position-att');details.append(el('summary','ATT gốc'));for(const original of originals){details.append(el('small',`${original.path||'Module'} · ${original.attribute}`),el('pre',original.formula));}card.append(details);}
    rows.append(card);
  }
  const contacts=(workspaceRule()?.constraints||[]).filter(c=>c.type==='contact'&&(c.face.part===key||c.other.part===key));
  for(const contact of contacts){const button=el('button',`${contact.label} · Áp mặt ${fmt(contact.gap||0)} mm`,'position-contact');button.addEventListener('click',()=>selectConstraint(contact.id,key));rows.append(button);}
}
function renderConstraintEditor(){
  const entry=activeConstraint(),editor=byId('constraint-editor');if(!editor)return;
  const testing=byId('test-tab').classList.contains('active'),hasPart=Boolean(selectedPartKey);
  editor.hidden=(!entry&&!hasPart)||testing;
  document.body.classList.toggle('rule-editing',Boolean((entry||hasPart)&&!testing));
  byId('learning-view').hidden=testing||Boolean(entry||hasPart);
  byId('constraint-title').textContent='QUY TẮC MODULE';
  const contextualPart=selectedPartKey || (entry?.type==='position'?entry.face.part:entry?.other?.part || entry?.face?.part);
  renderPositionSummary(contextualPart,entry);
  byId('formula-inspector').hidden=entry?.type!=='formula';
  byId('constraint-fields').hidden=!entry||['formula','position'].includes(entry.type);
  if(!entry){byId('constraint-source').textContent=hasPart?partLabel(selectedPartKey):'';return;}
  byId('constraint-source').textContent=`${sourceLabel(entry.source)}${entry.type==='formula'&&entry.translated?' · Bộ máy quy tắc điều khiển':entry.drive?' · Điều khiển hình học':' · Tham khảo'}`;
  if(entry.type==='position'){byId('constraint-source').textContent=`${partLabel(entry.face.part)} · ${entry.source==='dc_attributes'?'Điều khiển theo ATT':'Đo từ hình học hiện tại'}`;return;}
  if(entry.type==='formula'){byId('formula-expression').textContent=entry.formula;byId('formula-translation').textContent=entry.translated?'Đã quy đổi vào bộ máy quy tắc của app. Sửa giá trị trong Thử tham số.':'Đọc được ATT, chưa dịch được công thức. Xem cảnh báo để kiểm tra.';return;}
  byId('constraint-type').value=entry.type;populateFace('ref1',entry.face);populateFace('ref2',entry.other);populateFace('ref3',entry.third);
  byId('constraint-gap').value=entry.gap||0;byId('constraint-gap2').value=entry.gap2||0;
  byId('constraint-enabled').checked=entry.enabled;byId('constraint-drive').checked=entry.drive;
  byId('constraint-anchor').value=entry.anchor||'low';
  const params=byId('constraint-parameter');params.replaceChildren();
  for(const parameter of workspaceRule()?.parameters.filter(p=>p.editable)||[]){const option=el('option',parameter.label);option.value=parameter.key;params.append(option);}params.value=entry.parameter||params.options[0]?.value||'';
  updateConstraintFields();
}
window.renderModuleRuleContext=renderConstraintEditor;
function updateConstraintFields(){
  const type=byId('constraint-type').value;
  byId('ref2-row').hidden=!['contact','offset','align','between','center'].includes(type);
  byId('ref3-row').hidden=!['between','center'].includes(type);
  byId('constraint-thickness').hidden=type!=='thickness';
  byId('gap-row').hidden=['thickness','fix','align'].includes(type);byId('gap2-row').hidden=type!=='between';
  byId('reverse-direction').hidden=!['contact','offset','align'].includes(type);
  byId('constraint-direction').textContent=['contact','offset','align'].includes(type)?`${partLabel(readFace('ref2').part)} theo ${partLabel(readFace('ref1').part)}`:'Giữ phủ bì của module';
  const entry=activeConstraint();byId('constraint-help').textContent=entry?.source==='dc_attributes'?'ATT điều khiển theo công thức. Quan hệ hình học chỉ dùng khi mày bật Điều khiển.':entry?.drive?'Quy tắc được kiểm tra khi xem trước.':'Đang là quan hệ tham khảo; bật Điều khiển để áp dụng.';
  window.applyRuleSelection();
}
window.refreshRuleButtons=blocked=>{
  ['add-rule','save-constraint','remove-constraint'].forEach(id=>{if(byId(id))byId(id).disabled=blocked||!workspaceRule()||(id!=='add-rule'&&(!activeConstraint()||['formula','position'].includes(activeConstraint().type)));});
  document.querySelectorAll('#constraint-editor input,#constraint-editor select').forEach(node=>node.disabled=blocked);
  document.querySelectorAll('[data-jump-parameter]').forEach(button=>{const key=button.dataset.jumpParameter,p=workspaceRule()?.parameters.find(p=>p.key===key);button.disabled=blocked||!p?.editable||!workspaceRule()?.exposed_parameter_keys.includes(key);});
};
window.applyRuleSelection=()=>{
  mainViewer.colors.clear();
  const expanded=document.body.classList.contains('viewport-expanded');
  const parametric=document.body.classList.contains('parametric-mode');
  mainViewer.viewportPadding=expanded?[0,0]:[byId('module-browser').classList.contains('collapsed')?20:(innerWidth<1120?242:268),parametric?20:(innerWidth<1120?284:316)];
  mainViewer.verticalPadding=parametric&&!expanded?[0,byId('testing-view').getBoundingClientRect().height+18]:[0,0];
  const entry=activeConstraint();
  const editable=entry&&!['formula','position'].includes(entry.type)&&!byId('constraint-editor').hidden;
  const first=editable?readFace('ref1'):entry?.face,second=editable&&!byId('ref2-row').hidden?readFace('ref2'):entry?.other;
  if(first)mainViewer.colors.set(first.part,[0.22,0.66,0.68]);
  if(second&&second.part!==first?.part)mainViewer.colors.set(second.part,[0.93,0.67,0.28]);
  if(selectedPartKey&&!entry)mainViewer.colors.set(selectedPartKey,[0.22,0.66,0.68]);
  mainViewer.schedule();
};
function addRule(type='contact'){
  const rule=workspaceRule();if(!rule)return;
  const entry=rule.constraints.find(c=>c.type==='contact'),first=rule.parts.find(p=>p.key===selectedPartKey)||rule.parts[0],second=rule.parts.find(p=>p.key!==first.key);
  const axis=['thickness','fix'].includes(type)?(first.thickness_axis??0):0;
  newConstraint={type,source:'manual',enabled:true,drive:true,face:!selectedPartKey&&!['thickness','fix'].includes(type)&&entry?.face||{part:first.key,axis,side:1},other:!selectedPartKey&&entry?.other||{part:second?.key||first.key,axis,side:0},gap:0,anchor:'low',parameter:rule.parameters.find(p=>p.editable)?.key};
  selectedConstraintId=null;setTab(false);renderConstraintEditor();window.applyRuleSelection();refreshButtons();
}
byId('detect-rules').addEventListener('click',()=>request('detect_rules'));
byId('add-rule').addEventListener('click',()=>addRule());
document.querySelectorAll('[data-add-rule]').forEach(button=>button.addEventListener('click',()=>addRule(button.dataset.addRule)));
byId('constraint-type').addEventListener('change',updateConstraintFields);
byId('close-constraint').addEventListener('click',()=>{selectedConstraintId=null;newConstraint=null;pickingField=null;window.renderRuleWorkspace();});
byId('reverse-direction').addEventListener('click',()=>{const first=readFace('ref1'),second=readFace('ref2');populateFace('ref1',second);populateFace('ref2',first);updateConstraintFields();});
document.querySelectorAll('#constraint-editor select').forEach(select=>select.addEventListener('change',updateConstraintFields));
byId('save-constraint').addEventListener('click',()=>{
  const type=byId('constraint-type').value,entry={id:selectedConstraintId||crypto.randomUUID(),type,face:readFace('ref1'),gap:Number(byId('constraint-gap').value),gap2:Number(byId('constraint-gap2').value),enabled:byId('constraint-enabled').checked,drive:byId('constraint-drive').checked,anchor:byId('constraint-anchor').value,parameter:byId('constraint-parameter').value};
  if(['contact','offset','align','between','center'].includes(type))entry.other=readFace('ref2');
  if(['between','center'].includes(type))entry.third=readFace('ref3');
  if(type==='fix'||type==='align')entry.gap=0;
  entry.label=entry.other?`${partLabel(entry.face.part)} → ${partLabel(entry.other.part)}`:partLabel(entry.face.part);
  selectedConstraintId=entry.id;newConstraint=null;request('save_constraint',{constraint:entry});
});
byId('remove-constraint').addEventListener('click',()=>{const id=selectedConstraintId;selectedConstraintId=null;request('remove_constraint',{id});});
document.querySelectorAll('[data-pick-ref]').forEach(button=>button.addEventListener('click',()=>{pickingField=button.dataset.pickRef;byId('constraint-help').textContent='Bấm trực tiếp một mặt tấm trong khung 3D.';}));
mainViewer.onPick=ref=>{
  if(!ref)return;
  if(pickingField){populateFace(pickingField,ref);pickingField=null;updateConstraintFields();}
  else selectRulePart(ref.part);
  window.applyRuleSelection();
};
['learn-tab','test-tab'].forEach(id=>byId(id).addEventListener('click',()=>renderConstraintEditor()));
byId('collapse-browser').addEventListener('click',()=>{byId('module-browser').classList.toggle('collapsed');byId('collapse-browser').setAttribute('aria-expanded',String(!byId('module-browser').classList.contains('collapsed')));window.applyRuleSelection();});
byId('expand-view').addEventListener('click',()=>window.applyRuleSelection());
addEventListener('resize',()=>window.applyRuleSelection());
document.addEventListener('keydown',event=>{if(event.key==='Escape'){pickingField=null;window.applyRuleSelection();}});
const relationshipMarker=el('div',null,'relationship-marker');relationshipMarker.hidden=true;mainViewer.canvas.parentElement.append(relationshipMarker);
function updateRelationshipMarker(){
  const entry=activeConstraint(),first=entry?.face&&mainViewer.parts.find(p=>p.key===entry.face.part),second=entry?.other&&mainViewer.parts.find(p=>p.key===entry.other.part);
  relationshipMarker.hidden=!first||!second||first.visible===false||second.visible===false;
  if(relationshipMarker.hidden)return;
  const axis=entry.face.axis,point=first.bounds[0].map((v,a)=>(v+first.bounds[1][a])/2);
  point[axis]=first.bounds[entry.face.side][axis];
  [0,1,2].filter(a=>a!==axis).forEach(a=>{const low=Math.max(first.bounds[0][a],second.bounds[0][a]),high=Math.min(first.bounds[1][a],second.bounds[1][a]);if(high>=low)point[a]=(low+high)/2;});
  const rect=mainViewer.canvas.getBoundingClientRect(),mesh=mainViewer.geometry(rect.width,rect.height),projected=mesh.project(point);
  relationshipMarker.textContent=entry.type==='position'?`${entry.measure==='dimension'?entry.label:'Khoảng cách'} · ${fmt(positionMeasurement(entry))} mm`:`${typeLabels[entry.type]} · ${fmt(entry.gap||0)} mm`;
  relationshipMarker.style.left=`${Math.max(12,Math.min(rect.width-170,projected[0]+8))}px`;
  relationshipMarker.style.top=`${Math.max(8,Math.min(rect.height-42,projected[1]-28))}px`;
}
mainViewer.onViewChange=()=>{renderOrientationCube();updateRelationshipMarker();};
byId('scene-mode').addEventListener('change',()=>window.renderRuleWorkspace());
byId('scene-mode').addEventListener('change',()=>window.renderFullParametric?.());
window.renderRuleWorkspace();

'use strict';
const parametricGroupState=new Map();
function parametricScopeParts(id){
  const nodes=workspaceRule()?.formula_engine?.attribute_program?.dc_graph?.nodes||[];
  const lookup=new Map(nodes.map(n=>[n.id||n.path.join(' / '),n])),matches=[];
  for(const leaf of nodes.filter(n=>n.part_key)){
    let node=leaf;const visited=new Set();
    while(node){const current=node.id||node.path.join(' / ');if(visited.has(current))break;visited.add(current);if(current===id){matches.push(leaf.part_key);break;}node=lookup.get(node.parent_id??node.path.slice(0,-1).join(' / '));}
  }
  return matches;
}
window.renderFullParametric=()=>{
  const root=byId('parametric-derived');root.replaceChildren();
  const rule=workspaceRule(),source=ruleScene();if(!rule||!source)return;
  const groups=new Map(),append=(group,row)=>{if(!groups.has(group))groups.set(group,[]);groups.get(group).push(row);};
  for(const entry of rule.constraints.filter(c=>c.type==='position')){
    const ref=entry.measure==='dimension'?entry.label:`${entry.label} ${partLabel(entry.other.part)}`;
    append(`3D · ${partLabel(entry.face.part)}`,{id:entry.id,label:ref,value:positionMeasurement(entry),unit:'mm',formula:positionExpression(entry),source:entry.source==='dc_attributes'?'ATT → 3D':'Hình học',link:entry.id});
  }
  const actualRows=byId('scene-mode').value==='result'&&state.plan?state.parametric_preview_rows||state.parametric_rows:state.parametric_rows;
  for(const entry of actualRows||[]){
    const names=parametricScopeParts(entry.node_id).map(partLabel).join(', ');
    const scope=entry.node_id?`DC · ${entry.path}${names?' ['+names+']':''} · #${entry.node_id}`:'DC · Module';
    append(scope,{id:entry.id,label:entry.label,value:entry.value,unit:entry.unit,formula:entry.formula||'Giá trị đã đọc',source:entry.status==='unsupported'?'Chưa dịch':entry.status==='computed'?'ATT':'Cố định',diagnostic:entry.diagnostic});
  }
  for(const [name,rows] of groups){
    const section=el('details',null,'parametric-scope');section.open=parametricGroupState.get(name)||false;section.append(el('summary',`${name} (${rows.length})`));
    section.addEventListener('toggle',()=>{if(section.isConnected)parametricGroupState.set(name,section.open);});
    const table=el('table'),head=el('thead'),header=el('tr');['Thông số','Giá trị','Đơn vị','Công thức / Nguồn'].forEach(label=>header.append(el('th',label)));head.append(header);table.append(head);
    const body=el('tbody');for(const row of rows){
      const tr=el('tr');tr.dataset.parametricId=row.id;const nameCell=el('td');
      if(row.link){const button=el('button',row.label,'parametric-rule-link');button.addEventListener('click',()=>selectConstraint(row.link));nameCell.append(button);}else nameCell.textContent=row.label;
      const expression=el('td',row.formula,'parametric-equation');expression.append(el('small',row.source,'rule-provenance'));expression.title=row.diagnostic||row.formula;
      tr.append(nameCell,el('td',typeof row.value==='number'?fmt(row.value):String(row.value??''),'tabular-value'),el('td',row.unit),expression);body.append(tr);
    }table.append(body);section.append(table);root.append(section);
  }
  byId('parametric-diagnostic').textContent=state.parametric_diagnostic||'';
  byId('parametric-count').textContent=`${rule.parameters.length} đầu vào/thông số · ${rule.constraints.filter(c=>c.type==='position').length} thông số 3D · ${(actualRows||[]).length} thuộc tính DC`;
  window.applyRuleSelection();
};
byId('expand-parametric').addEventListener('click',()=>{const expanded=!document.body.classList.contains('parametric-expanded');document.body.classList.toggle('parametric-expanded',expanded);byId('expand-parametric').textContent=expanded?'Thu bảng':'Mở rộng bảng';window.applyRuleSelection();});
document.addEventListener('keydown',event=>{if(event.key==='Escape'){document.body.classList.remove('parametric-expanded');byId('expand-parametric').textContent='Mở rộng bảng';window.applyRuleSelection();}});
window.renderFullParametric();

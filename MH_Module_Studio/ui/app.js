'use strict';
let state = { snapshots: [], rule: null, plan: null, busy: false };
let pending = false;
let inspectedSnapshotId = null;
let latestSnapshotId = null;
const mainViewer = new ModuleViewer(document.getElementById('plan-canvas'));
const byId = id => document.getElementById(id);
const fmt = value => Number(value).toLocaleString('vi-VN', { maximumFractionDigits: 2 });
const dims = bounds => bounds[1].map((value, axis) => value - bounds[0][axis]);
const sizeText = bounds => dims(bounds).map(fmt).join(' × ');
const el = (tag, text, className) => { const node = document.createElement(tag); if (text != null) node.textContent = text; if (className) node.className = className; return node; };
const selectedChoice = () => (state.parameter_choices || []).find(choice => choice.dc_key === state.selected_dc_key);
const parameterValue = snapshot => selectedChoice()?.values[snapshot.id] ?? snapshot.parameter;
const moduleSet = () => ['module_parameter_set','module_rule_system'].includes(state.rule?.kind);
byId('assembly-open-hud')?.addEventListener('click', () => request('assembly_hud'));

function request(action, extra = {}) {
  if (pending || state.busy) return;
  if (!window.sketchup || !window.sketchup.request) {
    byId('notice').textContent = 'Mở bảng này từ Extensions → MH Module Studio trong SketchUp để đọc module.';
    byId('notice').classList.add('error');
    return;
  }
  pending = true;
  refreshButtons();
  window.sketchup.request(JSON.stringify({ action, ...extra }));
}

function refreshButtons() {
  const blocked = pending || state.busy;
  document.querySelectorAll('button').forEach(button => { button.disabled = blocked; });
  ['save', 'preview', 'trial', 'update'].forEach(id => { byId(id).disabled = blocked || !state.rule; });
  byId('create-model').disabled=blocked||!state.rule||!state.snapshots.length;
  const latest = state.snapshots.at(-1);
  const canReadATT = latest?.dc_graph && (Object.keys(latest.dc_inputs || {}).length || latest.dc_graph.nodes?.some(node=>Object.keys(node.attributes || {}).length));
  byId('analyze').disabled = blocked || state.snapshots.length < (canReadATT || byId('parameter-mode').value==='auto' ? 1 : 2);
  if(byId('detect-rules')) byId('detect-rules').disabled=blocked || !state.snapshots.length;
  if(window.refreshRuleButtons) window.refreshRuleButtons(blocked);
  byId('clear').disabled = blocked || !state.snapshots.length;
  ['capture', 'open-skp'].forEach(id => { byId(id).disabled = blocked || state.snapshots.length >= 20; });
  byId('learn-parameter').disabled = blocked || !(state.parameter_choices || []).length;
  document.querySelectorAll('#module-targets input').forEach(input => { input.disabled = blocked; });
  if(window.refreshLibraryButtons) window.refreshLibraryButtons();
}

function readInput() {
  const parameterMode = byId('parameter-mode').value;
  const parameter = Number(byId('parameter').value);
  if (parameterMode === 'manual' && (!Number.isFinite(parameter) || parameter < 0.2 || parameter > 100)) {
    byId('notice').textContent = 'Nhập độ dày của trạng thái đang đọc, trong khoảng 0,2–100 mm.';
    byId('notice').classList.add('error');
    return null;
  }
  return { parameter: parameterMode === 'auto' ? null : parameter, parameter_mode: parameterMode,
    label: byId('state-label').value.trim() || `Trạng thái ${state.snapshots.length + 1}` };
}

function setTab(testing) {
  if(testing){request('open_parametric');return;}
  document.body.classList.toggle('parametric-mode',testing);
  if(!testing) document.body.classList.remove('parametric-expanded');
  byId('learning-view').hidden = testing;
  byId('testing-view').hidden = true;
  byId('learn-tab').classList.toggle('active', !testing);
  byId('test-tab').classList.toggle('active', testing);
  if (testing && state.plan) byId('scene-mode').value = 'result';
  renderPlan();
  if(window.renderModuleRuleContext) window.renderModuleRuleContext();
  if(window.renderFullParametric) window.renderFullParametric();
}

window.receive = next => {
  const previousRuleId = state.rule?.id;
  const previousPlan = state.plan;
  state = next;
  const newest = state.snapshots.at(-1);
  if (newest?.id !== latestSnapshotId) { inspectedSnapshotId = newest?.id || null; latestSnapshotId = inspectedSnapshotId; }
  if (state.plan && JSON.stringify(state.plan) !== JSON.stringify(previousPlan)) byId('scene-mode').value = 'result';
  pending = false;
  renderParameterChoices();
  if (byId('parameter-mode').value === 'auto') {
    const latest = state.snapshots.at(-1);
    byId('parameter').value = latest && (selectedChoice() || latest.parameter_source?.kind === 'geometry_thickness_group') ? parameterValue(latest) : '';
  }
  if (state.rule && !moduleSet() && state.rule.id !== previousRuleId) byId('target').value = (state.rule.sample_range[0] + state.rule.sample_range[1]) / 2;
  renderModuleParameters(previousRuleId);
  byId('notice').textContent = state.message || '';
  byId('notice').classList.toggle('error', Boolean(state.error));
  byId('state-count').textContent = `${state.snapshots.length} / 20`;
  byId('footer-state').textContent = `${state.snapshots.length} trạng thái${state.busy ? ' · Đang đọc SKP…' : ''}`;
  byId('empty').hidden = state.snapshots.length > 0 || Boolean(state.plan);
  renderSnapshots();
  renderComparisons();
  renderRule();
  renderPlan();
  refreshButtons();
  if(window.renderRuleWorkspace) window.renderRuleWorkspace();
  if(window.renderFullParametric) window.renderFullParametric();
};

function renderParameterChoices() {
  const select = byId('learn-parameter'); select.replaceChildren();
  const fallback = el('option', 'Tất cả tham số của module'); fallback.value = ''; select.append(fallback);
  for (const choice of state.parameter_choices || []) {
    const option = el('option', `${choice.label} · ${choice.part_keys.length} tấm`); option.value = choice.dc_key; select.append(option);
  }
  select.value = state.selected_dc_key || '';
  const chosen = selectedChoice();
  byId('parameter-label').readOnly = Boolean(chosen);
  if (chosen) byId('parameter-label').value = chosen.label;
  byId('parameter-name-label').hidden = Boolean((state.parameter_choices || []).length);
  byId('capture-parameter-label').hidden = byId('parameter-mode').value === 'auto' && Boolean((state.parameter_choices || []).length);
  const controls = Object.values(state.fixed_controls || {});
  byId('dc-controls').hidden = !controls.length;
  byId('dc-controls-title').textContent = state.fixed_controls_source === 'rule' ? 'Điều kiện DC của quy tắc' : 'Tham số DC cố định · mẫu cuối';
  byId('fixed-controls').replaceChildren();
  for (const control of controls) {
    const row = el('div', null, 'fixed-control');
    row.append(el('span', control.label), el('strong', `${typeof control.display_value === 'number' ? fmt(control.display_value) : control.display_value}${control.unit ? ' ' + control.unit : ''}`));
    byId('fixed-controls').append(row);
  }
}

function renderModuleParameters(previousRuleId) {
  const grouped = moduleSet();
  byId('module-summary').hidden = !grouped;
  byId('module-targets').hidden = !grouped;
  byId('single-target-label').hidden = grouped;
  const summary = byId('module-parameter-table').querySelector('tbody'); summary.replaceChildren();
  const targetBody = byId('module-targets').querySelector('tbody');
  const drafts = Object.fromEntries(Array.from(targetBody.querySelectorAll('input[data-parameter-key]')).map(input => [input.dataset.parameterKey, input.value]));
  targetBody.replaceChildren();
  if (!grouped) return;
  const commonMM = state.rule.parameters.every(parameter=>parameter.unit==='mm');
  byId('parameter-unit-header').textContent = commonMM ? 'mm' : 'Giá trị';
  for (const parameter of state.rule.parameters) {
    const exposed = (state.rule.exposed_parameter_keys || Object.keys(state.rule.rules)).includes(parameter.key);
    const canEdit = parameter.editable;
    const value = typeof parameter.value === 'number' ? fmt(parameter.value) : parameter.value;
    const source = parameter.rule_source === 'dc_attributes' ? 'ATT' : parameter.rule_source === 'observations' ? 'So sánh mẫu' : parameter.rule_source==='geometry' ? 'Hình học' : '';
    const status = (canEdit ? (exposed?'Hiện trong Thông số module':'Ẩn trong Thông số module') : 'Giữ cố định') + (source ? ` · ${source}` : '');
    const row = el('tr'); row.append(el('td', parameter.label), el('td', `${value}${parameter.unit ? ' ' + parameter.unit : ''}`), el('td', status)); summary.append(row);
    const editRow = el('tr'), cell = el('td'), input = el('input'), tickCell = el('td', null, 'parameter-tick-cell'), tick = el('input');
    tick.type = 'checkbox'; tick.checked = exposed; tick.dataset.exposedKey = parameter.key;
    tick.setAttribute('aria-label', `Hiện ${parameter.label} trong Thông số module`);
    tick.title = 'Tick để hiện tham số trong bảng Thông số module. Bỏ tick chỉ ẩn dòng.';
    tick.addEventListener('change', () => {
      const keys = Array.from(targetBody.querySelectorAll('input[data-exposed-key]:checked')).map(box => box.dataset.exposedKey);
      request('set_exposed_parameters', {keys});
    });
    tickCell.append(tick);
    input.readOnly = !canEdit;
    if (parameter.editable) {
      input.type = 'number'; input.min = String(parameter.input_range?.[0] ?? 0.2); input.max = String(parameter.input_range?.[1] ?? 100); input.step = '0.1';
      input.dataset.parameterKey = parameter.key;
    }
    input.value = canEdit && previousRuleId === state.rule.id && Object.hasOwn(drafts, parameter.key) ? drafts[parameter.key] : parameter.value;
    input.setAttribute('aria-label', parameter.label); input.title = parameter.reason || status;
    cell.append(input);
    if (!commonMM && parameter.unit) cell.append(el('small', parameter.unit));
    const nameCell = el('td', parameter.label);
    if (source) nameCell.append(el('span', source, 'source-chip'));
    if (exposed && !parameter.editable) nameCell.append(el('small', 'Chưa có quy tắc'));
    nameCell.title = status + (parameter.reason ? ' · ' + parameter.reason : '');
    cell.className = 'parameter-value';
    editRow.title = nameCell.title;
    const formulaCell=el('td',parameter.editable?'Nhập giá trị':parameter.reason||'Giữ cố định','parametric-equation');
    editRow.append(tickCell, nameCell, cell, formulaCell); targetBody.append(editRow);
  }
}

function renderSnapshots() {
  const list = byId('snapshot-list'); list.replaceChildren();
  for (const snapshot of state.snapshots) {
    const card = el('div', null, 'snapshot');
    card.append(el('strong', snapshot.label), el('p', moduleSet() ? `${snapshot.parts.length} chi tiết · Cùng module` : `${fmt(parameterValue(snapshot))} mm · ${snapshot.parts.length} chi tiết`));
    const dcValues = (state.parameter_choices || []).map(choice => `${choice.label}: ${fmt(choice.values[snapshot.id])} mm`);
    if (dcValues.length) card.append(el('small', dcValues.join(' · ')));
    const hasDC = Object.keys(snapshot.dc_inputs || {}).length > 0 || snapshot.parts.some(part => Object.keys(part.dc_attributes || {}).length > 0);
    card.append(el('span', hasDC ? 'Có dữ liệu DC' : 'Hình học thường', 'tag'));
    card.append(el('small', snapshot.parameter_source?.kind === 'dc_parameter_set' ? ' · Tham số DC' : snapshot.parameter_source?.kind === 'geometry_thickness_group' ? ' · Độ dày tự đọc' : ' · Độ dày nhập tay'));
    if (state.rule?.training_sample_ids) card.append(el('p', state.rule.training_sample_ids.includes(snapshot.id) ? 'Được dùng để học' : 'Giữ lại · Khác tham số cố định'));
    card.classList.toggle('selected', snapshot.id === inspectedSnapshotId);
    const show = el('button', 'Xem 3D', 'show-state');
    show.addEventListener('click', () => { inspectedSnapshotId = snapshot.id; byId('scene-mode').value = 'source'; mainViewer.fit(); renderPlan(); renderSnapshots(); renderRule(); }); card.append(show);
    const remove = el('button', '×'); remove.title = 'Bỏ trạng thái';
    remove.addEventListener('click', () => request('remove', { id: snapshot.id })); card.append(remove); list.append(card);
  }
  const dcCount = state.snapshots.filter(snapshot => Object.keys(snapshot.dc_inputs || {}).length > 0 || snapshot.parts.some(part => Object.keys(part.dc_attributes || {}).length)).length;
  byId('dc-badge').textContent = state.snapshots.length ? `${dcCount}/${state.snapshots.length} mẫu có DC` : 'Chưa có mẫu';
}

function renderComparisons() {
  const table = byId('comparison-table'), head = table.querySelector('thead'), body = table.querySelector('tbody');
  head.replaceChildren(); body.replaceChildren();
  if (!state.snapshots.length) return;
  const row = el('tr'); row.append(el('th', 'Chi tiết / X × Y × Z (mm)'));
  state.snapshots.forEach(snapshot => row.append(el('th', moduleSet() ? snapshot.label : `${snapshot.label} · ${fmt(parameterValue(snapshot))} mm`))); head.append(row);
  const parts = state.snapshots[0].parts;
  const lookups = state.snapshots.map(snapshot => new Map(snapshot.parts.map(part => [part.key, part])));
  for (const part of parts) {
    const line = el('tr'); line.append(el('td', part.name));
    for (const lookup of lookups) line.append(el('td', lookup.has(part.key) ? sizeText(lookup.get(part.key).bounds) : 'Không khớp'));
    body.append(line);
  }
}

function anchorText(part) {
  const axis = part.thickness_axis, coefficients = part.coefficients;
  const low = coefficients[0][axis].slope, high = coefficients[1][axis].slope;
  const names = ['X', 'Y', 'Z'];
  if (Math.abs(low) < 0.01) return `Giữ mặt −${names[axis]} · Tăng dày về +${names[axis]}`;
  if (Math.abs(high) < 0.01) return `Giữ mặt +${names[axis]} · Tăng dày về −${names[axis]}`;
  if (Math.abs(low + high) < 0.01) return `Giữ mặt giữa theo ${names[axis]}`;
  return `Hai mặt cùng dịch theo ${names[axis]} · Cần kiểm tra`;
}

function renderRule() {
  byId('drivers').replaceChildren(); byId('relations').replaceChildren(); byId('formulas').replaceChildren();
  const latest = state.snapshots.find(snapshot=>snapshot.id===inspectedSnapshotId) || state.snapshots.at(-1);
  byId('part-count').textContent = latest?.parts.length || 0;
  byId('part-list').replaceChildren();
  for (const part of latest?.parts || []) { const row = el('div', null, 'part-item'); row.append(el('span', part.name), el('small', sizeText(part.bounds))); byId('part-list').append(row); }
  const rule = state.rule;
  if(rule?.kind==='module_rule_system') {
    const translated=(rule.attribute_formulas||[]).filter(entry=>entry.translated).length;
    byId('rule-status').textContent=`Hệ quy tắc chung · ${rule.constraints.length} quy tắc · ${translated} công thức ATT đã dịch`;
    byId('warnings').textContent=(rule.warnings||[]).join(' ');
    byId('parameter-badge').textContent=`${rule.parameters.length} tham số`;
    byId('formula-count').textContent=rule.attribute_formulas?.length || 0;
    for(const entry of rule.attribute_formulas||[]) {
      const card=el('div',null,'rule-card relation');card.append(el('strong',`${entry.path||'Module'} · ${entry.attribute} · ${entry.translated?'ATT đã dịch':'ATT chưa dịch'}`),el('p',entry.formula));byId('formulas').append(card);
    }
    return;
  }
  const attCount = moduleSet() ? Object.values(rule.rules).filter(entry=>entry.rule_source==='dc_attributes').length : 0;
  byId('rule-status').textContent = moduleSet() ? `Một module · ${attCount} quy tắc ATT · ${Object.keys(rule.rules).length-attCount} quy tắc so sánh · ${rule.parameters.length} thông số chung` : rule ? `${rule.parameter_label} · ${rule.sample_count}/${state.snapshots.length} trạng thái · ${rule.relations.length} quan hệ đề xuất` : 'Chưa phân tích bộ mẫu.';
  byId('warnings').textContent = rule ? rule.warnings.join(' ') : 'Tấm hộp được xác minh trong SketchUp mới được áp dụng. Bản đầu chưa xử lý tấm cong, đổi số lượng hoặc các nhánh điều kiện.';
  byId('parameter-badge').textContent = moduleSet() ? `${attCount} ATT · ${Object.keys(rule.rules).length-attCount} so sánh` : rule ? '1 quy tắc' : 'Chưa có quy tắc';
  byId('formula-count').textContent = rule?.attribute_formulas?.length || 0;
  if (!rule) return;
  for (const entry of rule.attribute_formulas || []) {
    const card = el('div', null, 'rule-card relation');
    card.append(el('strong', `${entry.path || 'Module'} · ${entry.attribute} · ATT ${entry.translated ? 'đã dịch' : 'đọc được, chưa dịch'}`), el('p', entry.formula));
    byId('formulas').append(card);
  }
  if (!moduleSet()) byId('parameter-label').value = rule.parameter_label;
  const detail = moduleSet() && state.selected_dc_key ? rule.rules[state.selected_dc_key] || rule : rule;
  for (const part of detail.parts.filter(part => part.driver)) {
    const card = el('div', null, 'rule-card anchor'); card.append(el('strong', part.name), el('p', anchorText(part))); byId('drivers').append(card);
  }
  for (const relation of detail.relations) {
    const card = el('div', null, 'rule-card relation');
    card.append(el('strong', `${relation.leader_name} → ${relation.follower_name}`), el('p', `Bám mặt theo ${['X', 'Y', 'Z'][relation.axis]} · Khoảng cách ${fmt(Math.abs(relation.gap_mm))} mm`));
    byId('relations').append(card);
  }
  if (!rule.relations.length && !(rule.attribute_formulas || []).some(entry=>entry.translated)) byId('relations').append(el('p', 'Chưa nhận diện được tiếp giáp có chuyển động khớp. Có thể xem quy tắc quan sát, cần kiểm tra kỹ.', 'help'));
}

function renderPlan() {
  const plan = state.plan, body = byId('plan-table').querySelector('tbody'); body.replaceChildren();
  byId('change-count').textContent = `${plan?.changed_count || 0} tấm`;
  byId('scene-mode').querySelector('option[value=result]').disabled = !plan;
  if (!plan && byId('scene-mode').value === 'result') byId('scene-mode').value = 'source';
  const source = state.snapshots.find(snapshot=>snapshot.id===inspectedSnapshotId) || state.snapshots.at(-1);
  const result = byId('scene-mode').value === 'result' && plan;
  const data = result ? plan : source;
  mainViewer.set((data?.parts || []).map(part=>({...part,visible:part.visible!==false&&!window.isPartHidden?.(part.key)})), new Set(result ? plan.parts.filter(part=>part.changed).map(part=>part.key) : []));
  if(window.applyRuleSelection) window.applyRuleSelection();
  byId('model-name').textContent = CoreName(source);
  byId('model-size').textContent = data ? sizeText(data.envelope) + ' mm' : '';
  byId('scene-status').textContent = result ? `${plan.changed_count} tấm thay đổi` : source?.label || '';
  if (!plan) { byId('plan-caption').textContent = 'Nhập tham số rồi bấm Xem trước. Model chưa bị sửa.'; return; }
  const description = plan.multi_parameter ? Object.entries(plan.target).map(([key,value]) => `${plan.parameter_labels[key]}: ${fmt(plan.previous[key])} → ${fmt(value)} mm`).join(' · ') : `${fmt(plan.previous)} → ${fmt(plan.target)} mm`;
  byId('plan-caption').textContent = `${description} · Phủ bì ${sizeText(plan.envelope)} mm${plan.outside_sample_range ? ' · Ngoài phạm vi mẫu đã đọc.' : ''}${plan.combination_unverified ? ' · Tổ hợp chưa có mẫu kiểm chứng riêng.' : ''}`;
  for (const part of plan.parts.filter(part => part.changed)) {
    const row = el('tr'); row.append(el('td', part.name), el('td', sizeText(part.old_bounds)), el('td', sizeText(part.bounds))); body.append(row);
  }
}
function CoreName(source) { return source?.dc_inputs?._name?.replace(/<[^>]*>/g,'').trim() || source?.label || 'Chưa có module'; }
function syncViewerButtons() {
  [['solid-mode',mainViewer.solid && !mainViewer.xray],['edge-mode',mainViewer.edges],['xray-mode',mainViewer.xray]].forEach(([id,active])=>{byId(id).classList.toggle('active',active);byId(id).setAttribute('aria-pressed',String(active));});
  mainViewer.schedule();
}
byId('solid-mode').addEventListener('click',()=>{mainViewer.solid=true;mainViewer.xray=false;syncViewerButtons();});
byId('edge-mode').addEventListener('click',()=>{mainViewer.edges=!mainViewer.edges;syncViewerButtons();});
byId('xray-mode').addEventListener('click',()=>{mainViewer.xray=!mainViewer.xray;syncViewerButtons();});
const cubeFaces = [
  {name:'left',indices:[0,1,3,2],normal:[-1,0,0]},
  {name:'right',indices:[4,6,7,5],normal:[1,0,0]},
  {name:'front',indices:[0,4,5,1],normal:[0,-1,0]},
  {name:'back',indices:[2,3,7,6],normal:[0,1,0]},
  {name:'bottom',indices:[0,2,6,4],normal:[0,0,-1]},
  {name:'top',indices:[1,5,7,3],normal:[0,0,1]}
];
function renderOrientationCube() {
  const yaw=mainViewer.yaw,pitch=mainViewer.pitch;
  const eye=[-Math.sin(yaw)*Math.cos(pitch),-Math.cos(yaw)*Math.cos(pitch),Math.sin(pitch)];
  const points=[-1,1].flatMap(x=>[-1,1].flatMap(y=>[-1,1].map(z=>{
    const right=Math.cos(yaw)*x-Math.sin(yaw)*y,depth=-Math.sin(yaw)*x-Math.cos(yaw)*y;
    return [55+right*25,55-(Math.cos(pitch)*z-Math.sin(pitch)*depth)*25];
  })));
  cubeFaces.forEach(face=>{
    const node=document.querySelector(`#orientation-cube [data-view=${face.name}]`);
    const facing=face.normal.reduce((sum,value,axis)=>sum+value*eye[axis],0);
    node.setAttribute('display',facing>0.000001?'inline':'none');
    const selected=facing>0.99999;
    node.classList.toggle('selected',selected);node.setAttribute('aria-pressed',String(selected));
    const corners=face.indices.map(index=>points[index]);
    node.querySelector('polygon').setAttribute('points',corners.map(point=>point.join(',')).join(' '));
    const x=corners.reduce((sum,point)=>sum+point[0],0)/4,y=corners.reduce((sum,point)=>sum+point[1],0)/4;
    const text=node.querySelector('text');text.setAttribute('x',x);text.setAttribute('y',y);
  });
}
mainViewer.onViewChange=renderOrientationCube;
function setCameraView(name) { byId('camera-view').value=name; mainViewer.view(name);renderOrientationCube(); }
byId('camera-view').addEventListener('change',()=>setCameraView(byId('camera-view').value));
byId('fit-view').addEventListener('click',()=>mainViewer.fit());
byId('scene-mode').addEventListener('change',()=>renderPlan());
let cubePointer=null,cubeDragged=false;
const cubeSVG=byId('orientation-cube');
cubeSVG.addEventListener('pointerdown',event=>{cubePointer={x:event.clientX,y:event.clientY,id:event.pointerId,view:event.target.closest('[data-view]')?.dataset.view};cubeDragged=false;cubeSVG.setPointerCapture(event.pointerId);});
cubeSVG.addEventListener('pointermove',event=>{
  if(!cubePointer||cubePointer.id!==event.pointerId)return;
  const dx=event.clientX-cubePointer.x,dy=event.clientY-cubePointer.y;
  if(Math.abs(dx)+Math.abs(dy)>1)cubeDragged=true;
  mainViewer.yaw+=dx*0.015;mainViewer.pitch=Math.max(-Math.PI/2,Math.min(Math.PI/2,mainViewer.pitch+dy*0.015));
  cubePointer.x=event.clientX;cubePointer.y=event.clientY;mainViewer.schedule();
});
cubeSVG.addEventListener('pointerup',()=>{if(cubePointer&&!cubeDragged&&cubePointer.view)setCameraView(cubePointer.view);cubePointer=null;});
['pointercancel','lostpointercapture'].forEach(event=>cubeSVG.addEventListener(event,()=>{cubePointer=null;}));
document.querySelectorAll('#orientation-cube [data-view]').forEach(face=>{
  face.addEventListener('click',()=>{if(!cubeDragged)setCameraView(face.dataset.view);cubeDragged=false;});
  face.addEventListener('keydown',event=>{if(event.key==='Enter'||event.key===' '){event.preventDefault();setCameraView(face.dataset.view);}});
});
renderOrientationCube();
function expandViewport(expanded) { document.body.classList.toggle('viewport-expanded',expanded); byId('expand-view').setAttribute('aria-pressed',String(expanded)); byId('expand-view').title=expanded?'Thu khung 3D':'Phóng lớn khung 3D'; mainViewer.schedule(); }
byId('expand-view').addEventListener('click',()=>expandViewport(!document.body.classList.contains('viewport-expanded')));
document.addEventListener('keydown',event=>{if(event.key==='Escape')expandViewport(false);});

byId('learn-tab').addEventListener('click', () => setTab(false));
byId('test-tab').addEventListener('click', () => setTab(true));
byId('learn-parameter').addEventListener('change', () => request('select_parameter', {dc_key: byId('learn-parameter').value}));
byId('parameter-mode').addEventListener('change', () => {
  const automatic = byId('parameter-mode').value === 'auto';
  byId('parameter').readOnly = automatic;
  byId('parameter-help').textContent = automatic
    ? 'Ưu tiên công thức ATT. So sánh mẫu khi công thức thiếu hoặc chưa hỗ trợ.'
    : 'Nhập độ dày thực tế của nhóm tấm cần học. Giá trị này phải khớp hình học ở bảng dưới.';
  if (automatic) byId('parameter').value = '';
  byId('capture-parameter-label').hidden = automatic && Boolean((state.parameter_choices || []).length);
});
byId('capture').addEventListener('click', () => { const input = readInput(); if (input) request('capture', input); });
byId('open-skp').addEventListener('click', () => { const input = readInput(); if (input) request('open_skp', input); });
byId('analyze').addEventListener('click', () => request('analyze', { parameter_label: byId('parameter-label').value }));
byId('clear').addEventListener('click', () => { if (window.confirm('Tạo bộ mẫu mới? Các trạng thái chưa lưu sẽ được bỏ khỏi bảng.')) request('clear'); });
byId('save').addEventListener('click', () => request('save'));
byId('create-model').addEventListener('click',()=>request('create_model',{rule_id:state.rule.id,snapshot_id:state.snapshots.at(-1).id,revision:state.parametric_revision||0,target:Number(byId('target').value)}));
byId('open-project').addEventListener('click', () => request('open_project'));
['preview', 'trial', 'update'].forEach(action => byId(action).addEventListener('click', () => {
  if (moduleSet()) {
    const targets = Object.fromEntries(Array.from(document.querySelectorAll('#module-targets input[data-parameter-key]:not([readonly])')).map(input => [input.dataset.parameterKey, Number(input.value)]));
    if (Object.entries(targets).some(([key,value])=>{
      const limits=state.rule.parameters.find(parameter=>parameter.key===key)?.input_range || [0.2,100];
      return !Number.isFinite(value) || value<limits[0] || value>limits[1];
    })) {
      byId('notice').textContent='Nhập giá trị trong phạm vi cho phép của từng tham số.'; return;
    }
    request(action, {targets});
  } else request(action, { target: Number(byId('target').value) });
}));
refreshButtons();
if (window.sketchup?.request) request('ready');
else { byId('notice').textContent = 'Giao diện kiểm chứng — mở từ Extensions → MH Module Studio trong SketchUp.'; }

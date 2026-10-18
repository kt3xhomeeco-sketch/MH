'use strict';
let activeActivityKey = null;
const scopedActions = new Set(['select_activity', 'select_module', 'wrong', 'begin_correction', 'accept_manual_boxes', 'cancel_manual_boxes', 'finish_correction', 'resize', 'split', 'merge', 'add_module', 'template']);
const send = (action, payload = {}) => window.sketchup?.request(JSON.stringify({action, ...(activeActivityKey && scopedActions.has(action) ? {activity_key: activeActivityKey} : {}), ...payload}));
const byId = (id) => document.getElementById(id);
const viewer = new CadViewer(byId('cad'), (box) => send('mark_region', {box}));
const cell = (row, text) => { const td = document.createElement('td'); td.textContent = text ?? ''; row.appendChild(td); };
const number = (value) => Number(value).toLocaleString('vi-VN', {maximumFractionDigits: 2});
let activityMode = false;
let activityAvailable = false;
let activityRecoverable = false;
const eventNames = {scan: 'Đã quét / phân tích CAD', build: 'Đã dựng khối', error: 'Lỗi khi thao tác',
  error_report: 'Đã bấm Sai', correction: 'Đã nhận Kết quả đúng', edit: 'Đã tự lưu chỉnh sửa',
  source_region_report: 'Đã đánh dấu vùng lỗi', unreadable: 'Hồ sơ cần kiểm tra'};
const timeLabel = value => value ? new Date(value).toLocaleString('vi-VN') : '';
const renderActivities = state => {
  activityMode = Array.isArray(state.activities);
  const selected = state.activity_detail;
  activeActivityKey = activityMode ? selected?.key || null : null;
  activityAvailable = Boolean(selected?.available);
  activityRecoverable = Boolean(!selected?.ambiguous && selected?.analysis?.status === 'needs_review' && selected.analysis.signature);
  const controls = byId('workflow-controls'), home = byId('workflow-controls-home');
  home.appendChild(controls);
  home.hidden = activityMode;
  const host = byId('activities');
  const scrollTop = host.scrollTop;
  const openedEvents = new Set([...host.querySelectorAll('.activity-event[open]')].map(e => e.dataset.eventId));
  host.replaceChildren();
  if (!activityMode || !state.activities.length) {
    host.textContent = 'Chưa có quá trình dựng. Quét chọn hoặc nhập mã SP để bắt đầu.';
    return;
  }
  for (const item of state.activities) {
    const row = document.createElement('div'); row.className = 'activity-row';
    row.dataset.activityKey = item.key;
    const trigger = document.createElement('button'); trigger.className = 'activity-heading secondary';
    trigger.setAttribute('aria-expanded', String(selected?.key === item.key));
    trigger.dataset.sessionBlocked = String(Boolean(state.correction && String(state.correction.product_id) !== String(item.product_id)));
    trigger.disabled = Boolean(manualRequest) || trigger.dataset.sessionBlocked === 'true';
    const title = document.createElement('strong'); title.textContent = item.label;
    const meta = document.createElement('small');
    meta.textContent = [timeLabel(item.time), `${selected?.key === item.key ? selected.events.length : item.event_count} sự kiện`, item.last_error || item.status === 'needs_review' ? 'Có lỗi đã ghi' : item.available ? 'Có khối trong model' : 'Chưa có khối / đã xóa'].filter(Boolean).join(' · ');
    trigger.append(title, meta);
    trigger.addEventListener('click', () => send(selected?.key === item.key ? 'activity_close' : 'activity_open', {key: item.key}));
    row.appendChild(trigger); host.appendChild(row);
    if (selected?.key !== item.key) continue;
    const body = document.createElement('div'); body.className = 'activity-body'; row.appendChild(body);
    body.appendChild(controls);
    const information = document.createElement('p'); information.className = 'hint';
    const analysis = selected.analysis || {};
    information.textContent = [analysis.bounds ? `R × S × C: ${analysis.bounds.map(number).join(' × ')} mm` : '',
      analysis.build_stages?.elevation === false ? 'Cao tạm 1600 mm' : '',
      analysis.source_path ? `Nguồn: ${analysis.source_path}` : '',
      item.ambiguous ? 'Có nhiều bộ khối trùng thông tin cũ; chưa thể Select an toàn.' : !item.available ? 'Không còn bộ khối tương ứng trong model; lịch sử vẫn được giữ.' : 'Select chọn lại toàn bộ khối đã tạo; không chọn CAD nguồn.'].filter(Boolean).join('\n');
    body.appendChild(information);
    const log = document.createElement('div'); log.className = 'activity-timeline'; body.appendChild(log);
    for (const event of selected.events || []) {
      const entry = document.createElement('details'); entry.className = 'activity-event';
      entry.dataset.eventId = event.id; entry.open = openedEvents.has(event.id);
      const caption = document.createElement('summary');
      const count = event.after?.modules?.length ?? event.analysis?.modules?.length;
      caption.textContent = [eventNames[event.kind] || event.kind, count === undefined ? '' : `${count} module`,
        event.status === 'accepted' ? 'Đã xác nhận' : event.status === 'unresolved' || event.error || event.analysis?.error ? 'Cần xem lỗi' : '', timeLabel(event.time)].filter(Boolean).join(' · ');
      entry.appendChild(caption);
      const note = document.createElement('p'); note.textContent = event.error || event.analysis?.error || event.reason || (event.analysis?.explanation || []).join('\n');
      if (event.error || event.analysis?.error) note.className = 'bad'; entry.appendChild(note);
      const data = document.createElement('pre'); data.textContent = JSON.stringify(event, null, 2); entry.appendChild(data);
      log.appendChild(entry);
    }
  }
  host.scrollTop = scrollTop;
};
let previousSources = null;
let previousStages = null;
let previousAuxiliary = null;
let manualRequest = null;
let manualSequence = 0;
let manualStarted = 0;
let manualTimedOut = false;
let manualPoll = null;
let manualDeadline = null;
let manualResult = null;
let manualView = {busy: false, correction: null};
const stopManualTimers = () => { clearInterval(manualPoll); clearTimeout(manualDeadline); manualPoll = manualDeadline = null; };
const renderManualFeedback = () => {
  const pending = Boolean(manualRequest), saving = pending && !manualTimedOut;
  const correction = byId('correction-status');
  correction.classList.toggle('hidden', !manualView.correction && !manualResult && !pending);
  correction.dataset.status = manualTimedOut ? 'error' : pending ? 'saving' : manualResult?.status || 'editing';
  correction.textContent = manualTimedOut
    ? 'Chưa nhận được kết quả sau 8 giây. App đang kiểm tra trạng thái; không tự gửi lại lệnh lưu. Bấm Làm mới để kiểm tra lại.'
    : pending ? 'Đang kiểm tra box và lưu kết quả…' : manualResult?.status === 'saved'
    ? `Đã lưu ${manualResult.modules + manualResult.auxiliary} khối đúng: ${manualResult.modules} module và ${manualResult.auxiliary} phần phụ.`
    : manualResult?.status === 'error' ? `Chưa xác nhận được kết quả: ${manualResult.message}`
    : manualView.correction?.manual ? `Đang sửa nguồn ${manualView.correction.source_bounds ? manualView.correction.source_bounds.slice(0, 2).map(number).join(' × ') + ' mm · ' + manualView.correction.source_modules + ' khoang · ' : ''}Chọn các box đúng trong SketchUp rồi bấm Kết quả đúng`
    : manualView.correction ? `Đang sửa ${manualView.correction.code} · Tự lưu mỗi thay đổi` : '';
  byId('accept-boxes').textContent = manualTimedOut ? 'Chưa có phản hồi' : saving ? 'Đang lưu…'
    : manualResult?.status === 'saved' && !manualView.correction ? 'Đã lưu kết quả' : 'Kết quả đúng';
  byId('accept-boxes').setAttribute('aria-busy', String(saving));
  const unavailable = activityMode && (!activeActivityKey || !activityAvailable);
  byId('select-activity').disabled = manualView.busy || unavailable || pending;
  byId('wrong').disabled = manualView.busy || unavailable || Boolean(manualView.correction) || pending;
  byId('accept-boxes').disabled = manualView.busy || unavailable || !manualView.correction?.manual || pending;
  byId('cancel-boxes').disabled = manualView.busy || unavailable || !manualView.correction?.manual || pending;
  byId('begin').disabled = manualView.busy || (unavailable && !activityRecoverable) || Boolean(manualView.correction) || pending;
  byId('begin').textContent = activityMode && !activityAvailable && activityRecoverable ? 'Khôi phục SP chưa dựng' : 'Bắt đầu sửa khối';
  document.querySelectorAll('#workflow-controls [data-action="finish_correction"], #workflow-controls [data-action="resize"], #workflow-controls [data-action="split"], #workflow-controls [data-action="merge"], #workflow-controls [data-action="add_module"], #workflow-controls [data-action="template"]').forEach(button => {
    button.disabled = manualView.busy || unavailable || !manualView.correction || manualView.correction.manual || pending;
  });
  document.querySelectorAll('.activity-heading').forEach(button => { button.disabled = pending || button.dataset.sessionBlocked === 'true'; });
};
window.receiveManualAcceptance = (result) => {
  if (!result || (manualRequest && result.request_id !== manualRequest)) return;
  if (!manualRequest && activityMode && (!activeActivityKey || result.activity_key !== activeActivityKey)) return;
  if (result.status === 'unknown') {
    if (!manualRequest || Date.now() - manualStarted < 8000) return;
    result = {...result, status: 'error', message: 'SketchUp chưa ghi nhận yêu cầu lưu này. Chọn box và bấm Kết quả đúng để gửi lại.'};
  }
  manualResult = result;
  if (['saved', 'error'].includes(result.status)) {
    stopManualTimers(); manualRequest = null; manualTimedOut = false;
    if (result.status === 'saved') manualView.correction = null;
  }
  renderManualFeedback();
};
const pollManualAcceptance = () => {
  if (!manualRequest) return;
  try {
    if (typeof window.sketchup?.request !== 'function') throw new Error('Mất kết nối với SketchUp');
    send('manual_acceptance_status', {request_id: manualRequest});
  } catch (_) { manualTimedOut = true; renderManualFeedback(); }
};
const stageSettings = () => ({build_plan: byId('build-plan').checked, build_elevation: byId('build-elevation').checked,
  build_auxiliary: byId('build-auxiliary').checked});
window.receive = (state) => {
  renderActivities(state);
  manualView = {busy: state.busy, correction: state.correction};
  if (!manualRequest && activityMode && manualResult?.activity_key !== activeActivityKey) manualResult = null;
  if (!manualRequest && !state.manual_acceptance) manualResult = null;
  if (state.manual_acceptance) window.receiveManualAcceptance(state.manual_acceptance);
  renderManualFeedback();
  byId('status').textContent = state.message || 'Chọn nguồn và thư viện một lần để bắt đầu.';
  const rules = state.plan_rules || {};
  byId('plan-rules-status').textContent = rules.updated_at
    ? `${rules.active || 0} quy tắc đang dùng · ${rules.waiting || 0} đang chờ mẫu · ${rules.blocked || 0} cần kiểm tra`
    : 'Tự cập nhật sau Kết quả đúng hoặc lần quét tiếp theo.';
  byId('plan-rules-details').replaceChildren();
  for (const rule of rules.rules || []) {
    const line = document.createElement('p');
    line.textContent = `${({active: 'Đang dùng', waiting: 'Chờ mẫu', blocked: 'Cần kiểm tra'})[rule.status]} · ${rule.examples.length}/${rules.minimum_examples || 3} hình học · kiểm thử ${rule.passed}/${rule.tested}: ${rule.reason}`;
    const sources = (rule.sources || []).map(s => `${s.code.startsWith('SCAN-') ? 'Vùng quét ' + s.event.slice(0, 8) : s.code} (${s.size.map(number).join(' × ')} mm)`);
    if (sources.length) line.textContent += ` Mẫu: ${sources.join('; ')}.`;
    byId('plan-rules-details').appendChild(line);
  }
  for (const issue of [...(rules.issues || []), ...(rules.error ? [{reason: rules.error}] : [])]) {
    const line = document.createElement('p'); line.textContent = issue.reason;
    byId('plan-rules-details').appendChild(line);
  }
  for (const key of ['library', 'python', 'converter']) byId(key).value = state.settings[key] || '';
  const sources = state.settings.sources.join('\n');
  const stages = JSON.stringify([state.settings.build_plan !== false, state.settings.build_elevation === true]);
  if (stages !== previousStages) {
    byId('build-plan').checked = state.settings.build_plan !== false;
    byId('build-elevation').checked = state.settings.build_elevation === true;
    previousStages = stages;
  }
  const auxiliary = state.settings.build_auxiliary !== false;
  if (auxiliary !== previousAuxiliary) {
    byId('build-auxiliary').checked = auxiliary;
    previousAuxiliary = auxiliary;
  }
  for (const id of ['build-plan', 'build-elevation', 'build-auxiliary', 'save']) byId(id).disabled = state.busy;
  if (sources !== previousSources) { byId('sources').value = sources; previousSources = sources; }
  document.querySelectorAll('[data-worker]').forEach((button) => { button.disabled = state.busy; });
  byId('products').replaceChildren();
  state.products.forEach((product) => {
    const row = document.createElement('tr'); row.className = 'pick';
    cell(row, product.automatic_scan ? 'Vùng quét' : product.code); cell(row, product.name); cell(row, product.status === 'ready' ? 'Sẵn sàng' : 'Cần kiểm tra');
    row.lastChild.className = product.status === 'ready' ? 'good' : 'bad';
    row.addEventListener('click', () => send('focus', {code: product.code})); byId('products').appendChild(row);
  });
  byId('errors').replaceChildren();
  const errors = (state.errors || []).filter(error => !error.activity_id && !error.code);
  for (const error of errors) {
    const line = document.createElement('p'); line.className = 'error-item'; line.textContent = error.error; byId('errors').appendChild(line);
  }
  const product = state.focused;
  byId('cad-title').textContent = product ? product.automatic_scan ? product.name : `${product.code} · ${product.name || 'Bản vẽ CAD'}` : 'Bản vẽ CAD';
  viewer.setProduct(product);
  viewer.setEvidence(state.selected_evidence);
  byId('check-view').disabled = !product?.check_outlines?.length;
  byId('check-view').setAttribute('aria-pressed', String(Boolean(viewer.checkView)));
  byId('explanation').textContent = product ? [...(product.explanation || []), ...((product.modules || []).map((m) => `${m.id}: ${m.explanation || 'Bản sửa theo người dùng'}`)), product.error || ''].join('\n') : 'Chọn SP hoặc chọn khối trong model rồi bấm Giải thích.';
  if (product?.learning) {
    const learned = product.learning;
    const mode = {user_confirmed: 'Bố trí do người dùng xác nhận', plan_rule: learned.message || 'Quy tắc tự học đã kiểm thử · đo lại từ CAD mới', plan_exact: 'Bố trí mặt bằng từ box đã xác nhận cùng hình học · cao tạm 1600 mm', staged: learned.message || 'Mặt bằng · cao tạm 1600 mm · chưa có mẫu đúng khớp hình học', exact: 'Mẫu có cùng hình học', similar: 'Suy rộng từ mẫu cùng cấu tạo', review: 'Kinh nghiệm cần kiểm tra', unmatched: 'Chưa có mẫu phù hợp'}[learned.mode];
    byId('explanation').textContent += `\n${mode || learned.mode}${learned.source_code ? ` · mẫu ${learned.source_code}` : ''}.`;
    if (learned.mode === 'similar') byId('explanation').textContent += '\nCác mặt khối đã được đo lại từ CAD mới và đối chiếu mặt bằng/mặt cắt; giữ độ dày ván. Phần phụ giữ riêng.';
    for (const issue of learned.issues || []) {
      byId('explanation').textContent += `\n${issue.source_code ? `${issue.source_code}: ` : ''}${issue.message}`;
      const missingNames = {top_crown_100mm: 'nẹp nóc 100 mm', right_hidden_arch_area: 'phần vòm nét khuất bên phải'};
      if (issue.excluded?.length) byId('explanation').textContent += ` Phần chưa có: ${issue.excluded.map(key => missingNames[key] || key).join(', ')}.`;
    }
  }
  if (product?.manual_boxes) byId('explanation').textContent += `\nĐã nhận ${(product.modules || []).length} module và ${(product.trim_parts || []).length} phần phụ từ các box đúng.`;
  if (product?.geometry_pipeline?.vertical && !product?.manual_boxes) {
    const pipeline = product.geometry_pipeline;
    byId('explanation').textContent += pipeline.mode === 'plan_only'
      ? `\n${pipeline.vertical.columns.length} khoang từ mặt bằng; cao tạm 1600 mm. Mặt đứng đang tắt.`
      : `\nBước 1: ${pipeline.vertical.columns.length} khoang dọc từ mặt bằng. Bước 2: ${(pipeline.horizontal?.modules || []).length} ${product.status === 'ready' ? 'module đã xác định' : 'khối ứng viên'} từ mặt đứng bỏ cánh. Nét đứt ?M là ứng viên cần kiểm tra; nét đỏ là phần chưa ghép.`;
  }
  for (const part of product?.trim_parts || []) {
      if (part.rule === 'plan-short-trim-full-depth-v1') { byId('explanation').textContent += `\n${part.name}: nẹp CAD sâu 50 mm, khối phụ dựng sâu ${number(part.size[1])} mm bằng tủ; cao tạm 1600 mm.`; continue; }
      if (part.role === 'common_base') { byId('explanation').textContent += `\n${part.name}: ${part.size.map(number).join(' × ')} mm; khung đối chiếu chân đế chung.`; continue; }
      if (part.role === 'cad_envelope_reference') { byId('explanation').textContent += '\nĐường bao nguồn CAD giữ dạng tham chiếu, không tính là vật liệu/module.'; continue; }
    byId('explanation').textContent += `\nNẹp ${part.owner_module_id ? `phụ ${part.owner_module_id} (${part.side === 'left' ? 'trái' : 'phải'})` : 'riêng'}: mặt nhìn ${number(part.face_width_mm)} mm, ván ${number(part.stock_thickness_mm)} mm; không tính là module.`;
  }
    if (product?.modules?.some(m => m.plan_profile) || product?.trim_parts?.some(p => p.plan_profile)) byId('explanation').textContent += '\nKhối bo giữ tâm, bán kính và góc quét; dựng bằng ArcCurve. Chiều cao mặt bằng vẫn tạm 1600 mm.';
  if (product?.panel_parts?.length) byId('explanation').textContent += `\n${product.panel_parts.length} tấm/vách/nẹp dựng riêng theo hình học, giữ liên kết cấu kiện; không tính vào số module tủ.`;
  byId('modules').replaceChildren();
  state.current_modules.forEach((mod) => {
    const row = document.createElement('tr'); row.className = 'pick'; cell(row, mod.name || mod.id);
    cell(row, mod.size.map(number).join(' × ')); cell(row, mod.origin.map(number).join(' / '));
    row.addEventListener('click', () => send('select_module', {id: mod.entity_id})); byId('modules').appendChild(row);
  });
};
document.querySelectorAll('[data-action]').forEach((button) => button.addEventListener('click', () => {
  if (button.dataset.action === 'refresh' && manualRequest) { pollManualAcceptance(); return; }
  if (button.dataset.action !== 'accept_manual_boxes') { send(button.dataset.action); return; }
  if (manualRequest) return;
  manualRequest = `${Date.now()}-${++manualSequence}`;
  manualStarted = Date.now(); manualTimedOut = false; manualResult = null;
  renderManualFeedback();
  manualPoll = setInterval(pollManualAcceptance, 2000);
  manualDeadline = setTimeout(() => { manualTimedOut = true; renderManualFeedback(); pollManualAcceptance(); }, 8000);
  try {
    if (typeof window.sketchup?.request !== 'function') throw new Error('Không kết nối được với SketchUp. Đóng và mở lại Quản lý.');
    send('accept_manual_boxes', {request_id: manualRequest, session_id: manualView.correction?.id});
  } catch (error) { window.receiveManualAcceptance({status: 'error', request_id: manualRequest, message: error.message}); }
}));
byId('save').addEventListener('click', () => send('save_settings', {settings: {...stageSettings(), sources: byId('sources').value.split(/\r?\n/).map((p) => p.trim()).filter(Boolean)}}));
byId('build-plan').addEventListener('change', () => {
  if (!byId('build-plan').checked) byId('build-elevation').checked = false;
  send('save_settings', {settings: stageSettings()});
});
byId('build-elevation').addEventListener('change', () => {
  if (byId('build-elevation').checked) byId('build-plan').checked = true;
  send('save_settings', {settings: stageSettings()});
});
byId('build-auxiliary').addEventListener('change', () => send('save_settings', {settings: stageSettings()}));
byId('begin').addEventListener('click', () => send('begin_correction', {reason: byId('reason').value}));
byId('fit').addEventListener('click', () => viewer.fit());
byId('check-view').addEventListener('click', () => {
  viewer.setCheckView(!viewer.checkView);
  byId('check-view').setAttribute('aria-pressed', String(viewer.checkView));
});
send('ready');

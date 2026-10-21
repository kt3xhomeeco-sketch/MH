'use strict';
let activeActivityKey = null;
let previousAI;
let geometryOnly = false;
const scopedActions = new Set(['select_activity', 'select_module', 'wrong', 'begin_correction', 'accept_manual_boxes', 'cancel_manual_boxes', 'finish_correction', 'resize', 'split', 'merge', 'add_module', 'template']);
const send = (action, payload = {}) => window.sketchup?.request(JSON.stringify({action, ...(activeActivityKey && scopedActions.has(action) ? {activity_key: activeActivityKey} : {}), ...payload}));
const byId = (id) => document.getElementById(id);
window.receiveProgress = state => { byId('status').textContent = state.message; };
const viewer = new CadViewer(byId('cad'), (box) => send('mark_region', {box}));
const cell = (row, text) => { const td = document.createElement('td'); td.textContent = text ?? ''; row.appendChild(td); };
const number = (value) => Number(value).toLocaleString('vi-VN', {maximumFractionDigits: 2});
let activityMode = false;
let activityAvailable = false;
let activityRecoverable = false;
let activityRows = [];
let expandedActivityKey = null;
const eventNames = {scan: 'Đã quét / phân tích CAD', build: 'Đã dựng khối', error: 'Lỗi khi thao tác',
  error_report: 'Đã bấm Sai', correction: 'Đã nhận Kết quả đúng', edit: 'Đã tự lưu chỉnh sửa',
  source_region_report: 'Đã đánh dấu vùng lỗi', unreadable: 'Hồ sơ cần kiểm tra'};
const timeLabel = value => value ? new Date(value).toLocaleString('vi-VN') : '';
const renderActivities = state => {
  activityMode = Array.isArray(state.activities);
  const selected = state.activity_detail;
  activityRows = state.activities || [];
  document.body.classList.toggle('activity-mode', activityMode);
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
    const expanded = selected?.key === item.key && expandedActivityKey === item.key;
    const header = document.createElement('div'); header.className = 'activity-header';
    const trigger = document.createElement('button'); trigger.className = 'activity-heading secondary';
    trigger.setAttribute('aria-expanded', String(expanded));
    trigger.dataset.sessionBlocked = String(Boolean(state.correction && String(state.correction.product_id) !== String(item.product_id)));
    trigger.disabled = Boolean(manualRequest) || trigger.dataset.sessionBlocked === 'true';
    const title = document.createElement('strong'); title.textContent = item.label;
    const meta = document.createElement('small');
    meta.textContent = [timeLabel(item.time), `${selected?.key === item.key ? selected.events.length : item.event_count} sự kiện`, item.last_error || item.status === 'needs_review' ? 'Có lỗi đã ghi' : item.available ? 'Có khối trong model' : 'Chưa có khối / đã xóa'].filter(Boolean).join(' · ');
    trigger.append(title, meta);
    trigger.addEventListener('click', () => {
      expandedActivityKey = expanded ? null : item.key;
      send(expanded ? 'activity_close' : 'activity_open', {key: item.key});
    });
    header.appendChild(trigger);
    const actions = document.createElement('div'); actions.className = 'activity-actions';
    for (const [action, label] of [['select_activity', 'Select'], ['wrong', 'Sai'], ['accept_manual_boxes', 'Kết quả đúng'], ['cancel_manual_boxes', 'Hủy sửa']]) {
      const button = document.createElement('button');
      button.dataset.rowAction = action; button.textContent = label;
      if (action === 'select_activity' || action === 'cancel_manual_boxes') button.className = 'secondary';
      button.addEventListener('click', () => {
        if (action === 'accept_manual_boxes') requestManualAcceptance(item.key);
        else send(action, {activity_key: item.key});
      });
      actions.appendChild(button);
    }
    header.appendChild(actions); row.appendChild(header); host.appendChild(row);
    const feedback = document.createElement('div'); feedback.className = 'activity-feedback active-correction hidden';
    feedback.setAttribute('role', 'status'); feedback.setAttribute('aria-live', 'polite'); row.appendChild(feedback);
    if (!expanded) continue;
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
let previousPlanImport = null;
let manualRequest = null;
let manualActivityKey = null;
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
  const correctionRow = activityRows.find(row => manualView.correction && String(row.product_id) === String(manualView.correction.product_id));
  const feedbackKey = pending ? manualActivityKey : manualResult?.activity_key || correctionRow?.key;
  const feedbackVisible = !correction.classList.contains('hidden');
  const feedbackStatus = correction.dataset.status, feedbackText = correction.textContent;
  if (activityMode && feedbackKey !== activeActivityKey) correction.classList.add('hidden');
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
  for (const row of document.querySelectorAll('.activity-row')) {
    const item = activityRows.find(item => item.key === row.dataset.activityKey);
    const sameSession = Boolean(manualView.correction && String(item.product_id) === String(manualView.correction.product_id));
    const blocked = manualView.busy || pending || !item.available || Boolean(manualView.correction && !sameSession);
    for (const button of row.querySelectorAll('[data-row-action]')) {
      const action = button.dataset.rowAction;
      button.disabled = blocked || (action === 'wrong' && Boolean(manualView.correction)) ||
        (['accept_manual_boxes', 'cancel_manual_boxes'].includes(action) && (!sameSession || !manualView.correction?.manual));
      if (action === 'accept_manual_boxes') {
        const ownPending = pending && item.key === manualActivityKey;
        button.textContent = ownPending ? manualTimedOut ? 'Chưa có phản hồi' : 'Đang lưu…' : 'Kết quả đúng';
        button.setAttribute('aria-busy', String(ownPending && !manualTimedOut));
      }
    }
    const feedback = row.querySelector('.activity-feedback');
    feedback.classList.toggle('hidden', !feedbackVisible || item.key !== feedbackKey);
    feedback.dataset.status = feedbackStatus; feedback.textContent = item.key === feedbackKey ? feedbackText : '';
  }
};
window.receiveManualAcceptance = (result) => {
  if (!result || (manualRequest && result.request_id !== manualRequest)) return;
  if (!manualRequest && activityMode && !activityRows.some(row => row.key === result.activity_key)) return;
  if (manualRequest && manualActivityKey && !result.activity_key) result = {...result, activity_key: manualActivityKey};
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
  build_auxiliary: byId('build-auxiliary').checked, import_plan_reference: byId('import-plan-reference').checked,
  ai_enabled: geometryOnly ? previousAI : byId('ai-enabled').checked});
const renderViewDiagnostics = (product, busy) => {
  const host = byId('view-diagnostics'); host.replaceChildren();
  const analysis = product?.view_analysis;
  if (!analysis) return;
  const title = document.createElement('strong'); title.textContent = 'Nhận dạng SP / hình chiếu'; host.appendChild(title);
  const message = document.createElement('p'); message.textContent = analysis.message; host.appendChild(message);
  if (product.plan_results?.length) {
    const layout = document.createElement('p'); layout.className = 'hint';
    const common = product.plan_results[0]?.unified_partial_plan;
    layout.textContent = common ? `${product.plan_results[0].source_plan_variants.length} mặt bằng đối chiếu · một bộ khối chung; chỉ vùng chưa rõ giữ box tạm.` : `${product.plan_results.length} mặt bằng · cách biên nhau 1000 mm${product.build_stages?.elevation ? ' · chiều cao theo dữ liệu từng SP' : ' · cao tạm 1600 mm'}. Mỗi mặt bằng có bộ khối và lịch sử sửa riêng.`;
    host.appendChild(layout);
  }
  for (const text of product.warnings || []) {
    const warning = document.createElement('p'); warning.className = 'hint'; warning.textContent = text; host.appendChild(warning);
  }
  if (analysis.scope_warning && analysis.status === 'selected') {
    const warning = document.createElement('p'); warning.className = 'hint'; warning.textContent = analysis.scope_warning; host.appendChild(warning);
  }
  const roles = {plan: 'Cắt bằng / mặt bằng', plan_candidate: 'Cần xác nhận mặt bằng', detail_section: 'Mặt cắt trích / chi tiết — không tự dựng', section_vertical: 'Cắt đứng / mặt bên',
    elevation: 'Mặt đứng', wall: 'Tường / hình bối cảnh', stairs: 'Cầu thang', unknown: 'Chưa phân loại chắc'};
  for (const candidate of analysis.candidates || []) {
    const row = document.createElement('div'); row.className = 'view-candidate';
    const text = document.createElement('p');
    text.textContent = `${candidate.id} · ${candidate.title || 'Không có tiêu đề'} · ${roles[candidate.role] || candidate.role} · ${number(candidate.width_mm)} × ${number(candidate.height_mm)} mm${(analysis.selected_view_ids || [analysis.selected_view_id]).includes(candidate.id) ? ' · Đang dựng' : ''}`;
    row.appendChild(text);
    const proof = document.createElement('p'); proof.className = 'hint';
    proof.textContent = [...(candidate.reasons || []), ...(candidate.elevation_checks || []).map(c => `Đối chiếu ${c.front_id}: rộng ${number(c.plan_width_mm)} / ${number(c.front_width_mm)} mm; ${c.aligned_panel_faces} biên ván khớp.`),
      ...(candidate.section_links || []).map(c => `Ký hiệu cắt trên ${c.front_id}: ${c.axis === 'horizontal' ? 'ngang' : c.axis === 'vertical' ? 'dọc' : 'xiên/chưa rõ'}.`)].join(' ');
    row.appendChild(proof);
    const actions = document.createElement('div'); actions.className = 'actions';
    const preview = document.createElement('button'); preview.className = 'secondary'; preview.textContent = 'Xem vùng';
    preview.addEventListener('click', () => {
      const view = product.view_previews?.find(v => v.id === candidate.id);
      if (!view) return;
      viewer.setProduct({...product, source_hash: `${product.source_hash}:${candidate.id}`, outlines: view.outlines, modules: [], trim_parts: [], panel_parts: []});
      viewer.setEvidence(null); viewer.fit();
      byId('cad-title').textContent = `${product.code} · ${candidate.title || candidate.id}`;
    });
    actions.appendChild(preview);
    if (candidate.can_confirm && product.status !== 'ready' && !product.envelope_preview) {
      const confirm = document.createElement('button'); confirm.textContent = 'Dùng mặt bằng này'; confirm.disabled = Boolean(busy);
      confirm.addEventListener('click', () => {
        confirm.disabled = true;
        send('confirm_plan_view', {code: product.code, source_hash: product.source_hash, source_path: product.source_path, view_id: candidate.id, signature: candidate.signature});
      });
      actions.appendChild(confirm);
    }
    row.appendChild(actions); host.appendChild(row);
  }
  if (analysis.excluded_context?.length) {
    const note = document.createElement('p'); note.className = 'hint';
    note.textContent = `Đã loại ${analysis.excluded_context.length} nét tường/bối cảnh hoặc nằm ngoài biên SP có bằng chứng.`;
    host.appendChild(note);
  }
};
window.receive = (state) => {
  renderActivities(state);
  manualView = {busy: state.busy, correction: state.correction};
  if (!manualRequest && !state.manual_acceptance) { manualResult = null; manualActivityKey = null; }
  if (state.manual_acceptance) window.receiveManualAcceptance(state.manual_acceptance);
  renderManualFeedback();
  byId('status').textContent = state.message || 'Chọn nguồn và thư viện một lần để bắt đầu.';
  geometryOnly = state.plan_engine === 'oy-stock-sweep-v1';
  if ((state.settings.ai_enabled === true) !== previousAI) {
    previousAI = state.settings.ai_enabled === true; byId('ai-enabled').checked = previousAI;
  }
  byId('ai-enabled').checked = geometryOnly ? false : previousAI;
  byId('ai-enabled').disabled = geometryOnly || state.busy;
  byId('ai-status').textContent = geometryOnly ? 'Mặt bằng dùng bộ quét OY theo độ dày ván, không gọi AI. Bản thuật toán cũ đã lưu riêng; mô hình và cấu hình AI vẫn được giữ.'
    : state.local_ai?.message || 'Qwen3 4B · xử lý trên máy. Bấm Kiểm tra AI để kiểm tra kết nối.';
  const rules = state.plan_rules || {};
  byId('plan-rules-status').textContent = rules.updated_at
    ? `${rules.active || 0} quy tắc đang dùng · ${rules.waiting || 0} đang chờ mẫu · ${rules.blocked || 0} cần kiểm tra`
    : 'Tự cập nhật sau Kết quả đúng hoặc lần quét tiếp theo.';
  if (geometryOnly) byId('plan-rules-status').textContent = 'Bộ quét OY đang dùng. Mẫu đúng chỉ áp dụng lại cho cùng hình học CAD; bộ chuyển quy tắc cũ không chạy.';
  byId('plan-rules-status').nextElementSibling.hidden = geometryOnly;
  byId('plan-rules-details').replaceChildren();
  for (const rule of rules.rules || []) {
    const line = document.createElement('p');
    line.textContent = `${({active: geometryOnly ? 'Đã lưu (không áp dụng)' : 'Đang dùng', waiting: 'Chờ mẫu', blocked: 'Cần kiểm tra'})[rule.status]} · ${rule.examples.length}/${rules.minimum_examples || 3} hình học · kiểm thử ${rule.passed}/${rule.tested}: ${rule.reason}`;
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
  const planImport = state.settings.import_plan_reference !== false;
  if (planImport !== previousPlanImport) { byId('import-plan-reference').checked = planImport; previousPlanImport = planImport; }
  for (const id of ['build-plan', 'build-elevation', 'build-auxiliary', 'import-plan-reference', 'save']) byId(id).disabled = state.busy;
  if (sources !== previousSources) { byId('sources').value = sources; previousSources = sources; }
  document.querySelectorAll('[data-worker]').forEach((button) => { button.disabled = state.busy; });
  if (geometryOnly) byId('ai-enabled').closest('fieldset').querySelector('[data-action="ai_status"]').disabled = true;
  byId('products').replaceChildren();
  state.products.forEach((product) => {
    const row = document.createElement('tr'); row.className = 'pick';
    cell(row, product.automatic_scan ? 'Vùng quét' : product.code); cell(row, product.name); cell(row, product.elevation_pending ? 'Cần kiểm tra mặt đứng' : product.status === 'ready' ? 'Sẵn sàng' : 'Cần kiểm tra');
    row.lastChild.className = product.status === 'ready' && !product.elevation_pending ? 'good' : 'bad';
    row.addEventListener('click', () => send('focus', {code: product.code})); byId('products').appendChild(row);
  });
  byId('errors').replaceChildren();
  const errors = (state.errors || []).filter(error => !error.activity_id && !error.code);
  for (const error of errors) {
    const line = document.createElement('p'); line.className = 'error-item'; line.textContent = error.error; byId('errors').appendChild(line);
  }
  const product = state.focused;
  renderViewDiagnostics(product, state.busy);
  byId('cad-title').textContent = product ? product.automatic_scan ? product.name : `${product.code} · ${product.name || 'Bản vẽ CAD'}` : 'Bản vẽ CAD';
  viewer.setProduct(product);
  viewer.setEvidence(state.selected_evidence);
  byId('check-view').disabled = !product?.check_outlines?.length;
  byId('check-view').setAttribute('aria-pressed', String(Boolean(viewer.checkView)));
  byId('explanation').textContent = product ? [...(product.explanation || []), ...((product.modules || []).map((m) => `${m.id}: ${m.explanation || 'Bản sửa theo người dùng'}`)), product.error || ''].join('\n') : 'Chọn SP hoặc chọn khối trong model rồi bấm Giải thích.';
  if (product?.envelope_preview) byId('explanation').textContent += `\nKHỐI TẠM THEO KHUNG BAO — CHƯA CHIA MODULE. ${product.envelope_preview.reason}\nBấm Sai, vẽ và chọn các box đúng rồi bấm Kết quả đúng. Khối tạm chưa được học làm mẫu đúng.`;
  const depth = product?.partial_plan?.depth_evidence || (product?.envelope_preview?.dimensions_from === 'closed_stock_depth' ? product.envelope_preview.depth_evidence : null);
  if (depth) {
    byId('explanation').textContent += `\nChiều sâu box lấy từ cặp ván kín cùng layer/kiểu nét: ${number(depth.high_mm - depth.low_mm)} mm; nét bối cảnh không kéo biên. Chiều sâu dùng dựng: ${number(product.modules[0].size[1])} mm.`;
  }
  if (product?.partial_plan) byId('explanation').textContent += `\nCHIA TỪNG PHẦN · ${product.partial_plan.confirmed_modules} module đã chia · ${product.partial_plan.unresolved_modules} vùng giữ box tạm. Đối chiếu ${product.source_plan_variants.length} mặt bằng; chỉ dựng một bộ khối. Lỗi một vùng không bỏ các khoang khác.`;
  if (product?.plan_components) {
    const proof = product.plan_components;
    byId('explanation').textContent += `\nMẶT CẮT BẰNG NHIỀU NHÁNH · Dấu cắt ngang · ${proof.closed_bays} khoang kín và ${proof.pending_bays} khoang giữ box tạm; chiều cao từng khoang còn chờ kiểm tra.`;
    for (const g of proof.front_matches) byId('explanation').textContent += `\nNhánh ${g.axis} → ${g.front_id || 'chưa phân biệt mặt đứng'}: ${g.matched_modules} đoạn khớp; module/phần chiếu ${number(g.module_width_sum_mm)} + phụ ${number(g.auxiliary_width_sum_mm)} = ${number(g.sum_with_auxiliary_mm)} mm; phần tủ trên mặt đứng ${number(g.front_furniture_width_mm)} mm; lệch ${number(g.unexplained_front_mm)} mm. Khung nguồn ${number(g.front_width_mm)} mm giữ riêng.`;
    for (const part of product.modules || []) {
      const ev = part.plan_component_evidence;
      if (!ev) continue;
      const nearest = [...(ev.sections || [])].sort((a,b) => Math.abs(a.difference_mm)-Math.abs(b.difference_mm))[0];
      byId('explanation').textContent += nearest ? `\n${part.name}: mặt cắt ${nearest.view_id} đo sâu ${number(nearest.depth_mm)} mm; chênh ${number(nearest.difference_mm)} mm. Giữ kích thước CAD gốc.` : `\n${part.name}: chưa có mặt cắt xác nhận chiều sâu này.`;
    }
  }
  if (product?.plan_engine === 'oy-stock-sweep-v1') {
    const scan = product.geometry_pipeline?.oy_sweep;
    const indexed = product.plan_evidence?.panel_index;
    byId('explanation').textContent += indexed ? '\nBỘ QUÉT ĐA HƯỚNG · Tìm cặp biên qua chỉ mục độ dày · Không gọi AI' : '\nBỘ QUÉT OY · Hình học trực tiếp · Không gọi AI';
    if (indexed) byId('explanation').textContent += `\n${indexed.directions} nhóm hướng · ${indexed.faces} vị trí biên · ${indexed.offset_probes} lượt tra độ dày · ${indexed.candidate_pairs} cặp ứng viên.`;
    const directional = product.geometry_pipeline?.directional_layout;
    if (directional) byId('explanation').textContent += `\nGhép các nhánh theo hướng tấm: ${directional.modules} module · ${directional.auxiliary || 0} khối phụ. Giữ khoảng hở giữa các thùng, không bao toàn bộ bằng một box.`;
    if (scan) {
      const names = {module_boundary: 'chia hai module', outer_plate_or_auxiliary: 'tấm ngoài/nẹp', unassigned: 'cần đối chiếu'};
      byId('explanation').textContent += `\n${scan.vertical_lines} đường OY · ${scan.walls?.length || 0} vách ứng viên · ${scan.depth_groups?.length || 0} nhóm khoảng Y.`;
      for (const seam of scan.joins || []) byId('explanation').textContent += `\n18 + 18 tại X=${number(seam.x)}: ${names[seam.role] || seam.role}.`;
    }
    const labels = {stock_scan: 'Quét độ dày', depth_and_seams: 'Nhóm Y / chia khoang', footprints_arcs_trims: 'Biên / bo / nẹp', evidence: 'Nhận tấm đa hướng', directional_layout: 'Chia khoang theo hướng tấm', exact_feedback: 'Đối chiếu box đúng', total_plan: 'Tổng đọc mặt bằng'};
    if (product.processing_from_cache) byId('explanation').textContent += '\nNhận tấm / chia khoang: dùng kết quả cache, không chạy lại các bước đã tính.';
    else for (const [key, seconds] of Object.entries(product.processing_times || {})) byId('explanation').textContent += `\n${labels[key] || key}: ${number(seconds)} giây.`;
    if (product.current_replay_seconds != null) byId('explanation').textContent += `\nĐối chiếu mẫu đúng / chuẩn bị nét CAD lượt này: ${number(product.current_replay_seconds)} giây.`;
    const nativeLabels = {validation: 'Kiểm tra trước dựng', source_watch: 'Đối chiếu nguồn', groups: 'Tạo Group', skp_snapshot: 'Lưu SKP thư viện', total_to_snapshot: 'Tổng đến khi lưu SKP'};
    for (const [key, seconds] of Object.entries(product.native_times || {})) byId('explanation').textContent += `\nSketchUp · ${nativeLabels[key] || key}: ${number(seconds)} giây.`;
  }
  if (product?.plan_engine === 'section-first-v1') {
    const capture = product.scan_capture;
    if (capture) {
      byId('explanation').textContent += `\nQUÉT KẾT HỢP · ${capture.view_titles} tiêu đề hình chiếu · ${capture.section_markers} dấu cắt đọc được. Khối đặt tại từng mặt bằng nguồn.`;
      if (capture.capture_seconds != null) byId('explanation').textContent += `\nThu nét/chữ/ký hiệu: ${number(capture.capture_seconds)} giây.`;
      byId('explanation').textContent += `\nNhận ký hiệu: ${number(capture.seconds)} giây.`;
      for (const issue of capture.issues || []) byId('explanation').textContent += `\nVùng quét cần kiểm tra: ${issue}`;
    }
    const stage = product.geometry_pipeline?.horizontal || {};
    const height = product.product_height;
    const heightMessage = height?.status === 'measured' && product.height_pending === false
      ? `Cao độ SP Z${number(height.low_mm)}..${number(height.high_mm)} mm · cao ${number(height.high_mm - height.low_mm)} mm · chia tầng còn chờ kiểm tra`
      : stage.status === 'user_confirmed' ? 'Kết quả người dùng xác nhận' : stage.status === 'measured' ? 'Đã đo chiều cao' : 'Còn phần cao tạm 1600 mm';
    byId('explanation').textContent += `\nMẶT ĐỨNG · Ưu tiên mặt cắt đứng · ${heightMessage}`;
    if (height?.status === 'pending') byId('explanation').textContent += `\nChiều cao SP: ${height.issue}`;
    byId('explanation').textContent += `\nLiên kết dấu cắt / chia tầng: ${number(stage.seconds || 0)} giây.`;
    for (const issue of stage.issues || []) byId('explanation').textContent += `\nCần kiểm tra: ${issue}`;
    for (const module of stage.modules || []) for (const link of module.links || []) {
      byId('explanation').textContent += `\n${module.plan_module_id}: dấu ${link.marker_handle}, mặt cắt ${link.section_id}, vị trí X nguồn ${number(link.source_x_mm)} mm; ${link.tiers.length} tầng; ${link.checks.length} mặt đứng kiểm tra.`;
    }
    if (stage.registration) {
      byId('explanation').textContent += `\nGHÉP HÌNH HỌC · Mặt đứng ${stage.registration.front_id} · Mặt cắt ${stage.registration.section_id} · ${stage.registration.front_checks.length} mặt đứng đối chiếu. Không tự đặt mã dấu cắt.`;
      for (const item of stage.modules || []) byId('explanation').textContent += `\n${item.plan_module_id}: ${item.intervals_mm.map(([lo,hi]) => `Z${number(lo)} → ${number(hi)} mm`).join('; ')}.`;
    }
    const native = product.native_times || {};
    for (const [key, seconds] of Object.entries(native)) byId('explanation').textContent += `\nSketchUp · ${key}: ${number(seconds)} giây.`;
  }
  if (product?.plan_reference?.scope === 'all_views') {
    const views = product.plan_reference.views;
    byId('explanation').textContent += '\nCAD đi kèm: giữ đủ nét của SP, kể cả khi chưa dựng được chiều cao. Các hình là Group rời. Mặt bằng XOY; mặt đứng XOZ; mặt cắt đứng và mặt bên YOZ dùng MH_DWG2. Mặt đứng có cánh: MH_DWG1; mặt đứng bỏ cánh, mặt cắt bằng và CAD khác: MH_DWG.';
    for (const view of views) {
      byId('explanation').textContent += `\n${view.id} · ${view.title || 'Chưa phân loại'}: ${view.alignment === 'unresolved' ? 'giữ bản vẽ phẳng, chưa đủ căn cứ căn vị trí' : view.alignment === 'front_pending_alignment' ? 'XOZ · chưa ghép được vị trí ngang với mặt bằng' : view.alignment === 'section_inspection' ? `${view.plane === 'YZ' ? 'YOZ' : 'XOZ'} · mặt cắt theo dấu cắt/biên SP${view.datum_proven ? ', cùng mốc cao độ theo hình học' : ', cần kiểm tra mốc cao độ'}` : `${view.plane} · căn theo hình học nguồn`}.`;
      if (view.section_position) byId('explanation').textContent += view.section_position.basis === 'cut_marker'
        ? ` Dấu cắt ${view.section_position.marker_handle}: X${number(view.display_x_mm)} mm; ${view.direction_basis === 'symbol_arrows' ? 'hướng theo mũi tên ký hiệu' : view.direction_basis === 'panel_geometry' ? 'hướng theo cặp ván' : 'chưa rõ hướng nhìn'}.`
        : ' Chưa có dấu cắt liên kết: đặt tại biên khung bao.';
      if (view.registration_issue) byId('explanation').textContent += ` Cần kiểm tra: ${view.registration_issue}`;
      for (const [axis, proof] of Object.entries(view.axis_registration || {})) {
        const links = proof.path || [proof];
        const count = links.reduce((n, p) => Math.min(n, p.matched_pairs || 0), Infinity);
        const ratio = links.reduce((n, p) => Math.min(n, p.coverage ?? 1), 1);
        byId('explanation').textContent += proof.status === 'proven'
          ? ` Trục ${axis}: ${links.length ? `${Number.isFinite(count) ? count : 0} vị trí cặp ván/nét khớp (${number(ratio * 100)}%), ${links.length} bước ghép` : 'mặt bằng gốc'}${links.some(p => p.source_slice !== undefined || p.target_slice !== undefined) ? ', xét tại cao độ/vị trí cắt' : ''}.`
          : ` Trục ${axis} chưa xác nhận: ${proof.reason || 'Thiếu chuỗi ván đối chiếu'}${proof.candidates?.length > 1 ? ` (${proof.candidates.length} vị trí cùng khớp)` : ''}.`;
        if (proof.warning) byId('explanation').textContent += ` Cảnh báo: ${proof.warning}`;
        for (const link of links) if (link.height_support) byId('explanation').textContent += ` Đối chiếu ${link.height_support} lát ngang tại Z${link.height_checks.map(c => number(c.height_mm)).join(' / ')} mm; phần mặt đứng bị lược bỏ không dùng làm mép căn.`;
      }
      if (product.plan_reference.display_mode === 'front_overlay' && ['front_open','front_check'].includes(view.role)) byId('explanation').textContent += ' Mặt đứng có cánh/bỏ cánh chồng theo tọa độ ghép trên XOZ; giữ Group và tag riêng.';
      else if (view.display_placement) byId('explanation').textContent += ' Mặt đứng bỏ cánh đặt riêng trên XOZ, bên phải mặt đứng, khoảng trống 500 mm.';
      if (view.depth_alignment) byId('explanation').textContent += view.depth_alignment.basis === 'provisional_source_min_y'
        ? ' Mốc Y tạm: chưa đủ cặp cạnh ván kín để loại nét bối cảnh.'
        : ` Mốc Y${number(view.display_y_mm)} mm từ cặp cạnh ván đạt độ dày chuẩn${view.depth_alignment.basis === 'cabinet_min_y' ? '; căn Y thấp nhất của tủ' : ' tại vị trí mặt cắt'}; khung CAD đầy đủ không dùng làm mốc chiều sâu.`;
      if (view.level) byId('explanation').textContent += view.level.placement_basis === 'single_plan_zero'
        ? ` Mặt bằng duy nhất đặt Z0 mm${view.level.status === 'measured' ? `; cao độ cắt nguồn ${number(view.level.level_mm)} mm được giữ để đối chiếu` : '; chưa xác định cao độ cắt nguồn'}.`
        : view.level.status === 'measured'
        ? ` Cao độ Z${number(view.z_mm)} mm từ dấu cắt ngang; các mặt cắt bằng trùng X/Y của SP.`
        : ` Cao độ tạm Z${number(view.z_mm)} mm${view.level.status === 'provisional' ? ', xếp cách 1.000 mm, trùng X/Y; không phải cao độ đo được' : ''}: ${view.level.issue}`;
    }
    for (const copy of product.plan_reference.display_copies || []) byId('explanation').textContent += `\n${copy.title} · XOZ: thêm bản xem cạnh mặt đứng, khoảng trống 500 mm; giữ bản YOZ tại vị trí đối chiếu mặt bằng. Tag MH_DWG2.`;
  } else if (product?.plan_reference?.level) {
    const level = product.plan_reference.level;
    byId('explanation').textContent += level.placement_basis === 'single_plan_zero'
      ? `\nMặt bằng duy nhất đặt Z0 mm${level.status === 'measured' ? `; cao độ cắt nguồn ${number(level.level_mm)} mm được giữ để đối chiếu` : '; chưa xác định cao độ cắt nguồn'}.`
      : level.status === 'measured'
      ? `\nMặt cắt bằng: Z${number(level.level_mm)} mm từ dấu cắt ngang, trùng X/Y của SP.`
      : `\nMặt cắt bằng: Z tạm ${number(product.plan_reference.z_mm)} mm${level.status === 'provisional' ? ', xếp cách 1.000 mm, trùng X/Y; không phải cao độ đo được' : ''}. ${level.issue}`;
  }
  if (product?.source_cache) {
    const cache = product.source_cache, modes = {analysis:'Cache kết quả', memory:'Chỉ mục nguồn trong RAM', disk:'Chỉ mục nguồn trên đĩa', extracted:'Nạp nguồn lần đầu / phiên bản mới'};
    byId('explanation').textContent += `\nNguồn CAD: ${modes[cache.mode] || cache.mode}.`;
    for (const [key,label] of Object.entries({revision_check:'Kiểm tra phiên bản file', index_load:'Nạp / mở chỉ mục CAD', spatial_selection:'Lấy vùng SP', total_source:'Nguồn và phân tích yêu cầu'})) if (cache[key] != null) byId('explanation').textContent += `\n${label}: ${number(cache[key])} giây.`;
  }
  if (product?.worker_timing) byId('explanation').textContent += `\nWorker thường trực · lượt ${product.worker_timing.job_number} · xử lý ${number(product.worker_timing.compute_seconds)} giây · nhận kết quả ${number(product.worker_timing.roundtrip_seconds)} giây.`;
  if (product?.plan_evidence) {
    const measured = product.plan_evidence;
    const stocks = Object.entries(measured.stock_counts || {}).filter(([, count]) => count).map(([mm, count]) => `${mm} mm: ${count}`);
    byId('explanation').textContent += `\nỨng viên tấm từ hình học: ${stocks.join('; ') || 'Chưa có cặp biên đủ bằng chứng'}. ${(measured.arcs || []).length} cung tròn từ chuỗi cạnh CAD.\nKhoảng cách chỉ là bằng chứng nhận dạng tấm; không tự coi mọi tấm là ranh giới module. Ván 36 mm cần đối chiếu đường tiếp giáp 18 + 18.`;
  }
  if (product?.learning) {
    const learned = product.learning;
    const heightNote = product.product_height?.status === 'measured' ? 'chiều cao theo cao độ SP' : product.build_stages?.elevation ? 'chiều cao kiểm tra riêng theo CAD' : 'cao tạm 1600 mm';
    const mode = {user_confirmed: 'Bố trí do người dùng xác nhận', geometry: learned.message, local_ai: learned.message, plan_rule: learned.message || 'Quy tắc tự học đã kiểm thử · đo lại từ CAD mới', plan_exact: `Bố trí mặt bằng từ box đã xác nhận cùng hình học · ${heightNote}`, staged: learned.message || `Mặt bằng · ${heightNote} · chưa có mẫu đúng khớp hình học`, exact: 'Mẫu có cùng hình học', similar: 'Suy rộng từ mẫu cùng cấu tạo', review: 'Kinh nghiệm cần kiểm tra', unmatched: 'Chưa có mẫu phù hợp'}[learned.mode];
    byId('explanation').textContent += `\n${mode || learned.mode}${learned.source_code ? ` · mẫu ${learned.source_code}` : ''}.`;
    if (learned.mode === 'similar') byId('explanation').textContent += '\nCác mặt khối đã được đo lại từ CAD mới và đối chiếu mặt bằng/mặt cắt; giữ độ dày ván. Phần phụ giữ riêng.';
    for (const issue of learned.issues || []) {
      byId('explanation').textContent += `\n${issue.source_code ? `${issue.source_code}: ` : ''}${issue.message}`;
      const missingNames = {top_crown_100mm: 'nẹp nóc 100 mm', right_hidden_arch_area: 'phần vòm nét khuất bên phải'};
      if (issue.excluded?.length) byId('explanation').textContent += ` Phần chưa có: ${issue.excluded.map(key => missingNames[key] || key).join(', ')}.`;
    }
  }
  if (product?.local_ai) byId('explanation').textContent += `\nAI local: ${product.local_ai.message}${product.local_ai.seconds !== undefined ? ' · ' + number(product.local_ai.seconds) + ' giây' : ''}${product.local_ai.cached ? ' · dùng kết quả đã lưu' : ''}${product.local_ai.reason ? '\n' + product.local_ai.reason : ''}`;
  if (product?.local_ai?.workflow === 'ai_plan_search_v2') {
    const ai = product.local_ai;
    const samples = (ai.selected_samples || []).map(s => s.code?.startsWith('SCAN-') ? 'Vùng quét ' + s.event.slice(0, 8) : s.code || s.event.slice(0, 8));
    byId('explanation').textContent += `\nMẫu AI chọn: ${samples.join(', ') || 'Không có mẫu phù hợp'} · ${ai.rounds || 0} lượt AI.`;
    for (const step of ai.trace || []) byId('explanation').textContent += `\n${step.message}`;
    if (ai.final_check?.passed) byId('explanation').textContent += '\nĐã kiểm tra hình học cuối; dựng tự động, không yêu cầu mẫu giống 100%.';
    for (const item of ai.rejected || []) byId('explanation').textContent += `\nPhương án bị loại: ${item.reason}`;
  }
  if (product?.manual_boxes) byId('explanation').textContent += `\nĐã nhận ${(product.modules || []).length} module và ${(product.trim_parts || []).length} phần phụ từ các box đúng.`;
  if (product?.geometry_pipeline?.vertical && !product?.manual_boxes && product?.learning?.mode !== 'local_ai') {
    const pipeline = product.geometry_pipeline;
    if (pipeline.mode !== 'plan_and_elevation') byId('explanation').textContent += pipeline.mode === 'plan_only'
      ? `\n${pipeline.vertical.columns.length} khoang từ mặt bằng; cao tạm 1600 mm. Mặt đứng đang tắt.`
      : `\nBước 1: ${pipeline.vertical.columns.length} khoang dọc từ mặt bằng. Bước 2: ${(pipeline.horizontal?.modules || []).length} ${product.status === 'ready' ? 'module đã xác định' : 'khối ứng viên'} từ mặt đứng bỏ cánh. Nét đứt ?M là ứng viên cần kiểm tra; nét đỏ là phần chưa ghép.`;
  }
  for (const part of product?.trim_parts || []) {
      if (part.rule === 'confirmed-section-top-trim-box-v1') { byId('explanation').textContent += `\n${part.name}: ${part.size.map(number).join(' × ')} mm; một khối theo xác nhận của người dùng, giữ bằng chứng hai tấm chữ L trên mặt cắt.`; continue; }
      if (part.rule === 'measured-section-top-trim-v1') { byId('explanation').textContent += `\n${part.name}: ${part.size.map(number).join(' × ')} mm; độ dày từ cặp biên song song khép hai đầu trên mặt cắt.`; continue; }
      if (part.rule === 'plan-measured-end-panel-v1') { byId('explanation').textContent += `\n${part.name}: ${part.size.map(number).join(' × ')} mm; giữ chiều sâu riêng đo từ CAD, không kéo sâu module bên trong.`; continue; }
      if (part.rule === 'measured-shared-rail-v1') { byId('explanation').textContent += `\n${part.id}: thanh chung ${part.size.map(number).join(' × ')} mm qua khoảng hở; giữ riêng, không tính là module tủ.`; continue; }
      if (part.rule === 'plan-short-trim-full-depth-v1') { byId('explanation').textContent += `\n${part.name}: nẹp CAD sâu 50 mm, khối phụ dựng sâu ${number(part.size[1])} mm bằng tủ; cao ${number(part.size[2])} mm${part.height_source === 'provisional_default' ? ' (tạm)' : ''}.`; continue; }
      if (part.role === 'common_base') { byId('explanation').textContent += `\n${part.name}: ${part.size.map(number).join(' × ')} mm; khung đối chiếu chân đế chung.`; continue; }
      if (part.role === 'cad_envelope_reference') { byId('explanation').textContent += '\nĐường bao nguồn CAD giữ dạng tham chiếu, không tính là vật liệu/module.'; continue; }
    byId('explanation').textContent += `\nNẹp ${part.owner_module_id ? `phụ ${part.owner_module_id} (${part.side === 'left' ? 'trái' : 'phải'})` : 'riêng'}: mặt nhìn ${number(part.face_width_mm)} mm, ván ${number(part.stock_thickness_mm)} mm; không tính là module.`;
  }
    if ([...(product?.modules || []), ...(product?.trim_parts || [])].some(p => p.plan_profile?.segments.some(s => s.type === 'arc'))) byId('explanation').textContent += '\nKhối bo giữ tâm, bán kính và góc quét; dựng bằng ArcCurve. Chiều cao theo giai đoạn dựng; phần chưa đo được ghi rõ là tạm.';
  if (product?.panel_parts?.length) byId('explanation').textContent += `\n${product.panel_parts.length} tấm/vách/nẹp dựng riêng theo hình học, giữ liên kết cấu kiện; không tính vào số module tủ.`;
  byId('modules').replaceChildren();
  state.current_modules.forEach((mod) => {
    const row = document.createElement('tr'); row.className = 'pick'; cell(row, mod.name || mod.id);
    cell(row, mod.size.map(number).join(' × ')); cell(row, mod.origin.map(number).join(' / '));
    row.addEventListener('click', () => send('select_module', {id: mod.entity_id})); byId('modules').appendChild(row);
  });
};
const requestManualAcceptance = (activityKey = activeActivityKey) => {
  if (manualRequest) return;
  manualActivityKey = activityKey;
  manualRequest = `${Date.now()}-${++manualSequence}`;
  manualStarted = Date.now(); manualTimedOut = false; manualResult = null;
  renderManualFeedback();
  manualPoll = setInterval(pollManualAcceptance, 2000);
  manualDeadline = setTimeout(() => { manualTimedOut = true; renderManualFeedback(); pollManualAcceptance(); }, 8000);
  try {
    if (typeof window.sketchup?.request !== 'function') throw new Error('Không kết nối được với SketchUp. Đóng và mở lại Quản lý.');
    send('accept_manual_boxes', {request_id: manualRequest, session_id: manualView.correction?.id,
      ...(manualActivityKey ? {activity_key: manualActivityKey} : {})});
  } catch (error) { window.receiveManualAcceptance({status: 'error', request_id: manualRequest, message: error.message}); }
};
document.querySelectorAll('[data-action]').forEach((button) => button.addEventListener('click', () => {
  if (button.dataset.action === 'refresh' && manualRequest) { pollManualAcceptance(); return; }
  if (button.dataset.action === 'accept_manual_boxes') requestManualAcceptance();
  else send(button.dataset.action);
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
byId('import-plan-reference').addEventListener('change', () => send('save_settings', {settings: stageSettings()}));
byId('begin').addEventListener('click', () => send('begin_correction', {reason: byId('reason').value}));
byId('fit').addEventListener('click', () => viewer.fit());
byId('check-view').addEventListener('click', () => {
  viewer.setCheckView(!viewer.checkView);
  byId('check-view').setAttribute('aria-pressed', String(viewer.checkView));
});
send('ready');

byId('ai-enabled').addEventListener('change', () => send('save_settings', {settings: stageSettings()}));

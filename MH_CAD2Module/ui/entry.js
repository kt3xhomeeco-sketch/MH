'use strict';
const byId = id => document.getElementById(id);
const send = (action, payload = {}) => window.sketchup?.request(JSON.stringify({action, ...payload}));
let previousList = null, current = {}, pending = null, poll = null;
const normalise = value => value.split(/([\r\n,;]+)/).map(v => /^[\r\n,;]+$/.test(v) ? v : /^\d+$/.test(v.trim()) ? `SP${v.trim().padStart(2, '0')}` : v.trim()).join('');
window.receiveProgress = () => {};
const renderActions = () => {
  const busy = Boolean(current.busy), correcting = Boolean(current.correction?.manual);
  byId('build').disabled = busy || correcting || Boolean(pending);
  byId('select-result').disabled = busy || !current.entry_target || Boolean(pending);
  byId('wrong-result').disabled = busy || !current.entry_target || Boolean(current.correction) || Boolean(pending);
  byId('accept-result').disabled = busy || !correcting || Boolean(pending);
  byId('accept-result').textContent = pending ? 'Đang lưu…' : 'Kết quả đúng';
  byId('cancel-result').disabled = busy || !correcting || Boolean(pending);
};
window.receiveManualAcceptance = result => {
  if (!pending || result.request_id !== pending) return;
  if (result.status === 'processing' || result.status === 'unknown') return;
  clearInterval(poll);poll = null;pending = null;renderActions();
  send('ready');
};
window.receive = state => {
  current = state;
  const selection = state.entry_mode === 'selection';
  byId('product-start-label').textContent = selection ? 'Mã sản phẩm' : 'Mã bắt đầu';
  byId('product-end-field').classList.toggle('hidden', selection);
  const remembered = JSON.stringify([state.last_products || '', state.last_product_end || '']);
  if (remembered !== previousList) {
    byId('product-input').value = state.last_products || '';
    byId('product-end').value = state.last_product_end || '';
    previousList = remembered;
  }
  if (pending && state.manual_acceptance) window.receiveManualAcceptance(state.manual_acceptance);
  renderActions();
};
for (const id of ['product-input','product-end']) byId(id).addEventListener('blur', () => { byId(id).value = normalise(byId(id).value); });
document.addEventListener('keydown', event => {
  if (event.key !== 'Enter' || event.isComposing || event.shiftKey || event.ctrlKey || event.altKey || event.metaKey) return;
  event.preventDefault();
  if (!event.repeat && !byId('build').disabled) byId('build-form').requestSubmit(byId('build'));
});
byId('build-form').addEventListener('submit', event => {
  event.preventDefault();
  if (byId('build').disabled) return;
  byId('product-input').value = normalise(byId('product-input').value);
  byId('product-end').value = normalise(byId('product-end').value);
  const payload = {products: byId('product-input').value};
  const end = byId('product-end').value.trim();
  if (!byId('product-end-field').classList.contains('hidden') && end) payload.product_end = end;
  send('build', payload);
});
for (const [id,operation] of [['select-result','select_activity'],['wrong-result','wrong'],['cancel-result','cancel_manual_boxes']]) {
  byId(id).addEventListener('click', () => send('entry_workflow', {operation}));
}
byId('accept-result').addEventListener('click', () => {
  if (pending || !current.correction?.manual) return;
  pending = crypto.randomUUID();renderActions();
  send('entry_workflow', {operation:'accept_manual_boxes', request_id:pending, session_id:current.correction.id});
  poll = setInterval(() => { if (pending) send('manual_acceptance_status',{request_id:pending}); },1000);
});
byId('manage').addEventListener('click', () => send('manager'));
window.addEventListener('focus', () => send('ready'));
document.body.addEventListener('pointerenter', () => send('ready'));
send('ready');

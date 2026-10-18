'use strict';
const send = (action, payload = {}) => window.sketchup?.request(JSON.stringify({action, ...payload}));
let previousList = null;
window.receive = (state) => {
  document.querySelector('label').textContent = state.entry_mode === 'selection' ? 'Mã SP — dựng ngay tại CAD đang quét' : 'Tên hoặc mã sản phẩm';
  document.getElementById('build').disabled = state.busy;
  document.getElementById('message').textContent = state.message || 'Dùng nguồn CAD đã lưu trong Quản lý.';
  if (state.last_products && state.last_products !== previousList) {
    document.getElementById('product-input').value = state.last_products;
    previousList = state.last_products;
  }
};
document.getElementById('build-form').addEventListener('submit', (event) => {
  event.preventDefault();
  send('build', {products: document.getElementById('product-input').value});
});
document.getElementById('manage').addEventListener('click', () => send('manager'));
send('ready');

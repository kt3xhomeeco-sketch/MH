// MH Registry — thu gọn/mở rộng các section bảng trong từng tab.
// Bấm tiêu đề section (h3.sub hoặc .card > .panel-head) để ẩn/hiện nội dung
// bên dưới, chỉ còn lại 1 dòng tiêu đề. Trạng thái lưu vào localStorage.
(function () {
  'use strict';

  var LS_KEY = 'mh_registry_collapse';

  function loadState() {
    try { return JSON.parse(localStorage.getItem(LS_KEY) || '{}') || {}; }
    catch (e) { return {}; }
  }
  function saveState(state) {
    try { localStorage.setItem(LS_KEY, JSON.stringify(state)); } catch (e) {}
  }
  var STATE = loadState();

  function headLabel(el) {
    // Lấy text tiêu đề, bỏ phần nút (+ dòng...) để key ổn định.
    var clone = el.cloneNode(true);
    clone.querySelectorAll('button, .btn, input, select').forEach(function (n) { n.remove(); });
    return clone.textContent.replace(/\s+/g, ' ').trim();
  }

  function wire(header, body, key) {
    if (!body.length || header.__mhWired) return;
    header.__mhWired = true;
    header.classList.add('mh-coll-head');

    var chev = document.createElement('span');
    chev.className = 'mh-coll-chev';
    chev.textContent = '▾';
    header.insertBefore(chev, header.firstChild);

    function apply(collapsed) {
      for (var i = 0; i < body.length; i++) body[i].style.display = collapsed ? 'none' : '';
      header.classList.toggle('mh-collapsed', collapsed);
    }

    if (STATE[key] === true) apply(true);

    header.addEventListener('click', function (e) {
      // Đừng thu gọn khi bấm vào nút/ô nhập trong tiêu đề.
      if (e.target.closest('button, .btn, input, select, textarea, a, .mh-card-drag-handle')) return;
      var collapsed = !header.classList.contains('mh-collapsed');
      apply(collapsed);
      STATE[key] = collapsed;
      saveState(STATE);
    });
  }

  function siblingsUntil(start, stopFn) {
    var body = [];
    var el = start.nextElementSibling;
    while (el && !stopFn(el)) { body.push(el); el = el.nextElementSibling; }
    return body;
  }

  function init() {
    var panels = document.querySelectorAll('.panel');
    for (var p = 0; p < panels.length; p++) {
      var panel = panels[p];
      var pname = panel.getAttribute('data-panel') || ('p' + p);

      // 1) Sub-section: <h3 class="sub"> ... </h3> + nội dung tới h3.sub kế tiếp.
      var subs = panel.querySelectorAll('h3.sub');
      for (var i = 0; i < subs.length; i++) {
        var h = subs[i];
        var body = siblingsUntil(h, function (el) { return el.matches('h3.sub'); });
        wire(h, body, pname + '|sub|' + headLabel(h));
      }

      // 2) Card sub-section: .card > .panel-head (có h3, không phải h2 tiêu đề panel)
      //    → nội dung = toàn bộ phần còn lại của card.
      var heads = panel.querySelectorAll('.card > .panel-head');
      for (var j = 0; j < heads.length; j++) {
        var ph = heads[j];
        if (!ph.querySelector('h3') || ph.querySelector('h2')) continue;
        var cbody = siblingsUntil(ph, function () { return false; });
        wire(ph, cbody, pname + '|card|' + headLabel(ph));
      }
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { setTimeout(init, 0); });
  } else {
    setTimeout(init, 0);
  }
})();

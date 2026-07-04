// Cho các vùng card 2 cột kéo chỉnh tỉ lệ trái/phải, không bị khóa 50/50.
(function () {
  'use strict';

  var SPLITS = [
    {
      gridId: 'superimpCardList',
      storageKey: 'mh_registry_superimp_split_ratio'
    },
    {
      gridId: 'materialAssignCardGrid',
      storageKey: 'mh_registry_material_assign_split_ratio'
    }
  ];

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
  }

  function readRatio(storageKey) {
    var number = parseFloat(localStorage.getItem(storageKey) || '50');
    return isFinite(number) ? clamp(number, 20, 80) : 50;
  }

  function applyRatio(grid, ratio) {
    ratio = clamp(ratio, 20, 80);
    grid.style.setProperty('--mh-left-col', ratio + 'fr');
    grid.style.setProperty('--mh-right-col', (100 - ratio) + 'fr');
    grid.style.setProperty('--mh-split-left', ratio + '%');
  }

  function gridHasHalfPair(grid) {
    var cards = Array.prototype.slice.call(grid.children).filter(function (node) {
      return node.classList && node.classList.contains('mh-card-half');
    });
    return cards.length >= 2;
  }

  function updateHandleVisibility(grid, handle) {
    handle.style.display = gridHasHalfPair(grid) ? '' : 'none';
  }

  function initSplit(def) {
    var grid = document.getElementById(def.gridId);
    if (!grid || grid.__mhSplitResizeWired) return;
    grid.__mhSplitResizeWired = true;

    var ratio = readRatio(def.storageKey);
    applyRatio(grid, ratio);
    grid.classList.add('mh-resizable-split-grid');

    var handle = document.createElement('div');
    handle.className = 'mh-grid-resizer';
    handle.title = 'Kéo để chỉnh tỉ lệ 2 cột';
    grid.appendChild(handle);
    updateHandleVisibility(grid, handle);

    var dragging = false;

    function setFromClientX(clientX, save) {
      var box = grid.getBoundingClientRect();
      if (!box.width) return;
      ratio = clamp(((clientX - box.left) / box.width) * 100, 20, 80);
      applyRatio(grid, ratio);
      if (save) localStorage.setItem(def.storageKey, String(Math.round(ratio * 10) / 10));
    }

    handle.addEventListener('mousedown', function (event) {
      dragging = true;
      grid.classList.add('mh-resizing-split');
      event.preventDefault();
      event.stopPropagation();
    });

    document.addEventListener('mousemove', function (event) {
      if (!dragging) return;
      setFromClientX(event.clientX, false);
    });

    document.addEventListener('mouseup', function (event) {
      if (!dragging) return;
      dragging = false;
      grid.classList.remove('mh-resizing-split');
      setFromClientX(event.clientX, true);
      updateHandleVisibility(grid, handle);
    });

    var observer = new MutationObserver(function () {
      updateHandleVisibility(grid, handle);
    });
    observer.observe(grid, { childList: true, attributes: true, subtree: true, attributeFilter: ['class'] });

    window.addEventListener('resize', function () {
      applyRatio(grid, ratio);
      updateHandleVisibility(grid, handle);
    });
  }

  function init() {
    SPLITS.forEach(initSplit);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();

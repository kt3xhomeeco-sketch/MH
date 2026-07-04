// Material Assign — kéo thả card, thả cạnh nhau để ghép hai cột.
(function () {
  'use strict';

  var LS_KEY = 'mh_registry_material_assign_card_layout';

  function cards(grid) {
    return Array.prototype.slice.call(grid.querySelectorAll('.material-assign-card[data-ma-card-id]'));
  }

  function loadLayout() {
    try {
      var data = JSON.parse(localStorage.getItem(LS_KEY) || '[]');
      return Array.isArray(data) ? data : [];
    } catch (e) {
      return [];
    }
  }

  function saveLayout(grid) {
    try {
      var data = cards(grid).map(function (card) {
        return {
          id: card.getAttribute('data-ma-card-id'),
          width: card.classList.contains('mh-card-half') ? 'half' : 'full'
        };
      });
      localStorage.setItem(LS_KEY, JSON.stringify(data));
    } catch (e) {}
  }

  function setWidth(card, width) {
    card.classList.toggle('mh-card-half', width === 'half');
    card.classList.toggle('mh-card-full', width !== 'half');
  }

  function normalizePairs(grid) {
    var list = cards(grid);
    for (var i = 0; i < list.length; i++) {
      if (!list[i].classList.contains('mh-card-half')) continue;
      if (i + 1 < list.length && list[i + 1].classList.contains('mh-card-half')) {
        i++;
      } else {
        setWidth(list[i], 'full');
      }
    }
  }

  function applySavedLayout(grid) {
    var saved = loadLayout();
    if (!saved.length) return;
    var byId = {};
    cards(grid).forEach(function (card) {
      byId[card.getAttribute('data-ma-card-id')] = card;
    });
    saved.forEach(function (entry) {
      var card = byId[entry.id];
      if (!card) return;
      setWidth(card, entry.width);
      grid.appendChild(card);
    });
    normalizePairs(grid);
  }

  function clearDropState(grid) {
    cards(grid).forEach(function (card) {
      card.classList.remove('mh-drop-left', 'mh-drop-right', 'mh-drop-full');
    });
  }

  function dropMode(target, clientX) {
    var box = target.getBoundingClientRect();
    var ratio = box.width ? (clientX - box.left) / box.width : 0.5;
    if (ratio < 0.3) return 'left';
    if (ratio > 0.7) return 'right';
    return 'full';
  }

  function breakTargetPair(grid, target) {
    if (!target.classList.contains('mh-card-half')) return;
    var list = cards(grid);
    var index = list.indexOf(target);
    var pair = null;
    if (index > 0 && list[index - 1].classList.contains('mh-card-half')) pair = list[index - 1];
    else if (index + 1 < list.length && list[index + 1].classList.contains('mh-card-half')) pair = list[index + 1];
    if (pair) setWidth(pair, 'full');
    setWidth(target, 'full');
  }

  function init() {
    var grid = document.getElementById('materialAssignCardGrid');
    if (!grid || grid.__mhMaterialCardLayout) return;
    grid.__mhMaterialCardLayout = true;
    applySavedLayout(grid);

    var dragging = null;

    cards(grid).forEach(function (card) {
      var handle = card.querySelector('.mh-card-drag-handle');
      if (!handle) return;
      handle.setAttribute('draggable', 'true');
      handle.addEventListener('click', function (event) {
        event.preventDefault();
        event.stopPropagation();
      });
      handle.addEventListener('mousedown', function (event) {
        event.stopPropagation();
      });
      handle.addEventListener('dragstart', function (event) {
        dragging = card;
        card.classList.add('mh-dragging');
        if (event.dataTransfer) {
          event.dataTransfer.effectAllowed = 'move';
          event.dataTransfer.setData('text/plain', card.getAttribute('data-ma-card-id') || '');
        }
      });
      handle.addEventListener('dragend', function () {
        if (dragging) dragging.classList.remove('mh-dragging');
        dragging = null;
        clearDropState(grid);
        normalizePairs(grid);
        saveLayout(grid);
      });
    });

    grid.addEventListener('dragover', function (event) {
      if (!dragging) return;
      event.preventDefault();
      clearDropState(grid);
      var target = event.target.closest('.material-assign-card[data-ma-card-id]');
      if (!target || target === dragging) return;
      var mode = dropMode(target, event.clientX);
      target.classList.add(mode === 'left' ? 'mh-drop-left' : mode === 'right' ? 'mh-drop-right' : 'mh-drop-full');
    });

    grid.addEventListener('drop', function (event) {
      if (!dragging) return;
      event.preventDefault();
      var target = event.target.closest('.material-assign-card[data-ma-card-id]');
      breakTargetPair(grid, dragging);
      if (!target || target === dragging) {
        setWidth(dragging, 'full');
        grid.appendChild(dragging);
      } else {
        var mode = dropMode(target, event.clientX);
        if (mode === 'left' || mode === 'right') {
          breakTargetPair(grid, target);
          setWidth(dragging, 'half');
          setWidth(target, 'half');
          if (mode === 'left') grid.insertBefore(dragging, target);
          else grid.insertBefore(dragging, target.nextSibling);
        } else {
          setWidth(dragging, 'full');
          var box = target.getBoundingClientRect();
          var before = event.clientY < box.top + box.height / 2;
          grid.insertBefore(dragging, before ? target : target.nextSibling);
        }
      }
      clearDropState(grid);
      normalizePairs(grid);
      saveLayout(grid);
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();

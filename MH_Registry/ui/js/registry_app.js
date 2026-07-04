/* MH Registry -- UI logic (giao tiếp Ruby qua sketchup-bridge global `Bridge`) */
(function () {
  'use strict';

  var state = { global: {}, project: {}, config: {} };
  var maValidThicknessColumnCount = 3;
  var mcrTestColumns = null;
  var mcrTestBranches = null;
  var mcrTestDrag = null;
  var pcrColumns = null;
  var pcrDrag = null;

  // Định nghĩa cột cho từng bảng. scope: 'project' | 'global'.
  var TABLES = {
    products:           { scope: 'project', key: 'products',           cols: [['code','Mã SP'],['name','Tên'],['type','Loại']] },
    modules:            { scope: 'project', key: 'modules',             cols: [['sp','Mã SP'],['modul','Modul'],['prefix','Prefix'],['suffix','Suffix']] },
    materials:          { scope: 'global',  key: 'materials',           cols: [['code','Mã VL'],['name','Tên'],['supplier','NCC']] },
    thickness_mappings: { scope: 'global',  key: 'thickness_mappings',  cols: [['min','Min','num'],['max','Max','num'],['value','Giá trị']] },
    invalid_materials:  { scope: 'global',  key: 'invalid_materials',   cols: [['material','Vật liệu'],['thickness','Độ dày']] },
    superimp_import_list: { scope: 'config', key: 'superimp_import_list', cols: [['name','Tên'],['path','Path'],['shortcut','Shortcut'],['group','Group'],['swap_key','Swap key','num']] },
    ma_vat_lieu_global: { scope: 'config', key: 'ma_vat_lieu_global', cols: [['gia_tri','Giá trị nhập'],['gia_tri_map','Mã chuẩn']] },
    ma_thickness:       { scope: 'config', key: 'ma_thickness',       cols: [['min','Min','num'],['max','Max','num'],['value','Giá trị']] },
    ma_detail_aliases:  { scope: 'config', key: 'ma_detail_aliases',  cols: [['pattern','Pattern'],['target','Target']] },
    ma_tag_materials:   { scope: 'config', key: 'ma_tag_materials',   cols: [['tag_name','Tag'],['material_name','Material']] },
    ma_valid:           { scope: 'config', key: 'ma_valid',           cols: [['material','Material'],['thickness','Ghi nhớ độ dày'],['actual_thickness','Thực tế']] },
    ma_invalid:         { scope: 'config', key: 'ma_invalid',         cols: [['material','Material'],['thickness','Độ dày']] },
    ma_column_aliases:  { scope: 'config', key: 'ma_column_aliases',  cols: [['internal_name','Tên nội bộ'],['alias','Alias']] },
    // Render bằng giao diện thẻ (renderSurfaceFaceRules), không dùng grid cols.
    ma_surface_face_rules: { scope: 'config', key: 'ma_surface_face_rules' },
    material_profile_choices: { scope: 'config', key: 'material_profile_choices', groupBy: 'material_name', cols: [['material_name','Tên vật liệu'],['thickness_1','Độ dày 1'],['thickness_2','Độ dày 2']] },
    dc_thickness_bindings: { scope: 'config', key: 'dc_thickness_bindings', cols: [['match','Match (path / group:..)'],['label','Tên Custom'],['param_panel','Param panel'],['param_back','Param hậu'],['param_extra','Param thêm'],['modul_only','Đánh modul'],['unit','Unit'],['enabled','Bật']] },
    dc_manual_materials: { scope: 'config', key: 'dc_manual_materials', cols: [['material_code','Mã vật liệu'],['sort_order','Số thứ tự','num'],['enabled','Bật']] }
  };

  // ---- helpers ----------------------------------------------------------
  function $(id) { return document.getElementById(id); }
  function on(id, event, fn) {
    var node = $(id);
    if (node) node.addEventListener(event, fn);
  }
  function setValue(id, value) {
    var node = $(id);
    if (node) node.value = value;
  }
  function el(tag, attrs, children) {
    var e = document.createElement(tag);
    if (attrs) Object.keys(attrs).forEach(function (k) {
      if (k === 'text') e.textContent = attrs[k];
      else e.setAttribute(k, attrs[k]);
    });
    (children || []).forEach(function (c) { e.appendChild(c); });
    return e;
  }
  function status(msg, kind) {
    var s = $('status'); s.textContent = msg;
    var bar = s.parentNode; bar.className = 'statusbar' + (kind ? ' ' + kind : '');
  }
  function lines(text) {
    return (text || '').split('\n').map(function (s) { return s.trim(); }).filter(function (s) { return s.length; });
  }
  function escapeHtml(value) {
    return String(value || '').replace(/[&<>"']/g, function (ch) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch];
    });
  }
  function uniqueStrings(values) {
    var seen = {};
    var out = [];
    (values || []).forEach(function (value) {
      value = String(value || '').trim();
      if (!value || seen[value]) return;
      seen[value] = true;
      out.push(value);
    });
    return out;
  }

  function pcrValueText(entry) {
    if (entry && typeof entry === 'object') return String(entry.value || entry.text || '').trim();
    return String(entry || '').trim();
  }

  function pcrValueShortcut(entry) {
    if (entry && typeof entry === 'object') {
      var raw = entry.shortcut != null ? entry.shortcut : entry.sc;
      var num = parseInt(raw, 10);
      return isNaN(num) ? '' : String(num);
    }
    return '';
  }

  function normalizeProductCodeValueEntries(values, keepShortcut) {
    var seen = {};
    var out = [];
    (values || []).forEach(function (entry) {
      var value = pcrValueText(entry);
      if (!value || seen[value]) return;
      seen[value] = true;
      if (keepShortcut) {
        var shortcut = pcrValueShortcut(entry);
        out.push({ value: value, shortcut: shortcut === '' ? null : parseInt(shortcut, 10) });
      } else {
        out.push(value);
      }
    });
    return out;
  }

  var DEFAULT_MATERIAL_CODE_RULES = {
    segment_separator: '.',
    multi_separators: ['&'],
    uppercase: true,
    trim_segments: true,
    gloss_suffix_regex: '-(\\d+)\\z',
    single_segment_gloss_is_finish: true,
    paint_surface_token: 'SON',
    paint_code_regex: '\\A(?=.*[A-Z])(?=.*\\d)[A-Z0-9][A-Z0-9 _\\/.-]*\\z',
    surface_variant_regex: '\\.(?:1M|2M|1M-BCT|2M-BCT)\\z',
    surface_groups: {
      SON: {
        label: 'Sơn',
        members: ['SON'],
        tail_label: 'mã sơn - độ bóng',
        finish_kind: 'paint_code',
        finish_required: true,
        allow_gloss: true,
        allow_surface_variant: false,
        finish_pattern: '\\A(?=.*[A-Z])(?=.*\\d)[A-Z0-9][A-Z0-9 _\\/.-]*\\z'
      },
      LK: {
        label: 'Laminate',
        members: ['LK'],
        tail_label: 'mã vật liệu .1M/.2M',
        finish_kind: 'material_code',
        finish_required: false,
        allow_gloss: false,
        allow_surface_variant: true
      },
      VER: {
        label: 'Veneer',
        members: ['VER', 'VERKT', 'VERSOI', 'VERKTSOI'],
        tail_label: 'mã sơn .1M/.2M',
        finish_kind: 'paint_code',
        finish_required: false,
        allow_gloss: false,
        allow_surface_variant: true,
        finish_pattern: '\\A(?=.*[A-Z])(?=.*\\d)[A-Z0-9][A-Z0-9 _\\/.-]*\\z'
      },
      MS: {
        label: 'Melamine',
        members: ['MS'],
        tail_label: 'mã vật liệu',
        finish_kind: 'material_code',
        finish_required: false,
        allow_gloss: false,
        allow_surface_variant: false
      }
    },
    layers: [
      { key: 'chat_lieu', label: 'Chất liệu', required: true },
      { key: 'do_day', label: 'Độ dày', role: 'thickness', optional: true, omit_from_parent: true, pattern: '\\A\\d+(?:[,.]\\d+)?\\z' },
      { key: 'nha_cung_cap', label: 'Nhà cung cấp', optional: true },
      { key: 'be_mat', label: 'Bề mặt', optional: true },
      { key: 'finish_code', label: 'Mã hoàn thiện / mã sơn', role: 'finish', optional: true, capture_rest: true }
    ]
  };
  var MCR_NUMBER_PATTERN = '\\A\\d+(?:[,.]\\d+)?\\z';
  var MCR_GLOSS_DASH_NUMBER_PATTERN = '-(\\d+)\\z';
  var DEFAULT_PRODUCT_CODE_RULES = {
    segment_separator: '_',
    uppercase: true,
    trim_segments: true,
    layers: [
      { key: 'product_code', label: 'Mã sản phẩm', type: 'text_number', source: 'pattern', required: true, values: ['SP'] },
      { key: 'module_no', label: 'Số module', type: 'number', source: 'number', optional: true, values: ['number'] }
    ]
  };

  function materialCodeRules() {
    var rules = mergeMaterialRules(DEFAULT_MATERIAL_CODE_RULES, state.global.material_code_rules || {});
    if (!hasValidMaterialCodeLayers(rules.layers)) {
      rules.layers = cloneMaterialCodeLayers(DEFAULT_MATERIAL_CODE_RULES.layers);
    }
    return rules;
  }

  function productCodeRules() {
    var rules = mergeMaterialRules(DEFAULT_PRODUCT_CODE_RULES, state.global.product_code_rules || {});
    rules.layers = normalizeProductCodeLayers(rules.layers);
    if (!hasValidMaterialCodeLayers(rules.layers)) {
      rules.layers = cloneMaterialCodeLayers(DEFAULT_PRODUCT_CODE_RULES.layers);
    }
    return rules;
  }

  function mcrSeparatorFromRules(rules) {
    return rules && Object.prototype.hasOwnProperty.call(rules, 'segment_separator')
      ? String(rules.segment_separator || '').trim()
      : '.';
  }

  function mcrSeparatorFromInput(id, fallback) {
    var input = $(id);
    return input ? String(input.value || '').trim() : (fallback == null ? '.' : fallback);
  }

  function mcrSeparatorForParsing(sep) {
    return String(sep || '').trim() || '.';
  }

  function normalizeProductCodeLayers(layers) {
    layers = cloneMaterialCodeLayers(layers || []).filter(function (layer) {
      return String(layer.key || '').trim() !== 'suffix';
    });
    var hasProductCode = layers.some(function (layer) { return String(layer.key || '').trim() === 'product_code'; });
    if (hasProductCode) {
      return layers.map(function (layer) {
        if (String(layer.key || '').trim() !== 'product_code') return layer;
        var values = normalizeMcrTestValues(layer.values || (layer.value ? [layer.value] : []))
          .map(pcrFamilyToken)
          .filter(function (value) { return value; });
        values = uniqueStrings(values);
        if (!values.length) values = ['SP'];
        return Object.assign({}, layer, {
          type: layer.type === 'text' || layer.type === 'alnum_code' || !layer.type ? 'text_number' : layer.type,
          source: 'pattern',
          values: values
        });
      });
    }

    var prefixLayer = null;
    var productNoLayer = null;
    var rest = [];
    layers.forEach(function (layer) {
      var key = String(layer.key || '').trim();
      if (key === 'prefix') prefixLayer = layer;
      else if (key === 'product_no') productNoLayer = layer;
      else rest.push(layer);
    });
    if (!prefixLayer && !productNoLayer) return layers;

    var productValues = normalizeMcrTestValues((prefixLayer && prefixLayer.values) || []).map(pcrFamilyToken).filter(function (value) { return value; });
    productValues = uniqueStrings(productValues);
    if (!productValues.length) productValues = ['SP'];

    return [{
      key: 'product_code',
      label: 'Mã sản phẩm',
      type: 'text_number',
      source: 'pattern',
      required: true,
      optional: false,
      values: productValues,
      migrated_from: ['prefix', 'product_no']
    }].concat(rest);
  }

  function normalizeConfigSuffixRows(rows) {
    return normalizeProductCodeValueEntries((rows || []).map(function (item) {
      if (item && typeof item === 'object') {
        return { value: item.value || item.text || '', shortcut: item.shortcut };
      }
      var parts = String(item || '').split('|').map(function (part) { return part.trim(); });
      return { value: parts[0] || '', shortcut: parts[1] || null };
    }), true);
  }

  function legacySuffixEntriesFromInput() {
    return normalizeConfigSuffixRows(lines($('nc_suffix') ? $('nc_suffix').value : ''));
  }

  function suffixEntriesFromDom() {
    var colEntries = suffixEntriesFromProductColumn();
    if (colEntries) return colEntries;
    var body = $('nc_suffix_rows');
    if (!body) return legacySuffixEntriesFromInput();
    return normalizeProductCodeValueEntries(Array.prototype.map.call(body.querySelectorAll('tr'), function (tr) {
      var value = tr.querySelector('[data-suffix-value]');
      var shortcut = tr.querySelector('[data-suffix-shortcut]');
      return {
        value: value ? value.value : '',
        shortcut: shortcut ? shortcut.value : null
      };
    }), true);
  }

  function suffixEntriesFromProductColumn(root) {
    var wrap = root || $('pcr_builder');
    if (!wrap) return null;
    var col = wrap.classList && wrap.classList.contains('pcr-col') ? wrap : null;
    if (col && pcrFieldValue(col, 'key') !== 'suffix') col = null;
    if (!col) {
      Array.prototype.some.call(wrap.querySelectorAll('.pcr-col'), function (candidate) {
        if (pcrFieldValue(candidate, 'key') === 'suffix') {
          col = candidate;
          return true;
        }
        return false;
      });
    }
    if (!col) return null;
    return normalizeProductCodeValueEntries(Array.prototype.map.call(col.querySelectorAll('.mcr-test-value-card'), function (item) {
      var value = item.querySelector('[data-mcr-test-value]');
      var shortcut = item.querySelector('[data-suffix-shortcut]');
      return {
        value: value ? value.value : '',
        shortcut: shortcut ? shortcut.value : null
      };
    }), true);
  }

  function syncSuffixTextarea(entries) {
    var node = $('nc_suffix');
    if (!node) return;
    node.value = normalizeProductCodeValueEntries(entries || [], true).map(function (entry) {
      var shortcut = pcrValueShortcut(entry);
      return pcrValueText(entry) + (shortcut ? ' | ' + shortcut : '');
    }).join('\n');
  }

  function renderSuffixRows(rows) {
    var body = $('nc_suffix_rows');
    var entries = normalizeConfigSuffixRows(rows || []);
    syncSuffixTextarea(entries);
    updateProductSuffixColumnModel(entries);
    refreshProductSuffixColumnValues(entries);
    if (!body) return;
    body.innerHTML = '';
    entries.forEach(function (entry) {
      body.appendChild(buildSuffixRow(entry));
    });
  }

  function buildSuffixRow(entry) {
    var tr = el('tr');
    tr.appendChild(el('td', {}, [
      el('input', { type: 'text', 'data-suffix-value': '1', value: pcrValueText(entry), placeholder: 'VD: Canh' })
    ]));
    tr.appendChild(el('td', {}, [
      el('input', { type: 'number', min: '1', step: '1', class: 'suffix-shortcut-input', 'data-suffix-shortcut': '1', value: pcrValueShortcut(entry), placeholder: 'Số' })
    ]));
    tr.appendChild(el('td', {}, [
      el('button', { class: 'btn xs del', type: 'button', title: 'Xóa suffix', text: '×', 'data-suffix-action': 'delete' })
    ]));
    return tr;
  }

  function addSuffixRow(entry) {
    var body = $('nc_suffix_rows');
    if (!body) return;
    body.appendChild(buildSuffixRow(entry || {}));
    syncSuffixTextarea(suffixEntriesFromDom());
    var inputs = body.querySelectorAll('[data-suffix-value]');
    if (inputs.length) inputs[inputs.length - 1].focus();
  }

  function pcrValuesLabel(values) {
    return (values || []).map(function (entry) {
      var text = pcrValueText(entry);
      var shortcut = pcrValueShortcut(entry);
      if (!text) return '';
      return shortcut ? text + ' (' + shortcut + ')' : text;
    }).filter(function (value) { return value; }).join(', ');
  }

  function hasValidMaterialCodeLayers(layers) {
    return materialCodeLayerList(layers).some(function (layer) {
      return layer && String(layer.key || '').trim();
    });
  }

  function cloneMaterialCodeLayers(layers) {
    return materialCodeLayerList(layers).map(function (layer) {
      return Object.assign({}, layer || {});
    });
  }

  function materialCodeLayerList(layers) {
    if (Array.isArray(layers)) return layers;
    if (layers && typeof layers === 'object') return [layers];
    return [];
  }

  function mergeMaterialRules(base, override) {
    var out = {};
    Object.keys(base || {}).forEach(function (k) {
      var v = base[k];
      out[k] = Array.isArray(v) ? v.slice() : (v && typeof v === 'object' ? mergeMaterialRules(v, {}) : v);
    });
    Object.keys(override || {}).forEach(function (k) {
      var v = override[k];
      out[k] = Array.isArray(v) ? v.slice() : (v && typeof v === 'object' && !Array.isArray(v) && out[k] && typeof out[k] === 'object' && !Array.isArray(out[k]) ? mergeMaterialRules(out[k], v) : v);
    });
    return out;
  }

  function isEmbedded() {
    return window.parent && window.parent !== window;
  }

  function switchRegistryTab(activeTab) {
    activeTab = String(activeTab || 'main').replace(/[^a-z_]/g, '');
    if (activeTab === 'material_assign') activeTab = 'ma_vat_lieu';
    if (!activeTab) activeTab = 'main';
    document.querySelectorAll('.tab').forEach(function (x) { x.classList.remove('active'); });
    document.querySelectorAll('.panel').forEach(function (x) { x.classList.remove('active'); });
    document.querySelectorAll('.tab-actions').forEach(function (x) {
      x.classList.toggle('active', x.dataset.tabActions === activeTab);
    });
    var tab = document.querySelector('.tab[data-tab="' + activeTab + '"]');
    if (tab) tab.classList.add('active');
    var panel = document.querySelector('.panel[data-panel="' + activeTab + '"]');
    if (panel) panel.classList.add('active');
    return !!panel;
  }

  window.MHRegSwitchTab = switchRegistryTab;
  window.MHEmbedded = window.MHEmbedded || {
    app: 'registry',
    ready: false,
    onShow: function (params) {
      return switchRegistryTab(params && params.tab ? params.tab : 'main');
    },
    onHide: function () {},
    destroy: function () {}
  };

  function signalEmbeddedReady() {
    if (!isEmbedded()) return;
    document.body.classList.add('mh-embedded');
    window.MHEmbedded.ready = true;
    try {
      if (window.parent.MHControlPanel && window.parent.MHControlPanel.frameReady) {
        window.parent.MHControlPanel.frameReady('registry');
      } else {
        window.parent.postMessage({ action: 'mh_embedded_ready', panelId: 'registry' }, '*');
      }
    } catch (e) {}
  }

  // ---- render tables ----------------------------------------------------
  function renderTable(name) {
    var def = TABLES[name];
    if (name === 'material_profile_choices') {
      renderMaterialProfileChoices();
      return;
    }
    if (name === 'ma_surface_face_rules') {
      renderSurfaceFaceRules();
      return;
    }
    if (name === 'dc_manual_materials') {
      renderManualMaterialsPicker();
      return;
    }
    if (name === 'ma_vat_lieu_global') {
      renderMaterialMappingBoard();
      return;
    }
    if (name === 'ma_valid') {
      renderValidMaterialsTable();
      return;
    }
    if (!def) return;
    var wrap = $('tbl_' + name);
    if (!wrap) return;
    var rows = (state[def.scope][def.key] || []);
    if (def.groupBy) {
      rows = rows.slice().sort(function (a, b) {
        return String(a[def.groupBy] || '').localeCompare(String(b[def.groupBy] || ''), 'vi');
      });
    }
    wrap.innerHTML = '';
    var table = el('table');
    // header
    var thead = el('tr');
    def.cols.forEach(function (c) { thead.appendChild(el('th', { text: c[1] })); });
    thead.appendChild(el('th', { text: '' }));
    table.appendChild(thead);
    // body
    var lastGroup = null;
    rows.forEach(function (row, i) {
      if (def.groupBy) {
        var group = row[def.groupBy] || '(chưa đặt tên)';
        if (group !== lastGroup) {
          var gtr = el('tr', { class: 'group-row' });
          gtr.appendChild(el('td', { colspan: String(def.cols.length + 1), text: group }));
          table.appendChild(gtr);
          lastGroup = group;
        }
      }
      table.appendChild(buildRow(name, def, row, i));
    });
    wrap.appendChild(table);
    if (!rows.length) wrap.appendChild(el('div', { class: 'empty', text: 'Chưa có dữ liệu — bấm “+ Thêm dòng”.' }));
  }

  function buildRow(name, def, row, i) {
    var tr = el('tr');
    def.cols.forEach(function (c) {
      var td = el('td');
      var value = row[c[0]] != null ? row[c[0]] : '';
      if (c[2] === 'select') {
        td.appendChild(buildSelect(c[0], value, selectOptions(c[3])));
      } else if (c[0] === 'product_only' || c[0] === 'modul_only') {
        var checked = ['1', 'true', 'yes', 'on', 'x', 'checked'].indexOf(String(value).toLowerCase()) >= 0;
        var attrs = { type: 'checkbox', 'data-col': c[0] };
        if (checked) attrs.checked = 'checked';
        td.appendChild(el('input', attrs));
      } else {
        var inputAttrs = { 'data-col': c[0], value: value };
        if (name === 'dc_manual_materials' && c[0] === 'sort_order') {
          inputAttrs.type = 'number';
          inputAttrs.step = '1';
        }
        td.appendChild(el('input', inputAttrs));
      }
      tr.appendChild(td);
    });
    var act = el('td', { class: 'actions' });
    var del = el('button', { class: 'btn del', title: 'Xoá', text: '✕' });
    del.addEventListener('click', function () { tr.parentNode.removeChild(tr); });
    act.appendChild(del);
    tr.appendChild(act);
    return tr;
  }

  function renderMaterialProfileChoices() {
    var rows = (state.config.material_profile_choices || []).slice().sort(function (a, b) {
      return String(a.material_name || '').localeCompare(String(b.material_name || ''), 'vi');
    });
    var wrap = $('tbl_material_profile_choices');
    wrap.innerHTML = '';
    var table = el('table', { class: 'material-profile-table' });
    var head = el('tr');
    head.appendChild(el('th', { text: 'Mã vật liệu' }));
    head.appendChild(el('th', { text: 'Độ dày 1' }));
    head.appendChild(el('th', { text: 'Độ dày 2' }));
    head.appendChild(el('th', { text: '' }));
    head.appendChild(el('th', { text: 'Mã vật liệu' }));
    head.appendChild(el('th', { text: 'Độ dày 1' }));
    head.appendChild(el('th', { text: 'Độ dày 2' }));
    head.appendChild(el('th', { text: '' }));
    table.appendChild(head);

    var splitAt = Math.ceil(rows.length / 2);
    var left = rows.slice(0, splitAt);
    var right = rows.slice(splitAt);
    var count = Math.max(left.length, right.length);
    for (var i = 0; i < count; i++) table.appendChild(buildMaterialProfilePairRow(left[i], right[i]));

    wrap.appendChild(table);
    if (!rows.length) wrap.appendChild(el('div', { class: 'empty', text: 'Chưa có dữ liệu — bấm “Tải danh sách”.' }));
  }

  function buildMaterialProfilePairRow(leftRow, rightRow) {
    var tr = el('tr', { class: 'material-profile-row' });
    appendMaterialProfileCells(tr, leftRow);
    appendMaterialProfileCells(tr, rightRow);
    return tr;
  }

  function appendMaterialProfileCells(tr, row) {
    if (!row) {
      tr.appendChild(el('td'));
      tr.appendChild(el('td'));
      tr.appendChild(el('td'));
      tr.appendChild(el('td', { class: 'actions' }));
      return;
    }

    tr.appendChild(el('td', {}, [el('input', { 'data-col': 'material_name', value: row.material_name || '', readonly: 'readonly' })]));
    tr.appendChild(el('td', {}, [el('input', { 'data-col': 'thickness_1', value: row.thickness_1 || row.material_type_1 || '', placeholder: 'VD: 17.6' })]));
    tr.appendChild(el('td', {}, [el('input', { 'data-col': 'thickness_2', value: row.thickness_2 || row.material_type_2 || '', placeholder: 'VD: 8' })]));

    var act = el('td', { class: 'actions' });
    var del = el('button', { class: 'btn del', title: 'Xoá vật liệu', text: '✕' });
    del.addEventListener('click', function () {
      state.config.material_profile_choices = (state.config.material_profile_choices || []).filter(function (item) {
        return item !== row;
      });
      renderMaterialProfileChoices();
    });
    act.appendChild(del);
    tr.appendChild(act);
  }

  function buildMaterialProfileThicknessRow(row, col, label, withDelete) {
    var tr = el('tr', { class: 'material-profile-row' });
    var labelTd = el('td');
    labelTd.appendChild(el('input', { type: 'hidden', 'data-col': 'material_name', value: row.material_name || '' }));
    labelTd.appendChild(el('span', { class: 'profile-thickness-label', text: label }));
    tr.appendChild(labelTd);

    var value = row[col] || row[col === 'thickness_1' ? 'material_type_1' : 'material_type_2'] || '';
    tr.appendChild(el('td', {}, [el('input', { 'data-col': col, value: value, placeholder: 'VD: 17.6 hoặc 8' })]));

    var act = el('td', { class: 'actions' });
    if (withDelete) {
      var del = el('button', { class: 'btn del', title: 'Xoá vật liệu', text: '✕' });
      del.addEventListener('click', function () {
        state.config.material_profile_choices = (state.config.material_profile_choices || []).filter(function (item) {
          return item !== row;
        });
        renderMaterialProfileChoices();
      });
      act.appendChild(del);
    }
    tr.appendChild(act);
    return tr;
  }

  function syncMaterialProfileRows(names, source) {
    names = uniqueBaseMaterialNames(names);
    var existing = state.config.material_profile_choices || [];
    var byName = {};
    existing.forEach(function (row) {
      var name = String(row.material_name || '').trim();
      if (name && !byName[name]) byName[name] = row;
    });

    state.config.material_profile_choices = names.map(function (name) {
      var row = byName[name] || {};
      return {
        material_name: name,
        thickness_1: row.thickness_1 || row.material_type_1 || '',
        thickness_2: row.thickness_2 || row.material_type_2 || ''
      };
    });
    renderTable('material_profile_choices');
    status('Đã tải ' + names.length + ' vật liệu từ ' + (source || 'nguồn dữ liệu') + '.', 'ok');
  }

  function uniqueBaseMaterialNames(names) {
    var seen = {};
    var out = [];
    (names || []).forEach(function (raw) {
      var base = baseMaterialName(raw);
      if (!base || seen[base]) return;
      seen[base] = true;
      out.push(base);
    });
    return out.sort(function (a, b) { return a.localeCompare(b, 'vi'); });
  }

  function baseMaterialName(raw) {
    var text = String(raw || '').trim();
    if (!text || /^VBO_/i.test(text)) return '';
    var parts = text.split('.').map(function (part) { return part.trim(); }).filter(function (part) { return part.length; });
    if (!parts.length) return '';
    if (parts.length > 1 && /^\d+(?:[,.]\d+)?$/.test(parts[1])) {
      return [parts[0]].concat(parts.slice(2)).join('.');
    }
    return parts.join('.');
  }

  function reloadMaterialProfiles() {
    status('Đang tải danh sách vật liệu…');
    Bridge.get('material_profile_names').then(function (r) {
      if (!r || !r.ok) {
        status('Lỗi tải danh sách vật liệu', 'err');
        return;
      }
      syncMaterialProfileRows(r.names || [], r.source);
    });
  }

  function collectTable(name) {
    if (name === 'material_profile_choices') return collectMaterialProfileChoices();
    if (name === 'ma_surface_face_rules') return collectSurfaceFaceRules();
    if (name === 'dc_manual_materials') return collectManualMaterialsPicker();
    if (name === 'ma_vat_lieu_global') return collectMaterialMappingBoard();
    if (name === 'ma_valid') return collectValidMaterialsTable();
    var def = TABLES[name];
    var wrap = $('tbl_' + name);
    if (!def || !wrap) {
      if (def && state[def.scope] && state[def.scope][def.key]) return state[def.scope][def.key];
      return [];
    }
    var out = [];
    var trs = wrap.querySelectorAll('table tr');
    for (var i = 1; i < trs.length; i++) { // skip header
      var obj = {}, empty = true;
      def.cols.forEach(function (c) {
        var inp = trs[i].querySelector('[data-col="' + c[0] + '"]');
        var v = inp ? (inp.type === 'checkbox' ? (inp.checked ? '1' : '') : inp.value.trim()) : '';
        if (v) empty = false;
        if (c[2] === 'num' && v !== '') { var n = parseFloat(v); obj[c[0]] = isNaN(n) ? v : n; }
        else obj[c[0]] = v;
      });
      if (!empty) out.push(obj);
    }
    return out;
  }

  function collectMaterialProfileChoices() {
    var out = [];
    var trs = $('tbl_material_profile_choices').querySelectorAll('tr.material-profile-row');
    for (var i = 0; i < trs.length; i++) {
      var nameInputs = trs[i].querySelectorAll('input[data-col="material_name"]');
      for (var j = 0; j < nameInputs.length; j++) {
        var name = nameInputs[j].value.trim();
        if (!name) continue;
        var cell = nameInputs[j].parentNode;
        var t1 = nextInputValue(cell, 'thickness_1');
        var t2 = nextInputValue(cell, 'thickness_2');
        out.push({ material_name: name, thickness_1: t1, thickness_2: t2 });
      }
    }
    return out.sort(function (a, b) { return a.material_name.localeCompare(b.material_name, 'vi'); });
  }

  function nextInputValue(nameCell, col) {
    var td = nameCell;
    while (td && td.nodeName !== 'TD') td = td.parentNode;
    if (!td) return '';
    var cur = td.nextSibling;
    while (cur) {
      var inp = cur.querySelector && cur.querySelector('input[data-col="' + col + '"]');
      if (inp) return inp.value.trim();
      if (cur.querySelector && cur.querySelector('input[data-col="material_name"]')) return '';
      cur = cur.nextSibling;
    }
    return '';
  }

  // ---- ma_surface_face_rules (giao diện thẻ, dễ thêm giá trị) ----------
  // Mỗi rule render thành 1 thẻ. Các field dạng danh sách (token phủ, chi tiết
  // .2M) hiển thị dạng chip có nút +/✕; override theo nhóm phủ là các dòng con.
  // Sửa hoàn toàn ở DOM (giống buildRow); collect đọc lại DOM lúc lưu — không
  // re-render giữa chừng nên không mất giá trị đang gõ dở.
  function sfrSplitList(value) {
    return String(value == null ? '' : value)
      .split(/[|,;]/).map(function (s) { return s.trim(); })
      .filter(function (s) { return s.length; });
  }
  function sfrIsTruthy(value) {
    return ['1', 'true', 'yes', 'y', 'on', 'x', 'checked', 'co', 'có']
      .indexOf(String(value == null ? '' : value).trim().toLowerCase()) >= 0;
  }
  function sfrParseOverrides(value) {
    return String(value == null ? '' : value).split(/[;|]/).map(function (entry) {
      var i = entry.indexOf(':');
      if (i < 0) return null;
      var group = entry.slice(0, i).trim();
      if (!group) return null;
      var sfx = entry.slice(i + 1).split(/[,\s]+/)
        .map(function (s) { return s.trim(); }).filter(function (s) { return s.length; });
      return { group: group, one: sfx[0] || '', two: sfx[1] || '', def: sfx[2] || '' };
    }).filter(Boolean);
  }

  var SFR_DEFAULT_RULE = {
    enabled: '1',
    surface_tokens: 'LAM,LAMINATE,LK,VENE,VER',
    max_one_side_thickness: '9',
    one_side_suffix: '.1M',
    two_side_suffix: '.2M',
    default_suffix: '.1M',
    finish_suffix_overrides: 'LK:.1M-BCT,.2M-BCT'
  };

  function sfrRuleValue(rule, field) {
    var value = rule && rule[field];
    value = value == null ? '' : String(value).trim();
    return value || SFR_DEFAULT_RULE[field] || '';
  }

  function renderSurfaceFaceRules() {
    var wrap = $('tbl_ma_surface_face_rules');
    if (!wrap) return;
    var rules = state.config.ma_surface_face_rules || [];
    wrap.innerHTML = '';
    var cards = el('div', { class: 'sfr-cards' });
    rules.forEach(function (rule) { cards.appendChild(buildSurfaceFaceCard(rule)); });
    wrap.appendChild(cards);
    if (!rules.length) wrap.appendChild(el('div', { class: 'empty', text: 'Chưa có quy luật — bấm “+ dòng”.' }));
  }

  function buildSurfaceFaceCard(rule) {
    rule = rule || {};
    var card = el('div', { class: 'sfr-card sfr-card-compact' });

    // header: bật + xoá thẻ
    var head = el('div', { class: 'sfr-head' });
    var lbl = el('label', { class: 'sfr-enabled' });
    var enAttrs = { type: 'checkbox', 'data-sfr': 'enabled' };
    if (sfrIsTruthy(rule.enabled == null ? '1' : rule.enabled)) enAttrs.checked = 'checked';
    lbl.appendChild(el('input', enAttrs));
    lbl.appendChild(el('span', { text: ' Bật quy luật này' }));
    head.appendChild(lbl);
    var del = el('button', { class: 'btn del', title: 'Xoá quy luật', text: '✕ Xoá' });
    del.addEventListener('click', function () {
      var c = card; if (c.parentNode) c.parentNode.removeChild(c);
    });
    head.appendChild(del);
    card.appendChild(head);

    card.appendChild(buildSfrHiddenField('surface_tokens', sfrRuleValue(rule, 'surface_tokens')));
    card.appendChild(buildSfrHiddenField('max_one_side_thickness', sfrRuleValue(rule, 'max_one_side_thickness')));
    card.appendChild(buildSfrHiddenField('one_side_suffix', sfrRuleValue(rule, 'one_side_suffix')));
    card.appendChild(buildSfrHiddenField('two_side_suffix', sfrRuleValue(rule, 'two_side_suffix')));
    card.appendChild(buildSfrHiddenField('default_suffix', sfrRuleValue(rule, 'default_suffix')));
    card.appendChild(buildSfrHiddenField('finish_suffix_overrides', sfrRuleValue(rule, 'finish_suffix_overrides')));

    card.appendChild(sfrFieldBlock('Chi tiết nhận surface_variant hai mặt (.2M); còn lại dùng biến thể một mặt',
      buildSfrChips('two_side_details', sfrSplitList(rule.two_side_details), 'VD: Cánh')));

    return card;
  }

  function sfrFieldBlock(labelText, child) {
    var block = el('div', { class: 'sfr-field' });
    block.appendChild(el('label', { class: 'sfr-label', text: labelText }));
    block.appendChild(child);
    return block;
  }
  function sfrTextField(labelText, field, value, ph) {
    var cell = el('div', { class: 'sfr-cell' });
    cell.appendChild(el('label', { class: 'sfr-label', text: labelText }));
    cell.appendChild(el('input', { 'data-sfr': field, value: value == null ? '' : value, placeholder: ph || '' }));
    return cell;
  }
  function buildSfrHiddenField(field, value) {
    return el('input', { type: 'hidden', 'data-sfr': field, value: value == null ? '' : value });
  }

  function buildSfrChip(value) {
    var chip = el('span', { class: 'sfr-tag' });
    chip.appendChild(el('span', { class: 'sfr-tag-label', text: value }));
    var x = el('button', { class: 'sfr-tag-del', title: 'Xoá', text: '✕' });
    x.addEventListener('click', function () { if (chip.parentNode) chip.parentNode.removeChild(chip); });
    chip.appendChild(x);
    return chip;
  }
  function buildSfrChips(field, values, ph) {
    var box = el('div', { class: 'sfr-tags', 'data-sfr': field });
    values.forEach(function (v) { box.appendChild(buildSfrChip(v)); });
    var add = el('input', { class: 'sfr-tag-add', placeholder: ph || '+ thêm…' });
    function commit() {
      // Tránh dấu phân tách trong giá trị để không phá chuỗi khi serialize.
      var v = add.value.replace(/[|,;]+/g, ' ').replace(/\s+/g, ' ').trim();
      if (!v) { add.value = ''; return; }
      box.insertBefore(buildSfrChip(v), add);
      add.value = '';
    }
    add.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') { e.preventDefault(); commit(); }
    });
    add.addEventListener('blur', commit);
    box.appendChild(add);
    return box;
  }

  function buildSfrOverrideRow(ov) {
    ov = ov || {};
    var row = el('div', { class: 'sfr-ov-row' });
    row.appendChild(el('input', { class: 'sfr-ov-group', 'data-ov': 'group', value: ov.group || '', placeholder: 'Nhóm' }));
    row.appendChild(el('input', { 'data-ov': 'one', value: ov.one || '', placeholder: 'Suffix mỏng' }));
    row.appendChild(el('input', { 'data-ov': 'two', value: ov.two || '', placeholder: 'Suffix 2 mặt' }));
    row.appendChild(el('input', { 'data-ov': 'def', value: ov.def || '', placeholder: 'Suffix còn lại' }));
    var x = el('button', { class: 'btn del', title: 'Xoá override', text: '✕' });
    x.addEventListener('click', function () { if (row.parentNode) row.parentNode.removeChild(row); });
    row.appendChild(x);
    return row;
  }
  function buildSfrOverrides(packed) {
    var block = el('div', { class: 'sfr-field' });
    var ohead = el('div', { class: 'sfr-ov-head' });
    ohead.appendChild(el('label', { class: 'sfr-label', text: 'Override suffix theo nhóm phủ (vd LK, VER)' }));
    var addBtn = el('button', { class: 'btn xs', text: '+ override' });
    ohead.appendChild(addBtn);
    block.appendChild(ohead);
    var list = el('div', { class: 'sfr-overrides' });
    sfrParseOverrides(packed).forEach(function (ov) { list.appendChild(buildSfrOverrideRow(ov)); });
    block.appendChild(list);
    addBtn.addEventListener('click', function () { list.appendChild(buildSfrOverrideRow({})); });
    return block;
  }

  function collectSurfaceFaceRules() {
    var wrap = $('tbl_ma_surface_face_rules');
    if (!wrap) return state.config.ma_surface_face_rules || [];
    var out = [];
    var cards = wrap.querySelectorAll('.sfr-card');
    for (var i = 0; i < cards.length; i++) {
      var card = cards[i];
      var enNode = card.querySelector('[data-sfr="enabled"]');
      var tokens = sfrFieldListValues(card, 'surface_tokens');
      var details = sfrChipValues(card, 'two_side_details');
      var overrides = sfrVal(card, 'finish_suffix_overrides') || sfrCollectOverrides(card);
      var thk = sfrVal(card, 'max_one_side_thickness');
      var one = sfrVal(card, 'one_side_suffix');
      var two = sfrVal(card, 'two_side_suffix');
      var def = sfrVal(card, 'default_suffix');
      // bỏ qua thẻ trống hoàn toàn
      if (!details.length) continue;
      out.push({
        enabled: (enNode && !enNode.checked) ? '' : '1',
        surface_tokens: tokens.join(','),
        max_one_side_thickness: thk,
        one_side_suffix: one,
        two_side_details: details.join(','),
        two_side_suffix: two,
        default_suffix: def,
        finish_suffix_overrides: overrides
      });
    }
    return out;
  }
  function sfrVal(card, field) {
    var n = card.querySelector('[data-sfr="' + field + '"]');
    return n ? n.value.trim() : '';
  }
  function sfrChipValues(card, field) {
    var box = card.querySelector('.sfr-tags[data-sfr="' + field + '"]');
    if (!box) return [];
    var labels = box.querySelectorAll('.sfr-tag-label');
    var out = [];
    for (var i = 0; i < labels.length; i++) {
      var t = labels[i].textContent.trim();
      if (t) out.push(t);
    }
    return out;
  }
  function sfrFieldListValues(card, field) {
    var chips = sfrChipValues(card, field);
    if (chips.length) return chips;
    return sfrSplitList(sfrVal(card, field));
  }
  function sfrCollectOverrides(card) {
    var rows = card.querySelectorAll('.sfr-ov-row');
    var parts = [];
    for (var i = 0; i < rows.length; i++) {
      var g = sfrOvVal(rows[i], 'group');
      if (!g) continue;
      var sfx = [sfrOvVal(rows[i], 'one'), sfrOvVal(rows[i], 'two'), sfrOvVal(rows[i], 'def')];
      while (sfx.length && !sfx[sfx.length - 1]) sfx.pop();
      parts.push(g + ':' + sfx.join(','));
    }
    return parts.join(';');
  }
  function sfrOvVal(row, key) {
    var n = row.querySelector('[data-ov="' + key + '"]');
    return n ? n.value.trim() : '';
  }

  // ---- dc_thickness_options (library; project table is deprecated) -----
  var dcOptCount = { project: 2, library: 2 };

  // Renderer vẫn giữ nhánh project để dọn dữ liệu cũ khi lưu config, nhưng UI
  // Superimp hiện chỉ dùng library/parent.
  var THICK_CFG = {
    project: {
      wrap: 'tbl_dc_thickness_options',
      read: function () { return []; },
      write: function (_rows) { state.config.dc_thickness_options = []; state.config.dc_thickness_options_project = []; },
      empty: 'Không có mã project cần bổ sung — mã đã có trong library sẽ không hiện ở đây.'
    },
    library: {
      wrap: 'tbl_dc_thickness_options_library',
      read: function () { return state.config.dc_thickness_options_library || []; },
      write: function (rows) { state.config.dc_thickness_options_library = rows; },
      empty: 'Library trống — bấm "+ loại" để thêm mã vật liệu và độ dày.'
    }
  };

  function currentOptionCount(kind, rows) {
    var maxOpt = 0;
    (rows || []).forEach(function (r) {
      var n = (r.options || []).length;
      if (n > maxOpt) maxOpt = n;
    });
    return Math.max(2, dcOptCount[kind] || 2, maxOpt);
  }

  function renderThicknessOptions(kind) {
    kind = kind || 'project';
    var cfg = THICK_CFG[kind];
    var wrap = $(cfg.wrap);
    if (!wrap) return;
    var rows = cfg.read().slice().sort(function (a, b) {
      return String(a.material_type || '').localeCompare(String(b.material_type || ''), 'vi');
    });
    var nOpt = currentOptionCount(kind, rows);
    dcOptCount[kind] = nOpt;
    wrap.innerHTML = '';
    var table = el('table', { class: 'thickness-options-table' });

    var h1 = el('tr');
    h1.appendChild(el('th', { text: 'Mã vật liệu (loại)', rowspan: '2', class: 'material-type-head' }));
    for (var i = 1; i <= nOpt; i++) h1.appendChild(el('th', { text: 'Option ' + i, colspan: '2', class: 'option-head' }));
    h1.appendChild(el('th', { text: '', rowspan: '2' }));
    table.appendChild(h1);
    var h2 = el('tr');
    for (var j = 1; j <= nOpt; j++) {
      h2.appendChild(el('th', { text: 'Panel', class: 'thickness-subhead' }));
      h2.appendChild(el('th', { text: 'Hậu', class: 'thickness-subhead' }));
    }
    table.appendChild(h2);

    rows.forEach(function (row) { table.appendChild(buildThicknessRow(kind, row, nOpt)); });
    wrap.appendChild(table);
    if (!rows.length) wrap.appendChild(el('div', { class: 'empty', text: cfg.empty }));
    if (kind === 'library') {
      wireThicknessLibrarySearch();
      applyThicknessLibrarySearchFilter();
    }
  }

  function buildThicknessRow(kind, row, nOpt) {
    var tr = el('tr', { class: 'thickness-row' });
    var materialInput = el('input', { 'data-col': 'material_type', value: row.material_type || '', placeholder: 'VD: MDFCA.AC' });
    tr.appendChild(el('td', {}, [materialInput]));
    var opts = row.options || [];
    for (var i = 0; i < nOpt; i++) {
      var o = opts[i] || {};
      tr.appendChild(el('td', {}, [thicknessInput(kind, 'opt' + i + '_panel', o.panel, '17.6')]));
      tr.appendChild(el('td', {}, [thicknessInput(kind, 'opt' + i + '_back', o.back, '8')]));
    }
    var act = el('td', { class: 'actions' });
    var del = el('button', { class: 'btn del', title: 'Xoá', text: '✕' });
    del.addEventListener('click', function () {
      var keep = collectThicknessOptions(kind).filter(function (r) {
        return String(r.material_type).trim() !== String(row.material_type || '').trim();
      });
      THICK_CFG[kind].write(keep);
      renderThicknessOptions(kind);
    });
    act.appendChild(del);
    tr.appendChild(act);
    return tr;
  }

  function thicknessInput(kind, col, value, placeholder) {
    var text = value == null ? '' : String(value).trim();
    var emptyLibraryCell = kind === 'library' && !text;
    var input = el('input', {
      'data-col': col,
      'data-empty-marker': emptyLibraryCell ? '1' : '',
      value: emptyLibraryCell ? '--' : text,
      placeholder: kind === 'library' ? '--' : placeholder
    });
    if (kind === 'library') {
      input.addEventListener('input', function () {
        input.setAttribute('data-empty-marker', cleanThicknessInputValue(kind, input.value) ? '' : '1');
      });
      input.addEventListener('focus', function () {
        if (input.value.trim() === '--') input.select();
      });
    }
    return input;
  }

  function cleanThicknessInputValue(kind, value) {
    var text = value == null ? '' : String(value).trim();
    if (kind === 'library' && text === '--') return '';
    return text;
  }

  function collectThicknessOptions(kind) {
    kind = kind || 'project';
    var cfg = THICK_CFG[kind];
    var wrap = $(cfg.wrap);
    if (!wrap) return kind === 'project' ? [] : cfg.read();
    var out = [];
    var trs = wrap.querySelectorAll('tr.thickness-row');
    for (var i = 0; i < trs.length; i++) {
      var typeInp = trs[i].querySelector('input[data-col="material_type"]');
      var type = typeInp ? typeInp.value.trim() : '';
      if (!type) continue;
      var options = [];
      var k = 0;
      while (true) {
        var p = trs[i].querySelector('input[data-col="opt' + k + '_panel"]');
        var b = trs[i].querySelector('input[data-col="opt' + k + '_back"]');
        if (!p && !b) break;
        var panel = p ? cleanThicknessInputValue(kind, p.value) : '';
        var back = b ? cleanThicknessInputValue(kind, b.value) : '';
        if (panel || back) options.push({ panel: panel, back: back });
        k++;
      }
      out.push({ material_type: type, options: options });
    }
    return out;
  }

  function addThicknessOption(kind) {
    kind = kind || 'project';
    THICK_CFG[kind].write(collectThicknessOptions(kind));
    dcOptCount[kind] = currentOptionCount(kind, THICK_CFG[kind].read()) + 1;
    renderThicknessOptions(kind);
  }

  function addThicknessType(kind) {
    kind = kind || 'project';
    var rows = collectThicknessOptions(kind);
    rows.push({ material_type: '', options: [] });
    THICK_CFG[kind].write(rows);
    renderThicknessOptions(kind);
    var inps = $(THICK_CFG[kind].wrap).querySelectorAll('input[data-col="material_type"]');
    for (var i = 0; i < inps.length; i++) { if (!inps[i].value.trim()) { inps[i].focus(); break; } }
  }

  function thicknessRowsByKey(rows) {
    var out = {};
    (rows || []).forEach(function (row) {
      var key = String(row.material_type || row.material_code || '').trim().toUpperCase();
      if (key && !out[key]) out[key] = row;
    });
    return out;
  }

  function manualSortOrder(row) {
    var raw = row && (row.sort_order != null ? row.sort_order
      : (row.order != null ? row.order : row.thu_tu));
    if (raw == null || String(raw).trim() === '') return null;
    var value = parseFloat(raw);
    return isFinite(value) ? value : null;
  }

  function normalizeManualMaterialRowsForUi(rows) {
    return (rows || []).map(function (row, index) {
      var sortOrder = manualSortOrder(row);
      return {
        material_code: String(row.material_code || row.material_type || '').trim(),
        sort_order: sortOrder == null ? '' : sortOrder,
        enabled: row.enabled != null ? row.enabled : '1',
        _source_index: index
      };
    }).filter(function (row) {
      return row.material_code.length > 0;
    }).sort(function (a, b) {
      var aOrder = manualSortOrder(a);
      var bOrder = manualSortOrder(b);
      if (aOrder == null && bOrder != null) return 1;
      if (aOrder != null && bOrder == null) return -1;
      if (aOrder != null && bOrder != null && aOrder !== bOrder) return aOrder - bOrder;
      return a._source_index - b._source_index;
    }).map(function (row) {
      delete row._source_index;
      return row;
    });
  }

  function mergeManualMaterialsFromTypes(types) {
    var current = collectTable('dc_manual_materials');
    var rows = [];
    var have = {};
    current.forEach(function (row) {
      var code = String(row.material_code || '').trim();
      var key = code.toUpperCase();
      if (!code || have[key]) return;
      var sortOrder = manualSortOrder(row);
      rows.push({ material_code: code, sort_order: sortOrder == null ? '' : sortOrder, enabled: row.enabled || '' });
      have[key] = true;
    });

    var added = 0;
    (types || []).forEach(function (type) {
      var code = String(type).trim();
      var key = code.toUpperCase();
      if (!code || have[key]) return;
      rows.push({ material_code: code, sort_order: '', enabled: '0' });
      have[key] = true;
      added++;
    });

    state.config.dc_manual_materials = normalizeManualMaterialRowsForUi(rows);
    renderTable('dc_manual_materials');
    return { added: added, total: rows.length };
  }

  function mergeManualRowsForUi(baseRows, overrideRows) {
    var rows = [];
    var index = {};
    function addOrMerge(row) {
      var code = String(row.material_code || row.material_type || '').trim();
      var key = code.toUpperCase();
      if (!code) return;
      var sortOrder = manualSortOrder(row);
      var normalized = {
        material_code: code,
        sort_order: sortOrder == null ? '' : sortOrder,
        enabled: row.enabled || ''
      };
      if (index.hasOwnProperty(key)) rows[index[key]] = Object.assign(rows[index[key]], normalized);
      else {
        index[key] = rows.length;
        rows.push(normalized);
      }
    }
    (baseRows || []).forEach(addOrMerge);
    (overrideRows || []).forEach(addOrMerge);
    return normalizeManualMaterialRowsForUi(rows);
  }

  function manualEnabled(value) {
    return ['1', 'true', 'yes', 'y', 'on', 'x', 'checked', 'co', 'có']
      .indexOf(String(value == null ? '' : value).trim().toLowerCase()) >= 0;
  }

  function addManualCandidate(map, code, row) {
    code = String(code || '').trim();
    if (!code) return;
    var key = code.toUpperCase();
    if (map[key]) return;
    map[key] = Object.assign({ material_code: code, enabled: '0', sort_order: '' }, row || {}, { material_code: code });
  }

  function manualSourceRows() {
    return collectThicknessOptions('library');
  }

  function manualSourceKeys() {
    var keys = {};
    manualSourceRows().forEach(function (row) {
      var code = String(row.material_type || row.material_code || '').trim();
      if (code) keys[code.toUpperCase()] = true;
    });
    return keys;
  }

  function allManualMaterialCandidates() {
    var map = {};
    var manualState = {};

    (state.config.dc_manual_materials || []).forEach(function (row) {
      var code = String(row.material_code || row.material_type || '').trim();
      if (code) manualState[code.toUpperCase()] = row;
    });

    manualSourceRows().forEach(function (row) {
      var code = String(row.material_type || row.material_code || '').trim();
      var key = code.toUpperCase();
      addManualCandidate(map, code, manualState[key] || { enabled: '0', sort_order: '' });
    });

    return Object.keys(map).map(function (key) { return map[key]; });
  }

  function manualPickerItem(row, manualIndex) {
    var code = String(row.material_code || row.material_type || '').trim();
    var item = el('div', { class: 'mh-manual-item', draggable: 'true', 'data-code': code });
    item.appendChild(el('span', { class: 'mh-manual-grip', text: '⋮⋮' }));
    if (manualIndex != null) item.appendChild(el('span', { class: 'mh-manual-order', text: String(manualIndex + 1) }));
    item.appendChild(el('span', { class: 'mh-manual-code', text: code }));
    return item;
  }

  function renderManualMaterialsPicker() {
    var wrap = $('tbl_dc_manual_materials');
    if (!wrap) return;

    var rows = normalizeManualMaterialRowsForUi(allManualMaterialCandidates());
    var manual = [];
    var available = [];
    rows.forEach(function (row) {
      if (manualEnabled(row.enabled)) manual.push(row);
      else available.push(row);
    });
    available.sort(function (a, b) {
      return String(a.material_code || '').localeCompare(String(b.material_code || ''), 'vi');
    });

    wrap.innerHTML = '';
    var picker = el('div', { class: 'mh-manual-picker' });
    var left = manualPickerColumn('available', 'Danh sách vật liệu tổng');
    var right = manualPickerColumn('manual', 'Danh sách Manual');
    available.forEach(function (row) { left.list.appendChild(manualPickerItem(row, null)); });
    manual.forEach(function (row, index) { right.list.appendChild(manualPickerItem(row, index)); });
    picker.appendChild(left.col);
    picker.appendChild(right.col);
    wrap.appendChild(picker);
    wireManualPickerDnD(wrap);
    wireManualSearch();
    applyManualSearchFilter();
    refreshManualPickerOrder(wrap);
  }

  function manualPickerColumn(name, title) {
    var col = el('div', { class: 'mh-manual-col', 'data-manual-col': name });
    col.appendChild(el('div', { class: 'mh-manual-col-title', text: title }));
    var list = el('div', { class: 'mh-manual-list', 'data-manual-list': name });
    col.appendChild(list);
    return { col: col, list: list };
  }

  function collectManualMaterialsPicker() {
    var wrap = $('tbl_dc_manual_materials');
    if (!wrap) return normalizeManualMaterialRowsForUi(state.config.dc_manual_materials || []);
    var out = [];
    var seen = {};
    var validKeys = manualSourceKeys();

    function push(code, enabled, order) {
      code = String(code || '').trim();
      var key = code.toUpperCase();
      if (!code || seen[key]) return;
      if (!validKeys[key]) return;
      out.push({
        material_code: code,
        sort_order: enabled ? order : '',
        enabled: enabled ? '1' : '0'
      });
      seen[key] = true;
    }

    var manualItems = wrap.querySelectorAll('.mh-manual-list[data-manual-list="manual"] .mh-manual-item[data-code]');
    for (var i = 0; i < manualItems.length; i++) push(manualItems[i].getAttribute('data-code'), true, i + 1);

    return out;
  }

  function wireManualPickerDnD(wrap) {
    if (wrap.__mhManualDnD) return;
    wrap.__mhManualDnD = true;
    var dragging = null;

    wrap.addEventListener('dragstart', function (e) {
      var item = e.target.closest('.mh-manual-item[data-code]');
      if (!item || !wrap.contains(item)) return;
      dragging = item;
      item.classList.add('mh-dragging');
      if (e.dataTransfer) {
        e.dataTransfer.effectAllowed = 'move';
        e.dataTransfer.setData('text/plain', item.getAttribute('data-code') || '');
      }
    });

    wrap.addEventListener('dragend', function () {
      if (dragging) dragging.classList.remove('mh-dragging');
      dragging = null;
      refreshManualPickerOrder(wrap);
      state.config.dc_manual_materials = collectManualMaterialsPicker();
    });

    wrap.addEventListener('dragover', function (e) {
      if (!dragging) return;
      var list = e.target.closest('.mh-manual-list');
      if (!list || !wrap.contains(list)) return;
      e.preventDefault();
      var after = manualItemAfterPointer(list, e.clientY, dragging);
      if (after) list.insertBefore(dragging, after);
      else list.appendChild(dragging);
      refreshManualPickerOrder(wrap);
    });

    wrap.addEventListener('drop', function (e) {
      if (!dragging) return;
      e.preventDefault();
      refreshManualPickerOrder(wrap);
      state.config.dc_manual_materials = collectManualMaterialsPicker();
    });
  }

  function manualItemAfterPointer(list, y, dragging) {
    var items = Array.prototype.filter.call(list.querySelectorAll('.mh-manual-item'), function (item) {
      return item !== dragging;
    });
    var closest = { offset: Number.NEGATIVE_INFINITY, item: null };
    items.forEach(function (item) {
      var box = item.getBoundingClientRect();
      var offset = y - box.top - box.height / 2;
      if (offset < 0 && offset > closest.offset) closest = { offset: offset, item: item };
    });
    return closest.item;
  }

  function refreshManualPickerOrder(wrap) {
    var manualItems = wrap.querySelectorAll('.mh-manual-list[data-manual-list="manual"] .mh-manual-item');
    for (var i = 0; i < manualItems.length; i++) {
      var badge = manualItems[i].querySelector('.mh-manual-order');
      if (!badge) {
        badge = el('span', { class: 'mh-manual-order' });
        manualItems[i].insertBefore(badge, manualItems[i].querySelector('.mh-manual-code'));
      }
      badge.textContent = String(i + 1);
    }
    var availableItems = wrap.querySelectorAll('.mh-manual-list[data-manual-list="available"] .mh-manual-item');
    for (var j = 0; j < availableItems.length; j++) {
      var old = availableItems[j].querySelector('.mh-manual-order');
      if (old) old.remove();
    }
  }

  // ---- material_code_rules ---------------------------------------------
  function renderMaterialCodeRules() {
    var rules = materialCodeRules();
    rules.layers = normalizeMcrLayerOrder(rules.layers || []);
    setValue('mcr_segment_separator', mcrSeparatorFromRules(rules));
    setValue('mcr_multi_separators', (rules.multi_separators || ['&']).join(', '));
    renderMcrGlossMode(rules.gloss_suffix_regex || MCR_GLOSS_DASH_NUMBER_PATTERN);
    var uppercase = $('mcr_uppercase');
    if (uppercase) uppercase.checked = rules.uppercase !== false;

    renderMaterialCodeContract(rules);
    renderMaterialCodeGroupRules(rules);
    renderMaterialCodeTestBuilder(rules);

    var wrap = $('tbl_material_code_layers');
    if (wrap) {
      wrap.hidden = true;
      wrap.innerHTML = '';
    }
    validateMaterialCodeRules(rules);
    updateMaterialCodePreview();
  }

  function materialContractInfo(layer) {
    var key = String(layer.key || '').trim();
    var info = {
      chat_lieu: {
        label: 'Chất liệu',
        type: 'Text',
        source: 'Từ điển',
        required: 'Có',
        parent: 'Có',
        note: 'MDFCA, PLY, HDFCA, GOSOI.'
      },
      do_day: {
        label: 'Độ dày',
        type: 'Number',
        source: 'Không dùng từ điển',
        required: 'Không',
        parent: 'Không',
        note: '17, 18, 17.5. Có thể thiếu.'
      },
      nha_cung_cap: {
        label: 'Nhà cung cấp',
        type: 'Text',
        source: 'Từ điển',
        required: 'Không',
        parent: 'Có',
        note: 'AC hoặc An Cường -> AC.'
      },
      be_mat: {
        label: 'Nhóm bề mặt',
        type: 'Text',
        source: 'Từ điển',
        required: 'Không',
        parent: 'Có',
        note: 'Phân nhóm chính: SON, LK, VER, MS. VER gồm VER/VERKT/VERSOI/VERKTSOI.'
      },
      finish_code: {
        label: 'Mã hoàn thiện',
        type: 'String tự do',
        source: 'Không bắt buộc từ điển',
        required: 'Không',
        parent: 'Có',
        note: 'Chứa chữ, số, khoảng trắng, /, -, _. Ví dụ 30GY 88/014-30, BQ743957-30, SA7680.'
      }
    }[key] || {};

    return {
      key: key,
      label: String(layer.label || info.label || key).trim(),
      type: info.type || (layer.role === 'thickness' ? 'Number' : (layer.capture_rest ? 'String tự do' : 'Text')),
      source: info.source || (layer.capture_rest ? 'Không bắt buộc từ điển' : 'Từ điển hoặc mã nhập'),
      required: info.required || (layer.optional === false || layer.required ? 'Có' : 'Không'),
      parent: info.parent || (layer.omit_from_parent ? 'Không' : 'Có'),
      note: info.note || ''
    };
  }

  function renderMaterialCodeContract(rules) {
    var wrap = $('mcr_contract');
    if (!wrap) return;
    wrap.innerHTML = '';

    var sep = mcrSeparatorFromRules(rules);
    var layers = normalizeMcrLayerOrder(rules.layers || []).filter(function (layer) {
      return layer && String(layer.key || '').trim();
    });
    if (!layers.length) layers = cloneMaterialCodeLayers(DEFAULT_MATERIAL_CODE_RULES.layers);
    var schema = el('div', { class: 'mcr-schema' });
    layers.forEach(function (layer, index) {
      var info = materialContractInfo(layer || {});
      if (index > 0) schema.appendChild(el('span', { class: 'mcr-sep', text: sep }));
      schema.appendChild(el('span', {
        class: 'mcr-chip' + (info.required === 'Không' ? ' optional' : ''),
        text: info.key + (info.required === 'Không' ? '?' : ''),
        title: info.label + ' - kéo để đổi thứ tự',
        draggable: 'true',
        'data-mcr-chip-index': String(index)
      }));
    });
    schema.appendChild(el('span', { class: 'mcr-sep', text: sep }));
    schema.appendChild(el('span', {
      class: 'mcr-chip conditional',
      text: 'surface_variant?',
      title: 'Hậu tố phủ mặt do card Quy luật phủ mặt .1M/.2M quản lý'
    }));

    var table = el('table', { class: 'mcr-contract-table' });
    var head = el('tr');
    ['Ô mã', 'Tên', 'Kiểu dữ liệu', 'Nguồn giá trị', 'Bắt buộc', 'VL_PARENT', 'Ghi chú'].forEach(function (label) {
      head.appendChild(el('th', { text: label }));
    });
    table.appendChild(head);
    layers.forEach(function (layer) {
      var info = materialContractInfo(layer || {});
      var tr = el('tr');
      [info.key, info.label, info.type, info.source, info.required, info.parent, info.note].forEach(function (text) {
        tr.appendChild(el('td', { text: text }));
      });
      table.appendChild(tr);
    });

    var surf = el('div', { class: 'mcr-contract-note' });
    surf.appendChild(el('strong', { text: 'surface_variant' }));
    surf.appendChild(document.createTextNode(': hậu tố phủ mặt tùy chọn, nằm sau finish_code. Cách nhận token phủ, điều kiện LK/VER và override suffix nằm ở card Quy luật phủ mặt .1M/.2M.'));

    wrap.appendChild(schema);
    wrap.appendChild(table);
    wrap.appendChild(surf);
    wireMcrSchemaDnD(schema);
  }

  function renderMaterialCodeGroupRules(rules) {
    var wrap = $('mcr_group_rules');
    if (!wrap) return;
    wrap.innerHTML = '';

    var head = el('div', { class: 'mcr-group-head' });
    head.appendChild(el('h4', { text: 'Quy luật theo nhóm bề mặt' }));
    head.appendChild(el('p', { class: 'hint', text: 'Sau khi đọc be_mat, hệ thống chọn nhánh bên dưới để kiểm tra finish_code, độ bóng và hậu tố phủ mặt.' }));
    var addBtn = el('button', { class: 'btn xs', type: 'button', text: '+ nhóm' });
    addBtn.addEventListener('click', addMaterialCodeSurfaceGroup);
    head.appendChild(addBtn);
    wrap.appendChild(head);

    var grid = el('div', { class: 'mcr-group-grid' });
    mcrSurfaceGroupKeys(rules).forEach(function (groupKey) {
      var rule = surfaceGroupRulePreview(groupKey, rules);
      if (!rule || !Object.keys(rule).length) return;
      grid.appendChild(buildMaterialCodeGroupCard(groupKey, rule, rules));
    });
    wrap.appendChild(grid);
  }

  function buildMaterialCodeGroupCard(groupKey, rule, rules) {
    var card = el('div', { class: 'mcr-group-card mcr-group-' + groupKey.toLowerCase(), 'data-mcr-group-card': groupKey });
    var head = el('div', { class: 'mcr-group-card-head' });
    head.appendChild(el('input', { class: 'mcr-group-key', 'data-mcr-group-field': 'key', value: groupKey, title: 'Mã nhóm' }));
    head.appendChild(el('input', { class: 'mcr-group-label-input', 'data-mcr-group-field': 'label', value: rule.label || groupKey, title: 'Tên nhóm' }));
    var del = el('button', { class: 'btn del xs', type: 'button', title: 'Xóa nhóm', text: '×' });
    del.addEventListener('click', function () {
      if (card.parentNode) card.parentNode.removeChild(card);
      collectMaterialCodeRulesIntoState();
      updateMaterialCodePreview();
    });
    head.appendChild(del);
    card.appendChild(head);

    card.appendChild(mcrGroupPath(groupKey, rule, rules));

    card.appendChild(mcrGroupFieldBlock('be_mat nhận', buildMcrGroupChips('members', rule.members || [groupKey], 'VD: ' + groupKey)));

    var grid = el('div', { class: 'mcr-group-form-grid' });
    grid.appendChild(mcrGroupSelectField('Đoạn phía sau', 'finish_kind', rule.finish_kind || 'material_code', [
      ['paint_code', 'Mã sơn'],
      ['material_code', 'Mã vật liệu'],
      ['free_text', 'Text tự do']
    ]));
    grid.appendChild(mcrGroupInputField('Nhãn nhánh', 'tail_label', rule.tail_label || mcrTailLabel(rule), 'VD: mã sơn - độ bóng'));
    grid.appendChild(mcrGroupCheckField('Bắt buộc finish_code', 'finish_required', truthyPreview(rule.finish_required)));
    grid.appendChild(mcrGroupCheckField('Cho độ bóng -30', 'allow_gloss', truthyPreview(rule.allow_gloss)));
    grid.appendChild(mcrGroupCheckField('Cho .1M/.2M', 'allow_surface_variant', truthyPreview(rule.allow_surface_variant)));
    card.appendChild(grid);

    card.appendChild(mcrGroupInputField('Pattern finish_code', 'finish_pattern', rule.finish_pattern || '', 'Để trống nếu không kiểm tra pattern'));
    card.appendChild(el('div', { class: 'mcr-group-example', text: mcrGroupExample(groupKey) }));
    return card;
  }

  function mcrSurfaceGroupKeys(rules) {
    var groups = rules.surface_groups || {};
    var preferred = ['SON', 'VER', 'LK', 'MS'];
    var seen = {};
    var keys = [];
    preferred.forEach(function (key) {
      if (groups[key]) { keys.push(key); seen[key] = true; }
    });
    Object.keys(groups).sort().forEach(function (key) {
      if (!seen[key]) keys.push(key);
    });
    return keys;
  }

  function mcrGroupFieldBlock(labelText, child) {
    var block = el('div', { class: 'mcr-group-field' });
    block.appendChild(el('label', { class: 'mcr-group-label', text: labelText }));
    block.appendChild(child);
    return block;
  }

  function mcrGroupInputField(labelText, field, value, placeholder) {
    var block = mcrGroupFieldBlock(labelText, el('input', {
      'data-mcr-group-field': field,
      value: value || '',
      placeholder: placeholder || ''
    }));
    return block;
  }

  function mcrGroupSelectField(labelText, field, value, options) {
    var sel = el('select', { 'data-mcr-group-field': field });
    options.forEach(function (pair) {
      var opt = el('option', { value: pair[0], text: pair[1] });
      if (pair[0] === value) opt.selected = true;
      sel.appendChild(opt);
    });
    return mcrGroupFieldBlock(labelText, sel);
  }

  function mcrGroupCheckField(labelText, field, checked) {
    var label = el('label', { class: 'mcr-group-check' });
    var input = el('input', { type: 'checkbox', 'data-mcr-group-field': field });
    input.checked = !!checked;
    label.appendChild(input);
    label.appendChild(el('span', { text: labelText }));
    return label;
  }

  function buildMcrGroupChip(value) {
    var chip = el('span', { class: 'sfr-tag' });
    chip.appendChild(el('span', { class: 'sfr-tag-label', text: value }));
    var x = el('button', { class: 'sfr-tag-del', type: 'button', title: 'Xoá', text: '×' });
    x.addEventListener('click', function () {
      if (chip.parentNode) chip.parentNode.removeChild(chip);
      collectMaterialCodeRulesIntoState();
      updateMaterialCodePreview();
    });
    chip.appendChild(x);
    return chip;
  }

  function buildMcrGroupChips(field, values, placeholder) {
    var box = el('div', { class: 'sfr-tags mcr-group-tags', 'data-mcr-group-field': field });
    (values || []).forEach(function (value) {
      if (String(value || '').trim()) box.appendChild(buildMcrGroupChip(String(value).trim()));
    });
    var add = el('input', { class: 'sfr-tag-add', placeholder: placeholder || '+ thêm' });
    function commit() {
      var value = add.value.replace(/[|,;]+/g, ' ').replace(/\s+/g, ' ').trim().toUpperCase();
      if (!value) { add.value = ''; return; }
      box.insertBefore(buildMcrGroupChip(value), add);
      add.value = '';
      collectMaterialCodeRulesIntoState();
      updateMaterialCodePreview();
    }
    add.addEventListener('keydown', function (ev) {
      if (ev.key === 'Enter') { ev.preventDefault(); commit(); }
    });
    add.addEventListener('blur', commit);
    box.appendChild(add);
    return box;
  }

  function addMaterialCodeSurfaceGroup() {
    var wrap = $('mcr_group_rules');
    if (!wrap) return;
    var grid = wrap.querySelector('.mcr-group-grid');
    if (!grid) return;
    var key = window.prompt('Mã nhóm bề mặt mới:', '');
    key = String(key || '').trim().toUpperCase().replace(/[^A-Z0-9_]/g, '_');
    if (!key) return;
    if (grid.querySelector('[data-mcr-group-card="' + key + '"]')) {
      window.alert('Nhóm "' + key + '" đã tồn tại.');
      return;
    }
    var rule = {
      label: key,
      members: [key],
      tail_label: 'mã vật liệu',
      finish_kind: 'material_code',
      finish_required: false,
      allow_gloss: false,
      allow_surface_variant: false
    };
    grid.appendChild(buildMaterialCodeGroupCard(key, rule, materialCodeRules()));
    collectMaterialCodeRulesIntoState();
    updateMaterialCodePreview();
  }

  function mcrGroupPath(groupKey, rule, rules) {
    var sep = mcrSeparatorFromRules(rules);
    var path = el('div', { class: 'mcr-group-path' });
    var parts = ['chat_lieu', 'do_day?', 'nha_cung_cap?', groupKey, mcrTailLabel(rule)];
    parts.forEach(function (part, index) {
      if (index > 0) path.appendChild(el('span', { class: 'mcr-sep', text: sep }));
      path.appendChild(el('span', { class: 'mcr-chip' + (part.indexOf('?') >= 0 ? ' optional' : ''), text: part }));
    });
    return path;
  }

  function mcrTailLabel(rule) {
    var base = rule.finish_kind === 'paint_code' ? 'ma_son' : 'ma_vat_lieu';
    var tail = base;
    if (truthyPreview(rule.allow_gloss)) tail += '-do_bong';
    if (truthyPreview(rule.allow_surface_variant)) tail += '.surface_variant?';
    return tail;
  }

  function mcrFinishKindLabel(rule) {
    var kind = rule.finish_kind === 'paint_code' ? 'Mã sơn' : 'Mã vật liệu';
    if (truthyPreview(rule.finish_required)) kind += ' bắt buộc';
    else kind += ' tùy chọn';
    return kind;
  }

  function mcrGroupExample(groupKey) {
    return {
      SON: 'VD: MDFCA.17.AC.SON.30GY 88/014-30',
      VER: 'VD: HDFCA.AC.VER.30GY 88/014.2M',
      LK: 'VD: MDFCA.17.AC.LK.SA7680.1M-BCT',
      MS: 'VD: MDFCA.17.AC.MS.MS502MM'
    }[groupKey] || '';
  }

  function renderMaterialCodeTestBuilder(rules) {
    var wrap = $('mcr_test_builder');
    if (!wrap) return;
    var sep = mcrSeparatorFromRules(rules);
    var sepNode = $('mcr_test_separator');
    if (sepNode) sepNode.value = sep;
    mcrTestBranches = ensureMcrTestBranches();
    mcrTestColumns = ensureMcrTestColumns(rules);
    wrap.innerHTML = '';
    var row = el('div', { class: 'mcr-test-columns', 'data-mcr-test-sep': sep });
    mcrTestColumns.forEach(function (col, index) {
      row.appendChild(buildMcrTestColumn(col, index, sep));
    });
    row.appendChild(el('div', { class: 'mcr-inline-parent-frame', 'aria-hidden': 'true' }, [
      el('span', { class: 'mcr-inline-parent-label', text: 'Parent' })
    ]));
    wrap.appendChild(row);
    positionMcrParentFrame(row);
    syncMcrInlineBranchHeights(wrap);
    updateMcrTestInputFromColumns(false);
  }

  function positionMcrParentFrame(row) {
    row = row || ($('mcr_test_builder') && $('mcr_test_builder').querySelector('.mcr-test-columns'));
    if (!row) return;
    var frame = row.querySelector('.mcr-inline-parent-frame');
    if (!frame) return;
    var parentCols = Array.prototype.filter.call(row.querySelectorAll('.mcr-test-col'), function (col) {
      return col.getAttribute('data-mcr-parent') === '1';
    });
    if (!parentCols.length) {
      frame.hidden = true;
      return;
    }
    frame.hidden = false;
    var rowBox = row.getBoundingClientRect();
    var firstBox = parentCols[0].getBoundingClientRect();
    var lastBox = parentCols[parentCols.length - 1].getBoundingClientRect();
    var pad = 8;
    frame.style.left = (firstBox.left - rowBox.left + row.scrollLeft - pad) + 'px';
    frame.style.top = '-8px';
    frame.style.width = (lastBox.right - firstBox.left + pad * 2) + 'px';
    frame.style.height = (Math.max(0, row.scrollHeight - 4)) + 'px';
  }

  function ensureMcrTestBranches() {
    if (mcrTestBranches) return mcrTestBranches;
    var saved = state.global && state.global.material_code_rules && state.global.material_code_rules.test_branches;
    if (Array.isArray(saved) && saved.length) {
      mcrTestBranches = saved.map(normalizeMcrTestBranch);
      return mcrTestBranches;
    }
    mcrTestBranches = [
      {
        be_mat_label: 'Sơn',
        finish_label: 'Mã sơn',
        variant_label: 'surface_variant 1',
        be_mat: ['SON'],
        finish_code: ['string'],
        surface_variant: []
      },
      {
        be_mat_label: 'Laminate',
        finish_label: 'Mã vật liệu',
        variant_label: 'surface_variant 2',
        be_mat: ['LK'],
        finish_code: ['string'],
        surface_variant: ['1M-BCT', '2M']
      },
      {
        be_mat_label: 'Veneer',
        finish_label: 'Mã sơn',
        variant_label: 'surface_variant 3',
        be_mat: ['VER', 'VERKT'],
        finish_code: ['string'],
        surface_variant: ['1M', '2M']
      },
      {
        be_mat_label: 'Melamine',
        finish_label: 'Mã vật liệu',
        variant_label: 'surface_variant 4',
        be_mat: ['MS'],
        finish_code: ['string'],
        surface_variant: []
      }
    ];
    return mcrTestBranches;
  }

  function normalizeMcrTestBranch(branch, index) {
    branch = branch || {};
    index = isFinite(index) ? index : 0;
    return {
      be_mat_label: String(branch.be_mat_label || ('Be_mat ' + (index + 1))).trim(),
      finish_label: String(branch.finish_label || ('finish_code ' + (index + 1))).trim(),
      variant_label: String(branch.variant_label || ('surface_variant ' + (index + 1))).trim(),
      be_mat: normalizeMcrTestValues(branch.be_mat || []),
      finish_code: normalizeMcrTestValues(branch.finish_code || []),
      surface_variant: normalizeMcrTestValues(branch.surface_variant || [])
    };
  }

  function buildMcrTestBranchPanel() {
    var panel = el('div', { class: 'mcr-branch-panel' });
    var head = el('div', { class: 'mcr-branch-head' });
    head.appendChild(el('div', { class: 'mcr-branch-title', text: 'Nhánh be_mat → finish_code → surface_variant' }));
    head.appendChild(el('button', { class: 'btn xs', type: 'button', text: '+ nhánh', 'data-mcr-test-action': 'add-branch' }));
    panel.appendChild(head);

    var board = el('div', { class: 'mcr-branch-flow-board' });
    var labels = el('div', { class: 'mcr-branch-flow-labels' });
    labels.appendChild(el('span', { text: 'be_mat' }));
    labels.appendChild(el('span', { text: '' }));
    labels.appendChild(el('span', { text: 'finish_code' }));
    labels.appendChild(el('span', { text: '' }));
    labels.appendChild(el('span', { text: 'surface_variant' }));
    board.appendChild(labels);
    ensureMcrTestBranches().forEach(function (branch, index) {
      board.appendChild(buildMcrTestBranch(branch, index));
    });
    panel.appendChild(board);
    return panel;
  }

  function buildMcrTestBranch(branch, index) {
    var card = el('div', { class: 'mcr-branch-card mcr-branch-flow-row', 'data-mcr-branch-index': String(index) });
    var head = el('div', { class: 'mcr-branch-card-head' });
    head.appendChild(el('strong', { text: 'Nhánh ' + (index + 1) }));
    head.appendChild(el('button', { class: 'btn xs del', type: 'button', title: 'Xóa nhánh', text: '×', 'data-mcr-test-action': 'delete-branch' }));
    card.appendChild(head);

    var flow = el('div', { class: 'mcr-branch-flow' });
    flow.appendChild(buildMcrBranchColumn('be_mat', branch.be_mat_label || ('Be_mat ' + (index + 1)), branch.be_mat || []));
    flow.appendChild(el('div', { class: 'mcr-branch-arrow', text: '→' }));
    flow.appendChild(buildMcrBranchColumn('finish_code', branch.finish_label || ('finish_code ' + (index + 1)), branch.finish_code || []));
    flow.appendChild(el('div', { class: 'mcr-branch-arrow', text: '→' }));
    flow.appendChild(buildMcrBranchColumn('surface_variant', branch.variant_label || ('surface_variant ' + (index + 1)), branch.surface_variant || []));
    card.appendChild(flow);
    return card;
  }

  function buildMcrBranchColumn(kind, label, values) {
    var col = el('div', { class: 'mcr-branch-col', 'data-mcr-branch-kind': kind });
    col.appendChild(el('input', { class: 'mcr-branch-label', value: label || kind, 'data-mcr-branch-label': kind }));
    var list = el('div', { class: 'mcr-branch-values' });
    normalizeMcrTestValues(values).forEach(function (value, index) {
      list.appendChild(buildMcrBranchValue(value, index));
    });
    col.appendChild(list);
    col.appendChild(el('button', { class: 'btn xs mcr-branch-add-value', type: 'button', text: '+ giá trị', 'data-mcr-test-action': 'add-branch-value' }));
    return col;
  }

  function buildMcrBranchValue(value, index) {
    var item = el('div', { class: 'mcr-branch-value' });
    item.appendChild(el('span', { class: 'mcr-branch-value-order', text: String(index + 1) }));
    item.appendChild(el('input', { value: value || '', 'data-mcr-branch-value': '1', placeholder: 'Không có giá trị' }));
    item.appendChild(el('button', { class: 'btn xs del', type: 'button', title: 'Xóa giá trị', text: '×', 'data-mcr-test-action': 'delete-branch-value' }));
    return item;
  }

  function ensureMcrTestColumns(rules) {
    var baseCols = normalizeMcrLayerOrder(rules.layers || []).filter(function (layer) {
      return layer && String(layer.key || '').trim();
    }).map(function (layer) {
      return {
        key: String(layer.key || '').trim(),
        label: String(layer.label || layer.key || '').trim(),
        parent: !layer.omit_from_parent,
        virtual: false,
        values: []
      };
    });
    baseCols.push({ key: 'surface_variant', label: 'surface_variant?', parent: false, virtual: true, values: [] });

    if (mcrTestColumns && mcrTestColumns.length) {
      var byKey = {};
      var used = {};
      baseCols.forEach(function (col) { byKey[col.key] = col; });
      var merged = mcrTestColumns.map(function (old) {
        var col = byKey[old.key] || old;
        used[col.key] = true;
        var values = mcrTestColumnIsSystemValue(col.key)
          ? mcrDefaultValuesForColumn(col.key, rules)
          : normalizeMcrTestValues(old.values || (old.value ? [old.value] : mcrDefaultValuesForColumn(col.key, rules)));
        return Object.assign({}, col, { parent: old.parent != null ? !!old.parent : !!col.parent, values: values });
      });
      baseCols.forEach(function (col) {
        if (used[col.key]) return;
        var old = byKey[col.key] || {};
        var values = normalizeMcrTestValues(old.values || (old.value ? [old.value] : mcrDefaultValuesForColumn(col.key, rules)));
        merged.push(Object.assign({}, col, { values: values }));
      });
      return merged;
    }

    var parsed = parseMaterialCodePreview(($('mcr_test_input') && $('mcr_test_input').value) || '', rules);
    return baseCols.map(function (col) {
      var parsedValue = col.key === 'surface_variant' ? (parsed.surface_variant || '') : (parsed.layers[col.key] || '');
      col.values = normalizeMcrTestValues(mcrDefaultValuesForColumn(col.key, rules));
      if (parsedValue && col.values.indexOf(parsedValue) < 0) col.values.unshift(parsedValue);
      return col;
    });
  }

  function buildMcrTestColumn(col, index, sep) {
    var box = el('div', {
      class: 'mcr-test-col' + (col.parent ? ' mcr-parent-member' : '') + (mcrInlineBranchKind(col.key) ? ' mcr-branch-host' : ''),
      'data-mcr-test-index': String(index),
      'data-mcr-test-key': col.key || '',
      'data-mcr-parent': col.parent ? '1' : '0',
      'data-mcr-test-sep': sep
    });
    var card = el('div', { class: 'mcr-test-token-card' });
    card.appendChild(el('span', { class: 'mh-card-drag-handle mcr-test-drag', draggable: 'true', title: 'Kéo cột', text: '⋮⋮' }));
    card.appendChild(el('input', {
      class: 'mcr-test-key-chip',
      'data-mcr-test-field': 'key',
      value: col.key || '',
      placeholder: 'ten_o'
    }));
    var del = el('button', { class: 'btn xs del mcr-test-delete', type: 'button', title: 'Xóa ô test', text: '×', 'data-mcr-test-action': 'delete' });
    card.appendChild(del);
    box.appendChild(card);

    var values = normalizeMcrTestValues(col.values || (col.value ? [col.value] : []));
    if (mcrInlineBranchKind(col.key)) {
      box.appendChild(buildMcrInlineBranchColumn(col.key));
    } else {
      var list = el('div', { class: 'mcr-test-value-list', 'data-mcr-test-values': String(index) });
      values.forEach(function (value, valueIndex) {
        list.appendChild(buildMcrTestValueCard(value, valueIndex));
      });
      box.appendChild(list);
      box.appendChild(el('button', { class: 'btn xs mcr-test-add-value', type: 'button', text: '+ giá trị', 'data-mcr-test-action': 'add-value' }));
    }
    return box;
  }

  function mcrInlineBranchKind(key) {
    key = String(key || '').trim();
    return key === 'be_mat' || key === 'finish_code' || key === 'surface_variant';
  }

  function buildMcrInlineBranchColumn(kind) {
    var wrap = el('div', { class: 'mcr-inline-branch-list', 'data-mcr-inline-branch-kind': kind });
    ensureMcrTestBranches().forEach(function (branch, index) {
      wrap.appendChild(buildMcrInlineBranchCell(kind, branch, index));
    });
    if (kind === 'be_mat') {
      wrap.appendChild(el('button', { class: 'btn xs mcr-inline-add-branch', type: 'button', text: '+ nhánh', 'data-mcr-test-action': 'add-branch' }));
    }
    return wrap;
  }

  function buildMcrInlineBranchCell(kind, branch, index) {
    var labelKey = kind === 'be_mat' ? 'be_mat_label' : (kind === 'finish_code' ? 'finish_label' : 'variant_label');
    var fallback = kind === 'be_mat' ? 'Be_mat ' : (kind === 'finish_code' ? 'finish_code ' : 'surface_variant ');
    var values = normalizeMcrTestValues(branch[kind] || []);
    var cell = el('div', {
      class: 'mcr-inline-branch-cell',
      'data-mcr-branch-index': String(index),
      'data-mcr-branch-kind': kind
    });
    var head = el('div', { class: 'mcr-inline-branch-head' });
    head.appendChild(el('input', {
      class: 'mcr-branch-label',
      value: branch[labelKey] || (fallback + (index + 1)),
      'data-mcr-branch-label': kind
    }));
    if (kind === 'be_mat') {
      head.appendChild(el('button', { class: 'btn xs del', type: 'button', title: 'Xóa nhánh', text: '×', 'data-mcr-test-action': 'delete-branch' }));
    }
    cell.appendChild(head);
    var list = el('div', { class: 'mcr-branch-values' });
    values.forEach(function (value, valueIndex) {
      list.appendChild(buildMcrBranchValue(value, valueIndex));
    });
    cell.appendChild(list);
    cell.appendChild(el('button', { class: 'btn xs mcr-branch-add-value', type: 'button', text: '+ giá trị', 'data-mcr-test-action': 'add-branch-value' }));
    return cell;
  }

  function buildMcrTestValueCard(value, index) {
    var item = el('div', { class: 'mcr-test-value-card', 'data-mcr-value-index': String(index) });
    item.appendChild(el('span', { class: 'mh-card-drag-handle mcr-test-value-drag', draggable: 'true', title: 'Kéo giá trị', text: '⋮⋮' }));
    item.appendChild(el('span', { class: 'mcr-test-value-order', text: String(index + 1) }));
    item.appendChild(el('input', {
      class: 'mcr-test-value',
      'data-mcr-test-value': '1',
      value: value || '',
      placeholder: 'Giá trị'
    }));
    item.appendChild(el('button', { class: 'btn xs del mcr-test-value-delete', type: 'button', title: 'Xóa giá trị', text: '×', 'data-mcr-test-action': 'delete-value' }));
    return item;
  }

  function collectMcrTestColumnsFromDom() {
    var wrap = $('mcr_test_builder');
    if (!wrap) return mcrTestColumns || [];
    return Array.prototype.map.call(wrap.querySelectorAll('.mcr-test-col'), function (col) {
      var key = mcrTestFieldValue(col, 'key') || 'cell';
      var values = Array.prototype.map.call(col.querySelectorAll('[data-mcr-test-value]'), function (input) {
        return String(input.value || '').trim();
      }).filter(function (value) { return value; });
      return {
        key: key,
        label: key,
        value: values[0] || '',
        values: values,
        parent: col.getAttribute('data-mcr-parent') === '1',
        virtual: key === 'surface_variant'
      };
    });
  }

  function collectMcrTestBranchesFromDom() {
    var wrap = $('mcr_test_builder');
    if (!wrap) return mcrTestBranches || [];
    var inlineCells = wrap.querySelectorAll('.mcr-inline-branch-cell[data-mcr-branch-index]');
    if (inlineCells.length) {
      var maxIndex = -1;
      Array.prototype.forEach.call(inlineCells, function (cell) {
        var index = parseInt(cell.getAttribute('data-mcr-branch-index'), 10);
        if (isFinite(index) && index > maxIndex) maxIndex = index;
      });
      var branches = [];
      for (var i = 0; i <= maxIndex; i++) {
        branches.push({
          be_mat_label: mcrInlineBranchLabel(wrap, i, 'be_mat') || ('Be_mat ' + (i + 1)),
          finish_label: mcrInlineBranchLabel(wrap, i, 'finish_code') || ('finish_code ' + (i + 1)),
          variant_label: mcrInlineBranchLabel(wrap, i, 'surface_variant') || ('surface_variant ' + (i + 1)),
          be_mat: mcrInlineBranchValues(wrap, i, 'be_mat'),
          finish_code: mcrInlineBranchValues(wrap, i, 'finish_code'),
          surface_variant: mcrInlineBranchValues(wrap, i, 'surface_variant')
        });
      }
      return branches;
    }
    return Array.prototype.map.call(wrap.querySelectorAll('.mcr-branch-card'), function (card, index) {
      return {
        be_mat_label: mcrBranchLabel(card, 'be_mat') || ('Be_mat ' + (index + 1)),
        finish_label: mcrBranchLabel(card, 'finish_code') || ('finish_code ' + (index + 1)),
        variant_label: mcrBranchLabel(card, 'surface_variant') || ('surface_variant ' + (index + 1)),
        be_mat: mcrBranchValues(card, 'be_mat'),
        finish_code: mcrBranchValues(card, 'finish_code'),
        surface_variant: mcrBranchValues(card, 'surface_variant')
      };
    });
  }

  function mcrInlineBranchCell(root, index, kind) {
    return root.querySelector('.mcr-inline-branch-cell[data-mcr-branch-index="' + index + '"][data-mcr-branch-kind="' + kind + '"]');
  }

  function mcrInlineBranchLabel(root, index, kind) {
    var cell = mcrInlineBranchCell(root, index, kind);
    var input = cell && cell.querySelector('[data-mcr-branch-label="' + kind + '"]');
    return input ? String(input.value || '').trim() : '';
  }

  function mcrInlineBranchValues(root, index, kind) {
    var cell = mcrInlineBranchCell(root, index, kind);
    if (!cell) return [];
    return Array.prototype.map.call(cell.querySelectorAll('[data-mcr-branch-value]'), function (input) {
      return String(input.value || '').trim();
    }).filter(function (value) { return value; });
  }

  function setMcrTestParent(key, parent) {
    key = String(key || '').trim();
    if (!key) return;
    mcrTestColumns = collectMcrTestColumnsFromDom().map(function (col) {
      if (col.key === key && !col.virtual) col.parent = !!parent;
      return col;
    });
  }

  function collectMcrTestLayerRules(fallbackLayers) {
    var wrap = $('mcr_test_builder');
    if (!wrap || !wrap.querySelector('.mcr-test-col')) return normalizeMcrLayerOrder(fallbackLayers || []);
    var oldByKey = {};
    materialCodeLayerList(fallbackLayers || []).forEach(function (layer) {
      oldByKey[String(layer.key || '').trim()] = layer;
    });
    var layers = [];
    collectMcrTestColumnsFromDom().forEach(function (col) {
      var key = String(col.key || '').trim();
      if (!key || key === 'surface_variant') return;
      var old = oldByKey[key] || {};
      var layer = Object.assign({}, old, {
        key: key,
        label: old.label || col.label || key,
        omit_from_parent: !col.parent
      });
      if (!layer.label) layer.label = key;
      if (key === 'do_day') {
        layer.role = layer.role || 'thickness';
        layer.pattern = layer.pattern || MCR_NUMBER_PATTERN;
        layer.optional = true;
      }
      if (key === 'finish_code') {
        layer.role = layer.role || 'finish';
        layer.capture_rest = true;
        layer.optional = true;
      }
      if (!layer.omit_from_parent) delete layer.omit_from_parent;
      layers.push(layer);
    });
    return normalizeMcrLayerOrder(layers);
  }

  function mcrBranchLabel(root, kind) {
    var node = root.querySelector('[data-mcr-branch-label="' + kind + '"]');
    return node ? String(node.value || '').trim() : '';
  }

  function mcrBranchValues(root, kind) {
    var col = root.querySelector('[data-mcr-branch-kind="' + kind + '"]');
    if (!col) return [];
    return Array.prototype.map.call(col.querySelectorAll('[data-mcr-branch-value]'), function (input) {
      return String(input.value || '').trim();
    }).filter(function (value) { return value; });
  }

  function mcrTestFieldValue(root, field) {
    var node = root.querySelector('[data-mcr-test-field="' + field + '"]');
    return node ? String(node.value || '').trim() : '';
  }

  function updateMcrTestInputFromColumns(updatePreview) {
    var wrap = $('mcr_test_builder');
    mcrTestBranches = collectMcrTestBranchesFromDom();
    mcrTestColumns = collectMcrTestColumnsFromDom();
    var sep = mcrSeparatorFromInput('mcr_segment_separator', '.');
    var values = mcrTestColumns.map(function (col) {
      return String(pcrValueText((col.values && col.values[0]) || col.value || '')).trim();
    }).filter(function (value) { return value; });
    var input = $('mcr_test_input');
    if (input) input.value = values.join(sep);
    var sepNode = $('mcr_test_separator');
    if (sepNode && sepNode.value !== sep) sepNode.value = sep;
    var row = wrap ? wrap.querySelector('.mcr-test-columns') : null;
    if (row) row.setAttribute('data-mcr-test-sep', sep);
    Array.prototype.forEach.call(wrap ? wrap.querySelectorAll('.mcr-test-col') : [], function (col) {
      col.setAttribute('data-mcr-test-sep', sep);
    });
    refreshMcrTestColumnOrder();
    if (updatePreview !== false) updateMaterialCodePreview();
  }

  function syncMcrSegmentSeparator(value, updatePreview) {
    var sep = String(value || '').trim();
    setValue('mcr_segment_separator', sep);
    setValue('mcr_test_separator', sep);
    if (!state.global.material_code_rules) state.global.material_code_rules = {};
    state.global.material_code_rules.segment_separator = sep;
    var wrap = $('mcr_test_builder');
    var row = wrap ? wrap.querySelector('.mcr-test-columns') : null;
    if (row) row.setAttribute('data-mcr-test-sep', sep);
    Array.prototype.forEach.call(wrap ? wrap.querySelectorAll('.mcr-test-col') : [], function (col) {
      col.setAttribute('data-mcr-test-sep', sep);
    });
    updateMcrTestInputFromColumns(updatePreview);
  }

  function refreshMcrTestColumnOrder() {
    var wrap = $('mcr_test_builder');
    if (!wrap) return;
    Array.prototype.forEach.call(wrap.querySelectorAll('.mcr-test-col'), function (col, index) {
      col.setAttribute('data-mcr-test-index', String(index));
      Array.prototype.forEach.call(col.querySelectorAll('.mcr-test-value-card'), function (item, valueIndex) {
        item.setAttribute('data-mcr-value-index', String(valueIndex));
        var badge = item.querySelector('.mcr-test-value-order');
        if (badge) badge.textContent = String(valueIndex + 1);
      });
    });
    refreshMcrBranchOrders(wrap);
    positionMcrParentFrame(wrap.querySelector('.mcr-test-columns'));
  }

  function refreshMcrBranchOrders(wrap) {
    Array.prototype.forEach.call((wrap || document).querySelectorAll('.mcr-branch-card'), function (card, index) {
      card.setAttribute('data-mcr-branch-index', String(index));
      var title = card.querySelector('.mcr-branch-card-head strong');
      if (title) title.textContent = 'Bảng ' + (index + 1);
      Array.prototype.forEach.call(card.querySelectorAll('.mcr-branch-values'), function (list) {
        Array.prototype.forEach.call(list.querySelectorAll('.mcr-branch-value'), function (item, valueIndex) {
          var badge = item.querySelector('.mcr-branch-value-order');
          if (badge) badge.textContent = String(valueIndex + 1);
        });
      });
    });
    Array.prototype.forEach.call((wrap || document).querySelectorAll('.mcr-inline-branch-list'), function (list) {
      Array.prototype.forEach.call(list.querySelectorAll('.mcr-inline-branch-cell'), function (cell, index) {
        Array.prototype.forEach.call(cell.querySelectorAll('.mcr-branch-value'), function (item, valueIndex) {
          var badge = item.querySelector('.mcr-branch-value-order');
          if (badge) badge.textContent = String(valueIndex + 1);
        });
      });
    });
    syncMcrInlineBranchHeights(wrap);
  }

  function syncMcrInlineBranchHeights(root) {
    root = root || $('mcr_test_builder') || document;
    var cells = Array.prototype.slice.call(root.querySelectorAll('.mcr-inline-branch-cell[data-mcr-branch-index]'));
    if (!cells.length) return;
    var byIndex = {};
    cells.forEach(function (cell) {
      cell.style.minHeight = '';
      var index = cell.getAttribute('data-mcr-branch-index');
      if (!byIndex[index]) byIndex[index] = [];
      byIndex[index].push(cell);
    });
    Object.keys(byIndex).forEach(function (index) {
      var maxHeight = 0;
      byIndex[index].forEach(function (cell) {
        maxHeight = Math.max(maxHeight, cell.getBoundingClientRect().height);
      });
      if (maxHeight <= 0) return;
      byIndex[index].forEach(function (cell) {
        cell.style.minHeight = Math.ceil(maxHeight) + 'px';
      });
    });
  }

  function refreshMcrSystemColumnValues(rules) {
    var wrap = $('mcr_test_builder');
    if (!wrap) return;
    mcrTestBranches = collectMcrTestBranchesFromDom();
    Array.prototype.forEach.call(wrap.querySelectorAll('.mcr-test-col'), function (col) {
      var key = mcrTestFieldValue(col, 'key');
      if (!mcrTestColumnIsSystemValue(key)) return;
      var list = col.querySelector('.mcr-test-value-list');
      if (!list) return;
      list.innerHTML = '';
      mcrDefaultValuesForColumn(key, rules).forEach(function (value, index) {
        list.appendChild(buildMcrTestValueCard(value, index));
      });
    });
    refreshMcrTestColumnOrder();
  }

  function addMcrTestCell() {
    var wrap = $('mcr_test_builder');
    if (!wrap) return;
    mcrTestColumns = collectMcrTestColumnsFromDom();
    var index = 1;
    var used = {};
    mcrTestColumns.forEach(function (col) { used[String(col.key || '').trim()] = true; });
    while (used['cot_moi_' + index]) index++;
    var key = 'cot_moi_' + index;
    var label = key;
    mcrTestColumns.push({ key: key, label: label, values: [], virtual: true });
    renderMaterialCodeTestBuilder(collectMaterialCodeRules());
    var inputs = wrap.querySelectorAll('.mcr-test-key-chip');
    if (inputs.length) {
      inputs[inputs.length - 1].focus();
      inputs[inputs.length - 1].select();
    }
  }

  function startMcrTestDrag(ev) {
    var target = ev.target && ev.target.closest ? ev.target : null;
    if (!target) return;
    var valueHandle = target.closest('.mcr-test-value-drag');
    var colHandle = target.closest('.mcr-test-drag');
    if (valueHandle) {
      var item = valueHandle.closest('.mcr-test-value-card');
      var list = valueHandle.closest('.mcr-test-value-list');
      if (!item || !list) return;
      mcrTestDrag = { type: 'value', node: item, list: list };
      item.classList.add('mcr-dragging');
    } else if (colHandle) {
      var col = colHandle.closest('.mcr-test-col');
      var list = colHandle.closest('.mcr-test-columns');
      if (!col || !list) return;
      mcrTestDrag = {
        type: 'column',
        node: col,
        list: list,
        key: mcrTestFieldValue(col, 'key'),
        parent: col.getAttribute('data-mcr-parent') === '1'
      };
      col.classList.add('mcr-dragging');
    } else {
      ev.preventDefault();
      return;
    }
    if (ev.dataTransfer) {
      ev.dataTransfer.effectAllowed = 'move';
      ev.dataTransfer.setData('text/plain', 'mcr-test');
    }
  }

  function dragOverMcrTest(ev) {
    if (!mcrTestDrag || !mcrTestDrag.node) return;
    var target = ev.target && ev.target.closest ? ev.target : null;
    if (!target) return;
    var list = mcrTestDrag.type === 'column'
      ? target.closest('.mcr-test-columns')
      : target.closest('.mcr-test-value-list');
    if (!list || list !== mcrTestDrag.list) return;
    ev.preventDefault();
    if (ev.dataTransfer) ev.dataTransfer.dropEffect = 'move';
    var after = mcrTestDrag.type === 'column'
      ? mcrTestColumnAfterPointer(list, ev.clientX, mcrTestDrag.node)
      : mcrTestValueAfterPointer(list, ev.clientY, mcrTestDrag.node);
    if (after) list.insertBefore(mcrTestDrag.node, after);
    else list.appendChild(mcrTestDrag.node);
    refreshMcrTestColumnOrder();
  }

  function dropMcrTest(ev) {
    if (!mcrTestDrag) return;
    ev.preventDefault();
    clearMaterialCodeDropMarks($('mcr_test_builder') || document);
    normalizeMcrParentAfterColumnDrop(mcrTestDrag);
    mcrTestColumns = collectMcrTestColumnsFromDom();
    mcrTestDrag = null;
    collectMaterialCodeRulesIntoState();
    updateMcrTestInputFromColumns(true);
  }

  function endMcrTestDrag() {
    normalizeMcrParentAfterColumnDrop(mcrTestDrag);
    clearMaterialCodeDropMarks($('mcr_test_builder') || document);
    mcrTestDrag = null;
    mcrTestColumns = collectMcrTestColumnsFromDom();
    collectMaterialCodeRulesIntoState();
    updateMcrTestInputFromColumns(true);
  }

  function normalizeMcrParentAfterColumnDrop(drag) {
    if (!drag || drag.type !== 'column' || !drag.node) return;
    var row = $('mcr_test_builder') && $('mcr_test_builder').querySelector('.mcr-test-columns');
    if (!row || !row.contains(drag.node)) return;
    var cols = Array.prototype.slice.call(row.querySelectorAll('.mcr-test-col'));
    var index = cols.indexOf(drag.node);
    if (index < 0) return;

    var otherParentIndexes = [];
    cols.forEach(function (col, colIndex) {
      if (col === drag.node) return;
      if (col.getAttribute('data-mcr-parent') === '1') otherParentIndexes.push(colIndex);
    });
    if (!otherParentIndexes.length) return;

    var min = Math.min.apply(Math, otherParentIndexes);
    var max = Math.max.apply(Math, otherParentIndexes);
    var shouldBeParent = drag.parent ? (index >= min && index <= max) : (index > min && index < max);
    drag.node.setAttribute('data-mcr-parent', shouldBeParent ? '1' : '0');
    drag.node.classList.toggle('mcr-parent-member', shouldBeParent);
    positionMcrParentFrame(row);
  }

  function mcrTestColumnAfterPointer(list, x, dragging) {
    var items = Array.prototype.filter.call(list.querySelectorAll('.mcr-test-col'), function (item) {
      return item !== dragging;
    });
    var closest = { offset: Number.NEGATIVE_INFINITY, item: null };
    items.forEach(function (item) {
      var box = item.getBoundingClientRect();
      var offset = x - box.left - box.width / 2;
      if (offset < 0 && offset > closest.offset) closest = { offset: offset, item: item };
    });
    return closest.item;
  }

  function mcrTestValueAfterPointer(list, y, dragging) {
    var items = Array.prototype.filter.call(list.querySelectorAll('.mcr-test-value-card'), function (item) {
      return item !== dragging;
    });
    var closest = { offset: Number.NEGATIVE_INFINITY, item: null };
    items.forEach(function (item) {
      var box = item.getBoundingClientRect();
      var offset = y - box.top - box.height / 2;
      if (offset < 0 && offset > closest.offset) closest = { offset: offset, item: item };
    });
    return closest.item;
  }

  function normalizeMcrTestValues(values) {
    return (values || []).map(function (value) {
      return String(value || '').trim();
    }).filter(function (value) { return value; });
  }

  function mcrDefaultValuesForColumn(key, rules) {
    key = String(key || '').trim();
    if (!key) return [];
    if (key === 'do_day') return ['number'];
    if (key === 'be_mat') return mcrBranchLabels('be_mat_label', 'Be_mat');
    if (key === 'finish_code') return mcrBranchLabels('finish_label', 'finish_code');
    if (key === 'surface_variant') return mcrBranchLabels('variant_label', 'surface_variant');

    var rows = state.global.material_code_mappings || [];
    var values = [];
    rows.forEach(function (row) {
      if (String(row.nhom || '').trim() !== key) return;
      var value = String(row.gia_tri_map || row.value || row.gia_tri || '').trim();
      if (value) values.push(value);
    });
    return values;
  }

  function mcrTestColumnIsSystemValue(key) {
    key = String(key || '').trim();
    return key === 'do_day' || key === 'be_mat' || key === 'finish_code' || key === 'surface_variant';
  }

  function mcrBranchLabels(field, fallback) {
    return ensureMcrTestBranches().map(function (branch, index) {
      return String(branch[field] || (fallback + ' ' + (index + 1))).trim();
    });
  }

  function mcrSurfaceGroupValues(rules) {
    var values = [];
    var groups = rules && rules.surface_groups ? rules.surface_groups : {};
    Object.keys(groups).forEach(function (key) {
      if (values.indexOf(key) < 0) values.push(key);
      (groups[key].members || []).forEach(function (member) {
        member = String(member || '').trim();
        if (member && values.indexOf(member) < 0) values.push(member);
      });
    });
    return values;
  }

  function switchMaterialCodeSubtab(tab) {
    tab = tab === 'test' ? 'test' : 'rules';
    document.querySelectorAll('[data-mcr-subtab]').forEach(function (btn) {
      btn.classList.toggle('active', btn.getAttribute('data-mcr-subtab') === tab);
    });
    var rulesPanel = $('mcr_rules_panel');
    var testPanel = $('mcr_test_panel');
    if (rulesPanel) rulesPanel.classList.toggle('active', tab === 'rules');
    if (testPanel) testPanel.classList.toggle('active', tab === 'test');
    if (tab === 'test') renderMaterialCodeTestBuilder(collectMaterialCodeRules());
  }

  function wireMcrSchemaDnD(schema) {
    if (!schema) return;
    schema.addEventListener('dragstart', startMaterialCodeChipDrag);
    schema.addEventListener('dragover', dragOverMaterialCodeChip);
    schema.addEventListener('dragleave', function (ev) {
      var chip = ev.target && ev.target.closest ? ev.target.closest('[data-mcr-chip-index]') : null;
      if (chip) chip.classList.remove('mcr-drop-target');
    });
    schema.addEventListener('drop', dropMaterialCodeChip);
    schema.addEventListener('dragend', function () { clearMaterialCodeDropMarks(schema); });
  }

  function buildMaterialCodeLayerRow(layer, index) {
    var tr = el('tr', { 'data-mcr-row': String(index), draggable: 'true' });
    tr.appendChild(mcrDragCell(index));
    tr.appendChild(mcrCellInput('key', layer.key || ''));
    tr.appendChild(mcrCellInput('label', layer.label || ''));
    tr.appendChild(mcrRoleCell(layer.role || ''));
    tr.appendChild(mcrPatternCell(layer));
    tr.appendChild(mcrCellCheck('include_in_parent', !layer.omit_from_parent));
    tr.appendChild(mcrCellCheck('optional', layer.optional !== false && !layer.required));

    var actions = el('td');
    [['×', 'delete']].forEach(function (pair) {
      actions.appendChild(el('button', { class: 'btn xs', type: 'button', 'data-mcr-action': pair[1], text: pair[0] }));
    });
    tr.appendChild(actions);
    return tr;
  }

  function mcrDragCell(index) {
    var td = el('td', { class: 'mcr-drag-cell' });
    td.appendChild(el('span', {
      class: 'mh-card-drag-handle mcr-drag-handle',
      title: 'Kéo để đổi thứ tự',
      'data-mcr-drag': String(index),
      text: '⋮⋮'
    }));
    return td;
  }

  function mcrCellInput(field, value) {
    var td = el('td');
    td.appendChild(el('input', { 'data-mcr': field, value: value || '' }));
    return td;
  }

  function mcrCellCheck(field, checked) {
    var td = el('td', { class: 'mcr-center' });
    var input = el('input', { type: 'checkbox', 'data-mcr': field });
    input.checked = !!checked;
    td.appendChild(input);
    return td;
  }

  function mcrRoleCell(value) {
    var td = el('td');
    var sel = el('select', { 'data-mcr': 'role' });
    [['', 'Thường'], ['thickness', 'Độ dày'], ['finish', 'Finish / sơn']].forEach(function (pair) {
      var opt = el('option', { value: pair[0], text: pair[1] });
      if (pair[0] === value) opt.selected = true;
      sel.appendChild(opt);
    });
    td.appendChild(sel);
    return td;
  }

  function mcrPatternKind(layer) {
    if (layer.capture_rest) return 'rest';
    var pattern = String(layer.pattern || '').trim();
    if (pattern === MCR_NUMBER_PATTERN) return 'number';
    if (pattern) return 'custom';
    if (layer.role === 'thickness') return 'number';
    return 'any';
  }

  function mcrPatternCell(layer) {
    var td = el('td', { class: 'mcr-pattern-cell' });
    var kind = mcrPatternKind(layer || {});
    var sel = el('select', { 'data-mcr': 'pattern_kind' });
    [
      ['any', 'Bất kỳ'],
      ['number', 'Số'],
      ['rest', 'Bắt phần còn lại'],
      ['custom', 'Tùy chỉnh regex']
    ].forEach(function (pair) {
      var opt = el('option', { value: pair[0], text: pair[1] });
      if (pair[0] === kind) opt.selected = true;
      sel.appendChild(opt);
    });
    var input = el('input', {
      class: 'mcr-pattern-custom',
      'data-mcr': 'pattern',
      value: kind === 'custom' ? String(layer.pattern || '') : ''
    });
    if (kind !== 'custom') input.hidden = true;
    td.appendChild(sel);
    td.appendChild(input);
    return td;
  }

  function updateMcrPatternVisibility(root) {
    (root || document).querySelectorAll('.mcr-pattern-cell').forEach(function (cell) {
      var kind = mcrValue(cell, 'pattern_kind');
      var input = cell.querySelector('[data-mcr="pattern"]');
      if (input) input.hidden = kind !== 'custom';
    });
  }

  function enforceMcrRowConsistency(row) {
    if (!row) return;
    var roleNode = row.querySelector('[data-mcr="role"]');
    var kindNode = row.querySelector('[data-mcr="pattern_kind"]');
    var includeNode = row.querySelector('[data-mcr="include_in_parent"]');
    var optionalNode = row.querySelector('[data-mcr="optional"]');
    if (!roleNode || !kindNode) return;

    if (roleNode.value === 'thickness') {
      if (kindNode.value === 'any' || kindNode.value === 'rest') kindNode.value = 'number';
      if (includeNode) includeNode.checked = false;
    }
    if (roleNode.value === 'finish') {
      if (kindNode.value === 'any' || kindNode.value === 'number') kindNode.value = 'rest';
      if (includeNode) includeNode.checked = true;
      if (optionalNode) optionalNode.checked = true;
    }
    if (kindNode.value === 'rest') {
      if (!roleNode.value) roleNode.value = 'finish';
      if (includeNode) includeNode.checked = true;
      if (optionalNode) optionalNode.checked = true;
    }
    updateMcrPatternVisibility(row);
  }

  function renderMcrGlossMode(pattern) {
    pattern = String(pattern || '').trim();
    var mode = pattern === MCR_GLOSS_DASH_NUMBER_PATTERN ? 'dash_number' : 'custom';
    setValue('mcr_gloss_mode', mode);
    setValue('mcr_gloss_suffix_regex', pattern || MCR_GLOSS_DASH_NUMBER_PATTERN);
    updateMcrGlossVisibility();
  }

  function updateMcrGlossVisibility() {
    var mode = $('mcr_gloss_mode');
    var input = $('mcr_gloss_suffix_regex');
    if (input) input.hidden = mode && mode.value !== 'custom';
  }

  function collectMcrGlossRegex() {
    var mode = $('mcr_gloss_mode') ? $('mcr_gloss_mode').value : 'dash_number';
    if (mode === 'dash_number') return MCR_GLOSS_DASH_NUMBER_PATTERN;
    return ($('mcr_gloss_suffix_regex') && $('mcr_gloss_suffix_regex').value || MCR_GLOSS_DASH_NUMBER_PATTERN).trim();
  }

  function collectMcrPattern(tr) {
    var kind = mcrValue(tr, 'pattern_kind');
    if (kind === 'number') return MCR_NUMBER_PATTERN;
    if (kind === 'custom') return mcrValue(tr, 'pattern');
    return '';
  }

  function collectMaterialCodeRules() {
    var current = materialCodeRules();
    var rules = mergeMaterialRules(current, {});
    rules.segment_separator = mcrSeparatorFromInput('mcr_segment_separator', mcrSeparatorFromRules(current));
    rules.multi_separators = ($('mcr_multi_separators') && $('mcr_multi_separators').value || '&')
      .split(',').map(function (x) { return x.trim(); }).filter(function (x) { return x; });
    rules.uppercase = $('mcr_uppercase') ? $('mcr_uppercase').checked : true;
    rules.trim_segments = true;
    rules.gloss_suffix_regex = collectMcrGlossRegex();
    rules.single_segment_gloss_is_finish = true;
    rules.surface_groups = collectMaterialCodeSurfaceGroups(current.surface_groups || {});
    rules.test_branches = collectMcrTestBranchesFromDom().map(normalizeMcrTestBranch);
    if (!rules.test_branches.length) rules.test_branches = ensureMcrTestBranches().map(normalizeMcrTestBranch);

    var wrap = $('tbl_material_code_layers');
    if (!wrap || wrap.hidden || !wrap.querySelector('tr[data-mcr-row]')) {
      rules.layers = collectMcrTestLayerRules(current.layers || cloneMaterialCodeLayers(DEFAULT_MATERIAL_CODE_RULES.layers));
      rules.parent_codes = collectMcrGeneratedParentCodes(rules);
      rules.semantic_aliases = collectMcrSemanticAliases(rules, rules.test_branches);
      return rules;
    }
    rules.layers = [];
    wrap.querySelectorAll('tr[data-mcr-row]').forEach(function (tr) {
      enforceMcrRowConsistency(tr);
      var layer = {
        key: mcrValue(tr, 'key'),
        label: mcrValue(tr, 'label'),
        role: mcrValue(tr, 'role'),
        pattern: collectMcrPattern(tr),
        omit_from_parent: !mcrChecked(tr, 'include_in_parent'),
        capture_rest: mcrValue(tr, 'pattern_kind') === 'rest',
        optional: mcrChecked(tr, 'optional')
      };
      if (!layer.key) return;
      if (!layer.role) delete layer.role;
      if (!layer.pattern) delete layer.pattern;
      if (!layer.omit_from_parent) delete layer.omit_from_parent;
      if (!layer.capture_rest) delete layer.capture_rest;
      if (!layer.optional) delete layer.optional;
      rules.layers.push(layer);
    });
    rules.layers = normalizeMcrLayerOrder(rules.layers);
    rules.parent_codes = collectMcrGeneratedParentCodes(rules);
    rules.semantic_aliases = collectMcrSemanticAliases(rules, rules.test_branches);
    return rules;
  }

  function collectMcrSemanticAliases(rules, branches) {
    var aliases = [];
    var byAlias = {};
    var groups = rules && rules.surface_groups ? rules.surface_groups : {};

    function add(alias, info) {
      var label = String(alias || '').trim();
      var key = mcrSemanticKey(label);
      if (!key) return;
      var row = Object.assign({ alias: label, alias_key: key }, info || {});
      aliases.push(row);
      if (!byAlias[key]) byAlias[key] = [];
      byAlias[key].push(row);
    }

    Object.keys(groups).forEach(function (groupKey) {
      var group = groups[groupKey] || {};
      add(groupKey, { kind: 'surface_group', group: groupKey, key: 'be_mat', members: group.members || [] });
      add(group.label, { kind: 'surface_group', group: groupKey, key: 'be_mat', members: group.members || [] });
      (group.members || []).forEach(function (member) {
        add(member, { kind: 'surface_group', group: groupKey, key: 'be_mat', members: group.members || [] });
      });
    });

    (branches || []).forEach(function (branch, index) {
      branch = normalizeMcrTestBranch(branch, index);
      var groupKey = mcrSurfaceGroupFromBranch(branch, rules);
      var groupRule = (groups && groups[groupKey]) || {};
      var finishKind = groupRule.finish_kind || 'material_code';
      add(branch.be_mat_label, {
        kind: 'surface_group',
        group: groupKey,
        key: 'be_mat',
        branch_index: index,
        values: branch.be_mat
      });
      add(branch.finish_label, {
        kind: 'field',
        group: groupKey,
        key: 'finish_code',
        branch_index: index,
        finish_kind: finishKind,
        values: branch.finish_code,
        be_mat: branch.be_mat
      });
      add(branch.variant_label, {
        kind: 'field',
        group: groupKey,
        key: 'surface_variant',
        branch_index: index,
        values: branch.surface_variant,
        be_mat: branch.be_mat
      });
    });

    return {
      aliases: aliases,
      by_alias: byAlias
    };
  }

  function mcrSurfaceGroupFromBranch(branch, rules) {
    var groups = rules && rules.surface_groups ? rules.surface_groups : {};
    var tokens = []
      .concat(branch && branch.be_mat ? branch.be_mat : [])
      .concat(branch && branch.be_mat_label ? [branch.be_mat_label] : []);
    var groupKeys = Object.keys(groups);
    for (var i = 0; i < groupKeys.length; i++) {
      var key = groupKeys[i];
      var group = groups[key] || {};
      var candidates = [key, group.label].concat(group.members || []);
      for (var j = 0; j < tokens.length; j++) {
        for (var k = 0; k < candidates.length; k++) {
          if (mcrSemanticKey(tokens[j]) && mcrSemanticKey(tokens[j]) === mcrSemanticKey(candidates[k])) return key;
        }
      }
    }
    return '';
  }

  function mcrSemanticKey(value) {
    var text = String(value || '').trim();
    if (!text) return '';
    if (text.normalize) text = text.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
    return text.toUpperCase().replace(/\u0110/g, 'D').replace(/[^A-Z0-9]+/g, '_').replace(/^_+|_+$/g, '');
  }

  function pcrFamilyToken(value) {
    var text = String(value || '').trim().toUpperCase();
    if (!text) return '';
    var family = text.match(/^([A-Z]+)(?:\d+[A-Z]?|\.\.\.|\*)?$/);
    return family ? family[1] : text;
  }

  function pcrSeparatorFromRules(rules) {
    return rules && Object.prototype.hasOwnProperty.call(rules, 'segment_separator')
      ? String(rules.segment_separator || '').trim()
      : '_';
  }

  function pcrSeparatorFromInput(id, fallback) {
    var input = $(id);
    return input ? String(input.value || '').trim() : (fallback == null ? '_' : fallback);
  }

  // ---- product_code_rules ----------------------------------------------
  function renderProductCodeRules() {
    pcrColumns = null;
    var rules = productCodeRules();
    setValue('pcr_segment_separator', pcrSeparatorFromRules(rules));
    var upper = $('pcr_uppercase');
    if (upper) upper.checked = rules.uppercase !== false;
    renderProductCodeBuilder(rules);
    renderProductCodeContract(rules);
  }

  function ensureProductCodeColumns(rules) {
    if (pcrColumns && pcrColumns.length) {
      var hasProductCode = pcrColumns.some(function (col) {
        return String(col && col.key || '').trim() === 'product_code';
      });
      if (!hasProductCode) pcrColumns = null;
    }
    if (pcrColumns && pcrColumns.length) {
      ensureProductSuffixColumn();
      return pcrColumns;
    }
    pcrColumns = cloneMaterialCodeLayers((rules || productCodeRules()).layers || DEFAULT_PRODUCT_CODE_RULES.layers).map(function (layer) {
      var key = String(layer.key || '').trim();
      var values = key === 'suffix'
        ? normalizeConfigSuffixRows(layer.values || (layer.value ? [layer.value] : []))
        : normalizeProductCodeValueEntries(layer.values || (layer.value ? [layer.value] : []), false);
      if (key === 'product_code') {
        values = uniqueStrings(values.map(pcrValueText).map(pcrFamilyToken).filter(function (value) { return value; }));
        if (layer.type === 'alnum_code') layer.type = 'text_number';
      }
      if (!values.length && layer.type === 'number') values = ['number'];
      return Object.assign({}, layer, { values: values });
    });
    ensureProductSuffixColumn();
    return pcrColumns;
  }

  function ensureProductSuffixColumn() {
    if (!pcrColumns) pcrColumns = [];
    var entries = normalizeConfigSuffixRows((configData && configData.suffix) || legacySuffixEntriesFromInput());
    var found = pcrColumns.some(function (col) {
      if (String(col && col.key || '').trim() === 'suffix' && entries.length && !(col.values && col.values.length)) {
        col.values = entries;
      }
      return String(col && col.key || '').trim() === 'suffix';
    });
    if (found) return;
    pcrColumns.push({
      key: 'suffix',
      label: 'Tên suffix',
      type: 'text',
      source: 'dictionary',
      required: false,
      optional: true,
      virtual: true,
      values: entries
    });
  }

  function updateProductSuffixColumnModel(entries) {
    entries = normalizeConfigSuffixRows(entries || []);
    if (!pcrColumns) pcrColumns = [];
    var found = false;
    pcrColumns = pcrColumns.map(function (col) {
      if (String(col && col.key || '').trim() !== 'suffix') return col;
      found = true;
      return Object.assign({}, col, { values: entries });
    });
    if (!found) {
      pcrColumns.push({
        key: 'suffix',
        label: 'Tên suffix',
        type: 'text',
        source: 'dictionary',
        required: false,
        optional: true,
        virtual: true,
        values: entries
      });
    }
  }

  function renderProductCodeBuilder(rules) {
    var wrap = $('pcr_builder');
    if (!wrap) return;
    var sep = pcrSeparatorFromRules(rules);
    setValue('pcr_test_separator', sep);
    pcrColumns = ensureProductCodeColumns(rules);
    wrap.innerHTML = '';
    var row = el('div', { class: 'mcr-test-columns pcr-columns', 'data-pcr-sep': sep });
    pcrColumns.forEach(function (col, index) {
      row.appendChild(buildProductCodeColumn(col, index, sep));
    });
    wrap.appendChild(row);
    refreshProductCodeOrder();
  }

  function buildProductCodeColumn(col, index, sep) {
    var box = el('div', {
      class: 'mcr-test-col pcr-col',
      'data-pcr-index': String(index),
      'data-pcr-key': col.key || '',
      'data-pcr-sep': sep
    });
    var card = el('div', { class: 'mcr-test-token-card' });
    card.appendChild(el('span', { class: 'mh-card-drag-handle pcr-drag', draggable: 'true', title: 'Kéo cột', text: '⋮⋮' }));
    card.appendChild(el('input', {
      class: 'mcr-test-key-chip',
      'data-pcr-field': 'key',
      value: col.key || '',
      placeholder: 'ten_o'
    }));
    card.appendChild(el('button', { class: 'btn xs del mcr-test-delete', type: 'button', title: 'Xóa ô', text: '×', 'data-pcr-action': 'delete' }));
    box.appendChild(card);

    var meta = el('div', { class: 'pcr-meta' });
    meta.appendChild(el('input', { 'data-pcr-field': 'label', value: col.label || col.key || '', placeholder: 'Tên hiển thị' }));
    var type = el('select', { 'data-pcr-field': 'type' });
    [
      ['text_number', 'Text + Number'],
      ['text', 'Text'],
      ['number', 'Number'],
      ['free_text', 'String tự do']
    ].forEach(function (opt) {
      var o = el('option', { value: opt[0], text: opt[1] });
      if ((col.type || 'text') === opt[0]) o.selected = true;
      type.appendChild(o);
    });
    meta.appendChild(type);
    var req = el('label', { class: 'pcr-check' });
    var cb = el('input', { type: 'checkbox', 'data-pcr-field': 'required' });
    cb.checked = col.required === true || String(col.required || '').toLowerCase() === 'true';
    req.appendChild(cb);
    req.appendChild(document.createTextNode(' Bắt buộc'));
    meta.appendChild(req);
    box.appendChild(meta);

    var list = el('div', { class: 'mcr-test-value-list', 'data-pcr-values': String(index) });
    var values = col.key === 'suffix'
      ? normalizeConfigSuffixRows(col.values || [])
      : normalizeProductCodeValueEntries(col.values || [], false);
    values.forEach(function (value, valueIndex) {
      list.appendChild(col.key === 'suffix'
        ? buildProductCodeSuffixValueCard(value, valueIndex)
        : buildProductCodeValueCard(value, valueIndex));
    });
    box.appendChild(list);
    box.appendChild(el('button', { class: 'btn xs mcr-test-add-value', type: 'button', text: '+ giá trị', 'data-pcr-action': 'add-value' }));
    return box;
  }

  function buildProductCodeValueCard(value, index) {
    var item = el('div', { class: 'mcr-test-value-card', 'data-pcr-value-index': String(index) });
    item.appendChild(el('span', { class: 'mh-card-drag-handle mcr-test-value-drag pcr-value-drag', draggable: 'true', title: 'Kéo giá trị', text: '⋮⋮' }));
    item.appendChild(el('span', { class: 'mcr-test-value-order', text: String(index + 1) }));
    item.appendChild(el('input', {
      class: 'mcr-test-value',
      'data-pcr-value': '1',
      value: pcrValueText(value),
      placeholder: 'Giá trị'
    }));
    item.appendChild(el('button', { class: 'btn xs del mcr-test-value-delete', type: 'button', title: 'Xóa giá trị', text: '×', 'data-pcr-action': 'delete-value' }));
    return item;
  }

  function buildProductCodeSuffixValueCard(entry, index) {
    var item = el('div', { class: 'mcr-test-value-card pcr-suffix-value-card', 'data-pcr-value-index': String(index) });
    item.appendChild(el('span', { class: 'mh-card-drag-handle mcr-test-value-drag pcr-value-drag', draggable: 'true', title: 'Kéo giá trị', text: '⋮⋮' }));
    item.appendChild(el('span', { class: 'mcr-test-value-order', text: String(index + 1) }));
    item.appendChild(el('input', {
      class: 'mcr-test-value',
      'data-pcr-value': '1',
      'data-suffix-value': '1',
      value: pcrValueText(entry),
      placeholder: 'Tên suffix'
    }));
    item.appendChild(el('input', {
      type: 'number',
      min: '1',
      step: '1',
      class: 'pcr-suffix-shortcut-input',
      'data-suffix-shortcut': '1',
      value: pcrValueShortcut(entry),
      placeholder: 'Số'
    }));
    item.appendChild(el('button', { class: 'btn xs del mcr-test-value-delete', type: 'button', title: 'Xóa suffix', text: '×', 'data-pcr-action': 'delete-value' }));
    return item;
  }

  function collectProductCodeColumnsFromDom() {
    var wrap = $('pcr_builder');
    if (!wrap) return pcrColumns || [];
    return Array.prototype.map.call(wrap.querySelectorAll('.pcr-col'), function (col) {
      var key = pcrFieldValue(col, 'key') || 'cell';
      var type = pcrFieldValue(col, 'type') || 'text';
      var values = key === 'suffix'
        ? (suffixEntriesFromProductColumn(col) || [])
        : Array.prototype.map.call(col.querySelectorAll('[data-pcr-value]'), function (input) {
          return String(input.value || '').trim();
        }).filter(function (value) { return value; });
      if (key === 'product_code') values = uniqueStrings(values.map(pcrFamilyToken).filter(function (value) { return value; }));
      return {
        key: key,
        label: pcrFieldValue(col, 'label') || key,
        type: type,
        source: type === 'number' ? 'number' : (type === 'free_text' ? 'free_text' : (type === 'text_number' || type === 'alnum_code' ? 'pattern' : 'dictionary')),
        required: pcrFieldChecked(col, 'required'),
        optional: !pcrFieldChecked(col, 'required'),
        virtual: key === 'suffix',
        values: values
      };
    }).filter(function (layer) { return layer; });
  }

  function pcrFieldValue(root, field) {
    var node = root.querySelector('[data-pcr-field="' + field + '"]');
    return node ? String(node.value || '').trim() : '';
  }

  function pcrFieldChecked(root, field) {
    var node = root.querySelector('[data-pcr-field="' + field + '"]');
    return !!(node && node.checked);
  }

  function collectProductCodeRules() {
    var current = productCodeRules();
    var rules = mergeMaterialRules(current, {});
    rules.segment_separator = pcrSeparatorFromInput('pcr_segment_separator', pcrSeparatorFromRules(current));
    rules.uppercase = $('pcr_uppercase') ? $('pcr_uppercase').checked : true;
    rules.trim_segments = true;
    rules.layers = collectProductCodeColumnsFromDom();
    if (!rules.layers.length) rules.layers = cloneMaterialCodeLayers(DEFAULT_PRODUCT_CODE_RULES.layers);
    rules.semantic_aliases = collectProductCodeSemanticAliases(rules);
    return rules;
  }

  function collectProductCodeSemanticAliases(rules) {
    var aliases = [];
    var byAlias = {};
    (rules.layers || []).forEach(function (layer, index) {
      [layer.key, layer.label].forEach(function (alias) {
        var key = mcrSemanticKey(alias);
        if (!key) return;
        var row = {
          alias: String(alias || '').trim(),
          alias_key: key,
          kind: 'product_field',
          key: layer.key,
          label: layer.label,
          type: layer.type || 'text',
          index: index
        };
        aliases.push(row);
        if (!byAlias[key]) byAlias[key] = [];
        byAlias[key].push(row);
      });
    });
    return { aliases: aliases, by_alias: byAlias };
  }

  function collectProductCodeRulesIntoState() {
    if ($('pcr_builder')) state.global.product_code_rules = collectProductCodeRules();
    return validateProductCodeRules(state.global.product_code_rules || {});
  }

  function validateProductCodeRules(rules) {
    var errors = [];
    var seen = {};
    (rules.layers || []).forEach(function (layer, index) {
      var rowNo = index + 1;
      var key = String(layer.key || '').trim();
      if (!key) errors.push('Dòng ' + rowNo + ': thiếu Ô mã.');
      if (key && seen[key]) errors.push('Dòng ' + rowNo + ': trùng Ô mã "' + key + '".');
      if (key) seen[key] = true;
      if (!String(layer.label || '').trim()) errors.push('Dòng ' + rowNo + ': thiếu Tên hiển thị.');
    });
    return { ok: errors.length === 0, errors: errors };
  }

  function renderProductCodeContract(rules) {
    var box = $('pcr_contract');
    if (!box) return;
    var sep = pcrSeparatorFromRules(rules);
    var layers = rules.layers || [];
    var html = '<div class="mcr-schema">' + layers.map(function (layer) {
      return '<span class="mcr-chip' + (layer.optional ? ' optional' : '') + '">' + escapeHtml(layer.key || '') + (layer.optional ? '?' : '') + '</span>';
    }).join('<span class="mcr-sep">' + escapeHtml(sep) + '</span>') + '</div>';
    html += '<table class="mcr-contract-table"><thead><tr><th>Ô mã</th><th>Tên</th><th>Kiểu dữ liệu</th><th>Nguồn giá trị</th><th>Bắt buộc</th><th>Ghi chú</th></tr></thead><tbody>';
    layers.forEach(function (layer) {
      html += '<tr>'
        + '<td><code>' + escapeHtml(layer.key || '') + '</code></td>'
        + '<td>' + escapeHtml(layer.label || '') + '</td>'
        + '<td>' + escapeHtml(pcrTypeLabel(layer.type)) + '</td>'
        + '<td>' + escapeHtml(pcrSourceLabel(layer.source || layer.type)) + '</td>'
        + '<td>' + (layer.required ? 'Có' : 'Không') + '</td>'
        + '<td>' + escapeHtml(pcrValuesLabel(layer.values || [])) + '</td>'
        + '</tr>';
    });
    html += '</tbody></table>';
    box.innerHTML = html;
  }

  function pcrTypeLabel(type) {
    if (type === 'text_number' || type === 'alnum_code') return 'Text + Number';
    if (type === 'number') return 'Number';
    if (type === 'free_text') return 'String tự do';
    return 'Text';
  }

  function pcrSourceLabel(source) {
    if (source === 'number') return 'Không dùng từ điển';
    if (source === 'free_text') return 'Không bắt buộc từ điển';
    if (source === 'pattern') return 'Theo pattern';
    return 'Từ điển';
  }

  function syncProductCodeSeparator(value) {
    var sep = String(value || '').trim();
    setValue('pcr_segment_separator', sep);
    setValue('pcr_test_separator', sep);
    if (!state.global.product_code_rules) state.global.product_code_rules = {};
    state.global.product_code_rules.segment_separator = sep;
    var wrap = $('pcr_builder');
    var row = wrap ? wrap.querySelector('.pcr-columns') : null;
    if (row) row.setAttribute('data-pcr-sep', sep);
    Array.prototype.forEach.call(wrap ? wrap.querySelectorAll('.pcr-col') : [], function (col) {
      col.setAttribute('data-pcr-sep', sep);
    });
    collectProductCodeRulesIntoState();
    renderProductCodeContract(productCodeRules());
  }

  function refreshProductCodeOrder() {
    var wrap = $('pcr_builder');
    if (!wrap) return;
    Array.prototype.forEach.call(wrap.querySelectorAll('.pcr-col'), function (col, index) {
      col.setAttribute('data-pcr-index', String(index));
      Array.prototype.forEach.call(col.querySelectorAll('.mcr-test-value-card'), function (item, valueIndex) {
        item.setAttribute('data-pcr-value-index', String(valueIndex));
        var badge = item.querySelector('.mcr-test-value-order');
        if (badge) badge.textContent = String(valueIndex + 1);
      });
    });
  }

  function refreshProductSuffixColumnValues(entries) {
    updateProductSuffixColumnModel(entries);
    var wrap = $('pcr_builder');
    if (!wrap) return;
    var col = null;
    Array.prototype.some.call(wrap.querySelectorAll('.pcr-col'), function (candidate) {
      if (pcrFieldValue(candidate, 'key') === 'suffix') {
        col = candidate;
        return true;
      }
      return false;
    });
    if (!col) return;
    var list = col.querySelector('.mcr-test-value-list');
    if (!list) return;
    list.innerHTML = '';
    normalizeConfigSuffixRows(entries || []).forEach(function (entry, index) {
      list.appendChild(buildProductCodeSuffixValueCard(entry, index));
    });
    refreshProductCodeOrder();
  }

  function addProductCodeCell() {
    pcrColumns = collectProductCodeColumnsFromDom();
    var next = pcrColumns.length + 1;
    pcrColumns.push({ key: 'field_' + next, label: 'Ô ' + next, type: 'text', source: 'dictionary', optional: true, values: [] });
    renderProductCodeBuilder(collectProductCodeRules());
    collectProductCodeRulesIntoState();
    renderProductCodeContract(productCodeRules());
  }

  function startProductCodeDrag(ev) {
    var target = ev.target && ev.target.closest ? ev.target : null;
    if (!target) return;
    var valueHandle = target.closest('.pcr-value-drag');
    var colHandle = target.closest('.pcr-drag');
    if (valueHandle) {
      var item = valueHandle.closest('.mcr-test-value-card');
      var list = valueHandle.closest('.mcr-test-value-list');
      if (!item || !list) return;
      pcrDrag = { type: 'value', item: item, list: list };
      item.classList.add('mcr-dragging');
    } else if (colHandle) {
      var col = colHandle.closest('.pcr-col');
      var cols = colHandle.closest('.pcr-columns');
      if (!col || !cols) return;
      pcrDrag = { type: 'col', item: col, list: cols };
      col.classList.add('mcr-dragging');
    } else {
      ev.preventDefault();
      return;
    }
    if (ev.dataTransfer) {
      ev.dataTransfer.effectAllowed = 'move';
      ev.dataTransfer.setData('text/plain', 'pcr');
    }
  }

  function dragOverProductCode(ev) {
    if (!pcrDrag) return;
    var target = ev.target && ev.target.closest ? ev.target : null;
    if (!target) return;
    var list = pcrDrag.type === 'col'
      ? target.closest('.pcr-columns')
      : target.closest('.mcr-test-value-list');
    if (!list || list !== pcrDrag.list) return;
    ev.preventDefault();
    if (ev.dataTransfer) ev.dataTransfer.dropEffect = 'move';
    var before = pcrDrag.type === 'col'
      ? mcrTestColumnAfterPointer(list, ev.clientX, pcrDrag.item)
      : mcrTestValueAfterPointer(list, ev.clientY, pcrDrag.item);
    if (before) list.insertBefore(pcrDrag.item, before);
    else list.appendChild(pcrDrag.item);
    refreshProductCodeOrder();
  }

  function dropProductCode(ev) {
    if (!pcrDrag) return;
    ev.preventDefault();
    endProductCodeDrag();
  }

  function endProductCodeDrag() {
    var hadDrag = !!pcrDrag;
    var wrap = $('pcr_builder') || document;
    Array.prototype.forEach.call(wrap.querySelectorAll('.mcr-dragging'), function (node) {
      node.classList.remove('mcr-dragging');
    });
    pcrDrag = null;
    refreshProductCodeOrder();
    if (hadDrag) syncProductCodeBuilderState();
  }

  function syncProductCodeBuilderState() {
    pcrColumns = collectProductCodeColumnsFromDom();
    syncSuffixTextarea(suffixEntriesFromDom());
    updateNamePreview();
    collectProductCodeRulesIntoState();
    renderProductCodeContract(productCodeRules());
  }

  function collectMcrGeneratedParentCodes(rules) {
    var sep = String((rules && rules.segment_separator) || '.').trim() || '.';
    var columns = collectMcrTestColumnsFromDom();
    if (!columns || !columns.length) columns = ensureMcrTestColumns(rules || materialCodeRules());
    var branches = collectMcrTestBranchesFromDom();
    if (!branches || !branches.length) branches = ensureMcrTestBranches();
    var prefixes = [''];
    var out = [];

    columns.forEach(function (col) {
      if (!col || !col.parent) return;
      var values = mcrParentValuesForColumn(col, branches, rules);
      if (!values.length) return;
      var next = [];
      prefixes.forEach(function (prefix) {
        values.forEach(function (value) {
          next.push(prefix ? (prefix + sep + value) : value);
        });
      });
      prefixes = uniqueStrings(next);
      out = out.concat(prefixes);
    });
    return uniqueStrings(out);
  }

  function mcrParentValuesForColumn(col, branches, rules) {
    var key = String(col.key || '').trim();
    var values = [];
    if (key === 'be_mat' || key === 'finish_code' || key === 'surface_variant') {
      (branches || []).forEach(function (branch) {
        (branch[key] || []).forEach(function (value) { values.push(value); });
      });
    } else {
      values = col.values || (col.value ? [col.value] : []);
    }
    return uniqueStrings(values.map(function (value) {
      return normalizeMcrParentToken(value, key, rules);
    }).filter(function (value) { return value; }));
  }

  function normalizeMcrParentToken(value, key, rules) {
    var text = String(value || '').trim();
    if (!text) return '';
    var comparable = text.toUpperCase();
    if (key === 'do_day') return '';
    if (comparable === 'NUMBER' || comparable === 'STRING') return '';
    if (/^(BE_MAT|FINISH_CODE|SURFACE_VARIANT)\s*\d+$/i.test(text)) return '';
    if (/\?$/.test(text)) return '';
    return rules && rules.uppercase === false ? text : comparable;
  }

  function collectMaterialCodeSurfaceGroups(fallback) {
    var wrap = $('mcr_group_rules');
    if (!wrap) return mergeMaterialRules(fallback || {}, {});
    var cards = wrap.querySelectorAll('[data-mcr-group-card]');
    if (!cards.length) return mergeMaterialRules(fallback || {}, {});
    var groups = {};
    cards.forEach(function (card) {
      var key = mcrGroupFieldValue(card, 'key').toUpperCase().replace(/[^A-Z0-9_]/g, '_');
      if (!key) return;
      var rule = {
        label: mcrGroupFieldValue(card, 'label') || key,
        members: mcrGroupChipValues(card, 'members'),
        tail_label: mcrGroupFieldValue(card, 'tail_label'),
        finish_kind: mcrGroupFieldValue(card, 'finish_kind') || 'material_code',
        finish_required: mcrGroupFieldChecked(card, 'finish_required'),
        allow_gloss: mcrGroupFieldChecked(card, 'allow_gloss'),
        allow_surface_variant: mcrGroupFieldChecked(card, 'allow_surface_variant'),
        finish_pattern: mcrGroupFieldValue(card, 'finish_pattern')
      };
      if (!rule.members.length) rule.members = [key];
      if (!rule.tail_label) rule.tail_label = mcrTailLabel(rule);
      if (!rule.finish_pattern) delete rule.finish_pattern;
      groups[key] = rule;
    });
    return groups;
  }

  function mcrGroupFieldValue(card, field) {
    var node = card.querySelector('[data-mcr-group-field="' + field + '"]');
    return node ? String(node.value || '').trim() : '';
  }

  function mcrGroupFieldChecked(card, field) {
    var node = card.querySelector('[data-mcr-group-field="' + field + '"]');
    return !!(node && node.checked);
  }

  function mcrGroupChipValues(card, field) {
    var box = card.querySelector('[data-mcr-group-field="' + field + '"]');
    if (!box) return [];
    return Array.prototype.map.call(box.querySelectorAll('.sfr-tag-label'), function (node) {
      return String(node.textContent || '').trim().toUpperCase();
    }).filter(function (value, index, arr) {
      return value && arr.indexOf(value) === index;
    });
  }

  function normalizeMcrLayerOrder(layers) {
    layers = materialCodeLayerList(layers);
    var normal = [];
    var rest = [];
    layers.forEach(function (layer) {
      (layer && layer.capture_rest ? rest : normal).push(layer);
    });
    return normal.concat(rest);
  }

  function mcrValue(root, field) {
    var node = root.querySelector('[data-mcr="' + field + '"]');
    return node ? String(node.value || '').trim() : '';
  }

  function mcrChecked(root, field) {
    var node = root.querySelector('[data-mcr="' + field + '"]');
    return !!(node && node.checked);
  }

  function collectMaterialCodeRulesIntoState() {
    if ($('tbl_material_code_layers')) state.global.material_code_rules = collectMaterialCodeRules();
    return validateMaterialCodeRules(state.global.material_code_rules || {});
  }

  function syncMaterialMappingsToGlobalState() {
    state.global.material_code_mappings = collectTable('ma_vat_lieu_global');
  }

  function validateMaterialCodeRules(rules) {
    var errors = [];
    var warnings = [];
    var seen = {};
    var restCount = 0;
    var layers = materialCodeLayerList(rules.layers);

    if (!layers.length) errors.push('Cần ít nhất 1 lớp mã vật liệu.');
    layers.forEach(function (layer, index) {
      var rowNo = index + 1;
      var key = String(layer.key || '').trim();
      if (!key) errors.push('Dòng ' + rowNo + ': thiếu Mã lớp.');
      else if (!/^[a-z][a-z0-9_]*$/.test(key)) errors.push('Dòng ' + rowNo + ': Mã lớp chỉ dùng a-z, 0-9, dấu _, và bắt đầu bằng chữ.');
      if (key && seen[key]) errors.push('Dòng ' + rowNo + ': Mã lớp "' + key + '" bị trùng.');
      seen[key] = true;
      if (!String(layer.label || '').trim()) warnings.push('Dòng ' + rowNo + ': nên có Tên hiển thị để dễ đọc.');
      if (layer.role === 'thickness' && String(layer.pattern || '') !== MCR_NUMBER_PATTERN) {
        warnings.push('Dòng ' + rowNo + ': Độ dày nên dùng Cách đọc = Số.');
      }
      if (layer.capture_rest) {
        restCount += 1;
        if (index !== layers.length - 1) errors.push('Dòng ' + rowNo + ': "Bắt phần còn lại" phải nằm ở dòng cuối.');
      }
    });
    if (restCount > 1) errors.push('Chỉ được có 1 dòng dùng Cách đọc = Bắt phần còn lại.');

    var box = $('mcr_validation');
    if (box) {
      var lines = errors.concat(warnings);
      box.hidden = lines.length === 0;
      box.className = 'mcr-validation ' + (errors.length ? 'err' : 'warn');
      box.textContent = lines.join('\n');
    }
    return { ok: errors.length === 0, errors: errors, warnings: warnings };
  }

  function addMaterialCodeLayer() {
    collectMaterialCodeRulesIntoState();
    var layers = state.global.material_code_rules.layers || [];
    var key = window.prompt('Mã lớp mới (ví dụ: mau_sac, quy_cach):', '');
    key = String(key || '').trim().toLowerCase().replace(/[^a-z0-9_]/g, '_').replace(/^[^a-z]+/, '');
    if (!key) return;
    if (layers.some(function (layer) { return String(layer.key || '') === key; })) {
      window.alert('Mã lớp "' + key + '" đã tồn tại.');
      return;
    }
    var label = window.prompt('Tên hiển thị:', key) || key;
    var finishIndex = layers.findIndex(function (layer) { return layer.capture_rest || layer.key === 'finish_code'; });
    var row = { key: key, label: label, optional: true };
    if (finishIndex >= 0) layers.splice(finishIndex, 0, row);
    else layers.push(row);
    state.global.material_code_rules.layers = layers;
    renderMaterialCodeRules();
  }

  function materialCodeLayerAction(button) {
    collectMaterialCodeRulesIntoState();
    var tr = button.closest('tr[data-mcr-row]');
    if (!tr) return;
    var index = parseInt(tr.getAttribute('data-mcr-row'), 10);
    var action = button.getAttribute('data-mcr-action');
    var layers = state.global.material_code_rules.layers || [];
    if (action === 'delete') layers.splice(index, 1);
    if (action === 'up' && index > 0) {
      var up = layers[index - 1]; layers[index - 1] = layers[index]; layers[index] = up;
    }
    if (action === 'down' && index < layers.length - 1) {
      var down = layers[index + 1]; layers[index + 1] = layers[index]; layers[index] = down;
    }
    state.global.material_code_rules.layers = layers;
    renderMaterialCodeRules();
  }

  function mcrDragIndexFromEvent(ev) {
    var tr = ev.target && ev.target.closest ? ev.target.closest('tr[data-mcr-row]') : null;
    if (!tr) return -1;
    var index = parseInt(tr.getAttribute('data-mcr-row'), 10);
    return isNaN(index) ? -1 : index;
  }

  function startMaterialCodeLayerDrag(ev) {
    var handle = ev.target && ev.target.closest ? ev.target.closest('[data-mcr-drag]') : null;
    if (!handle) {
      ev.preventDefault();
      return;
    }
    var index = mcrDragIndexFromEvent(ev);
    if (index < 0) return;
    ev.dataTransfer.effectAllowed = 'move';
    ev.dataTransfer.setData('text/plain', String(index));
    var tr = handle.closest('tr[data-mcr-row]');
    if (tr) tr.classList.add('mcr-dragging');
  }

  function dragOverMaterialCodeLayer(ev) {
    var tr = ev.target && ev.target.closest ? ev.target.closest('tr[data-mcr-row]') : null;
    if (!tr) return;
    ev.preventDefault();
    tr.classList.add('mcr-drop-target');
    ev.dataTransfer.dropEffect = 'move';
  }

  function clearMaterialCodeDropMarks(root) {
    (root || document).querySelectorAll('.mcr-drop-target,.mcr-dragging').forEach(function (node) {
      node.classList.remove('mcr-drop-target');
      node.classList.remove('mcr-dragging');
    });
  }

  function dropMaterialCodeLayer(ev) {
    var toIndex = mcrDragIndexFromEvent(ev);
    var fromIndex = parseInt(ev.dataTransfer.getData('text/plain'), 10);
    clearMaterialCodeDropMarks($('tbl_material_code_layers') || document);
    if (isNaN(fromIndex) || toIndex < 0 || fromIndex === toIndex) return;
    ev.preventDefault();
    collectMaterialCodeRulesIntoState();
    var layers = state.global.material_code_rules.layers || [];
    var moved = layers.splice(fromIndex, 1)[0];
    if (!moved) return;
    if (fromIndex < toIndex) toIndex -= 1;
    layers.splice(toIndex, 0, moved);
    layers = normalizeMcrLayerOrder(layers);
    state.global.material_code_rules.layers = layers;
    renderMaterialCodeRules();
  }

  function mcrChipIndexFromEvent(ev) {
    var chip = ev.target && ev.target.closest ? ev.target.closest('[data-mcr-chip-index]') : null;
    if (!chip) return -1;
    var index = parseInt(chip.getAttribute('data-mcr-chip-index'), 10);
    return isNaN(index) ? -1 : index;
  }

  function startMaterialCodeChipDrag(ev) {
    var index = mcrChipIndexFromEvent(ev);
    if (index < 0) return;
    ev.dataTransfer.effectAllowed = 'move';
    ev.dataTransfer.setData('text/plain', String(index));
    ev.dataTransfer.setData('application/x-mh-mcr-chip', String(index));
    var chip = ev.target.closest('[data-mcr-chip-index]');
    if (chip) chip.classList.add('mcr-dragging');
  }

  function dragOverMaterialCodeChip(ev) {
    var chip = ev.target && ev.target.closest ? ev.target.closest('[data-mcr-chip-index]') : null;
    if (!chip) return;
    ev.preventDefault();
    chip.classList.add('mcr-drop-target');
    ev.dataTransfer.dropEffect = 'move';
  }

  function dropMaterialCodeChip(ev) {
    var toIndex = mcrChipIndexFromEvent(ev);
    var fromIndex = parseInt(ev.dataTransfer.getData('application/x-mh-mcr-chip') || ev.dataTransfer.getData('text/plain'), 10);
    var schema = ev.target && ev.target.closest ? ev.target.closest('.mcr-schema') : null;
    clearMaterialCodeDropMarks(schema || document);
    if (isNaN(fromIndex) || toIndex < 0 || fromIndex === toIndex) return;
    ev.preventDefault();
    collectMaterialCodeRulesIntoState();
    var layers = cloneMaterialCodeLayers(state.global.material_code_rules.layers || []);
    var moved = layers.splice(fromIndex, 1)[0];
    if (!moved) return;
    if (fromIndex < toIndex) toIndex -= 1;
    layers.splice(toIndex, 0, moved);
    state.global.material_code_rules.layers = normalizeMcrLayerOrder(layers);
    renderMaterialCodeRules();
  }

  function updateMaterialCodePreview() {
    var out = $('mcr_test_output');
    var input = $('mcr_test_input');
    if (!out || !input) return;
    var rules = collectMaterialCodeRules();
    var parsed = parseMaterialCodePreview(input.value, rules);
    var layerLines = Object.keys(parsed.layers).map(function (key) { return key + ' = ' + parsed.layers[key]; });
    var validationLines = []
      .concat((parsed.validation_errors || []).map(function (line) { return 'ERR: ' + line; }))
      .concat((parsed.validation_warnings || []).map(function (line) { return 'WARN: ' + line; }));
    out.textContent = [
      'Input: ' + parsed.raw,
      'VL_PARENT: ' + parsed.vl_parent,
      'SURFACE_GROUP: ' + parsed.surface_group,
      'SURFACE_VARIANT: ' + parsed.surface_variant,
      'FINISH_CODE: ' + parsed.finish_code,
      'FINISH_BASE: ' + parsed.finish_base,
      'COLOR_CODE: ' + parsed.color_code,
      'DO_BONG: ' + parsed.do_bong,
      'VALID: ' + (parsed.valid ? 'OK' : 'NO'),
      '',
      layerLines.join('\n'),
      '',
      validationLines.join('\n')
    ].join('\n');
  }

  function parseMaterialCodePreview(value, rules) {
    var raw = String(value || '').trim();
    var normalized = rules.uppercase === false ? raw : raw.toUpperCase();
    var sep = mcrSeparatorForParsing(mcrSeparatorFromRules(rules));
    var segments = normalized.split(sep).map(function (x) { return x.trim(); }).filter(function (x) { return x; });
    segments = expandImplicitPaintSurfacePreview(segments, rules);
    var result = {
      raw: raw,
      layers: {},
      vl_parent: '',
      surface_group: '',
      surface_variant: '',
      finish_code: '',
      finish_base: '',
      color_code: '',
      do_bong: '',
      valid: true,
      validation_errors: [],
      validation_warnings: []
    };
    var glossRe = rubyRegexToJs(rules.gloss_suffix_regex || '-(\\d+)\\z');
    if (rules.single_segment_gloss_is_finish !== false && segments.length === 1 && glossRe && glossRe.test(segments[0])) {
      var finishLayer = (rules.layers || []).find(function (layer) {
        return layer.role === 'finish' || layer.key === 'finish_code';
      }) || { key: 'finish_code', role: 'finish' };
      assignMcrPreviewLayer(result, finishLayer, segments[0], rules);
      classifySurfaceGroupPreview(result, rules);
      validateSurfaceGroupPreview(result, rules);
      result.vl_parent = result.finish_code;
      return result;
    }
    var idx = 0;
    (rules.layers || []).forEach(function (layer) {
      var key = layer.key || '';
      if (!key) return;
      if (layer.capture_rest) {
        var rest = segments.slice(idx).join(sep);
        if (rest) assignMcrPreviewLayer(result, layer, rest, rules);
        idx = segments.length;
        return;
      }
      var current = segments[idx] || '';
      if (layer.role === 'thickness') {
        var re = layer.pattern ? rubyRegexToJs(layer.pattern) : null;
        if (!re || re.test(current)) {
          assignMcrPreviewLayer(result, layer, current, rules);
          idx += 1;
        }
        return;
      }
      var layerRe = layer.pattern ? rubyRegexToJs(layer.pattern) : null;
      if (current && (!layerRe || layerRe.test(current))) {
        assignMcrPreviewLayer(result, layer, current, rules);
        idx += 1;
      }
    });
    classifySurfaceGroupPreview(result, rules);
    validateSurfaceGroupPreview(result, rules);
    var parent = [];
    (rules.layers || []).forEach(function (layer) {
      if (layer.omit_from_parent) return;
      var v = result.layers[layer.key || ''];
      if (v) parent.push(v);
    });
    if (!parent.length && result.finish_code) parent.push(result.finish_code);
    result.vl_parent = parent.join(sep);
    return result;
  }

  function expandImplicitPaintSurfacePreview(segments, rules) {
    var parts = (segments || []).slice();
    var token = String(rules.paint_surface_token || 'SON').trim().toUpperCase();
    if (!token || parts.indexOf(token) >= 0) return parts;
    var index = -1;
    for (var i = 0; i < parts.length; i++) {
      if (paintCodePreview(parts[i], rules)) { index = i; break; }
    }
    if (index < 2) return parts;
    if (surfaceTokenPreview(parts[index - 1], rules)) return parts;
    parts.splice(index, 0, token);
    return parts;
  }

  function paintCodePreview(value, rules) {
    var re = rubyRegexToJs(rules.paint_code_regex || '');
    return !!(re && re.test(String(value || '').trim().toUpperCase()));
  }

  function surfaceTokenPreview(value, rules) {
    return !!surfaceGroupForTokenPreview(value, rules);
  }

  function classifySurfaceGroupPreview(result, rules) {
    result.surface_group = surfaceGroupForTokenPreview(result.layers.be_mat, rules);
    result.surface_variant = surfaceVariantFromFinishPreview(result.finish_code, rules);
    result.finish_base = finishBaseWithoutSurfaceVariantPreview(result.finish_code, rules);
  }

  function validateSurfaceGroupPreview(result, rules) {
    var errors = result.validation_errors || [];
    var warnings = result.validation_warnings || [];
    var beMat = String(result.layers.be_mat || '');
    var group = String(result.surface_group || '');
    if (!beMat) {
      warnings.push('Thiếu be_mat: không phân loại được nhóm SON/LK/VER/MS.');
      result.valid = errors.length === 0;
      return;
    }
    if (!group) {
      errors.push('be_mat "' + beMat + '" chưa thuộc nhóm SON/LK/VER/MS.');
      result.valid = false;
      return;
    }
    var rule = surfaceGroupRulePreview(group, rules);
    if (truthyPreview(rule.finish_required) && !result.finish_code) errors.push('Nhóm ' + group + ': thiếu finish_code.');
    if (!truthyPreview(rule.allow_surface_variant) && result.surface_variant) errors.push('Nhóm ' + group + ': không dùng hậu tố phủ mặt 1M/2M.');
    if (!truthyPreview(rule.allow_gloss) && result.do_bong) errors.push('Nhóm ' + group + ': không dùng độ bóng dạng -30.');
    var finishRe = rubyRegexToJs(rule.finish_pattern || '');
    if (finishRe && result.finish_base && !finishRe.test(result.finish_base)) errors.push('Nhóm ' + group + ': finish_code không đúng mẫu.');
    result.valid = errors.length === 0;
  }

  function surfaceGroupRulePreview(group, rules) {
    var groups = rules.surface_groups || {};
    return groups[group] || {};
  }

  function surfaceGroupForTokenPreview(value, rules) {
    var token = mcrComparable(value);
    if (!token) return '';
    var groups = rules.surface_groups || {};
    var keys = Object.keys(groups);
    for (var i = 0; i < keys.length; i++) {
      var group = groups[keys[i]] || {};
      var members = group.members || [];
      for (var j = 0; j < members.length; j++) {
        if (token === mcrComparable(members[j])) return keys[i];
      }
    }
    return '';
  }

  function surfaceVariantFromFinishPreview(value, rules) {
    var re = rubyRegexToJs(rules.surface_variant_regex || '');
    var text = String(value || '');
    var match = re ? text.match(re) : null;
    return match ? String(match[0] || '').replace(/^\./, '') : '';
  }

  function finishBaseWithoutSurfaceVariantPreview(value, rules) {
    var re = rubyRegexToJs(rules.surface_variant_regex || '');
    return re ? String(value || '').replace(re, '') : String(value || '');
  }

  function truthyPreview(value) {
    return value === true || String(value || '').toLowerCase() === 'true' || String(value || '') === '1';
  }

  function assignMcrPreviewLayer(result, layer, value, rules) {
    var val = applyMaterialMappingPreview(layer, String(value || '').trim(), rules);
    result.layers[layer.key] = val;
    if (layer.role === 'finish' || layer.key === 'finish_code') {
      result.finish_code = val;
      var re = rubyRegexToJs(rules.gloss_suffix_regex || '-(\\d+)\\z');
      var m = re ? val.match(re) : null;
      if (m) {
        result.do_bong = m[1] || '';
        result.color_code = val.replace(re, '').trim();
      } else {
        result.color_code = val;
      }
    }
  }

  function materialMappingRowsForPreview() {
    return $('tbl_ma_vat_lieu_global') ? collectMaterialMappingBoard() : (state.config.ma_vat_lieu_global || []);
  }

  function applyMaterialMappingPreview(layer, value) {
    var val = String(value || '').trim();
    var key = String(layer.key || '').trim();
    if (!val || !key) return val;
    var valKey = mcrComparable(val);
    var keyKey = mcrComparable(key);
    var rows = materialMappingRowsForPreview();
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i] || {};
      var group = row.nhom || row.layer || row.key || row.group || '';
      if (String(group || '').trim() && mcrComparable(group) !== keyKey) continue;
      var source = row.gia_tri || row.value || row.raw || '';
      var mapped = row.gia_tri_map || row.mapped || row.canonical || row.map || '';
      if (materialMappingCompositeReason(source) || materialMappingCompositeReason(mapped)) continue;
      if (!String(mapped || '').trim()) continue;
      if (valKey === mcrComparable(source) || valKey === mcrComparable(mapped)) {
        return String(mapped).trim();
      }
    }
    return val;
  }

  function mcrComparable(value) {
    return String(value || '').trim().toUpperCase().replace(/\s+/g, '');
  }

  function rubyRegexToJs(pattern) {
    var source = String(pattern || '').replace(/\\A/g, '^').replace(/\\z/g, '$');
    try { return new RegExp(source); } catch (e) { return null; }
  }

  var MATERIAL_MAPPING_GROUPS = [
    { key: 'chat_lieu', label: 'chat_lieu', order: 1 },
    { key: 'nha_cung_cap', label: 'nha_cung_cap', order: 2 },
    { key: 'be_mat', label: 'be_mat', order: 3 }
  ];

  function materialMappingGroups(rows) {
    var groups = MATERIAL_MAPPING_GROUPS.map(function (group) {
      return { key: group.key, label: group.label, order: group.order };
    });
    var have = {};
    groups.forEach(function (group) { have[group.key.toLowerCase()] = true; });
    (rows || []).forEach(function (row) {
      var key = String(row.nhom || '').trim();
      if (!key || have[key.toLowerCase()]) return;
      var rawOrder = parseInt(row.thu_tu, 10);
      groups.push({
        key: key,
        label: key,
        order: isFinite(rawOrder) && rawOrder > 0 ? rawOrder : groups.length + 1
      });
      have[key.toLowerCase()] = true;
    });
    return groups.sort(function (a, b) { return a.order - b.order; });
  }

  function mappingGroupKey(value, groups) {
    var raw = String(value == null ? '' : value).trim();
    if (!raw) return '';
    var numeric = parseInt(raw, 10);
    if (/^\d+$/.test(raw) && numeric > 0 && groups[numeric - 1]) return groups[numeric - 1].key;
    var lowered = raw.toLowerCase();
    for (var i = 0; i < groups.length; i++) {
      if (groups[i].key.toLowerCase() === lowered) return groups[i].key;
    }
    return raw;
  }

  function mappingRowId(index) {
    return 'mvl_' + Date.now().toString(36) + '_' + index + '_' + Math.random().toString(36).slice(2, 7);
  }

  function mappingPlacementItem(row, id) {
    var item = el('div', { class: 'mh-mapping-item', 'data-mapping-id': id });
    item.appendChild(el('span', {
      class: 'mh-mapping-grip',
      text: '⋮⋮',
      draggable: 'true',
      'data-mapping-id': id,
      title: 'Kéo để đổi nhóm hoặc vị trí'
    }));
    item.appendChild(el('span', { class: 'mh-mapping-order' }));
    item.appendChild(el('span', { class: 'mh-mapping-item-text' }));
    updateMappingPlacementLabel(item, row.gia_tri, row.gia_tri_map);
    return item;
  }

  function updateMappingPlacementLabel(item, value, mapped) {
    if (!item) return;
    var text = item.querySelector('.mh-mapping-item-text');
    if (text) text.textContent = String(mapped || '').trim();
  }

  function materialMappingSeparator() {
    var input = $('mcr_segment_separator');
    var sep = input ? input.value : '';
    return String(sep || '.');
  }

  function isDecimalNumberCode(value) {
    return /^\d+(?:[,.]\d+)?$/.test(String(value || '').trim());
  }

  function materialMappingCompositeReason(value, label) {
    value = String(value || '').trim();
    if (!value) return '';
    var sep = materialMappingSeparator();
    if (!sep || value.indexOf(sep) < 0 || isDecimalNumberCode(value)) return '';
    var parts = value.split(sep).map(function (part) { return part.trim(); }).filter(function (part) { return part; });
    if (parts.length <= 1) return '';
    return (label || 'Giá trị này') + ' đang là mã ghép nhiều lớp. Ví dụ PLY.AC = PLY + AC; không đặt trong Từ điển vật liệu.';
  }

  function refreshMaterialMappingRowValidation(row) {
    if (!row) return;
    if (row.getAttribute('data-mapping-kind') === 'parent') {
      row.classList.remove('mh-mapping-composite-row');
      var parentWarning = row.querySelector('.mh-mapping-warning');
      if (parentWarning) parentWarning.textContent = '';
      return;
    }
    var valueInput = row.querySelector('input[data-col="gia_tri"]');
    var mapInput = row.querySelector('input[data-col="gia_tri_map"]');
    var warning = row.querySelector('.mh-mapping-warning');
    var reason = materialMappingCompositeReason(valueInput ? valueInput.value : '', 'Giá trị nhập') ||
      materialMappingCompositeReason(mapInput ? mapInput.value : '', 'Mã chuẩn');
    row.classList.toggle('mh-mapping-composite-row', !!reason);
    if (warning) warning.textContent = reason;
  }

  function isMaterialParentRow(row) {
    var group = String((row && (row.nhom || row.layer || row.key || row.group)) || '').trim();
    if (group.toUpperCase() === 'VL_PARENT') return true;
    if (group) return false;
    return !!(materialMappingCompositeReason(row && (row.gia_tri_map || row.gia_tri || '')));
  }

  function mappingCatalogRow(row, id, kind) {
    kind = kind === 'parent' ? 'parent' : 'dictionary';
    var cls = 'mh-mapping-source-row' + (kind === 'parent' ? ' mh-mapping-parent-row' : '');
    var tr = el('tr', {
      class: cls,
      'data-mapping-id': id,
      'data-mapping-kind': kind,
      'data-nhom': row.nhom || '',
      'data-thu-tu': row.thu_tu || ''
    });
    var valueCell = el('td');
    valueCell.appendChild(el('input', {
      'data-col': 'gia_tri',
      value: row.gia_tri || '',
      placeholder: kind === 'parent' ? 'VD: PLY.AC.SON' : 'VD: An Cuong'
    }));
    tr.appendChild(valueCell);

    var mapCell = el('td');
    mapCell.appendChild(el('input', {
      'data-col': 'gia_tri_map',
      value: row.gia_tri_map || '',
      placeholder: kind === 'parent' ? 'VD: PLY.AC.SON' : 'VD: AC'
    }));
    mapCell.appendChild(el('div', { class: 'mh-mapping-warning' }));
    var del = el('button', { class: 'btn del mh-mapping-delete', title: 'Xoá', text: '✕' });
    mapCell.appendChild(del);
    tr.appendChild(mapCell);
    refreshMaterialMappingRowValidation(tr);
    return tr;
  }

  function buildMaterialMappingCatalog(title, hint, rows, kind) {
    var catalog = el('div', { class: 'mh-mapping-catalog mh-mapping-simple', 'data-mapping-catalog': kind });
    var head = el('div', { class: 'mh-mapping-section-head' });
    var text = el('div');
    text.appendChild(el('div', { class: 'mh-mapping-section-title', text: title }));
    text.appendChild(el('div', { class: 'mh-mapping-section-hint', text: hint }));
    head.appendChild(text);
    catalog.appendChild(head);

    var table = el('table', { class: 'mh-mapping-source-table' });
    var tableHead = el('tr');
    tableHead.appendChild(el('th', { text: kind === 'parent' ? 'Mã parent nhập' : 'Giá trị nhập' }));
    tableHead.appendChild(el('th', { text: kind === 'parent' ? 'Mã parent chuẩn' : 'Mã chuẩn' }));
    table.appendChild(tableHead);
    rows.forEach(function (row) { table.appendChild(mappingCatalogRow(row, row._id, kind)); });
    catalog.appendChild(table);
    if (!rows.length) catalog.appendChild(el('div', { class: 'empty', text: kind === 'parent' ? 'Chưa có VL_PARENT.' : 'Chưa có mapping — bấm “+ Thêm dòng”.' }));
    return catalog;
  }

  function renderMaterialMappingBoard() {
    var wrap = $('tbl_ma_vat_lieu_global');
    if (!wrap) return;
    var rows = (state.config.ma_vat_lieu_global || []).map(function (row, index) {
      return {
        gia_tri: row.gia_tri || '',
        gia_tri_map: row.gia_tri_map || '',
        nhom: row.nhom || row.layer || row.key || row.group || '',
        thu_tu: row.thu_tu || '',
        _id: row._id || mappingRowId(index)
      };
    });
    var dictRows = [];
    rows.forEach(function (row) {
      if (!isMaterialParentRow(row)) dictRows.push(row);
    });
    wrap.innerHTML = '';

    wrap.appendChild(buildMaterialMappingCatalog(
      'Từ điển token / alias',
      'Chỉ khai từng giá trị của một lớp: PLY, AC, SON, LK, VER. Không khai chuỗi ghép bằng dấu tách lớp.',
      dictRows,
      'dictionary'
    ));
    wireMaterialMappingInputs(wrap);
    refreshMaterialMappingOrder(wrap);
  }

  function cssEscape(value) {
    if (window.CSS && window.CSS.escape) return window.CSS.escape(String(value));
    return String(value).replace(/["\\]/g, '\\$&');
  }

  function collectMaterialMappingBoard() {
    var wrap = $('tbl_ma_vat_lieu_global');
    if (!wrap) return state.config.ma_vat_lieu_global || [];
    var rows = wrap.querySelectorAll('.mh-mapping-source-row[data-mapping-id]');
    var out = [];
    for (var k = 0; k < rows.length; k++) {
      var valueInput = rows[k].querySelector('input[data-col="gia_tri"]');
      var mapInput = rows[k].querySelector('input[data-col="gia_tri_map"]');
      var value = valueInput ? valueInput.value.trim() : '';
      var mapped = mapInput ? mapInput.value.trim() : '';
      if (!value && !mapped) continue;
      var item = {
        gia_tri: value,
        gia_tri_map: mapped
      };
      var kind = rows[k].getAttribute('data-mapping-kind') || '';
      var group = kind === 'parent' ? 'VL_PARENT' : (rows[k].getAttribute('data-nhom') || '');
      var order = kind === 'parent' ? (rows[k].getAttribute('data-thu-tu') || '4') : (rows[k].getAttribute('data-thu-tu') || '');
      if (group) item.nhom = group;
      if (order) item.thu_tu = order;
      out.push(item);
    }
    return out;
  }

  function wireMaterialMappingInputs(wrap) {
    if (wrap.__mhMappingInputs) return;
    wrap.__mhMappingInputs = true;
    wrap.addEventListener('input', function (e) {
      var input = e.target.closest('.mh-mapping-source-row input[data-col]');
      if (!input) return;
      var row = input.closest('.mh-mapping-source-row');
      var id = row.getAttribute('data-mapping-id');
      var value = row.querySelector('input[data-col="gia_tri"]').value;
      var mapped = row.querySelector('input[data-col="gia_tri_map"]').value;
      updateMappingPlacementLabel(wrap.querySelector('.mh-mapping-item[data-mapping-id="' + cssEscape(id) + '"]'), value, mapped);
      refreshMaterialMappingRowValidation(row);
    });
    wrap.addEventListener('click', function (e) {
      var button = e.target.closest('.mh-mapping-delete');
      if (!button) return;
      var row = button.closest('.mh-mapping-source-row');
      var id = row.getAttribute('data-mapping-id');
      var item = wrap.querySelector('.mh-mapping-item[data-mapping-id="' + cssEscape(id) + '"]');
      if (item) item.remove();
      row.remove();
      refreshMaterialMappingOrder(wrap);
    });
  }

  function wireMaterialMappingDnD(wrap) {
    if (wrap.__mhMappingDnD) return;
    wrap.__mhMappingDnD = true;
    var draggingId = '';
    var draggingFromPlacement = false;

    wrap.addEventListener('dragstart', function (e) {
      var grip = e.target.closest('.mh-mapping-grip[data-mapping-id]');
      if (!grip || !wrap.contains(grip)) return;
      draggingId = grip.getAttribute('data-mapping-id') || '';
      draggingFromPlacement = !!grip.closest('.mh-mapping-item');
      var visual = grip.closest('.mh-mapping-item') || grip.closest('.mh-mapping-source-row');
      if (visual) visual.classList.add('mh-dragging');
      if (e.dataTransfer) {
        e.dataTransfer.effectAllowed = 'move';
        e.dataTransfer.setData('text/plain', draggingId);
      }
    });

    wrap.addEventListener('dragend', function () {
      wrap.querySelectorAll('.mh-dragging').forEach(function (node) { node.classList.remove('mh-dragging'); });
      draggingId = '';
      draggingFromPlacement = false;
      refreshMaterialMappingOrder(wrap);
      state.config.ma_vat_lieu_global = collectMaterialMappingBoard();
    });

    wrap.addEventListener('dragover', function (e) {
      if (!draggingId) return;
      var list = e.target.closest('.mh-mapping-group-list');
      var catalog = e.target.closest('.mh-mapping-catalog');
      if (list || catalog) {
        e.preventDefault();
        if (e.dataTransfer) e.dataTransfer.dropEffect = 'move';
      }
    });

    wrap.addEventListener('drop', function (e) {
      if (!draggingId) return;
      var list = e.target.closest('.mh-mapping-group-list');
      var catalog = e.target.closest('.mh-mapping-catalog');
      if (!list && !catalog) return;
      e.preventDefault();

      var item = wrap.querySelector('.mh-mapping-item[data-mapping-id="' + cssEscape(draggingId) + '"]');
      if (catalog) {
        if (draggingFromPlacement && item) item.remove();
      } else if (list) {
        if (!item) {
          var sourceRow = wrap.querySelector('.mh-mapping-source-row[data-mapping-id="' + cssEscape(draggingId) + '"]');
          if (!sourceRow) return;
          item = mappingPlacementItem({
            gia_tri: sourceRow.querySelector('input[data-col="gia_tri"]').value,
            gia_tri_map: sourceRow.querySelector('input[data-col="gia_tri_map"]').value
          }, draggingId);
        }
        var after = mappingItemAfterPointer(list, e.clientY, item);
        if (after) list.insertBefore(item, after);
        else list.appendChild(item);
      }
      refreshMaterialMappingOrder(wrap);
      state.config.ma_vat_lieu_global = collectMaterialMappingBoard();
    });
  }

  function mappingItemAfterPointer(list, y, dragging) {
    var items = Array.prototype.filter.call(list.querySelectorAll('.mh-mapping-item'), function (item) {
      return item !== dragging;
    });
    var closest = { offset: Number.NEGATIVE_INFINITY, item: null };
    items.forEach(function (item) {
      var box = item.getBoundingClientRect();
      var offset = y - box.top - box.height / 2;
      if (offset < 0 && offset > closest.offset) closest = { offset: offset, item: item };
    });
    return closest.item;
  }

  function refreshMaterialMappingOrder(wrap) {
    var lists = wrap.querySelectorAll('.mh-mapping-group-list');
    for (var i = 0; i < lists.length; i++) {
      var items = lists[i].querySelectorAll('.mh-mapping-item');
      for (var j = 0; j < items.length; j++) {
        var badge = items[j].querySelector('.mh-mapping-order');
        if (badge) badge.textContent = String(j + 1);
      }
    }
    var assigned = {};
    wrap.querySelectorAll('.mh-mapping-item[data-mapping-id]').forEach(function (item) {
      assigned[item.getAttribute('data-mapping-id')] = true;
    });
    wrap.querySelectorAll('.mh-mapping-source-row[data-mapping-id]').forEach(function (row) {
      row.classList.toggle('mh-mapping-assigned', !!assigned[row.getAttribute('data-mapping-id')]);
    });
  }

  function groupedValidMaterialRows(rows) {
    var groups = [];
    var byMaterial = {};
    (rows || []).forEach(function (row) {
      var material = String(row.material || '').trim();
      var thickness = String(row.thickness == null ? '' : row.thickness).trim();
      var actualThickness = String(row.actual_thickness == null ? '' : row.actual_thickness).trim();
      if (!material) return;
      var key = material.toUpperCase();
      if (!byMaterial[key]) {
        byMaterial[key] = { material: material, thicknesses: [] };
        groups.push(byMaterial[key]);
      }
      if (thickness || actualThickness) {
        byMaterial[key].thicknesses.push({
          thickness: thickness,
          actual_thickness: actualThickness
        });
      }
    });
    return groups;
  }

  function renderValidMaterialsTable() {
    var wrap = $('tbl_ma_valid');
    if (!wrap) return;
    var groups = groupedValidMaterialRows(state.config.ma_valid || []);
    var maxThicknesses = groups.reduce(function (max, row) {
      return Math.max(max, row.thicknesses.length);
    }, 0);
    maValidThicknessColumnCount = Math.max(maValidThicknessColumnCount, maxThicknesses, 3);

    wrap.innerHTML = '';
    var table = el('table', { class: 'ma-valid-table' });
    var topHead = el('tr');
    topHead.appendChild(el('th', { text: 'Vật liệu', rowspan: '2', class: 'ma-valid-material-head' }));
    for (var i = 0; i < maValidThicknessColumnCount; i++) {
      topHead.appendChild(el('th', {
        text: String(i + 1),
        colspan: '2',
        class: 'ma-valid-thickness-head'
      }));
    }
    topHead.appendChild(el('th', { text: '', rowspan: '2', class: 'ma-valid-actions-head' }));
    table.appendChild(topHead);

    var subHead = el('tr');
    for (var j = 0; j < maValidThicknessColumnCount; j++) {
      subHead.appendChild(el('th', { text: '--', class: 'ma-valid-thickness-subhead actual' }));
      subHead.appendChild(el('th', { text: 'Ghi', class: 'ma-valid-thickness-subhead' }));
    }
    table.appendChild(subHead);

    groups.forEach(function (group) {
      table.appendChild(buildValidMaterialRow(group));
    });
    wrap.appendChild(table);
    if (!groups.length) wrap.appendChild(el('div', { class: 'empty', text: 'Chưa có vật liệu hợp lệ — bấm “+ dòng”.' }));
  }

  function buildValidMaterialRow(group) {
    group = group || { material: '', thicknesses: [] };
    var tr = el('tr', { class: 'ma-valid-row' });
    tr.appendChild(el('td', {}, [
      el('input', {
        'data-col': 'material',
        value: group.material || '',
        placeholder: 'Mã vật liệu'
      })
    ]));
    for (var i = 0; i < maValidThicknessColumnCount; i++) {
      var slot = group.thicknesses[i] || {};
      if (typeof slot === 'string') slot = { thickness: slot, actual_thickness: '' };
      tr.appendChild(el('td', {}, [
        el('input', {
          'data-actual-thickness-index': String(i),
          value: slot.actual_thickness || '',
          placeholder: 'thực tế'
        })
      ]));
      tr.appendChild(el('td', {}, [
        el('input', {
          'data-thickness-index': String(i),
          value: slot.thickness || '',
          placeholder: 'ghi'
        })
      ]));
    }
    var actions = el('td', { class: 'actions' });
    var del = el('button', { class: 'btn del', title: 'Xoá vật liệu', text: '✕' });
    del.addEventListener('click', function () {
      tr.remove();
      if (!$('tbl_ma_valid').querySelector('.ma-valid-row')) {
        $('tbl_ma_valid').appendChild(el('div', { class: 'empty', text: 'Chưa có vật liệu hợp lệ — bấm “+ dòng”.' }));
      }
    });
    actions.appendChild(del);
    tr.appendChild(actions);
    return tr;
  }

  function collectValidMaterialsTable() {
    var wrap = $('tbl_ma_valid');
    if (!wrap) return state.config.ma_valid || [];
    var out = [];
    var rows = wrap.querySelectorAll('.ma-valid-row');
    for (var i = 0; i < rows.length; i++) {
      var materialInput = rows[i].querySelector('input[data-col="material"]');
      var material = materialInput ? materialInput.value.trim() : '';
      if (!material) continue;
      var thicknessInputs = rows[i].querySelectorAll('input[data-thickness-index]');
      var actualThicknessInputs = rows[i].querySelectorAll('input[data-actual-thickness-index]');
      for (var j = 0; j < thicknessInputs.length; j++) {
        var thickness = thicknessInputs[j].value.trim();
        var actualThicknessInput = actualThicknessInputs[j];
        var actualThickness = actualThicknessInput ? actualThicknessInput.value.trim() : '';
        if (thickness || actualThickness) {
          out.push({
            material: material,
            thickness: thickness,
            actual_thickness: actualThickness
          });
        }
      }
    }
    return out;
  }

  function addValidMaterialThicknessColumn() {
    state.config.ma_valid = collectValidMaterialsTable();
    maValidThicknessColumnCount += 1;
    renderValidMaterialsTable();
    status('Đã thêm cặp cột ghi/thực tế ' + maValidThicknessColumnCount + '. Bấm Lưu để ghi Config.xlsx.', 'ok');
  }

  function wireThicknessLibrarySearch() {
    var input = $('dcThicknessLibrarySearch');
    if (!input || input.__mhThicknessLibrarySearchWired) return;
    input.__mhThicknessLibrarySearchWired = true;
    input.addEventListener('input', applyThicknessLibrarySearchFilter);
  }

  function applyThicknessLibrarySearchFilter() {
    var input = $('dcThicknessLibrarySearch');
    var wrap = $('tbl_dc_thickness_options_library');
    if (!input || !wrap) return;
    var q = input.value.trim().toUpperCase();
    var rows = wrap.querySelectorAll('tr.thickness-row');
    for (var i = 0; i < rows.length; i++) {
      var codeInput = rows[i].querySelector('input[data-col="material_type"]');
      var code = codeInput ? codeInput.value.trim().toUpperCase() : '';
      rows[i].style.display = !q || code.indexOf(q) >= 0 ? '' : 'none';
    }
  }

  function wireManualSearch() {
    var input = $('dcManualSearch');
    if (!input || input.__mhManualSearchWired) return;
    input.__mhManualSearchWired = true;
    input.addEventListener('input', applyManualSearchFilter);
  }

  function applyManualSearchFilter() {
    var input = $('dcManualSearch');
    var wrap = $('tbl_dc_manual_materials');
    if (!input || !wrap) return;
    var q = input.value.trim().toUpperCase();
    var items = wrap.querySelectorAll('.mh-manual-item[data-code]');
    for (var i = 0; i < items.length; i++) {
      var code = String(items[i].getAttribute('data-code') || '').toUpperCase();
      items[i].style.display = !q || code.indexOf(q) >= 0 ? '' : 'none';
    }
  }

  function autoGenThicknessTypes() {
    status('Đang lấy danh sách loại vật liệu từ Config…');
    var currentManualRows = collectTable('dc_manual_materials');
    var finished = false;
    var timer = setTimeout(function () {
      if (!finished) status('Đang lấy danh sách loại vật liệu quá lâu. Kiểm tra Config.xlsx/superimp_library.xlsx hoặc mở lại MH Registry.', 'err');
    }, 5000);
    Bridge.get('load_config').then(function (cfg) {
      var d = cfg && cfg.data ? cfg.data : {};
      state.config.dc_thickness_options_library = d.dc_thickness_options_library || state.config.dc_thickness_options_library || [];
      state.config.dc_manual_materials = mergeManualRowsForUi(d.dc_manual_materials || [], currentManualRows);
      renderTable('dc_manual_materials');
      return Bridge.get('dc_thickness_types');
    }).then(function (r) {
      finished = true;
      clearTimeout(timer);
      if (!r || !r.ok) { status('Lỗi lấy loại vật liệu: ' + (r && r.error || ''), 'err'); return; }
      var libraryByKey = thicknessRowsByKey(state.config.dc_thickness_options_library || []);
      var have = {};
      var skippedLibrary = 0;
      (r.types || []).forEach(function (t) {
        var key = String(t).trim();
        var up = key.toUpperCase();
        if (!key || have[up]) return;
        if (libraryByKey[up]) {
          skippedLibrary++;
          have[up] = true;
          return;
        }
        have[up] = true;
      });
      state.config.dc_thickness_options = [];
      state.config.dc_thickness_options_project = [];
      renderThicknessOptions('library');
      var manualMerge = mergeManualMaterialsFromTypes(r.types || []);
      status('Đã đồng bộ danh sách vật liệu theo parent'
        + ', library đã có ' + skippedLibrary + ' mã'
        + ', manual thêm ' + manualMerge.added + ' mã mới/tổng ' + manualMerge.total
        + (r.source ? ', nguồn ' + r.source : '')
        + (r.duration_ms != null ? ' (' + r.duration_ms + ' ms)' : '')
        + '. Nhập độ dày rồi bấm Lưu.', 'ok');
    }, function (err) {
      finished = true;
      clearTimeout(timer);
      status('Lỗi lấy loại vật liệu: ' + (err && err.message || err || ''), 'err');
    });
  }

  // ---- Học tham số DC (binding) ----------------------------------------
  function learnDCParams() {
    status('Đang đọc tham số DC đang chọn…');
    Bridge.get('dc_dynamic_attrs').then(function (r) {
      var box = $('dcAttrsList');
      if (!r || !r.ok) {
        box.innerHTML = '';
        status('Lỗi: ' + (r && r.error || 'không đọc được'), 'err');
        return;
      }
      if (r.suggest_match) $('dcBindMatch').value = r.suggest_match;
      var html = '<table style="width:100%"><tr><th>Nguồn</th><th>Tên Custom</th><th>Tham số (key)</th><th>Giá trị</th><th>mm</th><th>Unit</th><th>Access</th><th>Panel</th><th>Hậu</th></tr>';
      (r.attrs || []).forEach(function (a) {
        var spec = a.spec || a.key;
        var source = a.scope || '';
        var canBind = a.bindable !== false;
        var disabled = canBind ? '' : ' disabled';
        var labelAttr = (a.label || '').replace(/"/g, '&quot;');
        html += '<tr><td>' + source + '</td><td>' + (a.label || '') + '</td><td><code>' + a.key + '</code></td><td>' + (a.value || '') +
          '</td><td>' + (a.mm_if_length || '') + '</td><td>' + (a.formula_units || a.units || a.unit_guess || '') + '</td><td>' + (a.access || '') + '</td>' +
          '<td style="text-align:center"><input type="checkbox" name="dc_panel" value="' + spec + '" data-unit="' + a.unit_guess + '" data-label="' + labelAttr + '"' + disabled + '></td>' +
          '<td style="text-align:center"><input type="checkbox" name="dc_back" value="' + spec + '" data-unit="' + a.unit_guess + '" data-label="' + labelAttr + '"' + disabled + '></td></tr>';
      });
      html += '</table>';
      if (!(r.attrs || []).length) html = '<div class="empty">DC này không có tham số số học.</div>';
      box.innerHTML = html;
      status('Đọc ' + (r.attrs || []).length + ' tham số từ "' + (r.definition || '') + '". Chọn Panel/Hậu rồi Tạo binding.', 'ok');
    });
  }

  function buildBindingFromLearnForm(requirePanel) {
    var match = $('dcBindMatch').value.trim();
    var panelEls = Array.prototype.slice.call(document.querySelectorAll('input[name="dc_panel"]:checked'));
    var backEls = Array.prototype.slice.call(document.querySelectorAll('input[name="dc_back"]:checked'));
    if (!match) return null;
    if (requirePanel && !panelEls.length) { status('Chọn ít nhất 1 tham số làm Panel.', 'err'); return null; }
    if (!panelEls.length && !backEls.length && !($('dcBindExtra') && $('dcBindExtra').value.trim())) return null;
    var unitSource = panelEls[0] || backEls[0];
    var unit = $('dcBindUnit').value || (unitSource && unitSource.getAttribute('data-unit')) || 'length';
    var panelLabels = panelEls.map(function (el) { return el.getAttribute('data-label') || ''; }).filter(Boolean);
    var backLabels = backEls.map(function (el) { return el.getAttribute('data-label') || ''; }).filter(Boolean);
    var label = '';
    if (panelLabels.length && backLabels.length) {
      label = 'Panel: ' + panelLabels.join(', ') + ' | Hậu: ' + backLabels.join(', ');
    } else if (panelLabels.length) {
      label = panelLabels.join(', ');
    } else if (backLabels.length) {
      label = 'Hậu: ' + backLabels.join(', ');
    }
    return {
      match: match,
      label: label,
      param_panel: panelEls.map(function (el) { return el.value; }).join(', '),
      param_back: backEls.map(function (el) { return el.value; }).join(', '),
      param_extra: $('dcBindExtra') ? $('dcBindExtra').value.trim() : '',
      modul_only: '',
      product_only: '',
      unit: unit,
      enabled: '1'
    };
  }

  function upsertBindingRow(row) {
    if (!row || !row.match) return false;
    state.config.dc_thickness_bindings = collectTable('dc_thickness_bindings');
    var idx = state.config.dc_thickness_bindings.findIndex(function (b) {
      return String(b.match).trim().toLowerCase() === String(row.match).trim().toLowerCase();
    });
    if (idx >= 0) state.config.dc_thickness_bindings[idx] = row;
    else state.config.dc_thickness_bindings.push(row);
    renderTable('dc_thickness_bindings');
    return true;
  }

  function createBinding() {
    var match = $('dcBindMatch').value.trim();
    if (!match) { status('Nhập match (path hoặc group:Tên) trước.', 'err'); return; }
    var row = buildBindingFromLearnForm(true);
    if (!row) return;
    upsertBindingRow(row);
    status('Đã tạo binding cho "' + row.match + '". Bấm Lưu để ghi Config.xlsx.', 'ok');
  }

  function addExtraParam() {
    var checked = Array.prototype.slice.call(document.querySelectorAll('input[name="dc_panel"]:checked,input[name="dc_back"]:checked'));
    var target = $('dcBindExtra');
    if (!target) return;
    if (!checked.length) { status('Chọn ít nhất 1 tham số trong bảng học tham số trước.', 'err'); return; }
    var existing = target.value.trim();
    var additions = checked.map(function (el) {
      var role = el.getAttribute('name') === 'dc_back' ? 'back' : 'panel';
      return el.value + '=' + role;
    });
    target.value = [existing, additions.join('; ')].filter(Boolean).join('; ');
    status('Đã thêm parameter vào ô Param thêm.', 'ok');
  }

  function addRow(name) {
    if (name === 'ma_surface_face_rules') {
      var sfrWrap = $('tbl_ma_surface_face_rules');
      if (!sfrWrap) return;
      var emptyNode = sfrWrap.querySelector('.empty'); if (emptyNode) emptyNode.remove();
      var cards = sfrWrap.querySelector('.sfr-cards');
      if (!cards) { cards = el('div', { class: 'sfr-cards' }); sfrWrap.appendChild(cards); }
      cards.appendChild(buildSurfaceFaceCard({ enabled: '1' }));
      return;
    }
    if (name === 'dc_manual_materials') {
      var code = window.prompt('Nhập mã vật liệu thêm vào danh sách Manual:', '');
      code = String(code || '').trim();
      if (!code) return;
      var rows = collectManualMaterialsPicker();
      var key = code.toUpperCase();
      var exists = rows.some(function (row) {
        return String(row.material_code || '').trim().toUpperCase() === key;
      });
      if (exists) {
        rows = rows.map(function (row) {
          if (String(row.material_code || '').trim().toUpperCase() === key) {
            row.enabled = '1';
            row.sort_order = rows.filter(function (r) { return manualEnabled(r.enabled); }).length + 1;
          }
          return row;
        });
      } else {
        rows.unshift({ material_code: code, sort_order: 1, enabled: '1' });
      }
      state.config.dc_manual_materials = normalizeManualMaterialRowsForUi(rows);
      renderManualMaterialsPicker();
      return;
    }
    if (name === 'ma_vat_lieu_global') {
      var mappingRows = collectMaterialMappingBoard();
      mappingRows.push({ gia_tri: '', gia_tri_map: '' });
      state.config.ma_vat_lieu_global = mappingRows;
      renderMaterialMappingBoard();
      var mappingInputs = $('tbl_ma_vat_lieu_global').querySelectorAll('input[data-col="gia_tri"]');
      if (mappingInputs.length) mappingInputs[mappingInputs.length - 1].focus();
      return;
    }
    if (name === 'ma_valid') {
      var validWrap = $('tbl_ma_valid');
      if (!validWrap) return;
      var validTable = validWrap.querySelector('.ma-valid-table');
      if (!validTable) {
        state.config.ma_valid = [];
        renderValidMaterialsTable();
        validTable = validWrap.querySelector('.ma-valid-table');
      }
      var validEmpty = validWrap.querySelector('.empty');
      if (validEmpty) validEmpty.remove();
      validTable.appendChild(buildValidMaterialRow({ material: '', thicknesses: [] }));
      var validRows = validTable.querySelectorAll('.ma-valid-row');
      var newMaterialInput = validRows[validRows.length - 1].querySelector('input[data-col="material"]');
      if (newMaterialInput) newMaterialInput.focus();
      return;
    }
    var def = TABLES[name];
    var wrap = $('tbl_' + name);
    if (!def || !wrap) return;
    var table = wrap.querySelector('table');
    if (!table) { state[def.scope][def.key] = state[def.scope][def.key] || []; renderTable(name); table = wrap.querySelector('table'); }
    var emptyMsg = wrap.querySelector('.empty'); if (emptyMsg) emptyMsg.remove();
    table.appendChild(buildRow(name, def, {}, -1));
  }

  // ---- config (textareas) ----------------------------------------------
  function fillConfig() {
    renderMaterialCodeRules();
    renderProductCodeRules();
    var p = state.project, g = state.global;
    var kw = p.keywords || {};
    setValue('kw_exempt', (kw.exempt || []).join('\n'));
    setValue('kw_sp_base_only', (kw.sp_base_only || []).join('\n'));
    setValue('kw_modul_contact', (kw.modul_contact || []).join('\n'));
    setValue('sg_prefix', (p.prefix_suggestions || []).map(strOf).join('\n'));
    setValue('sg_modul', (p.modul_suggestions || []).map(strOf).join('\n'));
    setValue('sg_suffix', (p.suffix_suggestions || []).map(function (s) {
      if (s && typeof s === 'object') return s.value + (s.shortcut != null ? ' | ' + s.shortcut : '');
      return String(s);
    }).join('\n'));
    setValue('g_module_templates', (g.module_templates || []).join('\n'));
    setValue('g_header_columns', (g.header_columns || []).join('\n'));
    setValue('g_detail_aliases', Object.keys(g.detail_aliases || {}).map(function (k) { return k + ' | ' + g.detail_aliases[k]; }).join('\n'));
    setValue('g_column_aliases', Object.keys(g.column_aliases || {}).map(function (k) { return k + ' | ' + (g.column_aliases[k] || []).join(', '); }).join('\n'));
  }
  function strOf(s) { return (s && typeof s === 'object') ? s.value : String(s); }

  function collectConfigIntoState() {
    collectMaterialCodeRulesIntoState();
    collectProductCodeRulesIntoState();
    if (!$('kw_exempt')) return;
    // project
    state.project.keywords = {
      exempt: lines($('kw_exempt').value),
      sp_base_only: lines($('kw_sp_base_only').value),
      modul_contact: lines($('kw_modul_contact').value)
    };
    state.project.prefix_suggestions = lines($('sg_prefix').value);
    state.project.modul_suggestions = lines($('sg_modul').value);
    state.project.suffix_suggestions = lines($('sg_suffix').value).map(function (ln) {
      var parts = ln.split('|').map(function (x) { return x.trim(); });
      var sc = parts[1] != null && parts[1] !== '' ? parseInt(parts[1], 10) : null;
      return { value: parts[0], shortcut: isNaN(sc) ? null : sc };
    });
    // global
    state.global.module_templates = lines($('g_module_templates').value);
    state.global.header_columns = lines($('g_header_columns').value);
    var da = {};
    lines($('g_detail_aliases').value).forEach(function (ln) {
      var p = ln.split('|').map(function (x) { return x.trim(); });
      if (p[0]) da[p[0]] = p[1] || '';
    });
    state.global.detail_aliases = da;
    var ca = {};
    lines($('g_column_aliases').value).forEach(function (ln) {
      var p = ln.split('|');
      var key = (p[0] || '').trim();
      if (key) ca[key] = (p[1] || '').split(',').map(function (x) { return x.trim(); }).filter(function (x) { return x; });
    });
    state.global.column_aliases = ca;
  }

  // ---- save -------------------------------------------------------------
  function collectAllProjectTables() {
    state.project.products = collectTable('products');
    state.project.modules = collectTable('modules');
  }
  function collectAllGlobalTables() {
    collectMaterialCodeRulesIntoState();
    collectProductCodeRulesIntoState();
    syncMaterialMappingsToGlobalState();
    state.global.materials = collectTable('materials');
    state.global.thickness_mappings = collectTable('thickness_mappings');
    state.global.invalid_materials = collectTable('invalid_materials');
  }

  function save(scope) {
    collectConfigIntoState();
    var mcrCheck = validateMaterialCodeRules(state.global.material_code_rules || {});
    if (!mcrCheck.ok) {
      status('Cấu trúc mã vật liệu chưa hợp lệ.', 'err');
      return;
    }
    var pcrCheck = validateProductCodeRules(state.global.product_code_rules || {});
    if (!pcrCheck.ok) {
      status('Cấu trúc mã sản phẩm chưa hợp lệ: ' + pcrCheck.errors.join(' '), 'err');
      return;
    }
    if (scope === 'project') {
      collectAllProjectTables();
      Bridge.get('save_project', state.project).then(function (r) {
        status(r && r.ok ? 'Đã lưu Project: ' + (r.path || '') : 'Lỗi lưu Project', r && r.ok ? 'ok' : 'err');
      });
    } else {
      collectAllGlobalTables();
      Bridge.get('save_global', state.global).then(function (r) {
        status(r && r.ok ? 'Đã lưu Global.' : 'Lỗi lưu Global', r && r.ok ? 'ok' : 'err');
      });
    }
  }

  // ---- import / export --------------------------------------------------
  function doImport() {
    status('Đang đọc file…');
    Bridge.get('import_xlsx').then(function (r) {
      if (!r || !r.ok) { status(r && r.cancelled ? 'Đã huỷ.' : ('Lỗi import: ' + (r && r.error)), r && r.cancelled ? null : 'err'); return; }
      renderImportPreview(r.sheets);
      status('Đã đọc: ' + r.path);
    });
  }

  function renderImportPreview(sheets) {
    var box = $('importPreview'); box.innerHTML = '';
    Object.keys(sheets).forEach(function (name) {
      var rows = sheets[name] || [];
      var sec = el('div', { class: 'sheet' });
      sec.appendChild(el('h4', { text: name + ' (' + rows.length + ' dòng)' }));
      var table = el('table');
      rows.slice(0, 6).forEach(function (row) {
        var tr = el('tr');
        row.slice(0, 8).forEach(function (c) { tr.appendChild(el('td', { text: String(c) })); });
        table.appendChild(tr);
      });
      sec.appendChild(table);
      box.appendChild(sec);
    });
  }

  function doExport(scope) {
    collectConfigIntoState();
    var sheets, fname;
    if (scope === 'project') {
      collectAllProjectTables();
      sheets = {
        products: toRows(state.project.products, ['code', 'name', 'type']),
        modules: toRows(state.project.modules, ['sp', 'modul', 'prefix', 'suffix'])
      };
      fname = 'MH_project_registry.xlsx';
    } else {
      collectAllGlobalTables();
      sheets = {
        materials: toRows(state.global.materials, ['code', 'name', 'supplier']),
        thickness_mappings: toRows(state.global.thickness_mappings, ['min', 'max', 'value']),
        invalid_materials: toRows(state.global.invalid_materials, ['material', 'thickness'])
      };
      fname = 'MH_global_registry.xlsx';
    }
    Bridge.get('export_xlsx', { filename: fname, sheets: sheets }).then(function (r) {
      status(r && r.ok ? 'Đã xuất: ' + r.path : (r && r.cancelled ? 'Đã huỷ.' : 'Lỗi xuất'), r && r.ok ? 'ok' : (r && r.cancelled ? null : 'err'));
    });
  }

  function toRows(arr, cols) {
    var out = [cols.slice()];
    (arr || []).forEach(function (o) { out.push(cols.map(function (c) { return o[c] != null ? o[c] : ''; })); });
    return out;
  }

  // ---- scan model -------------------------------------------------------
  function scanModel() {
    status('Đang quét model…');
    Bridge.get('scan_model_products').then(function (r) {
      if (!r || !r.ok) { status('Lỗi quét model', 'err'); return; }
      collectAllProjectTables(); // giữ chỉnh sửa hiện tại
      var have = {};
      state.project.products.forEach(function (p) { have[(p.code || '').toUpperCase()] = true; });
      var added = 0;
      r.codes.forEach(function (code) {
        if (!have[code.toUpperCase()]) { state.project.products.push({ code: code, name: '', type: '' }); added++; }
      });
      renderTable('products');
      status('Quét xong: thêm ' + added + ' mã mới (tổng model có ' + r.codes.length + ').', 'ok');
    });
  }

  function mergeThicknessToConfig() {
    state.config.dc_thickness_options = [];
    state.config.dc_thickness_options_project = [];
    var formRow = buildBindingFromLearnForm(false);
    if (formRow) upsertBindingRow(formRow);
    state.config.dc_thickness_bindings = collectTable('dc_thickness_bindings');
    status('Đang lưu/cập nhật độ dày vật liệu và binding DC vào Config.xlsx…');
    Bridge.get('merge_dc_thickness_options_to_config', {
      dc_thickness_options: state.config.dc_thickness_options,
      dc_thickness_options_project: state.config.dc_thickness_options_project,
      dc_thickness_options_library: collectThicknessOptions('library'),
      dc_thickness_bindings: state.config.dc_thickness_bindings,
      dc_manual_materials: collectTable('dc_manual_materials')
    }).then(function (r) {
      if (!r || !r.ok) {
        status('Lỗi lưu độ dày vật liệu: ' + (r && r.error || ''), 'err');
        return;
      }
      status('Đã lưu dc_thickness_options: thêm ' + r.added
        + ', cập nhật ' + (r.updated || 0)
        + ', giữ nguyên ' + (r.unchanged || 0)
        + ', bỏ qua library ' + (r.skipped_library || 0)
        + '; manual thêm ' + (r.manual_added || 0) + '/tổng ' + (r.manual_total || 0) + ' dòng'
        + '; binding ' + (r.bindings || 0) + ' dòng.', 'ok');
      loadConfig();
    }, function (err) {
      status('Lỗi lưu độ dày vật liệu: ' + (err && err.message || err || ''), 'err');
    });
  }

  // ---- config (Config.xlsx) -----------------------------------------------
  var configData = {}; // lưu data gốc để dùng lại

  function loadConfig() {
    status('Đang đọc Config.xlsx…');
    Bridge.get('load_config').then(function (r) {
      if (!r || !r.ok) { status('Lỗi đọc Config.xlsx', 'err'); return; }
      var d = r.data || {};
      configData = d;
      var seps = d.separators || {};
      $('nc_sep_sub_prefix').value = seps.sep_sub_prefix != null ? seps.sep_sub_prefix : '-';
      $('nc_sep_prefix').value = seps.sep_prefix != null ? seps.sep_prefix : '_';
      $('nc_sep_suffix').value = seps.sep_suffix != null ? seps.sep_suffix : '_';
      $('nc_default_prefix').value = seps.default_prefix != null ? seps.default_prefix : 'SP';

      // Populate column dropdowns
      fillColumnSelect('nc_active_sub_prefix', d.sub_prefix_columns || {}, seps.active_sub_prefix || '');
      fillColumnSelect('nc_active_prefix', d.prefix_columns || {}, seps.active_prefix || '');
      fillColumnSelect('nc_active_modul', d.modul_columns || {}, seps.active_modul || '');

      // Show active values in textareas (readonly)
      $('nc_sub_prefix').value = (d.sub_prefix || []).join('\n');
      $('nc_prefix').value = (d.prefix || []).join('\n');
      $('nc_modul').value = (d.modul || []).join('\n');
      $('nc_sub_prefix_col').textContent = '(' + (d.sub_prefix || []).length + ')';
      $('nc_prefix_col').textContent = '(' + (d.prefix || []).length + ')';
      $('nc_modul_col').textContent = '(' + (d.modul || []).length + ')';

      $('nc_suffix').value = (d.suffix || []).map(function (s) {
        if (s && typeof s === 'object') return s.value + (s.shortcut != null ? ' | ' + s.shortcut : '');
        return String(s);
      }).join('\n');
      renderSuffixRows(d.suffix || []);
      renderProductCodeRules();
      collectProductCodeRulesIntoState();
      // config tables
      state.config.ma_vat_lieu = d.ma_vat_lieu || [];
      state.config.ma_vat_lieu_global = d.ma_vat_lieu_global || d.ma_vat_lieu || [];
      state.config.ma_thickness = d.ma_thickness || [];
      state.config.ma_detail_aliases = d.ma_detail_aliases || [];
      state.config.ma_tag_materials = d.ma_tag_materials || [];
      state.config.ma_valid = d.ma_valid || [];
      state.config.ma_invalid = d.ma_invalid || [];
      state.config.ma_column_aliases = d.ma_column_aliases || [];
      state.config.ma_surface_face_rules = d.ma_surface_face_rules || [];
      state.config.superimp_import_list = d.superimp_import_list || [];
      state.config.dc_material_options = d.dc_material_options || [];
      state.config.material_profile_choices = d.material_profile_choices || [];
      state.config.dc_thickness_options_library = d.dc_thickness_options_library || [];
      state.config.dc_thickness_options_project = [];
      state.config.dc_thickness_options = [];
      state.config.dc_thickness_bindings = d.dc_thickness_bindings || [];
      state.config.dc_manual_materials = normalizeManualMaterialRowsForUi(d.dc_manual_materials || []);
      renderTable('ma_vat_lieu_global');
      renderTable('superimp_import_list');
      renderThicknessOptions('library');
      renderTable('dc_thickness_bindings');
      renderTable('dc_manual_materials');
      renderTable('ma_thickness');
      renderTable('ma_detail_aliases');
      renderTable('ma_tag_materials');
      renderTable('ma_valid');
      renderTable('ma_invalid');
      renderTable('ma_column_aliases');
      renderTable('ma_surface_face_rules');
      updateNamePreview();
      status('Đã tải Config.xlsx', 'ok');
    });
  }

  function fillColumnSelect(selectId, columns, activeValue) {
    var sel = $(selectId);
    sel.innerHTML = '';
    var keys = Object.keys(columns);
    if (keys.length === 0) {
      sel.innerHTML = '<option value="">(trống)</option>';
      return;
    }
    keys.forEach(function (k) {
      var opt = el('option', { value: k, text: k + ' (' + columns[k].length + ')' });
      if (k === activeValue || (!activeValue && keys.indexOf(k) === 0)) opt.selected = true;
      sel.appendChild(opt);
    });
    sel.dataset.current = sel.value;
  }

  function onColumnChange(type) {
    var selId = 'nc_active_' + type;
    var sel = $(selId);
    syncActiveColumn(type, sel.dataset.current);
    var activeCol = sel.value;
    var cols = (configData[type + '_columns'] || {});
    var vals = cols[activeCol] || [];
    $('nc_' + type.replace('sub_prefix','sub_prefix')).value = vals.join('\n');
    $('nc_' + type + '_col').textContent = '(' + vals.length + ')';
    sel.dataset.current = activeCol;
    updateNamePreview();
  }

  function cloneColumns(cols) {
    var out = {};
    Object.keys(cols || {}).forEach(function (k) {
      out[k] = (cols[k] || []).slice();
    });
    return out;
  }

  function syncActiveColumn(type, columnName) {
    var colsKey = type + '_columns';
    configData[colsKey] = cloneColumns(configData[colsKey] || {});
    var activeCol = columnName || $('nc_active_' + type).value;
    if (!activeCol) activeCol = 'value';
    configData[colsKey][activeCol] = lines($('nc_' + type).value);
  }

  function updateNamePreview() {
    var s1 = $('nc_sep_sub_prefix').value;
    var s2 = $('nc_sep_prefix').value;
    var s3 = $('nc_sep_suffix').value;
    var sp = (lines($('nc_sub_prefix').value)[0] || 'T2S5A');
    var px = (lines($('nc_prefix').value)[0] || '');
    var md = (lines($('nc_modul').value)[0] || 'Tấm Đứng');
    var sx = (lines($('nc_suffix').value)[0] || 'L');
    if (sx.indexOf('|') > -1) sx = sx.split('|')[0].trim();
    $('nc_preview').textContent = 'Preview: ' + sp + s1 + px + s2 + md + s3 + sx;
  }

  function collectConfig() {
    syncActiveColumn('sub_prefix');
    syncActiveColumn('prefix');
    syncActiveColumn('modul');
    var suffixEntries = suffixEntriesFromDom();
    syncSuffixTextarea(suffixEntries);
    return {
      separators: {
        sep_sub_prefix: $('nc_sep_sub_prefix').value,
        sep_prefix: $('nc_sep_prefix').value,
        sep_suffix: $('nc_sep_suffix').value,
        default_prefix: $('nc_default_prefix').value,
        active_sub_prefix: $('nc_active_sub_prefix').value,
        active_prefix: $('nc_active_prefix').value,
        active_modul: $('nc_active_modul').value
      },
      sub_prefix: lines($('nc_sub_prefix').value),
      prefix: lines($('nc_prefix').value),
      modul: lines($('nc_modul').value),
      sub_prefix_columns: cloneColumns(configData.sub_prefix_columns || {}),
      prefix_columns: cloneColumns(configData.prefix_columns || {}),
      modul_columns: cloneColumns(configData.modul_columns || {}),
      suffix: suffixEntries,
      product_code_rules: state.global.product_code_rules || collectProductCodeRules(),
      material_code_rules: state.global.material_code_rules || collectMaterialCodeRules(),
      ma_vat_lieu: collectTable('ma_vat_lieu_global'),
      ma_vat_lieu_global: collectTable('ma_vat_lieu_global'),
      superimp_import_list: collectTable('superimp_import_list'),
      ma_thickness: collectTable('ma_thickness'),
      ma_detail_aliases: collectTable('ma_detail_aliases'),
      ma_tag_materials: collectTable('ma_tag_materials'),
      ma_valid: collectTable('ma_valid'),
      ma_invalid: collectTable('ma_invalid'),
      ma_column_aliases: collectTable('ma_column_aliases'),
      ma_surface_face_rules: collectTable('ma_surface_face_rules'),
      dc_material_profiles: configData.dc_material_profiles || [],
      dc_material_options: state.config.dc_material_options || configData.dc_material_options || [],
      material_profile_choices: state.config.material_profile_choices || [],
      dc_thickness_options: [],
      dc_thickness_options_project: [],
      dc_thickness_options_library: collectThicknessOptions('library'),
      dc_thickness_bindings: collectTable('dc_thickness_bindings'),
      dc_manual_materials: collectTable('dc_manual_materials')
    };
  }

  function saveConfig() {
    var mcrCheck = collectMaterialCodeRulesIntoState();
    if (mcrCheck && !mcrCheck.ok) {
      status('Cấu trúc mã vật liệu chưa hợp lệ.', 'err');
      return;
    }
    var pcrCheck = collectProductCodeRulesIntoState();
    if (pcrCheck && !pcrCheck.ok) {
      status('Cấu trúc mã sản phẩm chưa hợp lệ: ' + pcrCheck.errors.join(' '), 'err');
      return;
    }
    syncMaterialMappingsToGlobalState();
    var data = collectConfig();
    status('Đang lưu…');
    Bridge.get('save_config', data).then(function (r) {
      if (r && r.ok) {
        Bridge.get('save_global', state.global).then(function (gr) {
          state.config.dc_manual_materials = normalizeManualMaterialRowsForUi(data.dc_manual_materials || []);
          state.config.dc_thickness_options_library = data.dc_thickness_options_library || [];
          renderTable('dc_manual_materials');
          status('Đã lưu → Excel + Registry: ' + (r.path || '') + (gr && gr.ok ? ' + rule mã vật liệu + mã sản phẩm' : ''), gr && gr.ok ? 'ok' : 'err');
          fillConfig();
        });
      } else {
        status('Lỗi lưu: ' + (r && r.error || ''), 'err');
      }
    });
  }

  function saveSuperimp() {
    var formRow = buildBindingFromLearnForm(false);
    if (formRow) upsertBindingRow(formRow);
    saveConfig();
  }

  function openConfigFolder() {
    Bridge.get('open_config_folder');
  }

  // ---- tạo mã vật liệu -------------------------------------------------
  var mvlInputPath = '';
  var mvlInputExists = false;
  var mvlOutputPath = '';

  function setMVLInputPath(path, exists) {
    mvlInputPath = (path || '').trim();
    mvlInputExists = !!mvlInputPath && exists !== false;
    if (!mvlInputPath) {
      $('mvlInputPath').textContent = '';
      return;
    }
    $('mvlInputPath').textContent = mvlInputPath + (exists === false ? ' (không tồn tại)' : '');
  }

  function setSelectOptions(id, codes, selected) {
    var sel = $(id);
    if (!sel) return;
    sel.innerHTML = '';
    (codes || []).forEach(function (code) {
      var opt = el('option', { value: code, text: code });
      if (code === selected) opt.selected = true;
      sel.appendChild(opt);
    });
  }

  function spCodeNumber(code) {
    var m = String(code || '').match(/(\d+)/);
    return m ? parseInt(m[1], 10) : 0;
  }

  // Tien ich: doc Excel (neu co) chi de PREFILL o Cuoi = so SP lon nhat. Khong
  // bat buoc — nguoi dung van go tay khoang Dau-Cuoi de tu sinh ma.
  function loadSpCodes() {
    if (!mvlInputPath || !mvlInputExists) return;
    Bridge.get('list_sp_codes', mvlInputPath).then(function (r) {
      var codes = r && r.ok ? (r.codes || []) : [];
      var maxNo = codes.reduce(function (acc, c) { return Math.max(acc, spCodeNumber(c)); }, 0);
      if (maxNo > 0) {
        if ($('markStart') && !$('markStart').value) $('markStart').value = 1;
        if ($('markEnd')) $('markEnd').value = maxNo;
      }
      if ($('markLog')) {
        var source = r && r.source ? (' | nguồn: ' + r.source) : '';
        $('markLog').textContent = codes.length ? ('Excel có ' + codes.length + ' mã SP (đã điền sẵn Cuối).' + source) : '';
      }
    });
  }

  function restoreMVLInputPath(done) {
    Bridge.get('get_mvl_input_path').then(function (r) {
      if (r && r.path) setMVLInputPath(r.path, r.exists);
      if (r && r.path && r.exists !== false) loadSpCodes();
      if (done) done(!!(r && r.path && r.exists !== false));
    });
  }

  function withMVLInput(callback) {
    if (mvlInputPath && mvlInputExists) {
      callback();
      return;
    }
    restoreMVLInputPath(function (ok) {
      if (ok) callback();
      else status('Chọn file Excel thống kê trước!', 'err');
    });
  }

  function chooseMVLInput() {
    Bridge.get('choose_mvl_input').then(function (r) {
      if (!r || !r.ok) return;
      setMVLInputPath(r.path, true);
      $('mvlLog').textContent = '';
      $('btnOpenOutput').style.display = 'none';
      loadSpCodes();
    });
  }

  function markProducts() {
    var start = $('markStart') ? $('markStart').value : '';
    var end = $('markEnd') ? $('markEnd').value : '';
    if (!String(start).trim() || !String(end).trim()) {
      $('markLog').textContent = 'Nhập số Đầu và Cuối.';
      status('Nhập số Đầu–Cuối', 'err');
      return;
    }
    status('Đang sinh mã SP và tạo nhãn...');
    $('markLog').textContent = 'Đang xử lý...';
    Bridge.get('mark_products', {
      input: mvlInputPath,
      prefix: $('markPrefix') ? $('markPrefix').value : '',
      start: start,
      end: end,
      spacing: $('markSpacing') ? $('markSpacing').value : 5000
    }).then(function (r) {
      if (r && r.ok) {
        $('markLog').textContent = 'Đã tạo ' + r.count + ' nhãn: ' + (r.codes || []).join(', ');
        status('Đánh dấu ' + r.count + ' sản phẩm xong!', 'ok');
      } else {
        $('markLog').textContent = 'Lỗi: ' + (r && r.error || '');
        status('Lỗi đánh dấu SP', 'err');
      }
    });
  }

  function markProductsAuto() {
    status('Đang đọc danh sách mã SP từ JSON dự án...');
    $('markLog').textContent = 'Đang xử lý...';
    $('btnMarkProductsAuto').disabled = true;
    Bridge.get('mark_products_auto', {
      input: mvlInputPath,
      spacing: $('markSpacing') ? $('markSpacing').value : 5000
    }).then(function (r) {
      $('btnMarkProductsAuto').disabled = false;
      if (r && r.ok) {
        $('markLog').textContent = 'Đã tạo ' + r.count + ' nhãn từ JSON: ' + (r.codes || []).join(', ');
        status('Tự động đánh dấu ' + r.count + ' sản phẩm xong!', 'ok');
      } else {
        $('markLog').textContent = 'Lỗi: ' + (r && r.error || '');
        status('Lỗi đánh dấu SP tự động', 'err');
      }
    }).catch(function (err) {
      $('btnMarkProductsAuto').disabled = false;
      $('markLog').textContent = 'Lỗi: ' + (err && err.message || err || '');
      status('Lỗi đánh dấu SP tự động', 'err');
    });
  }

  function runMVL() {
    withMVLInput(function () {
      status('Đang tạo mã vật liệu từ file Excel mới nhất…');
      $('mvlLog').textContent = 'Đang xử lý...';
      $('btnRunMVL').disabled = true;
      $('maSection').style.display = 'none';
      var includeSon = $('mvlIncludeSon').checked;
      Bridge.get('run_mvl', { input: mvlInputPath, include_son: includeSon, config: collectConfig() }).then(function (r) {
        $('btnRunMVL').disabled = false;
        if (r && r.ok) {
          mvlOutputPath = r.output;
          var log = 'Đã tạo: ' + r.output;
          if (r.log) log = r.log + '\n' + log;

          // Material Assign auto-loaded?
          var ma = r.material_assign;
          if (ma && ma.ok) {
            log += '\nĐã load ' + ma.count + ' dòng vào Material Assign.';
            $('maDataCount').textContent = ma.count + ' dòng đã load';
            $('maSection').style.display = '';
          }

          var tk = r.thongke;
          if (tk && tk.ok) {
            log += '\nĐã nạp ' + (tk.rows || 0) + ' dòng Excel vào MH_Thongke.';
            log += '\nBảng vật liệu MH_Thongke: ' + (tk.material_rows || 0) + ' dòng.';
          } else if (tk && tk.error) {
            log += '\nMH_Thongke chưa nhận output: ' + tk.error;
          }

          $('mvlLog').textContent = log;
          $('btnOpenOutput').style.display = '';
          status('Tạo mã vật liệu xong!', 'ok');
        } else {
          $('mvlLog').textContent = 'Lỗi: ' + (r && r.error || '') + '\n' + (r && r.log || '');
          status('Lỗi tạo mã vật liệu', 'err');
        }
      });
    });
  }

  function reloadMVLExcel() {
    withMVLInput(function () {
      var path = mvlOutputPath || mvlInputPath;
      status('Đang reload Excel và đồng bộ cache…');
      $('mvlLog').textContent = 'Đang reload Excel...';
      $('btnReloadMVLExcel').disabled = true;
      Bridge.get('reload_mvl_excel', { input: mvlInputPath, output: mvlOutputPath || '' }).then(function (r) {
        $('btnReloadMVLExcel').disabled = false;
        if (r && r.ok) {
          mvlOutputPath = r.path || path;
          var log = 'Đã reload: ' + (r.path || path);
          if (r.json) log += '\nĐã cập nhật JSON/cache: ' + r.json;
          if (r.material_assign && r.material_assign.ok) {
            log += '\nMaterial Assign: ' + r.material_assign.count + ' dòng.';
            $('maDataCount').textContent = r.material_assign.count + ' dòng đã load';
            $('maSection').style.display = '';
          }
          if (r.thongke && r.thongke.ok) {
            log += '\nMH_Thongke: ' + (r.thongke.rows || 0) + ' dòng.';
          } else if (r.thongke && r.thongke.error) {
            log += '\nMH_Thongke chưa nhận file: ' + r.thongke.error;
          }
          $('mvlLog').textContent = log;
          $('btnOpenOutput').style.display = '';
          status('Reload Excel xong!', 'ok');
        } else {
          $('mvlLog').textContent = 'Lỗi reload: ' + (r && r.error || '');
          status('Lỗi reload Excel', 'err');
        }
      });
    });
  }

  function assignSelection() {
    status('Đang gán vật liệu selection…');
    $('maLog').textContent = 'Đang xử lý...';
    Bridge.get('assign_material_selection').then(function (r) {
      if (r && r.ok) {
        $('maLog').textContent = 'Thành công: ' + r.success + '/' + r.processed + ' đối tượng.';
        status('Gán VL selection xong!', 'ok');
      } else {
        $('maLog').textContent = 'Lỗi: ' + (r && r.error || '');
        status('Lỗi gán VL', 'err');
      }
    });
  }

  function assignAll() {
    status('Đang gán vật liệu toàn bộ…');
    $('maLog').textContent = 'Đang xử lý...';
    Bridge.get('assign_material_all').then(function (r) {
      if (r && r.ok) {
        $('maLog').textContent = 'Thành công: ' + r.success + '/' + r.processed + ' đối tượng.';
        status('Gán VL toàn bộ xong!', 'ok');
      } else {
        $('maLog').textContent = 'Lỗi: ' + (r && r.error || '');
        status('Lỗi gán VL', 'err');
      }
    });
  }

  function openMVLOutput() {
    if (mvlOutputPath) Bridge.get('open_mvl_output', mvlOutputPath);
  }

  // ---- bootstrap --------------------------------------------------------
  function loadData() {
    status('Đang tải dữ liệu…');
    Bridge.get('get_data').then(function (d) {
      state.global = d.global || {};
      state.project = d.project || {};
      $('modelName').textContent = d.model_name || '?';
      $('projectPath').textContent = d.project_path || '';
      if (d.mvl_input_path) {
        setMVLInputPath(d.mvl_input_path, d.mvl_input_exists);
        if (d.mvl_input_exists) loadSpCodes();
      }
      fillConfig();
      status('Sẵn sàng.' + (d.model_saved ? '' : ' (Model chưa lưu → project dùng file mặc định)'));
      loadConfig();
    });
  }

  // ---- wire events ------------------------------------------------------
  function init() {
    // tabs
    document.querySelectorAll('.tab').forEach(function (t) {
      t.addEventListener('click', function () {
        switchRegistryTab(t.dataset.tab);
      });
    });
    // add row / save / export buttons (event delegation)
    document.addEventListener('click', function (ev) {
      var t = ev.target;
      if (t.dataset && t.dataset.add) addRow(t.dataset.add);
      else if (t.dataset && t.dataset.save) save(t.dataset.save);
      else if (t.dataset && t.dataset.export) doExport(t.dataset.export);
    });
    on('btnReload', 'click', loadData);
    on('btnImport', 'click', doImport);
    on('btnScanModel', 'click', scanModel);
    on('btnReloadConfig', 'click', loadConfig);
    on('btnSaveConfig', 'click', saveConfig);
    on('btnOpenConfigFolder', 'click', openConfigFolder);
    on('btnReloadConfig2', 'click', loadConfig);
    on('btnSaveConfig2', 'click', saveConfig);
    on('btnOpenConfigFolder2', 'click', openConfigFolder);
    on('btnReloadMaterialProfiles', 'click', autoGenThicknessTypes);
    on('btnAddThicknessTypeLib', 'click', function () { addThicknessType('library'); });
    on('btnAddThicknessOptionLib', 'click', function () { addThicknessOption('library'); });
    on('btnAddMaValidThicknessColumn', 'click', addValidMaterialThicknessColumn);
    on('btnAddMaterialCodeLayer', 'click', addMcrTestCell);
    on('btnAddProductCodeCell', 'click', addProductCodeCell);
    var pcrBuilder = $('pcr_builder');
    if (pcrBuilder) {
      pcrBuilder.addEventListener('input', function () {
        pcrColumns = collectProductCodeColumnsFromDom();
        syncSuffixTextarea(suffixEntriesFromDom());
        updateNamePreview();
        collectProductCodeRulesIntoState();
        renderProductCodeContract(productCodeRules());
      });
      pcrBuilder.addEventListener('change', function () {
        pcrColumns = collectProductCodeColumnsFromDom();
        syncSuffixTextarea(suffixEntriesFromDom());
        updateNamePreview();
        collectProductCodeRulesIntoState();
        renderProductCodeContract(productCodeRules());
      });
      pcrBuilder.addEventListener('click', function (ev) {
        var btn = ev.target.closest('[data-pcr-action="delete"]');
        if (btn) {
          var col = btn.closest('.pcr-col');
          if (col && col.parentNode) col.parentNode.removeChild(col);
          syncProductCodeBuilderState();
          return;
        }
        btn = ev.target.closest('[data-pcr-action="add-value"]');
        if (btn) {
          var valueCol = btn.closest('.pcr-col');
          var list = valueCol && valueCol.querySelector('.mcr-test-value-list');
          if (list) {
            var isSuffix = valueCol && pcrFieldValue(valueCol, 'key') === 'suffix';
            list.appendChild(isSuffix
              ? buildProductCodeSuffixValueCard({}, list.querySelectorAll('.mcr-test-value-card').length)
              : buildProductCodeValueCard('', list.querySelectorAll('.mcr-test-value-card').length));
            refreshProductCodeOrder();
            var inputs = list.querySelectorAll('[data-pcr-value]');
            if (inputs.length) inputs[inputs.length - 1].focus();
          }
          syncProductCodeBuilderState();
          return;
        }
        btn = ev.target.closest('[data-pcr-action="delete-value"]');
        if (btn) {
          var item = btn.closest('.mcr-test-value-card');
          if (item && item.parentNode) item.parentNode.removeChild(item);
          refreshProductCodeOrder();
          syncProductCodeBuilderState();
        }
      });
      pcrBuilder.addEventListener('dragstart', startProductCodeDrag);
      pcrBuilder.addEventListener('dragover', dragOverProductCode);
      pcrBuilder.addEventListener('drop', dropProductCode);
      pcrBuilder.addEventListener('dragend', endProductCodeDrag);
    }
    on('btnAddSuffixRow', 'click', function () { addSuffixRow({}); });
    var suffixRows = $('nc_suffix_rows');
    if (suffixRows) {
      suffixRows.addEventListener('input', function () {
        syncSuffixTextarea(suffixEntriesFromDom());
        updateNamePreview();
      });
      suffixRows.addEventListener('click', function (ev) {
        var btn = ev.target.closest('[data-suffix-action="delete"]');
        if (!btn) return;
        var row = btn.closest('tr');
        if (row && row.parentNode) row.parentNode.removeChild(row);
        syncSuffixTextarea(suffixEntriesFromDom());
        updateNamePreview();
      });
    }
    var mcrWrap = $('tbl_material_code_layers');
    if (mcrWrap) {
      mcrWrap.addEventListener('click', function (ev) {
        var btn = ev.target.closest('[data-mcr-action]');
        if (btn) materialCodeLayerAction(btn);
      });
      mcrWrap.addEventListener('dragstart', startMaterialCodeLayerDrag);
      mcrWrap.addEventListener('dragover', dragOverMaterialCodeLayer);
      mcrWrap.addEventListener('dragleave', function (ev) {
        var tr = ev.target && ev.target.closest ? ev.target.closest('tr[data-mcr-row]') : null;
        if (tr) tr.classList.remove('mcr-drop-target');
      });
      mcrWrap.addEventListener('drop', dropMaterialCodeLayer);
      mcrWrap.addEventListener('dragend', function () { clearMaterialCodeDropMarks(mcrWrap); });
      mcrWrap.addEventListener('input', function () {
        collectMaterialCodeRulesIntoState();
        updateMaterialCodePreview();
      });
      mcrWrap.addEventListener('change', function (ev) {
        updateMcrPatternVisibility(ev.target.closest('tr[data-mcr-row]') || mcrWrap);
        collectMaterialCodeRulesIntoState();
        updateMaterialCodePreview();
      });
    }
    var mcrGroupWrap = $('mcr_group_rules');
    if (mcrGroupWrap) {
      mcrGroupWrap.addEventListener('input', function () {
        collectMaterialCodeRulesIntoState();
        updateMaterialCodePreview();
      });
      mcrGroupWrap.addEventListener('change', function () {
        collectMaterialCodeRulesIntoState();
        updateMaterialCodePreview();
      });
    }
    document.querySelectorAll('[data-mcr-subtab]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        switchMaterialCodeSubtab(btn.getAttribute('data-mcr-subtab'));
      });
    });
    on('btnAddMcrTestCell', 'click', addMcrTestCell);
    var mcrTestBuilder = $('mcr_test_builder');
    if (mcrTestBuilder) {
      mcrTestBuilder.addEventListener('input', function (ev) {
        if (ev.target && ev.target.closest && ev.target.closest('.mcr-branch-panel, .mcr-inline-branch-cell')) {
          refreshMcrSystemColumnValues(collectMaterialCodeRules());
        }
        updateMcrTestInputFromColumns(true);
      });
      mcrTestBuilder.addEventListener('change', function (ev) {
        if (!ev.target || !ev.target.matches) return;
        if (ev.target.matches('[data-mcr-test-value], [data-mcr-branch-value]')) {
          updateMcrTestInputFromColumns(true);
        }
      });
      mcrTestBuilder.addEventListener('click', function (ev) {
        var btn = ev.target.closest('[data-mcr-test-action="delete"]');
        if (btn) {
          var col = btn.closest('.mcr-test-col');
          if (col && col.parentNode) col.parentNode.removeChild(col);
          mcrTestColumns = collectMcrTestColumnsFromDom();
          renderMaterialCodeTestBuilder(collectMaterialCodeRules());
          updateMcrTestInputFromColumns(true);
          return;
        }
        btn = ev.target.closest('[data-mcr-test-action="remove-parent"]');
        if (btn) {
          var chip = btn.closest('.mcr-parent-chip');
          setMcrTestParent(chip && chip.getAttribute('data-mcr-parent-key'), false);
          renderMaterialCodeTestBuilder(materialCodeRules());
          collectMaterialCodeRulesIntoState();
          updateMaterialCodePreview();
          return;
        }
        btn = ev.target.closest('[data-mcr-test-action="add-value"]');
        if (btn) {
          var valueCol = btn.closest('.mcr-test-col');
          var list = valueCol && valueCol.querySelector('.mcr-test-value-list');
          if (list) {
            list.appendChild(buildMcrTestValueCard('', list.querySelectorAll('.mcr-test-value-card').length));
            refreshMcrTestColumnOrder();
            var inputs = list.querySelectorAll('[data-mcr-test-value]');
            if (inputs.length) inputs[inputs.length - 1].focus();
          }
          updateMcrTestInputFromColumns(true);
          return;
        }
        btn = ev.target.closest('[data-mcr-test-action="add-branch"]');
        if (btn) {
          mcrTestColumns = collectMcrTestColumnsFromDom();
          mcrTestBranches = collectMcrTestBranchesFromDom();
          var next = mcrTestBranches.length + 1;
          mcrTestBranches.push({
            be_mat_label: 'Be_mat ' + next,
            finish_label: 'finish_code ' + next,
            variant_label: 'surface_variant ' + next,
            be_mat: [],
            finish_code: ['string'],
            surface_variant: []
          });
          renderMaterialCodeTestBuilder(collectMaterialCodeRules());
          return;
        }
        btn = ev.target.closest('[data-mcr-test-action="delete-branch"]');
        if (btn) {
          var branch = btn.closest('.mcr-branch-card');
          var inlineBranch = btn.closest('.mcr-inline-branch-cell');
          if (branch && branch.parentNode) {
            branch.parentNode.removeChild(branch);
            mcrTestBranches = collectMcrTestBranchesFromDom();
          } else if (inlineBranch) {
            var branchIndex = parseInt(inlineBranch.getAttribute('data-mcr-branch-index'), 10);
            mcrTestBranches = collectMcrTestBranchesFromDom();
            if (isFinite(branchIndex)) mcrTestBranches.splice(branchIndex, 1);
            renderMaterialCodeTestBuilder(collectMaterialCodeRules());
          }
          refreshMcrSystemColumnValues(collectMaterialCodeRules());
          updateMcrTestInputFromColumns(true);
          return;
        }
        btn = ev.target.closest('[data-mcr-test-action="add-branch-value"]');
        if (btn) {
          var branchCol = btn.closest('.mcr-branch-col, .mcr-inline-branch-cell');
          var branchList = branchCol && branchCol.querySelector('.mcr-branch-values');
          if (branchList) {
            branchList.appendChild(buildMcrBranchValue('', branchList.querySelectorAll('.mcr-branch-value').length));
            refreshMcrBranchOrders(mcrTestBuilder);
            var branchInputs = branchList.querySelectorAll('[data-mcr-branch-value]');
            if (branchInputs.length) branchInputs[branchInputs.length - 1].focus();
          }
          updateMcrTestInputFromColumns(true);
          return;
        }
        btn = ev.target.closest('[data-mcr-test-action="delete-branch-value"]');
        if (btn) {
          var branchItem = btn.closest('.mcr-branch-value');
          if (branchItem && branchItem.parentNode) branchItem.parentNode.removeChild(branchItem);
          refreshMcrBranchOrders(mcrTestBuilder);
          updateMcrTestInputFromColumns(true);
          return;
        }
        btn = ev.target.closest('[data-mcr-test-action="delete-value"]');
        if (btn) {
          var item = btn.closest('.mcr-test-value-card');
          if (item && item.parentNode) item.parentNode.removeChild(item);
          updateMcrTestInputFromColumns(true);
        }
      });
      mcrTestBuilder.addEventListener('dragstart', startMcrTestDrag);
      mcrTestBuilder.addEventListener('dragover', dragOverMcrTest);
      mcrTestBuilder.addEventListener('dragleave', function (ev) {
        var col = ev.target && ev.target.closest ? ev.target.closest('.mcr-test-col') : null;
        if (col) col.classList.remove('mcr-drop-target');
      });
      mcrTestBuilder.addEventListener('drop', dropMcrTest);
      mcrTestBuilder.addEventListener('dragend', endMcrTestDrag);
    }
    ['mcr_multi_separators', 'mcr_gloss_suffix_regex', 'mcr_test_input'].forEach(function (id) {
      on(id, 'input', function () {
        collectMaterialCodeRulesIntoState();
        updateMaterialCodePreview();
      });
    });
    ['mcr_segment_separator', 'mcr_test_separator'].forEach(function (id) {
      on(id, 'input', function () {
        syncMcrSegmentSeparator($(id).value, false);
        collectMaterialCodeRulesIntoState();
        updateMaterialCodePreview();
      });
      on(id, 'change', function () {
        syncMcrSegmentSeparator($(id).value, true);
        collectMaterialCodeRulesIntoState();
        updateMaterialCodePreview();
      });
    });
    ['pcr_segment_separator', 'pcr_test_separator'].forEach(function (id) {
      on(id, 'input', function () {
        syncProductCodeSeparator($(id).value);
      });
      on(id, 'change', function () {
        syncProductCodeSeparator($(id).value);
      });
    });
    on('pcr_uppercase', 'change', function () {
      collectProductCodeRulesIntoState();
      renderProductCodeContract(productCodeRules());
    });
    on('mcr_gloss_mode', 'change', function () {
      updateMcrGlossVisibility();
      collectMaterialCodeRulesIntoState();
      updateMaterialCodePreview();
    });
    on('mcr_uppercase', 'change', function () {
      collectMaterialCodeRulesIntoState();
      updateMaterialCodePreview();
    });
    on('btnSaveSuperimp', 'click', saveSuperimp);
    on('btnLearnDCParams', 'click', learnDCParams);
    on('btnAddExtraParam', 'click', addExtraParam);
    on('btnCreateBinding', 'click', createBinding);
    on('btnChooseInput', 'click', chooseMVLInput);
    on('btnMarkProducts', 'click', markProducts);
    on('btnMarkProductsAuto', 'click', markProductsAuto);
    on('btnRunMVL', 'click', runMVL);
    on('btnReloadMVLExcel', 'click', reloadMVLExcel);
    on('btnOpenOutput', 'click', openMVLOutput);
    on('btnAssignSelection', 'click', assignSelection);
    on('btnAssignAll', 'click', assignAll);
    on('nc_active_sub_prefix', 'change', function () { onColumnChange('sub_prefix'); });
    on('nc_active_prefix', 'change', function () { onColumnChange('prefix'); });
    on('nc_active_modul', 'change', function () { onColumnChange('modul'); });
    ['nc_sep_sub_prefix', 'nc_sep_prefix', 'nc_sep_suffix', 'nc_default_prefix', 'nc_sub_prefix', 'nc_prefix', 'nc_modul', 'nc_suffix'].forEach(function (id) {
      on(id, 'input', updateNamePreview);
    });
    signalEmbeddedReady();
    loadData();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();

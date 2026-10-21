var PRESET_PANEL_HTML = '<div class="col3 preset-container" @click="clearPresetSelection">'
    + '<h3>Cài đặt mẫu</h3>'
    + '<div class="preset-form" style="padding-top:7px;" @click.stop>'
    + '<input type="text" v-model="newPresetName" @input="clearSelectedPreset" @keyup.enter="handleSaveOrGroup" placeholder="Nhập tên..." class="preset-input">'
    + '<div class="preset-button-group">'
    + '<button @click="handleSaveOrGroup" :disabled="saveButtonDisabled" class="preset-button preset-button-save">{{ saveButtonText }}</button>'
    + '<button @click="deletePresetByName" :disabled="deleteButtonDisabled" class="preset-button preset-button-delete">Xóa</button>'
    + '</div></div>'
    + '<div class="preset-list" :class="{\'dragging-active\': draggedIndex !== null}" @dragover="handleDragOver($event)" @drop="handleDrop($event)">'
    + '<div v-if="presets.length === 0" class="preset-list-empty">Chưa có cài đặt mẫu nào. Nhập tên và bấm nút lưu để tạo cài đặt mẫu mới.</div>'
    + '<template v-for="(item, idx) in flatDisplayList">'
    + '<div v-if="item.type === \'header\'" :key="\'gh-\' + idx" class="preset-group-header" :class="{\'collapsed\': item.collapsed, \'group-selected\': selectedGroup === item.name}" @click.stop="selectGroup(item.name)">'
    + '<span class="preset-group-label" @click.stop="toggleGroupCollapse(item.name)">'
    + '<span class="preset-group-toggle">▾</span>'
    + '<span class="preset-group-name">{{ item.name }}</span>'
    + '</span>'
    + '<span style="flex:1"></span>'
    + '<label class="preset-checkbox" @click.stop>'
    + '<input type="checkbox" :checked="isGroupEnabled(item.name)" @change="toggleGroupActive(item.name)">'
    + '</label></div>'
    + '<div v-else :key="\'pi-\' + idx" draggable="true" @click.stop="handlePresetClick(item.preset, item.index, $event)" @dragstart="handleDragStart(item.index, $event)" @dragend="handleDragEnd" :class="[\'preset-item\', {\'dragging\': draggedIndex === item.index, \'drag-gap\': insertBeforeIndex === item.index, \'drag-gap-end\': insertBeforeIndex === presets.length && item.index === presets.length - 1, \'preset-item-active\': isPresetSelected(item.index) && !item.preset.disabled, \'preset-item-active-disabled\': isPresetSelected(item.index) && item.preset.disabled, \'preset-item-disabled\': item.preset.disabled, \'preset-item-grouped\': item.grouped, \'preset-item-grouped-last\': item.lastInGroup}]">'
    + '<span class="preset-item-text">{{ item.preset.name }}</span>'
    + '<label class="preset-checkbox" @click.stop>'
    + '<input type="checkbox" :checked="!item.preset.disabled" @change="togglePresetActive(item.index)">'
    + '</label></div>'
    + '</template>'
    + '</div></div>';

function SettingsMixin(tabId) {
    return {
        data: function() {
            return {
                hideUnavailable: true,
                presets: [],
                newPresetName: '',
                draggedIndex: null,
                insertBeforeIndex: null,
                selectedPresetIndices: [],
                collapsedGroups: {},
                lastClickedIndex: null,
                selectedGroup: null
            };
        },
        computed: {
            isMultiSelect: function() {
                return this.selectedPresetIndices.length > 1;
            },
            saveButtonText: function() {
                return this.isMultiSelect ? 'Nhóm' : 'Lưu';
            },
            saveButtonDisabled: function() {
                if (this.isMultiSelect) return false;
                if (this.selectedGroup) return false;
                return !this.newPresetName.trim();
            },
            deleteButtonDisabled: function() {
                if (this.isMultiSelect) return false;
                if (this.selectedGroup) return false;
                return !this.newPresetName.trim();
            },
            flatDisplayList: function() {
                var result = [];
                var groups = {};
                var groupOrder = [];
                var ungrouped = [];
                var self = this;

                this.presets.forEach(function(preset, index) {
                    if (preset.group) {
                        if (!groups[preset.group]) {
                            groups[preset.group] = [];
                            groupOrder.push(preset.group);
                        }
                        groups[preset.group].push({ preset: preset, index: index });
                    } else {
                        ungrouped.push({ preset: preset, index: index });
                    }
                });

                ungrouped.forEach(function(item) {
                    result.push({ type: 'preset', preset: item.preset, index: item.index, grouped: false });
                });

                groupOrder.forEach(function(groupName) {
                    var collapsed = !!self.collapsedGroups[groupName];
                    result.push({ type: 'header', name: groupName, collapsed: collapsed });
                    if (!collapsed) {
                        var items = groups[groupName];
                        items.forEach(function(item, i) {
                            result.push({ type: 'preset', preset: item.preset, index: item.index, grouped: true, lastInGroup: i === items.length - 1 });
                        });
                    }
                });

                return result;
            }
        },
        methods: {
            saveSetting(key) {
                var value = this.settings[key];
                if (window.parent !== window) {
                    window.parent.postMessage({
                        action: 'save_setting',
                        tabId: tabId,
                        key: key,
                        value: value
                    }, '*');
                }
            },

            saveColor(key) {
                this.saveSetting(key);
            },

            incrementValue(key, step) {
                if (step === undefined) step = 0.1;
                this.settings[key] = parseFloat((this.settings[key] + step).toFixed(2));
                this.saveSetting(key);
            },

            decrementValue(key, step) {
                if (step === undefined) step = 0.1;
                this.settings[key] = parseFloat((this.settings[key] - step).toFixed(2));
                this.saveSetting(key);
            },

            validateNumber(key) {
                if (isNaN(this.settings[key])) {
                    this.settings[key] = 0;
                }
                this.settings[key] = parseFloat(this.settings[key].toFixed(2));
            },

            incrementInt(key, max) {
                if (max === undefined) max = Infinity;
                if (this.settings[key] < max) {
                    this.settings[key] += 1;
                    this.saveSetting(key);
                }
            },

            decrementInt(key, min) {
                if (min === undefined) min = 1;
                if (this.settings[key] > min) {
                    this.settings[key] -= 1;
                    this.saveSetting(key);
                }
            },

            validateInt(key, min, max) {
                if (min === undefined) min = 1;
                if (max === undefined) max = Infinity;
                var n = parseInt(this.settings[key], 10);
                if (isNaN(n) || n < min) n = min;
                if (n > max) n = max;
                this.settings[key] = n;
                this.saveSetting(key);
            },

            validateIntRange(key, min, max) {
                this.validateInt(key, min, max);
            },

            loadSettings(settingsData) {
                var self = this;
                Object.keys(settingsData).forEach(function (key) {
                    if (self.settings.hasOwnProperty(key)) {
                        var value = settingsData[key];
                        if (typeof value === 'string' && !isNaN(value) && value !== '') {
                            value = parseFloat(value);
                        }
                        if (self.isColorKey(key) && typeof value === 'string') {
                            value = value.split(',').map(function (v) {
                                return parseInt(v.trim());
                            });
                        }
                        if (typeof value === 'number' && !Number.isInteger(value)) {
                            value = parseFloat(value.toFixed(2));
                        }
                        self.settings[key] = value;
                    }
                });
            },

            isColorKey(key) {
                return key.startsWith('mau_') || key.endsWith('_mau');
            },

            requestLoadPresets() {
                if (window.parent !== window) {
                    window.parent.postMessage({
                        action: 'load_presets',
                        tabId: tabId
                    }, '*');
                }
            },

            saveNewPreset() {
                var name = this.newPresetName.trim();
                if (!name) return;

                var self = this;
                var settingsToSave = {};
                Object.keys(this.settings).forEach(function (key) {
                    var value = self.settings[key];
                    if (self.isColorKey(key) && Array.isArray(value)) {
                        value = value.join(',');
                    }
                    settingsToSave[key] = value;
                });

                if (window.parent !== window) {
                    window.parent.postMessage({
                        action: 'save_preset',
                        tabId: tabId,
                        presetName: name,
                        settings: settingsToSave
                    }, '*');
                }
                this.newPresetName = '';
                this.selectedPresetIndices = [];
            },

            loadPreset(presetName) {
                if (window.parent !== window) {
                    window.parent.postMessage({
                        action: 'load_preset',
                        tabId: tabId,
                        presetName: presetName
                    }, '*');
                }
            },

            isPresetSelected: function(index) {
                return this.selectedPresetIndices.indexOf(index) !== -1;
            },

            handlePresetClick: function(preset, index, event) {
                this.selectedGroup = null;
                if (event.ctrlKey || event.metaKey) {
                    var pos = this.selectedPresetIndices.indexOf(index);
                    if (pos !== -1) {
                        this.selectedPresetIndices.splice(pos, 1);
                    } else {
                        this.selectedPresetIndices.push(index);
                    }
                    this.lastClickedIndex = index;
                    if (this.selectedPresetIndices.length === 1) {
                        var selIdx = this.selectedPresetIndices[0];
                        this.newPresetName = this.presets[selIdx].name;
                        this.loadPreset(this.presets[selIdx].name);
                    } else {
                        this.newPresetName = '';
                    }
                } else if (event.shiftKey && this.lastClickedIndex !== null) {
                    var visualOrder = [];
                    this.flatDisplayList.forEach(function(item) {
                        if (item.type === 'preset') visualOrder.push(item.index);
                    });
                    var startVisual = visualOrder.indexOf(this.lastClickedIndex);
                    var endVisual = visualOrder.indexOf(index);
                    if (startVisual !== -1 && endVisual !== -1) {
                        var from = Math.min(startVisual, endVisual);
                        var to = Math.max(startVisual, endVisual);
                        var newSelection = [];
                        for (var i = from; i <= to; i++) {
                            newSelection.push(visualOrder[i]);
                        }
                        this.selectedPresetIndices = newSelection;
                    }
                    this.newPresetName = '';
                } else {
                    if (this.selectedPresetIndices.length === 1 && this.selectedPresetIndices[0] === index) {
                        this.selectedPresetIndices = [];
                        this.newPresetName = '';
                    } else {
                        this.selectedPresetIndices = [index];
                        this.newPresetName = preset.name;
                        this.loadPreset(preset.name);
                    }
                    this.lastClickedIndex = index;
                }
            },

            handleSaveOrGroup: function() {
                if (this.isMultiSelect) {
                    this.groupSelectedPresets();
                } else if (this.selectedGroup) {
                    this.renameGroup();
                } else {
                    this.saveNewPreset();
                }
            },

            renameGroup: function() {
                var oldName = this.selectedGroup;
                var newName = this.newPresetName.trim() || oldName;
                if (newName !== oldName) {
                    var self = this;
                    this.presets.forEach(function(preset) {
                        if (preset.group === oldName) {
                            self.$set(preset, 'group', newName);
                        }
                    });
                    if (this.collapsedGroups[oldName]) {
                        this.$set(this.collapsedGroups, newName, true);
                        this.$delete(this.collapsedGroups, oldName);
                    }
                    this.savePresetsOrder();
                }
                this.selectedGroup = null;
                this.newPresetName = '';
            },

            groupSelectedPresets: function() {
                var groupName = this.newPresetName.trim() || 'Chưa đặt tên';
                var self = this;
                this.selectedPresetIndices.forEach(function(index) {
                    self.$set(self.presets[index], 'group', groupName);
                });
                this.selectedPresetIndices = [];
                this.newPresetName = '';
                this.lastClickedIndex = null;
                this.savePresetsOrder();
            },

            toggleGroupCollapse: function(groupName) {
                this.$set(this.collapsedGroups, groupName, !this.collapsedGroups[groupName]);
                this.saveCollapsedGroups();
            },

            selectGroup: function(groupName) {
                if (this.selectedGroup === groupName) {
                    this.selectedGroup = null;
                    this.newPresetName = '';
                } else {
                    this.selectedGroup = groupName;
                    this.newPresetName = groupName;
                }
                this.selectedPresetIndices = [];
            },

            isGroupEnabled: function(groupName) {
                var groupPresets = this.presets.filter(function(p) { return p.group === groupName; });
                if (groupPresets.length === 0) return false;
                return groupPresets.every(function(p) { return !p.disabled; });
            },

            toggleGroupActive: function(groupName) {
                var enabled = this.isGroupEnabled(groupName);
                var self = this;
                this.presets.forEach(function(preset, index) {
                    if (preset.group === groupName) {
                        self.$set(preset, 'disabled', enabled);
                    }
                });
                this.savePresetsOrder();
            },

            loadPresetAndSetName(presetName, index) {
                this.handlePresetClick({ name: presetName }, index, { ctrlKey: false, metaKey: false, shiftKey: false });
            },

            deletePreset(presetName) {
                if (window.parent !== window) {
                    window.parent.postMessage({
                        action: 'delete_preset',
                        tabId: tabId,
                        presetName: presetName
                    }, '*');
                }
            },

            deletePresetByName() {
                if (this.isMultiSelect) {
                    var self = this;
                    var names = [];
                    this.selectedPresetIndices.forEach(function(idx) {
                        if (self.presets[idx]) names.push(self.presets[idx].name);
                    });
                    names.forEach(function(name) { self.deletePreset(name); });
                    this.selectedPresetIndices = [];
                    this.newPresetName = '';
                    return;
                }
                if (this.selectedGroup) {
                    var groupName = this.selectedGroup;
                    var self = this;
                    this.presets.forEach(function(preset) {
                        if (preset.group === groupName) {
                            self.$set(preset, 'group', undefined);
                        }
                    });
                    this.$delete(this.collapsedGroups, groupName);
                    this.selectedGroup = null;
                    this.newPresetName = '';
                    this.savePresetsOrder();
                    return;
                }
                var name = this.newPresetName.trim();
                if (!name) return;
                var exists = this.presets.some(function (p) {
                    return p.name === name;
                });
                if (exists) {
                    this.deletePreset(name);
                    this.newPresetName = '';
                    this.selectedPresetIndices = [];
                }
            },

            clearSelectedPreset() {
                if (!this.isMultiSelect) {
                    this.selectedPresetIndices = [];
                }
            },

            clearPresetSelection() {
                this.selectedPresetIndices = [];
                this.newPresetName = '';
                this.selectedGroup = null;
            },

            receivePresets(presetsData, collapsedGroups) {
                this.presets = presetsData;
                if (collapsedGroups) {
                    this.collapsedGroups = collapsedGroups;
                }
            },

            togglePresetActive(index) {
                var preset = this.presets[index];
                this.$set(preset, 'disabled', !preset.disabled);
                if (preset.disabled) {
                    var pos = this.selectedPresetIndices.indexOf(index);
                    if (pos !== -1) {
                        this.selectedPresetIndices.splice(pos, 1);
                        if (this.selectedPresetIndices.length === 0) {
                            this.newPresetName = '';
                        }
                    }
                }
                this.savePresetsOrder();
            },

            applyPresetSettings(presetSettings) {
                var self = this;
                Object.keys(presetSettings).forEach(function (key) {
                    if (self.settings.hasOwnProperty(key)) {
                        var value = presetSettings[key];
                        if (typeof value === 'string' && !isNaN(value) && value !== '') {
                            value = parseFloat(value);
                        }
                        if (self.isColorKey(key) && typeof value === 'string') {
                            value = value.split(',').map(function (v) {
                                return parseInt(v.trim());
                            });
                        }
                        if (typeof value === 'number' && !Number.isInteger(value)) {
                            value = parseFloat(value.toFixed(2));
                        }
                        self.$set(self.settings, key, value);
                    }
                });
            },

            handleDragStart(index, event) {
                this.draggedIndex = index;
                this.insertBeforeIndex = null;
                event.dataTransfer.effectAllowed = 'move';
                event.dataTransfer.setData('text/html', '');
                var listEl = event.currentTarget.closest('.preset-list');
                var items = listEl.querySelectorAll('.preset-group-header, [draggable]');
                var mids = [];
                for (var i = 0; i < items.length; i++) {
                    var rect = items[i].getBoundingClientRect();
                    mids.push(rect.top + rect.height / 2);
                }
                this._itemMids = mids;
                this._dragFlatItems = this.flatDisplayList.slice();
            },

            handleDragOver(event) {
                event.preventDefault();
                event.dataTransfer.dropEffect = 'move';
                if (this.draggedIndex === null || !this._itemMids) return;
                var y = event.clientY;
                var insertBefore = this._itemMids.length;
                for (var i = 0; i < this._itemMids.length; i++) {
                    if (y < this._itemMids[i]) {
                        insertBefore = i;
                        break;
                    }
                }
                var flatItems = this._dragFlatItems;
                var draggedFlatIdx = -1;
                for (var i = 0; i < flatItems.length; i++) {
                    if (flatItems[i].type === 'preset' && flatItems[i].index === this.draggedIndex) {
                        draggedFlatIdx = i;
                        break;
                    }
                }
                if (insertBefore === draggedFlatIdx || insertBefore === draggedFlatIdx + 1) {
                    this.insertBeforeIndex = null;
                    this._visualInsertBefore = null;
                } else {
                    this._visualInsertBefore = insertBefore;
                    var found = false;
                    for (var i = insertBefore; i < flatItems.length; i++) {
                        if (flatItems[i].type === 'preset') {
                            this.insertBeforeIndex = flatItems[i].index;
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        this.insertBeforeIndex = this.presets.length;
                    }
                }
            },

            handleDrop(event) {
                event.preventDefault();
                event.stopPropagation();

                if (this.draggedIndex !== null && this.insertBeforeIndex !== null && this._visualInsertBefore !== null) {
                    var vib = this._visualInsertBefore;
                    var flatItems = this._dragFlatItems;
                    var self = this;

                    var targetGroup = undefined;
                    for (var i = vib - 1; i >= 0; i--) {
                        var item = flatItems[i];
                        if (item.type === 'preset' && item.index === this.draggedIndex) continue;
                        if (item.type === 'header') {
                            targetGroup = item.name;
                            break;
                        } else if (item.type === 'preset') {
                            targetGroup = item.preset.group;
                            break;
                        }
                    }

                    var draggedPreset = this.presets[this.draggedIndex];
                    this.$set(draggedPreset, 'group', targetGroup);

                    var targetOrigIdx = -1;
                    for (var i = vib; i < flatItems.length; i++) {
                        if (flatItems[i].type === 'preset' && flatItems[i].index !== this.draggedIndex) {
                            targetOrigIdx = flatItems[i].index;
                            break;
                        }
                    }

                    var selectedNames = [];
                    this.selectedPresetIndices.forEach(function(idx) {
                        if (self.presets[idx]) selectedNames.push(self.presets[idx].name);
                    });

                    var newPresets = this.presets.slice();
                    newPresets.splice(this.draggedIndex, 1);
                    if (targetOrigIdx !== -1) {
                        if (targetOrigIdx > this.draggedIndex) targetOrigIdx--;
                        newPresets.splice(targetOrigIdx, 0, draggedPreset);
                    } else {
                        newPresets.push(draggedPreset);
                    }
                    this.presets = newPresets;

                    if (selectedNames.length > 0) {
                        var newIndices = [];
                        for (var i = 0; i < this.presets.length; i++) {
                            if (selectedNames.indexOf(this.presets[i].name) !== -1) {
                                newIndices.push(i);
                            }
                        }
                        this.selectedPresetIndices = newIndices;
                    }

                    this.savePresetsOrder();
                }

                this.draggedIndex = null;
                this.insertBeforeIndex = null;
                this._itemMids = null;
                this._dragFlatItems = null;
                this._visualInsertBefore = null;
            },

            handleDragEnd() {
                this.draggedIndex = null;
                this.insertBeforeIndex = null;
                this._itemMids = null;
                this._dragFlatItems = null;
                this._visualInsertBefore = null;
            },

            savePresetsOrder() {
                if (window.parent !== window) {
                    window.parent.postMessage({
                        action: 'save_presets_order',
                        tabId: tabId,
                        presets: this.presets
                    }, '*');
                }
            },

            saveCollapsedGroups() {
                if (window.parent !== window) {
                    window.parent.postMessage({
                        action: 'save_collapsed_groups',
                        tabId: tabId,
                        collapsedGroups: this.collapsedGroups
                    }, '*');
                }
            },

            resetSection() {
                if (window.parent !== window) {
                    window.parent.postMessage({
                        action: 'reset_section',
                        tabId: tabId
                    }, '*');
                }
            },

            resetToDefault(key) {
                if (this._defaults && this._defaults.hasOwnProperty(key)) {
                    this.$set(this.settings, key, JSON.parse(JSON.stringify(this._defaults[key])));
                    this.saveSetting(key);
                }
            }
        },

        beforeCreate() {
            var presetEl = document.getElementById('preset-panel');
            if (presetEl) presetEl.outerHTML = PRESET_PANEL_HTML;

            var appEl = document.querySelector('#app');
            if (appEl) {
                var groups = appEl.querySelectorAll('.number-input-group');
                var keyMap = [];
                for (var i = 0; i < groups.length; i++) {
                    var input = groups[i].querySelector('input');
                    if (input) {
                        var binding = input.getAttribute('v-model.number') || input.getAttribute('v-model');
                        keyMap.push(binding ? binding.replace('settings.', '') : null);
                    } else {
                        keyMap.push(null);
                    }
                }
                this._spinnerKeyMap = keyMap;
            }
        },

        created() {
            this._defaults = JSON.parse(JSON.stringify(this.settings));
        },

        mounted() {
            var self = this;

            if (this._spinnerKeyMap) {
                var groups = this.$el.querySelectorAll('.number-input-group');
                for (var i = 0; i < groups.length; i++) {
                    if (this._spinnerKeyMap[i]) {
                        groups[i].setAttribute('data-key', this._spinnerKeyMap[i]);
                    }
                }
            }

            this.$el.addEventListener('contextmenu', function (event) {
                var btn = event.target.closest('.spinner-btn');
                if (!btn) return;
                event.preventDefault();
                var group = btn.closest('.number-input-group');
                if (!group) return;
                var key = group.getAttribute('data-key');
                if (!key) return;
                self.resetToDefault(key);
            });

            window.addEventListener('message', function (event) {
                if (!event.data) return;

                switch (event.data.action) {
                    case 'loadSettings':
                        self.hideUnavailable = event.data.hideUnavailable !== undefined ? !!event.data.hideUnavailable : true;
                        self.loadSettings(event.data.settings);
                        break;
                    case 'set_hide_unavailable':
                        self.hideUnavailable = !!event.data.value;
                        break;
                    case 'presets_loaded':
                        if (self.receivePresets) self.receivePresets(event.data.presets, event.data.collapsedGroups);
                        break;
                    case 'preset_settings_loaded':
                        if (self.applyPresetSettings) self.applyPresetSettings(event.data.settings);
                        break;
                    case 'search_highlight':
                        var sq = (event.data.query || '').toLowerCase();
                        var allSw = self.$el.querySelectorAll('.switch');
                        for (var si = 0; si < allSw.length; si++) {
                            var sw = allSw[si];
                            var sp = sw.querySelector(':scope > span');
                            if (sq && sp && sp.textContent.trim().toLowerCase().indexOf(sq) !== -1) {
                                sw.classList.add('search-match');
                            } else {
                                sw.classList.remove('search-match');
                            }
                        }
                        if (sq) {
                            var cats = self.$el.querySelectorAll('.category');
                            for (var ci = 0; ci < cats.length; ci++) {
                                if (cats[ci].querySelector('.search-match')) {
                                    cats[ci].classList.remove('collapsed');
                                }
                            }
                            var fm = self.$el.querySelector('.search-match');
                            if (fm) fm.scrollIntoView({ behavior: 'smooth', block: 'center' });
                        }
                        break;
                }
            });

            if (window.parent !== window) {
                var searchItems = [];
                var spans = self.$el.querySelectorAll('.switch > span');
                for (var i = 0; i < spans.length; i++) {
                    searchItems.push(spans[i].textContent.trim());
                }
                var headers = self.$el.querySelectorAll('h3');
                for (var i = 0; i < headers.length; i++) {
                    searchItems.push(headers[i].textContent.trim());
                }
                window.parent.postMessage({
                    action: 'iframe_ready',
                    tabId: tabId
                }, '*');
                window.parent.postMessage({
                    action: 'search_index',
                    tabId: tabId,
                    items: searchItems
                }, '*');
            }

            if (this.presets !== undefined) {
                setTimeout(function () {
                    self.requestLoadPresets();
                }, 300);
            }

            initCategories(self, tabId);

            if (tabId !== 'chung') {
                var col3 = self.$el.querySelector('.col3');
                if (col3) {
                    col3.style.display = 'flex';
                    col3.style.flexDirection = 'column';
                    var spacer = document.createElement('div');
                    spacer.style.flex = '1';
                    col3.appendChild(spacer);
                    var footer = document.createElement('div');
                    footer.style.cssText = 'border-top:0.5px solid #e5e5ea; padding-top:10px; margin-top:15px;';
                    var tabName = tabId;
                    try {
                        var tabEl = window.parent.document.querySelector('.tab[data-tab="' + tabId + '"]');
                        if (tabEl) tabName = tabEl.textContent.trim();
                    } catch(e) {}
                    var btn = document.createElement('button');
                    btn.className = 'action-button-full danger';
                    btn.style.cssText = 'padding:6px 10px;';
                    btn.title = 'Đặt lại toàn bộ cài đặt của mục ' + tabName + ' về mặc định.';
                    btn.textContent = 'Đặt lại cài đặt gốc';
                    btn.addEventListener('click', function () {
                        self.resetSection();
                    });
                    footer.appendChild(btn);
                    col3.appendChild(footer);
                }
            }
        }
    };
}

var _categoryMap = [];

function initCategories(vue, storeKey) {
    var col2 = document.querySelector('.col2');
    if (!col2) return;

    // Lưu trạng thái thu gọn theo từng tab (localStorage) để mở lại còn nhớ.
    var lsKey = 'mhcp_cat_' + (storeKey || (location.pathname.split('/').pop() || 'panel'));
    var saved = {};
    try { saved = JSON.parse(localStorage.getItem(lsKey) || '{}') || {}; } catch (e) { saved = {}; }
    function persist() { try { localStorage.setItem(lsKey, JSON.stringify(saved)); } catch (e) {} }

    var children = Array.prototype.slice.call(col2.children);
    var categories = [];
    var current = null;

    children.forEach(function(el) {
        if (el.tagName === 'H3') {
            current = { header: el, items: [] };
            categories.push(current);
        } else if (current) {
            current.items.push(el);
        }
    });

    _categoryMap = [];
    categories.forEach(function(cat) {
        var wrapper = document.createElement('div');
        wrapper.className = 'category';
        var name = cat.header.textContent.trim();

        cat.header.classList.add('category-header');
        col2.insertBefore(wrapper, cat.header);
        wrapper.appendChild(cat.header);

        var content = document.createElement('div');
        content.className = 'category-content';
        cat.items.forEach(function(el) { content.appendChild(el); });
        wrapper.appendChild(content);

        if (saved[name] === true) wrapper.classList.add('collapsed');

        _categoryMap.push({ wrapper: wrapper, name: name });

        cat.header.addEventListener('click', function() {
            wrapper.classList.toggle('collapsed');
            saved[name] = wrapper.classList.contains('collapsed');
            persist();
        });
    });

    var inner = document.createElement('div');
    inner.className = 'col2-inner';
    while (col2.firstChild) {
        inner.appendChild(col2.firstChild);
    }
    col2.appendChild(inner);
}


function colorComputed(settingsKey) {
    return {
        get: function () {
            var rgb = this.settings[settingsKey];
            if (!rgb || !Array.isArray(rgb)) return '#000000';
            var r = rgb[0].toString(16).padStart(2, '0');
            var g = rgb[1].toString(16).padStart(2, '0');
            var b = rgb[2].toString(16).padStart(2, '0');
            return '#' + r + g + b;
        },
        set: function (hex) {
            var r = parseInt(hex.substr(1, 2), 16);
            var g = parseInt(hex.substr(3, 2), 16);
            var b = parseInt(hex.substr(5, 2), 16);
            this.settings[settingsKey] = [r, g, b];
        }
    };
}


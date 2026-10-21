// Run the actual Ruby-rendered dialog script with an instrumented DOM.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const ruby = `require './MH_Van/test/sketchup_stub';
$LOADED_FEATURES << 'sketchup.rb';
$LOADED_FEATURES << File.expand_path('MH_shared.rb');
require './MH_Van/main'; puts MH::Van.send(:html)`;
const html = execFileSync('ruby', ['-e', ruby], { cwd: root, encoding: 'utf8' });
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const callbacks = [];
class Node {
  constructor() {
    this.dataset = {}; this.listeners = {}; this.classes = new Set(); this.attributes = {};
    this.htmlWrites = 0; this.buttons = []; this.checked = false;
    this.classList = {
      contains: (name) => this.classes.has(name),
      toggle: (name, enabled) => enabled ? this.classes.add(name) : this.classes.delete(name),
    };
  }
  set innerHTML(html) {
    this.htmlWrites++; this.html = html;
    this.buttons = Array.from(html.matchAll(/<button class="eye ([^"]*)"[^>]*data-action="visible" data-key="([^"]*)"/g), (match) => {
      const button = new Node(); button.dataset.key = match[2];
      if (match[1] === 'off') button.classes.add('off');
      return button;
    });
  }
  get innerHTML() { return this.html; }
  querySelectorAll() { return this.buttons; }
  setAttribute(key, value) { this.attributes[key] = value; }
  addEventListener(name, callback) { this.listeners[name] = callback; }
}
const nodes = new Map();
const tabs = ['nesting', 'no-nesting', 'surface'].map((tab) => { const node = new Node(); node.dataset.tab = tab; return node; });
const document = {
  activeElement: null,
  getElementById: (id) => { if (!nodes.has(id)) nodes.set(id, new Node()); return nodes.get(id); },
  querySelectorAll: (selector) => selector === '.tab' ? tabs : [],
  addEventListener() {},
};
const sketchup = new Proxy({}, { get: (_, name) => (...args) => callbacks.push([name, args]) });
const context = vm.createContext({ document, window: { sketchup }, sketchup });
vm.runInContext(script, context);
const rows = Array.from({ length: 1000 }, (_, i) => ({ key: `row_${i}`, code: `MDF_${i}`, thickness: '18', thickness_value: 18, count: 1, ids: [i+1], visible: true, all_hidden: false }));
context.renderRows(rows);
const body = nodes.get('rows');
assert.equal(body.htmlWrites, 1);
const editing = new Node(); editing.classes.add('code'); editing.value = 'unfinished user edit';
document.activeElement = editing;
context.updateVisibility([{ key: 'row_999', visible: false, all_hidden: true }]);
assert.equal(body.htmlWrites, 1, 'visibility change must not reconstruct the table');
assert.equal(body.buttons[999].classes.has('off'), true);
assert.equal(editing.value, 'unfinished user edit');
assert.equal(nodes.get('master').indeterminate, true);
context.updateVisibility(rows.map((row) => ({ key: row.key, visible: false, all_hidden: true })));
assert.equal(body.htmlWrites, 1);
assert.equal(nodes.get('master').checked, false);
assert.equal(nodes.get('master').indeterminate, false);
document.activeElement = null;
tabs[1].listeners.click(); tabs[0].listeners.click();
assert.deepEqual(callbacks.slice(-2).map(([name]) => name), ['refresh_no_nesting', 'refresh_nesting']);
context.syncFastVisibility({ enabled: true });
assert.equal(nodes.get('fastVisibility').checked, true);
console.log('Dialog regression checks passed: partial eye updates, preserved edit, master state, tab scope.');

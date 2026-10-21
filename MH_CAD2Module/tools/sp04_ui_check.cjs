const fs = require('fs');
const path = require('path');
const assert = require('assert');
const {pathToFileURL} = require('url');
const {chromium} = require('playwright');
(async () => {
  const root = path.resolve(__dirname, '..');
  const product = JSON.parse(fs.readFileSync(path.join(root, 'outputs', 'sp04-eleven-modules.json'), 'utf8'));
  const actual = JSON.parse(fs.readFileSync(path.join(root, 'outputs', 'sp04-eleven-native.json'), 'utf8')).state;
  const browser = await chromium.launch({channel: 'msedge', headless: true});
  try {
    const page = await browser.newPage({viewport: {width: 1120, height: 900}});
    const errors = []; page.on('pageerror', e => errors.push(e.message));
    await page.goto(pathToFileURL(path.join(root, 'ui', 'manager.html')).href);
    await page.evaluate(state => window.receive(state), {settings: {sources: [product.source_path]}, products: [product],
      focused: product, current_modules: actual.modules, errors: [], history: [], correction: null});
    assert.equal(await page.locator('#modules tr').count(), 11);
    assert.equal(await page.locator('#modules tr').filter({hasText: 'Vách giữa'}).count(), 1);
    assert.deepEqual(errors, []);
    console.log('SP04 UI: 11 module rows, detailed wall counted once, no script errors.');
  } finally { await browser.close(); }
})();

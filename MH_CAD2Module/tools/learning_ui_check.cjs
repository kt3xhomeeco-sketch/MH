const fs = require('fs');
const path = require('path');
const assert = require('assert');
const {pathToFileURL} = require('url');
const {chromium} = require('playwright');
(async () => {
  const root = path.resolve(__dirname, '..');
  const product = JSON.parse(fs.readFileSync(path.join(root, 'outputs', 'learning-native-product.json'), 'utf8'));
  const browser = await chromium.launch({channel: 'msedge', headless: true});
  try {
    const page = await browser.newPage({viewport: {width: 1120, height: 900}});
    const errors = []; page.on('pageerror', e => errors.push(e.message));
    await page.goto(pathToFileURL(path.join(root, 'ui', 'manager.html')).href);
    const state = {settings: {sources: []}, products: [product], focused: product,
      current_modules: product.modules, errors: [], history: [], correction: null};
    await page.evaluate(s => window.receive(s), state);
    const explanation = await page.locator('#explanation').textContent();
    assert(explanation.includes('Suy rộng từ mẫu cùng cấu tạo'));
    assert(explanation.includes('mẫu SP21'));
    assert(explanation.includes('7 tấm/vách/nẹp'));
    assert.equal(await page.locator('#modules tr').count(), 4);
    const partial = {...product, status: 'needs_review', error: 'Mẫu thiếu nẹp nóc',
      learning: {mode: 'review', source_code: 'SP27', issues: [{message: 'Mẫu chưa đủ', excluded: ['nẹp nóc 100 mm']}]}};
    await page.evaluate(s => window.receive(s), {...state, products: [partial], focused: partial});
    assert((await page.locator('#explanation').textContent()).includes('nẹp nóc 100 mm'));
    assert((await page.locator('#products').textContent()).includes('Cần kiểm tra'));
    assert.deepEqual(errors, []);
    console.log('Learning UI passed: sample provenance, auxiliary roles, partial/review explanation.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });

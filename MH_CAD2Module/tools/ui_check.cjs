const fs = require('fs');
const path = require('path');
const assert = require('assert');
const {pathToFileURL} = require('url');
const {chromium} = require('playwright');
const root = path.resolve(__dirname, '..');
(async () => {
  const browser = await chromium.launch({channel: 'msedge', headless: true});
  const page = await browser.newPage({viewport: {width: 1120, height: 900}, deviceScaleFactor: 1});
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  const source = JSON.parse(fs.readFileSync(path.join(root, 'outputs', 'actual-analysis.json'), 'utf8'));
  const product = source.products[0];
  const state = {settings: {sources: [source.revision.original_path], library: path.join(root, 'library'), python: '', converter: ''},
    busy: false, message: 'Đã đọc SP60 từ hình học thực.', errors: [], labels: [],
    products: [product], focused: product, current_modules: product.modules.map((m, i) => ({...m, entity_id: i + 1})),
    correction: null, last_products: 'SP60'};
  try {
    await page.goto(pathToFileURL(path.join(root, 'ui', 'manager.html')).href);
    await page.evaluate((value) => { window.recorded = []; window.sketchup = {request: (text) => window.recorded.push(JSON.parse(text))}; window.receive(value); }, state);
    assert.equal(await page.locator('#products tr').count(), 1);
    assert.equal(await page.locator('#modules tr').count(), 3);
    assert(await page.locator('#explanation').textContent().then((text) => text.includes('không sử dụng DIM')));
    await page.locator('#check-view').click();
    assert.equal(await page.locator('#check-view').getAttribute('aria-pressed'), 'true');
    assert.equal(await page.evaluate(() => viewer.visibleOutlines().length), product.check_outlines.length);
    await page.locator('#check-view').click();
    assert.equal(await page.locator('#check-view').getAttribute('aria-pressed'), 'false');
    await page.getByRole('button', {name: 'Quét chọn', exact: true}).click();
    assert.equal(await page.evaluate(() => window.recorded.at(-1).action), 'scan_selection');
    const overflow = await page.evaluate(() => document.body.scrollWidth > innerWidth + 1);
    assert(!overflow, 'Manager has horizontal overflow');
    await page.screenshot({path: path.join(root, 'outputs', 'manager-preview.png'), fullPage: true});
    await page.setViewportSize({width: 760, height: 900});
    assert(await page.evaluate(() => document.body.scrollWidth <= innerWidth + 1));
    await page.goto(pathToFileURL(path.join(root, 'ui', 'entry.html')).href);
    await page.setViewportSize({width: 420, height: 260});
    await page.evaluate((value) => { window.recorded = []; window.sketchup = {request: (text) => window.recorded.push(JSON.parse(text))}; window.receive({...value, entry_mode: 'selection'}); }, state);
    await page.getByRole('button', {name: 'Dựng khối', exact: true}).click();
    assert.deepEqual(await page.evaluate(() => window.recorded.at(-1)), {action: 'build', products: 'SP60'});
    await page.screenshot({path: path.join(root, 'outputs', 'entry-preview.png')});
    assert.deepEqual(errors, []);
    console.log('UI passed: manager, scan button, CAD canvas, modules, entry callback, responsive layout.');
  } finally { await browser.close(); }
})().catch((error) => { console.error(error); process.exitCode = 1; });

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {pathToFileURL} = require('url');
const {chromium} = require('playwright');
(async () => {
  const root = path.resolve(__dirname, '..');
  const fixture = JSON.parse(fs.readFileSync(path.join(root, 'outputs/plan-rule-native-fixture.json'), 'utf8'));
  const browser = await chromium.launch({channel: 'msedge', headless: true});
  const page = await browser.newPage({viewport: {width: 1100, height: 950}});
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  try {
    await page.goto(pathToFileURL(path.join(root, 'ui/manager.html')).href);
    await page.evaluate(f => {
      window.ruleState = {settings: {sources: []}, busy: false, products: [], errors: [], current_modules: [],
        focused: f.products[0], plan_rules: f.summary};
      receive(ruleState);
    }, fixture);
    assert((await page.locator('#plan-rules-status').textContent()).includes('2 quy tắc đang dùng'));
    assert((await page.locator('#explanation').textContent()).includes('Quy tắc tự học từ 3'));
    assert((await page.locator('#plan-rules-details').textContent()).includes('kiểm thử 3/3'));
    await page.evaluate(() => receive({...ruleState, plan_rules: {updated_at: 'now', active: 0, waiting: 1, blocked: 1,
      minimum_examples: 3, rules: [{status: 'waiting', examples: ['a'], passed: 0, tested: 0,
        reason: 'Cần thêm mẫu cùng cấu tạo', sources: [{code: 'SCAN-X', event: 'abc123456789', size: [800, 600]}]}],
      issues: [{reason: 'Cách chia mâu thuẫn <b>giữ nguyên</b>'}]}}));
    assert((await page.locator('#plan-rules-status').textContent()).includes('1 đang chờ mẫu'));
    assert((await page.locator('#plan-rules-details').textContent()).includes('1/3 hình học'));
    assert((await page.locator('#plan-rules-details').textContent()).includes('800 × 600 mm'));
    assert.equal(await page.locator('#plan-rules-details b').count(), 0);
    const card = page.locator('section').filter({has: page.locator('#plan-rules-status')});
    await card.locator('summary').click();
    await card.screenshot({path: path.join(root, 'outputs/plan-rules-preview.png')});
    assert.deepEqual(errors, []);
    console.log('Plan rules UI passed: active/waiting/blocked counts, sample dimensions, tests, provenance and safe text.');
  } finally { await browser.close(); }
})().catch(error => {console.error(error); process.exitCode = 1;});

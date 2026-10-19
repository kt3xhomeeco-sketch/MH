const assert = require('assert');
const path = require('path');
const {pathToFileURL} = require('url');
const {chromium} = require('playwright');
(async () => {
  const browser = await chromium.launch({channel: 'msedge', headless: true});
  const page = await browser.newPage({viewport: {width: 1120, height: 950}});
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  try {
    await page.goto(pathToFileURL(path.resolve(__dirname, '../ui/manager.html')).href);
    await page.evaluate(() => {
      window.recorded = []; window.sketchup = {request: raw => recorded.push(JSON.parse(raw))};
      window.aiState = {settings: {sources: [], ai_enabled: true}, busy: false,
        products: [], errors: [], current_modules: [], local_ai: {ready: true, message: 'AI local sẵn sàng'},
        focused: {code: 'SCAN-A', automatic_scan: true, name: 'Vùng quét CAD', modules: [],
          local_ai: {message: 'AI đã đối chiếu', reason: '<b>safe text</b>', seconds: 12.34, cached: false},
          learning: {mode: 'local_ai', message: 'App đo lại các mặt trên CAD mới. Cao tạm 1600 mm.'}}};
      receive(aiState);
    });
    assert(await page.locator('#ai-enabled').isChecked());
    assert((await page.locator('#ai-status').textContent()).includes('sẵn sàng'));
    assert((await page.locator('#explanation').textContent()).includes('12,34 giây'));
    assert.equal(await page.locator('#explanation b').count(), 0);
    await page.evaluate(() => receive({...aiState,focused:{...aiState.focused,local_ai:{...aiState.focused.local_ai,
      workflow:'ai_plan_search_v2',rounds:2,selected_samples:[{event:'sample-001',code:'SCAN-SAMPLE'}],
      trace:[{stage:'find_samples',message:'AI tìm mẫu gần giống'},{stage:'decide',message:'AI quyết phương án cuối'}],
      final_check:{passed:true},rejected:[{reason:'Đường chia xuyên vách <b>giữ nguyên</b>'}]}}}));
    const explanation = await page.locator('#explanation').textContent();
    assert(explanation.includes('2 lượt AI') && explanation.includes('AI tìm mẫu gần giống') && explanation.includes('kiểm tra hình học cuối'));
    assert.equal(await page.locator('#explanation b').count(), 0);
    await page.locator('#ai-enabled').uncheck();
    assert.deepEqual(await page.evaluate(() => recorded.at(-1)), {action: 'save_settings',
      settings: {build_plan: true, build_elevation: false, build_auxiliary: true, ai_enabled: false}});
    await page.locator('[data-action="ai_status"]').click();
    assert.deepEqual(await page.evaluate(() => recorded.at(-1)), {action: 'ai_status'});
    await page.evaluate(() => receive({...aiState, busy: true}));
    assert(await page.locator('#ai-enabled').isDisabled());
    assert(await page.locator('[data-action="ai_status"]').isDisabled());
    await page.evaluate(() => receive({...aiState, local_ai: {ready: false, message: 'AI local chưa sẵn sàng'}}));
    assert((await page.locator('#ai-status').textContent()).includes('chưa sẵn sàng'));
    await page.screenshot({path: path.resolve(__dirname, '../outputs/local-ai-ui-preview.png')});
    assert.deepEqual(errors, []);
    console.log('Local AI UI passed: remembered toggle, worker health action, busy gating, provenance, safe text and offline status.');
  } finally { await browser.close(); }
})().catch(error => {console.error(error); process.exitCode = 1;});

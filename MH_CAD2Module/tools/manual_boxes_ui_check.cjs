const assert = require('assert');
const path = require('path');
const {pathToFileURL} = require('url');
const {chromium} = require('playwright');
(async () => {
  const browser = await chromium.launch({channel: 'msedge', headless: true});
  const page = await browser.newPage({viewport: {width: 1100, height: 900}});
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  try {
    await page.goto(pathToFileURL(path.resolve(__dirname, '../ui/manager.html')).href);
    await page.evaluate(() => {
      window.recorded = [];
      window.sketchup = {request: text => recorded.push(JSON.parse(text))};
      window.testState = {settings: {sources: []}, busy: false, products: [], errors: [], current_modules: []};
      window.receive(testState);
    });
    assert.equal(await page.locator('#scan-boxes, [data-action="scan_manual_boxes"]').count(), 0);
    assert(await page.locator('#accept-boxes').isDisabled());
    assert(await page.locator('#cancel-boxes').isDisabled());
    await page.locator('#wrong').click();
    assert.deepEqual(await page.evaluate(() => recorded.at(-1)), {action: 'wrong'});
    await page.evaluate(() => receive({...testState, correction: {manual: true, code: 'SCAN-test'}}));
    assert(await page.locator('#wrong').isDisabled());
    assert(!(await page.locator('#accept-boxes').isDisabled()));
    assert((await page.locator('#correction-status').textContent()).includes('Chọn các box đúng'));
    await page.locator('#accept-boxes').click();
    const request = await page.evaluate(() => recorded.at(-1));
    assert.equal(request.action, 'accept_manual_boxes');
    assert(request.request_id);
    assert.equal(await page.locator('#accept-boxes').textContent(), 'Đang lưu…');
    assert.equal(await page.locator('#accept-boxes').getAttribute('aria-busy'), 'true');
    assert(await page.locator('#accept-boxes').isDisabled());
    assert(await page.locator('#cancel-boxes').isDisabled());
    const count = await page.evaluate(() => recorded.length);
    await page.evaluate(() => document.querySelector('#accept-boxes').dispatchEvent(new MouseEvent('click')));
    assert.equal(await page.evaluate(() => recorded.length), count, 'Repeated clicks must not submit twice');
    await page.evaluate(() => receive({...testState, correction: {manual: true}}));
    assert(await page.locator('#accept-boxes').isDisabled(), 'An unrelated state must not end pending acceptance');
    await page.evaluate(id => receive({...testState, correction: {manual: true}, manual_acceptance: {
      status: 'error', request_id: id, message: 'Chọn các box đúng'}}), request.request_id);
    assert((await page.locator('#correction-status').textContent()).includes('Chưa xác nhận được'));
    assert(!(await page.locator('#accept-boxes').isDisabled()));
    await page.locator('#cancel-boxes').click();
    assert.deepEqual(await page.evaluate(() => recorded.at(-1)), {action: 'cancel_manual_boxes'});
    await page.locator('#accept-boxes').click();
    const retry = await page.evaluate(() => recorded.at(-1));
    assert.notEqual(retry.request_id, request.request_id);
    await page.evaluate(id => receive({...testState, correction: null, manual_acceptance: {
      status: 'saved', request_id: id, modules: 2, auxiliary: 1}}), retry.request_id);
    assert(await page.locator('#correction-status').isVisible());
    assert((await page.locator('#correction-status').textContent()).includes('Đã lưu 3 khối đúng: 2 module và 1 phần phụ'));
    assert.equal(await page.locator('#accept-boxes').textContent(), 'Đã lưu kết quả');
    assert.equal(await page.locator('#accept-boxes').getAttribute('aria-busy'), 'false');
    assert.equal(await page.locator('#accept-boxes').evaluate(e => getComputedStyle(e).cursor), 'default');
    await page.evaluate(() => receive({...testState, busy: true, correction: {manual: true}}));
    for (const id of ['wrong', 'accept-boxes', 'cancel-boxes']) assert(await page.locator(`#${id}`).isDisabled());
    await page.evaluate(() => receive({...testState, focused: {code: 'SCAN-test', manual_boxes: true, modules: [{id: 'M1'}], trim_parts: [],
      geometry_pipeline: {mode: 'plan_only', vertical: {columns: [{id: 'old', box: [0, 0, 1, 1]}]}}, learning: {mode: 'plan_exact'}}}));
    const text = await page.locator('#explanation').textContent();
    assert(text.includes('1 module') && text.includes('1600'));
    assert(!text.includes('1 khoang'));
    assert(await page.evaluate(() => document.body.scrollWidth <= innerWidth + 1));
    await page.screenshot({path: path.resolve(__dirname, '../outputs/manual-boxes-ui-preview.png'), fullPage: true});
    assert.deepEqual(errors, []);
    console.log('Manual boxes UI passed: direct selection, immediate pending feedback, duplicate guard, correlated save/error acknowledgement and retry.');
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });

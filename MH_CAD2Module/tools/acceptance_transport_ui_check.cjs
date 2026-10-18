const assert = require('assert');
const path = require('path');
const {pathToFileURL} = require('url');
const {chromium} = require('playwright');
(async () => {
  const browser = await chromium.launch({channel: 'msedge', headless: true});
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  try {
    await page.clock.install();
    await page.goto(pathToFileURL(path.resolve(__dirname, '../ui/manager.html')).href);
    const reset = async () => page.evaluate(() => {
      window.recorded = [];
      window.sketchup = {request: text => recorded.push(JSON.parse(text))};
      window.testState = {settings: {sources: []}, busy: false, products: [], errors: [], current_modules: [],
        correction: {manual: true, id: 'session-A', code: 'SCAN-test'}};
      receive(testState);
    });
    await reset();
    await page.locator('#accept-boxes').click();
    const first = await page.evaluate(() => recorded[0]);
    assert.equal(first.session_id, 'session-A');
    await page.clock.fastForward(2000);
    assert.equal(await page.evaluate(() => recorded.at(-1).action), 'manual_acceptance_status');
    await page.evaluate(id => receiveManualAcceptance({status: 'unknown', request_id: id}), first.request_id);
    assert(await page.locator('#accept-boxes').isDisabled());
    await page.clock.fastForward(6000);
    assert((await page.locator('#correction-status').textContent()).includes('8 giây'));
    assert.equal(await page.locator('#accept-boxes').getAttribute('aria-busy'), 'false');
    assert.equal(await page.evaluate(() => recorded.filter(p => p.action === 'accept_manual_boxes').length), 1);
    await page.evaluate(id => receiveManualAcceptance({status: 'unknown', request_id: id}), first.request_id);
    assert(!(await page.locator('#accept-boxes').isDisabled()));
    assert((await page.locator('#correction-status').textContent()).includes('chưa ghi nhận'));

    // A lost completion publication is recovered by read-only status polling.
    await reset();
    await page.locator('#accept-boxes').click();
    const second = await page.evaluate(() => recorded[0]);
    await page.clock.fastForward(2000);
    await page.evaluate(id => receiveManualAcceptance({status: 'saved', request_id: id, modules: 1, auxiliary: 2}), second.request_id);
    assert.equal(await page.locator('#accept-boxes').textContent(), 'Đã lưu kết quả');
    const delivered = await page.evaluate(() => recorded.length);
    await page.clock.fastForward(20 * 60 * 1000);
    assert.equal(await page.evaluate(() => recorded.length), delivered, 'Completion must stop polling');

    // Processing acknowledgement cannot unlock a second save; stale replies cannot complete it.
    await reset();
    await page.locator('#accept-boxes').click();
    const third = await page.evaluate(() => recorded[0]);
    await page.evaluate(id => receiveManualAcceptance({status: 'processing', request_id: id}), third.request_id);
    await page.evaluate(() => receiveManualAcceptance({status: 'saved', request_id: 'stale-request', modules: 9, auxiliary: 0}));
    assert.equal(await page.locator('#accept-boxes').textContent(), 'Đang lưu…');
    await page.clock.fastForward(8000);
    assert.equal(await page.evaluate(() => recorded.filter(p => p.action === 'accept_manual_boxes').length), 1);
    await page.evaluate(id => receiveManualAcceptance({status: 'saved', request_id: id, modules: 2, auxiliary: 0}), third.request_id);
    assert.equal(await page.locator('#accept-boxes').textContent(), 'Đã lưu kết quả');

    // A missing native bridge must report an error immediately, never spin forever.
    await reset();
    await page.evaluate(() => { window.sketchup = undefined; });
    await page.locator('#accept-boxes').click();
    assert((await page.locator('#correction-status').textContent()).includes('Không kết nối được'));
    assert(!(await page.locator('#accept-boxes').isDisabled()));
    await page.clock.fastForward(20 * 60 * 1000);
    assert.equal(await page.evaluate(() => recorded.length), 0);
    assert.deepEqual(errors, []);
    console.log('Acceptance transport passed: missing bridge, lost request/reply, 8s deadline, read-only recovery, stale/processing replies and no duplicate save over 20 simulated minutes.');
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });

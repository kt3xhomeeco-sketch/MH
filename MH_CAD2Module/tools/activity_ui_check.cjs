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
      const activities = ['A', 'B'].map(key => ({key, code: `SCAN-${key}`, label: 'Vừa quét SP không có mã',
        available: true, product_id: `assembly-${key}`, event_count: 2, time: '2026-10-19T00:00:00Z'}));
      window.baseState = {settings: {sources: []}, busy: false, products: [], errors: [], current_modules: [], activities};
      window.details = activities.map(row => ({...row, analysis: {code: row.code, automatic_scan: true, bounds: [800, 600, 1600],
        modules: [], build_stages: {elevation: false}, source_path: 'E:/CAD/source.dwg'}, events: [
        {id: row.key+'scan', kind: 'scan', analysis: {explanation: ['Đo cạnh CAD thực'], modules: []}},
        {id: row.key+'build', kind: 'build', analysis: {modules: [{id: 'M1', origin: [0,0,0], size: [800,600,1600]}]}}
      ]}));
      receive(baseState);
    });
    assert.equal(await page.locator('.activity-heading').count(), 2);
    assert.equal(await page.locator('.activity-body').count(), 0);
    assert.equal(await page.locator('#history').count(), 0);
    await page.locator('.activity-heading').first().click();
    assert.deepEqual(await page.evaluate(() => recorded.at(-1)), {action:'activity_open', key:'A'});
    await page.evaluate(() => receive({...baseState, activity_detail: details[0], focused: details[0].analysis}));
    assert.equal(await page.locator('.activity-body #workflow-controls').count(), 1);
    assert.equal(await page.locator('.activity-body .actions button').first().textContent(), 'Select');
    await page.locator('#select-activity').click();
    assert.deepEqual(await page.evaluate(() => recorded.at(-1)), {action:'select_activity', activity_key:'A'});
    await page.locator('#wrong').click();
    assert.deepEqual(await page.evaluate(() => recorded.at(-1)), {action:'wrong', activity_key:'A'});
    await page.locator('.activity-event summary').first().click();
    await page.evaluate(() => receive({...baseState, activity_detail: details[0], focused: details[0].analysis,
      correction: {id:'session-A', product_id:'assembly-A', code:'SCAN-A', manual:true}}));
    assert(await page.locator('.activity-event').first().getAttribute('open') !== null);
    assert(await page.locator('.activity-heading').nth(1).isDisabled());
    await page.locator('#accept-boxes').click();
    const request = await page.evaluate(() => recorded.at(-1));
    assert.equal(request.activity_key, 'A'); assert.equal(request.session_id, 'session-A');
    assert.equal(request.action, 'accept_manual_boxes');
    assert(await page.locator('.activity-heading').first().isDisabled());
    await page.evaluate(id => receiveManualAcceptance({status:'saved', request_id:id, activity_key:'A', modules:1, auxiliary:0}), request.request_id);
    await page.evaluate(() => receive({...baseState, activity_detail: details[1], focused: details[1].analysis,
      manual_acceptance:{status:'saved',request_id:'old-A',activity_key:'A',modules:1,auxiliary:0}}));
    assert.equal(await page.locator('#correction-status').isVisible(), false);
    const removed = await page.evaluate(() => ({...details[1], available:false, product_id:null}));
    await page.evaluate(detail => receive({...baseState, activities:[baseState.activities[0],detail], activity_detail:detail}), removed);
    assert(await page.locator('#select-activity').isDisabled()); assert(await page.locator('#wrong').isDisabled());
    assert((await page.locator('.activity-body > .hint').textContent()).includes('Không còn bộ khối'));
    await page.evaluate(() => {
      const failed = {...details[1], available:false, product_id:null, analysis:{status:'needs_review',signature:'a'.repeat(64)}};
      receive({...baseState, activities:[failed], activity_detail:failed});
    });
    assert(await page.locator('#select-activity').isDisabled());
    assert(!(await page.locator('#begin').isDisabled()));
    assert((await page.locator('#begin').textContent()).includes('Khôi phục'));
    await page.evaluate(() => receive({...baseState, activity_detail: details[0], focused:details[0].analysis}));
    await page.screenshot({path:path.resolve(__dirname,'../outputs/activity-preview.png'),fullPage:true});
    await page.setViewportSize({width:760,height:950});
    assert(await page.evaluate(() => document.body.scrollWidth<=innerWidth+1));
    assert.deepEqual(errors, []);
    console.log('Activity UI passed: independent unnamed rows, expansion, scoped Select/correction/acceptance, preserved event expansion, removed outputs and no cross-row saved reply.');
  } finally { await browser.close(); }
})().catch(e => {console.error(e);process.exitCode=1;});

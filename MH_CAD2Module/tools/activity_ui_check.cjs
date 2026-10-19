const assert = require('assert');
const path = require('path');
const {pathToFileURL} = require('url');
const {chromium} = require('playwright');
(async () => {
  const browser = await chromium.launch({channel: 'msedge', headless: true});
  const page = await browser.newPage({viewport: {width: 1120, height: 950}});
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  const row = key => page.locator(`.activity-row[data-activity-key="${key}"]`);
  const action = (key, name) => row(key).locator(`[data-row-action="${name}"]`);
  try {
    await page.clock.install();
    await page.goto(pathToFileURL(path.resolve(__dirname, '../ui/manager.html')).href);
    await page.evaluate(() => {
      window.recorded = []; window.sketchup = {request: raw => recorded.push(JSON.parse(raw))};
      const activities = ['A', 'B'].map(key => ({key, code: key === 'A' ? 'SCAN-A' : 'SP42',
        label: key === 'A' ? 'Vừa quét SP không có mã' : 'Sản phẩm SP42',
        available: true, product_id: `assembly-${key}`, event_count: 2, time: '2026-10-19T00:00:00Z'}));
      window.baseState = {settings: {sources: []}, busy: false, products: [], errors: [], current_modules: [], activities};
      window.details = activities.map(row => ({...row, analysis: {code: row.code, automatic_scan: row.key === 'A', bounds: [800, 600, 1600],
        modules: [], build_stages: {elevation: false}, source_path: 'E:/CAD/source.dwg'}, events: [
        {id: row.key+'scan', kind: 'scan', analysis: {explanation: ['Đo cạnh CAD thực'], modules: []}},
        {id: row.key+'build', kind: 'build', analysis: {modules: [{id: 'M1', origin: [0,0,0], size: [800,600,1600]}]}}
      ]}));
      receive(baseState);
    });
    assert.equal(await page.locator('.activity-body').count(), 0);
    for (const key of ['A','B']) {
      assert.equal(await row(key).locator('.activity-header [data-row-action]').count(), 4);
      for (const name of ['select_activity','wrong','accept_manual_boxes','cancel_manual_boxes']) assert(await action(key,name).isVisible());
      assert(await action(key,'accept_manual_boxes').isDisabled());
    }
    await action('B','select_activity').click();
    assert.deepEqual(await page.evaluate(() => recorded.at(-1)), {action:'select_activity', activity_key:'B'});
    await page.evaluate(() => receive({...baseState, activity_detail:details[1], focused:details[1].analysis}));
    assert.equal(await page.locator('.activity-body').count(), 0, 'Selecting must not expand history');
    await action('A','wrong').click();
    assert.deepEqual(await page.evaluate(() => recorded.at(-1)), {action:'wrong', activity_key:'A'});
    await page.evaluate(() => receive({...baseState, activity_detail:details[0], focused:details[0].analysis,
      correction:{id:'session-A',product_id:'assembly-A',code:'SCAN-A',manual:true}}));
    assert.equal(await page.locator('.activity-body').count(), 0);
    assert(await row('A').locator('.activity-feedback').isVisible());
    assert(await action('B','select_activity').isDisabled());
    await action('A','accept_manual_boxes').click();
    const request = await page.evaluate(() => recorded.at(-1));
    assert.equal(request.activity_key,'A');assert.equal(request.session_id,'session-A');
    assert.equal(request.action,'accept_manual_boxes');
    assert(await action('A','accept_manual_boxes').isDisabled());
    await page.clock.fastForward(9000);
    assert((await row('A').locator('.activity-feedback').textContent()).includes('8 giây'));
    assert.equal(await page.evaluate(() => recorded.filter(r=>r.action==='accept_manual_boxes').length),1);
    await page.evaluate(id => receiveManualAcceptance({status:'saved',request_id:id,activity_key:'A',modules:1,auxiliary:0}),request.request_id);
    await page.evaluate(() => receive({...baseState,activity_detail:details[1],focused:details[1].analysis,
      manual_acceptance:{status:'saved',request_id:'saved-A',activity_key:'A',modules:1,auxiliary:0}}));
    assert(await row('A').locator('.activity-feedback').isVisible());
    assert(!(await row('B').locator('.activity-feedback').isVisible()));
    await row('B').locator('.activity-heading').click();
    assert.deepEqual(await page.evaluate(() => recorded.at(-1)),{action:'activity_open',key:'B'});
    await page.evaluate(() => receive({...baseState,activity_detail:details[1],focused:details[1].analysis}));
    assert.equal(await page.locator('.activity-body #workflow-controls').count(),1);
    assert(!(await page.locator('#manual-actions').isVisible()),'No duplicate primary toolbar in expanded body');
    await page.locator('.activity-event summary').first().click();
    await page.evaluate(() => receive({...baseState,activity_detail:details[1],focused:details[1].analysis}));
    assert(await page.locator('.activity-event').first().getAttribute('open')!==null);
    await row('B').locator('.activity-heading').click();
    await page.evaluate(() => receive({...baseState,correction:{id:'session-A2',product_id:'assembly-A',manual:true}}));
    await action('A','cancel_manual_boxes').click();
    assert.deepEqual(await page.evaluate(() => recorded.at(-1)),{action:'cancel_manual_boxes',activity_key:'A'});
    await page.evaluate(() => {
      const failed={...details[1],available:false,product_id:null,analysis:{status:'needs_review',signature:'a'.repeat(64)}};
      window.failed=failed;receive({...baseState,activities:[baseState.activities[0],failed]});
    });
    assert(await action('B','select_activity').isDisabled());assert(await action('B','wrong').isDisabled());
    await row('B').locator('.activity-heading').click();
    await page.evaluate(() => receive({...baseState,activities:[baseState.activities[0],failed],activity_detail:failed}));
    assert(!(await page.locator('#begin').isDisabled()));
    await page.evaluate(() => receive(baseState));
    await row('A').locator('.activity-heading').click();
    await page.evaluate(() => receive({...baseState,activity_detail:details[0],focused:details[0].analysis}));
    await page.screenshot({path:path.resolve(__dirname,'../outputs/activity-inline-preview.png'),fullPage:true});
    const titleBox=await row('A').locator('.activity-heading').boundingBox();
    const buttonBox=await action('A','select_activity').boundingBox();
    assert(Math.abs(titleBox.y-buttonBox.y)<15,'Buttons must share the product header line');
    await page.setViewportSize({width:760,height:950});
    assert(await page.evaluate(() => document.body.scrollWidth<=innerWidth+1));
    assert.deepEqual(errors,[]);
    console.log('Inline activity controls passed: named/unnamed collapsed actions, explicit row scope, no action-driven expansion, manual selection/session routing, timeout recovery, per-row saved feedback and cancel.');
  } finally { await browser.close(); }
})().catch(e => {console.error(e);process.exitCode=1;});

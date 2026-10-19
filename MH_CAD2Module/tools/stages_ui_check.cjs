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
      window.testState = {settings: {sources: ['E:/source.dwg']}, busy: false, products: [], errors: [], current_modules: []};
      window.receive(testState);
    });
    assert(await page.locator('#build-plan').isChecked());
    assert(!(await page.locator('#build-elevation').isChecked()));
    await page.locator('#build-elevation').check();
    assert.deepEqual(await page.evaluate(() => recorded.at(-1)), {action: 'save_settings', settings: {build_plan: true, build_elevation: true, build_auxiliary: true, ai_enabled: false}});
    await page.locator('#build-plan').uncheck();
    assert(!(await page.locator('#build-elevation').isChecked()));
    assert.deepEqual(await page.evaluate(() => recorded.at(-1).settings), {build_plan: false, build_elevation: false, build_auxiliary: true, ai_enabled: false});
    await page.locator('#build-elevation').check();
    assert(await page.locator('#build-plan').isChecked());
    await page.locator('#build-elevation').uncheck();
    await page.locator('#save').click();
    assert.deepEqual(await page.evaluate(() => recorded.at(-1).settings), {build_plan: true, build_elevation: false, build_auxiliary: true, ai_enabled: false, sources: ['E:/source.dwg']});
    assert(await page.locator('#build-auxiliary').isChecked());
    await page.locator('#build-auxiliary').uncheck();
    assert.deepEqual(await page.evaluate(() => recorded.at(-1).settings), {build_plan: true, build_elevation: false, build_auxiliary: false, ai_enabled: false});
    await page.evaluate(() => receive({...testState, settings: {...testState.settings, build_auxiliary: false, ai_enabled: false}}));
    assert(!(await page.locator('#build-auxiliary').isChecked()));
    await page.locator('#save').click();
    assert.strictEqual(await page.evaluate(() => recorded.at(-1).settings.build_auxiliary), false);
    await page.evaluate(() => receive({...testState, busy: true}));
    assert(await page.locator('#build-auxiliary').isDisabled());
    assert(await page.locator('#build-plan').isDisabled());
    assert(await page.locator('#build-elevation').isDisabled());
    await page.evaluate(() => receive({...testState, settings: {...testState.settings, build_plan: true, build_elevation: false},
      focused: {code: 'SP99', source_hash: 'plan', modules: [], outlines: [], explanation: [],
        learning: {mode: 'staged'}, geometry_pipeline: {mode: 'plan_only', vertical: {columns: []}}}}));
    const text = await page.locator('#explanation').textContent();
    assert(text.includes('1600') && text.includes('Mặt đứng đang tắt'));
    assert(!text.includes('Bước 2'));
    assert(await page.evaluate(() => document.body.scrollWidth <= innerWidth + 1));
    await page.screenshot({path: path.resolve(__dirname, '../outputs/stages-settings-preview.png'), fullPage: true});
    assert.deepEqual(errors, []);
    console.log('Stages UI passed: defaults, auto-save, dependency, busy state and plan-only explanation.');
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });

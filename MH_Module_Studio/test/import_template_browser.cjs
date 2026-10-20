const {chromium}=require(process.env.MH_PLAYWRIGHT||'playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
(async()=>{
 const root=path.resolve(__dirname,'..'),folder=path.join(root,'outputs/import-072');fs.mkdirSync(folder,{recursive:true});
 const state=JSON.parse(fs.readFileSync(path.join(root,'outputs/list-071/preset.json'),'utf8'));
 const browser=await chromium.launch({headless:true,executablePath:process.env.MH_BROWSER||undefined});
 try{
  const page=await browser.newPage({viewport:{width:1300,height:900}}),errors=[];page.on('pageerror',error=>errors.push(error.message));
  await page.addInitScript(()=>{window.sent=[];window.sketchup={request:raw=>window.sent.push(JSON.parse(raw))};});
  await page.goto('file:///'+path.join(root,'ui/parametric.html').replaceAll('\\','/'));
  await page.evaluate(s=>window.receive(s),state);
  assert(!await page.locator('#import-links').evaluate(node=>node.open));
  await page.locator('#configure-import').click();
  assert(await page.locator('#import-links').evaluate(node=>node.open));
  await page.locator('#import-five').click();
  assert(await page.locator('#import-enabled').isChecked());
  assert.equal(await page.locator('[data-import-slot]:checked').count(),5);
  await page.locator('#import-role').selectOption('door');assert(await page.locator('#import-door-gap').isVisible());
  await page.locator('#import-mode').selectOption('outside');await page.locator('[data-import-gap="0:0"]').fill('2.5');
  await page.locator('#import-apply').click();
  const packet=await page.evaluate(()=>sent.at(-1));
  assert.equal(packet.action,'save_variables');assert.equal(packet.import_template.role,'door');assert.equal(packet.import_template.mode,'outside');assert.equal(packet.import_template.door_gap,1);
  assert.equal(packet.import_template.faces.find(face=>face.axis===0&&face.side===0).gap,2.5);
  const ack=structuredClone(state);ack.rule.import_template=packet.import_template;ack.parametric_revision++;
  await page.evaluate(s=>window.receive(s),ack);
  assert.equal(await page.locator('#import-role').inputValue(),'door');assert(await page.locator('#import-apply').isDisabled());
  await page.locator('#save-skp').click();assert.equal((await page.evaluate(()=>sent.at(-1))).import_template.role,'door');
  await page.evaluate(s=>window.receive(s),ack);
  await page.locator('[data-import-slot="0:1"]').uncheck();await page.locator('[data-import-slot="2:0"]').uncheck();await page.locator('[data-import-slot="2:1"]').uncheck();
  assert.equal(await page.locator('[data-import-slot]:checked').count(),2);
  await page.locator('#import-apply').click();assert.equal((await page.evaluate(()=>sent.at(-1))).import_template.faces.filter(face=>face.enabled).length,2);
  await page.locator('#import-links').screenshot({path:path.join(folder,'configuration.png')});
  for(const width of [1200,1000,850]){await page.setViewportSize({width,height:850});assert(await page.locator('header').evaluate(node=>node.scrollWidth<=node.clientWidth+1),`Header overflows at ${width}`);}
  const assembly=structuredClone(state);assembly.parametric_sheet.assembly=true;
  await page.evaluate(s=>window.receive(s),assembly);assert(await page.locator('#configure-import').isDisabled());
  assert.deepEqual(errors,[]);fs.writeFileSync(path.join(folder,'browser.json'),JSON.stringify({ok:true,errors}));
  console.log('Parametric: five-face preset, explicit door property, per-face gaps, partial slots and Save SKP configuration round trip passed.');
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});

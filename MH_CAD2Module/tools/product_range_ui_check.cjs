const fs=require('fs'),path=require('path'),assert=require('assert');
const {pathToFileURL}=require('url'),{chromium}=require('playwright');
(async()=>{
 const root=path.resolve(__dirname,'..'),browser=await chromium.launch({channel:'msedge',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:420,height:300}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto(pathToFileURL(path.join(root,'ui/entry.html')).href);
  await page.evaluate(()=>{window.recorded=[];window.sketchup={request:t=>recorded.push(JSON.parse(t))};window.testState={busy:false,entry_mode:'dwg',last_products:'SP08',last_product_end:'SP11'};receive(testState)});
  assert.equal(await page.locator('#product-input').inputValue(),'SP08');
  assert.equal(await page.locator('#product-end').inputValue(),'SP11');
  await page.getByRole('button',{name:'Dựng khối',exact:true}).click();
  assert.deepEqual(await page.evaluate(()=>recorded.at(-1)),{action:'build',products:'SP08',product_end:'SP11'});
  await page.locator('#product-input').fill('');await page.locator('#product-end').fill('SP11');
  await page.evaluate(()=>receive(testState)); // Routine refresh must not overwrite editing.
  assert.equal(await page.locator('#product-input').inputValue(),'');
  await page.getByRole('button',{name:'Dựng khối',exact:true}).click();
  assert.deepEqual(await page.evaluate(()=>recorded.at(-1)),{action:'build',products:'',product_end:'SP11'});
  await page.locator('#product-input').fill('SP08');await page.locator('#product-end').fill('');
  await page.getByRole('button',{name:'Dựng khối',exact:true}).click();
  assert.deepEqual(await page.evaluate(()=>recorded.at(-1)),{action:'build',products:'SP08'});
  await page.evaluate(()=>receive({...testState,last_products:'SP01\nSP03',last_product_end:''}));
  assert.equal(await page.locator('#product-input').inputValue(),'SP01\nSP03');
  assert.equal(await page.locator('#product-end').inputValue(),'');
  await page.evaluate(()=>receive({...testState,busy:true}));assert(await page.locator('#build').isDisabled());
  assert(await page.evaluate(()=>document.body.scrollWidth<=innerWidth+1));
  await page.screenshot({path:path.join(root,'outputs/product-range-entry.png'),fullPage:true});
  await page.goto(pathToFileURL(path.join(root,'ui/manager.html')).href);
  const p=JSON.parse(fs.readFileSync(path.join(root,'outputs/sp11-full-plans.json'),'utf8'));
  await page.evaluate(p=>{window.sketchup={request:()=>{}};receive({plan_engine:'oy-stock-sweep-v1',settings:{sources:[]},products:[p],focused:p,current_modules:[],busy:false,errors:[]})},p);
  const text=await page.locator('#view-diagnostics').textContent();assert.equal((text.match(/Đang dựng/g)||[]).length,4);
  assert(text.includes('Mặt bằng chữ L') && /2[.,]?420/.test(text));
  assert.deepEqual(errors,[]);console.log('Range/L UI passed: inclusive endpoint transport, either single field, retained edits/Excel, busy gating and4 SP11 plans.');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});

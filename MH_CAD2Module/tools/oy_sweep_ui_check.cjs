const fs=require('fs'),path=require('path'),assert=require('assert');
const {pathToFileURL}=require('url'),{chromium}=require('playwright');
(async()=>{
 const root=path.resolve(__dirname,'..');
 const product=JSON.parse(fs.readFileSync(path.join(root,'outputs/oy-sweep-latest82.json'),'utf8'));
 const browser=await chromium.launch({channel:'msedge',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1120,height:950}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto(pathToFileURL(path.join(root,'ui/manager.html')).href);
  await page.evaluate(p=>{
   window.recorded=[];window.sketchup={request:raw=>recorded.push(JSON.parse(raw))};
   window.state={plan_engine:'oy-stock-sweep-v1',settings:{sources:[],ai_enabled:true},products:[p],focused:p,
     current_modules:p.modules,errors:[],history:[],busy:false};receive(state);
  },product);
  assert(await page.locator('#ai-enabled').isDisabled());
  assert(!(await page.locator('#ai-enabled').isChecked()));
  assert(await page.locator('[data-action="ai_status"]').isDisabled());
  assert((await page.locator('#ai-status').textContent()).includes('không gọi AI'));
  const explanation=await page.locator('#explanation').textContent();
  for(const text of ['BỘ QUÉT OY','18 + 18','chia hai module','tấm ngoài/nẹp','Quét độ dày','Tổng đọc mặt bằng'])assert(explanation.includes(text),text);
  assert.equal(await page.locator('#modules tr').count(),4);
  assert((await page.locator('#plan-rules-status').textContent()).includes('không chạy'));
  await page.locator('#build-auxiliary').uncheck();
  assert.equal(await page.evaluate(()=>recorded.at(-1).settings.ai_enabled),true,'Do not erase saved legacy AI preference');
  await page.evaluate(()=>receiveProgress({message:'Đang quét OY · Tổng 1s'}));
  assert((await page.locator('#status').textContent()).includes('Tổng 1s'));
  assert(await page.evaluate(()=>document.body.scrollWidth<=innerWidth+1));
  await page.screenshot({path:path.join(root,'outputs/oy-sweep-manager.png'),fullPage:true});
  assert.deepEqual(errors,[]);
  console.log('OY UI passed: geometry-only engine, inactive archived AI, preserved preference, seams/depth/times and module list.');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});

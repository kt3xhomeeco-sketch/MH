const fs=require('fs'),path=require('path'),assert=require('assert');
const {pathToFileURL}=require('url'),{chromium}=require('playwright');
(async()=>{
 const root=path.resolve(__dirname,'..');
 const p=JSON.parse(fs.readFileSync(path.join(root,'outputs/scan-l-fixed.json'),'utf8'));
 const receipt=JSON.parse(fs.readFileSync(path.join(root,'outputs/resident-native-result.json'),'utf8'));
 p.source_cache=receipt.jobs[2].cache;p.worker_timing=receipt.jobs[2].worker;p.processing_from_cache=true;
 p.processing_times.stock_scan=9999;p.current_replay_seconds=.005;
 const browser=await chromium.launch({channel:'msedge',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1120,height:950}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(pathToFileURL(path.join(root,'ui/manager.html')).href);
  await page.evaluate(p=>{window.sketchup={request:()=>{}};receive({settings:{sources:[]},plan_engine:'oy-stock-sweep-v1',products:[p],focused:p,current_modules:p.modules,busy:false,errors:[]})},p);
  const text=await page.locator('#explanation').textContent();
  assert(text.includes('BỘ QUÉT ĐA HƯỚNG') && text.includes('tra độ dày'));
  assert(text.includes('Cache kết quả') && text.includes('Worker thường trực'));
  assert(text.includes('không chạy lại') && !text.includes('9999'));
  assert(text.includes('lượt này'));
  assert(text.includes('7 module · 4 khối phụ') && text.includes('thanh chung'));
  assert.equal(await page.locator('#modules tr').count(),7);
  assert.deepEqual(errors,[]);
  await page.screenshot({path:path.join(root,'outputs/scanned-l-manager.png'),fullPage:true});
  console.log('Scanned L UI passed: seven modules, auxiliary/rail explanation, geometry evidence and current timings.');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});

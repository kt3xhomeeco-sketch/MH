const fs=require('fs'),path=require('path'),assert=require('assert');
const {pathToFileURL}=require('url'),{chromium}=require('playwright');
(async()=>{
 const root=path.resolve(__dirname,'..'),p=JSON.parse(fs.readFileSync(path.join(root,'outputs/detail-plans-sp04.json'),'utf8'));
 const browser=await chromium.launch({channel:'msedge',headless:true});
 try{
  const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(pathToFileURL(path.join(root,'ui/manager.html')).href);
  await page.evaluate(p=>{window.sketchup={request:()=>{}};window.state={plan_engine:'oy-stock-sweep-v1',settings:{sources:[]},products:[p],focused:p,current_modules:[],errors:[],busy:false};receive(state)},p);
  const text=await page.locator('#view-diagnostics').textContent();
  assert.equal((text.match(/Đang dựng/g)||[]).length,3);
  assert.equal((text.match(/Mặt cắt trích \/ chi tiết — không tự dựng/g)||[]).length,4);
  assert(text.includes('15%') && text.includes('1000 mm'));
  const cards=page.locator('#view-diagnostics details');
  for(let i=0;i<await cards.count();i++){
   const card=cards.nth(i);
   if((await card.textContent()).includes('Mặt cắt trích / chi tiết')) assert.equal(await card.locator('button').count(),0);
  }
  assert.deepEqual(errors,[]);console.log('SP04 detail UI passed:3 selected plans,4 excluded details, measured reasons and no detail confirmation.');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});

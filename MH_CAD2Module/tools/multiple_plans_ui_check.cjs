const fs=require('fs'),path=require('path'),assert=require('assert');
const {pathToFileURL}=require('url'),{chromium}=require('playwright');
(async()=>{
 const root=path.resolve(__dirname,'..'),product=JSON.parse(fs.readFileSync(path.join(root,'outputs/multiple-plans-sp01.json'),'utf8'));
 const browser=await chromium.launch({channel:'msedge',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1120,height:950}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto(pathToFileURL(path.join(root,'ui/manager.html')).href);
  await page.evaluate(p=>{
   window.sketchup={request:()=>{}};
   window.state={plan_engine:'oy-stock-sweep-v1',settings:{sources:[]},products:[p],focused:p,current_modules:[],errors:[],busy:false};receive(state);
  },product);
  const diagnostic=await page.locator('#view-diagnostics').textContent();
  assert(diagnostic.includes('2 mặt bằng') && diagnostic.includes('1000 mm') && diagnostic.includes('cao tạm 1600'));
  assert.equal((diagnostic.match(/Đang dựng/g)||[]).length,2);
  assert(diagnostic.includes('2255') || diagnostic.includes('2.255'));
  const child=product.plan_results[0];
  await page.evaluate(p=>receive({...state,focused:p,current_modules:p.modules}),child);
  assert.equal(await page.getByRole('button',{name:'Dùng mặt bằng này',exact:true}).count(),0,'Unresolved partition should use Sai, not a repeated source confirmation');
  assert((await page.locator('#explanation').textContent()).includes('KHỐI TẠM'));
  assert(await page.evaluate(()=>document.body.scrollWidth<=innerWidth+1));
  await page.screenshot({path:path.join(root,'outputs/multiple-plans-manager.png'),fullPage:true});
  assert.deepEqual(errors,[]);
  console.log('Multiple plans UI passed: all selected cuts,1000 mm inspection row, mismatch warnings and editable orange preview.');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});

const fs=require('fs'),path=require('path'),assert=require('assert');
const {pathToFileURL}=require('url'),{chromium}=require('playwright');
(async()=>{
 const root=path.resolve(__dirname,'..');
 const product=JSON.parse(fs.readFileSync(path.join(root,'outputs/sp41-arc-analysis.json'),'utf8'));
 const browser=await chromium.launch({channel:'msedge',headless:true});
 try {
  const page=await browser.newPage({viewport:{width:1120,height:900}});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(pathToFileURL(path.join(root,'ui/manager.html')).href);
  await page.evaluate(p=>{
   const proto=CanvasRenderingContext2D.prototype,original=proto.arc;
   window.arcCalls=[];proto.arc=function(...args){arcCalls.push(args);return original.apply(this,args)};
   window.receive({settings:{sources:[]},products:[p],focused:p,current_modules:p.modules,errors:[],history:[],busy:false});
  },product);
  assert((await page.locator('#explanation').textContent()).includes('ArcCurve'));
  assert((await page.evaluate(()=>arcCalls.length))>0);
  assert.equal(await page.locator('#modules tr').count(),3);
  assert(await page.evaluate(()=>document.body.scrollWidth<=innerWidth+1));
  await page.screenshot({path:path.join(root,'outputs/sp41-arc-manager.png'),fullPage:true});
  await page.evaluate(p=>{
   p.plan_evidence={stock_counts:{3:1,6:1,9:1,12:1,15:1,18:2,25:1,36:1},arcs:[{},{}]};
   window.receive({settings:{sources:[]},products:[p],focused:p,current_modules:p.modules,errors:[],history:[],busy:false});
  },product);
  const evidence=await page.locator('#explanation').textContent();
  for(const mm of [3,6,9,12,15,18,25,36])assert(evidence.includes(`${mm} mm:`));
  assert(evidence.includes('2 cung tròn'));
  assert(evidence.includes('không tự coi mọi tấm là ranh giới module'));
  assert(evidence.includes('18 + 18'));
  await page.screenshot({path:path.join(root,'outputs/stock-arc-manager.png'),fullPage:true});
  await page.evaluate(p=>{
   p.plan_evidence={stock_counts:{}};
   window.receive({settings:{sources:[]},products:[p],focused:p,current_modules:p.modules,errors:[],history:[],busy:false});
  },product);
  assert((await page.locator('#explanation').textContent()).includes('Chưa có cặp biên đủ bằng chứng'));
  assert.deepEqual(errors,[]);
  console.log('Arc UI passed: analytic curved overlay, explanation, module list and layout.');
 } finally {await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});

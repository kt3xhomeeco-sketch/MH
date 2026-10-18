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
  assert.deepEqual(errors,[]);
  console.log('Arc UI passed: analytic curved overlay, explanation, module list and layout.');
 } finally {await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});

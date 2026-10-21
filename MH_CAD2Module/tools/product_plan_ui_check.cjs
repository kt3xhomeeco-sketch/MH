const fs=require('fs'),path=require('path'),assert=require('assert');
const {pathToFileURL}=require('url'),{chromium}=require('playwright');
(async()=>{
 const root=path.resolve(__dirname,'..');
 const product=JSON.parse(fs.readFileSync(path.join(root,'outputs/product-plan-ambiguous.json'),'utf8'));
 const browser=await chromium.launch({channel:'msedge',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1120,height:950}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto(pathToFileURL(path.join(root,'ui/manager.html')).href);
  await page.evaluate(p=>{
   window.recorded=[];window.sketchup={request:raw=>recorded.push(JSON.parse(raw))};
   window.state={plan_engine:'oy-stock-sweep-v1',settings:{sources:[],import_plan_reference:false},products:[p],focused:p,
     current_modules:[],errors:[],busy:false};receive(state);
  },product);
  assert(!(await page.locator('#import-plan-reference').isChecked()));
  await page.locator('#import-plan-reference').check();
  assert.equal(await page.evaluate(()=>recorded.at(-1).settings.import_plan_reference),true);
  const candidate=product.view_analysis.candidates.find(c=>c.can_confirm);
  const row=page.locator('.view-candidate').filter({hasText:`${candidate.id} ·`}).first();
  await row.getByRole('button',{name:'Xem vùng',exact:true}).click();
  const preview=await page.evaluate(()=>viewer.product);
  assert.deepEqual(preview.outlines,product.view_previews.find(v=>v.id===candidate.id).outlines);
  assert.equal(preview.modules.length,0);
  await row.getByRole('button',{name:'Dùng mặt bằng này',exact:true}).click();
  assert.deepEqual(await page.evaluate(()=>recorded.at(-1)),{action:'confirm_plan_view',code:product.code,source_hash:product.source_hash,source_path:product.source_path,view_id:candidate.id,signature:candidate.signature});
  await page.evaluate(()=>receive({...state,busy:true}));
  for(const b of await page.getByRole('button',{name:'Dùng mặt bằng này',exact:true}).all())assert(await b.isDisabled());
  await page.evaluate(()=>{state.focused.view_analysis.candidates[0].title='<img src=x onerror="window.bad=true">';receive(state)});
  assert(!(await page.evaluate(()=>window.bad)));
  assert.equal(await page.locator('#view-diagnostics img').count(),0);
  assert(await page.evaluate(()=>document.body.scrollWidth<=innerWidth+1));
  await page.screenshot({path:path.join(root,'outputs/product-plan-manager.png'),fullPage:true});
  assert.deepEqual(errors,[]);
  console.log('Product plan UI passed: isolated previews, source/signature-bound confirmation, remembered import toggle, busy gating and safe text.');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});

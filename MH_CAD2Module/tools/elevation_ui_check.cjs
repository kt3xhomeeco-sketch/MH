const fs=require('fs'),path=require('path'),assert=require('assert');
const {pathToFileURL}=require('url'),{chromium}=require('playwright');
(async()=>{
 const root=path.resolve(__dirname,'..');
 const browser=await chromium.launch({channel:'msedge',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1120,height:950}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto(pathToFileURL(path.join(root,'ui/manager.html')).href);
  for(const mode of ['measured','provisional']){
   const p=JSON.parse(fs.readFileSync(path.join(root,`outputs/elevation-${mode}.json`),'utf8'));
   await page.evaluate(p=>{
    window.sent=[];window.sketchup={request:s=>sent.push(JSON.parse(s))};
    receive({settings:{sources:[],build_plan:true,build_elevation:true},plan_engine:'oy-stock-sweep-v1',
      products:[p],focused:p,current_modules:p.modules,busy:false,errors:[]});
   },p);
   assert(await page.locator('#build-elevation').isChecked());
   const text=await page.locator('#explanation').textContent();
   assert(text.includes('Ưu tiên mặt cắt đứng'));
   assert(!text.includes('Mặt đứng đang tắt'));
   if(mode==='measured'){
    assert(text.includes('Đã đo chiều cao') && text.includes('dấu C1') && text.includes('dấu C2'));
    assert.equal(await page.locator('#modules tr').count(),4);
   }else{
    assert(text.includes('Còn phần cao tạm 1600 mm') && text.includes('Cần kiểm tra:'));
    assert((await page.locator('#products').textContent()).includes('Cần kiểm tra mặt đứng'));
   }
   await page.screenshot({path:path.join(root,`outputs/elevation-${mode}-manager.png`),fullPage:true});
  }
  assert.deepEqual(errors,[]);
  console.log('Elevation UI passed: saved stage, linked cuts, measured/pending heights and explicit review status.');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});

const fs=require('fs'),path=require('path'),assert=require('assert');
const {pathToFileURL}=require('url'),{chromium}=require('playwright');
(async()=>{
 const root=path.resolve(__dirname,'..'),browser=await chromium.launch({channel:'msedge',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1120,height:950}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto(pathToFileURL(path.join(root,'ui/manager.html')).href);
  assert((await page.locator('.stages').first().textContent()).includes('Quét chọn: bao cả mặt bằng'));
  for(const mode of ['native','pending']){
   const p=JSON.parse(fs.readFileSync(path.join(root,`outputs/scan-elevation-${mode}-product.json`),'utf8'));
   await page.evaluate(p=>{
    window.sketchup={request:()=>{}};
    receive({settings:{sources:[],build_plan:true,build_elevation:true},plan_engine:'oy-stock-sweep-v1',
      products:[p],focused:p,current_modules:p.modules,busy:false,errors:[]});
   },p);
   const text=await page.locator('#explanation').textContent();
   assert(text.includes('QUÉT KẾT HỢP') && text.includes('5 tiêu đề hình chiếu'));
   assert(text.includes('Khối đặt tại từng mặt bằng nguồn') && text.includes('Nhận ký hiệu:'));
   assert(await page.locator('#build-elevation').isChecked());
   if(mode==='native'){
    assert(text.includes('3 dấu cắt đọc được') && text.includes('Đã đo chiều cao'));
    assert.equal(await page.locator('#modules tr').count(),4);
   }else{
    assert(text.includes('Còn phần cao tạm 1600 mm') && text.includes('Vùng quét cần kiểm tra:'));
    assert.equal(await page.locator('#modules tr').count(),2);
   }
   await page.screenshot({path:path.join(root,`outputs/scan-elevation-${mode}-manager.png`),fullPage:true});
  }
  assert.deepEqual(errors,[]);
  console.log('Combined scan UI passed: selection instructions, readable annotations, measured/provisional stages and source placement.');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});

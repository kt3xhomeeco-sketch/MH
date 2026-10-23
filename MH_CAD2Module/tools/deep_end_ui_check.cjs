const fs=require('fs'),path=require('path'),assert=require('assert');
const {pathToFileURL}=require('url'),{chromium}=require('playwright');
(async()=>{
 const root=path.resolve(__dirname,'..'),browser=await chromium.launch({channel:'msedge',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1120,height:950}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto(pathToFileURL(path.join(root,'ui/manager.html')).href);
  const p=JSON.parse(fs.readFileSync(path.join(root,'outputs/deep-end-native-product.json'),'utf8'));
  await page.evaluate(p=>{window.sketchup={request:()=>{}};receive({settings:{sources:[],build_plan:true,build_elevation:true},plan_engine:'oy-stock-sweep-v1',products:[p],focused:p,current_modules:p.modules,busy:false,errors:[]})},p);
  assert.equal(await page.locator('#modules tr').count(),2);
  const rows=await page.locator('#modules').textContent();
  assert(rows.includes('970') && rows.includes('485') && rows.includes('520'));
  const text=await page.locator('#explanation').textContent();
  assert(text.includes('Tấm ngoài đo được') && text.includes('600'));
  assert(text.includes('giữ chiều sâu riêng đo từ CAD') && text.includes('Còn phần cao tạm 1600 mm'));
  assert(!text.includes('KHỐI TẠM THEO KHUNG BAO'));
  assert.deepEqual(errors,[]);
  await page.screenshot({path:path.join(root,'outputs/deep-end-manager.png'),fullPage:true});
  console.log('Actual deep end plan UI passed: two full-frame modules, measured deeper panels and provisional elevation.');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});

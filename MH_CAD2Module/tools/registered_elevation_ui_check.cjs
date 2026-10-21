const fs=require('fs'),path=require('path'),assert=require('assert');
const {pathToFileURL}=require('url'),{chromium}=require('playwright');
(async()=>{
 const root=path.resolve(__dirname,'..'),browser=await chromium.launch({channel:'msedge',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1120,height:950}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(pathToFileURL(path.join(root,'ui/manager.html')).href);
  const p=JSON.parse(fs.readFileSync(path.join(root,'outputs/registered-native-product.json'),'utf8'));
  await page.evaluate(p=>{window.sketchup={request:()=>{}};receive({settings:{sources:[],build_plan:true,build_elevation:true},plan_engine:'oy-stock-sweep-v1',products:[p],focused:p,current_modules:p.modules,busy:false,errors:[]})},p);
  assert.equal(await page.locator('#modules tr').count(),4);
  const text=await page.locator('#explanation').textContent();
  assert(text.includes('GHÉP HÌNH HỌC') && text.includes('Đã đo chiều cao'));
  const sizes=await page.locator('#modules').textContent();
  assert(sizes.includes('642') && sizes.includes('2.008') && text.includes('Z50') && text.includes('Z692'));
  assert(text.includes('Nẹp nóc') && text.includes('một khối theo xác nhận của người dùng') && text.includes('1.491 × 50 × 30'));
  assert(!text.includes('Còn phần cao tạm 1600 mm'));
  assert.deepEqual(errors,[]);
  await page.screenshot({path:path.join(root,'outputs/registered-elevation-manager.png'),fullPage:true});
  console.log('Registered elevation UI passed: four measured tiers, geometric correspondence and parallel-proven top return trim.');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});

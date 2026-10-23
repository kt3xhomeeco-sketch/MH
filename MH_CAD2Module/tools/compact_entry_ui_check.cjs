const fs=require('fs'),path=require('path'),assert=require('assert');
const {pathToFileURL}=require('url'),{chromium}=require('playwright');
(async()=>{
 const root=path.resolve(__dirname,'..'),browser=await chromium.launch({channel:'msedge',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:420,height:240}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(pathToFileURL(path.join(root,'ui/entry.html')).href);
  await page.evaluate(()=>{window.recorded=[];window.sketchup={request:t=>recorded.push(JSON.parse(t))};window.testState={busy:false,entry_mode:'dwg',entry_target:{product_id:'A'},message:'ERROR SHOULD NOT APPEAR'};receive(testState);receiveProgress({message:'PROGRESS SHOULD NOT APPEAR'})});
  assert.equal(await page.locator('#message,#range-hint').count(),0);
  assert(!(await page.locator('body').textContent()).includes('SHOULD NOT APPEAR'));
  for(const name of ['Select','Sai','Kết quả đúng','Hủy sửa'])assert.equal(await page.getByRole('button',{name,exact:true}).count(),1);
  for(const [value,expected] of [['20','SP20'],['D1','D1'],['SP01\nSP03','SP01\nSP03']]){
   await page.locator('#product-input').fill(value);await page.getByRole('button',{name:'Dựng khối',exact:true}).click();
   assert.deepEqual(await page.evaluate(()=>recorded.at(-1)),{action:'build',products:expected});
  }
  await page.locator('#product-input').fill('20');await page.locator('#product-end').fill('');
  await page.locator('#product-input').press('Enter');
  assert.deepEqual(await page.evaluate(()=>recorded.at(-1)),{action:'build',products:'SP20'});
  await page.locator('#product-end').fill('21');await page.locator('#product-end').press('Enter');
  assert.deepEqual(await page.evaluate(()=>recorded.at(-1)),{action:'build',products:'SP20',product_end:'SP21'});
  let count=await page.evaluate(()=>recorded.filter(r=>r.action==='build').length);
  await page.locator('#product-input').press('Shift+Enter');
  assert.equal(await page.evaluate(()=>recorded.filter(r=>r.action==='build').length),count);
  for(const state of [{busy:true},{correction:{manual:true,id:'S'}},{busy:false}]){
   await page.evaluate(s=>receive({...testState,...s}),state);
   const blocked=state.busy||state.correction;
   await page.locator('#manage').focus();await page.keyboard.press('Enter');
   const next=await page.evaluate(()=>recorded.filter(r=>r.action==='build').length);
   assert.equal(next,count+(blocked?0:1));count=next;
  }
  await page.evaluate(()=>document.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',repeat:true,bubbles:true})));
  await page.evaluate(()=>document.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',isComposing:true,bubbles:true})));
  assert.equal(await page.evaluate(()=>recorded.filter(r=>r.action==='build').length),count);
  await page.getByRole('button',{name:'Select',exact:true}).click();assert.deepEqual(await page.evaluate(()=>recorded.at(-1)),{action:'entry_workflow',operation:'select_activity'});
  await page.getByRole('button',{name:'Sai',exact:true}).click();assert.deepEqual(await page.evaluate(()=>recorded.at(-1)),{action:'entry_workflow',operation:'wrong'});
  await page.evaluate(()=>receive({...testState,correction:{id:'SESSION',manual:true}}));
  assert(await page.getByRole('button',{name:'Sai',exact:true}).isDisabled());
  await page.getByRole('button',{name:'Hủy sửa',exact:true}).click();assert.equal(await page.evaluate(()=>recorded.at(-1).operation),'cancel_manual_boxes');
  await page.getByRole('button',{name:'Kết quả đúng',exact:true}).click();
  const request=await page.evaluate(()=>recorded.at(-1));assert.equal(request.operation,'accept_manual_boxes');assert.equal(request.session_id,'SESSION');assert(request.request_id);
  assert(await page.getByRole('button',{name:'Đang lưu…',exact:true}).isDisabled());
  await page.evaluate(id=>receiveManualAcceptance({request_id:id,status:'saved'}),request.request_id);
  assert.equal(await page.getByRole('button',{name:'Kết quả đúng',exact:true}).count(),1);
  await page.evaluate(()=>receive({...testState,busy:true}));assert(await page.getByRole('button',{name:'Select',exact:true}).isDisabled());
  assert(await page.evaluate(()=>document.body.scrollWidth<=innerWidth+1));
  await page.screenshot({path:path.join(root,'outputs/compact-entry.png'),fullPage:true});
  assert.deepEqual(errors,[]);console.log('Compact entry passed: four scoped actions, no message/hint, numeric SP and generic codes, multi-line preservation and save acknowledgment.');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});

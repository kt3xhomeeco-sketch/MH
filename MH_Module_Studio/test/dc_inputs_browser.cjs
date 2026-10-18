const {chromium}=require(process.env.MH_PLAYWRIGHT||'playwright');
const path=require('path'),assert=require('assert'),fs=require('fs');
(async()=>{
  const browser=await chromium.launch({headless:true,executablePath:process.env.MH_BROWSER||undefined});
  try{
    const page=await browser.newPage({viewport:{width:1400,height:900}}),errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    await page.addInitScript(()=>{window.sent=[];window.sketchup={request:raw=>window.sent.push(JSON.parse(raw))};});
    const root=path.resolve(__dirname,'..'),state=JSON.parse(fs.readFileSync(path.join(root,'outputs/copies-ui-state.json'),'utf8'));
    await page.goto('file:///'+path.join(root,'ui/parametric.html').replaceAll('\\','/'));
    await page.evaluate(s=>window.receive(s),state);
    const count=page.locator('[data-variable-id="input:b6sochanphu"] [data-field="value"]');
    assert(await count.isEditable());assert.equal(await count.getAttribute('step'),'1');
    await count.fill('7');
    const mode=page.locator('[data-variable-id="input:c5_an_vien_nhua"] select[data-field="value"]');
    assert.equal(await mode.locator('option').first().textContent(),'ẩn');
    await mode.selectOption('1');await page.locator('#save-variables').click();
    const packet=await page.evaluate(()=>window.sent.at(-1));
    assert.equal(packet.variables.find(r=>r.binding==='b6sochanphu').value,7);
    assert.equal(packet.variables.find(r=>r.binding==='c5_an_vien_nhua').value,1);
    await page.screenshot({path:path.join(root,'outputs/parametric-copies-select.png')});
    await page.goto('file:///'+path.join(root,'ui/module_options.html').replaceAll('\\','/'));
    const next={root_pid:'private',token:'a',name:'Chân bệ',rows:[{id:'kind',name:'Ẩn / hiện',symbol:'Kind',category:'number',value:0,editable:true,options:[{label:'ẩn',value:0,supported:true},{label:'hiện',value:1,supported:true}]},{id:'locked',name:'Góc chưa hỗ trợ',category:'number',value:0,editable:false,reason:'Góc xoay chưa hỗ trợ',options:[{label:'Thẳng',value:0,supported:true},{label:'Xoay',value:90,supported:true}]}]};
    await page.evaluate(s=>window.receive(s),next);
    const dropdown=page.locator('select[data-variable-id="kind"]');
    await dropdown.selectOption('1');
    assert.deepEqual(await page.evaluate(()=>window.sent.at(-1)),{action:'change',root_pid:'private',token:'a',variable_id:'kind',value:1});
    next.rows[0].value=1;next.token='b';await page.evaluate(s=>window.receive(s),next);
    assert.equal(await dropdown.inputValue(),'1');
    assert(await page.locator('select[data-variable-id="locked"]').isDisabled());
    assert.equal(errors.length,0,errors.join('\n'));
    console.log('Editable plinth Copies, integer field, legacy Vietnamese LIST labels, numeric dispatch, acknowledgement focus and locked dropdowns passed.');
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});

// Developer-only smoke for the compact persistent assembly controls.
const {chromium}=require(process.env.MH_PLAYWRIGHT||'playwright');
const path=require('path'),assert=require('assert'),fs=require('fs');
(async()=>{
  const browser=await chromium.launch({headless:true,executablePath:process.env.MH_BROWSER||undefined});
  try{
    const page=await browser.newPage({viewport:{width:286,height:490}}),errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    await page.addInitScript(()=>{window.sent=[];window.sketchup={assembly_request:raw=>window.sent.push(JSON.parse(raw))};});
    const root=path.resolve(__dirname,'..');
    await page.goto('file:///'+path.join(root,'ui/assembly.html').replaceAll('\\','/'));
    const state={record:{mode:'contact',gap:3,count:2,angle:90,direction:'right',equal:false,ends:true,a:{name:'Module A / Hông trái / Mặt trong'},b:{name:'Module B / Hông trái / Mặt ngoài'}},gap:3,complete:true,picking:null,tool_active:false,links:[]};
    await page.evaluate(s=>window.receiveAssembly(s),state);
    assert((await page.locator('#status').textContent()).includes('M / S'));
    assert(await page.locator('#contact-mode').evaluate(e=>e.classList.contains('selected')));
    await page.locator('#flip').click();assert.deepEqual(await page.evaluate(()=>window.sent.at(-1)),{action:'flip'});
    await page.locator('#right-angle').click();assert.deepEqual(await page.evaluate(()=>window.sent.slice(-2)),[{action:'mode',value:'angle'},{action:'value',value:['angle',90]}]);
    await page.locator('#angle-mode').click();assert.deepEqual(await page.evaluate(()=>window.sent.at(-1)),{action:'mode',value:'angle'});
    await page.locator('#gap').fill('8');await page.locator('#gap').blur();
    assert.deepEqual(await page.evaluate(()=>window.sent.at(-1)),{action:'value',value:['gap',8]});
    const measured=structuredClone(state);measured.record.r1={};
    await page.evaluate(s=>window.receiveAssembly(s),measured);assert(await page.locator('#flip').isDisabled());
    await page.evaluate(s=>window.receiveAssembly(s),state);
    assert(!(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth)));
    assert(await page.locator('#save').isVisible());
    await page.screenshot({path:path.join(root,'outputs/assembly-035/controls.png')});
    await page.locator('#close').click();assert.deepEqual(await page.evaluate(()=>window.sent.at(-1)),{action:'close'});
    assert.equal(errors.length,0,errors.join('\n'));
    fs.writeFileSync(path.join(root,'outputs/assembly-035/browser.json'),JSON.stringify({ok:true,errors},null,2));
    console.log('Compact HUD controls, modes, numeric edit, flip, close and 286px layout passed.');
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});

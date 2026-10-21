// Developer-only Chromium check for custom ATT rows and a cleared model session.
const {chromium}=require(process.env.MH_PLAYWRIGHT||'playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.MH_BROWSER||undefined});
 try{
  const page=await browser.newPage({viewport:{width:1400,height:900}}),errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  await page.addInitScript(()=>{window.sent=[];window.sketchup={request:raw=>sent.push(JSON.parse(raw))};});
  await page.goto('file:///'+path.join(root,'ui/parametric.html').replaceAll('\\','/'));
  const state=JSON.parse(fs.readFileSync(path.join(root,'outputs/session-068/drawer-ui-state.json'),'utf8'));
  await page.evaluate(data=>window.receive(data),state);
  assert.equal(await page.locator('#variables-table tbody tr').count(),state.parametric_sheet.variables.length);
  const derived=state.parametric_sheet.variables.find(row=>row.binding==='x7ry2cn2w4');
  assert(derived&&derived.source_formula);
  const row=page.locator(`[data-variable-id="${derived.id}"]`);
  assert.equal(await row.locator('[data-field=formula]').inputValue(),derived.source_formula);
  assert.equal(await row.locator('[data-field=formula]').evaluate(node=>node.readOnly),true);
  assert.equal(await row.locator('[data-field=value]').evaluate(node=>node.readOnly),true);
  assert(Math.abs(Number(await row.locator('[data-field=value]').inputValue())-derived.computed_value)<0.000001);
  await row.locator('input[type=checkbox]').check();
  await page.locator('#save-variables').click();
  const request=await page.evaluate(()=>sent.at(-1));
  assert.equal(request.action,'save_variables');
  const saved=request.variables.find(item=>item.id===derived.id);
  assert.equal(saved.formula,''); // Original DC text must never become a new own override.
  assert.equal(saved.exported,true);
  await page.evaluate(()=>window.receive({snapshots:[],rule:null,busy:false,parametric_revision:2,message:'Đã chuyển model'}));
  assert.equal(await page.locator('#variables-table tbody tr').count(),0);
  assert.equal(await page.locator('#parts-table tbody tr').count(),0);
  assert.equal(await page.locator('#capture-sketchup').isEnabled(),true);
  assert.deepEqual(errors,[]);
  console.log('Custom ATT values/original readonly formulas, checkbox payload and New-model table reset passed.');
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});

// Developer-only live-catalog regressions; no browser dependency ships.
const {chromium}=require(process.env.MH_PLAYWRIGHT||'playwright');
const path=require('path'),fs=require('fs'),assert=require('assert');
(async()=>{
  const root=path.resolve(__dirname,'..');
  const browser=await chromium.launch({headless:true,executablePath:process.env.MH_BROWSER||undefined});
  try{
    const page=await browser.newPage(),errors=[];
    page.on('pageerror',error=>errors.push(error.message));
    await page.addInitScript(()=>{window.sent=[];window.sketchup={request:raw=>sent.push(JSON.parse(raw))};});
    await page.goto('file:///'+path.join(root,'ui/index.html').replaceAll('\\','/'));
    await page.evaluate(value=>window.receive(value),JSON.parse(fs.readFileSync(path.join(root,'outputs/ui-test-state.json'),'utf8')));
    const catalog={root:'D:/Library',settings:{folder:'',view:'grid',thumbnail_size:150},folders:[{id:'',name:'Library',parent:null}],entries:['A','B'].map(id=>({id:id+'.skp',name:'Cabinet '+id,folder:'',bytes:10,fingerprint:id+'1',thumbnail_key:id+'1'}))};
    await page.locator('#library-tab').click();
    await page.evaluate(value=>window.receiveLibrary(value),catalog);
    await page.waitForTimeout(100);
    assert(await page.evaluate(()=>sent.some(row=>row.action==='library_visibility'&&row.visible)));
    const png='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=';
    await page.evaluate(url=>window.receiveLibraryThumbnails({'A.skp':{key:'A1',url},'B.skp':{key:'B1',url}}),png);
    await page.locator('[data-id="B.skp"]').click();
    await page.locator('#library-search').fill('Cabinet');
    catalog.entries[0]={...catalog.entries[0],id:'Renamed.skp',name:'Cabinet Renamed',fingerprint:'R1',thumbnail_key:'R1'};
    catalog.background=true;
    await page.evaluate(value=>{sent.length=0;window.receiveLibrary(value);},catalog);
    assert.equal(await page.locator('#library-search').inputValue(),'Cabinet');
    assert.equal(await page.locator('#library-selected-name').textContent(),'Cabinet B');
    assert.equal(await page.locator('[data-id="A.skp"]').count(),0);
    assert.equal(await page.locator('[data-id="B.skp"] img').count(),1,'Unchanged image stays cached');
    await page.waitForTimeout(100);
    assert(!(await page.evaluate(()=>sent.filter(row=>row.action==='library_thumbnails').some(row=>row.ids.includes('B.skp')))));
    // A late old response must release its slot and request the newer revision.
    catalog.entries[0].thumbnail_key='R2';catalog.entries[0].fingerprint='R2';
    await page.evaluate(value=>window.receiveLibrary(value),catalog);
    await page.evaluate(()=>window.receiveLibraryThumbnails({'Renamed.skp':{key:'R1',url:null}}));
    await page.waitForTimeout(100);
    assert(await page.evaluate(()=>sent.filter(row=>row.action==='library_thumbnails').length>=2));
    await page.evaluate(()=>window.receiveLibraryThumbnails({'Renamed.skp':{key:'R2',url:null}}));
    await page.locator('#library-refresh').click();
    await page.evaluate(value=>window.receiveLibrary(value),catalog);
    assert(await page.locator('#library-refresh').isDisabled(),'Unsolicited update cannot acknowledge a pending command');
    catalog.background=false;await page.evaluate(value=>window.receiveLibrary(value),catalog);
    catalog.entries=catalog.entries.slice(0,1);catalog.background=true;
    await page.evaluate(value=>window.receiveLibrary(value),catalog);
    assert.equal(await page.locator('#library-selected-name').textContent(),'Cabinet Renamed');
    await page.locator('#learn-tab').click();
    assert(await page.evaluate(()=>sent.some(row=>row.action==='library_visibility'&&!row.visible)));
    await page.locator('#library-tab').click();
    assert(await page.evaluate(()=>sent.at(-1).action==='library_visibility'&&sent.at(-1).visible));
    assert.deepEqual(errors,[]);
    console.log('Library rename/delete refresh, cached images, selection/search, stale batches and visibility passed.');
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});

// Developer Chromium checks; no browser runtime ships in the extension.
const {chromium}=require(process.env.MH_PLAYWRIGHT||'playwright');
const path=require('path'),fs=require('fs'),assert=require('assert');
const root=path.resolve(__dirname,'..');
(async()=>{
  const browser=await chromium.launch({headless:true,executablePath:process.env.MH_BROWSER||undefined});
  try{
    const page=await browser.newPage({viewport:{width:1400,height:900}}),errors=[];
    page.on('pageerror',error=>errors.push(error.message));
    await page.addInitScript(()=>{window.sent=[];window.sketchup={request:raw=>sent.push(JSON.parse(raw)),hud_request:raw=>sent.push(JSON.parse(raw))};});
    const file=name=>'file:///'+path.join(root,'ui',name).replaceAll('\\','/');
    const views={saved:'Ảnh gốc SKP',iso:'3D',front:'Mặt đứng',top:'Mặt bằng',left:'Mặt trái',right:'Mặt phải',back:'Mặt sau',bottom:'Mặt dưới'};
    const report=JSON.parse(fs.readFileSync(path.join(root,'outputs/native-051.json'),'utf8'));
    const image=view=>'data:image/png;base64,'+fs.readFileSync(report.images[view].path).toString('base64');
    const catalog={root:'D:/Library',settings:{folder:'',view:'grid',thumbnail_size:150,hud_size:56,folder_keys:{}},folders:[{id:'',name:'Library',parent:null}],thumbnail_views:views,
      entries:[{id:'A.skp',name:'Khung bếp A',folder:'',bytes:12000,fingerprint:'source-a',thumbnail_key:'a1',thumbnail_view:'saved'},
               {id:'B.skp',name:'Khung bếp B',folder:'',bytes:12000,fingerprint:'source-b',thumbnail_key:'b1',thumbnail_view:'top'}]};
    await page.goto(file('index.html'));
    const studio=JSON.parse(fs.readFileSync(path.join(root,'outputs/ui-test-state.json'),'utf8'));
    await page.evaluate(state=>window.receive(state),studio);
    await page.locator('#library-tab').click();
    await page.evaluate(state=>window.receiveLibrary(state),catalog);
    assert.equal(await page.locator('#library-image-view option').count(),8);
    assert.equal(await page.locator('#library-image-view').inputValue(),'saved','Explicit view retained');
    delete catalog.entries[0].thumbnail_view;await page.evaluate(state=>window.receiveLibrary(state),catalog);
    assert.equal(await page.locator('#library-image-view').inputValue(),'front','Unconfigured module defaults to front');
    await page.locator('#library-image-view').selectOption('front');
    await page.evaluate(data=>window.receiveLibraryThumbnails(data),{'A.skp':{key:'a1',url:image('saved')}});
    assert.equal(await page.locator('#library-image-view').inputValue(),'front','async thumbnail must preserve unsubmitted selection');
    await page.locator('#library-update-image').click();
    assert.deepEqual(await page.evaluate(()=>sent.at(-1)),{action:'library_thumbnail_view',id:'A.skp',view:'front'});
    assert(await page.locator('#library-update-image').isDisabled());
    catalog.entries[0].thumbnail_key='a2';catalog.entries[0].thumbnail_view='front';
    await page.evaluate(state=>window.receiveLibrary(state),catalog);
    await page.evaluate(data=>window.receiveLibraryThumbnails(data),{'A.skp':{key:'a1',url:image('saved')}});
    assert.equal(await page.locator('#library-preview img').count(),0,'old pending response must not restore stale image');
    await page.evaluate(data=>window.receiveLibraryThumbnails(data),{'A.skp':{key:'a2',url:image('front')}});
    assert.equal(await page.locator('#library-preview img').getAttribute('src'),image('front'));
    assert.equal(await page.locator('.library-card[data-id="A.skp"] img').getAttribute('src'),image('front'));
    await page.locator('.library-card[data-id="B.skp"]').click();
    assert.equal(await page.locator('#library-image-view').inputValue(),'top');
    await page.locator('#library-image-view').selectOption('left');await page.locator('#library-update-image').click();
    await page.evaluate(state=>window.receiveLibrary({...state,error:true,message:'Không ghi được ảnh.'}),catalog);
    assert(await page.locator('#library-update-image').isEnabled());
    assert.equal(await page.locator('#library-image-view').inputValue(),'left','failure keeps draft for retry');
    await page.locator('.library-card[data-id="A.skp"]').click();
    assert.equal(await page.locator('#library-image-view').inputValue(),'front');
    await page.locator('#library-list').click();
    await page.evaluate(state=>window.receiveLibrary({...state,settings:{...state.settings,view:'list'}}),catalog);
    assert(await page.locator('#library-items').evaluate(el=>el.classList.contains('library-list-view')));
    await page.locator('#library-search').fill('bep b');
    assert.equal(await page.locator('.library-card').count(),1);
    await page.locator('#library-search').fill('');
    for(const width of [1000,1400]){await page.setViewportSize({width,height:900});assert(await page.evaluate(()=>document.body.scrollWidth<=innerWidth+1));}
    await page.screenshot({path:path.join(root,'outputs/library-views-051.png')});

    await page.goto(file('hud_settings.html'));await page.setViewportSize({width:370,height:550});
    const hud={settings:catalog.settings,folders:catalog.folders};
    await page.evaluate(state=>window.receiveHUDSettings(state),hud);
    assert.equal(await page.locator('#icons,#icon-page,#icon-prev,#icon-next').count(),0);
    assert(!await page.locator('body').textContent().then(text=>text.includes('Góc ảnh từng icon')));
    const folder=page.locator('#folders input');await folder.fill('A');await folder.blur();
    assert.deepEqual((await page.evaluate(()=>sent.at(-1))).settings.folder_keys,{'':'A'});
    await page.locator('#size').fill('24');assert.equal((await page.evaluate(()=>sent.at(-1))).settings.hud_size,24);
    assert.equal(await page.locator('#image-zoom').inputValue(),'100');
    await page.locator('#image-zoom').fill('50');assert.deepEqual((await page.evaluate(()=>sent.at(-1))).settings,{hud_image_zoom:50});
    await page.evaluate(state=>window.receiveHUDSettings({...state,settings:{...state.settings,hud_size:24,hud_image_zoom:50}}),hud);
    assert.equal(await page.locator('#image-zoom-value').textContent(),'50%');assert.equal(await page.locator('#size').inputValue(),'24');
    await page.locator('#image-zoom').fill('250');assert.deepEqual((await page.evaluate(()=>sent.at(-1))).settings,{hud_image_zoom:250});
    await page.locator('#position').selectOption('cursor');assert.equal((await page.evaluate(()=>sent.at(-1))).settings.hud_position,'cursor');
    await page.locator('#edit').click();assert.equal((await page.evaluate(()=>sent.at(-1))).action,'edit');
    await page.locator('#export-config').click();assert.equal((await page.evaluate(()=>sent.at(-1))).action,'export_config');
    assert(await page.locator('#import-config').isDisabled());assert(await page.locator('#export-config').isDisabled());
    await page.evaluate(state=>window.receiveHUDSettings(state),hud);
    assert(await page.locator('#import-config').isEnabled());assert(await page.locator('#export-config').isEnabled());
    await page.locator('#import-config').click();assert.equal((await page.evaluate(()=>sent.at(-1))).action,'import_config');
    await page.evaluate(state=>window.receiveHUDSettings({...state,error:'Config không hợp lệ.'}),hud);
    assert(await page.locator('#import-config').isEnabled());assert(await page.locator('#export-config').isEnabled());
    assert.equal(await page.locator('#status').textContent(),'Config không hợp lệ.');
    await page.evaluate(state=>window.receiveHUDSettings({...state,message:'Đã nhập config HUD.'}),hud);
    assert.equal(await page.locator('#status').textContent(),'Đã nhập config HUD.');
    assert(await page.evaluate(()=>document.body.scrollWidth<=innerWidth+1&&document.body.scrollHeight<=innerHeight+1));
    await page.screenshot({path:path.join(root,'outputs/hud-views-051.png')});
    await page.keyboard.press('Escape');assert.equal((await page.evaluate(()=>sent.at(-1))).action,'exit');
    assert.deepEqual(errors,[]);
    console.log('Library-only icon view editing, independent selections, async cache invalidation, draft retention, updates/errors; compact HUD Settings retains size, position, Edit and shortcuts.');
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});

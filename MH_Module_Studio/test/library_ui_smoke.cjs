// Developer Chromium checks, not a runtime dependency.
const {app,BrowserWindow}=require('electron');
const fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');
app.whenReady().then(async()=>{
 const win=new BrowserWindow({show:false,width:1390,height:960,webPreferences:{contextIsolation:true,sandbox:true}}),errors=[];
 win.webContents.on('console-message',(_e,level,message)=>{if(level>=3)errors.push(message);});
 const js=code=>win.webContents.executeJavaScript(code),sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
 const click=id=>js(`document.getElementById(${JSON.stringify(id)}).click()`);
 const catalog={root:'D:/Thư viện',settings:{root:'D:/Thư viện',folder:'Tủ dưới',view:'grid',thumbnail_size:150,hud_size:86,folder_keys:{}},folders:[{id:'',name:'MH Library',parent:null},{id:'Tủ dưới',name:'Tủ dưới',parent:''},{id:'Tủ dưới/Góc',name:'Góc',parent:'Tủ dưới'},{id:'Tủ trên',name:'Tủ trên',parent:''}],entries:Array.from({length:18},(_,i)=>({id:`Tủ dưới/Khung bếp ${i+1}.skp`,name:`Khung bếp ${i+1}`,folder:'Tủ dưới',bytes:53000,fingerprint:'fp-'+i}))};
 catalog.entries.push({id:'Tủ trên/<img>.skp',name:'<img src=x onerror="window.bad=true">',folder:'Tủ trên',bytes:1000,fingerprint:'attack'});
 try{
  await win.loadFile(path.join(root,'ui','index.html'));
  const studio=JSON.parse(fs.readFileSync(path.join(root,'outputs','ui-test-state.json'),'utf8'));
  await js(`window.receive(${JSON.stringify(studio)});window.mockCatalog=${JSON.stringify(catalog)};window.recorded=[];window.sketchup={request:raw=>{const data=JSON.parse(raw);recorded.push(data);if(data.action==='library_settings')Object.assign(mockCatalog.settings,data.settings);if(data.action==='library_hud_edit'){mockCatalog.hud_editing=true;mockCatalog.hud_active=true;}if(data.action==='library_thumbnails'){setTimeout(()=>window.receiveLibraryThumbnails(Object.fromEntries(data.ids.map(id=>[id,{fingerprint:mockCatalog.entries.find(item=>item.id===id).fingerprint,url:null}]))),5);}else if(data.action.startsWith('library_'))setTimeout(()=>window.receiveLibrary(structuredClone(mockCatalog)),5);}};void 0;`);
  await click('library-tab');await sleep(150);
  assert(await js(`document.body.classList.contains('library-mode')&&getComputedStyle(document.getElementById('work-area')).display==='none'`));
  await click('learn-tab');await js(`window.openLibraryTab()`);
  assert(await js(`document.body.classList.contains('library-mode')&&document.getElementById('library-tab').classList.contains('active')`));
  assert.equal(await js(`document.querySelectorAll('.library-card').length`),18);
  assert(await js(`!document.getElementById('library-place').disabled`));
  await click('library-list');await sleep(30);assert(await js(`document.getElementById('library-items').classList.contains('library-list-view')`));
  await js(`document.getElementById('library-size').value=220;document.getElementById('library-size').dispatchEvent(new Event('input'));`);await sleep(210);
  assert.equal(await js(`getComputedStyle(document.querySelector('.library-image')).height`),'220px');
  assert(await js(`recorded.some(data=>data.action==='library_settings'&&data.settings.thumbnail_size===220)`));
  await js(`document.getElementById('library-search').value='bep 12';document.getElementById('library-search').dispatchEvent(new Event('input'));`);
  assert.equal(await js(`document.querySelectorAll('.library-card').length`),1);
  await js(`document.querySelector('.library-card').click()`);await click('library-place');await sleep(25);
  assert.equal(await js(`recorded.findLast(data=>data.action==='library_place').id`),'Tủ dưới/Khung bếp 12.skp');
  for(const id of ['library-choose','library-save']){await click(id);await sleep(25);assert(await js(`!document.getElementById('library-choose').disabled&&!document.getElementById('library-refresh').disabled`));}
  await js(`Array.from(document.querySelectorAll('.library-folder')).find(n=>n.textContent.includes('Tủ trên')).click()`);await sleep(30);
  assert.equal(await js(`document.querySelectorAll('.library-card').length`),1);
  assert(await js(`!window.bad&&!document.querySelector('.library-card img')&&document.querySelector('.library-card strong').textContent.includes('<img')`));
  await click('library-edit-hud');await sleep(35);
  assert(await js(`document.querySelector('.library-card').dataset.hudDraggable==='true'`));
  await js(`const card=document.querySelector('.library-card');for(const [type,x] of [['pointerdown',20],['pointermove',60],['pointerup',60]])card.dispatchEvent(new PointerEvent(type,{bubbles:true,pointerId:1,button:0,clientX:x,clientY:20}));`);
  const drag=await js(`recorded.findLast(data=>data.action==='library_hud_drag')`),drop=await js(`recorded.findLast(data=>data.action==='library_hud_drop')`);
  assert.equal(drag.root,catalog.root);assert(drag.token&&drop.token===drag.token);assert(drag.id.includes('<img>'));
  assert(await js(`!document.querySelector('.library-card').draggable`));
  await js(`document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));`);
  assert(await js(`recorded.some(data=>data.action==='library_hud_exit')`));
  await click('learn-tab');assert(await js(`!document.body.classList.contains('library-mode')&&state.snapshots.length===3`));
  await click('library-tab');await click('library-grid');await sleep(30);
  for(const [width,height] of [[1390,960],[1000,650]]){win.setSize(width,height);await sleep(60);assert(await js(`document.body.scrollWidth<=innerWidth+1&&document.body.scrollHeight<=innerHeight+1`));}
  const native=JSON.parse(fs.readFileSync(path.join(root,'outputs','native-library-017.json'),'utf8'));
  const png='data:image/png;base64,'+fs.readFileSync(native.thumbnail).toString('base64');
  await js(`window.receiveLibrary(${JSON.stringify(catalog)});window.receiveLibraryThumbnails(${JSON.stringify(Object.fromEntries(catalog.entries.map(item=>[item.id,{fingerprint:item.fingerprint,url:png}])))});`);
  win.setSize(1390,960);await sleep(100);fs.writeFileSync(path.join(root,'outputs','library-ui-017.png'),(await win.webContents.capturePage()).toPNG());
  await win.loadFile(path.join(root,'ui','hud_settings.html'));
  await js(`window.recorded=[];window.sketchup={hud_request:raw=>recorded.push(JSON.parse(raw))};window.receiveHUDSettings(${JSON.stringify({settings:catalog.settings,folders:catalog.folders})});`);
  await js(`document.getElementById('size').value=120;document.getElementById('size').dispatchEvent(new Event('input'));`);
  assert.equal(await js(`recorded.at(-1).settings.hud_size`),120);
  await js(`document.getElementById('size').value=24;document.getElementById('size').dispatchEvent(new Event('input'));`);
  assert.equal(await js(`recorded.at(-1).settings.hud_size`),24);
  await js(`document.getElementById('position').value='cursor';document.getElementById('position').dispatchEvent(new Event('change'));`);
  assert.equal(await js(`recorded.at(-1).settings.hud_position`),'cursor');
  await click('edit');assert.equal(await js(`recorded.at(-1).action`),'edit');assert.equal(await js(`recorded.at(-1).enabled`),true);
  win.setSize(370,550);await sleep(60);assert(await js(`document.body.scrollWidth<=innerWidth+1&&document.body.scrollHeight<=innerHeight+1`));
  await js(`document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));document.dispatchEvent(new KeyboardEvent('keydown',{key:' ',code:'Space',bubbles:true}));`);
  assert.equal(await js(`recorded.filter(data=>data.action==='exit').length`),2);
  assert.deepEqual(errors,[]);console.log('Library UI: nested folders, grid/list, size, search, placement dispatch, picker cancellation, escaping, layout, Studio retained; HUD settings and exit keys passed.');
  win.destroy();app.exit(0);
 }catch(error){console.error(error.stack);win.destroy();app.exit(1);}
});

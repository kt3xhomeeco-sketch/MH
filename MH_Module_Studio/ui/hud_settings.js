'use strict';
let current={settings:{folder_keys:{}},folders:[]};
const send=(action,extra={})=>window.sketchup?.hud_request(JSON.stringify({action,...extra}));
const $=id=>document.getElementById(id);
window.receiveHUDSettings=state=>{
  current=state;$('size').value=state.settings.hud_size;$('value').value=state.settings.hud_size+' px';$('status').textContent=state.error||state.message||'';
  $('status').classList.toggle('error',Boolean(state.error));
  for(const id of ['import-config','export-config'])$(id).disabled=false;
  $('image-zoom').value=state.settings.hud_image_zoom??100;$('image-zoom-value').value=(state.settings.hud_image_zoom??100)+'%';
  $('position').value=state.settings.hud_position||'center';$('edit').classList.toggle('active',Boolean(state.editing));$('edit').textContent=state.editing?'Kết thúc Edit':'Edit · Sắp xếp icon';
  if(document.activeElement?.dataset.folder!=null)return;
  $('folders').replaceChildren();
  for(const folder of state.folders){const row=document.createElement('label');row.className='folder-key';const name=document.createElement('span');name.textContent=folder.id||folder.name;const input=document.createElement('input');input.maxLength=1;input.dataset.folder=folder.id;input.value=state.settings.folder_keys[folder.id]||'';input.setAttribute('aria-label','Phím cho '+name.textContent);
    input.addEventListener('change',()=>{const key=input.value.trim().toUpperCase();if(key&&!/^[A-Z]$/.test(key)){$('status').textContent='Chỉ dùng một chữ A–Z.';return;}const keys={...current.settings.folder_keys};for(const [id,letter] of Object.entries(keys)){if(letter===key)delete keys[id];}if(key)keys[folder.id]=key;else delete keys[folder.id];send('settings',{settings:{folder_keys:keys}});});row.append(name,input);$('folders').append(row);}
};
$('size').addEventListener('input',()=>{$('value').value=$('size').value+' px';send('settings',{settings:{hud_size:Number($('size').value)}});});
$('image-zoom').addEventListener('input',()=>{$('image-zoom-value').value=$('image-zoom').value+'%';send('settings',{settings:{hud_image_zoom:Number($('image-zoom').value)}});});
$('position').addEventListener('change',()=>send('settings',{settings:{hud_position:$('position').value}}));
$('edit').addEventListener('click',()=>send('edit',{enabled:!current.editing}));
for(const [id,action] of [['import-config','import_config'],['export-config','export_config']])$(id).addEventListener('click',()=>{
  $('import-config').disabled=true;$('export-config').disabled=true;send(action);
});
$('close').addEventListener('click',()=>send('close'));
document.addEventListener('keydown',event=>{if(event.key==='Escape'||event.code==='Space'){event.preventDefault();event.stopPropagation();send('exit');}},true);
send('ready');

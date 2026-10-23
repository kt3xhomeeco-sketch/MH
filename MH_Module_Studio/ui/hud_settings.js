'use strict';
let current={settings:{hud_boards:[]},boards:[]};
const send=(action,extra={})=>window.sketchup?.hud_request(JSON.stringify({action,...extra}));
const $=id=>document.getElementById(id);
window.receiveHUDSettings=state=>{
  current=state;$('size').value=state.settings.hud_size;$('value').value=state.settings.hud_size+' px';$('status').textContent=state.error||state.message||'';
  $('status').classList.toggle('error',Boolean(state.error));
  for(const id of ['import-config','export-config'])$(id).disabled=false;
  $('image-zoom').value=state.settings.hud_image_zoom??100;$('image-zoom-value').value=(state.settings.hud_image_zoom??100)+'%';
  $('position').value=state.settings.hud_position||'center';$('edit').classList.toggle('active',Boolean(state.editing));$('edit').textContent=state.editing?'Kết thúc Edit':'Edit · Sắp xếp icon';
  $('spacing').value=state.settings.hud_spacing??100;$('spacing-value').value=(state.settings.hud_spacing??100)+'%';$('spacing').disabled=!state.editing;
  $('board-create').hidden=!state.editing;
  if(state.editing&&document.activeElement?.matches('#boards input'))return;
  $('boards').replaceChildren();
  for(const board of state.boards||state.settings.hud_boards||[]){
    const row=document.createElement('div');row.className='board-row';
    const select=document.createElement('button');select.type='button';select.className='board-select';select.textContent=board.id===state.settings.hud_board?'●':'○';select.title='Mở bảng '+board.name;
    select.addEventListener('click',()=>send('select_board',{id:board.id}));
    const name=document.createElement('input');name.value=board.name;name.maxLength=80;name.setAttribute('aria-label','Tên bảng '+board.name);name.disabled=!state.editing;
    const update=()=>{if(!name.value.trim()){$('status').textContent='Nhập tên bảng.';return;}send('board',{operation:'update',board:{id:board.id,name:name.value.trim()}});};
    name.addEventListener('change',update);
    row.append(select,name);
    if(state.editing){
      const page=document.createElement('button');page.type='button';page.textContent='+8';page.title='Thêm trang 8 ô';page.addEventListener('click',()=>send('board',{operation:'page',board:{id:board.id}}));
      const remove=document.createElement('button');remove.type='button';remove.textContent='×';remove.title='Xóa bảng icon';remove.addEventListener('click',()=>send('board',{operation:'delete',board:{id:board.id}}));row.append(page,remove);
    }
    $('boards').append(row);
  }
  if(!$('boards').children.length)$('boards').textContent='Chưa có bảng. Bật Edit và tạo bảng bên dưới.';
};
$('board-create').addEventListener('submit',event=>{event.preventDefault();if(!event.currentTarget.reportValidity())return;send('board',{operation:'create',board:{name:$('board-name').value.trim()}});});
$('size').addEventListener('input',()=>{$('value').value=$('size').value+' px';send('settings',{settings:{hud_size:Number($('size').value)}});});
$('spacing').addEventListener('input',()=>{$('spacing-value').value=$('spacing').value+'%';send('settings',{settings:{hud_spacing:Number($('spacing').value)}});});
$('image-zoom').addEventListener('input',()=>{$('image-zoom-value').value=$('image-zoom').value+'%';send('settings',{settings:{hud_image_zoom:Number($('image-zoom').value)}});});
$('position').addEventListener('change',()=>send('settings',{settings:{hud_position:$('position').value}}));
$('edit').addEventListener('click',()=>send('edit',{enabled:!current.editing}));
for(const [id,action] of [['import-config','import_config'],['export-config','export_config']])$(id).addEventListener('click',()=>{
  $('import-config').disabled=true;$('export-config').disabled=true;send(action);
});
$('close').addEventListener('click',()=>send('close'));
document.addEventListener('keydown',event=>{if(event.key==='Escape'||event.code==='Space'&&!['INPUT','TEXTAREA','SELECT'].includes(event.target.tagName)){event.preventDefault();event.stopPropagation();send('exit');}},true);
send('ready');

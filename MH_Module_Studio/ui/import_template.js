'use strict';
window.ImportTemplateUI=(()=>{
  const root=document.getElementById('import-links'),get=id=>document.getElementById(id),names=[['Trái','Phải'],['Trước','Sau'],['Dưới','Trên']];
  const defaults=()=>({version:1,enabled:false,role:'module',mode:'auto',door_face:'1:1',door_gap:1,faces:names.flatMap((sides,axis)=>sides.map((name,side)=>({axis,side,enabled:!(axis===1&&side===0),gap:0})))});
  let value=defaults();
  function render(){
    get('import-enabled').checked=value.enabled;get('import-role').value=value.role;get('import-mode').value=value.mode;get('import-door-face').value=value.door_face;get('import-door-gap').value=value.door_gap;
    root.querySelector('.import-door').hidden=value.role!=='door';
    get('import-faces').replaceChildren();
    for(const face of value.faces){
      const label=document.createElement('label'),tick=document.createElement('input'),gap=document.createElement('input'),name=document.createElement('span'),unit=document.createElement('span');
      tick.type='checkbox';tick.checked=face.enabled;tick.dataset.importSlot=`${face.axis}:${face.side}`;tick.setAttribute('aria-label',`Liên kết mặt ${names[face.axis][face.side]}`);
      name.textContent=names[face.axis][face.side];gap.type='number';gap.min='0';gap.max='1000';gap.step='0.1';gap.value=face.gap;gap.dataset.importGap=`${face.axis}:${face.side}`;gap.setAttribute('aria-label',`Khoảng hở mặt ${name.textContent}`);unit.textContent='mm';
      tick.addEventListener('change',()=>{face.enabled=tick.checked;markDirty();});gap.addEventListener('input',()=>{face.gap=Number(gap.value);markDirty();});
      label.append(tick,name,gap,unit);get('import-faces').append(label);
    }
  }
  for(const [axis,sides]of names.entries())for(const [side,name]of sides.entries()){const option=document.createElement('option');option.value=`${axis}:${side}`;option.textContent=name;get('import-door-face').append(option);}
  for(const [id,key]of [['import-enabled','enabled'],['import-role','role'],['import-mode','mode'],['import-door-face','door_face'],['import-door-gap','door_gap']]){
    get(id).addEventListener(id==='import-door-gap'?'input':'change',()=>{value[key]=key==='enabled'?get(id).checked:key==='door_gap'?Number(get(id).value):get(id).value;if(key==='role')root.querySelector('.import-door').hidden=value.role!=='door';markDirty();});
  }
  get('import-five').addEventListener('click',()=>{value.faces=defaults().faces;value.enabled=true;render();markDirty();});
  get('import-apply').addEventListener('click',()=>get('save-variables').click());
  function refresh(blocked,available,assembly,editing){
    const disabled=Boolean(blocked||!available||assembly||editing);
    root.querySelectorAll('input,select,button').forEach(node=>node.disabled=disabled);
    get('import-apply').disabled=disabled||!dirty;
  }
  function reset(next){value=structuredClone(next.rule?.import_template||defaults());render();refresh(pending||next.busy,Boolean(next.parametric_sheet),next.parametric_sheet?.assembly,cellEdit);}
  reset(state);
  return {reset,refresh,value:()=>structuredClone(value)};
})();

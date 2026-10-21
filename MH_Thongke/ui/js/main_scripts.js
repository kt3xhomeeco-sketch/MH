          (function(){
            function pad(n){n=parseInt(n,10);return n<10?'0'+n:''+n;}
            function fullYear(y){y=parseInt(y,10);if(y<100)y+=(y<70?2000:1900);return y;}
            function valid(y,m,d){
              y=fullYear(y);m=parseInt(m,10);d=parseInt(d,10);
              var dt=new Date(y,m-1,d);
              if(dt.getFullYear()===y&&dt.getMonth()===(m-1)&&dt.getDate()===d)return pad(d)+'/'+pad(m)+'/'+y;
              return null;
            }
            function complete(text){
              text=(text||'').toString().trim();
              return !text||/^\\d{1,2}[\\/\\-.]\\d{2}$/.test(text)||/^\\d{1,2}[\\/\\-.]\\d{1,2}[\\/\\-.]\\d{2,4}$/.test(text)||/^\\d{4}[\\/\\-.]\\d{1,2}[\\/\\-.]\\d{1,2}$/.test(text)||/^\\d{4}$/.test(text)||/^\\d{6}$/.test(text)||/^\\d{8}$/.test(text);
            }
            function normDate(value){
              var text=(value||'').toString().trim().replace(/^['"]+|['"]+$/g,'');
              if(!text)return '';
              var m=text.match(/^(\\d{4})[\\/\\-.](\\d{1,2})[\\/\\-.](\\d{1,2})(?:\\D|$)/);
              if(m){var ymd=valid(m[1],m[2],m[3]);if(ymd)return ymd;}
              m=text.match(/^(\\d{1,2})[\\/\\-.](\\d{1,2})(?:[\\/\\-.](\\d{2,4}))?(?:\\D|$)/);
              if(m){
                var y=m[3]||new Date().getFullYear();
                var dmy=valid(y,m[2],m[1]);if(dmy)return dmy;
                if(parseInt(m[2],10)>12&&parseInt(m[1],10)<=12){var mdy=valid(y,m[1],m[2]);if(mdy)return mdy;}
              }
              var digits=text.replace(/\\D/g,'');
              if(digits.length===8){
                if(parseInt(digits.substr(0,4),10)>=1900){var c1=valid(digits.substr(0,4),digits.substr(4,2),digits.substr(6,2));if(c1)return c1;}
                var c2=valid(digits.substr(4,4),digits.substr(2,2),digits.substr(0,2));if(c2)return c2;
              }else if(digits.length===6){var c3=valid(digits.substr(4,2),digits.substr(2,2),digits.substr(0,2));if(c3)return c3;
              }else if(digits.length===4){var c4=valid(new Date().getFullYear(),digits.substr(2,2),digits.substr(0,2));if(c4)return c4;}
              return text;
            }
            function sameGroup(a,b){
              return a&&b&&a.getAttribute('data-bulk-table')===b.getAttribute('data-bulk-table')&&a.getAttribute('data-bulk-field')===b.getAttribute('data-bulk-field');
            }
            function sig(inp,value){
              return [(inp.getAttribute('data-bulk-table')||'acc'),(inp.getAttribute('data-bulk-field')||''),(inp.getAttribute('data-bulk-index')||'-1'),value].join('|');
            }
            function peerDateInputs(inp){
              var table=inp.getAttribute('data-bulk-table')||'acc';
              var idx=inp.getAttribute('data-bulk-index')||'-1';
              return Array.prototype.slice.call(document.querySelectorAll("input.bulk-edit[data-bulk-field='ngay_dat'][data-bulk-table='"+table+"'][data-bulk-index='"+idx+"']"));
            }
            function selectedInputs(inp){
              var all=Array.prototype.slice.call(document.querySelectorAll('td.bulk-cell-selected input.bulk-edit'));
              return all.filter(function(x){return sameGroup(x,inp);});
            }
            function syncPeers(inp,value){
              peerDateInputs(inp).forEach(function(x){x.value=value;x.setAttribute('data-committed-sig',sig(x,value));});
            }
            window.MHDateCommit=function(inp,delayed){
              if(!inp)return false;
              if(delayed&&!complete(inp.value))return false;
              clearTimeout(inp._mhDateTimer);
              var run=function(){
                var field=inp.getAttribute('data-bulk-field')||'';
                if(field!=='ngay_dat')return false;
                var value=normDate(inp.value);
                var table=inp.getAttribute('data-bulk-table')||'acc';
                var idx=parseInt(inp.getAttribute('data-bulk-index')||'-1',10);
                var selected=selectedInputs(inp);
                if(selected.indexOf(inp)>=0&&selected.length>1){
                  var payload=[];
                  selected.forEach(function(x){
                    syncPeers(x,value);
                    payload.push({table:x.getAttribute('data-bulk-table')||'acc',field:'ngay_dat',idx:parseInt(x.getAttribute('data-bulk-index')||'-1',10),value:value});
                  });
                  try{if(window.sketchup&&sketchup.bulk_update_cells)sketchup.bulk_update_cells(JSON.stringify(payload));}catch(e){}
                  return true;
                }
                if(inp.getAttribute('data-committed-sig')===sig(inp,value))return true;
                syncPeers(inp,value);
                try{
                  if(window.sketchup){
                    if(table==='mat'&&sketchup.update_mat_ngay_dat)sketchup.update_mat_ngay_dat(idx,value);
                    else if(sketchup.update_ngay_dat)sketchup.update_ngay_dat(idx,value);
                  }
                }catch(e){}
                return true;
              };
              if(delayed)inp._mhDateTimer=setTimeout(run,350);else run();
              return true;
            };
            window.MHSelectBulkInput=function(inp,ev){
              if(!inp)return;
              var all=Array.prototype.slice.call(document.querySelectorAll('input.bulk-edit')).filter(function(x){return sameGroup(x,inp);});
              var selected=selectedInputs(inp);
              if(ev&&ev.shiftKey&&window.MHBulkAnchor&&sameGroup(window.MHBulkAnchor,inp)){
                var a=all.indexOf(window.MHBulkAnchor),b=all.indexOf(inp);
                if(a>=0&&b>=0){
                  document.querySelectorAll('td.bulk-cell-selected').forEach(function(td){td.classList.remove('bulk-cell-selected');});
                  all.slice(Math.min(a,b),Math.max(a,b)+1).forEach(function(x){var td=x.closest('td');if(td)td.classList.add('bulk-cell-selected');});
                  ev.preventDefault();
                }
                return;
              }
              if(ev&&(ev.ctrlKey||ev.metaKey)){
                var pos=selected.indexOf(inp);
                if(pos>=0)selected.splice(pos,1);else selected.push(inp);
                document.querySelectorAll('td.bulk-cell-selected').forEach(function(td){td.classList.remove('bulk-cell-selected');});
                selected.forEach(function(x){var td=x.closest('td');if(td)td.classList.add('bulk-cell-selected');});
                window.MHBulkAnchor=inp;ev.preventDefault();return;
              }
              if(selected.indexOf(inp)<0||selected.length<=1){
                document.querySelectorAll('td.bulk-cell-selected').forEach(function(td){td.classList.remove('bulk-cell-selected');});
                var td=inp.closest('td');if(td)td.classList.add('bulk-cell-selected');
              }
              window.MHBulkAnchor=inp;
            };
            document.addEventListener('mousedown',function(e){var inp=e.target.closest&&e.target.closest('input.bulk-edit');if(inp)window.MHSelectBulkInput(inp,e);},true);
            document.addEventListener('input',function(e){var inp=e.target.closest&&e.target.closest('input.date-edit');if(inp)window.MHDateCommit(inp,true);},true);
            document.addEventListener('keyup',function(e){var inp=e.target.closest&&e.target.closest('input.date-edit');if(inp)window.MHDateCommit(inp,true);},true);
            document.addEventListener('change',function(e){var inp=e.target.closest&&e.target.closest('input.date-edit');if(inp)window.MHDateCommit(inp,false);},true);
            document.addEventListener('blur',function(e){var inp=e.target.closest&&e.target.closest('input.date-edit');if(inp)window.MHDateCommit(inp,false);},true);
          })();
          function mhUiDebug(message){
            try{ if(window.MH_THONGKE_DEBUG && window.sketchup && sketchup.main_ui_debug) sketchup.main_ui_debug(String(message)); }catch(e){}
          }
          window.addEventListener('error',function(e){
            mhUiDebug('window.error '+(e.message||'')+' line='+(e.lineno||''));
          });
          window.addEventListener('unhandledrejection',function(e){
            mhUiDebug('unhandledrejection '+(e.reason&&e.reason.message?e.reason.message:e.reason));
          });
          function tab(id, el, persist) {
            if(id === 'tab-import') id = 'tab-files';
            document.querySelectorAll('.content').forEach(function(c){ c.style.display='none'; });
            document.querySelectorAll('.tab').forEach(function(t){ t.classList.remove('active'); });
            var content = document.getElementById(id) || document.getElementById('tab-all');
            if(content) content.style.display = 'block';
            if(el) el.classList.add('active');
            if(persist !== false){
              try { sessionStorage.setItem('lastTabMHThongke', id); } catch(e) {}
              try { if(window.sketchup && sketchup.dialog_tab_changed) sketchup.dialog_tab_changed(id); } catch(e) {}
            }
            if(typeof initVisibleColumnResize === 'function') setTimeout(initVisibleColumnResize, 0);
          }
          function stopMiniEvent(){ if(window.event){ window.event.stopPropagation(); } }
          function rowProduct(el){ return (el && el.getAttribute) ? (el.getAttribute('data-product') || '') : ''; }
          function selectImportRow(row){
            if(!row || !row.getAttribute || !row.getAttribute('data-name')) return;
            document.querySelectorAll('.mini-row.selected').forEach(function(r){ r.classList.remove('selected'); });
            row.classList.add('selected');
            try{
              if(window.sketchup && sketchup.select_item){
                sketchup.select_item(row.getAttribute('data-product') || '', row.getAttribute('data-name') || '', row.getAttribute('data-ids') || '');
              }
            }catch(e){}
          }
          function acceptImportItem(btn){
            stopMiniEvent();
            try{
              if(window.sketchup && sketchup.accept_item){
                sketchup.accept_item(rowProduct(btn), btn.getAttribute('data-kind') || 'PK', btn.getAttribute('data-old') || '', btn.getAttribute('data-name') || '', btn.getAttribute('data-spec') || '');
              }
            }catch(e){}
          }
          function updateImportItem(btn){
            stopMiniEvent();
            try{
              if(window.sketchup && sketchup.update_item){
                sketchup.update_item(rowProduct(btn), btn.getAttribute('data-old') || '', btn.getAttribute('data-name') || '', btn.getAttribute('data-spec') || '');
              }
            }catch(e){}
          }
          function keepImportItem(btn){
            stopMiniEvent();
            try{
              if(window.sketchup && sketchup.keep_item){
                sketchup.keep_item(rowProduct(btn), btn.getAttribute('data-kind') || 'PK', btn.getAttribute('data-old') || '', btn.getAttribute('data-name') || '', btn.getAttribute('data-spec') || '');
              }
            }catch(e){}
          }
          function deleteImportItem(btn){
            stopMiniEvent();
            try{
              if(window.sketchup && sketchup.delete_item){
                sketchup.delete_item(rowProduct(btn), btn.getAttribute('data-name') || '', btn.getAttribute('data-ids') || '');
              }
            }catch(e){}
          }
          function removeExcelItem(btn){
            stopMiniEvent();
            try{
              if(window.sketchup && sketchup.remove_excel_item){
                sketchup.remove_excel_item(rowProduct(btn), btn.getAttribute('data-kind') || 'PK', btn.getAttribute('data-name') || '', btn.getAttribute('data-spec') || '');
              }
            }catch(e){}
          }
          function renameImportItem(input){
            try{
              if(window.sketchup && sketchup.rename_item){
                sketchup.rename_item(
                  rowProduct(input),
                  input.getAttribute('data-old') || '',
                  input.value || '',
                  input.getAttribute('data-target') || '',
                  input.getAttribute('data-spec') || '',
                  input.getAttribute('data-kind') || 'PK'
                );
              }
            }catch(e){}
          }
          function setImportNote(input){
            try{
              if(window.sketchup && sketchup.set_note){
                sketchup.set_note(rowProduct(input), input.getAttribute('data-kind') || 'PK', input.getAttribute('data-name') || '', input.getAttribute('data-spec') || '', input.value || '');
              }
            }catch(e){}
          }
          function normalizeMhDate(value){
            var text=(value||'').toString().trim().replace(/^['"]+|['"]+$/g,'');
            if(!text)return '';
            function pad(n){n=parseInt(n,10);return n<10?'0'+n:''+n;}
            function fullYear(y){y=parseInt(y,10);if(y<100)y+=(y<70?2000:1900);return y;}
            function valid(y,m,d){
              y=fullYear(y);m=parseInt(m,10);d=parseInt(d,10);
              var dt=new Date(y,m-1,d);
              if(dt.getFullYear()===y && dt.getMonth()===(m-1) && dt.getDate()===d)return pad(d)+'/'+pad(m)+'/'+y;
              return null;
            }
            var m=text.match(/^(\\d{4})[\\/\\-.](\\d{1,2})[\\/\\-.](\\d{1,2})(?:\\D|$)/);
            if(m){var ymd=valid(m[1],m[2],m[3]);if(ymd)return ymd;}
            m=text.match(/^(\\d{1,2})[\\/\\-.](\\d{1,2})(?:[\\/\\-.](\\d{2,4}))?(?:\\D|$)/);
            if(m){
              var y=m[3]||new Date().getFullYear();
              var dmy=valid(y,m[2],m[1]);if(dmy)return dmy;
              if(parseInt(m[2],10)>12 && parseInt(m[1],10)<=12){var mdy=valid(y,m[1],m[2]);if(mdy)return mdy;}
            }
            var digits=text.replace(/\\D/g,'');
            if(digits.length===8){
              if(parseInt(digits.substr(0,4),10)>=1900){
                var c1=valid(digits.substr(0,4),digits.substr(4,2),digits.substr(6,2));if(c1)return c1;
              }else{
                var c2=valid(digits.substr(4,4),digits.substr(2,2),digits.substr(0,2));if(c2)return c2;
              }
            }else if(digits.length===6){
              var c3=valid(digits.substr(4,2),digits.substr(2,2),digits.substr(0,2));if(c3)return c3;
            }else if(digits.length===4){
              var c4=valid(new Date().getFullYear(),digits.substr(2,2),digits.substr(0,2));if(c4)return c4;
            }
            return text;
          }
          var mhActivityLast=0;
          function markDialogActivity(){
            var now=Date.now();
            if(now-mhActivityLast<350)return;
            mhActivityLast=now;
            try{ if(window.sketchup && sketchup.mark_dialog_activity) sketchup.mark_dialog_activity(); }catch(e){}
          }
          document.addEventListener('keydown',markDialogActivity,true);
          document.addEventListener('input',markDialogActivity,true);
          document.addEventListener('focusin',markDialogActivity,true);
          function installTabHandlers(){
            document.querySelectorAll('.tab[data-tab]').forEach(function(el){
              el.addEventListener('click',function(ev){
                ev.preventDefault();
                ev.stopPropagation();
                tab(el.getAttribute('data-tab'),el);
              },false);
            });
          }
          function addHiddenItems(){
            var el=document.getElementById('hiddenInput');
            var value=el ? (el.value || '') : '';
            if(!value.trim()){alert('Nhập tên PK/VL cần ẩn.');return;}
            var items=collectHiddenItems().concat(splitHiddenInput(value));
            saveHiddenItems(items);
          }
          function removeHiddenItem(name){
            var target=normHiddenName(name || '');
            var items=collectHiddenItems().filter(function(item){return normHiddenName(item)!==target;});
            saveHiddenItems(items);
          }
          function normHiddenName(value){
            return (value || '').toString().trim().toLowerCase().replace(/\\s+/g,' ');
          }
          function collectHiddenItems(){
            var out=[];
            document.querySelectorAll('.hidden-item-row').forEach(function(row){
              var name=row.getAttribute('data-hidden-name') || '';
              if(name.trim())out.push(name.trim());
            });
            return out;
          }
          function splitHiddenInput(value){
            return (value || '').split(/[\\n\\r|;,]+/).map(function(x){return x.trim();}).filter(Boolean);
          }
          function saveHiddenItems(items){
            var seen={}, out=[];
            items.forEach(function(item){
              var key=normHiddenName(item);
              if(key && !seen[key]){seen[key]=true;out.push(item);}
            });
            sketchup.save_settings(out.length ? out.join('|') : '__MH_EMPTY_HIDDEN__');
          }
          function applySettings(){
            saveHiddenItems(collectHiddenItems());
          }
          function filterTable(){
            var f = document.getElementById("searchInput").value.toLowerCase();
            document.querySelectorAll("#table-acc .data-row,#table-mat .data-row,#table-all .data-row").forEach(function(row){
              var text = row.getAttribute('data-search')||row.innerText.toLowerCase();
              row.style.display = text.indexOf(f)>-1 ? "" : "none";
            });
          }
          function filterProjectTotal(){
            var raw=(document.getElementById('projectSearchInput').value||'').toLowerCase();
            var keys=raw.split(',').map(function(k){return k.trim();}).filter(Boolean);
            document.querySelectorAll('#table-project-total .project-total-row').forEach(function(row){
              var text=row.getAttribute('data-search')||row.innerText.toLowerCase();
              row.style.display = keys.length===0 || keys.some(function(k){return text.indexOf(k)>=0;}) ? '' : 'none';
            });
          }
          var bulkAnchorInput=null;
          var bulkApplying=false;
          function clearRowHighlight(){
            document.querySelectorAll('#table-acc .data-row,#table-mat .data-row,#table-all .data-row').forEach(function(row){
              row.classList.remove('mh-row-selected');
              row.style.opacity='';
              row.style.backgroundColor='';
              row.style.color='';
            });
          }
          function bulkInputs(){
            return Array.prototype.slice.call(document.querySelectorAll('input.bulk-edit'));
          }
          function sameBulkGroup(a,b){
            return a && b && a.getAttribute('data-bulk-table')===b.getAttribute('data-bulk-table') &&
              a.getAttribute('data-bulk-field')===b.getAttribute('data-bulk-field');
          }
          function bulkSelectedInputs(){
            return Array.prototype.slice.call(document.querySelectorAll('td.bulk-cell-selected input.bulk-edit'));
          }
          function bulkCommitSig(inp,value){
            return [
              inp.getAttribute('data-bulk-table')||'acc',
              inp.getAttribute('data-bulk-field')||'',
              inp.getAttribute('data-bulk-index')||'-1',
              value
            ].join('|');
          }
          function datePeerInputs(inp){
            var table=inp.getAttribute('data-bulk-table')||'acc';
            var idx=inp.getAttribute('data-bulk-index')||'-1';
            return Array.prototype.slice.call(document.querySelectorAll("input.bulk-edit[data-bulk-field='ngay_dat'][data-bulk-table='"+table+"'][data-bulk-index='"+idx+"']"));
          }
          function syncDateInputs(inp,value){
            datePeerInputs(inp).forEach(function(x){
              x.value=value;
              x.setAttribute('data-committed-sig',bulkCommitSig(x,value));
            });
          }
          function looksCompleteMhDate(value){
            var text=(value||'').toString().trim();
            if(!text)return true;
            if(/^\\d{1,2}[\\/\\-.]\\d{2}$/.test(text))return true;
            if(/^\\d{1,2}[\\/\\-.]\\d{1,2}[\\/\\-.]\\d{2,4}$/.test(text))return true;
            if(/^\\d{4}[\\/\\-.]\\d{1,2}[\\/\\-.]\\d{1,2}$/.test(text))return true;
            if(/^\\d{4}$/.test(text)||/^\\d{6}$/.test(text)||/^\\d{8}$/.test(text))return true;
            return false;
          }
          function scheduleDateCommit(inp){
            if(!inp)return;
            if(!looksCompleteMhDate(inp.value))return;
            clearTimeout(inp._mhDateTimer);
            inp._mhDateTimer=setTimeout(function(){commitBulkInput(inp);},450);
          }
          function setBulkSelection(inputs){
            document.querySelectorAll('td.bulk-cell-selected').forEach(function(td){td.classList.remove('bulk-cell-selected');});
            inputs.forEach(function(inp){
              var td=inp.closest('td');
              if(td)td.classList.add('bulk-cell-selected');
            });
          }
          function selectBulkInput(inp, ev){
            if(!inp)return;
            var fieldInputs=bulkInputs().filter(function(x){return sameBulkGroup(x,inp);});
            var selected=bulkSelectedInputs().filter(function(x){return sameBulkGroup(x,inp);});
            if(ev && ev.shiftKey && bulkAnchorInput && sameBulkGroup(bulkAnchorInput,inp)){
              var a=fieldInputs.indexOf(bulkAnchorInput), b=fieldInputs.indexOf(inp);
              if(a>=0 && b>=0){
                var lo=Math.min(a,b), hi=Math.max(a,b);
                setBulkSelection(fieldInputs.slice(lo,hi+1));
                ev.preventDefault();
              }
              return;
            }
            if(ev && (ev.ctrlKey||ev.metaKey)){
              var pos=selected.indexOf(inp);
              if(pos>=0) selected.splice(pos,1); else selected.push(inp);
              setBulkSelection(selected);
              bulkAnchorInput=inp;
              ev.preventDefault();
              return;
            }
            if(selected.indexOf(inp)>=0 && selected.length>1){
              bulkAnchorInput=inp;
              return;
            }
            setBulkSelection([inp]);
            bulkAnchorInput=inp;
          }
          function applyBulkValue(value, inputs){
            inputs=inputs||bulkSelectedInputs();
            if(inputs.length===0)return false;
            var first=inputs[0];
            var field=first.getAttribute('data-bulk-field')||'';
            if(field==='ngay_dat')value=normalizeMhDate(value);
            var payload=[];
            inputs.forEach(function(inp){
              if(!sameBulkGroup(first,inp))return;
              if(field==='ngay_dat')syncDateInputs(inp,value);
              else{
                inp.value=value;
                inp.setAttribute('data-committed-sig',bulkCommitSig(inp,value));
              }
              payload.push({
                table: inp.getAttribute('data-bulk-table')||'acc',
                field: field,
                idx: parseInt(inp.getAttribute('data-bulk-index')||'-1',10),
                value: value
              });
            });
            if(payload.length===0)return false;
            bulkApplying=true;
            sketchup.bulk_update_cells(JSON.stringify(payload));
            setTimeout(function(){bulkApplying=false;},250);
            return true;
          }
          function handleBulkChange(inp){
            if(bulkApplying)return false;
            if((inp.getAttribute('data-bulk-field')||'')==='ngay_dat')inp.value=normalizeMhDate(inp.value);
            var selected=bulkSelectedInputs().filter(function(x){return sameBulkGroup(x,inp);});
            if(selected.indexOf(inp)<0 || selected.length<=1)return false;
            return applyBulkValue(inp.value, selected);
          }
          function commitBulkInput(inp){
            if(!inp || bulkApplying)return false;
            var table=inp.getAttribute('data-bulk-table')||'acc';
            var field=inp.getAttribute('data-bulk-field')||'';
            var idx=parseInt(inp.getAttribute('data-bulk-index')||'-1',10);
            if(field==='ngay_dat')inp.value=normalizeMhDate(inp.value);
            var selected=bulkSelectedInputs().filter(function(x){return sameBulkGroup(x,inp);});
            if(selected.indexOf(inp)>=0 && selected.length>1)return applyBulkValue(inp.value, selected);
            var sig=bulkCommitSig(inp,inp.value);
            if(inp.getAttribute('data-committed-sig')===sig)return true;
            inp.setAttribute('data-committed-sig',sig);
            if(field==='ngay_dat'){
              syncDateInputs(inp,inp.value);
              if(table==='mat')sketchup.update_mat_ngay_dat(idx,inp.value);
              else sketchup.update_ngay_dat(idx,inp.value);
              return true;
            }
            return false;
          }
          function deleteBulkCells(){
            var selected=bulkSelectedInputs();
            if(selected.length===0){alert('Chưa chọn ô nào.');return;}
            applyBulkValue('', selected);
          }
          document.addEventListener('mousedown',function(e){
            var inp=e.target.closest && e.target.closest('input.bulk-edit');
            if(inp)selectBulkInput(inp,e);
          },true);
          document.addEventListener('input',function(e){
            var inp=e.target.closest && e.target.closest('input.date-edit');
            if(inp)scheduleDateCommit(inp);
          },true);
          document.addEventListener('keyup',function(e){
            var inp=e.target.closest && e.target.closest('input.date-edit');
            if(inp)scheduleDateCommit(inp);
          },true);
          document.addEventListener('change',function(e){
            var inp=e.target.closest && e.target.closest('input.date-edit');
            if(inp)commitBulkInput(inp);
          },true);
          document.addEventListener('blur',function(e){
            var inp=e.target.closest && e.target.closest('input.date-edit');
            if(inp)commitBulkInput(inp);
          },true);
          document.addEventListener('click',function(e){
            var inp=e.target.closest && e.target.closest('input.bulk-edit');
            if(inp){selectBulkInput(inp,e);return;}
            if(!(e.target.closest && e.target.closest('.data-row')) &&
               !(e.target.closest && e.target.closest('button,input,select,textarea,.tab,.col-resizer'))){
              clearRowHighlight();
            }
          },true);
          function getBackImportFields(){
            return ['ngay_dat'];
          }
          function applyBackImportUpdate(scope){
            mhUiDebug('applyBackImportUpdate scope='+scope+' lastRow='+window.MHLastSelectedRow);
            var fields=getBackImportFields();
            var rowIndices=[];
            if(scope==='selected'){
              if(typeof window.MHLastSelectedRow==='number' && window.MHLastSelectedRow>=0){
                rowIndices=[window.MHLastSelectedRow];
              }else{
                mhUiDebug('selected update has no JS row; delegating to Ruby selection');
              }
            }
            var payload={scope:scope,fields:fields,row_indices:rowIndices};
            if(window.sketchup && sketchup.apply_back_import_updates){
              mhUiDebug('calling apply_back_import_updates '+JSON.stringify(payload));
              sketchup.apply_back_import_updates(JSON.stringify(payload));
              return;
            }
            if(window.sketchup && scope==='all' && sketchup.apply_back_import_updates_all){
              mhUiDebug('calling apply_back_import_updates_all');
              sketchup.apply_back_import_updates_all();
              return;
            }
            if(window.sketchup && scope==='selected' && sketchup.apply_back_import_updates_selected){
              mhUiDebug('calling apply_back_import_updates_selected');
              sketchup.apply_back_import_updates_selected();
              return;
            }
            alert('Khong tim thay callback cap nhat. Hay dong/mo lai bang thong ke.');
          }
          function doSelectRow(idx){
            window.MHLastSelectedRow=idx;
            mhUiDebug('select row '+idx);
            sketchup.select_row(idx);
          }
          function doSelectMatRow(idx){
            sketchup.select_mat_row(idx);
          }
          function doSelectProduct(code){sketchup.select_product(code);}
          document.addEventListener('keydown', function(e){
            var tag=e.target.tagName;
            var inDialogControl = tag==='INPUT'||tag==='TEXTAREA'||tag==='SELECT'||tag==='BUTTON'||
              (e.target.closest && e.target.closest('.tab,[contenteditable="true"]'));
            if(inDialogControl){
              var bulkInp=e.target.closest && e.target.closest('input.bulk-edit');
              if(bulkInp && e.keyCode===13){
                e.preventDefault();e.stopPropagation();
                commitBulkInput(bulkInp);
                return;
              }
              return;
            }
            if((e.ctrlKey||e.metaKey) && e.keyCode===90){e.preventDefault();e.stopPropagation();sketchup.undo_last();return;}
            if((e.ctrlKey||e.metaKey) && e.keyCode===77){e.preventDefault();e.stopPropagation();sketchup.open_import_mini();return;}
            if((e.keyCode===46 || e.keyCode===8) && bulkSelectedInputs().length>0){e.preventDefault();e.stopPropagation();deleteBulkCells();return;}
            e.preventDefault();e.stopPropagation();
            sketchup.forward_key(e.keyCode,e.shiftKey?1:0,e.ctrlKey?1:0,e.altKey?1:0);
          },true);
          function addPsu(){
            var w=parseInt(document.getElementById('new_psu_w').value);
            if(!w||w<=0){alert('Nhập công suất hợp lệ!');return;}
            var cur=getPsuList();
            if(cur.indexOf(w)>=0){alert('Nguồn '+w+'W đã có!');return;}
            cur.push(w);sketchup.update_psu_list(cur.join(','));
            document.getElementById('new_psu_w').value='';
          }
          function removePsu(w){
            var cur=getPsuList().filter(function(x){return x!==w;});
            if(cur.length===0){alert('Phải có ít nhất 1 loại nguồn!');return;}
            sketchup.update_psu_list(cur.join(','));
          }
          function getPsuList(){
            var btns=document.querySelectorAll('#psu-table button'),list=[];
            btns.forEach(function(b){var m=b.getAttribute('onclick').match(/removePsu\\((\\d+)\\)/);if(m)list.push(parseInt(m[1]));});
            return list;
          }
          function addFactor(){
            var n=document.getElementById('new_factor_name').value, w=parseFloat(document.getElementById('new_factor_w').value);
            if(!w||w<=0){alert('Nhập định mức hợp lệ!');return;}
            sketchup.add_power_factor(w.toString(),n);
          }
          function initColumnResize(table, fallbackIndex){
            if(!table || table.getAttribute('data-col-resize-ready')==='1')return;
            if(table.getAttribute('data-no-resize')==='1' || (table.closest && table.closest('#mat-completion-summary')))return;
            var ths=Array.prototype.slice.call(table.querySelectorAll('tr:first-child th'));
            if(ths.length===0)return;
            mhUiDebug('initColumnResize table='+(table.id||fallbackIndex)+' ths='+ths.length);
            table.setAttribute('data-col-resize-ready','1');
            table.style.tableLayout='fixed';
            var tableKey=table.id || table.getAttribute('data-col-resize-key') || ('anonymous-table-'+fallbackIndex);
            table.setAttribute('data-col-resize-key',tableKey);
            var storageKey='MHThongkeColumnWidths:'+tableKey;
            var saved={};
            try{saved=JSON.parse(localStorage.getItem(storageKey)||'{}')||{};}catch(e){saved={};}
            function ensureResizeCols(count){
              var cg=table.querySelector('colgroup[data-mh-resize="1"]');
              if(!cg){
                cg=document.createElement('colgroup');
                cg.setAttribute('data-mh-resize','1');
                table.insertBefore(cg,table.firstChild);
              }
              while(cg.children.length<count)cg.appendChild(document.createElement('col'));
              while(cg.children.length>count)cg.removeChild(cg.lastChild);
              return Array.prototype.slice.call(cg.children);
            }
            function sumWidths(widths){
              return widths.reduce(function(total,w){return total+(parseInt(w,10)||0);},0);
            }
            var resizeCols=ensureResizeCols(ths.length);
            var initialWidths=ths.map(function(th,idx){
              return parseInt(saved[idx],10) || parseInt((th.style.width||'').replace('px',''),10) || 0;
            });
            if(initialWidths.some(function(w){return w>0;})){
              var total=0;
              initialWidths.forEach(function(w,idx){
                if(w>0){
                  resizeCols[idx].style.width=w+'px';
                  ths[idx].style.width=w+'px';
                  ths[idx].style.minWidth=w+'px';
                  total+=w;
                }
              });
              if(total>0)table.style.width=(parseInt(saved._tableWidth,10)||total)+'px';
            }else if(saved._tableWidth){
              table.style.width=saved._tableWidth+'px';
            }
            ths.forEach(function(th,idx){
              if(th.querySelector('.col-resizer'))return;
              var grip=document.createElement('span');
              grip.className='col-resizer';
              grip.title='Keo de chinh rong cot';
              th.appendChild(grip);
              function startResize(ev){
                ev.preventDefault();
                ev.stopPropagation();
                var freshThs=Array.prototype.slice.call(table.querySelectorAll('tr:first-child th'));
                var freshCols=ensureResizeCols(freshThs.length);
                var widths=freshThs.map(function(cell,i){
                  return parseInt((freshCols[i].style.width||'').replace('px',''),10) ||
                         cell.offsetWidth ||
                         parseInt((cell.style.width||'').replace('px',''),10) ||
                         60;
                });
                widths.forEach(function(w,i){
                  var cell=freshThs[i];
                  freshCols[i].style.width=w+'px';
                  cell.style.width=w+'px';
                  cell.style.minWidth=w+'px';
                });
                var currentTotal=sumWidths(widths);
                table.style.width=currentTotal+'px';
                var startX=ev.clientX;
                var startW=widths[idx] || th.offsetWidth || 60;
                grip.classList.add('active');
                document.body.style.cursor='col-resize';
                document.body.style.userSelect='none';
                function onMove(moveEv){
                  var nextW=Math.max(35,startW + moveEv.clientX - startX);
                  widths[idx]=nextW;
                  freshCols[idx].style.width=nextW+'px';
                  th.style.width=nextW+'px';
                  th.style.minWidth=nextW+'px';
                  table.style.width=Math.max(120,sumWidths(widths))+'px';
                }
                function onUp(){
                  document.removeEventListener('mousemove',onMove,true);
                  document.removeEventListener('mouseup',onUp,true);
                  grip.classList.remove('active');
                  document.body.style.cursor='';
                  document.body.style.userSelect='';
                  var data={_tableWidth:parseInt(table.style.width,10)||table.offsetWidth||0};
                  freshCols.forEach(function(col,i){
                    data[i]=parseInt((col.style.width||'').replace('px',''),10)||freshThs[i].offsetWidth||60;
                  });
                  try{localStorage.setItem(storageKey,JSON.stringify(data));}catch(e){}
                }
                document.addEventListener('mousemove',onMove,true);
                document.addEventListener('mouseup',onUp,true);
              }
              grip.addEventListener('mousedown',startResize,true);
              // Fallback: kéo ngay trên mép phải của header, kể cả khi khó bắt đúng grip.
              th.addEventListener('mousedown',function(ev){
                var rect=th.getBoundingClientRect();
                if((rect.right - ev.clientX) <= 10){
                  startResize(ev);
                }
              },true);
            });
          }
          function initVisibleColumnResize(){
            var active=document.querySelector('.content[style*="display: block"], .content[style*="display:block"]');
            var scope=active||document;
            var tables=scope.querySelectorAll('table');
            mhUiDebug('initVisibleColumnResize tables='+tables.length);
            tables.forEach(function(table,idx){initColumnResize(table,idx);});
          }
          function initAllColumnResize(){
            initVisibleColumnResize();
          }
          var rubyTab=(window.MHRubyTab||null);
          var storedTab=null;
          try{storedTab=sessionStorage.getItem('lastTabMHThongke');}catch(e){}
          var lt=rubyTab||storedTab||'tab-all';
          try{if(rubyTab)sessionStorage.setItem('lastTabMHThongke',rubyTab);}catch(e){}
          if(lt==='tab-import')lt='tab-files';
          var tabMap={'tab-all':'t7','tab-project-total':'t9','tab-acc':'t1','tab-mat':'t6','tab-import':'t8','tab-settings':'t2','tab-led':'t3','tab-rules':'t5','tab-files':'t8','tab-restore':'t11'};
          if(!tabMap[lt])lt='tab-all';
          installTabHandlers();
          tab(lt, document.getElementById(tabMap[lt]||'t7'), false);
          setTimeout(initVisibleColumnResize,0);
          window.addEventListener('load', function(){ setTimeout(initVisibleColumnResize, 0); }, { once: true });
          mhUiDebug('main dialog html loaded build=20260524-001');

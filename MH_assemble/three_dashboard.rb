# encoding: UTF-8
require 'sketchup.rb'
require 'json'

module MH
  module Assemble
    PLUGIN_NAME = 'MH_assemble'.freeze unless const_defined?(:PLUGIN_NAME)
    VERSION = '0.1.0'.freeze unless const_defined?(:VERSION)
    ROOT = File.dirname(__FILE__).freeze unless const_defined?(:ROOT)

    module_function

    def ensure_assemble
      return true if defined?(MH::Assemble) && MH::Assemble.respond_to?(:scan)

      loader = File.join(Sketchup.find_support_file('Plugins'), 'MH_assemble', 'main.rb')
      load loader if File.exist?(loader)
      defined?(MH::Assemble) && MH::Assemble.respond_to?(:scan)
    rescue StandardError => e
      puts "[#{PLUGIN_NAME}] Không load được MH_assemble: #{e.class}: #{e.message}"
      false
    end

    def dashboard
      html = <<~HTML
        <body style="font-family:Arial,sans-serif;margin:12px;font-size:13px;background:#f7f7f7;color:#222">
          <h3 style="margin:0 0 12px">MH Assemble</h3>
          <label style="display:block;margin-bottom:8px">Tên sản phẩm<br><input id="pname" style="width:100%;height:28px;box-sizing:border-box"></label>
          <button data-act="selection" style="width:100%;background:#2577c9;color:#fff;padding:12px;border:0;border-radius:4px;font-weight:bold">XUẤT THEO SELECTION</button>
          <div style="display:flex;align-items:center;gap:8px;margin-top:10px">
            <label style="flex:1">Profile<br><select id="prof" style="width:100%;height:28px"><option>all</option><option>full</option><option>no_door</option></select></label>
            <button data-act="settings" style="height:28px;margin-top:17px">Cài đặt...</button>
          </div>
          <div id="prog" style="margin-top:12px;display:none">
            <div id="progtxt" style="font-size:11px;margin-bottom:4px;color:#333">…</div>
            <div style="background:#ddd;border:1px solid #aaa;border-radius:5px;overflow:hidden;height:18px;position:relative">
              <div id="progbar" style="height:100%;width:0%;background:#2577c9;transition:width .12s"></div>
              <div id="progpct" style="position:absolute;left:0;right:0;top:0;text-align:center;font-size:11px;line-height:18px;color:#000">0%</div>
            </div>
          </div>
          <script>
            function v(id){ return document.getElementById(id).value; }
            document.querySelectorAll('button[data-act]').forEach(function(b){
              b.onclick = function(){
                sketchup.run(JSON.stringify({act:b.dataset.act, prof:v('prof'), product_name:v('pname')}));
              };
            });
            function mhThreeProgress(pct, done, total, text){
              var p = document.getElementById('prog');
              p.style.display = 'block';
              document.getElementById('progbar').style.width = pct + '%';
              document.getElementById('progpct').textContent = pct + '%';
              document.getElementById('progtxt').textContent = done + '/' + total + ' · ' + text;
              if (pct >= 100) setTimeout(function(){ p.style.display = 'none'; }, 2500);
            }
          </script>
        </body>
      HTML
      dlg = UI::HtmlDialog.new(
        dialog_title: 'MH Assemble',
        preferences_key: 'mh_assemble_panel',
        width: 330,
        height: 255,
        style: UI::HtmlDialog::STYLE_UTILITY
      )
      dlg.set_html(html)
      dlg.add_action_callback('run') { |_, json| dashboard_run(JSON.parse(json)) }
      dlg.show
      @dashboard = dlg
    end

    # Bảng dashboard đang mở (để ThreeExport đẩy tiến độ %). nil nếu chưa mở.
    def panel
      @dashboard
    end

    def dashboard_run(data)
      require_relative 'three_export'
      act = data['act'].to_s
      profile = data['prof'].to_s.strip

      case act
      when 'selection'
        ThreeExport.export_selection(profile: profile, product_name: data['product_name'])
      when 'settings'
        settings_dialog
      end
    rescue StandardError => e
      puts "[#{PLUGIN_NAME}] Lỗi: #{e.class}: #{e.message}"
      puts e.backtrace.first(8).join("\n")
      UI.messagebox("Lỗi MH Assemble: #{e.message}")
    end

    def settings_dialog
      raise 'Không load được MH_assemble.' unless ensure_assemble

      cfg = MH::Assemble.config
      profiles = MH::Assemble.profiles
      scope = cfg['no_door_scope'].is_a?(Hash) ? cfg['no_door_scope'] : {}
      legacy_no_door = Array((profiles['no_door'] || {})['hide'])
      initial = {
        no_door_product: Array(scope['product'] || legacy_no_door),
        no_door_module: Array(scope['module'] || legacy_no_door),
        hide_common: Array(cfg['hide_common']),
        hidden_tags: Array(cfg['hidden_tags']),
        no_number: Array(cfg['no_number']),
        draw_ratio: cfg['draw_ratio'] || 'auto',
        draw_ratios: Array(cfg['draw_ratios'] || [5, 10, 15, 20, 25, 50, 100]),
        sub_modules: Array(cfg['sub_modules'])
      }
      html = <<~HTML
        <body style="font-family:Arial,sans-serif;margin:0;background:#f5f5f5;color:#222;font-size:13px">
          <style>
            .wrap{padding:12px}.sec{background:white;border:1px solid #d0d0d0;border-radius:4px;margin-bottom:10px;padding:9px}
            h4{margin:0 0 4px}.hint{font-size:11px;color:#666;margin-bottom:6px}textarea{width:100%;box-sizing:border-box;font-family:Consolas,monospace;font-size:12px}
            .ratios button{margin:2px;padding:5px 8px}.ratios button.active{background:#2577c9;color:white;border-color:#2577c9}
            .customRatio{display:flex;align-items:center;gap:5px;margin-top:5px}.customRatio input{width:70px;height:24px}
            .presetLine{display:flex;align-items:center;gap:6px;margin-top:7px}.presetLine input{flex:1;height:24px}
            table{width:100%;border-collapse:collapse}td,th{border:1px solid #ccc;padding:4px}td input{width:100%;box-sizing:border-box;border:0;padding:3px}
            .del{width:26px}.save{width:100%;padding:10px;background:#2577c9;color:white;border:0;border-radius:4px;font-weight:bold}
            #status{font-size:12px;color:#187a2f;margin-top:7px;height:16px}
          </style>
          <div class="wrap">
            <div class="sec"><h4>KHÔNG CÁNH - BẢN TỔNG</h4><div class="hint">Ẩn khi xuất trang tổng sản phẩm.</div><textarea id="no_door_product" rows="4"></textarea></div>
            <div class="sec"><h4>KHÔNG CÁNH - BẢN MODULE</h4><div class="hint">Ẩn khi xuất từng module / chi tiết.</div><textarea id="no_door_module" rows="4"></textarea></div>
            <div class="sec"><h4>Chi tiết CẦN ẨN</h4><div class="hint">Ẩn ở mọi bản.</div><textarea id="hide_common" rows="4"></textarea></div>
            <div class="sec"><h4>TAG/LAYER CẦN ẨN</h4><div class="hint">Mỗi dòng 1 tên tag/layer, áp dụng cho bản vẽ HTML.</div><textarea id="hidden_tags" rows="3"></textarea></div>
            <div class="sec"><h4>Chi tiết KHÔNG ĐÁNH SỐ</h4><div class="hint">Vẫn hiện nhưng không có bóng/bảng.</div><textarea id="no_number" rows="4"></textarea></div>
            <div class="sec"><h4>TỈ LỆ bản vẽ</h4><div class="hint">Mặc định cho file HTML xuất sau.</div><div id="ratios" class="ratios"></div><div class="customRatio">1:<input id="custom_ratio" type="number" min="1" max="1000"><button id="custom_btn">Dùng tỉ lệ này</button></div><div class="presetLine"><span>Preset</span><input id="ratio_presets"><button id="apply_presets">Cập nhật nút</button></div></div>
            <div class="sec">
              <h4>MODULE CON</h4><div class="hint">Từ khóa gom + tên hiển thị. Ưu tiên key dài hơn khi trùng.</div>
              <table><thead><tr><th style="width:70px">Bật</th><th>Từ khóa gom</th><th>Tên hiển thị</th><th class="del"></th></tr></thead><tbody id="subbody"></tbody></table>
              <button id="add" style="margin-top:6px">+ Thêm dòng</button>
            </div>
            <button id="save" class="save">Lưu</button>
            <div id="status"></div>
          </div>
          <script>
            const DATA = #{JSON.generate(initial)};
            let ratios = ['auto'].concat((DATA.draw_ratios || [5,10,15,20,25,50,100]).map(String));
            function lines(id, arr){ document.getElementById(id).value = (arr || []).join('\\n'); }
            function splitLines(id){ return document.getElementById(id).value.split('\\n').map(s => s.trim()).filter(Boolean); }
            function parsePresetInput(){
              const seen = {};
              return document.getElementById('ratio_presets').value.split(/[,\s;]+/).map(s => parseInt(s, 10)).filter(function(n){
                if (!(n > 0 && n <= 1000) || seen[n]) return false;
                seen[n] = true;
                return true;
              });
            }
            function renderRatioButtons(){
              const box = document.getElementById('ratios');
              box.innerHTML = '';
              ratios.forEach(function(r){
                const b = document.createElement('button'); b.textContent = r === 'auto' ? 'AUTO' : '1:' + r; b.dataset.ratio = r;
                if (String(DATA.draw_ratio || 'auto') === r) b.className = 'active';
                b.onclick = function(){ document.querySelectorAll('#ratios button').forEach(x => x.classList.remove('active')); b.classList.add('active'); };
                box.appendChild(b);
              });
            }
            lines('no_door_product', DATA.no_door_product); lines('no_door_module', DATA.no_door_module); lines('hide_common', DATA.hide_common); lines('hidden_tags', DATA.hidden_tags); lines('no_number', DATA.no_number);
            document.getElementById('ratio_presets').value = ratios.slice(1).join(', ');
            renderRatioButtons();
            const isPreset = ratios.indexOf(String(DATA.draw_ratio || 'auto')) >= 0;
            if (!isPreset) document.getElementById('custom_ratio').value = parseInt(DATA.draw_ratio, 10) || '';
            document.getElementById('custom_btn').onclick = function(){
              document.querySelectorAll('#ratios button').forEach(x => x.classList.remove('active'));
            };
            document.getElementById('apply_presets').onclick = function(){
              const parsed = parsePresetInput();
              ratios = ['auto'].concat((parsed.length ? parsed : [5,10,15,20,25,50,100]).map(String));
              document.getElementById('ratio_presets').value = ratios.slice(1).join(', ');
              renderRatioButtons();
            };
            function addRow(row){
              row = row || {enabled:true,key:'',label:''};
              const tr = document.createElement('tr');
              tr.innerHTML = '<td style="text-align:center"><input type="checkbox" class="en"></td><td><input class="key"></td><td><input class="label"></td><td><button class="del">x</button></td>';
              tr.querySelector('.en').checked = row.enabled !== false;
              tr.querySelector('.key').value = row.key || '';
              tr.querySelector('.label').value = row.label || '';
              tr.querySelector('.del').onclick = function(){ tr.remove(); };
              document.getElementById('subbody').appendChild(tr);
            }
            (DATA.sub_modules || []).forEach(addRow);
            if (!(DATA.sub_modules || []).length) addRow();
            document.getElementById('add').onclick = function(){ addRow(); };
            document.getElementById('save').onclick = function(){
              const rows = Array.from(document.querySelectorAll('#subbody tr')).map(function(tr){
                return {enabled: tr.querySelector('.en').checked, key: tr.querySelector('.key').value.trim(), label: tr.querySelector('.label').value.trim()};
              }).filter(r => r.key && r.label);
              const active = document.querySelector('#ratios button.active');
              const custom = parseInt(document.getElementById('custom_ratio').value, 10);
              const presetValues = parsePresetInput();
              sketchup.save(JSON.stringify({no_door_product: splitLines('no_door_product'), no_door_module: splitLines('no_door_module'), hide_common: splitLines('hide_common'), hidden_tags: splitLines('hidden_tags'), no_number: splitLines('no_number'), draw_ratio: active ? active.dataset.ratio : (custom > 0 ? String(custom) : 'auto'), draw_ratios: presetValues, sub_modules: rows}));
            };
            function saved(){ document.getElementById('status').textContent = '✓ Đã lưu'; setTimeout(() => document.getElementById('status').textContent = '', 2500); }
          </script>
        </body>
      HTML
       dlg = UI::HtmlDialog.new(dialog_title: 'MH Assemble - Cài đặt',
                                preferences_key: 'mh_assemble_settings',
                               width: 540, height: 820,
                               style: UI::HtmlDialog::STYLE_DIALOG)
      dlg.set_html(html)
      dlg.add_action_callback('save') do |dialog, json|
        data = JSON.parse(json)
        cfg = MH::Assemble.config
        (cfg['profiles'] ||= {})['no_door'] ||= { 'label' => 'Không cánh', 'hide' => [] }
        cfg['profiles']['no_door']['hide'] = Array(data['no_door_module']).map(&:to_s)
        cfg['no_door_scope'] = {
          'product' => Array(data['no_door_product']).map(&:to_s),
          'module' => Array(data['no_door_module']).map(&:to_s)
        }
        cfg['hide_common'] = Array(data['hide_common']).map(&:to_s)
        cfg['hidden_tags'] = Array(data['hidden_tags']).map(&:to_s)
        cfg['no_number'] = Array(data['no_number']).map(&:to_s)
        ratio = data['draw_ratio'].to_s
        cfg['draw_ratio'] = ratio == 'auto' ? 'auto' : ratio.to_i
        ratios = Array(data['draw_ratios']).map(&:to_i).select { |n| n.between?(1, 1000) }.uniq
        cfg['draw_ratios'] = ratios.empty? ? [5, 10, 15, 20, 25, 50, 100] : ratios
        cfg['sub_modules'] = Array(data['sub_modules']).map do |row|
          next unless row.is_a?(Hash)
          key = row['key'].to_s.strip
          label = row['label'].to_s.strip
          next if key.empty? || label.empty?
          { 'key' => key, 'label' => label, 'enabled' => row.key?('enabled') ? !!row['enabled'] : true }
        end.compact
        MH::Assemble.save_config
        dialog.execute_script('saved()')
      rescue StandardError => e
        dialog.execute_script("document.getElementById('status').textContent = #{("Lỗi: #{e.message}").to_json}")
      end
      dlg.show
      @settings = dlg
    end

    unless file_loaded?(__FILE__)
      menu = UI.menu('Plugins').add_submenu('MH Assemble')
      menu.add_item('Mở bảng điều khiển') { dashboard }
      file_loaded(__FILE__)
    end
  end
end


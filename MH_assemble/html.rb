# encoding: UTF-8
#
# MH_assemble — Phase 4: ráp HTML trang A3 -> in PDF.

require 'base64'

module MH
  module Assemble
    module_function

    # ===== Bảng điều khiển 1-cửa (thay cho nhiều menu) =====
    def dashboard
      html = <<~HTML
        <body style="font-family:sans-serif;margin:10px;font-size:13px">
          <div style="display:flex;gap:8px;flex-wrap:wrap;align-items:flex-end;margin-bottom:8px">
            <label>Mã tủ<br><input id="prod" value="SP47" style="width:90px"></label>
            <label>Module<br><input id="mod" value="06" style="width:60px"></label>
            <label>Profile<br><select id="prof"><option>all</option><option>full</option><option>no_door</option></select></label>
          </div>
          <label style="display:block;margin-bottom:8px">Danh sách tủ (cách nhau dấu phẩy)<br><input id="list" placeholder="SP47, SP48, SP50" style="width:100%"></label>
          <div style="display:grid;grid-template-columns:1fr 1fr;gap:6px">
            <button data-act="scan">Scan (báo cây)</button>
            <button data-act="mini">Mini-map preview</button>
            <button data-act="aim_p">Ngắm tủ (isolate)</button>
            <button data-act="aim_m">Ngắm module (isolate)</button>
            <button data-act="uniso" style="grid-column:1/3">Hiện lại tất cả (bỏ isolate)</button>
            <button data-act="render_p">Render tủ (PNG)</button>
            <button data-act="render_m">Render module (PNG)</button>
            <button data-act="page_p">Trang A3 tủ</button>
            <button data-act="page_m">Trang A3 module</button>
            <button data-act="book" style="grid-column:1/3;background:#2a7;color:#fff;padding:9px;font-weight:bold">Trang A3 CẢ TỦ (book)</button>
            <button data-act="sel" style="grid-column:1/3;background:#27a;color:#fff;padding:8px;font-weight:bold">Xuất theo SELECTION (đang chọn)</button>
            <button data-act="list" style="grid-column:1/3">Xuất theo DANH SÁCH tủ</button>
            <button data-act="all">Xuất TẤT CẢ tủ</button>
            <button data-act="cancel" style="background:#a33;color:#fff">Hủy</button>
            <button data-act="settings" style="grid-column:1/3">Settings…</button>
          </div>
          <fieldset style="margin-top:10px;border:1px solid #ccc;border-radius:6px;padding:8px">
            <legend style="font-size:12px;color:#555">Góc camera riêng (theo Mã tủ · Module · Profile ở trên)</legend>
            <p style="margin:0 0 6px;font-size:11px;color:#777">Bỏ trống Module = áp cho trang tủ tổng quan. Profile = all sẽ áp cho cả Full &amp; Không cánh.</p>
            <div style="display:flex;gap:6px;align-items:flex-end;margin-bottom:6px">
              <label style="flex:1">Preset hướng<br>
                <select id="preset" style="width:100%">
                  <option value="iso_pt">Iso phải-trước</option>
                  <option value="iso_tt">Iso trái-trước</option>
                  <option value="iso_ps">Iso phải-sau</option>
                  <option value="iso_ts">Iso trái-sau</option>
                  <option value="front">Chính diện (trước)</option>
                  <option value="back">Sau</option>
                  <option value="left">Trái</option>
                  <option value="right">Phải</option>
                  <option value="top">Từ trên</option>
                </select>
              </label>
              <button data-act="cam_preset">Áp preset</button>
            </div>
            <div style="display:grid;grid-template-columns:1fr 1fr;gap:6px">
              <button data-act="cam_grab" style="background:#555;color:#fff;grid-column:1/3">📷 Chụp GÓC HIỆN TẠI → lưu cho module</button>
              <button data-act="cam_clear" style="grid-column:1/3">↺ Về góc mặc định</button>
            </div>
          </fieldset>
          <div id="prog" style="margin-top:12px;display:none">
            <div id="progtxt" style="font-size:11px;margin-bottom:4px;color:#333">…</div>
            <div style="background:#ddd;border:1px solid #aaa;border-radius:5px;overflow:hidden;height:18px;position:relative">
              <div id="progbar" style="height:100%;width:0%;background:#2a7;transition:width .12s"></div>
              <div id="progpct" style="position:absolute;left:0;right:0;top:0;text-align:center;font-size:11px;line-height:18px;color:#000">0%</div>
            </div>
          </div>
          <script>
            function v(id){ var e=document.getElementById(id); return e?e.value:''; }
            document.querySelectorAll('button[data-act]').forEach(function(b){
              b.onclick=function(){ sketchup.run(JSON.stringify({act:b.dataset.act, prod:v('prod'), mod:v('mod'), prof:v('prof'), list:v('list'), preset:v('preset')})); };
            });
            function mhProgress(pct, done, total, text){
              document.getElementById('prog').style.display='block';
              document.getElementById('progbar').style.width=pct+'%';
              document.getElementById('progpct').textContent=pct+'%';
              document.getElementById('progtxt').textContent=done+'/'+total+' · '+text;
            }
          </script>
        </body>
      HTML
      dlg = UI::HtmlDialog.new(dialog_title: 'MH Assemble', preferences_key: 'mh_assemble_panel',
                               width: 360, height: 560, style: UI::HtmlDialog::STYLE_UTILITY)
      dlg.set_html(html)
      dlg.add_action_callback('run') { |_, json| dashboard_run(JSON.parse(json)) }
      dlg.show
      @panel = dlg
    end

    def dashboard_run(a)
      act = a['act'].to_s
      scan_reset unless act == 'cancel'   # quét lại model 1 lần cho thao tác này (cache dùng lại bên trong)
      prod, mod = normalize_target_inputs(a['prod'], a['mod'])
      prof = a['prof'].to_s
      single    = (prof.empty? || prof == 'all') ? 'full' : prof # hàm 1 profile
      book_prof = (prof.empty? || prof == 'all') ? nil : prof     # book/all: nil = cả 2
      folder = "file:///#{out_dir.tr('\\\\', '/')}"
      case act
      when 'scan'      then report
      when 'mini'      then minimap_preview(prod, mod)
      when 'aim_p'     then frame_selection
      when 'aim_m'     then frame_selection
      when 'render_p'  then (render_product(prod, profile: single) && UI.openURL(folder))
      when 'render_m'  then (render_module(prod, mod, profile: single) && UI.openURL(folder))
      when 'page_p'    then export_product_page(prod, profile: book_prof)
      when 'page_m'    then export_module(prod, mod, profile: book_prof)
      when 'book'      then export_book(prod, profile: book_prof)
      when 'sel'       then export_selection(profile: book_prof)
      when 'list'      then export_list(a['list'], profile: book_prof)
      when 'uniso'     then unisolate
      when 'cam_grab'  then cam_capture(prod, mod, prof)
      when 'cam_preset' then cam_apply_preset(prod, mod, prof, a['preset'])
      when 'cam_clear' then cam_clear_override(prod, mod, prof)
      when 'all'       then export_all(profile: book_prof)
      when 'all_async' then export_all_async(profile: book_prof)
      when 'cancel'    then cancel_export
      when 'settings'  then settings_dialog
      end
    rescue StandardError => e
      UI.messagebox("Lỗi: #{e.message}")
    end

    # ---- Góc camera riêng cho (module × profile) -------------------------
    CAM_PRESETS = {
      'iso_pt' => [1, -1, 0.8],  'iso_tt' => [-1, -1, 0.8],
      'iso_ps' => [1,  1, 0.8],  'iso_ts' => [-1,  1, 0.8],
      'front'  => [0, -1, 0],    'back'   => [0,  1, 0],
      'left'   => [-1, 0, 0],    'right'  => [1,  0, 0],
      'top'    => [0,  0, 1]
    } unless const_defined?(:CAM_PRESETS)

    def resolve_cam_profiles(prof)
      (prof.nil? || prof.to_s.strip.empty? || prof == 'all') ? %w[full no_door] : [prof.to_s]
    end

    def normalize_target_inputs(prod, mod)
      p = prod.to_s.strip.upcase
      m = mod.to_s.strip
      if m.empty? && (mm = p.match(/\A(?:SP)?(\d+)\.(\d+)\z/i))
        p = "SP#{mm[1].to_i}"
        m = format('%02d', mm[2].to_i)
      elsif p =~ /\A\d+\z/
        p = "SP#{p.to_i}"
      elsif (mm = p.match(/\A([A-Z]+)(\d+)\z/))
        p = "#{mm[1]}#{mm[2].to_i}"
      end
      m = format('%02d', m.to_i) if m =~ /\A\d+\z/
      [p, m]
    end

    # Mã đích để lưu góc: module -> "SP47.06"; bỏ trống module -> cả tủ "SP47".
    def cam_target_code(prod, mod)
      p, label = normalize_target_inputs(prod, mod)
      return p if label.to_s.empty?
      "#{p}.#{label}"
    end

    # Chụp góc nhìn HIỆN TẠI của SketchUp -> lưu cho (mã × profile).
    def cam_capture(prod, mod, prof)
      code = cam_target_code(prod, mod)
      return UI.messagebox('Chưa nhập Mã tủ.') if code.to_s.empty?
      c = view.camera
      d = c.eye - c.target            # hướng từ tâm ra mắt = hướng nhìn
      return UI.messagebox('Camera không hợp lệ.') if d.length < 1e-6
      d.normalize!
      profs = resolve_cam_profiles(prof)
      profs.each { |pf| set_camera_override(code, pf, d.x, d.y, d.z) }
      UI.messagebox("Đã lưu GÓC HIỆN TẠI cho #{code}\nProfile: #{profs.join(', ')}\nHướng = (#{d.x.round(3)}, #{d.y.round(3)}, #{d.z.round(3)})")
    end

    # Áp 1 preset hướng cho (mã × profile).
    def cam_apply_preset(prod, mod, prof, preset)
      vec = CAM_PRESETS[preset.to_s]
      return UI.messagebox("Preset không hợp lệ: #{preset}") unless vec
      code = cam_target_code(prod, mod)
      profs = resolve_cam_profiles(prof)
      profs.each { |pf| set_camera_override(code, pf, vec[0], vec[1], vec[2]) }
      # ngắm thử luôn nếu đang có gì để xem
      UI.messagebox("Đã đặt preset '#{preset}' cho #{code}\nProfile: #{profs.join(', ')}")
    end

    # Xoá override -> trở lại góc mặc định.
    def cam_clear_override(prod, mod, prof)
      code = cam_target_code(prod, mod)
      profs = resolve_cam_profiles(prof)
      profs.each { |pf| clear_camera_override(code, pf) }
      UI.messagebox("Đã trả #{code} (#{profs.join(', ')}) về GÓC MẶC ĐỊNH.")
    end

    def data_uri(path)
      return '' unless path && File.exist?(path)
      "data:image/png;base64,#{Base64.strict_encode64(File.binread(path))}"
    end

    # CSS + JS dùng chung cho trang A3.
    def page_assets
      <<~CSS
        <style>
          @page { size: A3 landscape; margin: 0; }
          * { box-sizing: border-box; }
          html,body { margin:0; padding:0; font-family: Arial, sans-serif; background:#e8e8e8;
                      -webkit-print-color-adjust: exact; print-color-adjust: exact; }
          .page { width: 420mm; height: 297mm; padding: 10mm; page-break-after: always;  /* khung thụt vào 10mm mỗi bên */
                  margin: 12px auto; background:#fff; box-shadow:0 0 8px rgba(0,0,0,.35); }
          @media screen { body { padding-right: 200px; } }   /* chừa chỗ cho bảng điều khiển bên phải */
          @media print { html,body { background:#fff; padding:0; } .page { margin:0; box-shadow:none; } }
          /* 1 khung ngoài; trong chia: thân (ảnh | phải) + thanh khung tên ngang dưới */
          .sheet { width:100%; height:100%; border:2px solid #000; display:flex; flex-direction:column; }
          .body { flex:1; display:flex; min-height:0; }
          .left { flex:1; display:flex; align-items:center; justify-content:center; position:relative; overflow:hidden; }
          .frame { position:relative; overflow:visible; }
          .frame img { width:100%; height:100%; display:block; }
          .frame svg { position:absolute; left:0; top:0; width:100%; height:100%; overflow:visible; }
          .right { width:116mm; display:flex; flex-direction:column; min-height:0; }   /* rộng hơn ~1.2x -> mini to hơn, không cắt góc */
          .mini { width:100%; }                          /* mini-map: bỏ khung, fit theo width */
          .mini img { width:100%; height:auto; display:block; }
          .tbl { margin-top:auto; overflow:hidden; }     /* bảng dồn xuống ĐÁY phải */
          .tbl .cap { font-weight:bold; padding:3px 6px; background:#eee; font-size:10pt; }
          table { width:100%; border-collapse:collapse; font-size:8.5pt; }
          th,td { border:1px solid #444; padding:2px 5px; text-align:left; }
          th { background:#f0f0f0; }
          td.c { text-align:center; }
          /* khung tên: 3 ô NGANG, sát đáy, full width, thấp */
          .title { height:13mm; border-top:2px solid #000; display:flex; }
          .title .cell { flex:1; border-right:1px solid #000; padding:1px 10px; display:flex; flex-direction:column; justify-content:center; }
          .title .cell:last-child { border-right:none; }
          .title .lb { font-size:7.5pt; color:#555; }
          .title .vl { font-size:11pt; font-weight:bold; line-height:1.1; }
          /* bảng điều khiển: cố định BÊN PHẢI, đi theo khi cuộn trang; ẩn khi in */
          .controls { position:fixed; top:14px; right:14px; width:170px; z-index:60;
                      background:#222; color:#fff; padding:12px; font-size:12px; border-radius:8px;
                      display:flex; flex-direction:column; gap:10px; box-shadow:0 2px 10px rgba(0,0,0,.4); }
          .controls input[type=range] { width:100%; }
          .controls button { padding:4px 8px; }
          .controls .grp { display:flex; gap:6px; }
          @media print { .controls { display:none !important; } }
        </style>
      CSS
    end

    def controls_bar
      <<~H
        <div class="controls">
          <b>MH Assemble</b>
          <span id="curpage" style="font-size:11px;color:#9cf">Trang đang chỉnh: —</span>
          <label>Sắp xếp số (trang này):<br>
            <select id="arrmode" style="width:100%">
              <option value="edge">Hai cột rìa — ít cắt nhất</option>
              <option value="declutter">Gần part (không đè)</option>
              <option value="ring">Đều quanh ảnh</option>
            </select>
          </label>
          <label>Độ dài leader (trang này):<br><input type="range" id="leadlen" min="0" max="120" value="#{lead_pct}"></label>
          <label>Giãn dòng (trang này):<br><input type="range" id="linespace" min="0" max="320" value="#{line_pct}"></label>
          <button id="resetballoons">Reset số (trang này)</button>
          <div>Zoom (trang này):</div>
          <div class="grp"><button id="zoomout">−</button><button id="zoomreset">115%</button><button id="zoomin">+</button></div>
          <button id="printbtn" style="background:#2a7;color:#fff;border:none;padding:7px;font-weight:bold">In PDF</button>
          <span style="font-size:11px;color:#bbb">Kéo số để chỉnh tay · lăn chuột để zoom · In PDF: chọn A3 Ngang, lề None, bật Background graphics</span>
        </div>
      H
    end

    def balloon_js
      <<~JS
        <script>
        var MH = { frames: [], defFactor: #{lead_pct / 100.0}, defLine: #{line_pct / 100.0}, defaultZoom: 1.15, drag: null, active: null };

        function mhBuild(stage){
          var data = JSON.parse(stage.getAttribute('data-balloons'));
          var rawObs = stage.getAttribute('data-obstacles') || '[]';
          var obsData = JSON.parse(rawObs);
          var imgW = +stage.getAttribute('data-w'), imgH = +stage.getAttribute('data-h');
          var panel = stage.parentNode, pw = panel.clientWidth, ph = panel.clientHeight, M = 0.80;
          var ar = imgW/imgH, w = pw*M, h = w/ar;
          if (h > ph*M) { h = ph*M; w = h*ar; }
          stage.style.width = w+'px'; stage.style.height = h+'px';
          stage.style.transformOrigin = 'center center';
          var sc = w/imgW;
          var items = data.map(function(b){
            var box = b.box ? { x1:b.box.x1*sc, y1:b.box.y1*sc, x2:b.box.x2*sc, y2:b.box.y2*sc } : null;
            var poly = b.poly ? b.poly.map(function(p){ return [p[0]*sc, p[1]*sc]; }) : null;
            return {id:b.id, ax:b.x*sc, ay:b.y*sc, box:box, poly:poly, x:0, y:0, moved:false};
          });
          var obstacles = obsData.map(function(b){ return { x1:b.x1*sc, y1:b.y1*sc, x2:b.x2*sc, y2:b.y2*sc }; });
          var svg = stage.querySelector('svg'); svg.setAttribute('viewBox','0 0 '+w+' '+h);
          var st = { svg:svg, frame:stage, w:w, h:h, cx:w/2, cy:h/2, r:22, items:items, obstacles:obstacles, zoom:MH.defaultZoom, factor:MH.defFactor, lineFactor:MH.defLine, mode:'edge', idx:MH.frames.length };
          MH.frames.push(st);
          mhLayout(st);
          mhApplyZoom(st);
          svg.addEventListener('mousedown', function(e){
            var i = e.target.getAttribute('data-i'); if (i===null) return;
            MH.drag = { st: st, i: +i }; e.preventDefault();
          });
          panel.addEventListener('mouseenter', function(){ mhSetActive(st); });
          panel.addEventListener('wheel', function(e){            // ZOOM theo TỪNG trang
            e.preventDefault(); MH.active = st;
            st.zoom *= (e.deltaY < 0 ? 1.1 : 0.9);
            st.zoom = Math.max(0.3, Math.min(6, st.zoom)); mhApplyZoom(st);
          }, { passive:false });
        }

        function mhApplyZoom(st){ st.frame.style.transform = 'scale('+st.zoom+')'; }
        function mhZoom(f){ var st = MH.active || MH.frames[0]; if (!st) return;
          st.zoom = (f === 0) ? MH.defaultZoom : Math.max(0.3, Math.min(6, st.zoom*f)); mhApplyZoom(st); }
        // đổi trang đang chỉnh -> đồng bộ slider + nhãn
        function mhSetActive(st){
          MH.active = st;
          var sl = document.getElementById('leadlen'); if (sl) sl.value = Math.round(st.factor*100);
          var am = document.getElementById('arrmode'); if (am) am.value = st.mode;
          var ls = document.getElementById('linespace'); if (ls) ls.value = Math.round((st.lineFactor||1)*100);
          var cp = document.getElementById('curpage'); if (cp) cp.textContent = 'Trang đang chỉnh: #' + (st.idx+1);
        }

        // Chọn chế độ sắp xếp theo từng trang (st.mode). 'ring' = đều quanh ảnh; 'declutter' = gần part, không đè.
        // Đếm tổng số cặp leader cắt nhau.
        function mhCountCross(st){
          var it = st.items, c = 0;
          for (var i=0;i<it.length;i++){
            var L = mhLeaderEnds(it[i], st, it[i].k);
            for (var j=i+1;j<it.length;j++){
              var M = mhLeaderEnds(it[j], st, it[j].k);
              if (mhSegCross({x:L.x1,y:L.y1},{x:L.x2,y:L.y2},{x:M.x1,y:M.y1},{x:M.x2,y:M.y2})) c++;
            }
          }
          return c;
        }

        function mhTotalLen(st){
          var it = st.items, s = 0;
          for (var i=0;i<it.length;i++){ var L = mhLeaderEnds(it[i], st, it[i].k); s += Math.hypot(L.x2-L.x1, L.y2-L.y1); }
          return s;
        }
        // chi phí: số chéo nặng nhất + tổng dài leader (để gỡ chéo và làm gọn).
        function mhCost(st){ return mhCountCross(st)*100000 + mhTotalLen(st); }

        // 2-opt TOÀN CỤC: thử hoán đổi MỌI cặp bóng, giữ nếu chi phí giảm. (bỏ qua bóng kéo tay)
        function mhUncross(st){
          var it = st.items;
          for (var pass=0; pass<14; pass++){
            var improved = false, before0 = mhCost(st);
            for (var i=0;i<it.length;i++) for (var j=i+1;j<it.length;j++){
              var A = it[i], B = it[j];
              if (A.moved || B.moved) continue;
              var before = mhCost(st);
              var ax=A.x, ay=A.y;
              A.x=B.x; A.y=B.y; B.x=ax; B.y=ay;
              if (mhCost(st) < before - 0.5){ improved = true; }
              else { B.x=A.x; B.y=A.y; A.x=ax; A.y=ay; }
            }
            if (!improved || mhCost(st) >= before0 - 0.5) break;
          }
        }

        // MỘT CỘT mỗi bên (trái/phải), trong frame; khoảng cách dòng = (2r+gap)*lineFactor (slider Giãn dòng).
        // Vị trí cột (độ dài leader) theo st.factor (slider Độ dài leader).
        function mhLayoutEdge(st){
          var r = st.r, gap = 8, maxF = 1.2;
          var lf = (st.lineFactor != null) ? st.lineFactor : 1;
          var step  = (2*r + gap) * lf;                       // 0 -> dồn 1 hàng; lớn -> giãn ra
          var edge = r + 6, fac = Math.min(maxF, (st.factor != null) ? st.factor : 0.58); // nhận đúng 0
          var inset = edge + (1 - fac/maxF) * (st.w/2 - edge); // factor=0 -> GIỮA; factor max -> ra rìa (leader dài)
          var left = [], right = [];
          st.items.forEach(function(o){ if (o.moved) return; (o.ax < st.cx ? left : right).push(o); });
          function placeSide(arr, x){
            if (!arr.length) return;
            arr.sort(function(a,b){ return a.ay - b.ay; });
            var n = arr.length, startY = st.cy - (n-1)*step/2;
            arr.forEach(function(o,i){ o.x = x; o.y = startY + i*step; });
          }
          if (st.w - 2*inset < 2*r + 4){          // 2 cột chạm nhau -> GỘP 1 cột ở giữa
            placeSide(left.concat(right), st.w/2);
          } else {
            placeSide(left, inset);
            placeSide(right, st.w - inset);
          }
        }

        function mhLayout(st){
          if (st.items.length === 0){ st.svg.innerHTML = ''; return; }
          if (st.mode === 'declutter') mhLayoutDeclutter(st);
          else if (st.mode === 'edge') mhLayoutEdge(st);
          else mhLayoutRing(st);
          mhUncross(st);     // gỡ leader cắt nhau bằng hoán đổi vị trí bóng (mọi chế độ)
          mhOptimizeK(st);   // chọn độ cắm sâu K từng leader để giảm cắt id / cắt nhau
          mhRender(st);
        }

        // CŨ: rải đều quanh ảnh (ellipse), thứ tự theo góc anchor.
        function mhLayoutRing(st){
          var f = st.factor, n = st.items.length;
          st.items.forEach(function(o){ o.ang = Math.atan2(o.ay-st.cy, o.ax-st.cx); });
          var order = st.items.map(function(o,i){ return i; }).sort(function(a,b){ return st.items[a].ang-st.items[b].ang; });
          var start = st.items[order[0]].ang, Rx = st.w*f, Ry = st.h*f;
          order.forEach(function(ii,k){
            var o = st.items[ii]; if (o.moved) return;
            var ang = start + k*(2*Math.PI/n);
            o.x = st.cx + Rx*Math.cos(ang); o.y = st.cy + Ry*Math.sin(ang);
          });
        }

        function mhClamp(o, st){
          var m = st.r + 4;
          o.x = Math.max(m, Math.min(st.w-m, o.x));
          o.y = Math.max(m, Math.min(st.h-m, o.y));
        }

        function mhSegDistPoint(ax,ay,bx,by,px,py){
          var vx=bx-ax, vy=by-ay, wx=px-ax, wy=py-ay, l2=vx*vx+vy*vy;
          var t = l2 ? Math.max(0, Math.min(1, (wx*vx+wy*vy)/l2)) : 0;
          var x=ax+vx*t, y=ay+vy*t;
          return Math.hypot(px-x, py-y);
        }

        function mhSegCross(a,b,c,d){
          function ccw(p,q,r){ return (r.y-p.y)*(q.x-p.x) > (q.y-p.y)*(r.x-p.x); }
          return (ccw(a,c,d) !== ccw(b,c,d)) && (ccw(a,b,c) !== ccw(a,b,d));
        }

        function mhExpandedBox(box, pad){
          if (!box) return null;
          return { x1:box.x1-pad, y1:box.y1-pad, x2:box.x2+pad, y2:box.y2+pad };
        }

        function mhCircleHitsBox(x, y, r, box){
          if (!box) return false;
          var qx = Math.max(box.x1, Math.min(x, box.x2));
          var qy = Math.max(box.y1, Math.min(y, box.y2));
          return Math.hypot(x-qx, y-qy) < r;
        }

        // Giao điểm 2 đoạn; trả {x,y,t} (t dọc đoạn 1) nếu cắt.
        function mhSegInter(x1,y1,x2,y2, x3,y3,x4,y4){
          var d=(x2-x1)*(y4-y3)-(y2-y1)*(x4-x3);
          if (Math.abs(d) < 1e-9) return null;
          var t=((x3-x1)*(y4-y3)-(y3-y1)*(x4-x3))/d;
          var u=((x3-x1)*(y2-y1)-(y3-y1)*(x2-x1))/d;
          if (t>=0 && t<=1 && u>=0 && u<=1) return { x:x1+t*(x2-x1), y:y1+t*(y2-y1), t:t };
          return null;
        }

        // Điểm leader CHẠM part: cắt đoạn (bóng -> tâm part) với BAO LỒI (hull); lùi vào trong theo K (0=viền,1=tâm).
        function mhBoxTouchPoint(o, k){
          if (k === undefined) k = (o.k !== undefined ? o.k : 0.4);
          var poly = o.poly;
          if (poly && poly.length >= 2){
            var best = null;
            for (var i=0;i<poly.length;i++){
              var a = poly[i], b = poly[(i+1)%poly.length];
              var hit = mhSegInter(o.x,o.y, o.ax,o.ay, a[0],a[1], b[0],b[1]);
              if (hit && (!best || hit.t < best.t)) best = hit;
            }
            if (best){ return { x: best.x + (o.ax-best.x)*k, y: best.y + (o.ay-best.y)*k }; }
            return { x:o.ax, y:o.ay };
          }
          if (!o.box) return { x:o.ax, y:o.ay };
          return { x: Math.max(o.box.x1, Math.min(o.ax, o.box.x2)),
                   y: Math.max(o.box.y1, Math.min(o.ay, o.box.y2)) };
        }

        // Leader có CHÂN NGANG: số -(chân ngang)-> footEnd -(đoạn nghiêng)-> chạm part.
        // fsx,fsy = đầu chân (cạnh số); x1,y1 = cuối chân (= đầu đoạn nghiêng); x2,y2 = điểm chạm part.
        function mhLeaderEnds(o, st, k){
          var touch = mhBoxTouchPoint(o, k);
          var dirX = (touch.x >= o.x) ? 1 : -1;
          var gap = 10, foot = 16;
          return { fsx:o.x + dirX*gap, fsy:o.y, x1:o.x + dirX*(gap+foot), y1:o.y, x2:touch.x, y2:touch.y };
        }

        // Tối ưu K từng leader: chọn độ cắm sâu để leader ÍT cắt qua id & ÍT cắt leader khác nhất.
        function mhOptimizeK(st){
          var KS = [0.12, 0.28, 0.44, 0.6, 0.76, 0.9], r = st.r;
          st.items.forEach(function(o){ if (o.k === undefined) o.k = 0.44; });
          for (var pass=0; pass<2; pass++){
            st.items.forEach(function(o){
              var bestK = o.k, bestScore = Infinity;
              KS.forEach(function(k){
                var L = mhLeaderEnds(o, st, k), sc = 0;
                st.items.forEach(function(p){
                  if (p === o) return;
                  if (mhSegDistPoint(L.x1,L.y1,L.x2,L.y2, p.x,p.y) < r+4) sc += 100;        // leader cắt qua id
                  var P = mhLeaderEnds(p, st, p.k);
                  if (mhSegCross({x:L.x1,y:L.y1},{x:L.x2,y:L.y2},{x:P.x1,y:P.y1},{x:P.x2,y:P.y2})) sc += 12; // leader chéo
                });
                sc += k * 0.4;   // hoà nhau -> ưu tiên nông hơn
                if (sc < bestScore){ bestScore = sc; bestK = k; }
              });
              o.k = bestK;
            });
          }
        }

        function mhCandidateScore(c, o, placed, st){
          var score = Math.hypot(c.x-o.ax, c.y-o.ay);
          if (c.x < st.r || c.x > st.w-st.r || c.y < st.r || c.y > st.h-st.r) score += 5000;
          if (mhCircleHitsBox(c.x, c.y, st.r + 6, mhExpandedBox(o.box, 3))) score += 50000;
          st.obstacles.forEach(function(box){
            if (mhCircleHitsBox(c.x, c.y, st.r + 5, mhExpandedBox(box, 2))) score += 22000;
          });
          var vx = o.ax-st.cx, vy = o.ay-st.cy, vl = Math.hypot(vx,vy)||1;
          var ux = vx/vl, uy = vy/vl, ox = c.x-o.ax, oy = c.y-o.ay;
          var outward = ox*ux + oy*uy;
          var minOut = Math.min(st.w, st.h) * 0.16;
          if (outward < minOut) score += (minOut-outward) * 80;
          score += Math.abs((ox*uy) - (oy*ux)) * 0.75;
          var probe = { x:c.x, y:c.y, ax:o.ax, ay:o.ay };
          var L = mhLeaderEnds(probe, st);
          placed.forEach(function(p){
            var d = Math.hypot(c.x-p.x, c.y-p.y);
            var min = st.r*2 + 8;
            if (d < min) score += 9000 + (min-d)*120;
            if (mhSegDistPoint(L.x1,L.y1,L.x2,L.y2,p.x,p.y) < st.r+5) score += 6500;
            var P = mhLeaderEnds(p, st);
            if (mhSegCross({x:L.x1,y:L.y1},{x:L.x2,y:L.y2},{x:P.x1,y:P.y1},{x:P.x2,y:P.y2})) score += 2800;
            if (mhCircleHitsBox(c.x, c.y, st.r + 4, mhExpandedBox(p.box, 2))) score += 16000;
          });
          score += Math.abs(c.x-st.cx)*0.015 + Math.abs(c.y-st.cy)*0.015;
          return score;
        }

        // Đặt ID gần part: thử nhiều ứng viên gần anchor, phạt mạnh nếu đè ID hoặc leader cắt qua nhau.
        function mhLayoutDeclutter(st){
          var r = st.r, base = Math.max(r*2.8, Math.min(st.w, st.h) * st.factor * 0.42);
          var order = st.items.map(function(o,i){ return i; }).sort(function(a,b){
            var A=st.items[a], B=st.items[b];
            return Math.hypot(A.ax-st.cx,A.ay-st.cy) - Math.hypot(B.ax-st.cx,B.ay-st.cy);
          });
          var placed = st.items.filter(function(o){ return o.moved; });
          order.forEach(function(ii){
            var o = st.items[ii]; if (o.moved) return;
            var dx = o.ax-st.cx, dy = o.ay-st.cy, a0 = Math.atan2(dy,dx);
            var angles = [0, -0.32, 0.32, -0.65, 0.65, -1.05, 1.05, -1.45, 1.45];
            var radii = [base, base*1.22, base*1.5, base*1.85, base*2.25];
            var best = null, bestScore = Infinity;
            radii.forEach(function(rad){
              angles.forEach(function(da){
                var a = a0 + da, c = { x:o.ax + Math.cos(a)*rad, y:o.ay + Math.sin(a)*rad };
                mhClamp(c, st);
                var sc = mhCandidateScore(c, o, placed, st);
                if (sc < bestScore){ bestScore = sc; best = c; }
              });
            });
            o.x = best.x; o.y = best.y; mhClamp(o, st); placed.push(o);
          });
          var it = st.items, n = it.length, min = 2*r + 8;
          for (var k=0;k<220;k++){
            var any = false;
            for (var a=0;a<n;a++) for (var b=a+1;b<n;b++){
              var A=it[a], B=it[b], dx=B.x-A.x, dy=B.y-A.y, d=Math.hypot(dx,dy)||0.01;
              if (d < min){
                var p=(min-d)/2, ux=dx/d, uy=dy/d;
                if (!A.moved){ A.x-=ux*p; A.y-=uy*p; }
                if (!B.moved){ B.x+=ux*p; B.y+=uy*p; }
                mhClamp(A, st); mhClamp(B, st);
                any = true;
              }
            }
            if (!any) break;
          }
        }

        function mhRender(st){
          var r = st.r, FONT = 13, s = '';   // cỡ chữ CỐ ĐỊNH, không theo bán kính
          st.items.forEach(function(o,i){
            var L = mhLeaderEnds(o, st);
            s += '<line x1="'+L.fsx+'" y1="'+L.fsy+'" x2="'+L.x1+'" y2="'+L.y1+'" stroke="#000" stroke-width="0.8"/>'; // chân ngang
            s += '<line x1="'+L.x1+'" y1="'+L.y1+'" x2="'+L.x2+'" y2="'+L.y2+'" stroke="#000" stroke-width="0.8"/>'; // đoạn nghiêng
            s += '<circle cx="'+L.x2+'" cy="'+L.y2+'" r="2.2" fill="#000"/>';
            // CHỈ GIỮ SỐ: không viền, không nền. Vòng tròn trong suốt chỉ để bắt kéo chuột.
            s += '<circle cx="'+o.x+'" cy="'+o.y+'" r="'+r+'" fill="#fff" fill-opacity="0" data-i="'+i+'" style="cursor:move"/>';
            s += '<text x="'+o.x+'" y="'+o.y+'" text-anchor="middle" dominant-baseline="central" font-size="'+FONT+'" font-weight="bold" font-family="Arial" data-i="'+i+'" style="cursor:move">'+o.id+'</text>';
          });
          st.svg.innerHTML = s;
        }

        function mhPt(st, e){
          var rc = st.svg.getBoundingClientRect();
          return { x:(e.clientX-rc.left)*(st.w/rc.width), y:(e.clientY-rc.top)*(st.h/rc.height) };
        }

        document.addEventListener('mousemove', function(e){
          if (!MH.drag) return;
          var st = MH.drag.st, o = st.items[MH.drag.i], p = mhPt(st, e);
          o.x = p.x; o.y = p.y; o.moved = true; mhRender(st);
        });
        document.addEventListener('mouseup', function(){
          if (MH.drag){ var st = MH.drag.st; MH.drag = null; mhUncross(st); mhOptimizeK(st); mhRender(st); }
        });

        window.addEventListener('load', function(){
          document.querySelectorAll('.frame').forEach(mhBuild);
          if (MH.frames[0]) mhSetActive(MH.frames[0]);
          var sl = document.getElementById('leadlen');
          if (sl){ sl.addEventListener('input', function(){ var st = MH.active || MH.frames[0]; if (!st) return; st.factor = (+sl.value)/100; mhLayout(st); }); }
          var am = document.getElementById('arrmode');
          if (am){ am.addEventListener('change', function(){ var st = MH.active || MH.frames[0]; if (!st) return; st.mode = am.value; mhLayout(st); }); }
          var ls = document.getElementById('linespace');
          if (ls){ ls.addEventListener('input', function(){ var st = MH.active || MH.frames[0]; if (!st) return; st.lineFactor = (+ls.value)/100; mhLayout(st); }); }
          var rs = document.getElementById('resetballoons');
          if (rs){ rs.addEventListener('click', function(){ var st = MH.active || MH.frames[0]; if (!st) return; st.items.forEach(function(o){o.moved=false;}); mhLayout(st); }); }
          var zi = document.getElementById('zoomin'), zo = document.getElementById('zoomout'), zr = document.getElementById('zoomreset');
          if (zi){ zi.addEventListener('click', function(){ mhZoom(1.2); }); }
          if (zo){ zo.addEventListener('click', function(){ mhZoom(1/1.2); }); }
          if (zr){ zr.addEventListener('click', function(){ mhZoom(0); }); }
          var pb = document.getElementById('printbtn');
          if (pb){ pb.addEventListener('click', function(){ window.print(); }); }
        });
        window.addEventListener('beforeprint', function(){ MH.frames.forEach(function(st){ st.zoom=MH.defaultZoom; mhApplyZoom(st); }); }); // in mặc định 115%
        </script>
      JS
    end

    # Mã hiển thị: tủ không module (label "00") -> chỉ mã tủ; có module -> SPxx.yy.
    def mcode(product, label)
      label.to_s == '00' ? product : "#{product}.#{label}"
    end

    # Tên SP cho khung tên; profile khác 'full' thì gắn thêm nhãn (vd " - Không cánh").
    def product_label(product, prof)
      nm = product_name(product)
      prof.to_s == 'full' ? nm : "#{nm} - #{profile(prof)['label']}"
    end

    def title_block_html(project, product_name, code)
      <<~H
        <div class="title">
          <div class="cell"><div class="lb">Tên công trình</div><div class="vl">#{project}</div></div>
          <div class="cell"><div class="lb">Tên sản phẩm</div><div class="vl">#{product_name}</div></div>
          <div class="cell"><div class="lb">Mã sản phẩm</div><div class="vl">#{code}</div></div>
        </div>
      H
    end

    def table_html(rows, caption)
      body = rows.map do |r|
        "<tr><td class=\"c\">#{r['id']}</td><td>#{r['name']}</td><td class=\"c\">#{r['qty']}</td><td>#{r['material']}</td></tr>"
      end.join
      <<~H
        <div class="tbl">
          <div class="cap">#{caption}</div>
          <table>
            <tr><th style="width:34px">ID</th><th>Tên</th><th style="width:30px">SL</th><th>Material</th></tr>
            #{body}
          </table>
        </div>
      H
    end

    # Bảng trang TỔNG QUAN: Mã | Module | Số part (không cột Material).
    def overview_table_html(rows, caption)
      body = rows.map do |r|
        "<tr><td class=\"c\">#{r['id']}</td><td>#{r['name']}</td><td class=\"c\">#{r['qty']}</td></tr>"
      end.join
      <<~H
        <div class="tbl">
          <div class="cap">#{caption}</div>
          <table>
            <tr><th style="width:40px">Mã</th><th>Module</th><th style="width:60px">Số part</th></tr>
            #{body}
          </table>
        </div>
      H
    end

    # 1 trang A3 cho 1 module. Trả chuỗi HTML (1 .page).
    def module_page(product, label, main_data, main_png, mini)
      ptitle = project_title
      pname  = product_label(product, main_data['profile'])
      main_uri = data_uri(main_png)
      mini_html = if mini && mini['base']
        b = data_uri(File.join(out_dir, mini['base']))
        o = mini['overlay'] ? data_uri(File.join(out_dir, mini['overlay'])) : ''
        # ĐỎ ở DƯỚI; tủ trắng-đen đè trên + mix-blend multiply -> mặt trắng thành trong suốt (đỏ hiện qua), nét đen trên cùng
        "<div class=\"mini\" style=\"position:relative;background:#fff\">" \
          "<img src=\"#{o}\" style=\"position:absolute;left:0;top:0;width:100%\">" \
          "<img src=\"#{b}\" style=\"position:relative;width:100%;display:block;mix-blend-mode:multiply\">" \
        "</div>"
      else
        '<div class="mini"></div>'
      end
      balloons_json = main_data['balloons'].to_json.gsub('"', '&quot;')
      obstacles_json = Array(main_data['obstacles']).to_json.gsub('"', '&quot;')
      <<~H
        <div class="page">
          <div class="sheet">
            <div class="body">
              <div class="left">
                <div class="frame" data-balloons="#{balloons_json}" data-obstacles="#{obstacles_json}" data-w="#{main_data['image']['w']}" data-h="#{main_data['image']['h']}">
                  <img src="#{main_uri}">
                  <svg></svg>
                </div>
              </div>
              <div class="right">
                #{mini_html}
                #{table_html(main_data['table'], "Module #{mcode(product, label)}")}
              </div>
            </div>
            #{title_block_html(ptitle, pname, mcode(product, label))}
          </div>
        </div>
      H
    end

    # Trang TỦ tổng quan (bóng = module). Không có mini-map (chính nó là cả tủ).
    def product_page(product, data, png)
      ptitle = project_title
      pname  = product_label(product, data['profile'])
      uri = data_uri(png)
      balloons_json = data['balloons'].to_json.gsub('"', '&quot;')
      obstacles_json = Array(data['obstacles']).to_json.gsub('"', '&quot;')
      <<~H
        <div class="page">
          <div class="sheet">
            <div class="body">
              <div class="left">
                <div class="frame" data-balloons="#{balloons_json}" data-obstacles="#{obstacles_json}" data-w="#{data['image']['w']}" data-h="#{data['image']['h']}">
                  <img src="#{uri}">
                  <svg></svg>
                </div>
              </div>
              <div class="right">
                #{overview_table_html(data['table'], "Tủ #{product} — #{data['table'].size} module")}
              </div>
            </div>
            #{title_block_html(ptitle, pname, product)}
          </div>
        </div>
      H
    end

    # Trang sản phẩm part-level: dùng cho tủ không chia module hoặc selection label 00.
    def product_parts_page(product, data, caption = nil)
      ptitle = project_title
      pname  = product_label(product, data['profile'])
      uri = data_uri(File.join(out_dir, data['image']['file']))
      balloons_json = data['balloons'].to_json.gsub('"', '&quot;')
      obstacles_json = Array(data['obstacles']).to_json.gsub('"', '&quot;')
      <<~H
        <div class="page">
          <div class="sheet">
            <div class="body">
              <div class="left">
                <div class="frame" data-balloons="#{balloons_json}" data-obstacles="#{obstacles_json}" data-w="#{data['image']['w']}" data-h="#{data['image']['h']}">
                  <img src="#{uri}">
                  <svg></svg>
                </div>
              </div>
              <div class="right">
                #{table_html(data['table'], caption || "Tủ #{product}")}
              </div>
            </div>
            #{title_block_html(ptitle, pname, product)}
          </div>
        </div>
      H
    end

    # Trang TỦ tổng quan cho SELECTION: gộp tất cả part đã chọn của tủ, bóng = từng part,
    # bảng = ID|Tên|SL|Material (part-level), KHÔNG mini-map.
    def sel_product_page(product, data)
      product_parts_page(product, data, "Tủ #{product} (đã chọn)")
    end

    # Xuất trang TỦ tổng quan (theo profile; all -> full + no_door). Có thanh %.
    def export_product_page(product, profile: nil)
      return puts("[#{PLUGIN_NAME}] không có tủ #{product}") unless scan[product]
      tasks = resolve_profiles(profile).map do |prof|
        ["Tổng quan #{product} [#{prof}]", lambda {
          data = render_product_overview(product, profile: prof)
          data ? product_page(product, data, File.join(out_dir, data['image']['file'])) : ''
        }]
      end
      run_task_queue(tasks, "#{product}.overview.html", product)
    end

    # Xuất trang module (theo profile; all -> full + no_door nếu có cánh). Có thanh %.
    def export_module(product, mod, profile: nil)
      label = (mod.to_s =~ /\A\d+\z/) ? format('%02d', mod.to_i) : mod.to_s
      tree  = scan
      mods  = tree[product]
      return puts("[#{PLUGIN_NAME}] không có tủ #{product}/module #{label}") unless mods && mods[label]
      all_solids = mods.values.flatten.reject { |p| p[:flat] }
      mini_ref = []
      tasks = module_profiles(mods[label], resolve_profiles(profile)).map do |prof|
        ["Module #{mcode(product, label)} [#{prof}]", lambda {
          mini_ref[0] ||= render_minimap_module(product, label, all_solids, mods)
          data = render_module(product, label, profile: prof)
          data ? module_page(product, label, data, File.join(out_dir, data['image']['file']), mini_ref[0]) : ''
        }]
      end
      run_task_queue(tasks, "#{product}.#{label}.page.html", "#{product}.#{label}")
    end

    def resolve_profiles(profile)
      list = (profile.nil? || profile.to_s.strip.empty? || profile == 'all') ? %w[full no_door] : [profile]
      list.select { |p| profiles.key?(p) }
    end

    # Profile áp cho 1 module: nếu module KHÔNG có cánh (no_door không ẩn gì) -> bỏ bản no_door.
    def module_profiles(parts, profs)
      return profs unless profs.include?('no_door')
      no_door_hides = visible_parts(parts, 'full').size != visible_parts(parts, 'no_door').size
      no_door_hides ? profs : (profs - ['no_door'])
    end

    def wrap_html(pages, title)
      "<!doctype html><html><head><meta charset=\"utf-8\"><title>#{title}</title>" \
        "#{page_assets}#{balloon_js}</head><body>#{controls_bar}#{pages}</body></html>"
    end

    # Tạo chuỗi HTML các trang của 1 tủ. only_labels (mảng nhãn) -> chỉ những module đó.
    def build_product_pages(product, profs, tree = nil, only_labels: nil)
      tree ||= scan
      mods = tree[product]
      return '' unless mods
      all_solids = mods.values.flatten.reject { |p| p[:flat] }
      pages = ''
      profs.each do |prof|
        ov = render_product_overview(product, profile: prof)
        pages << product_page(product, ov, File.join(out_dir, ov['image']['file'])) if ov
      end
      labels = mods.keys.sort
      labels = labels.select { |l| only_labels.include?(l) } if only_labels
      labels.each do |label|
        mini = render_minimap_module(product, label, all_solids, mods)
        module_profiles(mods[label], profs).each do |prof|
          data = render_module(product, label, profile: prof)
          next unless data
          pages << module_page(product, label, data, File.join(out_dir, data['image']['file']), mini)
        end
      end
      pages
    end

    # {product => [labels] hoặc :all} từ SketchUp selection.
    # Nhận cả PART (parse_full) lẫn GROUP CONTAINER tên "SP47" / "SP47.06".
    CONTAINER_RE = /\A[\s_]*([A-Za-z]{1,4})(\d+)(?:\.(\d+))?[\s_]*\z/ unless const_defined?(:CONTAINER_RE)

    def selection_targets
      model = Sketchup.active_model
      found = {}
      add = lambda do |prod, label|
        return if prod.to_s.empty?
        if label.nil?
          found[prod] = :all
        elsif found[prod] != :all
          (found[prod] ||= [])
          found[prod] << label unless found[prod].include?(label)
        end
      end
      walker = nil
      walker = lambda do |ents|
        ents.each do |e|
          next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          nm = name_of(e)
          info = MH::ProductContext.parse_full(nm)
          if info
            add.call(info[:product], info[:modul_label])
          elsif (m = nm.match(CONTAINER_RE))
            prod = "#{m[1].upcase}#{m[2].to_i}"
            add.call(prod, m[3] ? format('%02d', m[3].to_i) : nil)
          end
          ch = e.is_a?(Sketchup::Group) ? e.entities : (e.respond_to?(:definition) && e.definition ? e.definition.entities : nil)
          walker.call(ch) if ch
        end
      end
      walker.call(model.selection.to_a)
      found
    end

    # EntityID gốc trong vùng chọn. Khi lọc part, xét cả entity part lẫn path tổ tiên.
    def selected_ids
      ids = {}
      Sketchup.active_model.selection.to_a.each do |e|
        id = (e.entityID rescue nil)
        ids[id] = true if id
      end
      ids
    end

    def selected_part?(part, selected)
      ent = part[:entity]
      eid = (ent.entityID rescue nil)
      return true if eid && selected[eid]
      Array(part[:path]).any? do |a|
        aid = (a.entityID rescue nil)
        aid && selected[aid]
      end
    end

    # Xuất theo SELECTION: coi phần được chọn là một sản phẩm đầy đủ riêng.
    def export_selection(profile: nil)
      sids = selected_ids
      return puts("[#{PLUGIN_NAME}] chưa chọn gì") if sids.empty?
      tree = scan
      groups = {}
      tree.each do |prod, mods|
        mods.each do |label, parts|
          sub = parts.select { |p| p[:entity] && (p[:entity].valid? rescue false) && selected_part?(p, sids) }
          groups[[prod, label]] = sub unless sub.empty?
        end
      end
      return puts("[#{PLUGIN_NAME}] selection không có part SPxx nào") if groups.empty?
      profs = resolve_profiles(profile)

      # Gom lại theo TỦ: prod => { label => subset_parts }
      by_prod = {}
      groups.each do |(prod, label), sub|
        (by_prod[prod] ||= {})[label] = sub
      end

      tasks = []
      by_prod.keys.sort.each do |prod|
        labmap = by_prod[prod]
        mods_hash = tree[prod]
        # toàn bộ part ĐÃ CHỌN của tủ này (nền mini-map + ảnh tổng quan)
        sel_parts_prod = labmap.values.flatten
        sel_solids_prod = sel_parts_prod.reject { |p| p[:flat] }
        next if sel_solids_prod.empty?
        labels = labmap.keys.sort
        sel_profs = module_profiles(sel_parts_prod, profs)

        if labels == ['00']
          sel_profs.each do |prof|
            tasks << ["Tủ #{prod} (đã chọn) [#{prof}] (#{sel_solids_prod.size} part)", lambda {
              data = render_core(sel_solids_prod, visible_parts(sel_parts_prod, prof), listed_parts(sel_parts_prod, prof),
                                 "#{prod}.sel.product.#{prof}",
                                 { 'product' => prod, 'profile' => prof }, render_width)
              data ? sel_product_page(prod, data) : ''
            }]
          end
          next
        end

        # 1) TRANG TỦ TỔNG QUAN — selection luôn được coi như một sản phẩm đầy đủ.
        sel_profs.each do |prof|
          tasks << ["Tổng quan #{prod} (đã chọn) [#{prof}] (#{sel_solids_prod.size} part)", lambda {
            data = render_product_overview_from(prod, labmap, profile: prof, width: render_width,
                                                basename: "#{prod}.sel.overview.#{prof}")
            data ? product_page(prod, data, File.join(out_dir, data['image']['file'])) : ''
          }]
        end

        # 2) TRANG TỪNG MODULE — mini-map: nền = part đã chọn của tủ, đỏ = part đã chọn của module
        labels.each do |label|
          subset = labmap[label]
          sub_solids = subset.reject { |p| p[:flat] }
          next if sub_solids.empty?
          module_profiles(subset, profs).each do |prof|
            tasks << ["Module #{mcode(prod, label)} (đã chọn) [#{prof}] (#{sub_solids.size} part)", lambda {
              data = render_core(sub_solids, visible_parts(subset, prof), listed_parts(subset, prof),
                                 "#{prod}.#{label}.sel.#{prof}",
                                 { 'product' => prod, 'module' => label, 'profile' => prof }, render_width)
              next '' unless data
              mini = render_minimap_module(prod, label, [], mods_hash,
                                           highlight: sub_solids, over_tag: "#{label}.sel.#{prof}",
                                           base_parts: sel_solids_prod, base_tag: "sel.#{prod}")
              module_page(prod, label, data, File.join(out_dir, data['image']['file']), mini)
            }]
          end
        end
      end
      return puts("[#{PLUGIN_NAME}] selection rỗng sau lọc") if tasks.empty?
      run_task_queue(tasks, 'SELECTION.book.html', "Selection (#{by_prod.size} tủ)")
    end

    # Xuất theo DANH SÁCH tủ (chuỗi 'SP47, SP48 SP50') (có tiến độ).
    def export_list(list_str, profile: nil)
      tree = scan
      codes = list_str.to_s.split(/[,;\s]+/).map { |s| s.strip.upcase }.reject(&:empty?).select { |c| tree[c] }
      return puts("[#{PLUGIN_NAME}] danh sách không có tủ hợp lệ") if codes.empty?
      profs = resolve_profiles(profile)
      tasks = codes.flat_map { |c| product_tasks(c, profs, tree) }
      run_task_queue(tasks, 'LIST.book.html', "Danh sách: #{codes.join(', ')}")
    end

    # Gộp 1 tủ -> 1 file A3 (chạy nhịp, có tiến độ). profile=nil/'all' -> cả full + no_door.
    def export_book(product, profile: nil)
      tree = scan
      return puts("[#{PLUGIN_NAME}] không có tủ #{product}") unless tree[product]
      run_task_queue(product_tasks(product, resolve_profiles(profile), tree), "#{product}.book.html", product)
    end
    def export_book_async(product, profile: nil); export_book(product, profile: profile); end

    # ---- Hạ tầng chạy theo NHỊP (timer) -> không treo, có tiến độ, hủy được ----
    @export_cancel = false
    class ExportCancelled < StandardError; end unless const_defined?(:ExportCancelled)

    def export_cancelled?
      !!@export_cancel
    end

    def abort_export_if_cancelled
      raise ExportCancelled, 'Đã hủy xuất' if export_cancelled?
    end

    def cancel_export
      @export_cancel = true
      report_progress(0, 1, 'Đang hủy sau bước render hiện tại...')
      puts "[#{PLUGIN_NAME}] đã yêu cầu hủy xuất."
    end

    # Danh sách "việc" [mô_tả, proc] cho 1 tủ. only_labels -> chỉ những module đó.
    def product_tasks(product, profs, tree, only_labels: nil)
      mods = tree[product]
      return [] unless mods
      all_solids = mods.values.flatten.reject { |p| p[:flat] }
      tasks = []
      labels = mods.keys.sort
      no_modules = (labels == ['00'])   # tủ đặt part trực tiếp (không có module)
      if no_modules
        module_profiles(mods['00'], profs).each do |prof|
          tasks << ["Tủ #{product} [#{prof}]", lambda {
            abort_export_if_cancelled
            data = render_core(all_solids, visible_parts(all_solids, prof), listed_parts(all_solids, prof),
                               "#{product}.#{prof}",
                               { 'product' => product, 'profile' => prof }, render_width)
            abort_export_if_cancelled
            data ? product_parts_page(product, data) : ''
          }]
        end
        return tasks
      end
      unless no_modules
        profs.each do |prof|
          tasks << ["Tổng quan #{product} [#{prof}]", lambda {
            ov = render_product_overview(product, profile: prof)
            ov ? product_page(product, ov, File.join(out_dir, ov['image']['file'])) : ''
          }]
        end
      end
      labels = labels.select { |l| only_labels.include?(l) } if only_labels
      labels.each do |label|
        mprofs = module_profiles(mods[label], profs)
        mini_ref = []
        mprofs.each do |prof|
          tasks << ["Module #{product}.#{label} [#{prof}]", lambda {
            abort_export_if_cancelled
            mini_ref[0] ||= render_minimap_module(product, label, all_solids, mods)
            abort_export_if_cancelled
            data = render_module(product, label, profile: prof)
            abort_export_if_cancelled
            data ? module_page(product, label, data, File.join(out_dir, data['image']['file']), mini_ref[0]) : ''
          }]
        end
      end
      tasks
    end

    def save_camera
      c = view.camera
      [c.eye, c.target, c.up, c.perspective?, (c.perspective? ? c.fov : c.height)]
    end

    def restore_camera(s)
      return unless s
      c = view.camera
      c.perspective = s[3]
      c.set(s[0], s[1], s[2])
      begin; s[3] ? (c.fov = s[4]) : (c.height = s[4]); rescue StandardError; end
      view.invalidate
    end

    # Đẩy tiến độ ra bảng điều khiển (nếu đang mở) + status bar.
    def report_progress(done, total, text)
      pct = total > 0 ? (done * 100 / total) : 100
      Sketchup.status_text = "MH Assemble #{done}/#{total} (#{pct}%): #{text}"
      return unless @panel
      begin
        @panel.execute_script("mhProgress(#{pct}, #{done}, #{total}, #{text.to_json})")
      rescue StandardError
        nil
      end
    end

    # Chạy hàng đợi [mô_tả, proc] theo nhịp timer; có tiến độ %; KHÔNG bao giờ chết chuỗi (mọi lỗi -> bỏ qua, chạy tiếp).
    def run_task_queue(tasks, filename, title)
      @export_cancel = false
      cam = save_camera
      pages = +''
      total = tasks.size
      i = 0
      step = nil
      finalize = lambda {
        begin
          restore_camera(cam)
          if @export_cancel
            pages.clear
            report_progress(i, total, "ĐÃ HỦY")
            puts "[#{PLUGIN_NAME}] HỦY #{i}/#{total} -> không ghi file dở"
          else
            File.write(File.join(out_dir, filename), wrap_html(pages, title))
            report_progress(i, total, "Hoàn tất -> #{filename}")
            puts "[#{PLUGIN_NAME}] XONG #{i}/#{total} -> #{filename}"
            UI.openURL("file:///#{File.join(out_dir, filename).tr('\\\\', '/')}")
          end
        rescue StandardError => e
          puts "[#{PLUGIN_NAME}] finalize lỗi: #{e.class}: #{e.message}"
        end
      }
      step = lambda {
        if @export_cancel || i >= total
          finalize.call
          next
        end
        begin
          desc, proc = tasks[i]
          report_progress(i, total, desc)
          puts "[#{PLUGIN_NAME}] (#{i + 1}/#{total}) #{desc}"
          pages << proc.call.to_s
        rescue ExportCancelled
          @export_cancel = true
          puts "[#{PLUGIN_NAME}] task #{i} đã hủy."
        rescue StandardError => e
          puts "[#{PLUGIN_NAME}] task #{i} lỗi: #{e.class}: #{e.message}"
        end
        i += 1
        UI.start_timer(0.05, false) { step.call }   # luôn lên lịch bước tiếp -> không treo
      }
      report_progress(0, total, 'Bắt đầu…')
      UI.start_timer(0.05, false) { step.call }
      puts "[#{PLUGIN_NAME}] xuất #{total} việc… (log từng bước ở Console)"
      nil
    end

    # Xuất TẤT CẢ tủ (chạy nhịp, có tiến độ).
    def export_all(profile: nil)
      tree = scan
      prods = tree.keys.sort
      return puts("[#{PLUGIN_NAME}] không tìm thấy tủ nào") if prods.empty?
      profs = resolve_profiles(profile)
      tasks = prods.flat_map { |p| product_tasks(p, profs, tree) }
      run_task_queue(tasks, 'ALL.book.html', "Toàn bộ #{prods.size} tủ")
    end
    def export_all_async(profile: nil); export_all(profile: profile); end

    # Preview mini-map: ảnh cả tủ, module đã được TÔ ĐỎ (shaded). Ghi HTML + mở.
    def minimap_preview(product, mod)
      label = (mod.to_s =~ /\A\d+\z/) ? format('%02d', mod.to_i) : mod.to_s
      tree  = scan
      mods  = tree[product]
      return puts("[#{PLUGIN_NAME}] không có tủ #{product}") unless mods
      all_solids = mods.values.flatten.reject { |p| p[:flat] }
      mini = render_minimap_module(product, label, all_solids, mods)
      return puts("[#{PLUGIN_NAME}] không tạo được mini-map module #{label}") unless mini

      html = <<~HTML
        <!doctype html><html><head><meta charset="utf-8">
        <title>Mini-map #{product}.#{label}</title></head>
        <body style="margin:16px;font-family:sans-serif">
          <h3 style="margin:0 0 8px">Mini-map #{product} — module #{label} (đỏ đè trên nền)</h3>
          <div style="position:relative;display:inline-block;border:1px solid #ccc;background:#fff">
            <img src="#{mini['overlay']}" style="position:absolute;left:0;top:0">
            <img src="#{mini['base']}" style="display:block;mix-blend-mode:multiply">
          </div>
        </body></html>
      HTML

      path = File.join(out_dir, "#{product}.mini.#{label}.preview.html")
      File.write(path, html)
      UI.openURL("file:///#{path.tr('\\\\', '/')}")
      puts "[#{PLUGIN_NAME}] mini preview -> #{path}"
      path
    end
  end
end

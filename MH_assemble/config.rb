# encoding: UTF-8
#
# MH_assemble — Config: View Profiles (sửa được, lưu JSON).
#   profile.hide = danh sách "từ khoá" tên part bị ẩn (khớp CHỨA-CHUỖI, không phân biệt hoa/thường).
#   vd hide "Cánh" sẽ ẩn: Cánh Trái/Phải/Trên/Dưới/Lật + Viền Cánh ...
#
# Luật chung mọi profile:
#   HIỆN          = (không phẳng) & (tên part KHÔNG chứa từ khoá nào trong hide)
#   ĐÁNH SỐ+LIỆT KÊ = phần hiện & có id (numbered)
#   Phụ kiện không-id: hiện, không số, không liệt kê.

require 'json'

module MH
  module Assemble
    CONFIG_PATH = File.join(ROOT, 'config.json') unless const_defined?(:CONFIG_PATH)

    @config = nil   # reset memo mỗi lần load (tránh dùng config cũ thiếu key mới)

    DEFAULT_PROFILES = {
      'full'    => { 'label' => 'Full',       'hide' => [] },
      'no_door' => { 'label' => 'Không cánh',
                     'hide' => ['Cánh Trái', 'Cánh Phải', 'Cánh Trên', 'Cánh Dưới',
                                'Cánh Lật', 'Viền Cánh', 'Pano Cánh', 'Mặt NK'] } # khớp CHÍNH XÁC
    } unless const_defined?(:DEFAULT_PROFILES)

    module_function

    def config
      @config ||= load_config
    end

    def load_config
      data = {}
      if File.exist?(CONFIG_PATH)
        begin
          data = JSON.parse(File.read(CONFIG_PATH))
        rescue StandardError => e
          puts "[#{PLUGIN_NAME}] load_config lỗi: #{e.message}"
        end
      end
      profiles = {}
      DEFAULT_PROFILES.each { |k, v| profiles[k] = { 'label' => v['label'], 'hide' => v['hide'].dup } }
      (data['profiles'] || {}).each do |k, v|
        profiles[k] = { 'label' => (v['label'] || k).to_s, 'hide' => Array(v['hide']).map(&:to_s) }
      end
      tb = { 'project' => '[TÊN CÔNG TRÌNH]', 'product' => '[TÊN SẢN PHẨM]' }
      (data['title_block'] || {}).each { |k, v| tb[k] = v.to_s }
      # Nhãn/tag LUÔN ẩn trong mọi bản vẽ (khớp theo tên entity HOẶC tên tag/layer, chứa-chuỗi).
      hide_always = data.key?('hide_always') ? Array(data['hide_always']).map(&:to_s) : ['ABF_label']
      # Map mã tủ -> Tên sản phẩm (điền khung tên). Sửa trong config.json.
      pnames = {}
      (data['product_names'] || {}).each { |k, v| pnames[k.to_s.upcase] = v.to_s }
      # Độ phân giải render: THẤP hơn -> nét ĐẬM hơn (sửa trong config.json / Settings).
      render_w = (data['render_w'] || 1200).to_i
      mini_w   = (data['mini_w']   || 700).to_i
      # Độ mờ LỚP NỀN tủ trong mini-map (0..255). THẤP -> nền mờ, module đỏ nổi (cảm giác nằm trong).
      mini_alpha = (data['mini_alpha'] || 110).to_i
      # Part HIỆN trong ảnh nhưng KHÔNG đánh số / KHÔNG vào bảng (khớp CHÍNH XÁC tên).
      no_number = Array(data['no_number'] || []).map(&:to_s)
      # Ẩn ở MỌI bản (full + no_door + ...), khớp chính xác — vd "Đánh Dấu Ray Trái".
      hide_common = Array(data['hide_common'] || []).map(&:to_s)
      hidden_tags = Array(data['hidden_tags'] || []).map(&:to_s)
      # Mặc định cho slider trên trang (%): độ dài leader, giãn dòng.
      lead_pct = (data['lead_pct'] || 58).to_i
      line_pct = (data['line_pct'] || 100).to_i
      draw_ratio = data.key?('draw_ratio') ? data['draw_ratio'] : 'auto'
      draw_ratio = 'auto' unless draw_ratio.to_s == 'auto' || draw_ratio.to_i.between?(1, 1000)
      draw_ratios = Array(data['draw_ratios'] || [5, 10, 15, 20, 25, 50, 100]).map(&:to_i).select { |n| n.between?(1, 1000) }.uniq
      draw_ratios = [5, 10, 15, 20, 25, 50, 100] if draw_ratios.empty?
      sub_modules = Array(data['sub_modules']).map do |row|
        next unless row.is_a?(Hash)
        key = row['key'].to_s.strip
        label = row['label'].to_s.strip
        next if key.empty? || label.empty?
        { 'key' => key, 'label' => label, 'enabled' => row.key?('enabled') ? !!row['enabled'] : true }
      end.compact
      no_door_scope = data['no_door_scope'].is_a?(Hash) ? data['no_door_scope'] : {}
      legacy_no_door = profiles.dig('no_door', 'hide') || DEFAULT_PROFILES['no_door']['hide']
      no_door_scope = {
        'product' => Array(no_door_scope.key?('product') ? no_door_scope['product'] : legacy_no_door).map(&:to_s),
        'module' => Array(no_door_scope.key?('module') ? no_door_scope['module'] : legacy_no_door).map(&:to_s)
      }
      main_back_edges = data.key?('main_back_edges') ? !!data['main_back_edges'] : false
      camera_iso = data['camera_iso'].is_a?(Hash) ? data['camera_iso'] : {}
      camera_iso = {
        'x' => (camera_iso['x'] || 0.27).to_f,
        'y' => (camera_iso['y'] || -1.16).to_f,
        'z' => (camera_iso['z'] || 0.35).to_f
      }
      # Góc camera RIÊNG theo (module × profile). Key = "<mã>|<profile>" vd "SP47.06|full".
      # Giá trị = {x,y,z} = hướng nhìn (eye - target). Không có -> dùng góc mặc định.
      overrides = data['camera_overrides'].is_a?(Hash) ? data['camera_overrides'] : {}
      { 'profiles' => profiles, 'title_block' => tb, 'hide_always' => hide_always,
        'product_names' => pnames, 'render_w' => render_w, 'mini_w' => mini_w,
        'mini_alpha' => mini_alpha, 'no_number' => no_number, 'hide_common' => hide_common, 'hidden_tags' => hidden_tags,
        'lead_pct' => lead_pct, 'line_pct' => line_pct, 'main_back_edges' => main_back_edges,
        'draw_ratio' => draw_ratio, 'draw_ratios' => draw_ratios, 'sub_modules' => sub_modules, 'no_door_scope' => no_door_scope,
        'camera_iso' => camera_iso, 'camera_overrides' => overrides }
    end

    # ---- Góc camera riêng theo (module × profile) -------------------------
    def camera_overrides
      config['camera_overrides'] ||= {}
    end

    def normalize_cam_code(code)
      s = code.to_s.strip.upcase
      s = "SP#{s}" if s =~ /\A\d+(?:\.\d+)?\z/
      if (m = s.match(/\A([A-Z]+)(\d+)(?:\.(\d+))?\z/))
        base = "#{m[1]}#{m[2].to_i}"
        m[3] ? "#{base}.#{format('%02d', m[3].to_i)}" : base
      else
        s
      end
    end

    def cam_key(code, profile)
      "#{normalize_cam_code(code)}|#{profile}"
    end

    # Trả {x,y,z} hoặc nil.
    def camera_override(code, profile)
      key = cam_key(code, profile)
      ov = camera_overrides[key]
      unless ov
        legacy = "#{code}|#{profile}"
        ov = camera_overrides[legacy]
        camera_overrides[key] = ov if ov
      end
      ov.is_a?(Hash) ? ov : nil
    end

    def set_camera_override(code, profile, x, y, z)
      camera_overrides[cam_key(code, profile)] = { 'x' => x.to_f, 'y' => y.to_f, 'z' => z.to_f }
      save_config
      camera_overrides[cam_key(code, profile)]
    end

    def clear_camera_override(code, profile)
      camera_overrides.delete(cam_key(code, profile))
      save_config
    end

    def lead_pct; (config['lead_pct'] || 58).to_i; end
    def line_pct; (config['line_pct'] || 100).to_i; end
    def draw_ratio; config['draw_ratio'] || 'auto'; end
    def draw_ratios; Array(config['draw_ratios']).map(&:to_i).select { |n| n.between?(1, 1000) }.uniq; end
    def sub_modules; Array(config['sub_modules']); end
    def hidden_tags; Array(config['hidden_tags']); end
    def no_door_scope; config['no_door_scope'] || { 'product' => Array(profile('no_door')['hide']), 'module' => Array(profile('no_door')['hide']) }; end
    def main_back_edges?; !!config['main_back_edges']; end
    def camera_iso_config; config['camera_iso'] || { 'x' => 0.27, 'y' => -1.16, 'z' => 0.35 }; end

    # Chuẩn hoá tên để khớp CHÍNH XÁC: bỏ dấu cách, không phân biệt hoa/thường.
    def norm_name(s)
      s.to_s.downcase.gsub(/\s+/, '')
    end

    def render_width; (config['render_w'] || 1200).to_i; end
    def mini_width;   (config['mini_w']   || 700).to_i;  end
    def mini_alpha;   [[ (config['mini_alpha'] || 30).to_i, 0].max, 255].min; end

    def title_block
      config['title_block']
    end

    # Tên công trình: lấy current_project_name từ MH_Thongke; fallback config; rồi placeholder.
    # Bỏ tiền tố số "xx." ở đầu nếu có (vd "19.GW2605008_..." -> "GW2605008_...").
    def project_title
      nm = thongke_project_name
      nm = title_block['project'] if nm.nil? || nm.empty?
      nm.to_s.sub(/\A\s*\d+\.\s*/, '').strip
    end

    def thongke_project_name
      ensure_thongke
      return nil unless defined?(MH_Thongke) && MH_Thongke.respond_to?(:current_project_name)
      nm = MH_Thongke.current_project_name.to_s.strip
      return nil if nm.empty? || nm == 'Chưa phân loại'
      nm
    rescue
      nil
    end

    # Tên sản phẩm cho khung tên: lấy từ MH_Thongke (Ten_SP theo mã); rồi map config; fallback placeholder.
    def product_name(product)
      code = product.to_s.upcase.split('.').first
      pd = project_data_product_name(code)
      return pd if pd && !pd.empty?
      tk = thongke_product_name(code)
      return tk if tk && !tk.empty?
      cfg = config['product_names'][code]
      return cfg if cfg && !cfg.empty?
      title_block['product']
    end

    def project_data_product_name(code)
      return nil unless defined?(MH::ProjectData) && MH::ProjectData.respond_to?(:product_name_for)
      MH::ProjectData.ensure_loaded if MH::ProjectData.respond_to?(:ensure_loaded)
      nm = MH::ProjectData.product_name_for(code).to_s.strip
      nm.empty? ? nil : nm
    rescue
      nil
    end

    # Lấy Ten_SP từ MH_Thongke.import_excel_product_name_for(code) (tự load snapshot Excel).
    def thongke_product_name(code)
      ensure_thongke
      return nil unless defined?(MH_Thongke) && MH_Thongke.respond_to?(:import_excel_product_name_for)
      nm = MH_Thongke.import_excel_product_name_for(code, true).to_s.strip
      nm.empty? ? nil : nm
    rescue
      nil
    end

    def ensure_thongke
      return if defined?(MH_Thongke) && MH_Thongke.respond_to?(:import_excel_product_name_for)
      plugins = Sketchup.find_support_file('Plugins')
      f = File.join(plugins, 'MH_Thongke', 'main.rb')
      load f if File.exist?(f)
    rescue StandardError
      nil
    end

    def hide_always
      config['hide_always'] || []
    end

    # Chuỗi có khớp từ khoá hide_always không?
    def hide_always_match?(text)
      t = text.to_s.downcase
      hide_always.any? { |k| !k.to_s.strip.empty? && t.include?(k.to_s.downcase) }
    end

    # Entity bị ẩn vĩnh viễn? Khớp tên entity hoặc tên tag/layer (chứa-chuỗi, không phân biệt hoa/thường).
    def never_show?(entity)
      return false if hide_always.empty?
      nm = (entity.respond_to?(:name) ? entity.name.to_s : '')
      nm = "#{nm} #{entity.definition.name}" if entity.respond_to?(:definition) && entity.definition
      lyr = (entity.respond_to?(:layer) && entity.layer ? entity.layer.name.to_s : '')
      hide_always_match?("#{nm} #{lyr}")
    rescue
      false
    end

    def save_config
      File.write(CONFIG_PATH, JSON.pretty_generate(@config || load_config))
      puts "[#{PLUGIN_NAME}] đã lưu config: #{CONFIG_PATH}"
    rescue StandardError => e
      puts "[#{PLUGIN_NAME}] save_config lỗi: #{e.message}"
    end

    def profiles
      config['profiles']
    end

    def profile(key)
      profiles[key.to_s] || profiles['full']
    end

    # KHỚP CHÍNH XÁC (bỏ dấu cách, không phân biệt hoa/thường). Ẩn nếu thuộc profile.hide HOẶC hide_common (mọi bản).
    def hidden_by_profile?(part_name, profile_key)
      pn = norm_name(part_name)
      list = Array(profile(profile_key)['hide']) + Array(config['hide_common'])
      list.any? { |h| !h.to_s.strip.empty? && norm_name(h) == pn }
    end

    def hidden_by_profile_scoped?(part_name, profile_key, scope)
      return hidden_by_profile?(part_name, profile_key) unless profile_key.to_s == 'no_door'
      scope_key = scope.to_s == 'product' ? 'product' : 'module'
      pn = norm_name(part_name)
      list = Array(no_door_scope[scope_key]) + Array(config['hide_common'])
      list.any? { |h| !h.to_s.strip.empty? && norm_name(h) == pn }
    end

    # Part hiện trong ảnh nhưng KHÔNG đánh số/không vào bảng (khớp chính xác).
    def no_number?(part_name)
      pn = norm_name(part_name)
      Array(config['no_number']).any? { |h| !h.to_s.strip.empty? && norm_name(h) == pn }
    end

    # Tổ tiên (part cha) có bị ẩn không? -> để ẩn luôn part con bên trong.
    def ancestor_hidden?(ent, profile_key)
      return false unless ent.respond_to?(:name)
      nm = ent.name.to_s
      info = MH::ProductContext.parse_full(nm)
      hidden_by_profile?(info ? info[:part] : nm, profile_key)
    rescue
      false
    end

    def ancestor_hidden_scoped?(ent, profile_key, scope)
      return false unless ent.respond_to?(:name)
      nm = ent.name.to_s
      info = MH::ProductContext.parse_full(nm)
      hidden_by_profile_scoped?(info ? info[:part] : nm, profile_key, scope)
    rescue
      false
    end

    # part hiện trong profile (ẩn nếu chính nó HOẶC tổ tiên thuộc hide).
    def visible_parts(parts, profile_key)
      parts.reject do |p|
        next true if p[:flat] || hidden_by_profile?(p[:part], profile_key)
        Array(p[:path]).any? { |a| a && a.valid? && ancestor_hidden?(a, profile_key) }
      end
    end

    def visible_parts_scoped(parts, profile_key, scope)
      parts.reject do |p|
        next true if p[:flat] || hidden_by_profile_scoped?(p[:part], profile_key, scope)
        Array(p[:path]).any? { |a| a && a.valid? && ancestor_hidden_scoped?(a, profile_key, scope) }
      end
    end

    # part được liệt kê/đánh số: hiện & có id & KHÔNG nằm trong no_number.
    def listed_parts(parts, profile_key)
      visible_parts(parts, profile_key).select { |p| p[:numbered] && !no_number?(p[:part]) }
    end

    # Thêm/xoá từ khoá hide cho 1 profile (gọi nhanh từ Console).
    def add_hide(profile_key, value)
      pr = profiles[profile_key.to_s]
      return puts("[#{PLUGIN_NAME}] không có profile #{profile_key}") unless pr
      v = value.to_s.strip
      return if v.empty?
      pr['hide'] << v unless pr['hide'].include?(v)
      save_config
      pr['hide']
    end

    def remove_hide(profile_key, value)
      pr = profiles[profile_key.to_s]
      return unless pr
      pr['hide'].delete(value.to_s.strip)
      save_config
      pr['hide']
    end

    # ---- Dialog Settings: sửa hide list từng profile ----------------------
    def settings_dialog
      rows = profiles.map do |key, pr|
        items = pr['hide'].map { |h| h.to_s }.join("\n")
        <<~ROW
          <div class="prof">
            <div class="hd"><b>#{pr['label']}</b> <span class="key">(#{key})</span></div>
            <textarea class="proftext" data-key="#{key}" rows="6" placeholder="mỗi dòng 1 TÊN part bị ẩn (chính xác), vd: Cánh Trái">#{items}</textarea>
          </div>
        ROW
      end.join
      nonum_items = Array(config['no_number']).map(&:to_s).join("\n")

      html = <<~HTML
        <body style="font-family:sans-serif;margin:12px;font-size:13px">
          <h4 style="margin:0 0 6px">Chất lượng / hiển thị</h4>
          <div style="display:flex;gap:10px;flex-wrap:wrap;margin-bottom:10px">
            <label>Độ phân giải ảnh (nhỏ=đậm hơn):<br><input type="number" id="render_w" value="#{render_width}" style="width:90px"></label>
            <label>Độ phân giải mini:<br><input type="number" id="mini_w" value="#{mini_width}" style="width:90px"></label>
            <label>Độ mờ nền mini (0–255):<br><input type="number" id="mini_alpha" min="0" max="255" value="#{mini_alpha}" style="width:90px"></label>
            <label>Mặc định Độ dài leader (0–120):<br><input type="number" id="lead_pct" min="0" max="120" value="#{lead_pct}" style="width:90px"></label>
            <label>Mặc định Giãn dòng (0–320):<br><input type="number" id="line_pct" min="0" max="320" value="#{line_pct}" style="width:90px"></label>
            <label style="display:flex;gap:6px;align-items:center;margin-top:16px"><input type="checkbox" id="main_back_edges" #{main_back_edges? ? 'checked' : ''}> Hiện nét đứt ẩn ở bản vẽ SP/module</label>
          </div>
          <h4 style="margin:8px 0 6px">Camera</h4>
          <div style="display:flex;gap:10px;flex-wrap:wrap;margin-bottom:10px">
            <label>X trái/phải:<br><input type="number" step="0.05" id="cam_x" value="#{camera_iso_config['x']}" style="width:90px"></label>
            <label>Y trước/sau:<br><input type="number" step="0.05" id="cam_y" value="#{camera_iso_config['y']}" style="width:90px"></label>
            <label>Z cao/thấp:<br><input type="number" step="0.05" id="cam_z" value="#{camera_iso_config['z']}" style="width:90px"></label>
          </div>
          <h4 style="margin:8px 0 6px">Từ khoá ẩn theo View Profile</h4>
          <p style="margin:0 0 8px">Mỗi dòng = 1 <b>tên part bị ẩn</b>, khớp <b>CHÍNH XÁC</b> (không phân biệt hoa/thường, bỏ dấu cách).</p>
          #{rows}
          <h4 style="margin:10px 0 6px">Ẩn ở MỌI bản (full + không cánh…)</h4>
          <p style="margin:0 0 6px">Mỗi dòng = 1 tên part <b>ẩn hẳn ở mọi bản vẽ</b> (khớp chính xác). Vd <code>Đánh Dấu Ray Trái</code>.</p>
          <textarea id="hidecommon" rows="4" style="width:100%" placeholder="vd: Đánh Dấu Ray Trái">#{Array(config['hide_common']).map(&:to_s).join("\n")}</textarea>
          <h4 style="margin:10px 0 6px">Không đánh số (vẫn hiện trong ảnh)</h4>
          <p style="margin:0 0 6px">Mỗi dòng = 1 tên part <b>hiện trong ảnh nhưng KHÔNG đánh số / không vào bảng</b> (khớp chính xác).</p>
          <textarea id="nonum" rows="5" style="width:100%" placeholder="vd: Tay Nắm">#{nonum_items}</textarea>
          <button id="save" style="width:100%;padding:8px;margin-top:8px">Lưu</button>
          <script>
            document.getElementById('save').onclick = function(){
              var out = { _hide: {} };
              document.querySelectorAll('textarea.proftext').forEach(function(t){
                out._hide[t.dataset.key] = t.value.split('\\n').map(function(s){return s.trim();}).filter(Boolean);
              });
              out.no_number = document.getElementById('nonum').value.split('\\n').map(function(s){return s.trim();}).filter(Boolean);
              out.hide_common = document.getElementById('hidecommon').value.split('\\n').map(function(s){return s.trim();}).filter(Boolean);
              out.render_w = +document.getElementById('render_w').value;
              out.mini_w = +document.getElementById('mini_w').value;
              out.mini_alpha = +document.getElementById('mini_alpha').value;
              out.lead_pct = +document.getElementById('lead_pct').value;
              out.line_pct = +document.getElementById('line_pct').value;
              out.main_back_edges = document.getElementById('main_back_edges').checked;
              out.camera_iso = {
                x: +document.getElementById('cam_x').value,
                y: +document.getElementById('cam_y').value,
                z: +document.getElementById('cam_z').value
              };
              sketchup.save(JSON.stringify(out));
            };
          </script>
        </body>
      HTML

      dlg = UI::HtmlDialog.new(dialog_title: 'MH Assemble — Settings',
                               preferences_key: 'mh_assemble_settings',
                               width: 380, height: 560,
                               style: UI::HtmlDialog::STYLE_DIALOG)
      dlg.set_html(html)
      dlg.add_action_callback('save') do |_, json|
        begin
          data = JSON.parse(json)
          (data['_hide'] || {}).each do |k, list|
            profiles[k]['hide'] = Array(list).map(&:to_s) if profiles[k]
          end
          config['no_number'] = Array(data['no_number']).map(&:to_s) if data.key?('no_number')
          config['hide_common'] = Array(data['hide_common']).map(&:to_s) if data.key?('hide_common')
          config['render_w']   = data['render_w'].to_i  if data['render_w'].to_i > 0
          config['mini_w']     = data['mini_w'].to_i    if data['mini_w'].to_i > 0
          config['mini_alpha'] = data['mini_alpha'].to_i if data.key?('mini_alpha')
          config['lead_pct']   = data['lead_pct'].to_i  if data.key?('lead_pct')
          config['line_pct']   = data['line_pct'].to_i  if data.key?('line_pct')
          config['main_back_edges'] = !!data['main_back_edges'] if data.key?('main_back_edges')
          if data['camera_iso'].is_a?(Hash)
            config['camera_iso'] = {
              'x' => data['camera_iso']['x'].to_f,
              'y' => data['camera_iso']['y'].to_f,
              'z' => data['camera_iso']['z'].to_f
            }
            set_iso(config['camera_iso']['x'], config['camera_iso']['y'], config['camera_iso']['z']) if respond_to?(:set_iso)
          end
          save_config
          UI.messagebox('Đã lưu Settings.')
        rescue StandardError => e
          UI.messagebox("Lỗi lưu: #{e.message}")
        end
      end
      dlg.show
      dlg
    end
  end
end

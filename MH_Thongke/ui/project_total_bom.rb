# encoding: utf-8
# MH_Thongke — Project Total BOM Renderer
# CHỈ CHỨA HTML RENDERING — Logic xử lý nằm ở engine/processors/project_total_processor.rb

module MH_Thongke

  # === Mini-import style CSS/JS for main dialog ===

  def self.mini_import_inline_css
    <<-CSS
      .status-khop{color:#2ecc71;font-weight:bold;text-align:center;font-size:13px;}
      .status-missing{color:#e67e22;font-weight:bold;text-align:center;}
      .status-extra{color:#e74c3c;font-weight:bold;text-align:center;font-size:10px;}
      .btn-nospec{background:#c0392b;color:#fff;border:none;border-radius:3px;min-width:42px;height:20px;line-height:20px;padding:0 4px;font-size:9px;font-family:inherit;font-weight:bold;margin:0 auto;display:block;cursor:default;text-transform:uppercase;box-sizing:border-box;}
      .btn-spec{background:#f1c40f;color:#1f2933;border:none;border-radius:3px;min-width:42px;height:20px;line-height:20px;padding:0 4px;font-size:9px;font-family:inherit;font-weight:bold;margin:0 auto;display:block;cursor:default;text-transform:uppercase;box-sizing:border-box;}
      .btn-accept{cursor:pointer;}
      .btn-update{background:#d35400;color:#fff;border:none;border-radius:3px;min-width:48px;height:20px;line-height:20px;padding:0 4px;font-size:9px;font-family:inherit;font-weight:bold;margin:0 auto;display:block;cursor:pointer;text-transform:uppercase;box-sizing:border-box;}
      .btn-keep{background:#475569;color:#fff;border:none;border-radius:3px;min-width:48px;height:20px;line-height:20px;padding:0 4px;font-size:9px;font-family:inherit;font-weight:bold;margin:0 auto;display:block;cursor:pointer;text-transform:uppercase;box-sizing:border-box;}
      .btn-del{background:#c0392b;color:#fff;border:none;border-radius:3px;width:17px;height:18px;line-height:18px;padding:0;margin:0 auto;display:block;cursor:pointer;font-size:9px;font-weight:bold;}
      .status-actions{display:flex;flex-direction:column;align-items:center;gap:2px;}
      .status-actions .btn{height:17px;line-height:17px;font-size:8px;padding:0 4px;}
      .mini-product-row td{background:#111827;color:#f8fafc;font-weight:bold;text-transform:uppercase;border-top:1px solid #6b7580;padding-top:5px;padding-bottom:5px;}
      .mini-product-head{display:flex;align-items:center;justify-content:space-between;gap:8px;width:100%;}
      .mini-product-title{display:block;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
      .mini-section-row td{background:#2f3740;color:#cbd5e1;font-weight:bold;font-size:10px;text-transform:uppercase;padding-top:3px;padding-bottom:3px;}
      .mini-row{cursor:pointer;}
      .mini-row:hover{background:#3d444b;}
      .mini-row.selected{background:#1a5276!important;color:#fff;}
      .name-input{width:100%;box-sizing:border-box;border:1px solid transparent;background:transparent;color:#e67e22;font-weight:bold;outline:none;padding:1px 2px;font-family:inherit;font-size:10px;line-height:14px;}
      .name-input:focus{border-color:#454d55;background:#1e1e24;}
      .note-input{width:100%;box-sizing:border-box;border:1px solid transparent;background:transparent;color:#dcdcdc;outline:none;padding:1px 2px;font-family:inherit;font-size:10px;line-height:14px;}
      .note-input:focus{border-color:#454d55;background:#1e1e24;}
      .qty-input{width:100%;height:18px;box-sizing:border-box;border:none;background:transparent;color:#fff;padding:1px 0;font-family:inherit;font-size:10px;text-align:center;outline:none;pointer-events:none;}
      .qty-input:disabled{opacity:1;-webkit-text-fill-color:#fff;}
      .spec-text{font-size:8px;color:#a1a1aa;display:block;margin-top:0;font-weight:normal;line-height:11px;}
    CSS
  end

  def self.mini_import_inline_js
    <<-JS
      function stopMiniEvent(){ if(window.event){ window.event.stopPropagation(); } }
      function selectImportRow(row) {
        if(!row.getAttribute('data-name')) return;
        document.querySelectorAll('.mini-row.selected').forEach(function(r){ r.classList.remove('selected'); });
        row.classList.add('selected');
        sketchup.select_item(row.getAttribute('data-product') || '', row.getAttribute('data-name') || '', row.getAttribute('data-ids') || '');
      }
      function rowProduct(el) { return el.getAttribute('data-product') || ''; }
      function acceptImportItem(btn) { stopMiniEvent(); sketchup.accept_item(rowProduct(btn), btn.getAttribute('data-kind') || 'PK', btn.getAttribute('data-old') || '', btn.getAttribute('data-name') || '', btn.getAttribute('data-spec') || ''); }
      function updateImportItem(btn) { stopMiniEvent(); sketchup.update_item(rowProduct(btn), btn.getAttribute('data-old'), btn.getAttribute('data-name'), btn.getAttribute('data-spec') || ''); }
      function keepImportItem(btn) { stopMiniEvent(); sketchup.keep_item(rowProduct(btn), btn.getAttribute('data-kind') || 'PK', btn.getAttribute('data-old') || '', btn.getAttribute('data-name') || '', btn.getAttribute('data-spec') || ''); }
      function deleteImportItem(btn) { stopMiniEvent(); sketchup.delete_item(rowProduct(btn), btn.getAttribute('data-name'), btn.getAttribute('data-ids') || ''); }
      function removeExcelItem(btn) { stopMiniEvent(); sketchup.remove_excel_item(rowProduct(btn), btn.getAttribute('data-kind') || 'PK', btn.getAttribute('data-name') || '', btn.getAttribute('data-spec') || ''); }
      function renameImportItem(input) { sketchup.rename_item(rowProduct(input), input.getAttribute('data-old') || '', input.value || '', input.getAttribute('data-target') || '', input.getAttribute('data-spec') || '', input.getAttribute('data-kind') || 'PK'); }
      function setImportNote(input) { sketchup.set_note(rowProduct(input), input.getAttribute('data-kind') || 'PK', input.getAttribute('data-name') || '', input.getAttribute('data-spec') || '', input.value); }
    JS
  end

  # === HTML helpers (thuần UI) ===

  def self.project_total_status_html(status_text)
    badge_color = case status_text
                  when "OK" then "green"
                  when "LỆCH SL" then "orange"
                  when "DƯ MODEL" then "purple"
                  else "red"
                  end
    "<span class='badge bg-#{badge_color}'>#{html_escape(status_text)}</span>"
  end

  def self.tab_all_status_html(status_text)
    color = case status_text
            when "OK" then "#27ae60"
            when "LỆCH SL" then "#f39c12"
            when "DƯ MODEL" then "#9b59b6"
            else "#e74c3c"
            end
    "<span style='display:inline-block;min-width:62px;text-align:center;background:#{color};color:#fff;font-weight:bold;font-size:10px;padding:2px 4px;border-radius:2px'>#{html_escape(status_text)}</span>"
  end

  def self.tab_all_empty_row
    "<tr><td colspan='12' style='text-align:center;color:#7f8c8d;padding:15px'>Không có dữ liệu vật liệu/phụ kiện từ JSON dự án hoặc JSON Excel</td></tr>"
  end

  # -------------------------------------------------------
  # build_project_total_bom_rows -> HTML string
  # Gọi compute_project_total_data() để lấy data, chỉ render HTML.
  # -------------------------------------------------------
  def self.build_project_total_bom_rows
    rows = compute_project_total_data

    rows_html = String.new
    rows.each do |group|
      status_text = group[:status] || project_total_status(group)
      products_text = Array(group[:products]).sort_by { |p| respond_to?(:product_code_sort_key) ? product_code_sort_key(p) : p }.join(", ")
      products_text = group[:product].to_s if products_text.empty?
      search_text = [products_text, group[:kind], group[:name], group[:spec], group[:note], status_text, group[:unit]].join(" ")
      is_missing = status_text == "THIẾU MODEL" || status_text == "LỆCH SL" ? "1" : "0"

      rows_html << "<tr class='data-row project-total-row' data-missing='#{is_missing}' data-search='#{html_escape(search_text)}'>"
      rows_html << "<td><b>#{html_escape(products_text)}</b></td>"
      rows_html << "<td><span class='badge'>#{html_escape(group[:kind])}</span></td>"
      rows_html << "<td>#{html_escape(group[:name])}</td>"
      rows_html << "<td>#{html_escape(group[:spec])}</td>"
      rows_html << "<td>#{html_escape(group[:note])}</td>"
      rows_html << "<td>#{project_total_status_html(status_text)}</td>"
      rows_html << "<td><b>#{project_total_qty_text(group[:excel_qty])}</b></td>"
      rows_html << "<td style='font-weight:bold;color:#e74c3c'>#{project_total_qty_text(group[:model_qty])}</td>"
      rows_html << "<td>#{html_escape(group[:unit])}</td>"
      rows_html << "<td></td>"
      rows_html << "</tr>\n"
    end

    rows_html.empty? ? "<tr><td colspan='10' style='text-align:center;color:#7f8c8d;padding:15px'>Không có dữ liệu vật liệu/phụ kiện từ JSON dự án hoặc JSON Excel</td></tr>" : rows_html
  rescue => error
    backtrace = Array(error.backtrace).first(3).join("<br>")
    "<tr><td colspan='10' style='text-align:center;color:#e74c3c;padding:15px'>Lỗi: #{html_escape(error.message)}<br>#{backtrace}</td></tr>"
  end

  # -------------------------------------------------------
  # build_tab_all_bom_rows -> HTML string (mini-import style)
  # Iterates ALL products, renders PK + VL per product using
  # the same matching/rendering pipeline as Mini Import.
  # -------------------------------------------------------
  def self.build_tab_all_bom_rows
    build_tab_bom_mini_rows(include_pk: true, include_vl: true)
  rescue => error
    "<tr><td colspan='5' style='text-align:center;color:#e74c3c;padding:15px'>Lỗi tab-all: #{html_escape(error.message)}</td></tr>"
  end

  # -------------------------------------------------------
  # build_tab_acc_bom_rows -> HTML string (mini-import style)
  # Same as tab-all but PK only (no VL sections).
  # -------------------------------------------------------
  def self.build_tab_acc_bom_rows
    build_tab_bom_mini_rows(include_pk: true, include_vl: false)
  rescue => error
    "<tr><td colspan='5' style='text-align:center;color:#e74c3c;padding:15px'>Lỗi tab-acc: #{html_escape(error.message)}</td></tr>"
  end

  # -------------------------------------------------------
  # build_tab_mat_bom_rows -> HTML string (mini-import style)
  # VL only (no PK sections) — for tab-mat.
  # -------------------------------------------------------
  def self.build_tab_mat_bom_rows
    build_tab_bom_mini_rows(include_pk: false, include_vl: true)
  rescue => error
    "<tr><td colspan='5' style='text-align:center;color:#e74c3c;padding:15px'>Lỗi tab-mat: #{html_escape(error.message)}</td></tr>"
  end

  def self.build_tab_bom_mini_rows(include_pk: true, include_vl: true)
    load_import_excel_snapshot_only if respond_to?(:load_import_excel_snapshot_only) && (@imported_excel_data.nil? || @imported_excel_data.empty?)
    ensure_mini_accept_rules if respond_to?(:ensure_mini_accept_rules)
    ensure_mini_name_lineage if respond_to?(:ensure_mini_name_lineage)

    # JSON-only: bang chinh doc tu snapshot trong tab FILE, khong scan model dang mo.
    if respond_to?(:merged_priority_snapshot_runtime_rows)
      # Memoized: tra ve CUNG object khi base-content + snapshots khong doi.
      # merged_priority_snapshot_runtime_rows() von tao mang moi moi lan goi, lam
      # object_id cua @current_report/mat_items doi lien tuc -> giet moi cache theo
      # object_id (tab BOM, mini_model_items, HUD). Memo giu object_id on dinh.
      merged_report, merged_mat = merged_priority_runtime_rows_memo([], [])
      @current_report_items = merged_report
      @current_mat_items = merged_mat
      if respond_to?(:session)
        session.current_report_items = @current_report_items
        session.current_mat_items = @current_mat_items
      end
    end

    # Top-level cache: avoid re-iterating 36 products on every refresh.
    # Invalidated automatically when any of these signatures change:
    #   Excel data / accept rules / lineage / synonyms / data source / model items
    cache_key = tab_bom_mini_rows_cache_key(include_pk, include_vl)
    if cache_key && respond_to?(:instance_cache_fetch)
      cached = instance_cache_fetch(:@tab_bom_mini_rows_cache, cache_key)
      return cached unless cached.nil?
    end

    products = tab_bom_all_product_codes
    empty_label = if include_pk && include_vl
                    "Không có dữ liệu PK/VL."
                  elsif include_pk
                    "Không có dữ liệu PK."
                  else
                    "Không có dữ liệu VL."
                  end
    return "<tr><td colspan='5' class='empty'>#{empty_label}</td></tr>" if products.empty?

    rows = +""
    products.each do |product_code|
      ex_items = mini_excel_items(product_code, false)
      pk_ex_items = ex_items.reject { |ex| ex[:kind].to_s == "VL" }
      vl_ex_items = ex_items.select { |ex| ex[:kind].to_s == "VL" }

      pk_rows = []
      if include_pk
        pk_html = build_import_mini_rows_for_product(product_code, pk_ex_items, true, [], nil, false, "PK")
        pk_rows, = mini_split_rows(pk_html)
      end

      vl_html = ""
      if include_vl
        vl_html = mini_rows_material_sections_html(product_code, vl_ex_items)
      end

      next if pk_rows.empty? && vl_html.empty?

      rows << mini_group_header(product_code)
      if pk_rows.any?
        rows << mini_section_header("Phụ kiện") if include_vl && !vl_html.empty?
        rows << pk_rows.join
      end
      rows << vl_html if include_vl && !vl_html.empty?
    end

    final = rows.empty? ? "<tr><td colspan='5' class='empty'>#{empty_label}</td></tr>" : rows
    instance_cache_store(:@tab_bom_mini_rows_cache, cache_key, final, 12) if cache_key && respond_to?(:instance_cache_store)
    final
  rescue => e
    puts "build_tab_bom_mini_rows error: #{e.class}: #{e.message}" rescue nil
    "<tr><td colspan='5' class='empty'>Lỗi: #{html_escape(e.message)}</td></tr>"
  end

  def self.tab_bom_mini_rows_cache_key(include_pk, include_vl)
    [
      include_pk ? 1 : 0,
      include_vl ? 1 : 0,
      respond_to?(:active_data_source_id) ? active_data_source_id : "MODEL",
      respond_to?(:import_mini_data_signature) ? import_mini_data_signature : import_mini_refresh_signature,
      (@current_report_items || []).size,
      (@current_mat_items || []).size,
      # CONTENT fingerprint, KHONG dung object_id: merged_priority_snapshot_runtime_rows
      # tao mang moi moi lan goi -> object_id luon doi -> cache khong bao gio trung.
      # Fingerprint chi gom field hien thi cap du an (bo sel_count/sel_length) nen
      # selection thay doi van giu cache (BOM tab khong phu thuoc selection).
      bom_rows_content_sig(@current_report_items),
      bom_rows_content_sig(@current_mat_items)
    ].join("::")
  rescue
    nil
  end

  # Memoize ket qua merge snapshot uu tien. Tra ve [merged_report, merged_mat] la
  # CUNG object qua nhieu lan goi khi base-content + snapshots khong doi -> object_id
  # on dinh -> cac cache theo object_id (mini_model_items, rebuild_mini_model_row_indexes,
  # material_hud) hoat dong lai, va 3 tab build khi mo dialog dung chung index.
  def self.merged_priority_runtime_rows_memo(base_report, base_mat)
    sig = [
      0, "",
      0, "",
      priority_snapshot_merge_signature
    ].join("::")
    memo = @merged_priority_runtime_memo
    return memo[:rows] if memo.is_a?(Hash) && memo[:sig] == sig

    rows = [
      merged_priority_snapshot_runtime_rows(base_report, :items),
      merged_priority_snapshot_runtime_rows(base_mat, :mat_items)
    ]
    @merged_priority_runtime_memo = { sig: sig, rows: rows }
    rows
  rescue
    [
      merged_priority_snapshot_runtime_rows(base_report, :items),
      merged_priority_snapshot_runtime_rows(base_mat, :mat_items)
    ]
  end

  # Signature thay doi khi tap snapshot hoac noi dung snapshot nguon thay doi.
  # Dung cung co che cache theo snapshot-id nhu phan con lai cua app.
  def self.priority_snapshot_merge_signature
    [
      (@file_snapshots || []).size,
      (@file_snapshots || []).map { |s| s["id"].to_s }.join(","),
      (respond_to?(:project_total_source_rows) ? project_total_source_rows(:items) : []).hash,
      (respond_to?(:project_total_source_rows) ? project_total_source_rows(:mat_items) : []).hash
    ].hash
  rescue
    0
  end

  # Cheap content fingerprint cua rows phuc vu cache BOM tabs.
  # Chi hash cac field anh huong output (project-level), KHONG gom sel_count/sel_length
  # de cache van trung khi nguoi dung click chon doi tuong.
  def self.bom_rows_content_sig(rows)
    Array(rows).map do |r|
      next 0 unless r.is_a?(Hash)
      [
        r[:product], r[:actual_product], r[:name], r[:count],
        r[:trang_thai], r[:unit], r[:_resolved_unit], r[:_resolved_qty],
        r[:ten_sp], r[:ghi_chu], r[:ngay_dat], r[:target_name],
        r[:new_name], r[:spec], r[:layer], r[:virtual_source]
      ].hash
    end.hash
  rescue
    Array(rows).size
  end

  def self.tab_bom_all_product_codes
    codes = Set.new

    if respond_to?(:import_excel_product_codes)
      import_excel_product_codes("product").each { |c| codes << c }
    end

    [(@current_report_items || []), (@current_mat_items || [])].each do |source|
      source.each do |row|
        next unless row.is_a?(Hash)
        product = row[:actual_product] || row[:product]
        code = respond_to?(:product_code_base) ? product_code_base(product) : product.to_s.strip.upcase
        codes << code if product_code_valid?(code) rescue code =~ /\A[A-Z]+\d+/i
      end
    end

    codes.to_a.sort_by { |c| respond_to?(:product_code_sort_key) ? product_code_sort_key(c) : c }
  rescue
    []
  end

end

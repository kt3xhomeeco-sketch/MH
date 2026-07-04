# encoding: utf-8
# MH_Thongke — SessionState
# Single source of truth cho tất cả session-scoped state.
# Thay thế 50+ @module_ivars rải rác — giờ có lifecycle rõ ràng và reset điểm duy nhất.

require 'set'

module MH_Thongke
  class SessionState

    # =========================================================
    # Nhóm 0: Dirty flags — chi dinh phan nao cua pipeline can chay lai
    # =========================================================
    attr_accessor :dirty_scan         # true: model thay doi, can rescan
    attr_accessor :dirty_excel        # true: excel data thay doi, can rematch
    attr_accessor :dirty_overrides    # true: date/meta/hidden thay doi, can reapply
    attr_accessor :dirty_status       # true: rules thay doi, can rematch status
    attr_accessor :dirty_html         # true: UI can rebuild
    attr_accessor :dirty_selection    # true: chi update sel_count (khong can rescan)
    attr_accessor :last_full_scan_at  # timestamp cua lan scan gan nhat

    # =========================================================
    # Nhóm 1: Kết quả scan model (reset sau mỗi lần scan)
    # =========================================================
    attr_accessor :data_map          # Hash: key -> row phụ kiện
    attr_accessor :mat_data_map      # Hash: key -> row vật liệu
    attr_accessor :prod_groups       # Hash: product_code -> [entities]
    attr_accessor :all_item_names    # Array: tất cả tên item đã thấy
    attr_accessor :all_item_names_set # Set: lookup nhanh
    attr_accessor :led_per_product   # Hash: product_code -> led_length
    attr_accessor :phaochi_map       # Hash: phao chi items
    attr_accessor :current_report_items  # Array: rows hiện tại tab PK (sorted)
    attr_accessor :current_mat_items     # Array: rows hiện tại tab VL (sorted)
    attr_accessor :process_selection_cache_sig  # String: signature để skip rescan
    attr_accessor :stat_entity_ids       # Set: entity IDs trong data_map
    attr_accessor :entity_ids_in_data    # Set: entity IDs dùng để check overlap
    attr_accessor :visible_product_codes_cache  # Array: cache mã SP đang visible
    attr_accessor :product_match_details  # Hash: product_code -> ProductDetail (matched/excel_only/model_only)

    # =========================================================
    # Nhóm 2: Excel import state
    # =========================================================
    attr_accessor :imported_excel_data    # Array: rows từ Excel đã load
    attr_accessor :back_imported_excel    # Array: back-import rows
    attr_accessor :back_import_diff       # Hash: diff giữa model và back-import

    # =========================================================
    # Nhóm 3: Rules (reload khi cần, không phụ thuộc model cụ thể)
    # =========================================================
    attr_accessor :match_rules      # Hash: specific matching rules
    attr_accessor :general_rules    # Hash: synonym/equivalent/ignore rules
    attr_accessor :mini_accept_rules  # Hash: accept rules từ Mini Import

    # =========================================================
    # Nhóm 4: Preferences (persistent, load từ JSON, keep qua model switch)
    # =========================================================
    attr_accessor :hidden_list           # Array: tên item bị ẩn
    attr_accessor :unit_overrides        # Hash: data_key -> unit override
    attr_accessor :length_display_units  # Hash: data_key -> "mm"/"cm"/"m"
    attr_accessor :known_pk_names        # Array: tên PK đã từng gặp
    attr_accessor :import_excel_path     # String: đường dẫn Excel hiện tại (legacy)
    attr_accessor :import_excel_paths    # Hash: project_name -> excel_path
    attr_accessor :import_excel_model_paths  # Hash: model_path -> excel_path
    attr_accessor :project_total_view    # "COMPACT" | "DETAIL"
    attr_accessor :project_total_sort    # "CUT" | "PRODUCT"
    attr_accessor :pk_report_view_scope  # "PROJECT" | "CUT"
    attr_accessor :pk_report_cut_source  # String
    attr_accessor :active_data_source_id # "MODEL" | "snap:X" | "json:Y" — drives mini/tabs/HUD source

    # =========================================================
    # Nhóm 5: UI display state
    # =========================================================
    attr_accessor :group_by      # "PRODUCT" | "NAME"
    attr_accessor :display_mode  # "ALL" | "MISSING" | ...

    # =========================================================
    # Nhóm 6: History / audit
    # =========================================================
    attr_accessor :change_history  # Array: {time, action, details}

    def initialize
      reset_dirty!
      reset_scan!
      reset_excel!
      reset_rules!
      reset_prefs!
      reset_ui!
    end

    # Reset dirty flags
    def reset_dirty!
      @dirty_scan = false
      @dirty_excel = false
      @dirty_overrides = false
      @dirty_status = false
      @dirty_html = false
      @dirty_selection = false
      @last_full_scan_at = nil
    end

    # Mark everything dirty (model changed significantly)
    def mark_all_dirty!
      @dirty_scan = true
      @dirty_excel = true
      @dirty_overrides = true
      @dirty_status = true
      @dirty_html = true
    end

    # Chi can update selection counts, khong can rescan
    def mark_selection_dirty!
      @dirty_selection = true
      @dirty_html = true
    end

    # Override thay doi (date edit, meta edit, hidden list)
    def mark_overrides_dirty!
      @dirty_overrides = true
      @dirty_status = true
      @dirty_html = true
    end

    # Kiem tra co can full pipeline hay chi fast update
    def needs_full_pipeline?
      @dirty_scan || @dirty_excel
    end

    def needs_partial_pipeline?
      @dirty_overrides || @dirty_status
    end

    def needs_selection_update_only?
      !needs_full_pipeline? && !needs_partial_pipeline? && @dirty_selection
    end

    def any_dirty?
      @dirty_scan || @dirty_excel || @dirty_overrides || @dirty_status || @dirty_html || @dirty_selection
    end

    # Reset kết quả scan — gọi mỗi khi model thay đổi đáng kể
    def reset_scan!
      @data_map = {}
      @mat_data_map = {}
      @prod_groups = {}
      @all_item_names = []
      @all_item_names_set = Set.new
      @led_per_product = {}
      @phaochi_map = {}
      @current_report_items = []
      @current_mat_items = []
      @process_selection_cache_sig = nil
      @stat_entity_ids = nil
      @entity_ids_in_data = nil
      @visible_product_codes_cache = nil
      @product_match_details = {}
      @back_import_diff = nil
    end

    # Reset excel state — gọi khi đổi file Excel hoặc đổi model
    def reset_excel!
      @imported_excel_data = nil
      @back_imported_excel = nil
      @back_import_diff = nil
    end

    # Reset rules cache — gọi khi rules file thay đổi
    def reset_rules!
      @match_rules = nil
      @general_rules = nil
      @mini_accept_rules = nil
    end

    # Reset preferences về default — chỉ gọi khi load_preferences thất bại
    def reset_prefs!
      @hidden_list = []
      @unit_overrides = {}
      @length_display_units = {}
      @known_pk_names = []
      @import_excel_path = ""
      @import_excel_paths = {}
      @import_excel_model_paths = {}
      @project_total_view = "COMPACT"
      @project_total_sort = "CUT"
      @pk_report_view_scope = "PROJECT"
      @pk_report_cut_source = ""
    end

    # Reset UI display state
    def reset_ui!
      @group_by = "PRODUCT"
      @display_mode = "ALL"
      @change_history = []
    end

    # Gọi khi đổi model: giữ prefs, reset scan + rules + excel
    def reset_for_new_model!
      reset_scan!
      reset_excel!
      reset_rules!
      @change_history = []
    end

    # Full reset — gọi khi dialog đóng để giải phóng bộ nhớ (entity refs)
    def reset!
      reset_scan!
      reset_excel!
      reset_rules!
      reset_ui!
      # Không reset prefs — chúng sẽ được reload từ JSON khi cần
    end

  end
end

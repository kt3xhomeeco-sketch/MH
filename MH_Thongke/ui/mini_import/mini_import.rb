# encoding: utf-8
module MH_Thongke
  MINI_IMPORT_DIR = File.dirname(__FILE__) unless defined?(MINI_IMPORT_DIR)
  MINI_IMPORT_UI_DIR = File.join(MINI_IMPORT_DIR, "logic") unless defined?(MINI_IMPORT_UI_DIR)
  MINI_IMPORT_PROCESSOR_DIR = File.expand_path(File.join(MINI_IMPORT_DIR, "..", "..", "engine", "processors")) unless defined?(MINI_IMPORT_PROCESSOR_DIR)
end

# Core processors: shared data/matching logic for aggregate tables and Mini Import.
load File.join(MH_Thongke::MINI_IMPORT_PROCESSOR_DIR, "matching_rules_processor.rb")
load File.join(MH_Thongke::MINI_IMPORT_PROCESSOR_DIR, "product_context_processor.rb")
load File.join(MH_Thongke::MINI_IMPORT_PROCESSOR_DIR, "accept_rules_processor.rb")
load File.join(MH_Thongke::MINI_IMPORT_PROCESSOR_DIR, "bom_data_processor.rb")

# Shared BOM table rendering (main tables + mini import dialog) depends on data processors.
load File.join(MH_Thongke::MINI_IMPORT_UI_DIR, "bom_tables_rendering.rb")
load File.join(MH_Thongke::MINI_IMPORT_PROCESSOR_DIR, "entity_actions_processor.rb")
load File.join(MH_Thongke::MINI_IMPORT_UI_DIR, "mini_import_refreshing.rb")
load File.join(MH_Thongke::MINI_IMPORT_UI_DIR, "mini_import_dialog_ui.rb")
load File.join(MH_Thongke::MINI_IMPORT_UI_DIR, "mini_import_callbacks.rb")
load File.join(MH_Thongke::MINI_IMPORT_UI_DIR, "mini_import_menu_ui.rb")

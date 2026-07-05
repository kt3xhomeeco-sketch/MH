# encoding: utf-8
# MH_Thongke - Entry Point

require 'sketchup.rb'
require 'fileutils'
require File.join(Sketchup.find_support_file('Plugins'), 'MH_shared.rb')
raise "MH_Thongke requires MH_shared" unless defined?(MH::Shared) && defined?(MH::ModelHub)

module MH_Thongke
  DIR = File.dirname(__FILE__) unless defined?(DIR)
  ROOT_DIR = DIR unless defined?(ROOT_DIR)
  CORE_DIR = File.join(ROOT_DIR, 'core') unless defined?(CORE_DIR)
  ENGINE_DIR = File.join(ROOT_DIR, 'engine') unless defined?(ENGINE_DIR)
  UI_DIR = File.join(ROOT_DIR, 'ui') unless defined?(UI_DIR)
  TOOLS_DIR = File.join(ROOT_DIR, 'tools') unless defined?(TOOLS_DIR)
  DEBUG = false unless const_defined?(:DEBUG, false)

  def self.debug_log(message)
    puts message if DEBUG
  end

  def self.reload_latest!
    return if @reloading_latest

    @reloading_latest = true
    @defer_next_process_selection = true
    load File.join(DIR, 'main.rb')
    debug_log("MH_Thongke: reload_latest! completed")
  rescue => e
    debug_log("MH_Thongke reload_latest error: #{e.class}: #{e.message}")
  ensure
    @reloading_latest = false
  end

  # Hot-reload: reload all code + reset caches, keep Excel data and session intact.
  # Safe to call from vbo agent or Ruby Console.
  #   MH_Thongke.hot_reload!
  def self.hot_reload!
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f

    # Preserve current state
    saved_excel = @imported_excel_data
    saved_excel_path = @import_excel_loaded_path
    saved_excel_mtime = @import_excel_loaded_mtime
    saved_excel_source = @import_excel_source

    # Stop timers to avoid stale callbacks
    UI.stop_timer(@staggered_mini_timer) if defined?(@staggered_mini_timer) && @staggered_mini_timer
    UI.stop_timer(@staggered_hud_timer) if defined?(@staggered_hud_timer) && @staggered_hud_timer
    UI.stop_timer(@periodic_refresh_timer) if defined?(@periodic_refresh_timer) && @periodic_refresh_timer
    @staggered_mini_timer = nil
    @staggered_hud_timer = nil
    @periodic_refresh_timer = nil

    # Reload all source files (main.rb cascades via load)
    reload_latest!

    # Force-reload files loaded via require_relative (won't reload via main.rb load)
    require_relative_files = [
      File.join(UI_DIR, 'project_total_bom.rb'),
      File.join(ENGINE_DIR, 'data_processor_utils.rb'),
      File.join(ENGINE_DIR, 'processors', 'accept_rules_store.rb'),
      File.join(ENGINE_DIR, 'processors', 'accept_rules.rb'),
      File.join(ENGINE_DIR, 'processors', 'accept_lineage.rb'),
      File.join(ENGINE_DIR, 'processors', 'accept_state.rb'),
      File.join(ENGINE_DIR, 'processors', 'accept_session.rb'),
      File.join(ENGINE_DIR, 'processors', 'attribute_history_processor.rb'),
      File.join(ENGINE_DIR, 'processors', 'matching_rules_processor.rb'),
      File.join(ENGINE_DIR, 'processors', 'bom_data_processor.rb'),
      File.join(ENGINE_DIR, 'processors', 'product_context_processor.rb'),
      File.join(ENGINE_DIR, 'processors', 'entity_actions_processor.rb'),
      File.join(ENGINE_DIR, 'processors', 'material_processor.rb'),
      File.join(ENGINE_DIR, 'processors', 'project_total_processor.rb'),
      File.join(ENGINE_DIR, 'processors', 'report_data_processor.rb'),
      File.join(ENGINE_DIR, 'processors', 'excel_match_rules.rb'),
    ]
    require_relative_files.each do |path|
      load(path) if File.exist?(path)
    end

    # Restore Excel data (avoid re-parsing)
    if saved_excel && !saved_excel.empty?
      set_imported_excel_data(saved_excel, "main_restore_saved_excel", sync_session: true) if respond_to?(:set_imported_excel_data)
      @import_excel_loaded_path = saved_excel_path
      @import_excel_loaded_mtime = saved_excel_mtime
      @import_excel_source = saved_excel_source
    end

    # Reset render/match caches (not data caches)
    invalidate_mini_import_caches(model: true, excel: false) if respond_to?(:invalidate_mini_import_caches)
    @mini_pk_model_name_match_cache = nil
    @last_main_html_hash = nil
    @process_selection_cache_sig = nil

    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f) - t0) * 1000.0
    debug_log("MH_Thongke: hot_reload! done in #{elapsed.round(0)}ms (Excel: #{(saved_excel || []).size} rows preserved)")

    # Refresh open dialogs
    if @dlg && (@dlg.visible? rescue false)
      process_selection_cached(true) if respond_to?(:process_selection_cached)
      update_html(true) if respond_to?(:update_html)
    end
    true
  rescue => e
    debug_log("MH_Thongke hot_reload! error: #{e.class}: #{e.message}")
    debug_log(e.backtrace.first(5).join("\n")) rescue nil
    false
  end

  def self.cleanup_legacy_project_indexer!
    if instance_variable_defined?(:@project_indexer_timer)
      timer = @project_indexer_timer
      UI.stop_timer(timer) if timer
    end
  rescue
  ensure
    [
      :@project_indexer_timer,
      :@project_indexer_busy,
      :@project_indexer_dirty,
      :@project_indexer_last_signature
    ].each do |ivar|
      remove_instance_variable(ivar) if instance_variable_defined?(ivar)
    end
    class << self
      [
        :project_indexer_signature,
        :index_current_model_to_project_json,
        :project_indexer_tick,
        :start_project_indexer,
        :stop_project_indexer
      ].each do |method_name|
        remove_method(method_name) if method_defined?(method_name)
      end
    end
  end
end

MH_Thongke.cleanup_legacy_project_indexer!

# Load modules in dependency order.
load File.join(MH_Thongke::CORE_DIR, 'session_state.rb')
load File.join(MH_Thongke::CORE_DIR, 'config.rb')
load File.join(MH_Thongke::CORE_DIR, 'normalizer.rb')
load File.join(MH_Thongke::CORE_DIR, 'row_models.rb')
load File.join(MH_Thongke::CORE_DIR, 'status.rb')
load File.join(MH_Thongke::CORE_DIR, 'snapshot_store.rb')
load File.join(MH_Thongke::ENGINE_DIR, 'geometry.rb')
load File.join(MH_Thongke::TOOLS_DIR, 'tools.rb')
load File.join(MH_Thongke::CORE_DIR, 'performance.rb')
load File.join(MH_Thongke::CORE_DIR, 'p4_delta_tracker.rb')
load File.join(MH_Thongke::CORE_DIR, 'p4_delta_merge_harness.rb')
load File.join(MH_Thongke::CORE_DIR, 'observers.rb')
load File.join(MH_Thongke::CORE_DIR, 'preferences.rb')
load File.join(MH_Thongke::CORE_DIR, 'excel_import.rb')
load File.join(MH_Thongke::CORE_DIR, 'classified_import.rb')
load File.join(MH_Thongke::CORE_DIR, 'restore_manager.rb')
load File.join(MH_Thongke::CORE_DIR, 'public_api.rb')
load File.join(MH_Thongke::ENGINE_DIR, 'rules_manager.rb')
load File.join(MH_Thongke::ENGINE_DIR, 'core_matcher.rb')
load File.join(MH_Thongke::ENGINE_DIR, 'model_scanner.rb')
load File.join(MH_Thongke::ENGINE_DIR, 'excel_matcher.rb')
load File.join(MH_Thongke::ENGINE_DIR, 'product_matcher.rb')
load File.join(MH_Thongke::ENGINE_DIR, 'processors', 'excel_match_rules.rb')
load File.join(MH_Thongke::ENGINE_DIR, 'processors', 'attribute_history_processor.rb')
load File.join(MH_Thongke::ENGINE_DIR, 'pipeline.rb')
load File.join(MH_Thongke::CORE_DIR, 'p3_harness.rb')
load File.join(MH_Thongke::ENGINE_DIR, 'data_processor.rb')
load File.join(MH_Thongke::UI_DIR, 'html_builder.rb')
load File.join(MH_Thongke::UI_DIR, 'dialog.rb')
load File.join(MH_Thongke::UI_DIR, 'mini_import', 'mini_import.rb')
load File.join(MH_Thongke::UI_DIR, 'material_hud_config.rb')
load File.join(MH_Thongke::UI_DIR, 'material_hud_render.rb')
load File.join(MH_Thongke::UI_DIR, 'material_hud_cache.rb')
load File.join(MH_Thongke::UI_DIR, 'material_hud_data.rb')
load File.join(MH_Thongke::UI_DIR, 'material_hud_overlay.rb')
load File.join(MH_Thongke::UI_DIR, 'material_hud_refresh.rb')
load File.join(MH_Thongke::UI_DIR, 'material_hud.rb')
load File.join(MH_Thongke::UI_DIR, 'info_hud_overlay.rb')

MH_Thongke.clear_excel_loading_state if MH_Thongke.respond_to?(:clear_excel_loading_state)
MH_Thongke.instance_variable_set(:@defer_next_process_selection, true) if MH_Thongke.instance_variable_get(:@reloading_latest)

MH_Thongke.register_mini_import_menu

unless file_loaded?(__FILE__)
  UI.add_context_menu_handler do |context_menu|
    sel = Sketchup.active_model.selection
    if sel.length > 0
      context_menu.add_item('Mini Import Phu Kien (Excel)') {
        MH_Thongke.reload_latest!
        MH_Thongke.force_show_import_mini_dialog
      }
    end
  end

  file_loaded(__FILE__)
end

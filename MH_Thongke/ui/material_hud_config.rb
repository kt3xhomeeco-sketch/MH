# encoding: utf-8
# MH_Thongke - Material HUD constants and colors.

module MH_Thongke
  remove_const(:HUD_REFRESH_DELAY_SECONDS) if const_defined?(:HUD_REFRESH_DELAY_SECONDS)
  HUD_REFRESH_DELAY_SECONDS = 0.9
  remove_const(:HUD_MAX_VISIBLE_ROWS) if const_defined?(:HUD_MAX_VISIBLE_ROWS)
  HUD_MAX_VISIBLE_ROWS = 15
  remove_const(:HUD_MAX_BUILD_ROWS) if const_defined?(:HUD_MAX_BUILD_ROWS)
  HUD_MAX_BUILD_ROWS = 24
  remove_const(:HUD_ENABLE_CACHE_PREWARM) if const_defined?(:HUD_ENABLE_CACHE_PREWARM)
  HUD_ENABLE_CACHE_PREWARM = false
  remove_const(:HUD_STARTUP_PROCESS_MODEL) if const_defined?(:HUD_STARTUP_PROCESS_MODEL)
  HUD_STARTUP_PROCESS_MODEL = false
  remove_const(:HUD_PANEL_WIDTH) if const_defined?(:HUD_PANEL_WIDTH)
  HUD_PANEL_WIDTH = 460
  remove_const(:HUD_PANEL_PADDING) if const_defined?(:HUD_PANEL_PADDING)
  HUD_PANEL_PADDING = 10
  remove_const(:HUD_ROW_HEIGHT) if const_defined?(:HUD_ROW_HEIGHT)
  HUD_ROW_HEIGHT = 26
  remove_const(:HUD_TITLE_HEIGHT) if const_defined?(:HUD_TITLE_HEIGHT)
  HUD_TITLE_HEIGHT = 20
  remove_const(:HUD_HEADER_HEIGHT) if const_defined?(:HUD_HEADER_HEIGHT)
  HUD_HEADER_HEIGHT = 20
  remove_const(:HUD_NAME_COLUMN_WIDTH) if const_defined?(:HUD_NAME_COLUMN_WIDTH)
  HUD_NAME_COLUMN_WIDTH = 280
  remove_const(:HUD_NOTE_COLUMN_WIDTH) if const_defined?(:HUD_NOTE_COLUMN_WIDTH)
  HUD_NOTE_COLUMN_WIDTH = 80

  if defined?(Sketchup::Color)
    remove_const(:HUD_COLOR_PANEL) if const_defined?(:HUD_COLOR_PANEL)
    HUD_COLOR_PANEL = Sketchup::Color.new(188, 188, 194, 230)
    remove_const(:HUD_COLOR_TITLE) if const_defined?(:HUD_COLOR_TITLE)
    HUD_COLOR_TITLE = Sketchup::Color.new(18, 18, 20)
    remove_const(:HUD_COLOR_HEADER_BG) if const_defined?(:HUD_COLOR_HEADER_BG)
    HUD_COLOR_HEADER_BG = Sketchup::Color.new(74, 79, 148, 235)
    remove_const(:HUD_COLOR_WHITE) if const_defined?(:HUD_COLOR_WHITE)
    HUD_COLOR_WHITE = Sketchup::Color.new(255, 255, 255)
    remove_const(:HUD_COLOR_EMPTY_TEXT) if const_defined?(:HUD_COLOR_EMPTY_TEXT)
    HUD_COLOR_EMPTY_TEXT = Sketchup::Color.new(35, 35, 38)
    remove_const(:HUD_COLOR_PRODUCT_BG) if const_defined?(:HUD_COLOR_PRODUCT_BG)
    HUD_COLOR_PRODUCT_BG = Sketchup::Color.new(224, 224, 228, 230)
    remove_const(:HUD_COLOR_PRODUCT_TEXT) if const_defined?(:HUD_COLOR_PRODUCT_TEXT)
    HUD_COLOR_PRODUCT_TEXT = Sketchup::Color.new(20, 20, 24)
    remove_const(:HUD_COLOR_ROW_BG) if const_defined?(:HUD_COLOR_ROW_BG)
    HUD_COLOR_ROW_BG = Sketchup::Color.new(238, 238, 240, 225)
    remove_const(:HUD_COLOR_ROW_TEXT) if const_defined?(:HUD_COLOR_ROW_TEXT)
    HUD_COLOR_ROW_TEXT = Sketchup::Color.new(10, 10, 12)
    remove_const(:HUD_COLOR_SUB_TEXT) if const_defined?(:HUD_COLOR_SUB_TEXT)
    HUD_COLOR_SUB_TEXT = Sketchup::Color.new(15, 15, 18)
    remove_const(:HUD_COLOR_NOTE_TEXT) if const_defined?(:HUD_COLOR_NOTE_TEXT)
    HUD_COLOR_NOTE_TEXT = Sketchup::Color.new(65, 65, 70)
    remove_const(:HUD_COLOR_MORE_TEXT) if const_defined?(:HUD_COLOR_MORE_TEXT)
    HUD_COLOR_MORE_TEXT = Sketchup::Color.new(80, 80, 84)
    remove_const(:HUD_COLOR_STATUS_OK) if const_defined?(:HUD_COLOR_STATUS_OK)
    HUD_COLOR_STATUS_OK = Sketchup::Color.new(0, 86, 168, 235)
    remove_const(:HUD_COLOR_STATUS_SPEC) if const_defined?(:HUD_COLOR_STATUS_SPEC)
    HUD_COLOR_STATUS_SPEC = Sketchup::Color.new(241, 196, 15, 235)
    remove_const(:HUD_COLOR_STATUS_UPDATE) if const_defined?(:HUD_COLOR_STATUS_UPDATE)
    HUD_COLOR_STATUS_UPDATE = Sketchup::Color.new(211, 84, 0, 235)
    remove_const(:HUD_COLOR_STATUS_MISSING) if const_defined?(:HUD_COLOR_STATUS_MISSING)
    HUD_COLOR_STATUS_MISSING = Sketchup::Color.new(192, 57, 43, 235)
    remove_const(:HUD_COLOR_DARK_STATUS_TEXT) if const_defined?(:HUD_COLOR_DARK_STATUS_TEXT)
    HUD_COLOR_DARK_STATUS_TEXT = Sketchup::Color.new(20, 20, 20)
    remove_const(:HUD_STATUS_DRAW_STYLES) if const_defined?(:HUD_STATUS_DRAW_STYLES)
    HUD_STATUS_DRAW_STYLES = {
      "OK" => [HUD_COLOR_STATUS_OK, HUD_COLOR_WHITE, "OK"],
      "SPEC" => [HUD_COLOR_STATUS_SPEC, HUD_COLOR_DARK_STATUS_TEXT, "SPEC"],
      "UPDATE" => [HUD_COLOR_STATUS_UPDATE, HUD_COLOR_WHITE, "UPDATE"],
      "THIEU" => [HUD_COLOR_STATUS_MISSING, HUD_COLOR_WHITE, "THIEU"]
    }.freeze
  end
end

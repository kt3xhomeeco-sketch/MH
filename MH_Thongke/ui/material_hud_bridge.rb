# encoding: UTF-8
# Compatibility entry points only. The standalone HUD never loads Thongke.
module MH_Thongke
  def self.standalone_material_hud
    require File.expand_path('../../MH_MaterialHUD/main.rb', __dir__)
    MH::MaterialHUD
  end

  def self.show_import_material_hud(_product_code = nil)
    standalone_material_hud.toggle
  end

  def self.open_import_material_hud(_product_code = nil)
    standalone_material_hud.show
  end

  def self.show_import_material_overlay(_product_code = nil, force_enable = nil)
    hud = standalone_material_hud
    force_enable.nil? ? hud.toggle : force_enable ? hud.show : hud.hide
  end

  # Deliberately false: Thongke observers must not schedule work for this HUD.
  def self.material_overlay_visible?; false; end
  def self.material_hud_visible?; false; end
  def self.refresh_import_material_hud(*); end
  def self.refresh_material_overlay_data(*); end

  # Mini accessory dialog still uses this screen-size utility.
  def self.import_material_hud_screen_size
    require 'fiddle'
    library = Fiddle.dlopen('user32')
    metric = Fiddle::Function.new(library['GetSystemMetrics'], [Fiddle::TYPE_INT], Fiddle::TYPE_INT)
    [metric.call(0), metric.call(1)]
  rescue
    [nil, nil]
  end

  # Retire any already-running old overlay/timers on live reload.
  @material_overlay.enabled = false if @material_overlay
  %i[@material_hud_prewarm_timer @mini_hud_refresh_timer @mini_hud_light_refresh_timer].each do |name|
    timer = instance_variable_get(name)
    UI.stop_timer(timer) if timer
    instance_variable_set(name, nil)
  end
  detach_observers_if_idle if respond_to?(:detach_observers_if_idle)
end

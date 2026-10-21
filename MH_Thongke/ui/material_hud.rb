# encoding: utf-8
# MH_Thongke - Material HUD runtime cleanup.

module MH_Thongke
  begin
    UI.stop_timer(@material_hud_prewarm_timer) if defined?(UI) && @material_hud_prewarm_timer
    UI.stop_timer(@mini_hud_refresh_timer) if defined?(UI) && @mini_hud_refresh_timer
    UI.stop_timer(@mini_hud_light_refresh_timer) if defined?(UI) && @mini_hud_light_refresh_timer
    if @material_overlay && @material_overlay.respond_to?(:enabled=)
      @material_overlay.enabled = false
      Sketchup.active_model.active_view.invalidate rescue nil
    end
  rescue
  ensure
    @material_hud_prewarm_timer = nil
    @mini_hud_refresh_timer = nil
    @mini_hud_light_refresh_timer = nil
    @material_hud_prewarm_running = false
    @material_overlay_refresh_busy = false
    @mini_hud_refresh_busy = false
    @mini_hud_refresh_pending = nil
    @material_hud_lazy_open = false
  end
end


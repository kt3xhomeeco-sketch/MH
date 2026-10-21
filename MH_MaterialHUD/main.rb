# encoding: UTF-8
require 'sketchup.rb'
require File.expand_path('../MH_shared.rb', __dir__)

module MH
  module MaterialHUD
    stop_timers if respond_to?(:stop_timers)
    @product_store.dispose if @product_store
    @product_store = nil
    %w[acceptances data model_index product_store runtime viewport].each { |file| load File.join(__dir__, "#{file}.rb") }
    migrate_acceptances

    ModelHub.subscribe(:material_hud,
      on_selection: ->(_) { schedule_refresh if mode == 'select' },
      on_view: ->(_) { view_changed },
      on_model: ->(_) { model_changed },
      visible: -> { true })

    unless @menu_registered
      menu = UI.menu('Extensions').add_submenu('MH Material HUD')
      command = UI::Command.new('Material HUD — bật / tắt') { toggle }
      command.tooltip = 'Bật / tắt Material HUD — Tab: View / Select'
      command.status_bar_text = 'Bấm lần 1 bật, lần 2 tắt Material HUD.'
      command.small_icon = command.large_icon = File.join(__dir__, 'icon.svg')
      menu.add_item(command)
      menu.add_item('Tắt Material HUD') { hide }
      menu.add_item('View / Select') { toggle_mode }
      menu.add_item('Chọn JSON dùng chung...') { choose_json }
      menu.add_item('Reload JSON') { reload_json }
      @toolbar = UI::Toolbar.new('MH Material HUD')
      @toolbar.add_item(command)
      @toolbar.restore
      @menu_registered = true
    end
  end
end

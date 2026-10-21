# frozen_string_literal: true

plugin = File.expand_path('..', __dir__)
app = MH::CAD2Module
load File.join(plugin, 'main.rb')
app.instance_variable_get(:@manager)&.close
UI.start_timer(0.4, false) do
  dialog = app.make_dialog('MH CAD2Module — Quản lý', 'manager.html', 1100, 780, 'manager')
  dialog.add_action_callback('qa_ready') do |_context, text|
    app::Storage.write_json(File.join(plugin, 'outputs', 'native-ui-result.json'), JSON.parse(text))
  end
  app.instance_variable_set(:@manager, dialog)
  dialog.show
  app.publish('Sẵn sàng: Nhập mã SP hoặc Quét chọn nét CAD trong model.')
  UI.start_timer(0.8, false) do
    dialog.execute_script("(()=>{const b=document.querySelector('#check-view');const enabled=!!b&&!b.disabled;if(enabled)b.click();const on=b?.getAttribute('aria-pressed')==='true';if(enabled)b.click();window.sketchup.qa_ready(JSON.stringify({title:document.title,products:document.querySelectorAll('#products tr').length,modules:document.querySelectorAll('#modules tr').length,canvas:!!document.querySelector('#cad'),check_view_enabled:enabled,check_view_toggle:on&&b?.getAttribute('aria-pressed')==='false',errors:document.querySelectorAll('.error-item').length,overflow:document.body.scrollWidth>innerWidth+1}));})();")
  end
end
puts 'Native HtmlDialog check queued.'

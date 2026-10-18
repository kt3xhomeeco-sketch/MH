# frozen_string_literal: true

require 'json'
plugin = File.expand_path('..', __dir__)
app = MH::CAD2Module
%w[settings storage jobs placement model corrections templates selection_source scan_tool main].each do |name|
  load File.join(plugin, name + '.rb')
end
model = Sketchup.active_model
baseline = model.entities.map(&:persistent_id).sort
config = app::Settings.read
if config['sources'].empty? && File.file?('E:/MAC/OneDrive/Desktop/Drawing1.dwg')
  app::Settings.save('sources' => ['E:/MAC/OneDrive/Desktop/Drawing1.dwg'])
end
app.manager
dialog = app.instance_variable_get(:@manager)
dialog.add_action_callback('qa_native') do |_context, text|
  data = JSON.parse(text)
  data['geometry_unchanged'] = model.entities.map(&:persistent_id).sort == baseline
  app::Storage.write_json(File.join(plugin, 'outputs', 'native-ui-result.json'), data)
end
app.scan do |job|
  products = app.products
  app::Storage.write_json(File.join(plugin, 'outputs', 'native-job-result.json'),
                         { 'status' => 'passed', 'library' => job[:root], 'products' => products.map { |p| p.slice('code', 'status', 'bounds') },
                           'geometry_unchanged' => model.entities.map(&:persistent_id).sort == baseline })
  UI.start_timer(0.6, false) do
    dialog.execute_script("window.sketchup.qa_native(JSON.stringify({title:document.title,products:document.querySelectorAll('#products tr').length,canvas:!!document.querySelector('#cad'),scan:!!document.querySelector('[data-action=scan_selection]'),errors:document.querySelectorAll('.error-item').length,overflow:document.body.scrollWidth>innerWidth+1}));")
  end
end
puts 'MH CAD2Module loaded; native asynchronous scan started.'

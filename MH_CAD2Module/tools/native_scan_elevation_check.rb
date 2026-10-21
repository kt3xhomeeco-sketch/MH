# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
load File.join(root, 'scan_annotations.rb')
load File.join(root, 'selection_source.rb')
app::Model.send(:remove_const, :DICT)
load File.join(root, 'model.rb')
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
selection = model.selection.to_a
settings_read = app::Settings.method(:read)
settings = settings_read.call(model)
source_sha = Digest::SHA256.file(model.path).hexdigest unless model.path.empty?
methods = %i[start_operation commit_operation abort_operation].to_h { |key| [key, [model.method(key), model.singleton_class.instance_methods(false).include?(key)]] }
qa_root = File.join(root, 'outputs/qae')
methods[:start_operation][0].call('CAD2Module: Kiểm Tra Quét Kết Hợp', true)
begin
  methods.each_key { |key| model.define_singleton_method(key) { |*_args| true } }
  app::Settings.define_singleton_method(:read) { |m = Sketchup.active_model| settings_read.call(m).merge('library' => qa_root, 'build_elevation' => true) }
  fixture = JSON.parse(File.read(File.join(root, 'outputs/scan-elevation-fixture.json'), encoding: 'UTF-8'))
  group = model.entities.add_group
  group.name = 'QA ONLY — aborted combined scan'
  group.transformation = Geom::Transformation.translation([6000.mm, -2000.mm, 73.mm])
  symbols = fixture['scan_annotations']['objects'].select { |obj| obj['symbol'] }
  fixture['lines'].each do |line|
    next if symbols.any? { |obj| line['path'] == obj['path'] }
    group.entities.add_line((line['a'] + [0]).map(&:mm), (line['b'] + [0]).map(&:mm))
  end
  title_entities = []
  fixture['scan_annotations']['objects'].select { |obj| obj['text'] }.each do |text|
    if text['text'].include?('BỎ CÁNH')
      title = group.entities.add_group
      title.entities.add_line([0, 0, 0], [1, 1, 0])
      title.transformation = Geom::Transformation.translation((text['point'] + [0]).map(&:mm))
      title.set_attribute('Curic Single-Line Text', 'text', text['text'])
    else
      title = group.entities.add_text(text['text'], (text['point'] + [0]).map(&:mm))
    end
    title_entities << title
  end
  native_symbols = []
  symbols.each do |symbol|
    item = group.entities.add_group
    item.name = 'SECTION MARK ' + symbol['handle']
    if symbol['handle'] == 'C1'
      item.transformation = Geom::Transformation.axes([4400.mm, 1000.mm, 0], Geom::Vector3d.new(0, 1, 0), Geom::Vector3d.new(-1, 0, 0), Geom::Vector3d.new(0, 0, 1))
      item.entities.add_line([0, 0, 0], [2400.mm, 0, 0])
      { '1' => 'wrong', '2' => 'wrong', '4' => '1', '5' => '1' }.each { |key, value| item.set_attribute('CAD attributes', key, value) }
    else
      symbol['segments'].each { |line| item.entities.add_line((line['a'] + [0]).map(&:mm), (line['b'] + [0]).map(&:mm)) }
      symbol['attributes'].each { |key, value| item.set_attribute('CAD attributes', key, value) }
    end
    native_symbols << item
  end
  native_symbols.last.definition.set_attribute('CAD attributes', '1', 'default-must-not-override-instance')
  model.selection.clear; model.selection.add(group)
  geometry = app::SelectionSource.capture(model)
  raise 'Missing native annotation watches' unless geometry['annotation_watch'].length == 8
  raise 'Wrong native projection/offset' unless geometry['plane'] == 'XY' && (geometry['plane_offset_mm'] - 73).abs < 0.01
  app::SelectionSource.validate_watch(geometry['source_watch'], model)
  app::ScanAnnotations.validate_watch(geometry['annotation_watch'], model)
  text = title_entities.first
  original = text.text
  text.text = original + ' changed'
  stale_text_rejected = false
  begin
    app::ScanAnnotations.validate_watch(geometry['annotation_watch'], model)
  rescue ArgumentError
    stale_text_rejected = true
    changed = app::SelectionSource.capture(model)
    raise 'Text change did not invalidate content hash' if changed['hash'] == geometry['hash']
  ensure
    text.text = original
  end
  raise 'Stale text accepted' unless stale_text_rejected
  mark = native_symbols.last
  original = mark.get_attribute('CAD attributes', '1')
  mark.set_attribute('CAD attributes', '1', '9')
  stale_symbol_rejected = false
  begin
    app::ScanAnnotations.validate_watch(geometry['annotation_watch'], model)
  rescue ArgumentError
    stale_symbol_rejected = true
  ensure
    mark.set_attribute('CAD attributes', '1', original)
  end
  raise 'Stale symbol accepted' unless stale_symbol_rejected
  title = title_entities.find { |entity| entity.is_a?(Sketchup::Group) }
  original_transform = title.transformation
  title.transformation = Geom::Transformation.translation([10.mm, 0, 0]) * original_transform
  moved_title_rejected = false
  begin
    app::ScanAnnotations.validate_watch(geometry['annotation_watch'], model)
  rescue ArgumentError
    moved_title_rejected = true
  ensure
    title.transformation = original_transform
  end
  raise 'Moved title accepted' unless moved_title_rejected
  # A clipped symbol cannot supply a height even if its insertion is selected.
  symbol = geometry['scan_annotations']['objects'].find { |obj| obj['symbol'] }
  raw = symbols.first
  sample = raw.merge('point' => [0, 0, 73], 'segments' => [{ 'handle' => 'sample', 'a' => [0, 0, 73], 'b' => [0, 1000, 73] }])
  point = model.active_view.screen_coords(Geom::Point3d.new(0, 0, 73.mm))
  clipped = app::ScanAnnotations.project([sample], [0, 1], 73, 2, [point.x - 1, point.y - 1, point.x + 1, point.y + 1], model)
  raise 'Partial symbol accepted' unless clipped['objects'].empty? && !clipped['issues'].empty?
  app::Storage.write_json(File.join(root, 'outputs/scan-elevation-native-request.json'), geometry)
  request_path = File.join(qa_root, 'request.json'); response_path = File.join(qa_root, 'response.json')
  request = app::SelectionSource.build_request(geometry).merge('library' => qa_root, 'build_plan' => true, 'build_elevation' => true)
  app::Storage.write_json(request_path, request)
  python = app::Settings.python(settings)
  pythonw = python.sub(/python\.exe\z/i, 'pythonw.exe'); python = pythonw if File.file?(pythonw)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  pid = Process.spawn(python, '-X', 'utf8', File.join(root, 'worker/main.py'), '--request', request_path, '--response', response_path, out: File::NULL, err: File::NULL)
  Process.waitpid(pid)
  worker_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  result = JSON.parse(File.read(response_path, encoding: 'UTF-8'))
  raise result['error'].to_s unless result['ok']
  product = result.dig('analyses', 0, 'products', 0)
  raise 'Did not measure combined scan' unless product.dig('geometry_pipeline', 'horizontal', 'status') == 'measured'
  raise 'Wrong source origin' unless product.dig('placement', 'origin_mm') == [6000, -1800]
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  built = app::Model.build(product, qa_root, app::Ids.uuid, model)
  native_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  raise 'Non-solid combined output' unless built.members.length == 4 && built.members.all?(&:manifold?)
  state = app::Model.state(built)
  raise 'Lost heights' unless state['modules'].map { |part| part['size'][2].round } == [1000, 1400, 1200, 1200]
  raise 'Lost levels' unless state['modules'].map { |part| part['origin'][2].round } == [0, 1000, 0, 1200]
  raise 'Wrong solid volume' unless (built.members.sum { |part| part.volume * 25.4**3 } - 1618 * 600 * 2400).abs < 1
  app::Storage.write_json(File.join(root, 'outputs/scan-elevation-native-product.json'), product)
  receipt = { passed: true, source_edges: geometry['lines'].length, capture_seconds: geometry['capture_seconds'],
              scan_capture: product['scan_capture'], worker_seconds: worker_seconds, native_seconds: native_seconds,
              modules: 4, heights_mm: [1000, 1400, 1200, 1200], levels_mm: [0, 1000, 0, 1200],
              actual_source_placement: true, stale_text_rejected: stale_text_rejected, stale_symbol_rejected: stale_symbol_rejected,
              changed_text_invalidates_hash: true, moved_title_rejected: moved_title_rejected, instance_attributes_override_definition: true,
              partial_symbol_rejected: true, rotated_symbol_attributes: true, live_source_watch: true }
ensure
  app::Settings.define_singleton_method(:read, settings_read)
  methods.each { |key, (method, owned)| owned ? model.define_singleton_method(key, method) : model.singleton_class.send(:remove_method, key) }
  methods[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'Registry changed' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
raise 'Settings changed' unless settings == settings_read.call(model)
raise 'Source file changed' if source_sha && source_sha != Digest::SHA256.file(model.path).hexdigest
receipt[:user_model_registry_selection_settings_file_preserved] = true
app::Storage.write_json(File.join(root, 'outputs/scan-elevation-native-result.json'), receipt)
puts JSON.generate(receipt)

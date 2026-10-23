# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Wrong source' unless model.path.tr('\\', '/') == 'E:/MAC/OneDrive/Desktop/Untitled1.skp'
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
selection = model.selection.to_a
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
sha = Digest::SHA256.file(model.path).hexdigest
begin
  model.selection.clear
  model.selection.add(model.entities.to_a)
  rejected = false
  begin
    app::SelectionSource.capture(model)
  rescue ArgumentError => error
    rejected = error.message.include?('mặt phẳng XY/XZ/YZ')
    message = error.message
  end
  raise 'Nonplanar source was accepted as a plan' unless rejected
ensure
  model.selection.clear
  model.selection.add(selection.select(&:valid?))
end
raise 'Geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'Registry changed' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
raise 'File changed' unless sha == Digest::SHA256.file(model.path).hexdigest
result = { passed: true, path: model.path, sha256: sha, kind: '3D cabinet, not a 2D CAD plan',
           size_mm: [600, 580, 740], scan_rejected_with_reason: message, file_geometry_registry_selection_unchanged: true }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs/untitled1-source-result.json'), result)
puts JSON.generate(result)

# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
load File.join(root, 'plan_profile.rb')
load File.join(root, 'placement.rb')
app::ManualBoxes.send(:remove_const, :STOCK)
app::ManualBoxes.const_set(:STOCK, [3, 6, 8, 9, 12, 15, 18, 25, 36].freeze)
cases = JSON.parse(File.read(File.join(root, 'outputs', 'stock-arc-native-fixtures.json'), encoding: 'UTF-8'))
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
selection = model.selection.to_a
results = []
model.start_operation('CAD2Module: Kiểm Tra Tấm Cong Và Khoảng Cách Ván', true)
begin
  cases.each do |test|
    part = test['part']; stock = test['stock']
    group = app::Model.cube(model.entities, part)
    raise 'Not an independent solid' unless group.parent == model && group.manifold?
    curves = group.entities.grep(Sketchup::Edge).map(&:curve).compact.uniq.grep(Sketchup::ArcCurve)
    raise 'Circular boundaries were tessellated into disconnected lines' unless curves.length == 4
    raise 'Measured concentric radii changed' unless curves.all? { |c| [100, 100 + stock].any? { |r| (c.radius.to_mm - r).abs < 0.01 } }
    size = [group.bounds.width, group.bounds.height, group.bounds.depth].map(&:to_mm)
    raise 'Analytic arc extrema not retained in solid bounds' unless size.zip(part['size']).all? { |a, b| (a - b).abs < 0.01 }
    measured = app::PlanProfile.measured(group, Geom::Transformation.new)
    raise 'Manual feedback lost concentric thickness' unless (app::PlanProfile.concentric_thickness(measured['plan_profile']) - stock).abs < 0.01
    boxes = [measured, { 'origin' => [500, 0, 0], 'size' => [1000, 600, 1600] }]
    capture = app::ManualBoxes.parts({ 'boxes' => boxes }, {})
    raise 'Curved board not classified by radial thickness' unless capture['modules'].length == 1 && capture['trim_parts'].first['stock_thickness_mm'] == stock
    results << { stock_mm: stock, solid: true, arc_curves: curves.length, extrema_preserved: true, feedback_stock: true }
  end
ensure
  model.abort_operation
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
receipt = { passed: true, cases: results, user_geometry_unchanged: true }
app::Storage.write_json(File.join(root, 'outputs', 'stock-arc-native-result.json'), receipt)
puts JSON.generate(receipt)

# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
load File.join(root, 'jobs.rb')
load File.join(root, 'main.rb')
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
rows = []
cancel_called = false
finish = lambda do |error = nil|
  result = { passed: error.nil?, jobs: rows, error: error, user_geometry_registry_unchanged: baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] } && registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h }
  result[:passed] &&= result[:user_geometry_registry_unchanged]
  app::Storage.write_json(File.join(root, 'outputs/resident-native-result.json'), result)
end
queue = nil
queue = lambda do |index|
  code = index == 1 ? 'SP11' : 'SP08'
  app::Jobs.start('analyze', 'targets' => [code], 'build_elevation' => false) do |result, _job|
    begin
      raise result['error'].to_s unless result['ok'] && Array(result['errors']).empty?
      product = result.fetch('analyses').first.fetch('products').first
      children = product['plan_results'] || [product]
      raise 'Wrong source/view count' unless product['code'] == code && children.length == (code == 'SP11' ? 4 : 2)
      row = { code: code, worker: result['worker'], cache: product['source_cache'], processing: children.map { |p| p['processing_times'] } }
      rows << row
      if index < 2
        raise 'Worker PID changed unexpectedly' if rows.map { |r| r[:worker]['pid'] }.uniq.length != 1
        queue.call(index + 1)
      elsif index == 2
        raise 'Warm worker not reused' unless rows.map { |r| r[:worker]['pid'] }.uniq.length == 1
        app::Jobs.start('geometry', 'geometry' => {}) { |_r, _j| cancel_called = true }
        app::Jobs.cancel
        raise 'Cancellation left busy state' if app::Jobs.busy?
        queue.call(3)
      else
        raise 'Canceled callback applied' if cancel_called
        raise 'Canceled worker reused' if rows.first[:worker]['pid'] == rows.last[:worker]['pid']
        finish.call
      end
    rescue StandardError => error
      finish.call(error.message)
    end
  end
end
queue.call(0)
puts 'Resident native check queued: cold/new SP/warm reuse/cancel/restart; no model build.'

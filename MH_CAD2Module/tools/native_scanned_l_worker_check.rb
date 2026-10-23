# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
load File.join(root, 'jobs.rb')
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
settings_read = app::Settings.method(:read)
settings = settings_read.call(model)
qa_root = File.join(root, 'outputs/qal') # Keep native Windows temporary paths below MAX_PATH.
source = JSON.parse(File.read(File.join(root, 'library/jobs/6a0d9623-f959-1865-937b-f9b97d854a9e/request.json'), encoding: 'UTF-8'))
# Captured source regression only; never apply these old entity IDs to another model.
source['geometry'].delete('source_watch')
values = source.slice('geometry', 'name', 'automatic_scan').merge('code' => 'SCAN-QA-L-WORKER', 'build_plan' => true, 'build_elevation' => false)
rows = []
queue = nil
queue = lambda do |index|
  app::Settings.define_singleton_method(:read) { |m = Sketchup.active_model| settings_read.call(m).merge('library' => qa_root) }
  begin
    app::Jobs.start('geometry', values) do |result, _job|
      begin
        product = result.dig('analyses', 0, 'products', 0)
        raise result['error'].to_s unless result['ok'] && product && product['status'] == 'ready'
        raise 'Wrong recovered parts' unless product['modules'].length == 7 && product['trim_parts'].length == 4
        rows << { worker: result['worker'], processing: product['processing_times'], modules: 7, auxiliary: 4 }
        if index.zero?
          queue.call(1)
        else
          raise 'Worker PID changed' unless rows.map { |r| r[:worker]['pid'] }.uniq.length == 1
          unchanged = baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] } && registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
          raise 'Model changed' unless unchanged && settings == settings_read.call(model)
          app::Storage.write_json(File.join(root, 'outputs/scanned-l-worker-result.json'), passed: true, jobs: rows, model_settings_unchanged: true)
        end
      rescue StandardError => error
        app::Storage.write_json(File.join(root, 'outputs/scanned-l-worker-result.json'), passed: false, jobs: rows, error: error.message)
      end
    end
  ensure
    app::Settings.define_singleton_method(:read, settings_read)
  end
end
queue.call(0)
puts 'Captured L source: cold/warm worker QA queued, no model writes.'

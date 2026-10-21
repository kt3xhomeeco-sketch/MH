# encoding: UTF-8
require 'json'
require_relative '../reader'

project = File.expand_path('..', __dir__)
folder = File.join(project, 'outputs', 'library-016')
functions = Hash.new(0)
prefixes = Hash.new(0)
rows = JSON.parse(File.read(File.join(folder, 'manifest.json'), encoding: 'UTF-8')).map do |file|
  response = JSON.parse(File.read(file['capture'], encoding: 'bom|utf-8'))
  data = response['data']
  formulas = []
  if data
    data.fetch('definitions').each_value do |definition|
      attrs = [definition['attributes'] || {}, *Array(definition['nodes']).map { |node| node['attributes'] || {} }]
      attrs.each do |attributes|
        attributes.each do |key, value|
          prefixes[key.split('/').first] += 1
          next unless key.match?(/dynamic_attributes\/_.+_formula\z/) && value.is_a?(String)
          formulas << value
          value.scan(/\b([a-z_][a-z_0-9]*)\s*\(/i).flatten.each { |name| functions[name.downcase] += 1 }
        end
      end
    end
  end
  row = file.slice('relative', 'capture', 'ok', 'source_unchanged').merge('formula_count' => formulas.uniq.length)
  begin
    sample = MH::ModuleStudio::Reader.from_bridge(data, label: file['relative'], parameter: nil, path: file['path'])
    row['parts'] = sample['parts'].length
    row['controls'] = MH::ModuleStudio::Core.dc_controls(sample).length
    begin
      engine = MH::ModuleStudio::Core.learn_module([sample])
      row['engine_keys'] = engine['rules'].keys
    rescue StandardError => error
      row['engine_error'] = error.message
    end
  rescue StandardError => error
    row['read_error'] = error.message
  end
  row
end
report = { 'files' => rows, 'functions' => functions.sort.to_h, 'attribute_prefixes' => prefixes.sort.to_h }
File.write(File.join(folder, 'analysis-after.json'), JSON.pretty_generate(report))
puts JSON.generate('files' => rows.length, 'files_with_formulas' => rows.count { |row| row['formula_count'].positive? },
                   'engine_ok' => rows.count { |row| row['engine_keys'] }, 'read_errors' => rows.count { |row| row['read_error'] },
                   'functions' => functions.length, 'prefixes' => prefixes.keys)

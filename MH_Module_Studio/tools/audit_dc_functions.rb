# encoding: UTF-8
# Read-only portable audit. SDK bounds are not native geometry certification.
require 'json'
require 'digest'
require 'fileutils'
require_relative '../reader'

project = File.expand_path('..', __dir__)
manifest = JSON.parse(File.read(File.join(project, 'outputs', 'library-016', 'manifest.json'), encoding: 'UTF-8'))
output = ARGV.fetch(0)
profiles = ARGV[1] ? JSON.parse(File.read(ARGV[1], encoding: 'UTF-8')).fetch('files').to_h { |row| [row['relative'], row] } : {}
files = manifest.map do |file|
  row = file.slice('relative', 'sha256')
  begin
    row['source_unchanged'] = Digest::SHA256.file(file.fetch('path')).hexdigest == file.fetch('sha256')
    raise MH::ModuleStudio::Core::Error, 'Stale SDK capture: source hash changed.' unless row['source_unchanged']
    capture = JSON.parse(File.read(file.fetch('capture'), encoding: 'bom|utf-8'))
    raise MH::ModuleStudio::Core::Error, 'SDK capture failed.' unless capture['ok']
    sample = MH::ModuleStudio::Reader.from_bridge(capture.fetch('data'), label: file['relative'], parameter: nil, path: file['path'])
    profile = profiles[file['relative']]
    if profile && profile['sha256'] == file['sha256']
      sample['function_aliases'] = sample.fetch('function_aliases', {}).merge(profile.fetch('aliases', {}))
      MH::ModuleStudio::DCFormulas.function_aliases(sample)
    end
    inventory = MH::ModuleStudio::Core.attribute_inventory(sample)
    row['unknown_functions'] = inventory['unknown_functions']
    row['formula_count'] = inventory['count']
    begin
      engine = MH::ModuleStudio::Core.learn_module([sample])
      row['compiled_parameters'] = engine['rules'].keys
    rescue MH::ModuleStudio::Core::Error => error
      row['compiler_error'] = error.message
    end
  rescue StandardError => error
    row['read_error'] = "#{error.class}: #{error.message}"
  end
  row
end
report = { 'kind' => 'sdk_compiler_audit_not_native_conversion', 'files' => files,
           'total' => files.length, 'compiled' => files.count { |row| row['compiled_parameters'] },
           'source_hashes_verified' => files.all? { |row| row['source_unchanged'] },
           'read_failures' => files.count { |row| row['read_error'] },
           'compiler_failures' => files.count { |row| row['compiler_error'] } }
FileUtils.mkdir_p(File.dirname(output))
File.write(output, JSON.pretty_generate(report))
puts JSON.generate(report.reject { |key, _value| key == 'files' })

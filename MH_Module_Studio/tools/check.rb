# frozen_string_literal: true

# Developer-only: stage exactly the shipped Ruby sources so SketchUp's package
# checks cannot accidentally inspect the other extensions in Plugins/.
require 'fileutils'
require 'rbconfig'
require 'json'

project = File.expand_path('..', __dir__)
Dir.chdir(project) do
  stage = File.join(project, 'outputs', 'lint-source')
  support = File.join(stage, 'MH_Module_Studio')
  FileUtils.mkdir_p(support)
  FileUtils.cp(File.join(project, '..', 'MH_Module_Studio.rb'), stage)
  manifest = JSON.parse(File.read('runtime_manifest.json', encoding: 'UTF-8'))
  runtime = manifest.fetch('calculation') + manifest.fetch('adapters')
  runtime.each do |name|
    FileUtils.cp(File.join(project, name), support)
  end

  sources = [File.join(stage, 'MH_Module_Studio.rb')] + runtime.map { |name| File.join(support, name) } + Dir['test/**/*.rb', 'tools/**/*.rb'].sort
  rubocop = Gem.bin_path('rubocop', 'rubocop', '1.92.0')
  abort 'RuboCop failed.' unless system(RbConfig.ruby, rubocop, '--config', '.rubocop.yml', '--force-exclusion', *sources)

  tests = "Dir['test/*_test.rb'].sort.each { |path| require File.expand_path(path) }"
  abort 'Ruby tests failed.' unless system(RbConfig.ruby, '-I', 'test', '-e', tests)
end

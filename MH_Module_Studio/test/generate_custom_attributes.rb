# encoding: UTF-8
require_relative '../core'
s=MH::ModuleStudio
root=File.expand_path('..',__dir__)
data=JSON.parse(File.read(File.join(__dir__,'fixtures/drawer-front-custom.json'),encoding:'UTF-8'))
rule=s::StudioCalculation.build_system([data])
state={'snapshots'=>[data],'rule'=>rule,'busy'=>false,'parametric_revision'=>1,
  'parametric_sheet'=>s::Parametric.sheet(rule,data),'message'=>'Custom ATT'}
folder=File.join(root,'outputs/session-068');Dir.mkdir(folder) unless File.directory?(folder)
File.write(File.join(folder,'drawer-ui-state.json'),JSON.pretty_generate(state))

# encoding: UTF-8
require 'fileutils'
require_relative 'fixtures'
require_relative '../parametric'

directory = File.expand_path('../outputs', __dir__)
FileUtils.mkdir_p(directory)
samples = StudioFixtures.samples
rule = StudioFixtures.rule
state = { 'snapshots' => samples, 'rule' => rule, 'plan' => nil, 'busy' => false,
          'message' => 'Dữ liệu kiểm thử tổng hợp: 3 mức độ dày, 8 quan hệ tiếp giáp. Chưa áp dụng vào model.' }
File.write(File.join(directory, 'ui-test-state.json'), JSON.pretty_generate(state), encoding: 'UTF-8')
File.write(File.join(directory, 'demo.mhmodule.json'), JSON.pretty_generate({ 'format' => MH::ModuleStudio::Core::FORMAT, 'version' => 1, 'snapshots' => samples, 'rule' => rule }), encoding: 'UTF-8')
puts directory

ordinary = StudioFixtures.cabinet(18)
system = MH::ModuleStudio::RuleSystem.build(ordinary)
File.write(File.join(directory, 'rules-ui-state.json'), JSON.pretty_generate({ 'snapshots' => [ordinary], 'rule' => system, 'plan' => nil, 'busy' => false, 'message' => 'Group thường · Đã nhận diện quy tắc.' }), encoding: 'UTF-8')
readable = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'readable_nested_dc.json'), encoding: 'UTF-8'))
att_system = MH::ModuleStudio::RuleSystem.build(readable, MH::ModuleStudio::Core.learn_module([readable]))
att_full_state = { 'snapshots' => [readable], 'rule' => att_system, 'plan' => nil, 'busy' => false, 'message' => 'ATT → Hệ quy tắc chung.',
                   'parametric_rows' => MH::ModuleStudio::Parametric.describe(att_system, readable) }
att_full_state['parametric_sheet'] = MH::ModuleStudio::Parametric.sheet(att_system, readable)
att_full_state['parametric_revision'] = 0
File.write(File.join(directory, 'rules-att-ui-state.json'), JSON.pretty_generate(att_full_state), encoding: 'UTF-8')
att_full_plan = MH::ModuleStudio::Core.plan(att_system, readable, 'hauday' => 10)
File.write(File.join(directory, 'rules-att-ui-preview-state.json'), JSON.pretty_generate(att_full_state.merge('plan' => att_full_plan,
           'parametric_preview_rows' => MH::ModuleStudio::Parametric.describe(att_system, readable, att_full_plan['target']),
           'parametric_sheet' => MH::ModuleStudio::Parametric.sheet(att_system, readable, att_full_plan))), encoding: 'UTF-8')
brace_key = readable['parts'].find { |part| part['name'] == 'Giằng Trước' }['key']
cell_rule = MH::ModuleStudio::Parametric.edit_part_formula(att_system, brace_key, 'lenz', 'giang + 10')
cell_plan = MH::ModuleStudio::Core.plan(cell_rule, readable, MH::ModuleStudio::Parametric.targets(cell_rule))
File.write(File.join(directory, 'cell-formula-ui-state.json'), JSON.pretty_generate(att_full_state.merge('rule' => cell_rule, 'plan' => cell_plan,
           'parametric_revision' => 2, 'parametric_sheet' => MH::ModuleStudio::Parametric.sheet(cell_rule, readable, cell_plan))), encoding: 'UTF-8')

dc_samples = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'dc_mixed_thickness.json'), encoding: 'UTF-8'))
dc_rule = MH::ModuleStudio::Core.learn_dc_parameter(dc_samples, 'ikqikbwfw7')
dc_state = { 'snapshots' => dc_samples, 'rule' => dc_rule, 'plan' => nil, 'busy' => false,
             'selected_dc_key' => 'ikqikbwfw7',
             'parameter_choices' => MH::ModuleStudio::Core.dc_thickness_parameters(dc_samples),
             'fixed_controls' => dc_rule['control_context'], 'fixed_controls_source' => 'rule',
             'message' => 'Học hậu từ mẫu 2 và 3; Hậu lùi giữ 18 mm.' }
File.write(File.join(directory, 'dc-ui-test-state.json'), JSON.pretty_generate(dc_state), encoding: 'UTF-8')

module_rule = MH::ModuleStudio::Core.learn_module(dc_samples)
module_state = dc_state.merge('rule' => module_rule, 'selected_dc_key' => nil,
                              'fixed_controls' => module_rule['control_context'],
                              'message' => 'Một module chứa bộ tham số chung: ván thùng, hậu, hậu lùi và kiểu lắp.')
File.write(File.join(directory, 'module-ui-test-state.json'), JSON.pretty_generate(module_state), encoding: 'UTF-8')

require_relative 'formula_fixtures'
att_sample = FormulaFixtures.snapshot
att_rule = MH::ModuleStudio::Core.learn_module([att_sample])
att_state = { 'snapshots' => [att_sample], 'rule' => att_rule, 'plan' => nil, 'busy' => false,
              'message' => 'Một DC: đọc ATT để sửa độ dày và Hậu lùi; không cần mẫu so sánh.' }
File.write(File.join(directory, 'att-ui-test-state.json'), JSON.pretty_generate(att_state), encoding: 'UTF-8')

# frozen_string_literal: true
require 'minitest/autorun'
require 'open3'
require 'rbconfig'

class ModuleStudioParametricNamesPanelTest < Minitest::Test
  def test_file_draft_names_need_no_live_root_and_keep_the_editable_snapshot_identity
    script = <<~'RUBY'
      $LOADED_FEATURES << 'sketchup.rb'
      def file_loaded?(*)
        true
      end
      require ARGV.fetch(0)
      s=MH::ModuleStudio
      snapshot=JSON.parse(File.read(ARGV.fetch(1),encoding:'UTF-8'))
      original=JSON.generate(snapshot)
      panel=s::Panel.new
      rule=s::RuleSystem.build(snapshot,s::Core.learn_module([snapshot]))
      panel.instance_variable_set(:@rule,rule)
      panel.instance_variable_set(:@snapshots,[snapshot])
      panel.instance_variable_set(:@module_name,'File đang sửa')
      key=snapshot['parts'].first['key']
      packet={'action'=>'rename_model','part_key'=>key,'name'=>'Chi tiết mới','rule_id'=>rule['id'],'snapshot_id'=>snapshot['id'],'revision'=>0}
      panel.request(packet)
      raise 'Detail rename erased module name' unless panel.instance_variable_get(:@module_name)=='File đang sửa'
      raise 'Snapshot rewritten' unless JSON.generate(snapshot)==original
      changed=panel.instance_variable_get(:@rule)
      raise 'Name missing' unless s::Parametric.sheet(changed,snapshot)['parts'].first['name']=='Chi tiết mới'
      panel.request(packet.merge('part_key'=>nil,'name'=>'Module mới','revision'=>1))
      changed=panel.instance_variable_get(:@rule)
      raise 'Title missing' unless changed['module_name']=='Module mới'
      raise 'ATT references changed' unless changed['formula_engine']==rule['formula_engine']
      raise 'Wrong revision' unless panel.instance_variable_get(:@parametric_revision)==2
      raise 'Formula edits no longer work' unless s::Core.plan(changed,snapshot,s::Parametric.targets(changed))['changed_count'].zero?
      begin
        panel.request(packet)
        raise 'Stale rename accepted'
      rescue s::Core::Error
      end
      begin
        panel.request(packet.merge('revision'=>2,'name'=>''))
        raise 'Blank name accepted'
      rescue s::Core::Error
      end
      raise 'Rejected rename poisoned sheet' unless s::Parametric.sheet(panel.instance_variable_get(:@rule),snapshot)['parts'].first['name']=='Chi tiết mới'
      puts 'ok'
    RUBY
    main=File.expand_path('../main.rb',__dir__)
    fixture=File.join(__dir__,'fixtures/readable_nested_dc.json')
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,main,fixture)
    assert status.success?,error
    assert_equal "ok\n",output
  end
end

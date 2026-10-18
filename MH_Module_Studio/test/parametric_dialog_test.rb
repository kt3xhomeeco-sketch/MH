# frozen_string_literal: true
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'json'

class ModuleStudioParametricDialogTest < Minitest::Test
  def test_dialog_reuse_reopen_shared_state_stale_edits_and_cancel_acknowledgement
    script = <<~'RUBY'
      $LOADED_FEATURES << 'sketchup.rb'
      def file_loaded?(_path)
        true
      end
      module UI
        def self.savepanel(*)
          nil
        end
        class HtmlDialog
          STYLE_DIALOG = 0
          attr_reader :messages, :callbacks, :file
          def initialize(**)
            @messages = []
            @callbacks = {}
            @visible = false
          end
          def set_file(file)
            @file = file
          end
          def add_action_callback(name, &block)
            @callbacks[name] = block
          end
          def set_on_closed(&block)
            @closed = block
          end
          def show
            @visible = true
          end
          def visible?
            @visible
          end
          def bring_to_front
          end
          def close
            @visible = false
            @callbacks.clear
            @closed.call
          end
          def defer_close
            @visible = false
            @callbacks.clear
          end
          def finish_close
            @closed.call
          end
          def execute_script(script)
            encoded = script.delete_prefix('window.receive(JSON.parse(').delete_suffix('));')
            @messages << JSON.parse(JSON.parse(encoded))
          end
        end
      end
      require ARGV.fetch(0)
      studio = MH::ModuleStudio
      snapshot = JSON.parse(File.read(ARGV.fetch(1), encoding: 'UTF-8'))
      panel = studio::Panel.new
      panel.instance_variable_set(:@snapshots, [snapshot])
      rule = studio::RuleSystem.build(snapshot, studio::Core.learn_module([snapshot]))
      panel.instance_variable_set(:@rule, rule)
      panel.show
      main = panel.instance_variable_get(:@dialog)
      panel.request('action' => 'open_parametric', 'parameter_key' => 'hauday')
      child = panel.instance_variable_get(:@parametric_dialog)
      child.callbacks['request'].call(nil, JSON.generate('action' => 'ready', 'surface' => 'parametric'))
      focused = child.messages.last['parametric_focus']
      panel.request('action' => 'open_parametric')
      reused = child.equal?(panel.instance_variable_get(:@parametric_dialog))
      rows = studio::Parametric.variables(rule)
      rows.first['name'] = 'Tên mới'
      packet = { 'action' => 'save_variables', 'rule_id' => rule['id'],
        'snapshot_id' => snapshot['id'], 'revision' => 0, 'variables' => rows }
      child.callbacks['request'].call(nil, JSON.generate(packet))
      saved = child.messages.last
      child.callbacks['request'].call(nil, JSON.generate(packet))
      stale = child.messages.last
      packet['revision'] = 1
      packet['snapshot_id'] = 'another-instance'
      child.callbacks['request'].call(nil, JSON.generate(packet))
      wrong_instance = child.messages.last
      child.close
      panel.request('action' => 'open_parametric')
      reopened = panel.instance_variable_get(:@parametric_dialog)
      reopened.callbacks['request'].call(nil, JSON.generate('action' => 'ready', 'surface' => 'parametric'))
      delayed = reopened
      delayed.defer_close
      panel.request('action' => 'open_parametric')
      replacement = panel.instance_variable_get(:@parametric_dialog)
      delayed.finish_close
      delayed_child_safe = panel.instance_variable_get(:@parametric_dialog).equal?(replacement)
      reopened = replacement
      reopened.callbacks['request'].call(nil, JSON.generate('action' => 'ready', 'surface' => 'parametric'))
      delayed_main = main
      delayed_main.defer_close
      panel.show
      replacement_main = panel.instance_variable_get(:@dialog)
      delayed_main.finish_close
      delayed_main_safe = panel.instance_variable_get(:@dialog).equal?(replacement_main)
      main = replacement_main
      retained = reopened.messages.last['parametric_sheet']['variables'].first['name']
      panel.request('action' => 'save')
      cancelled = reopened.messages.last
      synced = main.messages.last == cancelled
      main.close
      panel.request('action' => 'ready', 'surface' => 'parametric')
      puts JSON.generate('reused' => reused, 'reopened' => !child.equal?(reopened),
        'callbacks' => reopened.callbacks.keys, 'file' => reopened.file,
        'focused' => focused, 'saved_revision' => saved['parametric_revision'],
        'stale' => stale['error'], 'wrong_instance' => wrong_instance['error'],
        'retained' => retained, 'cancel_error' => cancelled['error'],
        'cancel_busy' => cancelled['busy'], 'synced' => synced,
        'delayed_child_safe' => delayed_child_safe, 'delayed_main_safe' => delayed_main_safe,
        'main_closed_sheet' => !!reopened.messages.last['parametric_sheet'])
    RUBY
    output, error, status = Open3.capture3(RbConfig.ruby, '-e', script,
      File.expand_path('../main.rb', __dir__), File.join(__dir__, 'fixtures/readable_nested_dc.json'))
    assert status.success?, error
    result = JSON.parse(output)
    assert result['reused']
    assert result['reopened']
    assert_equal ['request'], result['callbacks']
    assert_match(%r{ui/parametric.html\z}, result['file'])
    assert_equal 'hauday', result['focused']
    assert_equal 1, result['saved_revision']
    assert result['stale']
    assert result['wrong_instance']
    assert_equal 'Tên mới', result['retained']
    assert_equal false, result['cancel_error']
    assert_equal false, result['cancel_busy']
    assert result['synced']
    assert result['main_closed_sheet']
    assert result['delayed_child_safe']
    assert result['delayed_main_safe']
  end
end

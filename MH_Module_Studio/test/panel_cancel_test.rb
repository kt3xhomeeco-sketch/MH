# frozen_string_literal: true
require 'json'
require 'minitest/autorun'
require 'open3'
require 'rbconfig'

class ModuleStudioPanelCancelTest < Minitest::Test
  def test_canceling_skp_picker_releases_pending_request
    check_cancellation('open_skp')
  end

  def test_canceling_project_picker_releases_pending_request
    check_cancellation('open_project')
  end

  def test_canceling_save_picker_releases_pending_request
    check_cancellation('save')
  end

  def check_cancellation(action)
    # Isolate native API substitutes from the other tests and from SketchUp.
    script = <<~'RUBY'
      require 'json'
      $LOADED_FEATURES << 'sketchup.rb'
      def file_loaded?(_path)
        true
      end
      module UI
        def self.openpanel(*)
          nil
        end
        def self.savepanel(*)
          nil
        end
      end
      require ARGV.fetch(0)
      class RecordingDialog
        attr_reader :messages
        def initialize
          @messages = []
        end
        def execute_script(script)
          encoded = script.delete_prefix('window.receive(JSON.parse(').delete_suffix('));')
          @messages << JSON.parse(JSON.parse(encoded))
        end
      end
      panel = MH::ModuleStudio::Panel.new
      dialog = RecordingDialog.new
      panel.instance_variable_set(:@dialog, dialog)
      panel.instance_variable_set(:@snapshots, [{ 'id' => 'keep-sample' }])
      panel.instance_variable_set(:@rule, { 'id' => 'keep-rule' })
      panel.instance_variable_set(:@plan, { 'id' => 'keep-plan' })
      panel.request('action' => ARGV.fetch(1))
      puts JSON.generate(dialog.messages)
    RUBY
    main = File.expand_path('../main.rb', __dir__)
    output, error, status = Open3.capture3(RbConfig.ruby, '-e', script, main, action)
    assert status.success?, error
    replies = JSON.parse(output)
    assert_equal 1, replies.length, "Cancel #{action} must acknowledge the request to unlock the UI"
    state = replies.first
    assert_equal false, state['busy']
    assert_equal false, state['error']
    assert_equal [{ 'id' => 'keep-sample' }], state['snapshots']
    assert_equal({ 'id' => 'keep-rule' }, state['rule'])
    assert_equal({ 'id' => 'keep-plan' }, state['plan'])
  end
end

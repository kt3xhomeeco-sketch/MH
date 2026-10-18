# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'tmpdir'
require_relative '../jobs'
require_relative '../plan_rules'

module UI
  def self.start_timer(*) = 1
  def self.stop_timer(*) = nil
end

module MH::CAD2Module
  def self.publish(*) = nil
end

class PlanRulesTest < Minitest::Test
  def setup
    @rules = MH::CAD2Module::PlanRules
    %i[@pending @timer @errors].each { |key| @rules.instance_variable_set(key, nil) }
  end

  def test_acceptance_only_queues_and_deduplicates_before_worker_runs
    timers = []
    event = { 'path' => 'E:/chosen/history/accepted.json', 'analysis' => { 'build_stages' => { 'elevation' => false } } }
    MH::CAD2Module::Settings.stub(:resolve_library, ->(root) { root }) do
      UI.stub(:start_timer, ->(*args, &_block) { timers << args; 12 }) do
        2.times { @rules.enqueue(event) }
      end
    end
    assert_equal [[0.5, true]], timers
    assert_equal ['E:/chosen'], @rules.instance_variable_get(:@pending)
    calls = []
    MH::CAD2Module::Jobs.stub(:busy?, true) { @rules.drain }
    assert_equal ['E:/chosen'], @rules.instance_variable_get(:@pending)
    MH::CAD2Module::Jobs.stub(:busy?, false) do
      MH::CAD2Module::Jobs.stub(:start, ->(*args, &done) { calls << args; done.call({ 'ok' => true }, {}) }) { @rules.drain }
      @rules.drain
    end
    assert_equal [['learn_plan', { 'learning_library' => 'E:/chosen' }]], calls
    assert_nil @rules.instance_variable_get(:@timer)
  end

  def test_background_failure_is_status_only_and_does_not_raise
    @rules.instance_variable_set(:@pending, ['E:/chosen'])
    MH::CAD2Module::Jobs.stub(:busy?, false) do
      MH::CAD2Module::Jobs.stub(:start, ->(*) { raise IOError, 'worker unavailable' }) { @rules.drain }
    end
    assert_match(/worker unavailable/, @rules.instance_variable_get(:@errors)['E:/chosen'])
  end

  def test_status_reads_only_derived_summary_and_preserves_error
    Dir.mktmpdir do |root|
      path = File.join(root, 'rules', 'plan-v1', 'status.json')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.generate('active' => 1, 'waiting' => 2))
      MH::CAD2Module::Settings.stub(:resolve_library, root) do
        assert_equal 1, @rules.status(root)['active']
        File.write(path, 'broken')
        assert_match(/Chưa đọc/, @rules.status(root)['error'])
      end
    end
  end
end

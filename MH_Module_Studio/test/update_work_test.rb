# encoding: UTF-8
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'json'

class ModuleStudioUpdateWorkTest < Minitest::Test
  HARNESS=<<~'RUBY'
    module Sketchup
      class ModelObserver;end
      def self.active_model;$model;end
    end
    module UI
      def self.start_timer(*,&block);(@queue ||= []) << block;end
      def self.tick
        (@queue ||= []).shift&.call
        sleep(0.001)
      end
      def self.drain
        deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+10
        while MH::ModuleStudio::UpdateWork.pending?($model)
          raise 'Timed out' if Process.clock_gettime(Process::CLOCK_MONOTONIC)>deadline
          tick
        end
      end
    end
    require ARGV[0]
    require File.join(File.dirname(ARGV[0]), 'core')
    W=MH::ModuleStudio::UpdateWork
    Studio=MH::ModuleStudio
    RuleSystem=Studio::RuleSystem
    Core=Studio::Core
    class TestModel
      attr_reader :observer,:events
      attr_accessor :value
      def initialize;@value=10;@events=[];end
      def add_observer(observer);@observer=observer;end
      def start
        raise 'Nested transaction' if @open
        @saved=@value;@open=true;@events << 'start';@observer.onTransactionStart(self)
      end
      def commit_operation
        raise 'No transaction' unless @open
        @open=false;@events << ['commit',@value];@observer.onTransactionCommit(self)
      end
      def abort_operation
        @value=@saved;@open=false;@events << 'abort';@observer.onTransactionAbort(self)
      end
      def open?;@open;end
    end
    $model=TestModel.new
    $worker_threads=[]
    snapshot=JSON.parse(File.read(File.join(File.dirname(ARGV[0]),'test','fixtures','readable_nested_dc.json'),encoding:'UTF-8'))
    $rule=RuleSystem.build(snapshot)
    W.define_singleton_method(:dispatch) do |kind,args|
      $worker_threads << !Thread.current.equal?(Thread.main)
      # Enough pure work to exercise yielding under Ruby's shared GVL.
      5000.times { |i| Math.sqrt(i) }
      if kind==:rule
        raise 'Rule formula failed' if args.first['bad']
        return args.first
      end
      raise 'Invalid formula' if args.first=='bad'
      args.first*2
    end
    def rule_action(rule)
      lambda do
        $model.start
        $model.value=W.calculate(:rule,rule)
        W.commit($model)
      rescue W::Deferred,W::Prepared,StandardError
        $model.abort_operation
        raise
      end
    end
    def action(value)
      lambda do
        $model.start
        $model.value=-1
        $model.value=W.calculate(:plan,value)
        W.commit($model)
      rescue W::Deferred,W::Prepared,StandardError
        $model.abort_operation
        raise
      end
    end
  RUBY

  def run_case(body)
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',HARNESS+body,File.expand_path('../update_work.rb',__dir__))
    assert status.success?,error
    JSON.parse(output)
  end

  def test_worker_yields_without_an_open_transaction_and_only_final_geometry_commits
    result=run_case(<<~'RUBY')
      completed=[];W.submit($model,key: :scale,complete:->(s,e) { completed << [s,e&.message] },&action(300))
      ticks=0;visible=[]
      while W.pending?($model)
        UI.tick;ticks+=1
        raise 'Operation left open between callbacks' if $model.open?
        visible << $model.value
      end
      puts JSON.generate(value:$model.value,visible:visible.uniq,ticks:ticks,workers:$worker_threads,events:$model.events,completed:completed)
    RUBY
    assert_equal 600,result['value']
    assert_equal [10,600],result['visible']
    assert_operator result['ticks'],:>,2
    assert result['workers'].all?
    assert_equal [['commit',600]],result['events'].grep(Array)
    assert_equal [['done',nil]],result['completed']
  end

  def test_superseding_input_never_applies_old_result
    result=run_case(<<~'RUBY')
      completed=[]
      W.submit($model,key: :options,complete:->(s,_) { completed << s },&action(200))
      UI.tick
      W.submit($model,key: :options,complete:->(s,_) { completed << s },&action(20))
      UI.drain
      puts JSON.generate(value:$model.value,events:$model.events,completed:completed)
    RUBY
    assert_equal 40,result['value']
    assert_equal [['commit',40]],result['events'].grep(Array)
    assert_equal %w[superseded done],result['completed']
  end

  def test_sequential_calculations_are_all_prepared_before_one_atomic_commit
    result=run_case(<<~'RUBY')
      action=lambda do
        $model.start
        $model.value=W.calculate(:plan,100)
        $model.value=W.calculate(:scale,50)
        W.commit($model)
      rescue W::Deferred,W::Prepared,StandardError
        $model.abort_operation
        raise
      end
      W.submit($model,key: :multi,&action);UI.drain
      puts JSON.generate(value:$model.value,events:$model.events,workers:$worker_threads)
    RUBY
    assert_equal 100,result['value']
    assert_equal [['commit',100]],result['events'].grep(Array)
    assert result['workers'].all?
  end

  def test_external_undo_cancels_prepared_output_without_overwriting_user_geometry
    result=run_case(<<~'RUBY')
      completed=[];W.submit($model,key: :scale,complete:->(s,_) { completed << s },&action(200))
      UI.tick
      $model.value=7;$model.observer.onTransactionUndo($model)
      UI.drain
      puts JSON.generate(value:$model.value,events:$model.events,completed:completed)
    RUBY
    assert_equal 7,result['value']
    assert_empty result['events'].grep(Array)
    assert_equal ['cancelled'],result['completed']
  end

  def test_empty_native_operations_release_wait_and_formula_failure_is_atomic
    result=run_case(<<~'RUBY')
      completed=[];W.submit($model,key: :options,complete:->(s,e) { completed << [s,e&.message] },&action('bad'))
      $model.observer.onTransactionStart($model);UI.tick
      raise 'Ran during user operation' unless $model.events.empty?
      $model.observer.onTransactionEmpty($model);UI.drain
      puts JSON.generate(value:$model.value,events:$model.events,completed:completed)
    RUBY
    assert_equal 10,result['value']
    assert_empty result['events'].grep(Array)
    assert_equal [['error','Invalid formula']],result['completed']
  end

  def test_cached_results_are_owned_and_final_pass_rejects_a_cache_miss
    result=run_case(<<~'RUBY')
      cache={key:'cache',probe:true,cancelled:false,cache:{},results:{},canonical_rules:{},seeds:{},model:$model}
      digest=Digest::SHA256.hexdigest(Marshal.dump([300]))
      key=Digest::SHA256.hexdigest('plan'+digest)
      value=[[1]]
      cache[:cache][key]=JSON.generate('result'=>value)
      Thread.current[:mh_module_update]=cache
      first=W.calculate(:plan,300);first.first << 2
      second=W.calculate(:plan,300)
      begin
        W.calculate(:plan,301)
      rescue W::Deferred=>miss
        cache[:probe]=false
        error=begin;W.calculate(:plan,301);nil;rescue StandardError=>caught;caught;end
      ensure
        Thread.current[:mh_module_update]=nil
      end
      puts JSON.generate(first:first,second:second,error:error&.message,value:$model.value,events:$model.events)
    RUBY
    assert_equal [[[1,2]],[[1]]],result.values_at('first','second')
    assert_equal 'Dữ liệu dựng đã thay đổi. Đọc lại module rồi thử lại.',result['error']
    assert_equal 10,result['value']
    assert_empty result['events']
  end

  def test_async_rule_payloads_survive_the_worker_but_errors_report_their_message
    result=run_case(<<~'RUBY')
      completed=[];labels=[]
      W.submit($model,key: :rule,complete:->(s,e) { completed << [s,e&.message] }) do
        value=W.calculate(:rule,$rule)
        $model.value=value
        canonical=W.canonical_rule($rule)
        labels << (canonical && 'cached')
        raise 'Canonical rule changed' unless Core.rule!(JSON.parse(canonical))==$rule
      end
      UI.drain
      rule_result=$model.value
      $model.value=11
      W.submit($model,key: :bad_rule,complete:->(s,e) { completed << [s,e&.message] },&rule_action({'bad'=>true}))
      UI.drain
      puts JSON.generate(value:$model.value,rule:rule_result,completed:completed,labels:labels,workers:$worker_threads)
    RUBY
    assert_equal 'module_rule_system',result.dig('rule','kind')
    assert_equal 11,result['value']
    assert_equal [['done',nil],['error','Rule formula failed']],result['completed']
    assert_equal ['cached'],result['labels']
    assert result['workers'].all?
  end
end

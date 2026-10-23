# encoding: UTF-8
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'json'

# Real UpdateWork scheduling and the real AssemblyModelObserver run in a
# subprocess with a deterministic timer queue. The job bodies are recorders;
# submit/queue/advance/pending? and the observer generation are production code.
# This isolates the external-sync/options cancellation race.
class ModuleStudioExternalSyncOptionsRaceTest < Minitest::Test
  HARNESS=<<~'RUBY'
    module Sketchup
      class ModelObserver;end
      class AppObserver;end
      def self.active_model;$model;end
      def self.status_text;@status_text;end
      def self.status_text=(value);@status_text=value;end
    end
    module UI
      def self.start_timer(delay,*_, &block);timers << [delay,block];end
      def self.timers;@timers ||= [];end
      def self.run_observer_tick
        index=timers.index { |row| row[0]>=0.1 }
        return false unless index
        timers.delete_at(index)[1].call
        true
      end
      def self.run_options_tick
        index=timers.index { |row| row[0]<0.1 }
        return false unless index
        timers.delete_at(index)[1].call
        true
      end
      def self.drain(limit=2000)
        count=0
        while (row=timers.shift)
          count+=1
          raise 'timer storm' if count>limit
          row[1].call
        end
        count
      end
      def self.clear;timers.clear;end
    end
    require ARGV.fetch(0)
    Studio=MH::ModuleStudio
    W=Studio::UpdateWork
    $model=Struct.new(:active_path,:observer) do
      def add_observer(value);self.observer=value;end
      def valid?;true;end
    end.new(nil,nil)
    $events=[]
    $statuses=[]
    Studio::Assembly.define_singleton_method(:fingerprint) { |_model| 'same' }
    Studio::Assembly.define_singleton_method(:records) { |_model| [] }
    Studio::AssemblyContainers.define_singleton_method(:containers) { |_model| [] }
    Studio::ImportLinks.define_singleton_method(:root_frames) { |_model| {} }
    Studio::AssemblyContainers.define_singleton_method(:dangling_door_links) { |_model| [] }
    Studio::ImportLinks.define_singleton_method(:release_targets) { |*_args| {} }
    Studio::ImportLinks.define_singleton_method(:scaled_reservation_targets) { |*_args| {} }
    Studio::ScaleRedraw.define_singleton_method(:pending?) { |_model| false }
    original_submit=W.method(:submit)
    W.define_singleton_method(:submit) do |model,**options,&action|
      key=options[:key];inner=options[:complete]
      $events << "submit:#{key}"
      options[:complete]=lambda do |status,error|
        $events << "complete:#{key}:#{status}"
        $statuses << [key.to_s,status.to_s,error&.message]
        inner&.call(status,error)
      end
      original_submit.call(model,**options,&action)
    end
    def fresh_observer
      $model.observer=nil
      UI.clear
      $events.clear
      $statuses.clear
      Studio::Assembly::AssemblyModelObserver.new($model)
    end
    def run_hold(ticks)
      observer=fresh_observer
      runs=[]
      W.submit($model,key: :options,guard:-> { true }) { runs << 18.6 }
      observer.onTransactionCommit($model)
      observed=0
      ticks.times do
        break unless UI.run_observer_tick
        observed+=1
      end
      before={'pending'=>W.pending?($model),'runs'=>runs.dup,
              'statuses'=>$statuses.dup,'events'=>$events.dup,
              'timers'=>UI.timers.map(&:first)}
      ran_options=UI.run_options_tick
      UI.drain
      {'requested_ticks'=>ticks,'observed_ticks'=>observed,'ran_options'=>ran_options,
       'before_options'=>before,'runs'=>runs,'events'=>$events,'statuses'=>$statuses,
       'pending'=>W.pending?($model),'timers'=>UI.timers.length}
    end
    def run_stale_generation
      observer=fresh_observer
      runs=[]
      W.submit($model,key: :options,guard:-> { true }) { runs << 20.0 }
      observer.onTransactionCommit($model)
      # Undo/reset invalidates the generation of the already queued assembly timer.
      observer.reset
      observed=0
      40.times do
        break unless UI.run_observer_tick
        observed+=1
      end
      before={'pending'=>W.pending?($model),'statuses'=>$statuses.dup,
              'events'=>$events.dup,'timers'=>UI.timers.map(&:first)}
      UI.run_options_tick
      UI.drain
      {'observed_ticks'=>observed,'before_options'=>before,'runs'=>runs,
       'events'=>$events,'statuses'=>$statuses,'pending'=>W.pending?($model),
       'timers'=>UI.timers.length}
    end
    def run_latest_options
      observer=fresh_observer
      runs=[]
      W.submit($model,key: :options,guard:-> { true }) { runs << 18.6 }
      W.submit($model,key: :options,guard:-> { true }) { runs << 20.0 }
      observer.onTransactionCommit($model)
      observed=0
      40.times do
        break unless UI.run_observer_tick
        observed+=1
      end
      before={'pending'=>W.pending?($model),'runs'=>runs.dup,
              'statuses'=>$statuses.dup,'events'=>$events.dup}
      UI.run_options_tick
      UI.drain
      {'observed_ticks'=>observed,'before_options'=>before,'runs'=>runs,
       'events'=>$events,'statuses'=>$statuses,'pending'=>W.pending?($model),
       'timers'=>UI.timers.length}
    end
  RUBY

  def source
    ENV['MH_ASSEMBLY_SOURCE'] || File.expand_path('../assembly.rb',__dir__)
  end

  def run_script(body)
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',HARNESS+body,source)
    assert status.success?,error
    JSON.parse(output)
  end

  def test_options_held_for_4s_8s_and_more_are_never_superseded_by_external_sync
    result=run_script(<<~'RUBY')
      puts JSON.generate(holds:[40,80,90].map { |ticks| run_hold(ticks) })
    RUBY
    result['holds'].each do |hold|
      label="hold #{hold['requested_ticks']} ticks"
      assert_equal hold['requested_ticks'],hold['observed_ticks'],label
      assert_equal true,hold['before_options']['pending'],label
      assert_empty hold['before_options']['runs'],label
      assert_empty hold['before_options']['statuses'],label
      assert_equal true,hold['ran_options'],label
      assert_equal [18.6],hold['runs'],label
      assert_equal false,hold['pending'],label
      assert_equal 0,hold['timers'],label
      assert_includes hold['statuses'],['options','done',nil],label
      assert_includes hold['statuses'],['assembly','done',nil],label
      refute_includes hold['statuses'],[ 'options','superseded',nil],label
      done_at=hold['events'].index('complete:options:done')
      submitted_at=hold['events'].index('submit:assembly')
      assembly_at=hold['events'].index('complete:assembly:done')
      refute_nil done_at,label
      refute_nil submitted_at,label
      refute_nil assembly_at,label
      assert_operator done_at,:<,submitted_at,label
      assert_operator submitted_at,:<,assembly_at,label
    end
  end

  def test_stale_generation_or_undo_does_not_run_the_old_assembly_timer
    result=run_script(<<~'RUBY')
      puts JSON.generate(result:run_stale_generation)
    RUBY
    result=result['result']
    assert_equal 1,result['observed_ticks']
    assert_equal true,result['before_options']['pending']
    refute_includes result['events'],'submit:assembly'
    assert_equal [20.0],result['runs']
    assert_equal false,result['pending']
    assert_equal 0,result['timers']
    assert_includes result['statuses'],['options','done',nil]
    refute_includes result['statuses'],[ 'options','superseded',nil]
  end

  def test_latest_options_edit_wins_and_external_sync_runs_after_it
    result=run_script(<<~'RUBY')
      puts JSON.generate(result:run_latest_options)
    RUBY
    result=result['result']
    assert_equal 40,result['observed_ticks']
    assert_equal true,result['before_options']['pending']
    assert_empty result['before_options']['runs']
    assert_equal [['options','superseded',nil]],result['before_options']['statuses']
    assert_equal [20.0],result['runs']
    assert_equal false,result['pending']
    assert_equal 0,result['timers']
    assert_includes result['statuses'],['options','done',nil]
    assert_includes result['statuses'],['assembly','done',nil]
    assert_equal 1,(result['statuses'].count { |row| row[0]=='options' && row[1]=='superseded' })
    done_at=result['events'].index('complete:options:done')
    submitted_at=result['events'].index('submit:assembly')
    refute_nil done_at
    refute_nil submitted_at
    assert_operator done_at,:<,submitted_at
  end
end

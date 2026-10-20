# encoding: UTF-8
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'json'

class ModuleStudioScaleObserverTest < Minitest::Test
  def test_pending_committed_scale_survives_abort_without_redrawing_cancelled_or_undone_scales
    script=<<~'RUBY'
      module Sketchup
        class ModelObserver;end
        class AppObserver;end
        def self.active_model;$model;end
      end
      module UI
        def self.start_timer(*,&callback);(@timers ||= []) << callback;end
        def self.flush
          @timers.shift.call until @timers.empty?
        end
      end
      require ARGV.fetch(0)
      s=MH::ModuleStudio
      $model=Struct.new(:active_path).new(nil)
      root=Struct.new(:persistent_id,:scales).new(1,[1.0,1.0,1.0])
      s::ScaleRedraw.define_singleton_method(:roots) { |_model| [root] }
      s::ScaleRedraw.define_singleton_method(:signature) { |entity| entity.scales.dup }
      result={}
      %w[pending_abort unchanged_path changed_path cancelled_abort undo undo_other completed_undo applying_abort unrelated_commit].each do |scenario|
        $model.active_path=nil
        root.scales=[1.0,1.0,1.0]
        observer=s::ScaleRedraw::ScaleModelObserver.new($model)
        applied=[]
        observer.define_singleton_method(:perform) { |entities| applied << entities.map { |item| item.scales.dup };reset }
        root.scales=[1.0,1.4,1.0]
        observer.onTransactionCommit($model)
        case scenario
        when 'pending_abort'
          # A temporary operation was cancelled, after the Scale had committed.
          observer.onTransactionUndo($model)
          observer.onTransactionAbort($model)
          observer.onActivePathChanged($model)
        when 'unchanged_path'
          observer.onActivePathChanged($model)
        when 'changed_path'
          $model.active_path=[Struct.new(:persistent_id).new(2)]
          observer.onActivePathChanged($model)
        when 'cancelled_abort'
          root.scales=[1.0,1.0,1.0]
          observer.onTransactionAbort($model)
        when 'undo'
          root.scales=[1.0,1.0,1.0]
          observer.onTransactionUndo($model)
        when 'undo_other'
          observer.onTransactionUndo($model)
        when 'completed_undo'
          UI.flush
          root.scales=[1.0,1.0,1.0]
          observer.onTransactionUndo($model)
          observer.onActivePathChanged($model)
        when 'applying_abort'
          observer.instance_variable_set(:@applying,true)
          observer.onTransactionAbort($model)
          observer.instance_variable_set(:@applying,false)
        when 'unrelated_commit'
          observer.onTransactionCommit($model)
        end
        UI.flush
        result[scenario]=applied
      end
      puts JSON.generate(result)
    RUBY
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,File.expand_path('../scale_redraw.rb',__dir__))
    assert status.success?,error
    result=JSON.parse(output)
    expected=[[[1.0,1.4,1.0]]]
    assert_equal expected,result['pending_abort'],'An unrelated abort must not acknowledge a still-unrepaired committed Scale.'
    assert_equal expected,result['unchanged_path'],'An unchanged edit path notification must keep the Scale pending.'
    assert_empty result['changed_path']
    assert_empty result['cancelled_abort']
    assert_empty result['undo']
    assert_equal expected,result['undo_other']
    assert_equal expected,result['completed_undo'],'Undo after completed redraw must not create a new repair operation.'
    assert_equal expected,result['applying_abort']
    assert_equal expected,result['unrelated_commit']
  end
end

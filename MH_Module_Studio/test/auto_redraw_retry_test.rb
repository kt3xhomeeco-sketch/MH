# encoding: UTF-8
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'json'

# Real UpdateWork scheduling plus the real ScaleModelObserver are exercised in a
# subprocess so the single-writer queue, the observer generation and UI timers
# behave exactly as in SketchUp (only `perform` is replaced with a recorder).
class ModuleStudioAutoRedrawRetryTest < Minitest::Test
  HARNESS=<<~'RUBY'
    module Sketchup
      class ModelObserver;end
      class AppObserver;end
      def self.active_model;$model;end
      def self.status_text;@status_text;end
      def self.status_text=(value);@status_text=value;end
    end
    module UI
      def self.start_timer(delay,*,&block);(@timers ||= []) << [delay,block];end
      def self.timers;@timers ||= [];end
      def self.run_one;row=timers.shift;row[1].call if row;end
      def self.run_delay(delay)
        index=timers.index { |row| row[0]==delay }
        raise "no timer #{delay}" unless index
        row=timers.delete_at(index)
        row[1].call
      end
      def self.drain(limit=400)
        count=0
        while (row=timers.shift)
          count+=1
          raise 'timer storm' if count>limit
          row[1].call
        end
        count
      end
      def self.messagebox(message);($messages ||= []) << message;end
      def self.messages;$messages ||= [];end
    end
    require ARGV.fetch(0)
    s=MH::ModuleStudio
  RUBY

  def redraw_fixture
    <<~'RUBY'
      $model=Struct.new(:active_path,:observer) do
        def add_observer(value);self.observer=value;end
      end.new(nil,nil)
      entity=Struct.new(:persistent_id,:model,:scales,:mesh) do
        def valid?;true;end
        def deleted?;false;end
      end
      a=entity.new(1,$model,[1,1,1],[300,18,500])
      b=entity.new(2,$model,[1,1,1],[300,18,500])
      s::ScaleRedraw.define_singleton_method(:roots) { |_model| [a,b] }
      s::ScaleRedraw.define_singleton_method(:signature) { |root| root.scales.dup }
      s::ScaleRedraw.define_singleton_method(:geometry_signature) { |root| root.mesh.dup }
      w=s::UpdateWork
    RUBY
  end

  def test_pending_scale_survives_superseding_options_edit
    script=HARNESS+redraw_fixture+<<~'RUBY'
      applied=[];options_runs=0;statuses=[]
      original=w.method(:submit)
      w.define_singleton_method(:submit) do |model,**options,&action|
        key=options[:key];inner=options[:complete]
        options[:complete]=->(status,error) { statuses << [key.to_s,status.to_s];inner&.call(status,error) }
        original.call(model,**options,&action)
      end
      observer=s::ScaleRedraw::ScaleModelObserver.new($model)
      observer.define_singleton_method(:perform) { |roots| applied << roots.map { |root| root.persistent_id };reset }
      b.mesh=[300,25,500]
      observer.onTransactionCommit($model)
      UI.run_one
      w.submit($model,key: :options,guard:-> { true }) { options_runs+=1 }
      w.submit($model,key: :options,guard:-> { true }) { options_runs+=1 }
      drained=UI.drain
      puts JSON.generate(applied:applied,options_runs:options_runs,drained:drained,
        pending:observer.instance_variable_get(:@pending).map { |root| root.persistent_id },
        update_pending:w.pending?($model),timers:UI.timers.length,statuses:statuses)
    RUBY
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,File.expand_path('../scale_redraw.rb',__dir__))
    assert status.success?,error
    result=JSON.parse(output)
    # Latest options edit wins and runs once; the superseded root B is still
    # redrawn exactly once, though its first job was cancelled before advancing.
    assert_equal 1,result['options_runs']
    assert_equal [[2]],result['applied']
    assert_empty result['pending']
    assert_equal false,result['update_pending']
    assert_equal 0,result['timers']
    assert_operator result['drained'],:<,20
    assert_includes result['statuses'],['scale','superseded']
    assert_equal %w[options scale],result['statuses'].map(&:first).uniq.sort
  end

  def test_undo_cancellation_does_not_replay_or_leave_a_stale_job
    script=HARNESS+redraw_fixture+<<~'RUBY'
      applied=[];statuses=[]
      original=w.method(:submit)
      w.define_singleton_method(:submit) do |model,**options,&action|
        key=options[:key];inner=options[:complete]
        options[:complete]=->(status,error) { statuses << [key.to_s,status.to_s];inner&.call(status,error) }
        original.call(model,**options,&action)
      end
      observer=s::ScaleRedraw::ScaleModelObserver.new($model)
      observer.define_singleton_method(:perform) { |roots| applied << roots.map { |root| root.persistent_id };reset }
      b.mesh=[300,25,500]
      observer.onTransactionCommit($model)
      UI.run_one
      # User Undo restores the original geometry; both observers see it.
      b.mesh=[300,18,500]
      $model.observer.onTransactionUndo($model)
      observer.onTransactionUndo($model)
      drained=UI.drain
      puts JSON.generate(applied:applied,statuses:statuses,drained:drained,
        pending:observer.instance_variable_get(:@pending).map { |root| root.persistent_id },
        update_pending:w.pending?($model),timers:UI.timers.length)
    RUBY
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,File.expand_path('../scale_redraw.rb',__dir__))
    assert status.success?,error
    result=JSON.parse(output)
    assert_empty result['applied']
    assert_equal [['scale','cancelled']],result['statuses']
    assert_empty result['pending']
    assert_equal false,result['update_pending']
    assert_equal 0,result['timers']
    assert_operator result['drained'],:<,10
  end

  def test_manual_redraw_reports_success_only_after_done
    script=HARNESS+<<~'RUBY'
      require ARGV.fetch(1)
      $model=Struct.new(:active_path,:observer) do
        def add_observer(value);self.observer=value;end
      end.new(nil,nil)
      root=Struct.new(:persistent_id,:model).new(1,$model)
      s::Runtime.define_singleton_method(:selected_root) { root }
      redrawn=[]
      s::Assembly.define_singleton_method(:redraw) { |entity| redrawn << entity }
      texts={}
      Sketchup.status_text=nil
      s.redraw_selected
      $model.observer.onTransactionUndo($model)
      UI.drain
      texts['cancelled']=Sketchup.status_text
      Sketchup.status_text=nil
      s.redraw_selected
      s::UpdateWork.submit($model,key: :options) { 0 }
      UI.drain
      texts['superseded']=Sketchup.status_text
      puts JSON.generate(texts:texts,messages:UI.messages,redrawn:redrawn.length,
        update_pending:s::UpdateWork.pending?($model),timers:UI.timers.length)
    RUBY
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,
      File.expand_path('../scale_redraw.rb',__dir__),File.expand_path('../module_options.rb',__dir__))
    assert status.success?,error
    result=JSON.parse(output)
    assert_nil result['texts']['cancelled']
    assert_nil result['texts']['superseded']
    assert_empty result['messages']
    assert_equal 0,result['redrawn']
    assert_equal false,result['update_pending']
    assert_equal 0,result['timers']
  end

  def test_duplicate_commit_timer_does_not_cancel_the_owning_job
    script=HARNESS+redraw_fixture+<<~'RUBY'
      applied=[];statuses=[];options_runs=0
      original=w.method(:submit)
      w.define_singleton_method(:submit) do |model,**options,&action|
        key=options[:key];inner=options[:complete]
        options[:complete]=->(status,error) { statuses << [key.to_s,status.to_s];inner&.call(status,error) }
        original.call(model,**options,&action)
      end
      observer=s::ScaleRedraw::ScaleModelObserver.new($model)
      observer.define_singleton_method(:perform) { |roots| applied << roots.map { |root| root.persistent_id };reset }
      b.mesh=[300,25,500]
      observer.onTransactionCommit($model)
      # Deterministic QA path: queue the job now, leaving the commit timer armed.
      observer.redraw([b],observer.instance_variable_get(:@generation))
      w.submit($model,key: :options,guard:-> { true }) { options_runs+=1 }
      UI.drain
      puts JSON.generate(applied:applied,statuses:statuses,options_runs:options_runs,
        pending:observer.instance_variable_get(:@pending).map { |root| root.persistent_id },
        update_pending:w.pending?($model),timers:UI.timers.length)
    RUBY
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,File.expand_path('../scale_redraw.rb',__dir__))
    assert status.success?,error
    result=JSON.parse(output)
    assert_equal 1,result['options_runs']
    refute_includes result['statuses'],%w[options superseded]
    assert_equal [[2]],result['applied']
    assert_empty result['pending']
    assert_equal 0,result['timers']
  end

  def test_recheck_survives_a_long_running_superseding_job
    script=HARNESS+redraw_fixture+<<~'RUBY'
      applied=[];statuses=[];options_runs=0
      original=w.method(:submit)
      w.define_singleton_method(:submit) do |model,**options,&action|
        key=options[:key];inner=options[:complete]
        options[:complete]=->(status,error) { statuses << [key.to_s,status.to_s];inner&.call(status,error) }
        original.call(model,**options,&action)
      end
      observer=s::ScaleRedraw::ScaleModelObserver.new($model)
      observer.define_singleton_method(:perform) { |roots| applied << roots.map { |root| root.persistent_id };reset }
      b.mesh=[300,25,500]
      observer.onTransactionCommit($model)
      UI.run_one
      w.submit($model,key: :options,guard:-> { true }) { options_runs+=1 }
      held=[]
      90.times do
        UI.run_delay(0.12)
        held << [applied.length,options_runs,observer.instance_variable_get(:@pending).length]
      end
      held_result={'ticks'=>held.length,'applied'=>applied.length,'options_runs'=>options_runs,
        'pending'=>observer.instance_variable_get(:@pending).map { |root| root.persistent_id },
        'max_pending'=>held.map(&:last).max,
        'statuses'=>statuses.dup,'update_pending'=>w.pending?($model)}
      UI.drain
      puts JSON.generate(held:held_result,applied:applied,options_runs:options_runs,
        pending:observer.instance_variable_get(:@pending).map { |root| root.persistent_id },
        update_pending:w.pending?($model),timers:UI.timers.length,statuses:statuses)
    RUBY
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,File.expand_path('../scale_redraw.rb',__dir__))
    assert status.success?,error
    result=JSON.parse(output)
    held=result['held']
    # More than the former 80-tick cap: the pending work must still survive.
    assert_equal 90,held['ticks']
    assert_equal 0,held['applied']
    assert_equal 0,held['options_runs']
    assert_equal 1,held['max_pending']
    assert_equal [2],held['pending']
    assert_equal true,held['update_pending']
    assert_equal [['scale','superseded']],held['statuses']
    assert_equal [[2]],result['applied']
    assert_equal 1,result['options_runs']
    assert_empty result['pending']
    assert_equal false,result['update_pending']
    assert_equal 0,result['timers']
  end

  def test_initial_redraw_defers_instead_of_superseding_queued_options
    script=HARNESS+redraw_fixture+<<~'RUBY'
      applied=[];statuses=[];options_runs=0
      original=w.method(:submit)
      w.define_singleton_method(:submit) do |model,**options,&action|
        key=options[:key];inner=options[:complete]
        options[:complete]=->(status,error) { statuses << [key.to_s,status.to_s];inner&.call(status,error) }
        original.call(model,**options,&action)
      end
      observer=s::ScaleRedraw::ScaleModelObserver.new($model)
      observer.define_singleton_method(:perform) { |roots| applied << roots.map { |root| root.persistent_id };reset }
      b.mesh=[300,25,500]
      w.submit($model,key: :options,guard:-> { true }) { options_runs+=1 }
      observer.redraw([b],observer.instance_variable_get(:@generation))
      UI.drain
      puts JSON.generate(applied:applied,statuses:statuses,options_runs:options_runs,
        pending:observer.instance_variable_get(:@pending).map { |root| root.persistent_id },
        update_pending:w.pending?($model),timers:UI.timers.length)
    RUBY
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,File.expand_path('../scale_redraw.rb',__dir__))
    assert status.success?,error
    result=JSON.parse(output)
    assert_equal 1,result['options_runs']
    refute_includes result['statuses'],%w[options superseded]
    assert_includes result['statuses'],%w[options done]
    assert_equal [[2]],result['applied']
    assert_empty result['pending']
    assert_equal false,result['update_pending']
    assert_equal 0,result['timers']
  end
end

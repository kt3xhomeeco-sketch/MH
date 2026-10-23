# encoding: UTF-8
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'json'

class ModuleStudioExternalGeometryObserverTest < Minitest::Test
  def test_deleted_door_uses_direct_restore_without_solving_unrelated_links
    script=<<~'RUBY'
      module Sketchup
        class ModelObserver;end
        class AppObserver;end
      end
      require ARGV.fetch(0)
      s=MH::ModuleStudio;model=Object.new;rows=[{'id'=>'unrelated'}];events=[]
      model.define_singleton_method(:start_operation) { |*| }
      model.define_singleton_method(:commit_operation) { events << 'commit' }
      s::Runtime.define_singleton_method(:ensure_assembly_context) { |_| }
      s::Assembly.define_singleton_method(:fingerprint) { |_| 'after' }
      s::Assembly.define_singleton_method(:records) { |_| rows }
      s::Assembly.define_singleton_method(:transact) { |*| raise 'Unrelated graph solved' }
      s::ImportLinks.define_singleton_method(:detached_targets?) { |*| true }
      s::ImportLinks.define_singleton_method(:apply_reservations) { |_,records,**| raise 'Other links lost' unless records==rows;events << 'restore' }
      s::AssemblyContainers.define_singleton_method(:store) { |_,records| raise 'Other links lost' unless records==rows;events << 'store' }
      observer=s::Assembly::AssemblyModelObserver.allocate
      observer.instance_variable_set(:@model,model)
      observer.instance_variable_set(:@fingerprint,'before')
      observer.instance_variable_set(:@pending_reservation_targets,{[nil,'host','1:0']=>600})
      observer.synchronize_external
      raise 'Wrong restore sequence' unless events==%w[restore store commit]
    RUBY
    _output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,File.expand_path('../assembly.rb',__dir__))
    assert status.success?,error
  end

  def test_thickness_recovery_and_links_share_one_transaction_and_do_not_double_undo
    script=<<~'RUBY'
      module Sketchup
        class ModelObserver;end
        class AppObserver;end
        def self.undo;($events ||= []) << 'undo';end
        def self.status_text=(_text);end
      end
      module UI
        def self.messagebox(_text);end
      end
      require ARGV.fetch(0)
      s=MH::ModuleStudio
      # Scheduling/concurrency is covered by update_work_test; retain the
      # observer baseline assertions here with an immediate dispatcher.
      s::UpdateWork.define_singleton_method(:submit) do |_model,**options,&action|
        action.call;options[:complete]&.call(:done,nil)
      end
      model=Object.new;root=Object.new
      model.define_singleton_method(:start_operation) { |*| raise 'Separate T-only transaction' }
      s::Runtime.define_singleton_method(:ensure_assembly_context) { |_model| }
      s::ScaleRedraw.define_singleton_method(:prepare) { |item| [item,{}, {'changed_count'=>1}] }
      s::Assembly.define_singleton_method(:records) { |_model| [{'id'=>'contact'}] }
      s::Assembly.define_singleton_method(:fingerprint) { |_model| 'after-scale' }
      s::AssemblyContainers.define_singleton_method(:containers) { |_model| [] }
      anchor={'root'=>'member','scope'=>'assembly'}
      s::ImportLinks.define_singleton_method(:roots) { |_model| [[root,anchor]] }
      coordinator=s::Assembly::AssemblyModelObserver.allocate
      coordinator.instance_variable_set(:@model,model)
      coordinator.instance_variable_set(:@pending_reservation_targets,{'host'=>600})
      s::Assembly.define_singleton_method(:watch) { |_model| coordinator }
      observer=s::ScaleRedraw::ScaleModelObserver.allocate
      observer.instance_variable_set(:@model,model)
      observer.define_singleton_method(:reset) { }
      result={};transactions=[]
      s::Assembly.define_singleton_method(:transact) { |_model,_records,**options| transactions << options }
      observer.perform([root]);result['success']=transactions.dup
      s::Assembly.define_singleton_method(:transact) do |_model,_records,**|
        Sketchup.undo # The assembly transaction owns rollback on failure.
        raise 'Failed contact verification'
      end
      $events=[];observer.perform([root]);result['rollback']=$events
      puts JSON.generate(result)
    RUBY
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,File.expand_path('../assembly.rb',__dir__))
    assert status.success?,error
    result=JSON.parse(output)
    assert_equal 1,result['success'].length
    options=result['success'].first
    assert_equal [{'root'=>'member','scope'=>'assembly'}],options['redraw']
    assert_equal options['redraw'],options['mutable_anchors']
    assert_equal({'host'=>600},options['reservation_targets'])
    assert options['transparent']
    assert_equal ['undo'],result['rollback']
  end

  def test_internal_stretch_and_pending_repairs_survive_unrelated_stamps_and_cancelled_operations
    script=<<~'RUBY'
      module Sketchup
        class ModelObserver;end
        class AppObserver;end
        def self.active_model;$model;end
      end
      module UI
        def self.start_timer(delay,*,&callback);(@timers ||= []) << callback;(@delays ||= []) << delay;end
        def self.flush
          @timers.shift.call until @timers.empty?
        end
      end
      require ARGV.fetch(0)
      s=MH::ModuleStudio
      # Scheduling/concurrency is covered by update_work_test; retain the
      # observer baseline assertions here with an immediate dispatcher.
      s::UpdateWork.define_singleton_method(:submit) do |_model,**options,&action|
        action.call;options[:complete]&.call(:done,nil)
      end
      $model=Struct.new(:active_path).new(nil)
      entity=Struct.new(:persistent_id,:model,:scales,:mesh)
      a=entity.new(1,$model,[1,1,1],[300,18,500]);b=entity.new(2,$model,[1,1,1],[300,18,500])
      s::ScaleRedraw.define_singleton_method(:roots) { |_model| [a,b] }
      s::ScaleRedraw.define_singleton_method(:signature) { |root| root.scales.dup }
      s::ScaleRedraw.define_singleton_method(:geometry_signature) { |root| root.mesh.dup }
      result={}
      %w[stretch cancelled_stretch own_stamp other_stamp unrelated_commit unchanged_context changed_context].each do |scenario|
        $model.active_path=nil;a.scales=[1,1,1];a.mesh=[300,18,500];b.mesh=[300,18,500]
        observer=s::ScaleRedraw::ScaleModelObserver.new($model)
        s::ScaleRedraw.instance_variable_set(:@observers,{$model=>observer})
        applied=[]
        observer.define_singleton_method(:perform) { |roots| applied << roots.map(&:persistent_id);reset }
        a.mesh=[400,18,500]
        if scenario=='own_stamp'
          s::ScaleRedraw.acknowledge(a)
        end
        observer.onTransactionCommit($model)
        case scenario
        when 'cancelled_stretch'
          a.mesh=[300,18,500];observer.onTransactionUndo($model);observer.onTransactionAbort($model)
        when 'other_stamp'
          b.mesh=[300,20,500];s::ScaleRedraw.acknowledge(b);observer.onTransactionCommit($model)
        when 'unrelated_commit'
          observer.onTransactionCommit($model)
        when 'unchanged_context'
          observer.onTransactionUndo($model);observer.onActivePathChanged($model)
        when 'changed_context'
          $model.active_path=[Struct.new(:persistent_id).new(9)];observer.onActivePathChanged($model)
        end
        UI.flush;result[scenario]=applied
      end
      puts JSON.generate(result)
    RUBY
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,File.expand_path('../scale_redraw.rb',__dir__))
    assert status.success?,error
    result=JSON.parse(output)
    %w[stretch other_stamp unrelated_commit unchanged_context].each { |key| assert_equal [[1]],result[key],key }
    %w[cancelled_stretch own_stamp changed_context].each { |key| assert_empty result[key],key }
  end

  def test_link_observation_retains_original_baseline_until_external_geometry_is_solved
    script=<<~'RUBY'
      module Sketchup
        class ModelObserver;end
        class AppObserver;end
        def self.active_model;$model;end
      end
      module UI
        def self.start_timer(delay,*,&callback);(@timers ||= []) << callback;(@delays ||= []) << delay;end
        def self.flush
          @timers.shift.call until @timers.empty?
        end
        def self.run_one;@timers.shift.call;end
        def self.last_delay;@delays.last;end
      end
      require ARGV.fetch(0)
      s=MH::ModuleStudio
      # Scheduling/concurrency is covered by update_work_test; retain the
      # observer baseline assertions here with an immediate dispatcher.
      s::UpdateWork.define_singleton_method(:submit) do |_model,**options,&action|
        action.call;options[:complete]&.call(:done,nil)
      end
      $model=Struct.new(:active_path).new(nil)
      $fingerprint='before'
      s::Assembly.define_singleton_method(:fingerprint) { |_model| $fingerprint }
      s::Assembly.define_singleton_method(:records) { |_model| [{'id'=>'real-link'}] }
      s::AssemblyContainers.define_singleton_method(:containers) { |_model| [] }
      s::AssemblyContainers.define_singleton_method(:dangling_door_links) { |_model| [] }
      s::ImportLinks.define_singleton_method(:root_frames) { |_model| {'host'=>'before-frame'} }
      s::ScaleRedraw.define_singleton_method(:pending?) { |_model| $scale_pending }
      captures=[]
      s::ImportLinks.define_singleton_method(:scaled_reservation_targets) { |_model,_records,before| raise 'Lost before frame' unless before=={'host'=>'before-frame'};captures << $fingerprint;{'host'=>600} }
      result={}
      %w[commit cancelled_temp unchanged_context changed_context undo cancelled abort_no_pending].each do |scenario|
        $model.active_path=nil;$fingerprint='before'
        observer=s::Assembly::AssemblyModelObserver.new($model);applied=[]
        s::Assembly.define_singleton_method(:transact) { |_model,_records,**options| applied << options }
        if scenario=='abort_no_pending'
          observer.onTransactionAbort($model)
        else
          $fingerprint='after';observer.onTransactionCommit($model)
          case scenario
          when 'cancelled_temp'
            observer.onTransactionUndo($model);observer.onTransactionAbort($model);observer.onActivePathChanged($model)
          when 'unchanged_context'
            observer.onActivePathChanged($model)
          when 'changed_context'
            $model.active_path=[Struct.new(:persistent_id).new(9)];observer.onActivePathChanged($model)
          when 'undo','cancelled'
            $fingerprint='before';observer.onTransactionUndo($model);observer.onTransactionAbort($model)
          end
        end
        UI.flush;result[scenario]={'applied'=>applied,'captures'=>captures.dup};captures.clear
      end
      $model.active_path=nil;$fingerprint='before';observer=s::Assembly::AssemblyModelObserver.new($model)
      applied=[];s::Assembly.define_singleton_method(:transact) { |_model,_records,**options| applied << options }
      $fingerprint='after';$scale_pending=true;observer.onTransactionCommit($model);UI.run_one
      deferred=applied.empty? && UI.last_delay==0.1
      $scale_pending=false;UI.run_one
      result['scale_redraw_settles_first']={'deferred'=>deferred,'applied'=>applied}
      puts JSON.generate(result)
    RUBY
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,File.expand_path('../assembly.rb',__dir__))
    assert status.success?,error
    result=JSON.parse(output)
    %w[commit cancelled_temp unchanged_context].each do |key|
      assert_equal 1,result[key]['applied'].length,key
      assert_equal true,result[key]['applied'][0]['external_geometry']
      assert_equal({'host'=>600},result[key]['applied'][0]['reservation_targets'])
      assert_operator result[key]['captures'].length,:>=,1,key
      assert result[key]['captures'].all? { |fingerprint| fingerprint=='after' },key
    end
    %w[changed_context undo cancelled abort_no_pending].each { |key| assert_empty result[key]['applied'],key }
    assert result['scale_redraw_settles_first']['deferred']
    assert_equal 1,result['scale_redraw_settles_first']['applied'].length
  end

  def test_erasing_last_linked_door_restores_host_without_full_assembly_solve
    script=<<~'RUBY'
      module Sketchup
        class ModelObserver;end
        class AppObserver;end
      end
      require ARGV.fetch(0)
      s=MH::ModuleStudio
      model=Object.new;events=[]
      model.define_singleton_method(:start_operation) { |*args| events << [:start,*args] }
      model.define_singleton_method(:commit_operation) { events << [:commit] }
      model.define_singleton_method(:abort_operation) { events << [:abort] }
      s::Runtime.define_singleton_method(:ensure_assembly_context) { |_model| }
      s::Assembly.define_singleton_method(:fingerprint) { |_model| 'after-delete' }
      s::Assembly.define_singleton_method(:records) { |_model| [] }
      s::Assembly.define_singleton_method(:transact) { |*| raise 'Unexpected full constraint solve' }
      s::ImportLinks.define_singleton_method(:reservation_fingerprint) { |_model| [['host','saved-span']] }
      targets={['host','1:0']=>600}
      s::ImportLinks.define_singleton_method(:apply_reservations) do |_model,rows,**options|
        events << [:restore,rows,options];raise 'Door row survived' unless rows.empty?
      end
      s::AssemblyContainers.define_singleton_method(:store) { |_model,rows| events << [:store,rows] }
      observer=s::Assembly::AssemblyModelObserver.allocate
      observer.instance_variable_set(:@model,model)
      observer.instance_variable_set(:@fingerprint,'before-delete')
      observer.instance_variable_set(:@pending_reservation_targets,targets)
      observer.synchronize_external
      puts JSON.generate(events)
    RUBY
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,File.expand_path('../assembly.rb',__dir__))
    assert status.success?,error
    events=JSON.parse(output)
    assert_equal 1,(events.count { |event| event[0]=='restore' })
    assert_equal 1,(events.count { |event| event[0]=='store' })
    assert_equal [],events.find { |event| event[0]=='store' }[1]
    assert_equal 1,(events.count { |event| event[0]=='commit' })
    refute(events.any? { |event| event[0]=='abort' })
  end
end

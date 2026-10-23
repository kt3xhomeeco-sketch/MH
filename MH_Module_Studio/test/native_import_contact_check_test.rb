# encoding: UTF-8
require 'minitest/autorun'
require 'rbconfig'
require 'tmpdir'

class NativeImportContactCheckTest < Minitest::Test
  # Dir.pwd avoids a Bundler realpath lookup through the inaccessible parent.
  ROOT=Dir.pwd
  HELPER=File.join(ROOT,'tools','native_import_contact_check.rb')
  ENV_CLEAN={'RUBYOPT'=>nil,'RUBYLIB'=>nil,'BUNDLE_GEMFILE'=>nil,'BUNDLE_BIN_PATH'=>nil}

  def run_script(name,body)
    Dir.mktmpdir("mh-qa-#{name}") do |dir|
      path=File.join(dir,'script.rb');File.write(path,body)
      output=IO.popen(ENV_CLEAN,[RbConfig.ruby,'-I',File.join(ROOT,'test'),path,HELPER],err: [:child,:out],chdir:ROOT) { |io| io.read }
      yield output,$?
    end
  end

  COMMON=<<~'RUBY'
    module Sketchup; end
    class << Sketchup; attr_accessor :calls; end
    class << Sketchup
      def method_missing(name,*)
        (Sketchup.calls ||= []) << name
        raise "unexpected sketchup access: #{name}"
      end
      def respond_to_missing?(*); true; end
    end
    require ARGV.fetch(0)
    qa=MH::ModuleStudio::NativeImportContactCheck
  RUBY

  def test_both_mutating_entrypoints_refuse_by_default_before_accessing_sketchup
    script=COMMON+<<~'RUBY'
      begin
        qa.run(host_id: 1,door_id: 2)
        abort 'run did not refuse'
      rescue => error
        abort error.message unless error.message.include?('isolated idle SketchUp session')
      end
      begin
        qa.start_deletion(host_id: 1,door_id: 2)
        abort 'start_deletion did not refuse'
      rescue => error
        abort error.message unless error.message.include?('isolated idle SketchUp session')
      end
      abort "accessed Sketchup: #{Sketchup.calls.inspect}" if Sketchup.calls
    RUBY
    run_script('preflight',script) { |output,status| assert status.success?,output }
  end

  def test_busy_is_restored_to_previous_value_when_block_raises
    script=COMMON+<<~'RUBY'
      module MH
        module ModuleStudio
          module Assembly; end
        end
      end
      Assembly=MH::ModuleStudio::Assembly
      Assembly.instance_variable_set(:@busy,:before)
      error=begin
        qa.with_assembly_busy(true) { raise 'boom' }
      rescue => e
        e
      end
      abort 'exception not propagated' unless error&.message=='boom'
      abort "busy not restored: #{Assembly.instance_variable_get(:@busy).inspect}" unless Assembly.instance_variable_get(:@busy)==:before
      abort 'Sketchup accessed' if Sketchup.calls
    RUBY
    run_script('busy',script) { |output,status| assert status.success?,output }
  end

  CLEANUP_ENV=<<~'RUBY'
    module Sketchup
      class << self; attr_accessor :active_model; end
    end
    module MH
      module ModuleStudio
        module UpdateWork
          def self.pending?(_); false; end
          def self.cancel(*); raise 'must not cancel jobs'; end
          class << self; attr_accessor :watchers; end
        end
        module Assembly
          def self.records(model); @rows_by_model.fetch(model); end
          class << self
            attr_accessor :rows_by_model
            attr_reader :watchers
          end
        end
        module ScaleRedraw
          def self.watch(*); raise 'must not rebind observer'; end
        end
        module AssemblyContainers
          def self.store(model,rows); Assembly.rows_by_model[model]=rows; end
        end
      end
    end
    Entity=Struct.new(:persistent_id,:valid) { def valid?; valid; end; def erase!; self.valid=false; end }
    Definition=Struct.new(:persistent_id,:instances,:valid) { def valid?; valid; end }
    class Definitions
      def initialize(items); @items=items; end
      def to_a; @items.dup; end
      def find(&block); @items.find(&block); end
      def remove(item); @items.delete(item); end
    end
    class Model
      Selection=Struct.new(:items) { def to_a; items; end }
      attr_reader :definitions,:started,:committed,:aborted,:entities,:selection
      def initialize(items)
        @definitions=Definitions.new(items);@started=[];@committed=0;@aborted=[]
        @entities=[];@selection=Selection.new([])
      end
      def start_operation(name,_);@started<<name;end
      def commit_operation;@committed+=1;end
      def abort_operation;@aborted<<@started.last;end
      def active_operation_name;nil;end
    end
    class UI; def self.start_timer(*); raise 'unexpected defer'; end; end
    require ARGV.fetch(0)
    qa=MH::ModuleStudio::NativeImportContactCheck
    def watcher_for(model)
      Object.new.tap { |watcher| def watcher.open?; false; end }.then do |watcher|
        MH::ModuleStudio::UpdateWork.instance_variable_set(:@watchers,{model=>watcher})
      end
    end
  RUBY

  def test_cleanup_owns_only_its_links_definitions_job_and_restores_busy
    script=CLEANUP_ENV+<<~'RUBY'
      model=Model.new([Definition.new(90,[],true)])
      watcher_for(model)
      copy=Entity.new(20,true); door=Entity.new(21,true)
      Assembly=MH::ModuleStudio::Assembly
      Assembly.rows_by_model={model=>[
        {'id'=>'qa-other','copies'=>[]}, {'id'=>'user','copies'=>[]},
        {'id'=>'qa-job','copies'=>[]}]}
      Assembly.instance_variable_set(:@busy,:idle)
      qa.instance_variable_set(:@deletion,{
        'model'=>model,'before'=>[],'selection'=>[],
        'samples'=>[copy,door],'host'=>copy,'door_id'=>21,'finished'=>false,
        'link_ids'=>['qa-job'],'definition_ids'=>[77],'observations'=>[]})
      model.definitions.instance_variable_get(:@items).concat(
        [Definition.new(78,[],true),Definition.new(77,[],true)])
      unowned=model.definitions.instance_variable_get(:@items)[1]
      qa.finish_deletion
      rows=Assembly.records(model)
      abort 'other QA/user rows removed' unless rows.map { |r| r['id'] }==['qa-other','user']
      items=model.definitions.instance_variable_get(:@items)
      abort 'unowned definition removed' unless items.include?(unowned)
      abort 'owned definition retained' if items.any? { |d| d.persistent_id==77 }
      abort 'copies retained' if copy.valid? || door.valid?
      abort 'busy not restored' unless Assembly.instance_variable_get(:@busy)==:idle
      result=qa.deletion_result
      abort 'not finished' unless result['finished']
      abort "cleanup error: #{result['error']}" if result['error']
      abort 'selection changed' unless result['selection_changed']==false
      abort 'cleanup aborted unexpectedly' unless model.aborted.empty?
    RUBY
    run_script('cleanup',script) { |output,status| assert status.success?,output }
  end

  def test_cleanup_is_deferred_while_user_job_active_and_preserves_job
    script=CLEANUP_ENV+<<~'RUBY'
      model=Model.new([])
      watcher_for(model)
      Assembly=MH::ModuleStudio::Assembly
      Assembly.rows_by_model={model=>[{'id'=>'user','copies'=>[]}]}
      Assembly.instance_variable_set(:@busy,:idle)
      job={'model'=>model,'finished'=>false,'before'=>[],'selection'=>[],'samples'=>[],
        'link_ids'=>[],'definition_ids'=>[],'observations'=>[],'error'=>'observer failed'}
      qa.instance_variable_set(:@deletion,job)
      UpdateWork=MH::ModuleStudio::UpdateWork
      def UpdateWork.pending?(_); true; end
      timers=[]
      UI.define_singleton_method(:start_timer) { |delay,repeat,&block| timers << [delay,repeat,block] }
      qa.finish_deletion
      abort 'cleanup did not defer' unless job['cleanup_deferred'] && !job['finished']
      abort 'defer did not preserve error' unless job['error']=='observer failed'
      abort 'model mutated during deferred cleanup' unless model.started.empty? && model.aborted.empty?
      abort 'user job changed' unless Assembly.records(model).map { |row| row['id'] }==['user']
      abort 'busy changed during defer' unless Assembly.instance_variable_get(:@busy)==:idle
      abort "unexpected timer: #{timers.inspect}" unless timers.length==1 && timers[0][0]==0.1 && !timers[0][1]
    RUBY
    run_script('deferred',script) { |output,status| assert status.success?,output }
  end

  def test_cleanup_restores_busy_after_failed_setup_transaction
    script=CLEANUP_ENV+<<~'RUBY'
      model=Model.new([])
      watcher_for(model)
      Assembly=MH::ModuleStudio::Assembly
      Assembly.rows_by_model={model=>[]}
      Assembly.instance_variable_set(:@busy,:idle)
      Sketchup.active_model=model
      model.define_singleton_method(:find_entity_by_persistent_id) { |id| Entity.new(id,true) }
      qa.define_singleton_method(:clone_root) { |_model,_source| raise 'setup failed' }
      error=begin
        qa.start_deletion(host_id:1,door_id:2,isolated:true)
      rescue => e
        e
      end
      abort 'setup error not propagated' unless error&.message=='setup failed'
      abort "busy not restored: #{Assembly.instance_variable_get(:@busy).inspect}" unless Assembly.instance_variable_get(:@busy)==:idle
      abort 'setup transaction not aborted' unless model.aborted==['MH QA create deletion copies'] && model.committed==0
      abort 'setup failure accessed an observer' if Sketchup.calls
    RUBY
    run_script('setup-busy',script) { |output,status| assert status.success?,output }
  end

  def test_default_refusal_does_not_touch_existing_unfinished_job
    script=COMMON+<<~'RUBY'
      existing={'finished'=>false,'error'=>'original'}
      qa.instance_variable_set(:@deletion,existing)
      begin
        qa.start_deletion(host_id: 9,door_id: 10)
        abort 'start_deletion did not refuse'
      rescue => error
        abort error.message unless error.message.include?('isolated idle SketchUp session')
      end
      abort 'existing job changed' unless qa.instance_variable_get(:@deletion).equal?(existing) && existing=={'finished'=>false,'error'=>'original'}
      abort 'Sketchup accessed' if Sketchup.calls
    RUBY
    run_script('refusal',script) { |output,status| assert status.success?,output }
  end
end

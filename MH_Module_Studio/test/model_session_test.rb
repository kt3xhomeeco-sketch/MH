# encoding: UTF-8
require 'minitest/autorun'
require 'open3'
require 'rbconfig'

class ModuleStudioModelSessionTest < Minitest::Test
  def test_new_model_releases_stale_roots_observers_and_already_queued_file_callbacks
    script=<<~'RUBY'
      require 'json'
      $LOADED_FEATURES << 'sketchup.rb'
      def file_loaded?(*);true;end
      module Sketchup
        class AppObserver;end
        def self.add_observer(_observer);end
        def self.remove_observer(observer);(@removed ||= []) << observer;end
        def self.removed;@removed;end
      end
      module UI
        @timers={};@serial=0
        def self.start_timer(*,&callback);@timers[@serial+=1]=callback;@serial;end
        def self.stop_timer(id);@timers.delete(id);end
        def self.timers;@timers;end
        def self.openpanel(*);'old-file.skp';end
      end
      require ARGV.fetch(0)
      s=MH::ModuleStudio
      module Sketchup
        def self.active_model;$model;end
      end
      $model=Object.new
      panel=s::Panel.new
      s.instance_variable_set(:@panel,panel)
      panel.instance_variable_set(:@captured_root_pid,42)
      panel.instance_variable_set(:@captured_model,$model)
      panel.instance_variable_set(:@snapshots,[{'id'=>'old'}])
      panel.instance_variable_set(:@rule,{'id'=>'old-rule'})
      panel.instance_variable_set(:@busy,true)
      # New may reuse the Ruby Model object; explicit notification must reset it.
      s::StudioSessionObserver.new.onNewModel($model)
      raise 'Old session retained' unless panel.instance_variable_get(:@snapshots).empty? && panel.instance_variable_get(:@rule).nil? && !panel.instance_variable_get(:@busy) && panel.instance_variable_get(:@captured_root_pid).nil?
      s::ModuleFile.define_singleton_method(:read) { |_path| nil }
      s::Reader.define_singleton_method(:read_file) { |*args,**options| {'id'=>'obsolete'} }
      s::Reader.define_singleton_method(:enrich_file_functions!) { |*args| raise 'Old file callback reached native reader' }
      panel.request('action'=>'open_skp')
      Thread.list.reject { |thread| thread==Thread.current }.each(&:join)
      queued=UI.timers.values.last
      raise 'File read was not scheduled' unless queued
      $model=Object.new
      s::StudioSessionObserver.new.onNewModel($model)
      queued.call
      panel.request('action'=>'ready')
      raise 'Old read polluted new model' unless panel.instance_variable_get(:@snapshots).empty? && !panel.instance_variable_get(:@busy)
      # Cleanup must not touch invalid native Model handles.
      deleted=Object.new
      deleted.define_singleton_method(:valid?) { false }
      deleted.define_singleton_method(:selection) { raise 'Invalid model accessed' }
      options=s::ModuleOptions.new
      observer=Object.new
      options.instance_variable_set(:@model,deleted)
      options.instance_variable_set(:@root,Object.new)
      options.instance_variable_set(:@members,{'old'=>Object.new})
      options.instance_variable_set(:@app_observer,observer)
      options.detach
      raise 'Old option handles retained' unless options.instance_variable_get(:@model).nil? && options.instance_variable_get(:@root).nil? && options.instance_variable_get(:@members).nil? && Sketchup.removed.include?(observer)
      puts 'New-model session, stale asynchronous response and deleted-model handles passed'
    RUBY
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,File.expand_path('../main.rb',__dir__))
    assert status.success?,error
    assert_includes output,'deleted-model handles passed'
  end
end

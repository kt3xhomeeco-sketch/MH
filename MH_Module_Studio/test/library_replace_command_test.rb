# encoding: UTF-8
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
class ModuleStudioLibraryReplaceCommandTest < Minitest::Test
  def test_single_click_auto_replaces_selection_and_double_click_does_not_replace_twice
    script=<<~'RUBY'
      module Sketchup
        def self.active_model;$model;end
      end
      require ARGV.fetch(0)
      studio=MH::ModuleStudio
      $model=Struct.new(:selection).new([Object.new])
      library=studio::Library.allocate;calls=[];opened=[];messages=[]
      library.define_singleton_method(:preview) { |id| {'entry_id'=>id} }
      library.define_singleton_method(:open_hud) { |id| opened << id }
      library.define_singleton_method(:publish) { |message=nil,**options| messages << [message,options] }
      studio::LibraryPlacement.define_singleton_method(:selected_targets) { |_model| [{'root'=>'1'}] }
      studio::LibraryPlacement.define_singleton_method(:replace_many) { |_library,data,targets| calls << [data['entry_id'],targets];[Object.new] }
      library.request('action'=>'library_pick','id'=>'A.skp','gesture'=>'one')
      raise 'Single click did not replace' unless calls.length==1
      library.request('action'=>'library_place','id'=>'A.skp','gesture'=>'one')
      raise 'Double click replaced twice' unless calls.length==1
      library.request('action'=>'library_pick','id'=>'A.skp','gesture'=>'two')
      raise 'New click blocked' unless calls.length==2
      $model.selection.clear
      library.request('action'=>'library_pick','id'=>'B.skp','gesture'=>'three')
      raise 'Empty selection changed geometry' unless calls.length==2 && opened.empty? && messages.last[1][:background]
      library.request('action'=>'library_place','id'=>'B.skp','gesture'=>'three')
      raise 'Ordinary placement no longer opens HUD' unless opened==['B.skp']
      puts 'Selection Replace, gesture identity and normal placement passed'
    RUBY
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,File.expand_path('../library.rb',__dir__))
    assert status.success?,error
    assert_includes output,'normal placement passed'
  end
end

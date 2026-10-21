# encoding: UTF-8
require 'minitest/autorun'
require 'open3'
require 'rbconfig'

class ModuleStudioHUDLoadingTest < Minitest::Test
  def test_open_does_not_process_pixels_warm_cache_survives_reopen_and_stale_jobs_cancel
    script = <<~'RUBY'
      require 'json'
      require 'tmpdir'
      module UI
        @timers={};@next=0
        def self.start_timer(*,&block)
          @next+=1;@timers[@next]=block;@next
        end
        def self.stop_timer(id)
          @timers.delete(id)
        end
        def self.tick
          id=@timers.keys.first;@timers.delete(id)&.call
        end
        def self.pending
          @timers.length
        end
      end
      module Sketchup
        class ImageRep
          attr_reader :width,:height
          def initialize(path)
            @width,@height=File.read(path).split(',').map(&:to_i)
          end
          def prepare
            @width=40;@height=80
          end
          def save_file(path)
            File.write(path,[@width,@height].join(','))
          end
        end
        def self.active_model
          @model
        end
        def self.model=(value)
          @model=value
        end
      end
      class View
        attr_reader :alive
        def initialize;@next=0;@alive=[];end
        def load_texture(_image);@next+=1;@alive<<@next;@next;end
        def release_texture(texture);@alive.delete(texture);end
        def invalidate;end
      end
      require ARGV.fetch(0)
      studio=MH::ModuleStudio;thumb=studio::HUDThumbnail;prepared=0
      thumb.define_singleton_method(:prepare) { |image| prepared+=1;image.prepare;image }
      Dir.mktmpdir('mh-hud-loading') do |folder|
        thumb.define_singleton_method(:cache_path) { |key| File.join(folder,key+'.png') }
        source=File.join(folder,'raw.png');File.write(source,'100,100')
        library=Object.new
        library.define_singleton_method(:config) { {'hud_boards'=>[]} }
        library.define_singleton_method(:catalog) { {'entries'=>[]} }
        library.define_singleton_method(:thumbnail_key) { |item| item['key'] }
        library.define_singleton_method(:thumbnail) { |_item| source }
        library.define_singleton_method(:preview_thumbnail) { |_item| source }
        model=Struct.new(:active_view).new(View.new);Sketchup.model=model
        create=lambda do |keys|
          hud=studio::LibraryHUD.allocate
          {library:library,model:model,active:true,pending:nil,folders:false,page:0,items:keys.map { |key| {'key'=>key} },textures:{},texture_aspects:{},image_jobs:{}}.each { |name,value| hud.instance_variable_set('@'+name.to_s,value) }
          hud
        end
        hud=create.call(%w[a b]);hud.load_textures
        raise 'Pixel processing blocks HUD open' unless prepared.zero? && model.active_view.alive.length==2 && UI.pending==1
        UI.tick
        raise 'Not one preparation per tick' unless prepared==1 && hud.instance_variable_get(:@texture_aspects)['a']==0.5 && UI.pending==1
        UI.tick
        raise 'Prepared textures/caches missing' unless prepared==2 && model.active_view.alive.length==2 && UI.pending.zero? && File.file?(thumb.cache_path('b'))
        second=create.call(%w[a b]);second.load_textures
        raise 'Reopen did pixel work' unless prepared==2 && UI.pending.zero? && second.instance_variable_get(:@image_jobs).empty?
        second.instance_variable_set(:@items,[{'key'=>'changed'}]);second.load_textures
        raise 'Changed image key reused stale data' unless UI.pending==1 && second.instance_variable_get(:@textures).keys==['changed']
        second.instance_variable_set(:@items,[{'key'=>'other'}]);second.load_textures;UI.tick
        raise 'Old page prepared after navigation' unless prepared==3 && !File.file?(thumb.cache_path('changed')) && File.file?(thumb.cache_path('other'))
        second.instance_variable_set(:@items,[{'key'=>'cancelled'}]);second.load_textures
        second.instance_variable_set(:@active,false);second.cancel_image_jobs;UI.tick
        raise 'Cancelled job still running' unless prepared==3 && UI.pending.zero? && !File.file?(thumb.cache_path('cancelled'))
        switched=create.call(['switched']);switched.load_textures;Sketchup.model=Object.new;UI.tick
        raise 'Model switch kept a job timer alive' unless prepared==3 && UI.pending.zero? && !File.file?(thumb.cache_path('switched'))
        switched.cancel_image_jobs;Sketchup.model=model
        third=create.call(['missing']);third.load_textures;File.delete(source);UI.tick
        raise 'Enhancement failure removed raw image or kept spinning' unless third.instance_variable_get(:@textures).key?('missing') && UI.pending.zero?
        puts 'HUD cold preview, one-job ticks, persistent warm cache, view-key invalidation, page cancellation, exit and enhancement failures passed.'
      end
    RUBY
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,File.expand_path('../library_hud.rb',__dir__))
    assert status.success?,error+output
    assert_includes output,'enhancement failures passed'
  end
end

# encoding: UTF-8
require 'minitest/autorun'
require 'open3'
require 'rbconfig'

class ModuleStudioLibraryAdapterTest < Minitest::Test
  def test_preferences_round_trip_cancel_acknowledgements_stale_files_and_shortcut_command
    script = <<~'RUBY'
      require 'json'
      require 'tmpdir'
      $LOADED_FEATURES << 'sketchup.rb'
      def file_loaded?(*)
        true
      end
      module Sketchup
        class Group; end
        class ComponentInstance; end
        @prefs = {}
        def self.read_default(section, key, default)
          @prefs.fetch([section, key], default)
        end
        def self.write_default(section, key, value)
          raise 'Unsafe preference quotes' if value.include?('"')
          @prefs[[section, key]] = value
        end
        def self.active_model
          nil
        end
      end
      module UI
        class Command
          attr_accessor :tooltip, :status_bar_text
          attr_reader :name
          def initialize(name, &block)
            @name = name
            @block = block
          end
        end
        class Menu
          def add_item(command)
            $commands << command.name
          end
        end
        def self.menu(*)
          Menu.new
        end
        def self.select_directory(**)
          nil
        end
        def self.savepanel(*)
          nil
        end
        def self.openpanel(*)
          nil
        end
        @timers = {}
        def self.start_timer(*,&block)
          id=(@next_timer||0)+1;@next_timer=id;@timers[id]=block;id
        end
        def self.stop_timer(id)
          @timers.delete(id)
        end
        def self.timers
          @timers
        end
      end
      $commands = []
      require ARGV.fetch(0)
      studio = MH::ModuleStudio
      raise 'Shortcut command missing' unless $commands == ['MH Module Studio · Parametric','MH Module Studio · Mở HUD', 'MH Module Studio · Liên kết module HUD']
      fake_panel=Object.new
      fake_panel.instance_variable_set(:@draft,'preserve formulas')
      fake_panel.define_singleton_method(:show_parametric) { @opened=true }
      studio.instance_variable_set(:@panel,fake_panel)
      studio.instance_variable_get(:@parametric_command).instance_variable_get(:@block).call
      raise 'Shortcut lost existing workspace' unless fake_panel.instance_variable_get(:@opened) && fake_panel.instance_variable_get(:@draft)=='preserve formulas'
      replies = []
      library = studio::Library.new { |receiver, value| replies << [receiver, value] }
      library.request('action' => 'library_choose')
      raise 'Cancel did not acknowledge' unless replies.length == 1 && !replies.last[1]['error']
      library.config['root'] = 'D:/Thư viện có "quote"'
      library.config['folder'] = 'Tủ dưới'
      library.config['folder_keys'] = { 'Tủ dưới' => 'B' }
      library.config['view'] = 'list'
      library.config['hud_size'] = 125
      library.save_settings('hud_image_zoom'=>75)
      raise 'Image zoom changed circle size' unless library.config['hud_size']==125
      raise 'Image zoom setting lost' unless library.config['hud_image_zoom']==75
      library.persist
      raise 'Preferences lost' unless studio::Library.new.config == library.config
      Dir.mktmpdir('mh-lib-adapter') do |folder|
        path = File.join(folder, 'Khung.skp'); File.write(path, 'native fixture placeholder')
        library.config['root'] = folder; library.config['folder'] = ''; library.refresh
        library.save_settings('hud_orders'=>{''=>['Khung.skp']},'folder_keys'=>{''=>'A'})
        exported=File.join(folder,'HUD.json')
        library.export_hud_config(exported)
        raise 'Config missing order' unless studio::HUDConfig.parse(File.read(exported))['settings']['hud_orders']=={''=>['Khung.skp']}
        library.save_settings('hud_orders'=>{},'hud_image_zoom'=>30)
        library.import_hud_config(exported)
        raise 'Config import did not restore display' unless library.config['hud_image_zoom']==75 && library.config['hud_orders']=={''=>['Khung.skp']}
        before=Marshal.dump(library.config)
        bad=File.join(folder,'bad.json');File.write(bad,'{}')
        begin
          library.import_hud_config(bad)
          raise 'Invalid config accepted'
        rescue studio::Core::Error
        end
        raise 'Invalid config mutated settings' unless Marshal.dump(library.config)==before
        raise 'Import cancel changed settings' unless library.transfer_hud_config('import_config').nil? && Marshal.dump(library.config)==before
        raise 'Export cancel changed settings' unless library.transfer_hud_config('export_config').nil? && Marshal.dump(library.config)==before
        item = library.catalog['entries'].first
        raise 'Selection missing' unless library.entry('Khung.skp')['fingerprint'] == item['fingerprint']
        File.write(path, 'changed')
        begin
          library.entry('Khung.skp')
          raise 'Stale file accepted'
        rescue studio::Core::Error
        end
        library.request('action' => 'library_settings', 'settings' => { 'folder' => '../outside' })
        raise 'Bad folder not reported' unless replies.last[1]['error']
        library.request('action' => 'library_refresh')
        raise 'UI remained in error after refresh' if replies.last[1]['error']
        cached_thumbnails=library.thumbnails
        library.refresh
        raise 'Unchanged thumbnail view cache discarded' unless library.thumbnails.equal?(cached_thumbnails)
        timer=library.instance_variable_get(:@monitor_timer)
        raise 'Visible browser has no monitor' unless UI.timers.key?(timer)
        library.browser_visible=false
        raise 'Hidden browser still polls' if UI.timers.key?(timer)
        library.browser_visible=true
        fake_tool=Struct.new(:active,:blocked,:updates) do
          def editing;false;end
          def catalog_busy?;blocked;end
          def catalog_updated;self.updates+=1;end
        end.new(true,true,0)
        library.instance_variable_set(:@tool,fake_tool)
        File.rename(path,File.join(folder,'Renamed.skp'))
        reopened=studio::Library.new;reopened.refresh
        raise 'Restart/rename lost HUD slot' unless reopened.config['hud_orders']=={''=>['Renamed.skp']}
        changed=studio::LibraryCatalog.scan(folder)
        fake_monitor=Object.new
        fake_monitor.define_singleton_method(:poll) { changed }
        library.instance_variable_set(:@monitor,fake_monitor)
        library.poll_catalog
        raise 'Placement was interrupted' unless library.catalog['entries'].first['id']=='Khung.skp'
        fake_tool.blocked=false
        library.poll_catalog
        raise 'Background rename missing' unless library.catalog['entries'].first['id']=='Renamed.skp' && fake_tool.updates==1 && replies.last[1]['background']
        library.request('action'=>'library_thumbnails','ids'=>['Khung.skp'])
        raise 'Removed thumbnail batch not acknowledged' unless replies.last==['receiveLibraryThumbnails',{'Khung.skp'=>{'fingerprint'=>nil,'key'=>nil,'url'=>nil}}]
        library.browser_visible=false
        raise 'Open HUD should keep monitoring' if UI.timers.empty?
        library.tool_closed(fake_tool)
        raise 'All surfaces closed but timer leaked' unless UI.timers.empty?
        studio::Runtime.define_singleton_method(:selected_root) { Object.new }
        library.define_singleton_method(:require_owned) { |_root| nil }
        root = Struct.new(:name).new('Khung')
        studio::Runtime.define_singleton_method(:selected_root) { root }
        replies.clear
        library.request('action' => 'library_save')
        raise 'Save cancel did not acknowledge' unless replies.length == 1 && !replies.last[1]['error']
      end
      puts 'Library preferences, cancellation, path freshness and assignable command passed.'
    RUBY
    output, error, status = Open3.capture3(RbConfig.ruby, '-e', script, File.expand_path('../main.rb', __dir__))
    assert status.success?, error
    assert_includes output, 'assignable command passed'
  end
end

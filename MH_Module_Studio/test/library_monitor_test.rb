# encoding: UTF-8
require 'minitest/autorun'
require 'tmpdir'
require_relative '../library_monitor'

class ModuleStudioLibraryMonitorTest < Minitest::Test
  S=MH::ModuleStudio

  def observe(monitor,now)
    result=monitor.poll(now:now)
    result || monitor.poll(now:now+0.01)
  end

  def test_metadata_refresh_debounces_changes_and_keeps_unchanged_fingerprints
    Dir.mktmpdir do |folder|
      File.write(File.join(folder,'A.skp'),'first')
      File.write(File.join(folder,'B.skp'),'unchanged')
      original=S::LibraryCatalog.scan(folder)
      monitor=S::LibraryMonitor.new;monitor.reset(folder,original)
      assert_nil observe(monitor,0)
      File.rename(File.join(folder,'A.skp'),File.join(folder,'Renamed.skp'))
      assert_nil observe(monitor,3), 'First changed observation must not publish'
      File.write(File.join(folder,'Renamed.skp'),'save still in progress')
      assert_nil observe(monitor,6), 'A second differing observation is not stable'
      changed=observe(monitor,9)
      assert_equal ['B.skp','Renamed.skp'],(changed['entries'].map { |item| item['id'] })
      assert_equal original['entries'].last,changed['entries'].first
      assert_nil observe(monitor,12), 'An unchanged folder must not republish'
      File.delete(File.join(folder,'Renamed.skp'))
      FileUtils.mkdir_p(File.join(folder,'New folder'))
      File.write(File.join(folder,'New folder','Added.skp'),'new')
      assert_nil observe(monitor,15)
      changed=observe(monitor,18)
      assert_equal ['B.skp','New folder/Added.skp'],(changed['entries'].map { |item| item['id'] })
      assert_equal ['','New folder'],(changed['folders'].map { |item| item['id'] })
      assert_equal 'unchanged',File.read(File.join(folder,'B.skp'))
    end
  end

  def test_root_switch_and_missing_root_recovery
    Dir.mktmpdir do |folder|
      a=File.join(folder,'A');b=File.join(folder,'B');FileUtils.mkdir_p([a,b])
      File.write(File.join(a,'A.skp'),'old')
      monitor=S::LibraryMonitor.new;monitor.reset(a,S::LibraryCatalog.scan(a))
      monitor.poll(now:0)
      monitor.reset(b,S::LibraryCatalog.scan(b))
      assert_nil observe(monitor,3)
      File.write(File.join(b,'B.skp'),'new')
      assert_nil observe(monitor,6)
      assert_equal ['B.skp'],(observe(monitor,9)['entries'].map { |item| item['id'] })
      FileUtils.rm_r(b)
      assert_nil observe(monitor,12)
      assert_empty observe(monitor,15)['entries']
      FileUtils.mkdir_p(b);File.write(File.join(b,'Restored.skp'),'again')
      assert_nil observe(monitor,18)
      assert_equal ['Restored.skp'],(observe(monitor,21)['entries'].map { |item| item['id'] })
    end
  end

  def test_partial_tick_yields_and_file_removed_mid_scan_never_publishes_partial_data
    Dir.mktmpdir do |folder|
      File.write(File.join(folder,'A.skp'),'first')
      File.write(File.join(folder,'B.skp'),'keep')
      monitor=S::LibraryMonitor.new;monitor.reset(folder,S::LibraryCatalog.scan(folder))
      clock=0
      Process.stub(:clock_gettime,->(_kind) { clock+=0.005 }) do
        assert_nil monitor.poll(now:0), 'A timed-out tick must yield before completing the scan'
      end
      File.delete(File.join(folder,'A.skp'))
      assert_nil monitor.poll(now:0.1), 'A path removed between ticks must discard partial data'
      assert_nil observe(monitor,3)
      changed=observe(monitor,6)
      assert_equal ['B.skp'],(changed['entries'].map { |item| item['id'] })
    end
  end
end

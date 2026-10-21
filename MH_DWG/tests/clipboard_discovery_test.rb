# frozen_string_literal: true

# Run separately outside SketchUp: ruby MH_DWG/tests/clipboard_discovery_test.rb
# Exercise the real finder, which the placement suite replaces with a stub.
require 'minitest/autorun'
require 'tmpdir'

$LOADED_FEATURES << 'sketchup.rb'
def file_loaded?(_path) = true

module Sketchup
  class ToolsObserver; end
end
require_relative '../main'

class ClipboardDiscoveryTest < Minitest::Test
  def with_temp_directory
    previous_temp = ENV.fetch('TEMP', nil)
    Dir.mktmpdir('mh-dwg-clipboard-test-') do |directory|
      ENV['TEMP'] = directory
      @events = []
      logger = ->(event, data = {}) { @events << [event, data] }
      MH::DWG.stub(:log_event, logger) { yield directory }
    end
  ensure
    ENV['TEMP'] = previous_temp
  end

  def cad_file(directory, name, modified_at = Time.utc(2026, 10, 13))
    path = File.join(directory, name)
    File.write(path, 'test fixture; never passed to the DWG importer')
    File.utime(modified_at, modified_at, path)
    path
  end

  def test_selects_newest_autocad_or_paired_vinacad_and_ignores_unpaired_dwg
    with_temp_directory do |directory|
      cad_file(directory, 'A$C_old.dwg')
      newest = cad_file(directory, '8F0.DWG', Time.utc(2026, 10, 13, 1))
      File.write(File.join(directory, '8F0.tmp'), '')
      cad_file(directory, 'unrelated.dwg', Time.utc(2026, 10, 13, 2))

      assert_equal newest, MH::DWG.find_clipboard_dwg
    end
  end

  { disappears: Errno::ENOENT, unreadable: Errno::EACCES }.each do |scenario, error_class|
    define_method("test_#{scenario}_candidate_does_not_hide_another_valid_dwg") do
      with_temp_directory do |directory|
        good = cad_file(directory, 'A$C_good.dwg')
        bad = cad_file(directory, 'A$C_bad.dwg')
        real_mtime = File.method(:mtime)
        mtime = lambda do |path|
          raise error_class, path if path == bad

          real_mtime.call(path)
        end

        File.stub(:mtime, mtime) { assert_equal good, MH::DWG.find_clipboard_dwg }
        assert(@events.any? { |_, data| data[:path] == bad && data[:error].to_s.include?(error_class.name) })
      end
    end
  end

  def test_all_unreadable_candidates_return_nil_without_failing_the_whole_scan
    with_temp_directory do |directory|
      cad_file(directory, 'A$C_one.dwg')
      cad_file(directory, 'A$C_two.dwg')
      File.stub(:mtime, ->(path) { raise Errno::ENOENT, path }) do
        assert_nil MH::DWG.find_clipboard_dwg
      end
      assert_equal(2, @events.count { |_, data| data[:error].to_s.include?('Errno::ENOENT') })
    end
  end

  def test_selected_timestamp_is_not_read_again_just_for_logging
    with_temp_directory do |directory|
      path = cad_file(directory, 'A$C_good.dwg')
      real_mtime = File.method(:mtime)
      reads = 0
      mtime = lambda do |file|
        reads += 1
        raise Errno::ENOENT, file if reads > 1

        real_mtime.call(file)
      end

      File.stub(:mtime, mtime) { assert_equal path, MH::DWG.find_clipboard_dwg }
      assert_equal 1, reads
    end
  end

  def test_no_candidates_returns_nil
    with_temp_directory { assert_nil MH::DWG.find_clipboard_dwg }
  end
end

# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../activity'

class ActivityProduct
  attr_reader :persistent_id
  def initialize(id, values)
    @persistent_id = id
    @values = values
  end

  def get_attribute(_dict, key)
    @values[key]
  end
end

class ActivityTest < Minitest::Test
  def setup
    @activity = MH::CAD2Module::Activity
    @storage = MH::CAD2Module::Storage
  end

  def test_unnamed_scans_remain_separate_and_output_identity_is_explicit
    Dir.mktmpdir do |root|
      %w[A B].each do |id|
        @storage.event(root, 'kind' => 'scan', 'analysis' => { 'code' => "SCAN-#{id}", 'automatic_scan' => true, 'activity_id' => id })
      end
      live = [ActivityProduct.new('output-B', 'code' => 'SCAN-B', 'activity_id' => 'B')]
      rows = @activity.rows(root, live)
      assert_equal 2, rows.length
      assert_equal ['Vừa quét SP không có mã'], rows.map { |row| row['label'] }.uniq
      assert_equal 'output-B', rows.find { |row| row['key'] == 'B' }['product_id']
      assert_equal false, rows.find { |row| row['key'] == 'A' }['available']
    end
  end

  def test_all_events_beyond_thirty_and_legacy_edits_follow_session_only
    Dir.mktmpdir do |root|
      @storage.event(root, 'kind' => 'error_report', 'session' => 'own', 'analysis' => { 'code' => 'SCAN-A' })
      35.times { @storage.event(root, 'kind' => 'edit', 'session' => 'own', 'after' => { 'modules' => [] }) }
      @storage.event(root, 'kind' => 'edit', 'session' => 'another', 'after' => { 'modules' => [] })
      bytes = Dir.glob(File.join(root, 'history', '*.json')).to_h { |file| [file, File.binread(file)] }
      row = @activity.rows(root, []).first
      detail = @activity.detail(root, row, [])
      assert_equal 36, detail['events'].length
      assert detail['events'].all? { |event| event['session'] == 'own' }
      assert bytes.all? { |file, value| File.binread(file) == value }
    end
  end

  def test_removed_and_ambiguous_outputs_cannot_be_guessed_from_another_product
    Dir.mktmpdir do |root|
      @storage.event(root, 'kind' => 'build', 'analysis' => { 'code' => 'SP01' })
      unrelated = ActivityProduct.new('different', 'code' => 'SP02')
      assert_nil @activity.rows(root, [unrelated]).find { |row| row['code'] == 'SP01' }['product_id']
      copies = %w[one two].map { |id| ActivityProduct.new(id, 'code' => 'SP01') }
      row = @activity.rows(root, copies).find { |item| item['code'] == 'SP01' }
      assert row['ambiguous']
      assert_nil row['product_id']
    end
  end

  def test_new_correction_indexes_keep_activity_identity_and_details_are_compact
    Dir.mktmpdir do |root|
      analysis = { 'code' => 'SCAN-A', 'activity_id' => 'A', 'bounds' => [800, 600, 1600], 'outlines' => ['large geometry'] }
      @storage.event(root, 'kind' => 'correction', 'analysis' => analysis, 'status' => 'accepted')
      row = @activity.rows(root, []).first
      detail = @activity.detail(root, row, [])
      assert_equal 'A', row['key']
      assert_equal analysis, detail['analysis']
      refute detail['events'][0]['analysis'].key?('outlines')
      assert_equal [800, 600, 1600], detail['events'][0]['analysis']['bounds']
    end
  end
end

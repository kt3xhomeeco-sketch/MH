# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'
require_relative '../library_import'

class ModuleStudioLibraryImportTest < Minitest::Test
  S=MH::ModuleStudio

  def captured
    File.read(File.join(__dir__,'fixtures/owned-plinth-copies.json'),encoding:'UTF-8')
  end

  def test_preview_checks_only_display_bounds_and_full_load_rejects_invalid_rules
    data=JSON.parse(captured).merge('format'=>'mh_module_library','version'=>1,'name'=>'Chân bệ');data['rule']=nil;raw=JSON.generate(data)
    importer=S::LibraryImport.new
    preview=importer.preview(raw)
    assert_equal data['snapshot']['parts'].length,preview['snapshot']['parts'].length
    refute preview.key?('rule')
    assert_raises(S::Core::Error) { importer.payload(raw) }
    data['snapshot']['parts'].first['bounds']=[[10,0,0],[0,1,1]]
    assert_raises(S::Core::Error) { importer.preview(JSON.generate(data)) }
    assert_raises(S::Core::Error) { importer.preview('{') }
    assert_raises(S::Core::Error) { importer.preview(raw.sub('"version":1','"version":99')) }
  end

  def test_assembly_preview_has_a_valid_outer_box_without_flattening_member_rules
    data={'format'=>'mh_module_assembly','version'=>1,'name'=>'Cụm','snapshot'=>{'envelope'=>[[0,0,0],[600,500,800]]}}
    result=S::LibraryImport.new.preview(JSON.generate(data))
    assert_equal [[0.0,0.0,0.0],[600.0,500.0,800.0]],result['snapshot']['parts'].first['bounds']
    assert_equal '@assembly',result['snapshot']['parts'].first['key']
  end

  def test_cache_is_private_content_keyed_bounded_and_does_not_cache_failures
    importer=S::LibraryImport.new;calls=0
    loader=lambda do |raw|
      calls+=1
      raise S::Core::Error,'Bad payload' if raw=='bad'
      {'name'=>raw,'nested'=>{'values'=>[18.6]}}
    end
    S::LibraryCatalog.stub(:payload,loader) do
      first=importer.payload('a');first['nested']['values'][0]=200
      assert_equal 18.6,importer.payload('a')['nested']['values'][0]
      assert_equal 1,calls
      assert_equal 'changed',importer.payload('changed')['name']
      assert_equal 2,calls
      2.times { assert_raises(S::Core::Error) { importer.payload('bad') } }
      assert_equal 4,calls
      16.times { |index| importer.payload('entry-'+index.to_s) }
      importer.payload('a');assert_equal 21,calls,'Old entry evicted at the bounded item count'
      assert_operator importer.instance_variable_get(:@bytes),:<=,S::LibraryImport::MAX_BYTES
    end
    giant={'blob'=>'x'*(S::LibraryImport::MAX_BYTES+1)};calls=0
    S::LibraryCatalog.stub(:payload,->(_raw) { calls+=1;giant }) do
      2.times { importer.payload('large') }
      assert_equal 2,calls,'Oversized normalized data is not cached'
    end
  end

  def test_cached_legacy_copy_rules_keep_the_same_parametric_result
    data=JSON.parse(captured).merge('format'=>'mh_module_library','version'=>1,'name'=>'Chân bệ')
    importer=S::LibraryImport.new;raw=JSON.generate(data)
    importer.prefetch(raw);importer.instance_variable_get(:@worker).join
    first=importer.payload(raw);cached=importer.payload(raw)
    assert S::DCCopies.enabled?(cached['rule'])
    targets={'b6sochanphu'=>7}
    expected=S::Core.plan(first['rule'],first['snapshot'],targets)
    actual=S::Core.plan(cached['rule'],cached['snapshot'],targets)
    assert_equal expected,actual
    assert_operator actual['parts'].length,:>,cached['snapshot']['parts'].length
  end

  def test_prefetch_is_one_portable_worker_and_placement_shares_its_result
    importer=S::LibraryImport.new;entered=Queue.new;release=Queue.new;calls=Queue.new
    loader=lambda do |raw|
      calls << Thread.current
      entered << true
      release.pop
      {'name'=>raw,'values'=>[18.6]}
    end
    S::LibraryCatalog.stub(:payload,loader) do
      raw='original'
      importer.prefetch(raw);entered.pop
      raw.replace('edited')
      importer.prefetch('other')
      assert_equal 1,calls.size,'Rapid selection cannot start more workers'
      refute_equal Thread.current,calls.pop,'Only portable payload work runs off the UI thread'
      placement=Thread.new { importer.payload('original') }
      release << true
      result=placement.value
      importer.instance_variable_get(:@worker).join
      assert_equal 'original',result['name'],'Worker owns its input string'
      result['values'][0]=200
      assert_equal 18.6,importer.payload('original')['values'][0]
      importer.prefetch('original')
      assert_equal 0,calls.size,'Prefetch and placement normalize the same content once'
    ensure
      release << true
      importer.instance_variable_get(:@worker)&.join
      placement&.join
    end
  end

  def test_failed_prefetch_cannot_authorize_import_or_hide_its_error
    importer=S::LibraryImport.new;calls=0
    S::LibraryCatalog.stub(:payload,->(_raw) { calls+=1;raise S::Core::Error,'Invalid formula' }) do
      importer.prefetch('bad');importer.instance_variable_get(:@worker).join
      assert_equal 'Invalid formula',assert_raises(S::Core::Error) { importer.payload('bad') }.message
      assert_equal 2,calls,'Actual placement retries validation after a speculative failure'
      refute importer.instance_variable_get(:@foreground_waiting),'Failed placement clears its foreground wait'
      importer.prefetch('x'*(S::LibraryCatalog::MAX_BYTES+1))
      assert_equal 2,calls,'Oversized payloads never start a worker'
    end
  end
end

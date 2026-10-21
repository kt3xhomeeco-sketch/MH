# encoding: UTF-8
require 'minitest/autorun'
require 'tmpdir'
require_relative '../hud_config'

class ModuleStudioHUDConfigTest < Minitest::Test
  S=MH::ModuleStudio

  def settings
    S::LibraryCatalog.settings('root'=>'D:/old','folder'=>'Tấm','folder_keys'=>{'Tấm'=>'T'},
      'hud_orders'=>{'Tấm'=>['Khác/Đứng.skp','Tấm/Ngang.skp']},'hud_size'=>28,'hud_image_zoom'=>250,'hud_position'=>'cursor')
  end

  def fixture(directory)
    FileUtils.mkdir_p(File.join(directory,'Tấm'));FileUtils.mkdir_p(File.join(directory,'Khác'))
    File.write(File.join(directory,'Tấm/Ngang.skp'),'horizontal');File.write(File.join(directory,'Khác/Đứng.skp'),'vertical')
    S::LibraryCatalog.scan(directory)
  end

  def hashed(catalog)
    catalog.merge('entries'=>catalog['entries'].map { |row| row.merge('sha256'=>Digest::SHA256.file(row['path']).hexdigest) })
  end

  def test_rename_folder_and_file_keeps_cross_folder_slot_one_and_folder_hotkey
    Dir.mktmpdir do |directory|
      before=fixture(directory)
      bindings=S::HUDConfig.capture(before)
      File.rename(File.join(directory,'Tấm'),File.join(directory,'Tên tùy ý'))
      File.rename(File.join(directory,'Khác/Đứng.skp'),File.join(directory,'Khác/Đứng mới.skp'))
      after=S::LibraryCatalog.scan(directory)
      restored,missing=S::HUDConfig.remap(settings,bindings,after)
      assert_empty missing
      assert_equal 'Tên tùy ý',restored['folder']
      assert_equal({'Tên tùy ý'=>'T'},restored['folder_keys'])
      assert_equal ['Khác/Đứng mới.skp','Tên tùy ý/Ngang.skp'],restored['hud_orders']['Tên tùy ý']
      assert_equal 'Khác/Đứng mới.skp',S::LibraryCatalog.hud_entries(after['entries'],restored).first['id']
    end
  end

  def test_portable_json_matches_renamed_copy_by_unique_content_without_exporting_absolute_paths
    Dir.mktmpdir do |directory|
      before=hashed(fixture(File.join(directory,'A')))
      data=S::HUDConfig.document(settings,before)
      encoded=JSON.generate(data)
      refute_includes encoded,directory
      refute data['settings'].key?('root')
      FileUtils.cp_r(File.join(directory,'A'),File.join(directory,'B'))
      File.rename(File.join(directory,'B/Tấm'),File.join(directory,'B/Renamed'))
      File.rename(File.join(directory,'B/Khác/Đứng.skp'),File.join(directory,'B/Khác/Vertical.skp'))
      after=hashed(S::LibraryCatalog.scan(File.join(directory,'B')))
      parsed=S::HUDConfig.parse(encoded)
      restored,missing=S::HUDConfig.remap(parsed['settings'],parsed['library'],after)
      assert_empty missing
      assert_equal ['Khác/Vertical.skp','Renamed/Ngang.skp'],restored['hud_orders']['Renamed']
      assert_equal({'Renamed'=>'T'},restored['folder_keys'])
      %w[hud_size hud_image_zoom hud_position].each { |key| assert_equal settings[key],restored[key] }
    end
  end

  def test_ambiguous_hash_does_not_bind_slot_to_arbitrary_duplicate
    Dir.mktmpdir do |directory|
      before=hashed(fixture(File.join(directory,'A')))
      after=hashed(fixture(File.join(directory,'B')))
      item=after['entries'].find { |r| r['id']=='Khác/Đứng.skp' }
      after['entries'].delete(item)
      after['entries'] += %w[copy1.skp copy2.skp].map { |id| item.merge('id'=>id,'folder'=>'') }
      restored,missing=S::HUDConfig.remap(settings,S::HUDConfig.capture(before),after)
      assert_equal ['Khác/Đứng.skp'],missing
      assert_equal ['Tấm/Ngang.skp'],restored['hud_orders']['Tấm']
    end
  end

  def test_invalid_config_is_rejected_and_missing_files_do_not_change_other_slots
    data=S::HUDConfig.document(settings,{'folders'=>[{'id'=>''}],'entries'=>[]})
    [nil,'{}','[1]','not json',JSON.generate(data.merge('version'=>2)), 'x'*(S::HUDConfig::MAX_BYTES+1)].each do |raw|
      assert_raises(S::Core::Error) { S::HUDConfig.parse(raw) }
    end
    ['../escape','C:/outside','/outside','a/../b'].each do |id|
      bad=S::Core.copy_data(data);bad['library']['entries']=[{'id'=>id,'folder'=>''}]
      assert_raises(S::Core::Error) { S::HUDConfig.parse(JSON.generate(bad)) }
    end
    duplicate=S::Core.copy_data(data);duplicate['library']['folders']*=2
    assert_raises(S::Core::Error) { S::HUDConfig.parse(JSON.generate(duplicate)) }
    assert_equal settings.slice(*S::HUDConfig::KEYS),S::HUDConfig.parse(JSON.generate(data))['settings']
  end
end

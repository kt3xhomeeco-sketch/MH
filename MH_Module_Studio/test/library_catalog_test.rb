# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative '../library_catalog'
require_relative '../rule_system'

class ModuleStudioLibraryCatalogTest < Minitest::Test
  Catalog = MH::ModuleStudio::LibraryCatalog

  def test_settings_normalize_sizes_modes_and_unique_folder_shortcuts
    settings = Catalog.settings('view' => 'invalid', 'thumbnail_size' => 'bad', 'hud_size' => 900,
      'folder_keys' => { 'Tủ dưới' => 'b', 'other' => 'B', 'invalid' => 'Esc', 'root' => 'a' }, 'untrusted' => 'discard')
    assert_equal 'grid', settings['view']
    assert_equal 150, settings['thumbnail_size']
    assert_equal 140, settings['hud_size']
    assert_equal({ 'Tủ dưới' => 'B', 'root' => 'A' }, settings['folder_keys'])
    refute settings.key?('untrusted')
    assert_equal 24, Catalog.settings('hud_size' => -30)['hud_size']
    assert_equal 100, Catalog.settings({})['hud_image_zoom']
    assert_equal 100, Catalog.settings('hud_image_zoom' => 'bad')['hud_image_zoom']
    assert_equal 25, Catalog.settings('hud_image_zoom' => -1)['hud_image_zoom']
    assert_equal 300, Catalog.settings('hud_image_zoom' => 1000)['hud_image_zoom']
    assert_equal 75, Catalog.settings('hud_image_zoom' => '75')['hud_image_zoom']
    assert_equal settings, Catalog.settings(JSON.parse(JSON.generate(settings)))
  end

  def test_scan_nested_unicode_folders_and_case_insensitive_skp
    Dir.mktmpdir('mh-library') do |base|
      root = File.join(base, 'Thư viện'); FileUtils.mkdir_p(File.join(root, 'Tủ dưới', 'Góc'))
      File.write(File.join(root, 'Tủ dưới', 'Khung.SKP'), 'fake')
      File.write(File.join(root, 'Tủ dưới', 'copy.skb'), 'ignore')
      result = Catalog.scan(root)
      assert_equal ['', 'Tủ dưới', 'Tủ dưới/Góc'], (result['folders'].map { |row| row['id'] })
      assert_equal ['Tủ dưới/Khung.SKP'], (result['entries'].map { |row| row['id'] })
      item = result['entries'].first
      assert_equal Catalog.fingerprint(item['path']),item['fingerprint']
      assert_equal 'Khung', item['name']
      assert_equal 'Tủ dưới', item['folder']
      before = item['fingerprint']
      File.write(item['path'], 'new content')
      refute_equal before, Catalog.fingerprint(item['path'])
      sibling = File.join(base, 'Thư viện-other'); FileUtils.mkdir_p(sibling)
      refute Catalog.inside?(root, sibling)
      assert Catalog.inside?(root, item['path'])
      refute Catalog.inside?(root, File.join(root, 'missing.skp'))
    end
  end

  def test_filter_matches_vietnamese_without_accents_and_stays_in_selected_folder
    items = [{ 'name' => 'Khung BẾP dưới', 'folder' => 'Tủ' }, { 'name' => 'Khung bếp dưới', 'folder' => 'Khác' }]
    assert_equal [items.first], Catalog.filtered(items, 'Tủ', 'bep duoi')
    assert_empty Catalog.filtered(items, 'Tủ', 'khong co')
  end

  def test_layout_keeps_all_eight_image_circles_separate_and_inside_view
    [[1200, 750], [700, 500], [450, 350]].each do |width, height|
      [24, 52, 86, 140].each do |size|
        layout = Catalog.layout(width, height, size)
        points = layout['items']
        points.combination(2).each { |a, b| assert_operator Math.hypot(a[0]-b[0], a[1]-b[1]), :>, layout['size'] }
        points.each do |x, y|
          assert_operator x - layout['size']/2, :>=, 0
          assert_operator x + layout['size']/2, :<=, width
          assert_operator y - layout['size']/2, :>=, 0
          assert_operator y + layout['size']/2, :<=, height - 50
        end
      end
    end
  end

  def test_hud_orders_are_sanitized_saved_and_do_not_override_grid_sort
    items = %w[a b c d e f g h i].map { |id| { 'id' => id, 'name' => id.upcase, 'folder' => 'main' } }
    items << { 'id' => 'other/x', 'name' => 'Other X', 'folder' => 'other' }
    settings = Catalog.settings('folder' => 'main', 'hud_position' => 'invalid',
      'hud_orders' => { 'main' => ['c', 'c', 12, nil, 'a', 'missing'], 'bad' => false })
    assert_equal 'center', settings['hud_position']
    assert_equal({ 'main' => %w[c a missing] }, settings['hud_orders'])
    assert_equal %w[c a b d e f g h i], (Catalog.hud_entries(items, settings).map { |item| item['id'] })
    orders = Catalog.move_hud_item(items, settings, 'a', 4)
    settings = Catalog.settings(settings.merge('hud_orders' => orders, 'hud_position' => 'cursor'))
    assert_equal %w[c b d e a f g h i], (Catalog.hud_entries(items, settings).map { |item| item['id'] })
    orders = Catalog.move_hud_item(items, settings, 'other/x', 1)
    settings = Catalog.settings(JSON.parse(JSON.generate(settings.merge('hud_orders' => orders))))
    assert_equal %w[c other/x b d e a f g h i], (Catalog.hud_entries(items, settings).map { |item| item['id'] })
    assert_equal ['other/x'], (Catalog.hud_entries(items, settings, 'other').map { |item| item['id'] })
    assert_equal %w[a b c d e f g h i], (Catalog.filtered(items, 'main').map { |item| item['id'] })
    assert_equal 'cursor', settings['hud_position']
    assert_raises(MH::ModuleStudio::Core::Error) { Catalog.move_hud_item(items, settings, 'missing', 0) }
    assert_raises(MH::ModuleStudio::Core::Error) { Catalog.move_hud_item(items, settings, 'a', -1) }
    assert_equal 'a', Catalog.hud_entries(items, settings.merge('hud_orders' => {})).first['id']
  end

  def test_cursor_layout_stays_anchored_until_clamped_at_each_corner
    [24, 52, 140].each do |size|
      centered = Catalog.layout(1400, 1000, size)
      assert_equal [700, 500], centered['center']
      anchored = Catalog.layout(1400, 1000, size, center: [750, 520])
      assert_equal [750, 520], anchored['center']
      [[0, 0], [1400, 0], [0, 1000], [1400, 1000]].each do |cursor|
        layout = Catalog.layout(1400, 1000, size, center: cursor)
        extent = layout['radius'] + layout['size'] / 2
        x, y = layout['center']
        assert_operator x - extent, :>=, 0
        assert_operator x + extent, :<=, 1400
        assert_operator y - extent - 40, :>=, 0
        assert_operator y + extent + 80, :<=, 1000
      end
    end
  end

  def test_embedded_payload_keeps_formulas_visibility_and_current_inputs
    samples = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'dc_mixed_thickness.json'), encoding: 'UTF-8'))
    core = MH::ModuleStudio::Core
    rule = MH::ModuleStudio::RuleSystem.build(samples.last, core.learn_module(samples))
    core.set_exposed_parameters!(rule, [rule['parameters'].first['key']])
    data = { 'format' => 'mh_module_library', 'version' => 1, 'name' => 'Tủ dưới', 'rule' => rule,
             'values' => rule['parameters'].to_h { |param| [param['key'], param['value']] }, 'snapshot' => samples.last }
    restored = Catalog.payload(JSON.generate(data))
    assert_equal MH::ModuleStudio::ThicknessSymbols.normalize(rule), restored['rule']
    assert_equal rule['formula_engine'],restored['rule']['formula_engine']
    assert_equal rule['exposed_parameter_keys'],restored['rule']['exposed_parameter_keys']
    assert_equal data['values'], restored['values']
    assert_operator restored['rule']['parameters'].length, :>, restored['rule']['exposed_parameter_keys'].length
    assert_raises(core::Error) { Catalog.payload(nil) }
    assert_raises(core::Error) { Catalog.payload('{') }
    assert_raises(core::Error) { Catalog.payload(JSON.generate(data.merge('version' => 2))) }
    altered = Marshal.load(Marshal.dump(data)); altered['snapshot']['parts'].first['key'] = 'wrong'
    assert_raises(core::Error) { Catalog.payload(JSON.generate(altered)) }
  end
end

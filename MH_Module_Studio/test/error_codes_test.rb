# encoding: UTF-8
require 'minitest/autorun'
require_relative '../error_codes'

class ErrorCodesTest < Minitest::Test
  E=MH::ModuleStudio::ErrorCodes

  def test_action_maps_to_owning_area_code
    assert_equal 'MH-PAR',E.area_for('parametric_apply')
    assert_equal 'MH-PAR',E.area_for('rule_preview')
    assert_equal 'MH-ASM',E.area_for('assembly_probe')
    assert_equal 'MH-LIB',E.area_for('library_import')
    assert_equal 'MH-SCL',E.area_for('scale_preview')
    assert_equal 'MH-UPD',E.area_for('options_update')
    assert_equal 'MH-UPD',E.area_for('redraw')
    assert_equal 'MH-RUN',E.area_for('something_else')
    assert_equal 'MH-RUN',E.area_for(nil)
  end

  def test_tag_prefixes_once
    assert_equal '[MH-LIB] Không đọc được thư viện.',E.tag('MH-LIB','Không đọc được thư viện.')
    assert_equal '[MH-LIB] Không đọc được thư viện.',E.tag('MH-LIB','[MH-LIB] Không đọc được thư viện.')
    assert_equal '[MH-RUN] ',E.tag('MH-RUN',nil)
  end

  def test_for_action_uses_action_area
    assert_equal '[MH-UPD] Hệ số không hợp lệ.',E.for_action('options_update','Hệ số không hợp lệ.')
    assert_equal '[MH-RUN] Hệ số không hợp lệ.',E.for_action(nil,'Hệ số không hợp lệ.')
  end
end

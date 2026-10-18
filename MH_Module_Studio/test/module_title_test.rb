# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioModuleTitleTest < Minitest::Test
  S=MH::ModuleStudio

  def test_capture_label_cannot_override_source_name_or_become_a_generated_module_name
    snapshot=JSON.parse(File.read(File.join(__dir__,'fixtures/readable_nested_dc.json'),encoding:'UTF-8'))
    snapshot['label']='Trạng thái 1';snapshot['module_name']='Khung Nóc Lọt'
    before=JSON.generate(snapshot)
    assert_equal 'Khung Nóc Lọt',S::Parametric.module_title(snapshot,fallback:'Trạng thái 1')
    rule=S::StudioCalculation.build_system([snapshot])
    assert_equal 'Khung Nóc Lọt',rule['module_name']
    assert_equal 'source',rule['module_name_source']
    assert_equal before,JSON.generate(snapshot)
    legacy=rule.merge('module_name'=>'Trạng thái 1','module_name_source'=>nil)
    assert_equal 'Khung Nóc Lọt',S::Parametric.module_title(snapshot,rule:legacy)
  end

  def test_explicit_renames_are_retained_and_legacy_inputs_fall_back_to_dc_or_filename
    snapshot={'label'=>'Trạng thái 1','dc_inputs'=>{'_name'=>'<b>Khung</b>'}}
    assert_equal 'Khung',S::Parametric.module_title(snapshot)
    snapshot.delete('dc_inputs');snapshot['source']={'path'=>'D:\\Library\\Tủ dưới.skp'}
    assert_equal 'Tủ dưới',S::Parametric.module_title(snapshot)
    snapshot['module_name']='Khung Nóc Lọt'
    renamed=S::Parametric.rename_display({'parts'=>[]},'Tên riêng')
    assert_equal 'Tên riêng',S::Parametric.module_title(snapshot,rule:renamed)
    explicit=S::Parametric.rename_display({'parts'=>[]},'Trạng thái 1')
    assert_equal 'Trạng thái 1',S::Parametric.module_title(snapshot,rule:explicit)
    assert_equal 'Module',S::Parametric.module_title({'label'=>'Trạng thái 1'})
    generic={'label'=>'Trạng thái 1','module_name'=>'MH File Module','source'=>{'path'=>'D:/Library/Nẹp bù.skp'}}
    assert_equal 'Nẹp bù',S::Parametric.module_title(generic)
    legacy={'module_name'=>'Trạng thái 1','formula_engine'=>{'attribute_program'=>{'dc_inputs'=>{'_name'=>'Khung gốc'}}}}
    assert_equal 'Khung gốc',S::Parametric.module_title({'label'=>'Trạng thái 1'},rule:legacy)
  end
end

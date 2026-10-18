# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioAssemblyPresentationTest < Minitest::Test
  S=MH::ModuleStudio

  def anchor(id,name='Module')
    {'root'=>id,'module_name'=>name}
  end

  def link(id,a,b,**extra)
    {'id'=>id,'mode'=>'contact','a'=>a,'b'=>b,'gap'=>0}.merge(extra.transform_keys(&:to_s))
  end

  def test_pair_names_are_separate_once_with_all_relations_below_and_private_data
    a=anchor('A','Khung');b=anchor('B','Cánh')
    rows=[link('touch',a,b),link('front',b,a,relation:'coplanar')]
    before=JSON.generate(rows)
    groups=S::AssemblyPresentation.groups(rows)
    assert_equal 1,groups.size
    assert_equal(%w[Khung Cánh],groups.first['modules'].map { |member| member['name'] })
    assert_equal 2,groups.first['links'].length
    assert_match(/Tiếp xúc/,groups.first['links'][0]['label'])
    assert_match(/Đồng phẳng/,groups.first['links'][1]['label'])
    groups.first['links'].first['a']['module_name']='Changed'
    groups.first['modules'].first['ref']['root']='Changed'
    assert_equal before,JSON.generate(rows)
    assert_match(/Khoảng cách/,S::AssemblyPresentation.label(rows.last.merge('gap'=>3)))
  end

  def test_grouped_assembly_lists_every_member_including_third_member_without_a_pair_link
    a=anchor('A','Tủ');b=anchor('B','Cánh');c=anchor('C','Nẹp')
    members=[a,b,c].map { |ref| {'ref'=>ref,'name'=>ref['module_name']} }
    groups=S::AssemblyPresentation.groups([link('one',a,b)],scope:'assembly',members:members,name:'Cụm tủ')
    assert_equal 1,groups.size
    assert_equal 'Cụm tủ',groups.first['name']
    assert_equal(%w[Tủ Cánh Nẹp],groups.first['modules'].map { |member| member['name'] })
    assert_equal 'one',groups.first['links'].first['id']
    groups.first['modules'].last['name']='Other'
    assert_equal 'Nẹp',members.last['name']
    assert_empty S::AssemblyPresentation.groups([],scope:'assembly',members:members)
  end

  def test_identity_does_not_merge_distinct_same_named_modules_or_copied_assemblies
    a=anchor('A');b=anchor('B');c=anchor('C')
    groups=S::AssemblyPresentation.groups([link('ab',a,b),link('bc',b,c)])
    assert_equal 2,groups.size
    assert_equal 2,groups.first['modules'].size
    refute_equal groups.first['id'],groups.last['id']
    one=S::AssemblyPresentation.groups([link('ab',a,b)],scope:'one')
    two=S::AssemblyPresentation.groups([link('ab',a,b)],scope:'two')
    refute_equal one.first['id'],two.first['id']
  end
end

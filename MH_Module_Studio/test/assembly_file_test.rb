# encoding: UTF-8
require 'minitest/autorun'
require_relative '../library'

class ModuleStudioAssemblyFileTest < Minitest::Test
  S=MH::ModuleStudio

  def data
    {'format'=>S::AssemblyFile::FORMAT,'version'=>1,'name'=>'Cụm','snapshot'=>{'envelope'=>[[0,0,0],[100,100,100]]},
     'members'=>%w[A B].map { |key| {'key'=>key,'frame'=>[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]} },
     'links'=>[{'id'=>'link','mode'=>'contact','gap'=>3,'a'=>{'root'=>'A','axis'=>0,'side'=>1},'b'=>{'root'=>'B','axis'=>0,'side'=>0}}]}
  end

  def test_payload_accepts_only_local_stable_member_references_and_retains_independent_data
    source=data
    restored=S::LibraryCatalog.payload(JSON.generate(source))
    assert_equal source,restored
    source['construction_envelope']=[[0,0,0],[100,80,100]]
    assert_equal source,S::LibraryCatalog.payload(JSON.generate(source))
    bad=data;bad['construction_envelope']=[[0,0,0],[100,-1,100]]
    assert_raises(S::Core::Error) { S::AssemblyFile.payload(bad) }
    ['missing',nil].each do |key|
      bad=data;bad['links'].first['b']['root']=key
      assert_raises(S::Core::Error) { S::AssemblyFile.payload(bad) }
    end
    bad=data;bad['links'].first['external']=true
    assert_raises(S::Core::Error) { S::AssemblyFile.payload(bad) }
    bad=data;bad['members'].last['key']='A'
    assert_raises(S::Core::Error) { S::AssemblyFile.payload(bad) }
    bad=data;bad['members'].last['frame'][0]=Float::INFINITY
    assert_raises(S::Core::Error) { S::AssemblyFile.payload(bad) }
    bad=data;bad['links'] << {'id'=>'reverse','mode'=>'contact','a'=>{'root'=>'B'},'b'=>{'root'=>'A'}}
    assert_raises(S::Core::Error) { S::AssemblyFile.payload(bad) }
  end
end

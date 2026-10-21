# encoding: UTF-8
require 'minitest/autorun'
require 'tmpdir'
require_relative '../library'

class ModuleStudioLibraryThumbnailsTest < Minitest::Test
  S=MH::ModuleStudio

  def test_per_file_views_persist_without_changing_source_fingerprints_and_refresh_cache_keys
    Dir.mktmpdir('mh-thumb-test') do |folder|
      %w[A B].each { |name| File.write(File.join(folder,name+'.skp'),'source '+name) }
      entries=S::LibraryCatalog.scan(folder)['entries']; a,b=entries
      before=entries.to_h { |item| [item['path'],Digest::SHA256.file(item['path']).hexdigest] }
      thumbnails=S::LibraryThumbnails.new(folder)
      thumbnails.define_singleton_method(:render) do |_item,view,output|
        FileUtils.mkdir_p(File.dirname(output));File.write(output,'thumbnail '+view)
      end
      assert_equal 'front',thumbnails.view(a)
      refute_equal a['fingerprint'],thumbnails.key(a),'Default front must not reuse saved-SKP pixels'
      path=thumbnails.update(a,'front'); first=thumbnails.key(a)
      assert File.file?(path)
      assert_equal 'front',thumbnails.view(a)
      assert_equal 'front',thumbnails.view(b)
      refute_equal a['fingerprint'],first
      loaded=S::LibraryThumbnails.new(folder)
      assert_equal first,loaded.key(a)
      assert_equal 'front',loaded.view(a)
      assert_equal path,loaded.path(a)
      thumbnails.update(a,'front')
      refute_equal first,thumbnails.key(a),'Explicit Update regenerates even the same view'
      preview=thumbnails.preview_path(b)
      assert_equal 'thumbnail saved',File.read(preview)
      refute_equal preview,thumbnails.path(b),'Preview must not become the final front-camera image'
      assert_equal 'thumbnail front',File.read(thumbnails.path(b))
      thumbnails.update(b,'saved')
      assert_equal 'saved',S::LibraryThumbnails.new(folder).view(b),'Explicit saved-image choice is retained'
      assert_equal before,(entries.to_h { |item| [item['path'],Digest::SHA256.file(item['path']).hexdigest] })
      assert_equal 2,S::LibraryCatalog.scan(folder)['entries'].length
      assert_raises(S::Core::Error) { thumbnails.update(a,'arbitrary') }
      old=thumbnails.key(a)
      thumbnails.define_singleton_method(:render) { |*_args| raise S::Core::Error,'Cannot render' }
      assert_raises(S::Core::Error) { thumbnails.update(a,'top') }
      assert_equal old,S::LibraryThumbnails.new(folder).key(a)
      assert_equal old,thumbnails.key(a)
    end
  end
end

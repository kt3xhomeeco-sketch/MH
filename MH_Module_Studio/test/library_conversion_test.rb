# encoding: UTF-8
require 'minitest/autorun'
require 'open3'
require 'rbconfig'

class ModuleStudioLibraryConversionTest < Minitest::Test
  def test_batch_controller_progress_cancel_roots_and_cancelled_folder_picker
    script=<<~'RUBY'
      require 'tmpdir'
      module Sketchup
        class Group;end
        class ComponentInstance;end
        def self.read_default(_section,_key,default);default;end
        def self.write_default(*);end
        def self.active_model;$model;end
        def self.status_text=(_value);end
      end
      module UI
        def self.select_directory(**);nil;end
        def self.start_timer(*,&block);@timer=block;1;end
        def self.stop_timer(*);@timer=nil;end
      end
      require ARGV.fetch(0)
      s=MH::ModuleStudio
      $model=Struct.new(:active_path,:active_entities,:definitions,:selection).new(nil,[],[],[])
      stub=Struct.new(:tool).new(nil)
      s.define_singleton_method(:library) { stub }
      replies=[]
      lib=s::Library.new { |receiver,value| replies << [receiver,Marshal.load(Marshal.dump(value))] }
      lib.request('action'=>'library_conversion_source')
      raise 'Cancel picker missing acknowledgement' unless replies.last[0]=='receiveLibraryConversion' && !replies.last[1]['error']
      Dir.mktmpdir do |base|
        source=File.join(base,'source');dest=File.join(base,'dest')
        FileUtils.mkdir_p(File.join(source,'Nested'));FileUtils.mkdir_p(dest)
        File.write(File.join(source,'A.skp'),'a');File.write(File.join(source,'Nested/B.SKP'),'b')
        klass=s::DCLibraryConversion
        [source,File.join(source,'Nested'),base].each do |target|
          begin
            klass.new(source:source,destination:target)
            raise 'Nested/source target accepted'
          rescue s::Core::Error
          end
        end
        klass.class_eval do
          def convert(path,target_path:nil)
            {'relative'=>relative(path),'status'=>'converted','source_unchanged'=>true}
          end
        end
        lib.conversion_setup.merge!('source'=>source,'destination'=>dest)
        lib.request('action'=>'library_conversion_start','update'=>true)
        worker=lib.instance_variable_get(:@conversion)
        raise 'Batch did not start' unless worker.running? && worker.report['total']==2 && replies.last[1]['running']
        worker.tick
        raise 'Progress not acknowledged' unless worker.report['processed']==1 && replies.last[1]['report']['converted']==1
        lib.request('action'=>'library_conversion_source')
        raise 'Root could change while running' unless replies.last[1]['error'] && lib.conversion_setup['source']==source
        lib.request('action'=>'library_conversion_cancel')
        raise 'Cancel failed' unless !worker.running? && worker.report['status']=='cancelled' && worker.report['processed']==1
        raise 'Report not written' unless File.file?(File.join(dest,'.conversion/report.json'))
        lib.request('action'=>'library_conversion_start','update'=>false)
        worker=lib.instance_variable_get(:@conversion)
        3.times { worker.tick }
        raise 'Nested files not processed or not complete' unless worker.report['status']=='complete' && worker.report['files'].map { |r| r['relative'] }.sort==['A.skp','Nested/B.SKP']
        raise 'UI remained blocked' if replies.last[1]['running']
        raise 'Unexpected model mutation' unless $model.active_entities.empty? && $model.definitions.empty? && $model.selection.empty?
      end
      puts 'Batch roots, progress, cancellation, retry and folder picker cancellation passed.'
    RUBY
    out,err,status=Open3.capture3(RbConfig.ruby,'-e',script,File.expand_path('../library.rb',__dir__))
    assert status.success?,err
    assert_includes out,'folder picker cancellation passed'
  end
end

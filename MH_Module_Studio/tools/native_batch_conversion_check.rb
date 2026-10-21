# encoding: UTF-8
require 'tmpdir'

module MH
  module ModuleStudio
    module NativeBatchConversionCheck
      extend self

      def run
        model=Sketchup.active_model
        source_path='D:/Cong viec/Sketchup/DC/MH/1.TA Nẹp Bù Phải.skp'
        raise 'Pinned source SKP missing' unless File.file?(source_path)
        original_sha=Digest::SHA256.file(source_path).hexdigest
        ids=model.entities.map(&:persistent_id);defs=model.definitions.to_a;selection=model.selection.to_a
        report={'ok'=>false,'checks'=>[]}
        Dir.mktmpdir('mh066-') do |base|
          input=File.join(base,'DC');output=File.join(base,'Library')
          FileUtils.mkdir_p(File.join(input,'Nested'));FileUtils.mkdir_p(output)
          path=File.join(input,'Nested/Filler.skp')
          FileUtils.cp(source_path,path)
          File.write(File.join(input,'Invalid.skp'),'not a SketchUp file')
          source_sha=Digest::SHA256.file(path).hexdigest
          worker=DCLibraryConversion.new(source:input,destination:output)
          worker.start
          3.times { worker.tick }
          raise 'Expected one converted and one failed source' unless worker.report['status']=='complete' && worker.report['converted']==1 && worker.report['failed']==1
          target=File.join(output,'Nested/Filler.skp')
          data=ModuleFile.read(target)
          row=Parametric.variables(data['rule']).find { |r| r['binding']=='xuong' }
          raise 'Batch file lost Xuong' unless row && row['value']==50 && row['unit']=='mm'
          raise 'Filename/module title differs' unless data['name']=='Filler' && data['rule']['module_name']=='Filler'
          report['checks'] << 'Recursive batch converts supported DC with Xuong=50 mm, retains filename and reports invalid SKP separately'
          kept=Digest::SHA256.file(target).hexdigest
          skip=DCLibraryConversion.new(source:input,destination:output)
          skip.start;3.times { skip.tick }
          raise 'Default changed existing target' unless skip.report['existing']==1 && Digest::SHA256.file(target).hexdigest==kept
          update=DCLibraryConversion.new(source:input,destination:output,update:true)
          update.start;3.times { update.tick }
          converted=update.report['files'].find { |r| r['relative']=='Nested/Filler.skp' }
          raise 'Verified update missing backup' unless converted['status']=='converted' && converted['replaced_existing'] && File.file?(converted['backup']) && Digest::SHA256.file(converted['backup']).hexdigest==kept
          report['checks'] << 'Default skip preserves provenance; explicit update verifies existing output and creates matching backup'
          stop=DCLibraryConversion.new(source:input,destination:output)
          stop.start;stop.cancel
          retry_worker=DCLibraryConversion.new(source:input,destination:output,update:true)
          retry_worker.start;3.times { retry_worker.tick }
          raise 'Cancel lost prior output provenance' unless retry_worker.report['converted']==1 && retry_worker.report['files'].find { |r| r['relative']=='Nested/Filler.skp' }['replaced_existing']
          report['checks'] << 'Cancelling before any file retains earlier output signatures for a later upgrade'
          File.open(target,'ab') { |f| f.write('user modified bytes') }
          changed=Digest::SHA256.file(target).hexdigest
          protected=DCLibraryConversion.new(source:input,destination:output,update:true)
          protected.start;3.times { protected.tick }
          raise 'Edited target overwritten' unless protected.report['existing']==1 && Digest::SHA256.file(target).hexdigest==changed
          cancelled=DCLibraryConversion.new(source:input,destination:output)
          cancelled.start;cancelled.cancel
          raise 'Cancel continued converting' unless cancelled.report['status']=='cancelled' && cancelled.report['processed']==0
          report['checks'] << 'Modified target is protected and cancel stops before next file'
          raise 'DC source modified' unless Digest::SHA256.file(path).hexdigest==source_sha
        end
        raise 'User model changed' unless ids==model.entities.map(&:persistent_id) && defs==model.definitions.to_a && selection==model.selection.to_a && original_sha==Digest::SHA256.file(source_path).hexdigest
        report['checks'] << 'Original DC, source SKP, model entities, definitions and selection retained'
        report['ok']=true
        puts JSON.generate(report)
      ensure
        File.write(File.join(File.dirname(Panel.instance_method(:show).source_location.first),'outputs/native-066.json'),JSON.pretty_generate(report)) if report
      end
    end
  end
end

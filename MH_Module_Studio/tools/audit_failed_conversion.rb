# encoding: UTF-8
module MH
  module ModuleStudio
    module FailedConversionAudit
      extend self
      def start
        @model=Sketchup.active_model
        base=File.dirname(Panel.instance_method(:show).source_location.first)
        @out=File.join(base,'outputs','conversion-067');FileUtils.mkdir_p(@out)
        report=JSON.parse(File.read('D:/Cong viec/Sketchup/DC/Modul_studio/New folder/.conversion/report.json',encoding:'UTF-8'))
        @source=report['source']
        @files=report['files'].select { |row| row['status']=='failed' && !row['relative'].match?(/cong|uốn/i) && !row['error'].to_s.match?(/dadx/i) }
        @rows=[]
        @timer=UI.start_timer(0.1,true) { tick }
        puts JSON.generate({'audit_count'=>@files.length,'folder'=>@out})
      end

      def tick
        return if @working
        @working=true
        entry=@files[@rows.length]
        unless entry
          UI.stop_timer(@timer);return
        end
        raise 'Model switched' unless Sketchup.active_model.equal?(@model) && !@model.active_path
        roots=@model.entities.to_a;defs=@model.definitions.to_a;selected=@model.selection.to_a
        row={'file'=>entry['relative'],'old_error'=>entry['error']}
        @model.start_operation('MH Audit Conversion',true)
        begin
          definition=@model.definitions.load(File.join(@source,entry['relative']))
          root=@model.entities.add_instance(definition,Geom::Transformation.new)
          converter=DCLibraryConversion.allocate
          converter.instance_variable_set(:@model,@model)
          root=converter.unwrap(root);converter.normalize(root);converter.assign_part_keys(root)
          row['root_attrs']=DCFrames.merge_attributes(Reader.dynamic_attributes(root.definition),Reader.dynamic_attributes(root))
          direct=root.definition.entities.grep(Sketchup::Edge)
          row['root_edges']=direct.length
          row['root_mesh_bounds']=Frames.box(direct.flat_map(&:vertices).uniq.map { |v| v.position.to_a.map { |n| n*25.4 } }) unless direct.empty?
          row['bounds']=[root.definition.bounds.min.to_a,root.definition.bounds.max.to_a].map { |v| v.map { |n| n*25.4 } }
          snapshot,=Reader.live(root,label:entry['relative'],parameter:1)
          file=format('%03d.json',@rows.length)
          File.write(File.join(@out,file),JSON.pretty_generate(snapshot));row['snapshot']=file
        rescue StandardError=>error
          row['read_error']=error.message
        ensure
          @model.abort_operation
        end
        raise 'Audit mutated model' unless roots==@model.entities.to_a && defs==@model.definitions.to_a && selected==@model.selection.to_a
        @rows << row
        File.write(File.join(@out,'audit.json'),JSON.pretty_generate({'total'=>@files.length,'processed'=>@rows.length,'rows'=>@rows}))
      rescue StandardError=>error
        UI.stop_timer(@timer)
        File.write(File.join(@out,'fatal.txt'),error.message)
      ensure
        @working=false
      end
    end
  end
end

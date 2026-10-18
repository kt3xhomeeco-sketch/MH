# encoding: UTF-8
# Developer-only. Load verified staged files, edit private instances, then abort.
module MH
  module ModuleStudio
    module NativeConversionCheck
      extend self

      def start(rounds: %w[retry-final])
        @base=File.expand_path('..',__dir__)
        @model=Sketchup.active_model;Runtime.ensure_top_level(@model)
        @roots=@model.entities.to_a;@definitions=@model.definitions.to_a;@selection=@model.selection.to_a
        @files=rounds.flat_map do |name|
          folder=File.join(@base,'outputs/conversion-067',name)
          JSON.parse(File.read(File.join(folder,'.conversion/report.json'),encoding:'UTF-8'))['files'].filter_map do |row|
            row.merge('path'=>File.join(folder,row['relative'])) if row['status']=='converted'
          end
        end
        @report={'status'=>'running','total'=>@files.length,'files'=>[]}
        write_report
        @timer=UI.start_timer(0.1,true) { tick }
        puts JSON.generate('native_checks'=>@files.length)
      end

      def write_report
        File.write(File.join(@base,'outputs/conversion-067/native-check.json'),JSON.pretty_generate(@report))
      end

      def tick
        return if @working
        @working=true
        row=@files[@report['files'].length]
        unless row
          @report['status']='complete';UI.stop_timer(@timer);write_report;return
        end
        raise 'Model switched during native check' unless Sketchup.active_model.equal?(@model) && !@model.active_path
        result={'relative'=>row['relative'],'kind'=>row['module_kind']}
        operation=false
        begin
          raise 'Staged SKP changed' unless Digest::SHA256.file(row['path']).hexdigest==row['output_sha256']
          @model.start_operation('MH Verify Converted DC',true);operation=true
          definition=@model.definitions.load(row['path'])
          root=@model.entities.add_instance(definition,Geom::Transformation.new)
          raise 'Exported parent must be Component' unless root.is_a?(Sketchup::ComponentInstance)
          data=LibraryCatalog.payload(definition.get_attribute(Reader::DICT,LibraryCatalog::PAYLOAD_KEY))
          rule=data['rule'];values=data['values'];library=Library.new
          current,bindings=library.validate_geometry(root,data)
          raise 'Unexpected child Component' if root.definition.entities.grep(Sketchup::ComponentInstance).any? { |child| !child.is_a?(Sketchup::Group) }
          Runtime.private_tree(root)
          if row['module_kind']=='parametric'
            variable=Parametric.variables(rule).find { |item| %w[T1 T2].include?(item['symbol']) && item['binding'] }
            raise 'No verified thickness variable' unless variable
            original=values.fetch(variable['binding'])
            result['edits']=[]
            [original+0.5,20,original+1,original].uniq.each do |value|
              plan=Core.plan(rule,current,variable['binding']=>value)
              Runtime.apply_plan(bindings,plan);Runtime.stamp(root,rule,bindings,plan['target']);Runtime.verify_result(root,plan)
              values=plan['target'];current,bindings=Reader.live(root,label:data['name'],parameter:Runtime.read_parameter(rule,values))
              raise 'Repeated edit is not stable' unless Core.plan(rule,current,{})['changed_count'].zero?
              result['edits'] << value
            end
          end
          2.times do
            root.transformation=root.transformation*Geom::Transformation.scaling(1.1,1,1.05)
            current,bindings=Reader.live(root,label:data['name'],parameter:Runtime.read_parameter(rule,values))
            plan=ScalePlan.plan(rule,current,values)
            Runtime.apply_plan(bindings,plan);Runtime.stamp(root,rule,bindings,plan['target']);Runtime.verify_result(root,plan)
            values=plan['target']
          end
          result['scale_passes']=2;result['status']='passed'
        rescue StandardError=>error
          result['status']='failed';result['error']="#{error.class}: #{error.message}"
        ensure
          @model.abort_operation if operation
        end
        raise 'User model changed' unless @model.entities.to_a==@roots && @model.definitions.to_a==@definitions && @model.selection.to_a==@selection
        raise 'Staged SKP changed during test' unless Digest::SHA256.file(row['path']).hexdigest==row['output_sha256']
        @report['files'] << result
        write_report
      rescue StandardError=>error
        @report['status']='stopped';@report['error']=error.message;UI.stop_timer(@timer);write_report
      ensure
        @working=false
      end
    end
  end
end

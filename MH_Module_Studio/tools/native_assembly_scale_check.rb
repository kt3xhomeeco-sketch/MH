# encoding: UTF-8
require_relative 'native_drawer_check'

module MH
  module ModuleStudio
    module NativeAssemblyScaleCheck
      extend self

      def copy_attributes(source,target)
        source.attribute_dictionary(Reader::DICT,false).each_pair { |key,value| target.set_attribute(Reader::DICT,key,value) }
      end

      def clone_wrapper(source)
        @model.start_operation('MH QA independent assembly copy',true)
        clone = @model.entities.add_instance(source.definition,source.transformation)
        copy_attributes(source,clone)
        before = AssemblyContainers.members(clone).to_h { |entity| [entity.get_attribute(Reader::DICT,AssemblyContainers::MEMBER),entity.persistent_id.to_s] }
        raise 'Source assembly has no unique member keys' if before.key?(nil) || before.length!=AssemblyContainers.members(clone).length
        clone.make_unique
        after = AssemblyContainers.members(clone).to_h { |entity| [entity.get_attribute(Reader::DICT,AssemblyContainers::MEMBER),entity.persistent_id.to_s] }
        mapping = before.to_h { |key,pid| [pid,after.fetch(key)] }
        records = AssemblyContainers.read(source)
        records.each do |record|
          AssemblyContainers::REFS.each { |key| record[key]['root'] = mapping.fetch(record[key]['root']) if record[key] }
          record['copies']&.map! { |pid| mapping.fetch(pid) }
        end
        clone.set_attribute(Reader::DICT,AssemblyContainers::KEY,JSON.generate(records))
        @model.commit_operation
        reset
        clone
      end

      def reset
        Assembly.watch(@model).reset; ScaleRedraw.watch(@model).reset
      end

      def discard(root)
        @model.start_operation('MH QA remove assembly copy',true)
        root.erase! if root.valid?
        @model.commit_operation
        reset
      end

      def scale(root,factors)
        @model.start_operation('MH QA assembly Scale input',true)
        root.transformation *= Geom::Transformation.scaling(*factors)
        root.definition.invalidate_bounds
        frame = Frames.scale_frame(root.transformation.to_a)
        expected = Frames.box(Frames.corners([root.definition.bounds.min.to_a,root.definition.bounds.max.to_a]).map { |point| Frames.point(frame,point).map { |value| value*25.4 } })
        @model.commit_operation
        reset
        Assembly.transact(@model,Assembly.records(@model))
        reset
        Assembly.records(@model).select { |record| record['scope']==root.persistent_id.to_s }.each { |record| Assembly.verify(@model,record) }
        AssemblyContainers.members(root).each do |member|
          next unless member.get_attribute(Reader::DICT,'trial',false)
          rule,values,current, = NativeDrawerCheck.current(member)
          raise 'Scaled member is not idempotent' unless Core.plan(rule,current,values)['changed_count'].zero?
        end
        root.definition.invalidate_bounds
        actual = [root.definition.bounds.min.to_a,root.definition.bounds.max.to_a].map { |point| point.map { |value| value*25.4 } }
        raise 'Aggregate envelope does not match requested Scale' unless Core.bounds_close?(expected,actual,0.02)
      end

      def common(root,value,envelope_requests: {})
        jobs = AssemblyContainers.members(root).filter_map do |member|
          next unless member.get_attribute(Reader::DICT,'trial',false)
          rule,saved, = NativeDrawerCheck.current(member)
          rows = Parametric.variables(rule)
          rows.each { |row| row['value'] = saved[row['binding']] if row['binding'] && row['formula'].empty? && saved.key?(row['binding']) }
          variable = rows.find { |row| row['symbol']=='T1' }
          next unless variable
          variable['value'] = value
          edited = Parametric.edit_variables(rule,rows)
          [{'root'=>member.persistent_id.to_s,'scope'=>root.persistent_id.to_s},edited,Parametric.targets(edited)]
        end
        raise 'No common thickness jobs' if jobs.length<2
        Assembly.transact(@model,Assembly.records(@model),updates:jobs,envelope_requests:envelope_requests)
        reset
        jobs.each do |anchor,rule,values|
          member = Assembly.root(@model,anchor)
          loaded,saved,current, = NativeDrawerCheck.current(member)
          raise 'Common thickness did not update geometry' unless saved==values && Core.plan(loaded,current,values)['changed_count'].zero?
          raise 'Wrong T1 saved' unless Parametric.variables(rule).any? { |row| row['symbol']=='T1' && row['value']==value }
        end
      end

      def twin(source)
        member = AssemblyContainers.members(source).find { |item| item.name.include?('Tu Bep') }
        raise 'Expected cabinet member' unless member
        @model.start_operation('MH QA twin cabinets',true)
        roots = [0,1].map do |index|
          root = @model.entities.add_instance(member.definition,member.transformation)
          copy_attributes(member,root); Runtime.private_tree(root)
          root.name = "MH QA Twin #{index}"
          root
        end
        @model.commit_operation
        reset
        refs = roots.map do |root|
          _rule,_saved,_snapshot,bindings = NativeDrawerCheck.current(root)
          bindings
        end
        left = refs[0].find { |_key,binding| binding[:entity].name.include?('Phải') }
        right = refs[1].find { |_key,binding| binding[:entity].name.include?('Trái') }
        raise 'Expected side panel names' unless left && right
        record = Assembly.save(@model,{'mode'=>'contact','gap'=>0,'a'=>{'root'=>roots[0].persistent_id.to_s,'part'=>left[0],'axis'=>0,'side'=>1},'b'=>{'root'=>roots[1].persistent_id.to_s,'part'=>right[0],'axis'=>0,'side'=>0}})
        record = Assembly.group(@model,record)
        reset
        AssemblyContainers.wrapper(@model,record['scope'])
      end

      def failed_common_is_atomic(root)
        before = NativeDrawerCheck.fingerprint(root)
        jobs = AssemblyContainers.members(root).map.with_index do |member,index|
          rule,values, = NativeDrawerCheck.current(member)
          row = Parametric.variables(rule).find { |variable| variable['symbol']=='T1' }
          values[row.fetch('binding')] = index.zero? ? 20 : -1
          [{'root'=>member.persistent_id.to_s,'scope'=>root.persistent_id.to_s},rule,values]
        end
        begin
          Assembly.transact(@model,Assembly.records(@model),updates:jobs)
          raise 'Invalid second member was accepted'
        rescue Core::Error
          raise 'Failed second member did not roll back the first member' unless before==NativeDrawerCheck.fingerprint(root)
        ensure
          reset
        end
      end

      def run(expected_pid:,source_pid:,stage:)
        @model = Sketchup.active_model
        raise 'Pinned model 1 only' unless Process.pid==expected_pid && @model.title=='1' && !@model.active_path
        base = File.dirname(Panel.instance_method(:request).source_location.first)
        source = @model.find_entity_by_persistent_id(source_pid)
        raise 'Expected managed source' unless AssemblyContainers.managed?(source)
        originals = @model.entities.to_a; definitions = @model.definitions.to_a; selection = @model.selection.to_a
        fingerprints = originals.select { |root| Assembly.container?(root) }.to_h { |root| [root,NativeDrawerCheck.fingerprint(root)] }
        report = {'stage'=>stage,'results'=>[]}
        begin
          [[1.2,1,1],[1,1.2,1],[1,1,1.2],[0.8,0.8,0.8],[1.2,1.2,1.2]].each do |factors|
            copy = clone_wrapper(source)
            begin
              scale(copy,factors)
              report['results'] << {'case'=>'actual_assembly','factors'=>factors,'ok'=>true}
            rescue StandardError => error
              report['results'] << {'case'=>'actual_assembly','factors'=>factors,'ok'=>false,'error'=>error.message}
            ensure
              discard(copy)
            end
          end
          copy = clone_wrapper(source)
          begin
            [20,18.6,17.6].each { |value| common(copy,value) }
            report['results'] << {'case'=>'actual_common_T1','ok'=>true}
          rescue StandardError => error
            report['results'] << {'case'=>'actual_common_T1','ok'=>false,'error'=>error.message}
          ensure
            discard(copy)
          end
          copy = clone_wrapper(source)
          begin
            failed_common_is_atomic(copy)
            report['results'] << {'case'=>'failed_common_atomic','ok'=>true}
          rescue StandardError => error
            report['results'] << {'case'=>'failed_common_atomic','ok'=>false,'error'=>error.message}
          ensure
            discard(copy)
          end
          copy = clone_wrapper(source)
          begin
            @model.start_operation('MH QA rotated mirrored aggregate',true)
            copy.transformation = Geom::Transformation.rotation(ORIGIN,Z_AXIS,30.degrees)*Geom::Transformation.scaling(-1,1,1)*copy.transformation
            @model.commit_operation; reset
            scale(copy,[0.8,0.9,1.1])
            report['results'] << {'case'=>'rotated_mirrored_scale','ok'=>true}
          rescue StandardError => error
            report['results'] << {'case'=>'rotated_mirrored_scale','ok'=>false,'error'=>error.message}
          ensure
            discard(copy)
          end
          pair = twin(source)
          [[1.2,1.2,1.2],[0.8,0.8,0.8],[1.3,1,1]].each do |factors|
            copy = clone_wrapper(pair)
            begin
              scale(copy,factors)
              report['results'] << {'case'=>'twin_cabinets','factors'=>factors,'ok'=>true}
            rescue StandardError => error
              report['results'] << {'case'=>'twin_cabinets','factors'=>factors,'ok'=>false,'error'=>error.message}
            ensure
              discard(copy)
            end
          end
        rescue StandardError => error
          report['fatal'] = [error.message,*error.backtrace.first(5)]
        ensure
          Assembly.instance_variable_set(:@busy,true)
          @model.start_operation('MH QA assembly scale cleanup',true)
          added = @model.entities.to_a-originals; @model.entities.erase_entities(added) unless added.empty?
          loop do
            unused = (@model.definitions.to_a-definitions).select { |definition| definition.instances.empty? }
            break if unused.empty?
            unused.each { |definition| @model.definitions.remove(definition) }
          end
          @model.selection.clear; @model.selection.add(selection.select(&:valid?))
          @model.commit_operation
          Assembly.instance_variable_set(:@busy,false); reset
          report['originals_retained'] = originals==@model.entities.to_a && definitions==@model.definitions.to_a && selection==@model.selection.to_a && fingerprints.all? { |root,sha| NativeDrawerCheck.fingerprint(root)==sha }
          report['ok'] = !report['fatal'] && report['originals_retained'] && report['results'].all? { |result| result['ok'] }
          File.write(File.join(base,"outputs/assembly-scale-040/#{stage}.json"),JSON.pretty_generate(report))
        end
        report
      end
    end
  end
end

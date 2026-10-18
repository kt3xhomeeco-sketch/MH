# encoding: UTF-8
require_relative 'native_drawer_check'
require_relative 'convert_dc_library'

module MH
  module ModuleStudio
    module NativeCabinetCheck
      extend self

      def check(condition,message)
        raise message unless condition
        @report['checks'] << message
      end

      def run(expected_pid:)
        model = Sketchup.active_model
        raise 'Pinned Untitled only' unless Process.pid==expected_pid && model.title.empty? && !model.active_path
        base = File.dirname(Panel.instance_method(:request).source_location.first)
        @report = {'ok'=>false,'checks'=>[],'files'=>[]}
        roots = model.entities.to_a; definitions = model.definitions.to_a; selected = model.selection.to_a
        camera = model.active_view.camera
        sources = [1266556,1266716].map { |pid| model.find_entity_by_persistent_id(pid) }
        raise 'Expected both source DCs' unless sources.all? { |source| source && !source.get_attribute(Reader::DICT,'trial',false) }
        hashes = sources.to_h { |source| [source.definition.path,Digest::SHA256.file(source.definition.path).hexdigest] }
        fingerprints = roots.select { |root| Assembly.container?(root) }.to_h { |root| [root,NativeDrawerCheck.fingerprint(root)] }
        begin
          sources.each do |source|
            key = source.persistent_id==1266556 ? 'a0van' : 'a1ddtam'
            snapshot, = Reader.live(source,label:File.basename(source.definition.path),parameter:nil)
            rule = StudioCalculation.build_system([snapshot])
            check(rule.dig('formula_engine','rules',key),'Source compiles ATT rules: '+File.basename(source.definition.path))
            Runtime.make_trial(source,rule,{key=>18.6})
            root = model.selection.first
            [17,18.6,20,25,18.6].each do |value|
              Runtime.update_trial(root,rule,{key=>value})
              rule,_values,actual, = NativeDrawerCheck.current(root)
              dims = Core.dimensions(actual['envelope'])
              expected = key=='a1ddtam' ? [400,350,value*2] : [800,450,500]
              check(dims.zip(expected).all? { |a,b| (a-b).abs<0.001 } && Core.plan(rule,actual,{})['changed_count'].zero?,"#{key}=#{value}: actual native geometry matches ATT and stays editable")
            end
            Sketchup.undo
            rule,values,actual, = NativeDrawerCheck.current(root)
            check(values[key]==25 && Core.plan(rule,actual,{})['changed_count'].zero?,'One Undo restores previous thickness and all dependent geometry')
            [[1.2,1.1,1],[0.8,0.9,1]].each_with_index do |factors,index|
              model.start_operation('MH QA cabinet Scale',true)
              root.transformation *= Geom::Transformation.scaling(*factors)
              ScaleRedraw.apply(model,[ScaleRedraw.prepare(root)])
              model.commit_operation
              rule,values,actual, = NativeDrawerCheck.current(root)
              check(Core.plan(rule,actual,{})['changed_count'].zero?,"#{key} repeated Scale #{index+1} reconstructs valid formulas")
            end
            original = NativeDrawerCheck.fingerprint(root)
            model.start_operation('MH QA cabinet copy',true)
            clone = model.entities.add_instance(root.definition,root.transformation)
            root.attribute_dictionary(Reader::DICT,false).each_pair { |name,value| clone.set_attribute(Reader::DICT,name,value) }
            model.commit_operation
            Runtime.update_trial(clone,rule,{key=>17})
            check(original==NativeDrawerCheck.fingerprint(root),'Thickness edit leaves a shared original instance unchanged')
            # Library defaults use canonical source values, rather than QA Scale.
            model.start_operation('MH QA canonical cabinet',true)
            copy = model.entities.add_instance(source.definition,Geom::Transformation.new)
            copy.name = File.basename(source.definition.path,'.skp')
            Reader.dynamic_attributes(source).each { |name,value| copy.set_attribute('dynamic_attributes',name,value) }
            LibraryConversion.allocate.normalize(copy)
            data,bindings = Reader.live(copy,label:copy.name,parameter:nil)
            own = StudioCalculation.build_system([data])
            values = own['parameters'].select { |p| p['editable'] }.to_h { |p| [p['key'],p['value']] }
            Runtime.private_tree(copy); Runtime.stamp(copy,own,bindings,values)
            model.commit_operation
            folder = File.join(base,'outputs/cabinet-039/library'); FileUtils.mkdir_p(folder)
            path = File.join(folder,copy.name+'.skp')
            library = Library.new; library.export(copy,path)
            library.instance_variable_get(:@config)['root'] = folder; library.refresh
            prepared = library.prepare(File.basename(path))
            model.start_operation('MH QA cabinet reimport',true)
            imported = library.build_instance(prepared,Geom::Transformation.new)
            Runtime.apply_trial_update(imported,own,{key=>18.6})
            loaded,_saved,geometry, = NativeDrawerCheck.current(imported)
            check(Core.plan(loaded,geometry,{})['changed_count'].zero?,'Saved own-rule SKP reimports and edits actual native geometry')
            check(imported.is_a?(Sketchup::ComponentInstance) && imported.definition.entities.select { |e| Assembly.container?(e) }.all? { |e| e.is_a?(Sketchup::Group) },'Library parent is Component and children are Groups')
            model.abort_operation
            @report['files'] << {'path'=>path,'source'=>source.definition.path,'source_sha256'=>hashes[source.definition.path],'output_sha256'=>Digest::SHA256.file(path).hexdigest,'native_verified'=>true}
          end
          @report['ok'] = true
        rescue StandardError => error
          @report['error'] = [error.message,*error.backtrace.first(9)]
        ensure
          Assembly.instance_variable_set(:@busy,true)
          model.start_operation('MH QA cabinet cleanup',true)
          added = model.entities.to_a-roots; model.entities.erase_entities(added) unless added.empty?
          loop do
            unused = (model.definitions.to_a-definitions).select { |definition| definition.instances.empty? }
            break if unused.empty?
            unused.each { |definition| model.definitions.remove(definition) }
          end
          model.selection.clear; model.selection.add(selected.select(&:valid?)); model.active_view.camera = camera
          model.commit_operation
          Assembly.instance_variable_set(:@busy,false)
          Assembly.watch(model).reset; ScaleRedraw.watch(model).reset
          @report['source_retained'] = hashes.all? { |path,sha| Digest::SHA256.file(path).hexdigest==sha } && fingerprints.all? { |root,sha| NativeDrawerCheck.fingerprint(root)==sha }
          @report['model_retained'] = model.entities.to_a==roots && model.definitions.to_a==definitions && model.selection.to_a==selected
          @report['ok'] &&= @report['source_retained'] && @report['model_retained']
          File.write(File.join(base,'outputs/cabinet-039/native.json'),JSON.pretty_generate(@report))
        end
        @report
      end
    end
  end
end

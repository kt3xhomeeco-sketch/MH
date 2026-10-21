# encoding: UTF-8
require_relative 'native_drawer_check'
require_relative '../test/formula_fixtures'

module MH
  module ModuleStudio
    module NativeConditionalCheck
      extend self

      def check(condition,message)
        raise message unless condition
        @report['checks'] << message
      end

      def fixture(model,tag: nil)
        data = FormulaFixtures.snapshot
        definition = model.definitions.add('MH QA Conditional source')
        root = model.entities.add_instance(definition,Geom::Transformation.new)
        data['dc_inputs'].merge!('_name'=>'cabinet','show'=>0,'_show_access'=>'TEXTBOX','_show_units'=>'FLOAT',
                                  'offset'=>0,'_offset_access'=>'TEXTBOX','_offset_units'=>'MILLIMETERS')
        data['dc_inputs'].each { |key,value| root.set_attribute('dynamic_attributes',key,value) }
        nodes = data['dc_graph']['nodes']; groups = {}; build = nil
        build = lambda do |node|
          next groups[node['id']] if groups[node['id']]
          parent_node = nodes.find { |entry| entry['path']==node['path'][0...-1] }
          entities = parent_node ? build.call(parent_node).entities : definition.entities
          group = entities.add_group; groups[node['id']] = group
          group.name = node['name']; group.transformation = Geom::Transformation.new(node['transform'])
          attrs = node['attributes'].dup
          if node['id']=='carrier'
            attrs.merge!('_hidden_formula'=>'or(parent!show,parent!lenx>65)','_hidden_formulaunits'=>'FLOAT')
          elsif node['part_key']=='back'
            attrs.merge!('_hidden_formula'=>'cabinet!t<2','_hidden_formulaunits'=>'FLOAT')
            group.hidden = true; group.layer = tag if tag
          elsif node['part_key']=='top'
            attrs['_leny_formula'] = 'parent!leny-parent!cut-if(parent!offset>2,0.5,0)'
          end
          attrs.each { |key,value| group.set_attribute('dynamic_attributes',key,value) }
          if node['part_key']
            group.set_attribute(Reader::DICT,'part_key',node['part_key'])
            low,high = node['local_bounds']; x,y,z = low; a,b,c = high
            points = [[x,y,z],[a,y,z],[a,b,z],[x,b,z],[x,y,c],[a,y,c],[a,b,c],[x,b,c]]
            [[3,2,1,0],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]].each do |indices|
              group.entities.add_face(indices.map { |i| points[i] })
            end
          end
          group
        end
        nodes.each { |node| build.call(node) }
        root
      end

      def state(root)
        NativeDrawerCheck.current(root)
      end

      def run(expected_pid:)
        model = Sketchup.active_model
        raise 'Pinned Untitled session only' unless Process.pid==expected_pid && model.title.empty? && !model.active_path
        @base = File.dirname(Panel.instance_method(:request).source_location.first)
        @report = {'pid'=>Process.pid,'ok'=>false,'checks'=>[]}
        roots = model.entities.to_a; definitions = model.definitions.to_a; selected = model.selection.to_a
        camera = model.active_view.camera
        tags = []
        fingerprints = roots.select { |root| Assembly.container?(root) }.to_h { |root| [root,NativeDrawerCheck.fingerprint(root)] }
        begin
          model.start_operation('MH QA Conditional fixture',true)
          source = fixture(model)
          model.commit_operation
          original = NativeDrawerCheck.fingerprint(source)
          snapshot, = Reader.live(source,label:'Conditional native',parameter:nil)
          rule = RuleSystem.build(snapshot,Core.learn_module([snapshot]))
          check(rule['parameters'].any? { |p| p['key']=='offset' && p['editable'] },'Dormant IF input is recognized from ATT dependencies')
          check(rule['parameters'].any? { |p| p['key']=='show' && p['editable'] && p['unit']=='' },'Scalar visibility input stays scalar and editable')
          Runtime.make_trial(source,rule,{'t'=>19})
          root = model.selection.first
          rule,values,actual, = state(root)
          envelope = actual['envelope']
          check(actual['parts'].find { |p| p['key']=='back' }['visible']==false,'Inactive panel remains hidden while thickness changes')
          {'t'=>22,'show'=>1}.each { |key,value| Runtime.update_trial(root,rule,{key=>value}) }
          rule,values,actual, = state(root)
          check(actual['parts'].find { |p| p['key']=='back' }['visible']==false && values['show']==1,'Ancestor visibility applies and saved scalar value remains 1')
          Runtime.update_trial(root,rule,{'t'=>23})
          Runtime.update_trial(root,rule,{'show'=>0,'offset'=>21})
          rule,values,actual, = state(root)
          back = actual['parts'].find { |p| p['key']=='back' }
          check(back['visible'] && (back['bounds'][0][0]-23).abs<0.001,'Showing an ancestor reconstructs the panel with current thickness')
          check((Core.dimensions(actual['parts'].find { |p| p['key']=='top' }['bounds'])[1]-169).abs<0.001,'Crossing dormant IF threshold changes actual native geometry')
          check(Core.bounds_close?(actual['envelope'],envelope,0.001) && Core.plan(rule,actual,values)['changed_count'].zero?,'Combined conditional/visibility edits retain envelope and are idempotent')
          Sketchup.undo
          rule,values,actual, = state(root)
          check(values['show']==1 && actual['parts'].find { |p| p['key']=='back' }['visible']==false,'One Undo restores scalar value, ancestor visibility and geometry together')
          Runtime.update_trial(root,rule,{'show'=>0,'offset'=>21})
          rule,values,actual, = state(root)
          bad_before = NativeDrawerCheck.fingerprint(root)
          begin
            Runtime.update_trial(root,rule,{'t'=>-1})
            raise 'Invalid thickness accepted'
          rescue Core::Error
            check(bad_before==NativeDrawerCheck.fingerprint(root),'Invalid value rolls back geometry and visibility')
          end
          [[1.2,1,1],[0.8,1,1]].each_with_index do |factors,index|
            model.start_operation('MH QA Conditional Scale',true)
            root.transformation *= Geom::Transformation.scaling(*factors)
            ScaleRedraw.apply(model,[ScaleRedraw.prepare(root)])
            model.commit_operation
            rule,values,actual, = state(root)
            back = actual['parts'].find { |p| p['key']=='back' }
            check(back['visible']==(index==1) && Core.plan(rule,actual,values)['changed_count'].zero?,"Scale #{index+1} crosses visibility threshold and retains valid formulas")
          end
          original_instance = NativeDrawerCheck.fingerprint(root)
          model.start_operation('MH QA Conditional clone',true)
          clone = model.entities.add_instance(root.definition,root.transformation)
          root.attribute_dictionary(Reader::DICT,false).each_pair { |key,value| clone.set_attribute(Reader::DICT,key,value) }
          model.commit_operation
          Runtime.update_trial(clone,rule,{'show'=>1})
          _clone_rule,_clone_values,clone_snapshot, = state(clone)
          check(clone_snapshot['parts'].find { |p| p['key']=='back' }['visible']==false && original_instance==NativeDrawerCheck.fingerprint(root),'Visibility edit on a shared copied component leaves original geometry and flags unchanged')
          directory = File.join(@base,'outputs/conditional-038/library')
          FileUtils.mkdir_p(directory)
          path = File.join(directory,'Conditional.skp')
          library = Library.new
          library.export(root,path)
          library.instance_variable_get(:@config)['root'] = directory; library.refresh
          data = library.prepare('Conditional.skp')
          model.start_operation('MH QA Conditional reimport',true)
          imported = library.build_instance(data,Geom::Transformation.new)
          saved_rule,saved_values,imported_snapshot, = state(imported)
          check(Core.plan(saved_rule,imported_snapshot,saved_values)['changed_count'].zero?,'Own-rule SKP export and reimport preserve conditional visibility')
          model.abort_operation
          Runtime.create_model(snapshot,rule,{'t'=>22})
          generated = model.selection.first
          Runtime.update_trial(generated,rule,{'show'=>1})
          _rule,_values,generated_snapshot, = state(generated)
          check(generated_snapshot['parts'].find { |p| p['key']=='back' }['visible']==false,'Generated flat-group model supports ancestor visibility rules')
          Runtime.update_trial(generated,rule,{'show'=>0})
          _rule,_values,generated_snapshot, = state(generated)
          check(generated_snapshot['parts'].find { |p| p['key']=='back' }['visible'],'Generated model can show the existing part again')
          model.start_operation('MH QA Conditional tag fixture',true)
          tag = model.layers.add('MH QA Conditional '+Core::Ids.hex(4)); tags << tag
          tag.visible = false
          tagged_source = fixture(model,tag:tag)
          model.commit_operation
          tagged_snapshot, = Reader.live(tagged_source,label:'Tagged conditional fixture',parameter:nil)
          tagged_rule = RuleSystem.build(tagged_snapshot,Core.learn_module([tagged_snapshot]))
          Runtime.make_trial(tagged_source,tagged_rule,{'t'=>22})
          tagged_root = model.selection.first
          _tagged_rule,_tagged_values,tagged_actual, = state(tagged_root)
          check(!tag.visible? && tagged_actual['parts'].find { |p| p['key']=='back' }['visible']==false,'Changing hidden formula never turns on a disabled native tag')
          check(original==NativeDrawerCheck.fingerprint(source),'Source DC remains unchanged throughout trial edits, Scale and export')
          @report['ok'] = true
        rescue StandardError => error
          @report['error'] = [error.message,*error.backtrace.first(8)]
        ensure
          Assembly.instance_variable_set(:@busy,true)
          model.abort_operation if model.respond_to?(:active_operation_name) && !model.active_operation_name.to_s.empty?
          model.start_operation('MH QA Conditional cleanup',true)
          added = model.entities.to_a-roots
          model.entities.erase_entities(added) unless added.empty?
          loop do
            unused = (model.definitions.to_a-definitions).select { |definition| definition.instances.empty? }
            break if unused.empty?
            unused.each { |definition| model.definitions.remove(definition) }
          end
          tags.each { |tag| model.layers.remove(tag,false) }
          model.selection.clear; model.selection.add(selected.select(&:valid?))
          model.active_view.camera = camera
          model.commit_operation
          Assembly.instance_variable_set(:@busy,false)
          Assembly.watch(model).reset; ScaleRedraw.watch(model).reset
          @report['originals_retained'] = roots==model.entities.to_a && definitions==model.definitions.to_a && selected==model.selection.to_a && fingerprints.all? { |item,sha| NativeDrawerCheck.fingerprint(item)==sha }
          @report['ok'] &&= @report['originals_retained']
          File.write(File.join(@base,'outputs/conditional-038/native.json'),JSON.pretty_generate(@report))
        end
        puts JSON.generate(@report)
      end
    end
  end
end

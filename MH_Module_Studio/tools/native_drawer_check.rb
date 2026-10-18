# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeDrawerCheck
      extend self

      def check(condition, label)
        raise label unless condition
        @report['checks'] << label
      end

      def fingerprint(root)
        digest = []
        walk = lambda do |item|
          digest << [item.persistent_id,item.transformation.to_a,item.attribute_dictionaries&.map { |d| [d.name,d.to_a] }]
          item.definition.entities.each do |child|
            if Assembly.container?(child)
              walk.call(child)
            elsif child.is_a?(Sketchup::Edge)
              digest << [child.persistent_id,child.start.position.to_a,child.end.position.to_a]
            end
          end
        end
        walk.call(root)
        Digest::SHA256.hexdigest(JSON.generate(digest))
      end

      def current(root)
        rule = Core.rule!(JSON.parse(root.get_attribute(Reader::DICT,'rule_json')))
        values = JSON.parse(root.get_attribute(Reader::DICT,'parameter_values_json'))
        snapshot,bindings = Reader.live(root,label:'Native drawer check',parameter:Runtime.read_parameter(rule,values))
        [rule,values,snapshot,bindings]
      end

      def wire_shape(root)
        _rule,_values,_snapshot,bindings = current(root)
        binding = bindings.values.find { |b| b[:entity].name=='ABF_minifixPlasticBase55' }
        frame = Geom::Transformation.new(binding[:frame])
        points = binding[:entity].definition.entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq.map { |v| v.position.transform(frame) }
        origin = points.first
        points.map { |p| (p-origin).to_a.map { |v| (v*25.4).round(6) } }.sort
      end

      def run(expected_pid:, source_pid:)
        model = Sketchup.active_model
        raise 'Wrong session or edit context' unless Process.pid==expected_pid && model.active_path.nil?
        source = model.find_entity_by_persistent_id(source_pid)
        raise 'Expected selected source drawer' unless source && source==model.selection.first && File.basename(source.definition.path)=='1.QQ Ngan keo 1 tang 550.skp'
        base = File.dirname(Panel.instance_method(:request).source_location.first)
        originals = model.entities.to_a; definitions = model.definitions.to_a; selected = model.selection.to_a
        before = fingerprint(source); hash = Digest::SHA256.file(source.definition.path).hexdigest
        @report = {'pid'=>Process.pid,'checks'=>[],'ok'=>false}
        begin
          library = Library.new
          library.instance_variable_get(:@config)['root'] = 'D:/Cong viec/Sketchup/DC/Modul_studio'
          library.refresh
          item = library.catalog['entries'].find { |entry| entry['id']=='1.QQ Ngan keo 1 tang 550.skp' }
          data = library.prepare(item['id'])
          values = Parametric.targets(data['rule'])
          check((values['hfwgp2tb7u']-13.5).abs<0.000001,'Rail clearance remains 13.5 mm and is not merged into T2 board thickness')
          root = library.place(data,Geom::Point3d.new(1000.0/25.4,0,0))
          rule,saved,snapshot, = current(root)
          defaults = saved.dup
          envelope = snapshot['envelope']
          shape = wire_shape(root)
          check(root.is_a?(Sketchup::ComponentInstance) && root.definition.entities.select { |e| Assembly.container?(e) }.all? { |e| e.is_a?(Sketchup::Group) },'Converted drawer imports with a component parent and group children')
          check(Core.plan(rule,snapshot,{})['changed_count'].zero?,'Reimported drawer formulas agree with actual geometry')
          path = item['path']
          FileUtils.cp(path,File.join(base,'outputs/drawer-036/pilot-before-canonical.skp'))
          library.export(root,path)
          @report['canonical_export'] = {'path'=>path,'sha256'=>Digest::SHA256.file(path).hexdigest}
          {'eqgyit1tf1'=>17.6,'erhqw_82nd'=>9,'hfwgp2tb7u'=>14,'htq36k7xp9'=>22,
            'mck7tq7ua1'=>23,'n46i8yerg0'=>18,'nqqa6h35ja'=>1,'uez6mvfjr1'=>13,'w5cbyli7el'=>9}.each do |key,value|
            Runtime.update_trial(root,rule,{key=>value})
            rule,saved,actual, = current(root)
            check(Core.bounds_close?(actual['envelope'],envelope,0.001) && Core.plan(rule,actual,saved)['changed_count'].zero?,"Native parameter edit #{key}=#{value} preserves envelope and remains editable")
            check(wire_shape(root)==shape,'Rail symbol vertices preserve their relative shape after '+key)
          end
          Sketchup.undo
          rule,saved,actual, = current(root)
          check((saved['w5cbyli7el']-defaults['w5cbyli7el']).abs<0.000001,'One Undo restores the previous drawer parameter and wire geometry')
          before_bad = fingerprint(root)
          begin
            Runtime.update_trial(root,rule,{'eqgyit1tf1'=>-1})
            raise 'Invalid negative thickness accepted'
          rescue Core::Error
            check(before_bad==fingerprint(root),'Invalid thickness aborts without changing the imported drawer')
          end
          [[1.2,1,1.1],[0.9,1,1.05]].each do |factors|
            model.start_operation('MH QA drawer Scale',true)
            root.transformation *= Geom::Transformation.scaling(*factors)
            ScaleRedraw.apply(model,[ScaleRedraw.prepare(root)])
            model.commit_operation
            rule,saved,actual, = current(root)
            plan = Core.plan(rule,actual,saved)
            check(plan['changed_count'].zero? && (saved['eqgyit1tf1']-17.6).abs<0.000001,'Repeated Scale redraw keeps saved thickness and valid drawer formulas')
          end
          check(before==fingerprint(source) && hash==Digest::SHA256.file(source.definition.path).hexdigest,'Original selected DC and original SKP file remain unchanged')
          @report['ok'] = true
        rescue StandardError => error
          @report['error'] = [error.message,*error.backtrace.first(7)]
        ensure
          Assembly.instance_variable_set(:@busy,true)
          model.start_operation('MH QA drawer cleanup',true)
          added = model.entities.to_a-originals
          model.active_entities.erase_entities(added) unless added.empty?
          loop do
            unused = (model.definitions.to_a-definitions).select { |d| d.instances.empty? }
            break if unused.empty?
            unused.each { |d| model.definitions.remove(d) }
          end
          model.selection.clear; model.selection.add(selected.select(&:valid?))
          model.commit_operation
          Assembly.instance_variable_set(:@busy,false)
          Assembly.watch(model).reset; ScaleRedraw.watch(model).reset
          @report['source_retained'] = before==fingerprint(source) && hash==Digest::SHA256.file(source.definition.path).hexdigest
          @report['model_retained'] = model.entities.to_a==originals && model.definitions.to_a==definitions && model.selection.to_a==selected
          @report['ok'] &&= @report['source_retained'] && @report['model_retained']
          File.write(File.join(base,'outputs/drawer-036/native.json'),JSON.pretty_generate(@report))
        end
        puts JSON.generate(@report)
      end
    end
  end
end

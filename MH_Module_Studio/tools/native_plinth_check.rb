# encoding: UTF-8
require_relative 'native_drawer_check'

module MH
  module ModuleStudio
    module NativePlinthCheck
      extend self

      def check(condition,message)
        raise message unless condition
        @report['checks'] << message
      end

      def run(expected_pid:,source_pid:)
        model = Sketchup.active_model
        raise 'Pinned Untitled session only' unless Process.pid==expected_pid && model.title.empty? && !model.active_path
        source = model.find_entity_by_persistent_id(source_pid)
        raise 'Expected original plinth' unless source && File.basename(source.definition.path)=='3.CC Chân bệ.skp'
        base = File.dirname(Panel.instance_method(:request).source_location.first)
        originals = model.entities.to_a; definitions = model.definitions.to_a; selected = model.selection.to_a
        source_before = NativeDrawerCheck.fingerprint(source)
        source_sha = Digest::SHA256.file(source.definition.path).hexdigest
        @report = {'pid'=>Process.pid,'ok'=>false,'checks'=>[]}
        begin
          library = Library.new
          library.instance_variable_get(:@config)['root'] = 'D:/Cong viec/Sketchup/DC/Modul_studio'
          library.refresh
          data = library.prepare('3.CC Chân bệ.skp')
          root = library.place(data,Geom::Point3d.new(1000.0/25.4,0,0))
          rule,saved,snapshot, = NativeDrawerCheck.current(root)
          defaults = saved.dup; envelope = snapshot['envelope']
          check(root.is_a?(Sketchup::ComponentInstance) && root.definition.entities.select { |e| Assembly.container?(e) }.all? { |e| e.is_a?(Sketchup::Group) },'Reimported plinth has Component parent and Group children')
          check(Parametric.variables(rule).any? { |row| row['symbol']=='T1' && row['binding']=='a5dodayvan' },'Board thickness uses the common T1 symbol')
          check(Core.plan(rule,snapshot,{})['changed_count'].zero?,'Reimported file agrees with its own formulas')
          {'a5dodayvan'=>17.6,'a6_chieucaonumnhua'=>1,'c1_hut_trai'=>1,'c2_hut_phai'=>1,'c3_hut_sau'=>12,'c4_hut_truoc'=>25}.each do |key,value|
            Runtime.update_trial(root,rule,{key=>value})
            rule,saved,actual, = NativeDrawerCheck.current(root)
            check(Core.bounds_close?(actual['envelope'],envelope,0.001) && Core.plan(rule,actual,saved)['changed_count'].zero?,"Native edit #{key}=#{value} preserves envelope and remains editable")
          end
          Sketchup.undo
          rule,saved,actual, = NativeDrawerCheck.current(root)
          check((saved['c4_hut_truoc']-defaults['c4_hut_truoc']).abs<0.000001,'One Undo restores the previous parameter')
          bad_before = NativeDrawerCheck.fingerprint(root)
          begin
            Runtime.update_trial(root,rule,{'a5dodayvan'=>-1})
            raise 'Negative thickness accepted'
          rescue Core::Error
            check(bad_before==NativeDrawerCheck.fingerprint(root),'Invalid thickness leaves geometry and saved parameters unchanged')
          end
          [[1.2,1,1],[0.9,1,1]].each do |factors|
            model.start_operation('MH QA plinth Scale',true)
            root.transformation *= Geom::Transformation.scaling(*factors)
            ScaleRedraw.apply(model,[ScaleRedraw.prepare(root)])
            model.commit_operation
            rule,saved,actual, = NativeDrawerCheck.current(root)
            check(Core.plan(rule,actual,saved)['changed_count'].zero? && (saved['a5dodayvan']-17.6).abs<0.000001,'Repeated Scale reconstructs leg spacing and retains thickness')
          end
          @report['ok'] = true
        rescue StandardError => error
          @report['error'] = [error.message,*error.backtrace.first(6)]
        ensure
          Assembly.instance_variable_set(:@busy,true)
          model.start_operation('MH QA plinth cleanup',true)
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
          @report['source_retained'] = source_before==NativeDrawerCheck.fingerprint(source) && source_sha==Digest::SHA256.file(source.definition.path).hexdigest
          @report['model_retained'] = originals==model.entities.to_a && definitions==model.definitions.to_a && selected==model.selection.to_a
          @report['ok'] &&= @report['source_retained'] && @report['model_retained']
          File.write(File.join(base,'outputs/plinth-037/native.json'),JSON.pretty_generate(@report))
        end
        puts JSON.generate(@report)
      end
    end
  end
end

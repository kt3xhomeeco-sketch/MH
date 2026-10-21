# encoding: UTF-8
require_relative 'native_conditional_check'

module MH
  module ModuleStudio
    module NativeConditionalAsyncCheck
      extend self

      def check(condition,message)
        raise message unless condition
        @report['checks'] << message
      end

      def later(&block)
        UI.start_timer(0.3,false) do
          begin
            raise 'Native model changed during QA' unless Sketchup.active_model.equal?(@model) && !@model.active_path
            block.call
          rescue StandardError => error
            @report['error'] = [error.message,*error.backtrace.first(6)]
            finish
          end
        end
      end

      def start(expected_pid:)
        raise 'Pinned Untitled only' unless Process.pid==expected_pid && Sketchup.active_model.title.empty?
        @model = Sketchup.active_model
        @finished = false
        @base = File.dirname(Panel.instance_method(:request).source_location.first)
        @roots = @model.entities.to_a; @defs = @model.definitions.to_a; @selected = @model.selection.to_a
        @fingerprints = @roots.select { |root| Assembly.container?(root) }.to_h { |root| [root,NativeDrawerCheck.fingerprint(root)] }
        @report = {'status'=>'running','ok'=>false,'checks'=>[]}
        @model.start_operation('MH QA Conditional async fixture',true)
        source = NativeConditionalCheck.fixture(@model)
        @model.commit_operation
        snapshot, = Reader.live(source,label:'Async fixture',parameter:nil)
        @rule = RuleSystem.build(snapshot,Core.learn_module([snapshot]))
        Runtime.make_trial(source,@rule,{'t'=>22})
        @root = @model.selection.first
        Runtime.update_trial(@root,@rule,{'show'=>1})
        Sketchup.undo
        _rule,values,snapshot, = NativeDrawerCheck.current(@root)
        check(values['show']==0 && snapshot['parts'].find { |p| p['key']=='back' }['visible'],'Undo restores visible state and scalar value')
        Sketchup.send_action('editRedo:')
        later { after_redo }
      rescue StandardError => error
        @report['error'] = [error.message,*error.backtrace.first(6)]
        finish
      end

      def after_redo
        _rule,values,snapshot, = NativeDrawerCheck.current(@root)
        check(values['show']==1 && snapshot['parts'].find { |p| p['key']=='back' }['visible']==false,'Native queued Redo restores hidden ancestor and scalar value')
        Runtime.update_trial(@root,@rule,{'show'=>0})
        scale(1.2) { after_scale_up }
      end

      def scale(factor,&block)
        @model.start_operation('MH QA Native Scale transaction',true)
        @root.transformation *= Geom::Transformation.scaling(factor,1,1)
        @model.commit_operation
        later(&block)
      end

      def valid(expected_width,visible)
        rule,values,snapshot, = NativeDrawerCheck.current(@root)
        back = snapshot['parts'].find { |p| p['key']=='back' }
        (Core.dimensions(snapshot['envelope'])[0]-expected_width).abs<0.001 && back['visible']==visible &&
          (values['t']-22).abs<0.001 && Core.plan(rule,snapshot,values)['changed_count'].zero? && ScaleRedraw.watch(@model).last_error.nil?
      end

      def after_scale_up
        check(valid(720,false),'Actual transaction observer repairs Scale and hides the ancestor at the threshold')
        scale(0.8) { after_scale_down }
      end

      def after_scale_down
        check(valid(576,true),'Second actual Scale observer restores visible panel with preserved thickness')
        Sketchup.undo
        later do
          check(valid(720,false),'Single Undo restores Scale, geometry and visibility together')
          Sketchup.send_action('editRedo:')
          later do
            check(valid(576,true),'Redo of repaired Scale remains idempotent without another repair')
            @report['ok'] = true
            finish
          end
        end
      end

      def finish
        return if @finished
        @finished = true
        Assembly.instance_variable_set(:@busy,true)
        @model.start_operation('MH QA Conditional async cleanup',true)
        added = @model.entities.to_a-@roots
        @model.entities.erase_entities(added) unless added.empty?
        loop do
          unused = (@model.definitions.to_a-@defs).select { |definition| definition.instances.empty? }
          break if unused.empty?
          unused.each { |definition| @model.definitions.remove(definition) }
        end
        @model.selection.clear; @model.selection.add(@selected.select(&:valid?))
        @model.commit_operation
        Assembly.instance_variable_set(:@busy,false)
        Assembly.watch(@model).reset; ScaleRedraw.watch(@model).reset
        @report['originals_retained'] = @roots==@model.entities.to_a && @defs==@model.definitions.to_a && @selected==@model.selection.to_a && @fingerprints.all? { |root,sha| NativeDrawerCheck.fingerprint(root)==sha }
        @report['ok'] &&= @report['originals_retained']
        @report['status'] = 'complete'
        File.write(File.join(@base,'outputs/conditional-038/async-native.json'),JSON.pretty_generate(@report))
      end
    end
  end
end

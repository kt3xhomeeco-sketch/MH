# encoding: UTF-8
require_relative 'native_face_picker_check'

module MH
  module ModuleStudio
    module NativeFacePickerAsyncCheck
      extend self

      def later(&block)
        UI.start_timer(0.4,false) do
          begin
            raise 'Model switched during QA' unless Sketchup.active_model.equal?(@model)
            block.call
          rescue StandardError => error
            finish(error)
          end
        end
      end

      def check(condition,message)
        raise message unless condition
        @report['checks'] << message
      end

      def valid(width)
        return false unless (Core.dimensions(AssemblyEnvelope.bounds(@copy))[0]-width).abs<0.02
        Assembly.records(@model).each { |record| Assembly.verify(@model,record) }
        true
      end

      def start(expected_pid:)
        @model = Sketchup.active_model
        raise 'Pinned model 1 only' unless Process.pid==expected_pid && @model.title=='1' && !@model.active_path
        @base = File.dirname(Panel.instance_method(:request).source_location.first)
        @roots = @model.entities.to_a; @defs = @model.definitions.to_a; @selected = @model.selection.to_a
        @global = @model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        @fingerprints = @roots.select { |root| Assembly.container?(root) }.to_h { |root| [root,NativeDrawerCheck.fingerprint(root)] }
        @report = {'status'=>'running','ok'=>false,'checks'=>[]}; @finished = false
        @helper = NativeFacePickerCheck; @helper.instance_variable_set(:@model,@model)
        wrapper, = @helper.build
        @clone = NativeAssemblyScaleCheck; @clone.instance_variable_set(:@model,@model)
        @copy = @clone.clone_wrapper(wrapper)
        @owned_roots = [wrapper,@copy]
        @left = Assembly.save(@model,{'mode'=>'contact','gap'=>-10,'a'=>@helper.anchor(wrapper,0,0,'assembly'),'b'=>@helper.anchor(@copy,0,0,'assembly')})
        @right = Assembly.save(@model,{'mode'=>'contact','gap'=>-10,'a'=>@helper.anchor(wrapper,0,1,'assembly'),'b'=>@helper.anchor(@copy,0,1,'assembly')})
        write
        later do
          check(valid(1180),'Actual observers retain the whole-assembly fit and internal links')
          Sketchup.undo
          later do
            check(valid(1200) && Assembly.records(@model).none? { |row| row['id']==@right['id'] },'One Undo restores geometry and removes only the second external link')
            Sketchup.send_action('editRedo:')
            later do
              check(valid(1180) && Assembly.records(@model).any? { |row| row['id']==@right['id'] },'Queued Redo restores the external link and exact assembly fit')
              independent_copy(wrapper)
            end
          end
        end
      rescue StandardError => error
        finish(error)
      end

      def independent_copy(wrapper)
        other = @clone.clone_wrapper(@copy)
        @owned_roots << other
        Assembly.save(@model,{'mode'=>'contact','gap'=>-25,'a'=>@helper.anchor(wrapper,0,0,'assembly'),'b'=>@helper.anchor(other,0,0,'assembly')})
        Assembly.save(@model,{'mode'=>'contact','gap'=>-30,'a'=>@helper.anchor(wrapper,0,1,'assembly'),'b'=>@helper.anchor(other,0,1,'assembly')})
        later do
          check(valid(1180) && (Core.dimensions(AssemblyEnvelope.bounds(other))[0]-1145).abs<0.02,
            'Linking a copied assembly fits that copy independently and preserves the first assembly')
          check(other.definition!=@copy.definition,'Linked copied assemblies retain independent parent definitions')
          finish
        end
      end

      def finish(error = nil)
        return if @finished
        @finished = true
        @report['error'] = [error.message,*error.backtrace.first(6)] if error
        Assembly.instance_variable_set(:@busy,true)
        @model.start_operation('MH QA async picker cleanup',true)
        @global ? @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,@global) : @model.delete_attribute(Reader::DICT,AssemblyContainers::KEY)
        added = @owned_roots.to_a.select(&:valid?); @model.entities.erase_entities(added) unless added.empty?
        loop do
          unused = (@model.definitions.to_a-@defs).select { |definition| definition.instances.empty? }
          break if unused.empty?
          unused.each { |definition| @model.definitions.remove(definition) }
        end
        @model.selection.clear; @model.selection.add(@selected.select(&:valid?)); @model.commit_operation
        Assembly.instance_variable_set(:@busy,false); @helper.reset
        @report['originals_retained'] = @roots==@model.entities.to_a && @defs==@model.definitions.to_a && @selected==@model.selection.to_a && @global==@model.get_attribute(Reader::DICT,AssemblyContainers::KEY) && @fingerprints.all? { |root,sha| NativeDrawerCheck.fingerprint(root)==sha }
        @report['ok'] = !error && @report['originals_retained']; @report['status'] = 'complete'; write
      end

      def write
        File.write(File.join(@base,'outputs/face-picking-042/async.json'),JSON.pretty_generate(@report))
      end
    end
  end
end

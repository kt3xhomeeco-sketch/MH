# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeHUDDigitsCheck
      extend self
      class Recorder
        attr_reader :keys
        def initialize;@keys=[];end
        def active;true;end
        def onKeyDown(key,*_args);@keys << key;end
        def onKeyUp(*_args);end
        def drag_active?;false;end
        def fail_session(error);raise error;end
      end
      def start(hwnd:)
        model=Sketchup.active_model;before=model.entities.map(&:persistent_id);selection=model.selection.to_a
        native=Fiddle.dlopen('user32.dll');int=Fiddle::TYPE_INT;pointer=Fiddle::TYPE_VOIDP
        pid=Fiddle::Pointer.malloc(4,Fiddle::RUBY_FREE)
        get_pid=Fiddle::Function.new(native['GetWindowThreadProcessId'],[pointer,pointer],int);get_pid.call(hwnd,pid)
        raise 'Wrong keyboard test window' unless pid[0,4].unpack1('L')==Process.pid
        HUDInput.stop;HUDInput.instance_variable_set(:@api,nil);HUDInput.instance_variable_set(:@dll,nil)
        recorder=Recorder.new;HUDInput.start(recorder)
        post=Fiddle::Function.new(native['PostMessageW'],[pointer,int,Fiddle::TYPE_LONG_LONG,Fiddle::TYPE_LONG_LONG],int)
        expected=[48,57,96,105]
        expected.each { |key| post.call(hwnd,0x100,key,1);post.call(hwnd,0x101,key,1<<30) }
        UI.start_timer(0.35,false) do
          begin
            raise 'Native digit filtering/polling did not deliver all keys' unless recorder.keys==expected
            HUDInput.stop(recorder)
            raise 'Native keyboard filter remained active' if HUDInput.active?
            raise 'Keyboard test modified the model or selection' unless before==model.entities.map(&:persistent_id) && selection==model.selection.to_a
            report={'status'=>'passed','keys'=>recorder.keys,'filter_stopped'=>true,'model_retained'=>true}
          rescue StandardError=>error
            HUDInput.stop(recorder);report={'status'=>'failed','keys'=>recorder.keys,'error'=>error.message}
          end
          folder=File.join(File.dirname(__dir__),'outputs/hud-docks-082');FileUtils.mkdir_p(folder);File.write(File.join(folder,'digits.json'),JSON.pretty_generate(report));puts JSON.generate(report)
        end
        puts 'scheduled native Windows message test'
      end
    end
  end
end

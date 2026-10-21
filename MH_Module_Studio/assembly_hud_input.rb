# encoding: UTF-8
require 'fiddle'

module MH
  module ModuleStudio
    # Receives only bounded tree mouse events. Never captures M/S or other keys.
    module AssemblyHUDInput
      extend self

      def start(view)
        unless @api
          raise Core::Error,'HUD cần SketchUp Windows 64-bit.' unless Sketchup.platform==:platform_win && Fiddle::SIZEOF_VOIDP==8
          @dll = Fiddle.dlopen(File.join(__dir__.dup.force_encoding(Encoding::UTF_8),'native','assembly_input_v2.dll'))
          int = Fiddle::TYPE_INT; ptr = Fiddle::TYPE_VOIDP
          signatures = {'AHStart'=>[[int,int],int],'AHStop'=>[[],Fiddle::TYPE_VOID],
            'AHRect'=>[[int,int,int,int],Fiddle::TYPE_VOID],'AHPoll'=>[[ptr,ptr,ptr],int],
            'AHViewport'=>[[ptr,ptr,ptr,ptr],int],'AHActive'=>[[],int],'AHScale'=>[[],Fiddle::TYPE_DOUBLE]}
          @api = signatures.to_h { |name,(args,result)| [name,Fiddle::Function.new(@dll[name],args,result)] }
        end
        factor = UI.scale_factor.to_f
        raise Core::Error,'Không gắn được cây HUD vào viewport.' unless @api['AHStart'].call((view.vpwidth*factor).round,(view.vpheight*factor).round)==1
        @factor = factor*@api['AHScale'].call
      end

      def stop
        @api&.fetch('AHStop')&.call
      end

      def active?
        @api && @api['AHActive'].call==1
      end

      def region(rect)
        factor = @factor || UI.scale_factor.to_f
        @api['AHRect'].call(*rect.map { |v| (v*factor).round })
      end

      def read(name,count)
        pointers = Array.new(count) { Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT,Fiddle::RUBY_FREE) }
        return unless @api && @api[name].call(*pointers)==1
        pointers.map { |ptr| ptr[0,Fiddle::SIZEOF_INT].unpack1('i') }
      end

      def poll
        event = read('AHPoll',3)
        event && [event[0],event[1]/@factor,event[2]/@factor]
      end

      def viewport
        read('AHViewport',4)&.map { |v| v/@factor }
      end
    end
  end
end

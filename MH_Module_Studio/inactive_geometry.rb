# encoding: UTF-8
module MH
  module ModuleStudio
    # Inactive alternatives retain native Scale on free axes. On a proved root
    # output axis they follow its coordinate frame until activated and rebuilt
    # from their own ATT. Never let masked geometry override an exact root T.
    module InactiveGeometry
      extend self

      def align!(bounds, frozen, visibility, outputs)
        hidden=bounds.keys.select { |key| visibility[key]==false }
        visible=bounds.keys-hidden
        return bounds if hidden.empty? || visible.empty? || outputs.empty?
        source=Core.union(frozen.values)
        target=Core.union(visible.map { |key| {'bounds'=>bounds.fetch(key)} })
        outputs.each do |key,declared|
          axis=%w[lenx leny lenz].index(key)
          old=Core.dimensions(source)[axis];size=Core.dimensions(target)[axis]
          next unless axis && declared.is_a?(Numeric) && declared.positive? && old>0.001 &&
                      (size-declared).abs<=0.001
          hidden.each do |part|
            box=Core.copy_data(bounds.fetch(part))
            next if box[0][axis]>=target[0][axis]-0.001 && box[1][axis]<=target[1][axis]+0.001
            if Core.dimensions(box)[axis]<=size+0.001
              shift=box[0][axis]<target[0][axis] ? target[0][axis]-box[0][axis] : target[1][axis]-box[1][axis]
              2.times { |side| box[side][axis]+=shift }
            else
              2.times { |side| box[side][axis]=target[0][axis]+(box[side][axis]-source[0][axis])*size/old }
            end
            bounds[part]=box
          end
        end
        bounds
      end
    end
  end
end

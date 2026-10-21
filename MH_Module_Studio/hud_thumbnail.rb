# encoding: UTF-8
require 'digest'
require 'tmpdir'
require 'fileutils'
module MH
  module ModuleStudio
    # HUD presentation only: fit the complete image and strengthen thin ink edges.
    module HUDThumbnail
      extend self

      CACHE_VERSION = 'ink2-trim3-v1'.freeze

      def cache_path(key)
        File.join(Dir.tmpdir,'MH_Module_Studio_HUD',Digest::SHA256.hexdigest(CACHE_VERSION+'|'+key)+'.png')
      end

      def cached_image(key)
        path=cache_path(key)
        File.file?(path) ? Sketchup::ImageRep.new(path) : nil
      rescue SystemCallError,ArgumentError
        nil
      end

      def cache_image(key,image)
        path=cache_path(key);FileUtils.mkdir_p(File.dirname(path))
        temporary=path+'.tmp-'+Process.pid.to_s+'.png'
        image.save_file(temporary)
        FileUtils.mv(temporary,path,force:true) if File.file?(temporary) && File.size(temporary).positive?
      rescue SystemCallError
        nil # The prepared picture still displays when the cache folder is readonly.
      ensure
        File.delete(temporary) if temporary && File.file?(temporary)
      end

      def half_size(aspect,size,percent)
        scale = [[percent/100.0,0.25].max,3.0].min
        half_height = (size*0.5-2.0)*scale/Math.sqrt(aspect*aspect+1.0)
        [half_height*aspect,half_height]
      end

      def mesh(aspect,size,percent)
        width,height = half_size(aspect,size,percent)
        polygon = [[-width,-height],[width,-height],[width,height],[-width,height]]
        if percent>100
          radius = size*0.5-1.0
          polygon = 48.times.map { |index| angle=index*Math::PI/24; [radius*Math.cos(angle),radius*Math.sin(angle)] }
          [[0,-width,-1],[0,width,1],[1,-height,-1],[1,height,1]].each do |axis,limit,direction|
            input = polygon; polygon = []
            input.each_with_index do |point,index|
              previous = input[index-1]
              inside = (point[axis]-limit)*direction<=0
              was_inside = (previous[axis]-limit)*direction<=0
              if inside!=was_inside
                ratio = (limit-previous[axis])/(point[axis]-previous[axis])
                polygon << 2.times.map { |coordinate| previous[coordinate]+ratio*(point[coordinate]-previous[coordinate]) }
              end
              polygon << point if inside
            end
          end
        end
        points = polygon.each_with_index.flat_map { |point,index| [[0.0,0.0],point,polygon[(index+1)%polygon.length]] }
        uvs = points.map { |x,y| [(0.5+x/(2*width)).clamp(0.0,1.0),(0.5-y/(2*height)).clamp(0.0,1.0)] }
        [points,uvs]
      end

      def prepare(image)
        data = bold_pixels(image.data,image.width,image.height,image.bits_per_pixel,image.row_padding)
        data,width,height,padding = trim(data,image.width,image.height,image.bits_per_pixel,image.row_padding)
        image.set_data(width,height,image.bits_per_pixel,padding,data)
        image
      end

      def trim(data,width,height,bits,padding)
        unchanged = [data,width,height,padding]
        return unchanged unless [24,32].include?(bits)
        channels=bits/8;stride=width*channels+padding
        blank = lambda do |x,y|
          offset=y*stride+x*channels
          alpha=channels==4 ? data.getbyte(offset+3) : 255
          alpha.zero? || (alpha>=250 && 3.times.all? { |channel| data.getbyte(offset+channel)>=250 })
        end
        return unchanged unless [[0,0],[width-1,0],[0,height-1],[width-1,height-1]].all? { |x,y| blank.call(x,y) }
        left=width;right=-1;bottom=height;top=-1
        height.times do |y|
          width.times do |x|
            next if blank.call(x,y)
            left=[left,x].min;right=[right,x].max;bottom=[bottom,y].min;top=[top,y].max
          end
        end
        return unchanged if right<left
        left=[left-3,0].max;right=[right+3,width-1].min;bottom=[bottom-3,0].max;top=[top+3,height-1].min
        cropped=(bottom..top).map { |y| data.byteslice(y*stride+left*channels,(right-left+1)*channels) }.join
        [cropped,right-left+1,top-bottom+1,0]
      end

      def bold_pixels(data,width,height,bits,padding)
        return data unless [24,32].include?(bits)
        channels = bits/8; stride = width*channels+padding
        output = data.dup
        height.times do |y|
          width.times do |x|
            offset = y*stride+x*channels
            colors = 3.times.map { |channel| data.getbyte(offset+channel) }
            low,high = colors.minmax
            next if high>190 || high-low>16 || (channels==4 && data.getbyte(offset+3)<250)
            neighbors = []
            neighbors << offset-channels if x.positive?
            neighbors << offset+channels if x+1<width
            neighbors << offset-stride if y.positive?
            neighbors << offset+stride if y+1<height
            next unless neighbors.any? { |position| 3.times.sum { |channel| data.getbyte(position+channel) }/3.0-high>=40 }
            ink = colors.map { |value| [2*value-255,0].max }
            # One extra pixel per direction doubles a one-pixel stroke, without
            # repeatedly growing already-strengthened pixels in this pass.
            [y,y+1].each do |row|
              next if row>=height
              [x,x+1].each do |column|
                next if column>=width
                target = row*stride+column*channels
                next if channels==4 && data.getbyte(target+3)<250
                3.times { |channel| output.setbyte(target+channel,[output.getbyte(target+channel),ink[channel]].min) }
              end
            end
          end
        end
        output
      end
    end
  end
end

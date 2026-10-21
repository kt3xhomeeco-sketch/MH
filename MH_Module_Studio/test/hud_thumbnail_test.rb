# encoding: UTF-8
require 'minitest/autorun'
require_relative '../hud_thumbnail'

class ModuleStudioHUDThumbnailTest < Minitest::Test
  Image=MH::ModuleStudio::HUDThumbnail

  def test_complete_image_fits_fixed_thin_border_at_all_supported_sizes
    [24,60,140].product([0.2,0.5,1.0,2.0,5.0],[25,50,75,100]).each do |size,aspect,percent|
      width,height=Image.half_size(aspect,size,percent)
      assert_in_delta aspect,width/height,0.000001
      assert_operator Math.hypot(width,height),:<=,size/2.0-1.999999
    end
    small=Image.half_size(2.0,60,50); full=Image.half_size(2.0,60,100)
    assert_in_delta full[0]/2,small[0],0.000001
    assert_in_delta full[1]/2,small[1],0.000001
    assert_in_delta full[0]*2.5,Image.half_size(2.0,60,250)[0],0.000001
  end

  def test_zoom_mesh_enlarges_picture_without_crossing_circle_or_repeating_texture
    [24,60,140].product([0.1,0.5,1.0,2.0,10.0],[25,100,150,250,300]).each do |size,aspect,percent|
      points,uvs=Image.mesh(aspect,size,percent)
      assert_operator points.length,:>=,12
      assert_equal 0,points.length%3
      assert_equal points.length,uvs.length
      assert(points.all? { |x,y| Math.hypot(x,y)<=size/2.0-0.999999 })
      assert(uvs.all? { |u,v| u.between?(0,1) && v.between?(0,1) })
      assert_equal [[0,0],[0,1],[1,0],[1,1]],uvs.reject { |p| p==[0.5,0.5] }.uniq.sort if percent<=100
    end
    normal,=Image.mesh(1.0,60,100);large,=Image.mesh(1.0,60,200)
    assert_operator large.map(&:first).max,:>,normal.map(&:first).max
  end

  def test_trim_removes_only_unused_white_margin_and_retains_ink_and_safety_space
    data=([255,255,255]*400).pack('C*')
    (8..11).each { |y| (7..12).each { |x| data[(y*20+x)*3,3]=[20,80,160].pack('C*') } }
    source=data.dup
    cropped,width,height,padding=Image.trim(data,20,20,24,0)
    assert_equal [12,10,0],[width,height,padding]
    assert_equal [20,80,160],cropped[(3*width+3)*3,3].bytes
    assert_equal source,data
    assert_equal [cropped,width,height,0],Image.trim(cropped,width,height,24,0),'Trimming is stable'
    dark=([150,150,150]*400).pack('C*')
    assert_equal [dark,20,20,0],Image.trim(dark,20,20,24,0),'No guessing a non-white background'
    transparent=([0,0,0,0]*400).pack('C*')
    assert_equal [transparent,20,20,0],Image.trim(transparent,20,20,32,0),'Empty transparent thumbnail remains valid'
  end

  def test_gray_ink_contrast_and_one_pixel_stroke_double_without_repeated_growth
    data=([255,255,255]*25).pack('C*')
    5.times { |y| 3.times { |channel| data.setbyte((y*5+2)*3+channel,128) } }
    original=data.dup
    bold=Image.bold_pixels(data,5,5,24,0)
    assert_equal original,data,'Source/cache bytes remain immutable'
    5.times do |y|
      assert_equal [255,255,1,1,255],(5.times.map { |x| bold.getbyte((y*5+x)*3) })
    end
    assert_equal ([150,150,150]*25).pack('C*'),Image.bold_pixels(([150,150,150]*25).pack('C*'),5,5,24,0),'Uniform material is not darkened'
  end

  def test_color_alpha_padding_and_row_boundaries_are_retained
    data=([255,255,255,255]*8).pack('C*')
    data[0,4]=[10,80,160,255].pack('C*')
    data[12,4]=[100,100,100,255].pack('C*')
    data[28,4]=[20,20,20,0].pack('C*')
    result=Image.bold_pixels(data,4,2,32,0)
    assert_equal data[0,4],result[0,4],'Colored materials are not recolored'
    assert_equal data[28,4],result[28,4],'Transparent pixels/alpha remain untouched'
    assert_equal [255,255,255,255],result[16,4].bytes,'Right-edge ink never wraps to the next row'
    padded=([255,255,255,100,100,100,9,8]*2).pack('C*')
    output=Image.bold_pixels(padded,2,2,24,2)
    assert_equal [9,8],output[6,2].bytes
    assert_equal [9,8],output[14,2].bytes
  end
end

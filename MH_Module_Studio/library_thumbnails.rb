# encoding: UTF-8
require 'json'
require 'digest'
require 'fileutils'
require 'tmpdir'

module MH
  module ModuleStudio
    # Per-library presentation data; never write camera or rules into source SKPs.
    class LibraryThumbnails
      VIEWS = {'saved'=>'Ảnh gốc SKP','iso'=>'3D','front'=>'Mặt đứng','top'=>'Mặt bằng',
               'left'=>'Mặt trái','right'=>'Mặt phải','back'=>'Mặt sau','bottom'=>'Mặt dưới'}.freeze
      DIRECTIONS = {'iso'=>[[1,-1,1],[0,0,1]],'front'=>[[0,-1,0],[0,0,1]],'top'=>[[0,0,1],[0,1,0]],
                    'left'=>[[-1,0,0],[0,0,1]],'right'=>[[1,0,0],[0,0,1]],'back'=>[[0,1,0],[0,0,1]],'bottom'=>[[0,0,-1],[0,-1,0]]}.freeze
      attr_reader :root

      def initialize(root)
        @root = root
        @records = {}
        file = index_path
        return unless File.file?(file)
        raise Core::Error,'Cài đặt ảnh thư viện vượt 2 MB.' if File.size(file)>2*1024*1024
        data = JSON.parse(File.read(file,encoding:'UTF-8'))
        unless data.is_a?(Hash) && data['version']==1 && data['items'].is_a?(Hash) && data['items'].length<=5000 &&
               data['items'].all? { |id,row| id.is_a?(String) && row.is_a?(Hash) && VIEWS.key?(row['view']) && row['revision'].is_a?(String) }
          raise Core::Error,'Cài đặt góc ảnh thư viện không hợp lệ.'
        end
        @records = data['items']
      rescue JSON::ParserError
        raise Core::Error,'Không đọc được cài đặt góc ảnh thư viện.'
      end

      def index_path
        File.join(@root,'.mh-thumbnails','index.json')
      end

      def view(item)
        @records.dig(item['id'],'view') || 'front'
      end

      def key(item,record = @records[item['id']])
        record ||= {'view'=>'front','revision'=>'default-front-v1'}
        Digest::SHA256.hexdigest(JSON.generate([item['fingerprint'],record['view'],record['revision'],'camera-v1']))
      end

      def image_path(item,record = @records[item['id']])
        folder = record ? File.dirname(index_path) : File.join(Dir.tmpdir,'MH_Module_Studio_Library')
        File.join(folder,key(item,record)+'.png')
      end

      def path(item)
        output = image_path(item)
        return output if File.file?(output) && File.size(output).positive?
        render(item,view(item),output)
        output
      end

      def preview_path(item)
        desired = image_path(item)
        return desired if File.file?(desired) && File.size(desired).positive?
        # The original SKP thumbnail is cheap to show while the desired camera
        # is generated later by the HUD image job, preserving fast cold opens.
        preview = File.join(Dir.tmpdir,'MH_Module_Studio_Library',item['fingerprint']+'.png')
        render(item,'saved',preview) unless File.file?(preview) && File.size(preview).positive?
        preview
      end

      def update(item,selected)
        raise Core::Error,'Góc ảnh không hợp lệ.' unless VIEWS.key?(selected)
        record = {'view'=>selected,'revision'=>Core::Ids.hex(8)}
        output = image_path(item,record)
        render(item,selected,output)
        proposed = @records.merge(item['id']=>record)
        raise Core::Error,'Thư viện vượt 5.000 góc ảnh.' if proposed.length>5000
        temporary = index_path+'.tmp-'+Core::Ids.hex(4)
        File.write(temporary,JSON.generate('version'=>1,'items'=>proposed),mode:'w',encoding:'UTF-8')
        FileUtils.mv(temporary,index_path,force:true)
        @records = proposed
        output
      ensure
        File.delete(temporary) if temporary && File.file?(temporary)
      end

      def render(item,selected,output)
        raise Core::Error,'File đã đổi; làm mới thư viện trước khi cập nhật ảnh.' unless LibraryCatalog.fingerprint(item['path'])==item['fingerprint']
        FileUtils.mkdir_p(File.dirname(output))
        temporary = output+'.tmp-'+Core::Ids.hex(4)+'.png'
        if selected=='saved'
          raise Core::Error,'Không trích được ảnh gốc SKP.' unless Sketchup.save_thumbnail(item['path'],temporary)
        else
          render_camera(item['path'],selected,temporary)
        end
        raise Core::Error,'Không tạo được ảnh module.' unless File.file?(temporary) && File.size(temporary).positive?
        raise Core::Error,'File thay đổi trong lúc tạo ảnh; làm mới thư viện.' unless LibraryCatalog.fingerprint(item['path'])==item['fingerprint']
        FileUtils.mv(temporary,output,force:true)
      ensure
        File.delete(temporary) if temporary && File.file?(temporary)
      end

      def render_camera(path,selected,output)
        model = Sketchup.active_model
        Runtime.ensure_top_level(model)
        model.start_operation('MH Tạo Ảnh Thư Viện',true); operation = true
        definition = model.definitions.load(path)
        copy = model.active_entities.add_instance(definition,Geom::Transformation.new)
        copy.make_unique
        definition = copy.definition
        bounds = definition.bounds
        raise Core::Error,'Module không có hình học để tạo ảnh.' if bounds.empty? || bounds.diagonal<0.000001
        direction,up = DIRECTIONS.fetch(selected)
        distance = [bounds.diagonal*2,1.0].max
        eye = bounds.center+Geom::Vector3d.new(direction.map { |value| value*distance })
        camera = Sketchup::Camera.new(eye,bounds.center,Geom::Vector3d.new(up),false)
        camera.height = bounds.diagonal*1.1
        definition.thumbnail_camera = camera
        definition.refresh_thumbnail
        raise Core::Error,'Không xuất được ảnh theo góc đã chọn.' unless definition.save_thumbnail(output)
      ensure
        model.abort_operation if operation
      end
    end
  end
end

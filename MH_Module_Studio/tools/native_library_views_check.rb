# encoding: UTF-8
require_relative 'native_drawer_check'

module MH
  module ModuleStudio
    module NativeLibraryViewsCheck
      extend self

      def run(expected_pid:)
        raise 'Wrong SketchUp session' unless Process.pid==expected_pid && Sketchup.active_model.active_path.nil?
        model = Sketchup.active_model
        roots = model.entities.select { |entity| Assembly.container?(entity) }.to_h { |entity| [entity,NativeDrawerCheck.fingerprint(entity)] }
        definitions = model.definitions.to_a; selected = model.selection.map(&:persistent_id)
        camera = model.active_view.camera
        camera_before = [camera.eye.to_a,camera.target.to_a,camera.up.to_a,camera.perspective?]
        library = MH::ModuleStudio.library
        library.refresh
        source = library.catalog['entries'].find { |item| item['name'].include?('Khung noc lot') } || library.catalog['entries'].first
        raise 'Library is empty' unless source
        base = File.dirname(Panel.instance_method(:request).source_location.first)
        folder = Dir.mktmpdir('qa051-',File.join(base,'outputs'))
        path = File.join(folder,'Khung QA051.skp'); FileUtils.cp(source['path'],path)
        FileUtils.cp(source['path'],File.join(folder,'Other QA051.skp'))
        hash = Digest::SHA256.file(path).hexdigest
        replies = []
        own = Library.new { |receiver,state| replies << [receiver,state] }
        own.config['root']=folder;own.config['folder']='';own.refresh
        item = own.catalog['entries'].first
        report = {'ok'=>false,'folder'=>folder,'images'=>{},'checks'=>[]}
        begin
          LibraryThumbnails::VIEWS.each_key do |view|
            own.update_thumbnail(item['id'],view)
            image_path = own.thumbnail(item)
            image = Sketchup::ImageRep.new;image.load_file(image_path)
            raise 'Image missing or empty' unless image.width>0 && image.height>0
            report['images'][view] = {'path'=>image_path,'width'=>image.width,'height'=>image.height,'sha256'=>Digest::SHA256.file(image_path).hexdigest}
          end
          raise 'Camera views all produced the same image' unless report['images'].values.map { |row| row['sha256'] }.uniq.length>=4
          report['checks'] << 'All eight view choices produce actual PNGs with distinct camera images'
          raise 'Source SKP was changed' unless Digest::SHA256.file(path).hexdigest==hash
          report['checks'] << 'Source SKP bytes and placement fingerprint unchanged'
          reloaded = LibraryThumbnails.new(folder)
          raise 'View not persisted' unless reloaded.view(item)=='bottom'
          other = own.catalog['entries'].last
          raise 'Other module view changed' unless reloaded.view(other)=='front'
          report['checks'] << 'Per-module view survives reload and leaves the other icon unchanged'
          hud = LibraryHUD.new(own)
          hud.instance_variable_set(:@items,own.catalog['entries']);hud.instance_variable_set(:@page,0);hud.instance_variable_set(:@folders,false)
          hud.load_textures
          old_key = own.thumbnail_key(item)
          own.update_thumbnail(item['id'],'front');hud.load_textures
          raise 'HUD kept the stale texture' if hud.instance_variable_get(:@textures).key?(old_key)
          raise 'HUD missed updated texture' unless hud.instance_variable_get(:@textures).key?(own.thumbnail_key(item))
          fake = Object.new;settings_state = nil
          fake.define_singleton_method(:execute_script) { |script| settings_state = JSON.parse(JSON.parse(script[/JSON.parse\((.*)\)\);/,1])) }
          hud.instance_variable_set(:@settings,fake);hud.send_settings
          raise 'HUD Settings still owns icon editing' if settings_state.key?('icons') || settings_state.key?('thumbnail_views')
          report['checks'] << 'Library updates the HUD GPU texture; HUD Settings excludes per-icon editing'
          report['ok'] = true
        rescue StandardError=>error
          report['error'] = [error.message,*error.backtrace.first(7)]
        ensure
          hud&.instance_variable_get(:@textures)&.each_value { |texture| model.active_view.release_texture(texture) }
          model.start_operation('MH QA051 Cleanup',true)
          40.times do
            empty=(model.definitions.to_a-definitions).select { |definition| definition.instances.empty? };break if empty.empty?
            empty.each { |definition| model.definitions.remove(definition) }
          end
          model.commit_operation
          Assembly.watch(model).reset;ScaleRedraw.watch(model).reset
          current = model.active_view.camera
          retained = roots.all? { |root,signature| root.valid? && NativeDrawerCheck.fingerprint(root)==signature } && selected==model.selection.map(&:persistent_id) && camera_before==[current.eye.to_a,current.target.to_a,current.up.to_a,current.perspective?]
          report['checks'] << 'All user objects, selection and viewport camera retained' if retained
          report['ok'] &&= retained
        end
        report
      end
    end
  end
end

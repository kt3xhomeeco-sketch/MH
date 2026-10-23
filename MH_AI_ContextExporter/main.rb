# frozen_string_literal: true

require 'sketchup.rb'
require 'json'
require 'time'
require 'fileutils'
require 'digest'
require 'base64'

module MH
  module AIContextExporter
    extend self

    MAX_SELECTED_ENTITIES = 50
    MAX_FACE_VERTICES = 64
    MAX_PASTED_IMAGE_BYTES = 3 * 1024 * 1024
    MAX_PASTED_IMAGE_INPUT_BYTES = 20 * 1024 * 1024
    MAX_PASTED_IMAGE_WIDTH = 1600
    MAX_PASTED_IMAGE_HEIGHT = 1200
    MAX_PASTED_IMAGE_BASE64_CHARS = ((MAX_PASTED_IMAGE_BYTES + 2) / 3) * 4
    APP_NAME = 'MH SketchUp Plugins'
    REPOSITORY_URL = 'https://github.com/kt3xhomeeco-sketch/MH'

    def install_menu
      return if @menu_installed

      UI.menu('Extensions').add_item('MH · Xuất ngữ cảnh lỗi cho AI…') { export_context }
      @menu_installed = true
    end

    def export_context
      model = Sketchup.active_model
      selection = model.selection.to_a.select { |entity| entity.valid? }
      if selection.length > MAX_SELECTED_ENTITIES
        UI.messagebox("Đang chọn #{selection.length} đối tượng. Hãy thu hẹp lựa chọn còn tối đa #{MAX_SELECTED_ENTITIES} đối tượng liên quan rồi xuất lại.")
        return
      end

      prompt_issue_description do |issue_description, pasted_image|
        export_context_for_issue(model, selection, issue_description, pasted_image)
      end
    rescue StandardError => error
      UI.messagebox("Không xuất được gói ngữ cảnh: #{error.class}: #{error.message}")
    end

    def prompt_issue_description(&on_submit)
      @issue_dialog&.close
      @issue_dialog = UI::HtmlDialog.new(
        dialog_title: 'MH · Ngữ cảnh lỗi',
        preferences_key: 'MH_AI_ContextExporter_IssueDialog',
        width: 820,
        height: 500,
        min_width: 640,
        min_height: 380,
        resizable: true,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @issue_dialog.add_action_callback('submit_issue') do |_context, raw|
        data = JSON.parse(raw)
        issue_description = data['description'].to_s.strip
        pasted_image = nil
        begin
          pasted_image = decode_pasted_image(data)
        rescue ArgumentError => error
          UI.messagebox("Không dùng được ảnh dán: #{error.message}")
          next
        end

        if issue_description.empty? && pasted_image.nil?
          UI.messagebox('Hãy mô tả ngắn gọn lỗi hoặc điều cần phân tích, hoặc dán ảnh lỗi.')
          next
        end

        @issue_dialog.close
        @issue_dialog = nil
        on_submit.call(issue_description, pasted_image)
      end
      @issue_dialog.add_action_callback('cancel_issue') do |_context, _raw|
        @issue_dialog.close
        @issue_dialog = nil
      end
      @issue_dialog.set_html(issue_description_html)
      @issue_dialog.show
    end

    def issue_description_html
      <<~HTML
        <!doctype html>
        <html lang="vi">
        <head>
          <meta charset="utf-8">
          <style>
            * { box-sizing: border-box; }
            body { margin: 0; padding: 22px; font: 15px "Segoe UI", sans-serif; color: #202124; }
            label { display: block; margin-bottom: 10px; font-size: 17px; font-weight: 600; }
            textarea { display: block; width: 100%; height: 180px; min-height: 120px; resize: vertical; padding: 12px; border: 1px solid #9aa0a6; border-radius: 5px; font: 15px "Segoe UI", sans-serif; }
            .paste-panel { display: flex; align-items: center; gap: 10px; min-height: 28px; margin-top: 10px; }
            .paste-status { flex: 1; color: #5f6368; font-size: 13px; }
            .paste-status.error { color: #b3261e; }
            #preview { display: none; max-width: 100%; max-height: 150px; margin-top: 8px; border: 1px solid #dadce0; border-radius: 5px; }
            button.secondary { min-width: 0; padding: 5px 10px; font-size: 13px; }
            .buttons { display: flex; justify-content: flex-end; gap: 10px; margin-top: 14px; }
            button { min-width: 110px; padding: 9px 18px; border: 1px solid #9aa0a6; border-radius: 5px; background: #f8f9fa; font: 15px "Segoe UI", sans-serif; cursor: pointer; }
            button.primary { color: white; background: #1769aa; border-color: #1769aa; }
          </style>
        </head>
        <body>
          <label for="description">Mô tả lỗi hoặc yêu cầu cần phân tích</label>
          <textarea id="description" autofocus placeholder="Có thể xuống dòng để mô tả chi tiết…"></textarea>
          <div class="paste-panel">
            <span id="pasteStatus" class="paste-status">Ctrl+V dán ảnh PNG/JPEG (tối đa 1600×1200 px, 3 MiB).</span>
            <button id="removeImage" class="secondary" type="button" hidden>Xóa ảnh</button>
          </div>
          <img id="preview" alt="Ảnh đã dán">
          <div class="buttons">
            <button onclick="sketchup.cancel_issue('')">Hủy</button>
            <button class="primary" onclick="submitIssue()">Tiếp tục</button>
          </div>
          <script>
            var pastedImage = null;
            var MAX_BYTES = #{MAX_PASTED_IMAGE_BYTES};
            var MAX_INPUT_BYTES = #{MAX_PASTED_IMAGE_INPUT_BYTES};
            var MAX_WIDTH = #{MAX_PASTED_IMAGE_WIDTH};
            var MAX_HEIGHT = #{MAX_PASTED_IMAGE_HEIGHT};
            var MAX_BASE64_CHARS = #{MAX_PASTED_IMAGE_BASE64_CHARS};

            function setPasteStatus(message, isError) {
              var status = document.getElementById('pasteStatus');
              status.textContent = message;
              status.className = 'paste-status' + (isError ? ' error' : '');
            }

            function clearPastedImage() {
              pastedImage = null;
              var preview = document.getElementById('preview');
              preview.removeAttribute('src');
              preview.style.display = 'none';
              document.getElementById('removeImage').hidden = true;
              setPasteStatus('Ctrl+V dán ảnh PNG/JPEG (tối đa 1600×1200 px, 3 MiB).', false);
            }

            async function acceptPastedImage(blob) {
              try {
              if (!blob || (blob.type !== 'image/png' && blob.type !== 'image/jpeg')) {
                setPasteStatus('Ảnh dán phải là PNG hoặc JPEG.', true);
                return;
              }
              if (blob.size > MAX_INPUT_BYTES) {
                setPasteStatus('Ảnh gốc quá lớn (' + (blob.size / 1048576).toFixed(1) + ' MiB); hãy cắt vùng cần xem rồi dán lại.', true);
                return;
              }
              var image = await loadClipboardImage(blob);
              var scale = Math.min(1, MAX_WIDTH / image.width, MAX_HEIGHT / image.height);
              var width = Math.max(1, Math.round(image.width * scale));
              var height = Math.max(1, Math.round(image.height * scale));
              var normalizedBlob = blob;
              if (scale < 1 || blob.size > MAX_BYTES) normalizedBlob = await resizeClipboardImage(image, width, height, blob.type);
              if (normalizedBlob.size > MAX_BYTES) {
                setPasteStatus('Ảnh sau khi thu nhỏ vẫn lớn hơn 3 MiB; hãy cắt vùng cần xem rồi dán lại.', true);
                return;
              }
              var dataUrl = await readClipboardImage(normalizedBlob);
              var base64 = dataUrl.substring(dataUrl.indexOf(',') + 1);
              if (base64.length > MAX_BASE64_CHARS) {
                setPasteStatus('Ảnh vượt giới hạn dữ liệu; hãy cắt vùng cần xem rồi dán lại.', true);
                return;
              }
              var bytes = base64ToBytes(base64);
              var isPng = bytes.length >= 8 && bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 && bytes[3] === 71 &&
                bytes[4] === 13 && bytes[5] === 10 && bytes[6] === 26 && bytes[7] === 10;
              var isJpeg = bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
              if ((normalizedBlob.type === 'image/png' && !isPng) || (normalizedBlob.type === 'image/jpeg' && !isJpeg)) {
                setPasteStatus('Nội dung ảnh không khớp định dạng PNG/JPEG.', true);
                return;
              }
              pastedImage = { mime_type: normalizedBlob.type, data_base64: base64, width: width, height: height };
              var preview = document.getElementById('preview');
              preview.src = dataUrl;
              preview.style.display = 'block';
              document.getElementById('removeImage').hidden = false;
              var scaled = width !== image.width || height !== image.height;
              setPasteStatus('Đã dán ảnh ' + (normalizedBlob.type === 'image/png' ? 'PNG' : 'JPEG') +
                ' ' + width + '×' + height + ' (' + (normalizedBlob.size / 1024).toFixed(0) + ' KiB)' +
                (scaled || blob.size !== normalizedBlob.size ? '; đã tối ưu để gọn dữ liệu.' : '.') , false);
              } catch (error) {
                setPasteStatus(error && error.message ? error.message : 'Không xử lý được ảnh clipboard.', true);
              }
            }

            function loadClipboardImage(blob) {
              return new Promise(function(resolve, reject) {
                var url = URL.createObjectURL(blob);
                var image = new Image();
                image.onload = function() {
                  URL.revokeObjectURL(url);
                  resolve({ element: image, width: image.naturalWidth, height: image.naturalHeight });
                };
                image.onerror = function() {
                  URL.revokeObjectURL(url);
                  reject(new Error('Không đọc được ảnh từ clipboard.'));
                };
                image.src = url;
              });
            }

            function resizeClipboardImage(image, width, height, mimeType) {
              return new Promise(function(resolve, reject) {
                var canvas = document.createElement('canvas');
                canvas.width = width;
                canvas.height = height;
                var context = canvas.getContext('2d');
                if (!context) return reject(new Error('Không thể thu nhỏ ảnh.'));
                context.drawImage(image.element, 0, 0, width, height);
                canvas.toBlob(function(blob) {
                  if (blob) resolve(blob);
                  else reject(new Error('Không tạo được ảnh đã thu nhỏ.'));
                }, mimeType, 0.9);
              });
            }

            function readClipboardImage(blob) {
              return new Promise(function(resolve, reject) {
                var reader = new FileReader();
                reader.onload = function() { resolve(reader.result); };
                reader.onerror = function() { reject(new Error('Không thể đọc ảnh clipboard.')); };
                reader.readAsDataURL(blob);
              });
            }

            function base64ToBytes(value) {
              var binary = atob(value);
              var bytes = new Uint8Array(binary.length);
              for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
              return bytes;
            }

            document.getElementById('description').addEventListener('paste', function(event) {
              var items = event.clipboardData && event.clipboardData.items;
              if (!items) return;
              for (var i = 0; i < items.length; i++) {
                if (items[i].kind === 'file' && items[i].type.indexOf('image/') === 0) {
                  event.preventDefault();
                  acceptPastedImage(items[i].getAsFile());
                  return;
                }
              }
            });
            document.getElementById('removeImage').addEventListener('click', clearPastedImage);
            function submitIssue() {
              var data = { description: document.getElementById('description').value };
              if (pastedImage) data.pasted_image = pastedImage;
              sketchup.submit_issue(JSON.stringify(data));
            }
            document.getElementById('description').addEventListener('keydown', function(event) {
              if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') submitIssue();
            });
          </script>
        </body>
        </html>
      HTML
    end

    def decode_pasted_image(data)
      return nil unless data.is_a?(Hash) && data.key?('pasted_image')

      image = data['pasted_image']
      raise ArgumentError, 'dữ liệu ảnh không hợp lệ.' unless image.is_a?(Hash)

      mime_type = image['mime_type'].to_s.downcase
      raise ArgumentError, 'chỉ hỗ trợ ảnh PNG hoặc JPEG.' unless %w[image/png image/jpeg].include?(mime_type)
      width = Integer(image['width']) rescue nil
      height = Integer(image['height']) rescue nil
      unless width && height && width.between?(1, MAX_PASTED_IMAGE_WIDTH) && height.between?(1, MAX_PASTED_IMAGE_HEIGHT)
        raise ArgumentError, 'kích thước ảnh không hợp lệ hoặc vượt 1600×1200 px.'
      end

      bytes = decode_base64_strict(image['data_base64'].to_s)
      raise ArgumentError, 'ảnh vượt quá giới hạn 3 MiB.' if bytes.bytesize > MAX_PASTED_IMAGE_BYTES
      raise ArgumentError, 'nội dung ảnh không khớp định dạng PNG/JPEG.' unless image_signature_valid?(bytes, mime_type)

      {
        mime_type: mime_type,
        extension: mime_type == 'image/png' ? 'png' : 'jpg',
        width: width,
        height: height,
        bytes: bytes,
        sha256: Digest::SHA256.hexdigest(bytes)
      }
    end

    def decode_base64_strict(value)
      encoded = value.gsub(/\s+/, '')
      raise ArgumentError, 'dữ liệu ảnh rỗng.' if encoded.empty?
      raise ArgumentError, 'ảnh vượt quá giới hạn 3 MiB.' if encoded.length > MAX_PASTED_IMAGE_BASE64_CHARS
      raise ArgumentError, 'dữ liệu base64 không hợp lệ.' unless encoded.match?(/\A[A-Za-z0-9+\/]*={0,2}\z/) && encoded.length % 4 == 0

      bytes = begin
        Base64.strict_decode64(encoded)
      rescue ArgumentError
        raise ArgumentError, 'dữ liệu base64 không hợp lệ.'
      end
      raise ArgumentError, 'ảnh vượt quá giới hạn 3 MiB.' if bytes.bytesize > MAX_PASTED_IMAGE_BYTES

      bytes
    end

    def image_signature_valid?(bytes, mime_type)
      signature = mime_type == 'image/png' ? "\x89PNG\r\n\x1A\n".b : "\xFF\xD8\xFF".b
      bytes.b.start_with?(signature)
    end

    def default_context_dir
      File.join(ENV.fetch('USERPROFILE', Dir.home), 'Documents', 'MH_GitHub_Migration_20261021', 'MH_Sketchup_Plugins', 'ai_context')
    end

    def default_context_name
      "sketchup_context_#{Time.now.strftime('%Y%m%d_%H%M%S_%L')}"
    end

    def export_context_for_issue(model, selection, issue_description, pasted_image = nil)

      stamp = Time.now.strftime('%Y%m%d_%H%M%S')
      default_dir = default_context_dir
      FileUtils.mkdir_p(default_dir)
      json_path = UI.savepanel('Lưu gói ngữ cảnh lỗi', default_dir, "#{default_context_name}.json")
      return unless json_path

      unless json_path.downcase.end_with?('.json')
        UI.messagebox('Tên file phải kết thúc bằng .json.')
        return
      end

      base_path = json_path.sub(/\.json\z/i, '')
      json_path = "#{base_path}.json"
      markdown_path = "#{base_path}.md"
      image_path = "#{base_path}.png"
      pasted_image_path = pasted_image && "#{base_path}_pasted.#{pasted_image[:extension]}"
      output_paths = [json_path, markdown_path, image_path, pasted_image_path].compact
      if output_paths.any? { |path| File.exist?(path) }
        UI.messagebox('Tên gói này đã tồn tại. Hãy chọn tên khác để tránh ghi đè dữ liệu cũ.')
        return
      end
      pasted_attachment = pasted_image && {
        'kind' => 'pasted_image',
        'filename' => File.basename(pasted_image_path),
        'mime_type' => pasted_image[:mime_type],
        'width' => pasted_image[:width],
        'height' => pasted_image[:height],
        'bytes' => pasted_image[:bytes].bytesize,
        'sha256' => pasted_image[:sha256],
        'embedded' => false
      }

      written_paths = []
      begin
        image_saved = false
        if !selection.empty? || pasted_image.nil?
          written_paths << image_path
          image_saved = model.active_view.write_image(
            filename: image_path,
            width: [model.active_view.vpwidth.to_i, MAX_PASTED_IMAGE_WIDTH].min,
            height: [model.active_view.vpheight.to_i, MAX_PASTED_IMAGE_HEIGHT].min,
            antialias: true,
            compression: 0.85
          )
          File.delete(image_path) if !image_saved && File.exist?(image_path)
          written_paths.delete(image_path) unless image_saved
        end

        attachments = []
        attachments << {
          'kind' => 'active_view_screenshot',
          'filename' => File.basename(image_path),
          'mime_type' => 'image/png',
          'embedded' => false
        } if image_saved
        attachments << pasted_attachment if pasted_attachment
        payload = build_payload(model, selection, issue_description, stamp, attachments)

        written_paths << json_path
        File.write(json_path, JSON.pretty_generate(payload), mode: 'w:UTF-8')
        if pasted_image
          written_paths << pasted_image_path
          File.binwrite(pasted_image_path, pasted_image[:bytes])
        end
        written_paths << markdown_path
        File.write(markdown_path, render_markdown(payload, image_saved ? File.basename(image_path) : nil), mode: 'w:UTF-8')
      rescue StandardError
        written_paths.reverse_each do |path|
          begin
            File.delete(path) if File.exist?(path)
          rescue StandardError
            nil
          end
        end
        raise
      end

      files = [json_path, markdown_path]
      files << image_path if image_saved
      files << pasted_image_path if pasted_image
      scope = selection.empty? ? 'không có đối tượng được chọn' : "#{selection.length} đối tượng"
      UI.messagebox("Đã xuất ngữ cảnh (#{scope}):\n#{files.join("\n")}\n\nModel không bị thay đổi.")
    rescue StandardError => error
      UI.messagebox("Không xuất được gói ngữ cảnh: #{error.class}: #{error.message}")
    end

    def build_payload(model, selection, issue_description, stamp, attachments = [])
      options = model.options['UnitsOptions']
      view = model.active_view
      camera = view.camera
      payload = {
        'schema' => 'mh-ai-error-context/v1',
        'created_at' => Time.now.iso8601,
        'host' => { 'application' => 'SketchUp', 'version' => Sketchup.version },
        'project' => {
          'app_name' => APP_NAME,
          'repository_url' => REPOSITORY_URL,
          'commit_sha' => ''
        },
        'source' => {
          'model_title' => model.title,
          'model_file' => model.path.empty? ? nil : File.basename(model.path),
          'model_saved' => !model.path.empty?,
          'length_unit' => safe_option(options, 'LengthUnit'),
          'length_format' => safe_option(options, 'LengthFormat'),
          'length_precision' => safe_option(options, 'LengthPrecision'),
          'edit_transform' => transformation_array(model.edit_transform),
          'active_path' => Array(model.active_path).map { |entity| entity_summary(entity, include_geometry: false) }
        },
        'problem' => {
          'reported_error' => issue_description,
          'expected' => '',
          'actual' => '',
          'related_dwg_dxf' => ''
        },
        'view' => {
          'camera_eye' => point_array(camera.eye),
          'camera_target' => point_array(camera.target),
          'camera_up' => point_array(camera.up),
          'perspective' => camera.perspective?
        },
        'selection_count' => selection.length,
        'selection' => selection.map { |entity| entity_summary(entity, include_geometry: true) },
        'limits' => {
          'max_selected_entities' => MAX_SELECTED_ENTITIES,
          'face_vertices_per_face' => MAX_FACE_VERTICES,
          'scope' => 'Only the current SketchUp selection, active edit path, camera metadata, optional active-view screenshot, and optional pasted screenshot are included.',
          'max_pasted_image_dimensions' => [MAX_PASTED_IMAGE_WIDTH, MAX_PASTED_IMAGE_HEIGHT],
          'max_pasted_image_bytes' => MAX_PASTED_IMAGE_BYTES
        },
        'attachments' => attachments
      }
      payload
    end

    def entity_summary(entity, include_geometry:)
      result = {
        'class' => entity.typename,
        'entity_id' => (entity.entityID if entity.respond_to?(:entityID)),
        'persistent_id' => (entity.persistent_id if entity.respond_to?(:persistent_id)),
        'guid' => (entity.guid if entity.respond_to?(:guid)),
        'name' => (entity.name if entity.respond_to?(:name)),
        'tag' => (entity.layer.name if entity.respond_to?(:layer) && entity.layer),
        'hidden' => (entity.hidden? if entity.respond_to?(:hidden?)),
        'locked' => (entity.locked? if entity.respond_to?(:locked?)),
        'bounds_in_parent_context' => bounds_array(entity.bounds)
      }
      result['transformation'] = transformation_array(entity.transformation) if entity.respond_to?(:transformation)

      case entity
      when Sketchup::Edge
        result['start_point_in_parent_context'] = point_array(entity.start.position)
        result['end_point_in_parent_context'] = point_array(entity.end.position)
        result['curve_class'] = entity.curve&.typename
      when Sketchup::Face
        result['area_square_inches'] = entity.area
        result['normal_in_parent_context'] = point_array(entity.normal)
        result['outer_loop_vertex_count'] = entity.outer_loop.vertices.length
        result['outer_loop_vertices_in_parent_context'] = entity.outer_loop.vertices.first(MAX_FACE_VERTICES).map { |vertex| point_array(vertex.position) } if include_geometry
        result['outer_loop_vertices_truncated'] = entity.outer_loop.vertices.length > MAX_FACE_VERTICES if include_geometry
        result['hole_loop_count'] = [entity.loops.length - 1, 0].max
      when Sketchup::Group, Sketchup::ComponentInstance
        result['definition_name'] = entity.definition.name
        result['direct_child_count'] = entity.definition.entities.length
        result['direct_child_types'] = entity.definition.entities.to_a.group_by(&:typename).transform_values(&:length) if include_geometry
      end
      result
    end

    def bounds_array(bounds)
      return nil unless bounds && bounds.valid?

      { 'min' => point_array(bounds.min), 'max' => point_array(bounds.max), 'dimensions' => point_array(bounds.width, bounds.depth, bounds.height) }
    end

    def point_array(point, y = nil, z = nil)
      values = y.nil? ? [point.x, point.y, point.z] : [point, y, z]
      values.map { |value| value.to_f.round(6) }
    end

    def transformation_array(transformation)
      transformation.to_a.map { |value| value.to_f.round(9) }
    rescue StandardError
      nil
    end

    def safe_option(options, key)
      options[key]
    rescue StandardError
      nil
    end

    def markdown_value(value)
      value.to_s.empty? ? '(not specified)' : value.to_s.gsub(/[\r\n]+/, ' ')
    end

    def render_markdown(payload, image_name)
      problem = payload.fetch('problem')
      project = payload.fetch('project')
      lines = [
        '# SketchUp error context',
        '',
        "- Created: #{payload['created_at']}",
        "- App/project: #{markdown_value(project['app_name'])}",
        "- Repository URL: #{markdown_value(project['repository_url'])}",
        "- Commit/revision: #{markdown_value(project['commit_sha'])}",
        "- Model: #{payload.dig('source', 'model_title')} (#{payload.dig('source', 'model_file') || 'unsaved'})",
        "- SketchUp: #{payload.dig('host', 'version')}",
        "- Selected entities: #{payload['selection_count']}",
        "- Units: #{payload.dig('source', 'length_unit')}",
        '',
        '## Reported issue',
        "- Error / request: #{markdown_value(problem['reported_error'])}",
        '',
        '## Selected entities',
        *(payload.fetch('selection').empty? ? ['(No entities selected; see the reported issue.)'] : payload.fetch('selection').each_with_index.map do |entity, index|
          box = entity['bounds_in_parent_context']
          "#{index + 1}. #{entity['class']} · #{entity['name']} · PID #{entity['persistent_id']} · tag #{entity['tag']} · bounds #{box && box['min']} → #{box && box['max']}"
        end),
        '',
        '## View',
        *(image_name ? ["Active-view screenshot: see `#{image_name}`. The exporter did not move the camera."] : ['No duplicate active-view screenshot was added; use the pasted screenshot if present.']),
        *(payload.fetch('attachments').map do |attachment|
          dims = attachment['width'] && attachment['height'] ? ", #{attachment['width']}×#{attachment['height']} px" : ''
          size = attachment['bytes'] ? ", #{attachment['bytes']} bytes" : ''
          "- #{attachment['kind']}: see `#{attachment['filename']}` (#{attachment['mime_type']}#{dims}#{size})."
        end),
        '',
        'Coordinate fields and bounds are labeled with their SketchUp context. Compare them only after accounting for the active edit transform.'
      ]
      lines.join("\n") + "\n"
    end

    unless file_loaded?(__FILE__)
      install_menu
      file_loaded(__FILE__)
    end
  end
end

# frozen_string_literal: true

require 'sketchup.rb'
require 'json'
require 'time'
require 'fileutils'

module MH
  module AIContextExporter
    extend self

    MAX_SELECTED_ENTITIES = 50
    MAX_FACE_VERTICES = 64
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
      if selection.empty?
        UI.messagebox('Hãy chọn các đối tượng SketchUp liên quan đến lỗi trước khi xuất.')
        return
      end
      if selection.length > MAX_SELECTED_ENTITIES
        UI.messagebox("Đang chọn #{selection.length} đối tượng. Hãy thu hẹp lựa chọn còn tối đa #{MAX_SELECTED_ENTITIES} đối tượng liên quan rồi xuất lại.")
        return
      end

      prompt_issue_description do |issue_description|
        export_context_for_issue(model, selection, issue_description)
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
        if issue_description.empty?
          UI.messagebox('Hãy mô tả ngắn gọn lỗi hoặc điều cần phân tích.')
          next
        end

        @issue_dialog.close
        @issue_dialog = nil
        on_submit.call(issue_description)
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
            textarea { display: block; width: 100%; height: calc(100vh - 112px); min-height: 210px; resize: vertical; padding: 12px; border: 1px solid #9aa0a6; border-radius: 5px; font: 15px "Segoe UI", sans-serif; }
            .buttons { display: flex; justify-content: flex-end; gap: 10px; margin-top: 14px; }
            button { min-width: 110px; padding: 9px 18px; border: 1px solid #9aa0a6; border-radius: 5px; background: #f8f9fa; font: 15px "Segoe UI", sans-serif; cursor: pointer; }
            button.primary { color: white; background: #1769aa; border-color: #1769aa; }
          </style>
        </head>
        <body>
          <label for="description">Mô tả lỗi hoặc yêu cầu cần phân tích</label>
          <textarea id="description" autofocus placeholder="Có thể xuống dòng để mô tả chi tiết…"></textarea>
          <div class="buttons">
            <button onclick="sketchup.cancel_issue('')">Hủy</button>
            <button class="primary" onclick="submitIssue()">Tiếp tục</button>
          </div>
          <script>
            function submitIssue() {
              sketchup.submit_issue(JSON.stringify({ description: document.getElementById('description').value }));
            }
            document.getElementById('description').addEventListener('keydown', function(event) {
              if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') submitIssue();
            });
          </script>
        </body>
        </html>
      HTML
    end

    def export_context_for_issue(model, selection, issue_description)

      stamp = Time.now.strftime('%Y%m%d_%H%M%S')
      default_dir = File.join(ENV.fetch('USERPROFILE', Dir.home), 'Documents', 'MH_AI_Context')
      FileUtils.mkdir_p(default_dir)
      json_path = UI.savepanel('Lưu gói ngữ cảnh lỗi', default_dir, "sketchup_#{stamp}.json")
      return unless json_path

      base_path = json_path.sub(/\.json\z/i, '')
      json_path = "#{base_path}.json"
      markdown_path = "#{base_path}.md"
      image_path = "#{base_path}.png"
      payload = build_payload(model, selection, issue_description, stamp)

      File.write(json_path, JSON.pretty_generate(payload), mode: 'w:UTF-8')
      File.write(markdown_path, render_markdown(payload, File.basename(image_path)), mode: 'w:UTF-8')
      image_saved = model.active_view.write_image(
        filename: image_path,
        width: [model.active_view.vpwidth.to_i, 1600].min,
        height: [model.active_view.vpheight.to_i, 1200].min,
        antialias: true,
        compression: 0.85
      )
      File.delete(image_path) if !image_saved && File.exist?(image_path)

      files = [json_path, markdown_path]
      files << image_path if image_saved
      UI.messagebox("Đã xuất ngữ cảnh cho #{selection.length} đối tượng:\n#{files.join("\n")}\n\nModel không bị thay đổi.")
    rescue StandardError => error
      UI.messagebox("Không xuất được gói ngữ cảnh: #{error.class}: #{error.message}")
    end

    def build_payload(model, selection, issue_description, stamp)
      options = model.options['UnitsOptions']
      view = model.active_view
      camera = view.camera
      {
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
          'scope' => 'Only the current SketchUp selection and the active edit path are included.'
        }
      }
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
        *payload.fetch('selection').each_with_index.map do |entity, index|
          box = entity['bounds_in_parent_context']
          "#{index + 1}. #{entity['class']} · #{entity['name']} · PID #{entity['persistent_id']} · tag #{entity['tag']} · bounds #{box && box['min']} → #{box && box['max']}"
        end,
        '',
        '## View',
        "See `#{image_name}`. The image shows the current view; this exporter did not move the camera.",
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

# encoding: UTF-8

require 'sketchup.rb'

module MH
  module Redraw
    COMMAND_NAME = 'MH Redraw'.freeze
    DYNAMIC_DICTIONARY = 'dynamic_attributes'.freeze

    module_function

    def dynamic_component?(entity)
      return false unless entity.is_a?(Sketchup::ComponentInstance)
      return false unless entity.valid?

      instance_attributes = entity.attribute_dictionary(DYNAMIC_DICTIONARY, false)
      definition_attributes =
        entity.definition.attribute_dictionary(DYNAMIC_DICTIONARY, false)

      !instance_attributes.nil? || !definition_attributes.nil?
    rescue StandardError
      false
    end

    def selected_dynamic_components
      model = Sketchup.active_model
      return [] unless model

      model.selection.to_a.select { |entity| dynamic_component?(entity) }
    end

    def dynamic_component_class
      return nil unless defined?($dc_observers) && $dc_observers

      $dc_observers.get_latest_class
    rescue StandardError
      nil
    end

    def redraw_selection
      if @redrawing
        UI.messagebox('MH Redraw đang xử lý một lượt redraw khác.')
        return
      end

      components = selected_dynamic_components
      if components.empty?
        UI.messagebox('Hãy chọn ít nhất một Dynamic Component để redraw.')
        return
      end

      dc_class = dynamic_component_class
      unless dc_class && dc_class.respond_to?(:redraw_with_undo)
        UI.messagebox(
          "Không tìm thấy Dynamic Components.\n" \
          'Hãy bật extension Dynamic Components rồi thử lại.'
        )
        return
      end

      @redrawing = true
      Sketchup.status_text = "MH Redraw: đang xử lý #{components.length} component..."

      # Chạy ở lượt UI kế tiếp để tránh xung đột operation với lệnh/menu hiện tại.
      UI.start_timer(0, false) do
        redraw_components(components, dc_class)
      end
    end

    def redraw_components(components, dc_class)
      succeeded = 0
      failures = []

      components.each_with_index do |component, index|
        next unless component && component.valid?

        Sketchup.status_text =
          "MH Redraw: #{index + 1}/#{components.length}"

        begin
          dc_class.redraw_with_undo(component)
          succeeded += 1
        rescue StandardError => error
          failures << [component_label(component), error]
          warn(
            "[MH Redraw] #{component_label(component)}: " \
            "#{error.class}: #{error.message}"
          )
        end
      end

      report_result(succeeded, failures)
    ensure
      @redrawing = false
    end

    def component_label(component)
      name = component.name.to_s.strip
      name = component.definition.name.to_s.strip if name.empty?
      name.empty? ? "Component ##{component.entityID}" : name
    rescue StandardError
      'Component'
    end

    def report_result(succeeded, failures)
      if failures.empty?
        message = "MH Redraw: đã redraw #{succeeded} Dynamic Component."
        Sketchup.status_text = message
      else
        message =
          "Đã redraw thành công #{succeeded} component.\n" \
          "Không redraw được #{failures.length} component.\n\n" \
          'Chi tiết lỗi đã được ghi trong Ruby Console.'
        Sketchup.status_text = "MH Redraw: #{succeeded} thành công, #{failures.length} lỗi."
        UI.messagebox(message)
      end
    end

    unless file_loaded?(__FILE__)
      command = UI::Command.new(COMMAND_NAME) { redraw_selection }
      command.tooltip = 'Redraw các Dynamic Component đang chọn'
      command.status_bar_text =
        'Redraw tất cả Dynamic Component đang được chọn trong một lần chạy'

      UI.menu('Extensions').add_item(command)

      UI.add_context_menu_handler do |menu|
        menu.add_item(command) unless selected_dynamic_components.empty?
      end

      file_loaded(__FILE__)
    end
  end
end

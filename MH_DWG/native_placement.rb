# frozen_string_literal: true

module MH
  # CAD clipboard import and placement for SketchUp.
  module DWG
    def self.assign_tag(inst, model = inst.model)
      return unless inst.is_a?(Sketchup::ComponentInstance)

      tag = model.layers[TAG_NAME] || model.layers.add(TAG_NAME)
      inst.layer = tag
    end

    def self.pending_native_taggers
      @pending_native_taggers
    end

    def self.importing?
      @importing
    end

    def self.defer_native_tagging
      previous = @native_tagger
      @native_tagger = nil
      @pending_native_taggers << previous if previous&.defer_placed!
    end

    def self.start_native_placement(model, definition)
      defer_native_tagging
      @native_tagger = NativePlacementTagger.new(model, definition)
      raise 'Không bật được công cụ đặt CAD native.' unless model.place_component(definition, false)

      @native_tagger.arm!
    rescue StandardError
      @native_tagger&.cancel!
      raise
    end

    # Defers Tag assignment until native placement has returned to Select.
    class NativePlacementTagger < Sketchup::ToolsObserver
      def initialize(model, definition)
        super()
        @model = model
        @definition = definition
        remember_context
        @active = true
        @armed = false
        @timer = nil
        @attached = @tools.add_observer(self)
        raise 'Không theo dõi được công cụ đặt CAD.' unless @attached
      end

      def arm!
        @armed = true
        DWG.log_event('paste.native_tag_armed', tool_id: @tools.active_tool_id)
      end

      def defer_placed!
        return false unless @active

        # Freeze only the instances already placed before the next Paste.
        # Later copies of this definition must not be included in this session.
        @placed_instances = context_valid? ? placement_instances : []
        return true unless @placed_instances.empty?

        cancel!
        false
      rescue StandardError => e
        cancel!
        DWG.log_event('paste.native_tag_error', error: "#{e.class}: #{e.message}")
        false
      end

      def onActiveToolChanged(_tools, _name, _tool_id)
        schedule_check
      end

      def schedule_check
        return unless @active && @armed
        return if @timer

        # Notifications are read-only. Wait for the native callback to return.
        @timer = UI.start_timer(0.0, false) do
          @timer = nil
          finish_if_idle
        end
      rescue StandardError => e
        cancel!
        DWG.log_event('paste.native_tag_error', error: "#{e.class}: #{e.message}")
      end

      def cancel!
        @active = false
        DWG.pending_native_taggers.delete(self)
        UI.stop_timer(@timer) if @timer
        @timer = nil
        @tools.remove_observer(self) if @attached
        @attached = false
      rescue StandardError => e
        DWG.log_event('paste.native_tag_cleanup_error', error: "#{e.class}: #{e.message}")
      end

      def finish_if_idle
        return unless @active
        # Native import may pump timers while it owns an operation and Select
        # is still active. The Paste ensure block requeues pending checks.
        return if DWG.importing?

        return cancel! unless context_valid?
        # Do not start an operation during placement, Orbit, Move or another
        # editing tool. If the user immediately presses M, wait until Select.
        return unless @tools.active_tool.nil? && [0, 21_022].include?(@tools.active_tool_id)

        finish_instances(placement_instances)
      rescue StandardError => e
        cancel!
        DWG.log_event('paste.native_tag_error', error: "#{e.class}: #{e.message}")
        UI.messagebox("CAD đã đặt nhưng chưa gán được Tag MH_DWG: #{e.message}")
      end

      private

      def remember_context
        @entities = @model.active_entities
        @active_path = @model.active_path&.dup
        @existing_instances = @definition.instances.to_a.dup
        @tools = @model.tools
      end

      def finish_instances(instances)
        cancel! # One-shot; detach before making any model changes.
        if instances.empty?
          DWG.log_event('paste.native_tag_cancelled', reason: 'no_placed_instance')
          return
        end

        assign_placed_tags(instances)
      end

      def assign_placed_tags(instances)
        operation_open = false
        # Keep this separate from native placement's Undo. A delayed transparent
        # operation could otherwise merge into an unrelated user action.
        raise 'Không mở được operation gán Tag CAD.' unless @model.start_operation('Tag CAD MH DWG', true)

        operation_open = true
        instances.each { |instance| DWG.assign_tag(instance, @model) }
        @model.commit_operation
        operation_open = false
        DWG.log_event('paste.native_tag_assigned', tag: TAG_NAME, instances: instances.map do |instance|
          DWG.entity_log(instance)
        end)
      rescue StandardError
        @model.abort_operation if operation_open
        raise
      end

      def context_valid?
        @model.valid? && Sketchup.active_model == @model && @definition.valid? &&
          @model.active_path == @active_path && @model.active_entities == @entities
      end

      def placement_instances
        instances = @placed_instances || @definition.instances.to_a.reject do |instance|
          @existing_instances.include?(instance)
        end
        instances.select { |instance| instance.valid? && instance.parent == @entities.parent }
      end
    end
  end
end

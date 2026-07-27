# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

module CustomPlugins
  module DuplicateObject
    PLUGIN_NAME = 'Duplicate Obj'.freeze unless const_defined?(:PLUGIN_NAME, false)
    DYNAMIC_DICTIONARY = 'dynamic_attributes'.freeze unless const_defined?(:DYNAMIC_DICTIONARY, false)
    DYNAMIC_LENGTH_KEYS = {
      x: 'lenx',
      y: 'leny',
      z: 'lenz'
    }.freeze unless const_defined?(:DYNAMIC_LENGTH_KEYS, false)
    SCALE_EPSILON = 0.001 unless const_defined?(:SCALE_EPSILON, false)

    unless const_defined?(:EXTENSION, false)
      EXTENSION = SketchupExtension.new(PLUGIN_NAME, 'DuplicateObject x')
      EXTENSION.creator = 'MH'
      EXTENSION.description = 'Duplicate group/component theo 6 huong, make unique va giu properties.'
      EXTENSION.version = '1.1.0'
      EXTENSION.copyright = '2026 MH'
    end

    AXES = {
      x_pos: { label: 'X+', vector: [1, 0, 0], axis: :x, text: 'Duplicate +X', icon: 'duplicate_x_pos.svg' },
      x_neg: { label: 'X-', vector: [-1, 0, 0], axis: :x, text: 'Duplicate -X', icon: 'duplicate_x_neg.svg' },
      y_pos: { label: 'Y+', vector: [0, 1, 0], axis: :y, text: 'Duplicate +Y', icon: 'duplicate_y_pos.svg' },
      y_neg: { label: 'Y-', vector: [0, -1, 0], axis: :y, text: 'Duplicate -Y', icon: 'duplicate_y_neg.svg' },
      z_pos: { label: 'Z+', vector: [0, 0, 1], axis: :z, text: 'Duplicate +Z', icon: 'duplicate_z_pos.svg' },
      z_neg: { label: 'Z-', vector: [0, 0, -1], axis: :z, text: 'Duplicate -Z', icon: 'duplicate_z_neg.svg' }
    }.freeze unless const_defined?(:AXES, false)

    class << self
      def duplicate_selected_objects
        duplicate_along(:x_pos)
      end

      def duplicate_along(axis_key)
        axis = AXES[axis_key]
        unless axis
          UI.messagebox('Huong duplicate khong hop le.')
          return
        end

        model = Sketchup.active_model
        selection = model.selection
        originals = selection.to_a.select { |entity| duplicatable?(entity) }

        if originals.empty?
          UI.messagebox('Vui long chon it nhat mot group hoac component.')
          return
        end

        copies = []
        skipped = []

        model.start_operation("#{PLUGIN_NAME} #{axis[:label]}", true)

        begin
          originals.each do |entity|
            distance = offset_distance(entity, axis[:axis])
            if distance <= 0.0
              skipped << display_name(entity)
              next
            end

            copy = copy_entity(entity)
            next unless copy && copy.valid?

            copy = unlock_temporarily(copy) do
              copy = make_unique(copy)
              preserve_visible_name(entity, copy)
              move_copy(copy, axis[:vector], distance)
              restore_definition_properties(entity, copy)
              restore_instance_properties(entity, copy)
              preserve_dynamic_component_size(copy)
              copy
            end

            copies << copy
          rescue StandardError => e
            skipped << "#{display_name(entity)} (#{e.message})"
            puts "[#{PLUGIN_NAME}] Loi duplicate #{entity}: #{e.message}"
            puts e.backtrace.first
          end

          selection.clear
          selection.add(copies) unless copies.empty?
          model.commit_operation
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("Khong duplicate duoc: #{e.message}")
          raise e
        end

        report_result(copies, skipped)
      end

      def duplicatable?(entity)
        entity.valid? && (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
      end

      def copy_entity(entity)
        entity.copy
      end

      def make_unique(entity)
        return entity unless entity.respond_to?(:make_unique)

        unique = entity.make_unique
        unique && unique.respond_to?(:valid?) ? unique : entity
      end

      def move_copy(entity, direction, distance)
        vector = Geom::Vector3d.new(
          direction[0] * distance,
          direction[1] * distance,
          direction[2] * distance
        )
        entity.transform!(Geom::Transformation.translation(vector))
      end

      def offset_distance(entity, axis)
        span = measured_axis_span(entity, axis)
        span ? span.to_f : 0.0
      end

      def measured_axis_span(entity, axis)
        bounds = measured_bounds(entity)
        return nil unless bounds && !bounds.empty?

        min = axis_value(bounds.min, axis)
        max = axis_value(bounds.max, axis)
        max - min
      end

      # Same measuring pattern used in MH_shared/MH_Thongke:
      # local definition bounds -> transformed 8 corners -> explicit x/y/z minmax.
      def measured_bounds(entity)
        local = local_bounds_for(entity)
        return transformed_bounds(local, entity.transformation) if local && !local.empty? && entity.respond_to?(:transformation)
        return entity.bounds if entity.respond_to?(:bounds)

        nil
      rescue StandardError
        entity.bounds rescue nil
      end

      def local_bounds_for(entity)
        if entity.is_a?(Sketchup::ComponentInstance) && entity.respond_to?(:definition)
          entity.definition.bounds
        elsif entity.is_a?(Sketchup::Group)
          entity.respond_to?(:local_bounds) ? entity.local_bounds : entity.definition.bounds
        elsif entity.respond_to?(:bounds)
          entity.bounds
        end
      rescue StandardError
        nil
      end

      def transformed_bounds(bounds, transformation)
        measured = Geom::BoundingBox.new
        8.times { |index| measured.add(bounds.corner(index).transform(transformation)) }
        measured
      end

      def axis_value(point, axis)
        case axis
        when :x then point.x.to_f
        when :y then point.y.to_f
        when :z then point.z.to_f
        else 0.0
        end
      end

      def restore_instance_properties(source, target)
        restore_property(source, target, :name, :name=)
        restore_property(source, target, :material, :material=)
        restore_property(source, target, :layer, :layer=)
        restore_property(source, target, :casts_shadows?, :casts_shadows=)
        restore_property(source, target, :receives_shadows?, :receives_shadows=)
        restore_attributes(source, target)
        preserve_visible_name(source, target)
        restore_property(source, target, :hidden?, :hidden=)
        restore_property(source, target, :locked?, :locked=)
      end

      def restore_definition_properties(source, target)
        return unless source.respond_to?(:definition) && target.respond_to?(:definition)

        restore_attributes_between(source.definition, target.definition)
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] Khong restore definition attributes: #{e.message}"
      end

      def restore_property(source, target, reader, writer)
        return unless source.respond_to?(reader) && target.respond_to?(writer)

        target.public_send(writer, source.public_send(reader))
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] Khong restore #{reader}: #{e.message}"
      end

      def restore_attributes(source, target)
        restore_attributes_between(source, target)
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] Khong restore attributes: #{e.message}"
      end

      def restore_attributes_between(source, target)
        dictionaries = source.attribute_dictionaries
        return unless dictionaries && target.respond_to?(:set_attribute)

        dictionaries.each do |dictionary|
          dictionary.each_pair do |key, value|
            target.set_attribute(dictionary.name, key, value)
          end
        end
      end

      # A Dynamic Component can be resized with SketchUp's Scale tool. In that
      # case the visible size is stored in the instance transformation while
      # lenx/leny/lenz still contain the old DC values. A later DC redraw then
      # evaluates those old values and snaps the duplicate back to its base
      # size. Store the actual size on the duplicate so a redraw is stable.
      #
      # Only the duplicate is changed. Nested dynamic components are included
      # because redraw_with_undo on a parent redraws its complete tree.
      def preserve_dynamic_component_size(entity)
        sync_dynamic_component_tree(entity, {})
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] Khong dong bo kich thuoc Dynamic Component: #{e.message}"
      end

      def sync_dynamic_component_tree(entity, visited)
        return unless entity && entity.valid?

        object_key = entity.object_id
        return if visited[object_key]

        visited[object_key] = true
        sync_dynamic_component_dimensions(entity) if dynamic_component?(entity)

        child_entities(entity).each do |child|
          sync_dynamic_component_tree(child, visited) if duplicatable?(child)
        end
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] Khong dong bo DC con: #{e.message}"
      end

      def dynamic_component?(entity)
        return false unless entity.is_a?(Sketchup::ComponentInstance)
        return false unless entity.valid?

        entity.attribute_dictionary(DYNAMIC_DICTIONARY, false) ||
          entity.definition.attribute_dictionary(DYNAMIC_DICTIONARY, false)
      rescue StandardError
        false
      end

      def child_entities(entity)
        if entity.is_a?(Sketchup::Group)
          entity.entities.to_a
        elsif entity.is_a?(Sketchup::ComponentInstance)
          entity.definition.entities.to_a
        else
          []
        end
      rescue StandardError
        []
      end

      def sync_dynamic_component_dimensions(entity)
        dimensions = dynamic_component_dimensions(entity)
        return unless dimensions

        DYNAMIC_LENGTH_KEYS.each do |axis, key|
          next unless dynamic_length_attribute_present?(entity, key)

          actual = dimensions[axis]
          current = dynamic_attribute_value(entity, key)
          next unless dynamic_dimension_needs_sync?(entity, axis, actual, current)

          write_dynamic_length(entity, key, actual)
        end
      end

      def dynamic_component_dimensions(entity)
        bounds = entity.definition.bounds
        return nil if bounds.empty?

        sx, sy, sz = transformation_scale(entity.transformation)
        {
          x: bounds.width.to_f * sx,
          y: bounds.depth.to_f * sy,
          z: bounds.height.to_f * sz
        }
      rescue StandardError
        nil
      end

      def transformation_scale(transformation)
        matrix = transformation.to_a
        [
          Math.sqrt(matrix[0]**2 + matrix[1]**2 + matrix[2]**2),
          Math.sqrt(matrix[4]**2 + matrix[5]**2 + matrix[6]**2),
          Math.sqrt(matrix[8]**2 + matrix[9]**2 + matrix[10]**2)
        ]
      end

      def dynamic_length_attribute_present?(entity, key)
        attribute_present?(entity, key) || attribute_present?(entity.definition, key)
      rescue StandardError
        false
      end

      def attribute_present?(entity, key)
        dictionary = entity.attribute_dictionary(DYNAMIC_DICTIONARY, false)
        return false unless dictionary

        !dictionary[key].nil? ||
          !dictionary["_#{key}_formula"].nil? ||
          !dictionary["_#{key}_nominal"].nil?
      rescue StandardError
        false
      end

      def dynamic_attribute_value(entity, key)
        value = entity.get_attribute(DYNAMIC_DICTIONARY, key)
        return value unless value.nil?

        entity.definition.get_attribute(DYNAMIC_DICTIONARY, key)
      rescue StandardError
        nil
      end

      def dynamic_dimension_needs_sync?(entity, axis, actual, current)
        return false unless actual && actual > 0.0

        scales = transformation_scale(entity.transformation)
        scale_index = { x: 0, y: 1, z: 2 }[axis]
        return true if scale_index && (scales[scale_index] - 1.0).abs > SCALE_EPSILON

        numeric = numeric_dynamic_value(current)
        numeric.nil? || (numeric - actual).abs > [actual.abs * 0.001, 0.01].max
      end

      def numeric_dynamic_value(value)
        return value.to_f if value.is_a?(Numeric)

        text = value.to_s.strip
        return nil unless text.match?(/\A-?\d+(?:\.\d+)?\z/)

        text.to_f
      end

      def write_dynamic_length(entity, key, value)
        definition_present = attribute_present?(entity.definition, key)
        entity.make_unique if definition_present && entity.respond_to?(:make_unique)
        definition = entity.definition

        write_dynamic_length_value(entity, key, value)
        write_dynamic_length_value(definition, key, value) if definition_present
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] Khong luu #{key} cho DC: #{e.message}"
      end

      def write_dynamic_length_value(target, key, value)
        target.set_attribute(DYNAMIC_DICTIONARY, key, value)
        target.set_attribute(DYNAMIC_DICTIONARY, "_#{key}_nominal", value)
        target.set_attribute(DYNAMIC_DICTIONARY, "_#{key}_error", value.to_s)

        dictionary = target.attribute_dictionary(DYNAMIC_DICTIONARY, false)
        dictionary.delete_key("_#{key}_formula") if dictionary && dictionary.respond_to?(:delete_key)
      end

      def preserve_visible_name(source, target)
        name = source.respond_to?(:name) ? source.name.to_s : ''
        name = source.definition.name.to_s if name.empty? && source.respond_to?(:definition)
        return if name.empty? || !target.respond_to?(:name=)

        target.name = name
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] Khong restore ten object: #{e.message}"
      end

      def unlock_temporarily(entity)
        was_locked = entity.respond_to?(:locked?) && entity.locked?
        entity.locked = false if was_locked && entity.respond_to?(:locked=)
        yield
      ensure
        entity.locked = true if was_locked && entity.valid? && entity.respond_to?(:locked=)
      end

      def display_name(entity)
        return entity.name unless entity.name.to_s.empty?
        return entity.definition.name if entity.respond_to?(:definition)

        entity.to_s
      end

      def report_result(copies, skipped)
        if copies.empty?
          UI.messagebox('Khong tao duoc ban duplicate nao.')
        elsif !skipped.empty?
          UI.messagebox("Da duplicate #{copies.length} object. Bo qua #{skipped.length} object co kich thuoc bang 0 hoac bi loi.")
        end
      end

      def create_command(axis_key, axis)
        UI::Command.new(axis[:text]) { duplicate_along(axis_key) }.tap do |cmd|
          icon = icon_path(axis[:icon])
          if icon
            cmd.small_icon = icon
            cmd.large_icon = icon
          end

          cmd.tooltip = "#{axis[:text]} (make unique)"
          cmd.status_bar_text = 'Duplicate group/component, make unique, giu ten mau tag attributes, va offset theo truc da chon.'
          cmd.menu_text = axis[:text]
          apply_extension_to_command(cmd)
        end
      end

      def apply_extension_to_command(cmd)
        return unless cmd.respond_to?(:extension=)
        return unless const_defined?(:EXTENSION, false)

        cmd.extension = EXTENSION
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] Khong gan extension cho command: #{e.message}"
      end

      def icon_path(filename)
        path = File.join(__dir__, 'duplicate_obj_icons', filename.to_s)
        File.exist?(path) ? path : nil
      end

      def setup_ui
        return if ui_loaded?

        @toolbar = UI::Toolbar.new(PLUGIN_NAME)
        @commands = []
        menu = UI.menu('Plugins')
        @submenu = menu.add_submenu(PLUGIN_NAME)

        AXES.each do |axis_key, axis|
          cmd = create_command(axis_key, axis)
          @commands << cmd
          @toolbar.add_item(cmd)
          @submenu.add_item(cmd)
        end

        @toolbar.show
        register_curic_pie_menu
        @ui_loaded = true
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] Loi tao toolbar/menu: #{e.message}"
        puts e.backtrace.first
      end

      def ui_loaded?
        @ui_loaded && @commands.is_a?(Array) && !@commands.empty?
      end

      def register_curic_pie_menu
        return unless defined?(::CURIC::PieMenu::NativeSketchup)
        return if @commands.nil? || @commands.empty?

        native = ::CURIC::PieMenu::NativeSketchup
        curic_commands = native.instance_variable_get(:@commands)
        if curic_commands.is_a?(Array)
          @commands.each do |cmd|
            next if curic_commands.any? { |item| item.respond_to?(:menu_text) && item.menu_text == cmd.menu_text }

            curic_commands << cmd
          end
          native.instance_variable_set(:@commands, curic_commands)
        end

        curic_toolbars = native.instance_variable_get(:@toolbars)
        if curic_toolbars.is_a?(Hash)
          curic_toolbars[PLUGIN_NAME] = @commands
          native.instance_variable_set(:@toolbars, curic_toolbars)
        elsif curic_toolbars.is_a?(Array)
          curic_toolbars << [PLUGIN_NAME, @commands] unless curic_toolbars.any? { |item| item.is_a?(Array) && item.first == PLUGIN_NAME }
          native.instance_variable_set(:@toolbars, curic_toolbars)
        end
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] Khong dang ky Curic Pie Menu: #{e.message}"
      end
    end

    setup_ui unless file_loaded?(__FILE__)
    file_loaded(__FILE__) unless file_loaded?(__FILE__)
  end

  module DuplicateOffset
    def self.duplicate_and_offset
      DuplicateObject.duplicate_along(:z_pos)
    end
  end

  module DuplicateYOffset
    def self.duplicate_and_offset_y
      DuplicateObject.duplicate_along(:y_neg)
    end
  end
end

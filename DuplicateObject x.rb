# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

module CustomPlugins
  module DuplicateObject
    PLUGIN_NAME = 'Duplicate Obj'.freeze unless const_defined?(:PLUGIN_NAME, false)

    unless const_defined?(:EXTENSION, false)
      EXTENSION = SketchupExtension.new(PLUGIN_NAME, 'DuplicateObject x')
      EXTENSION.creator = 'MH'
      EXTENSION.description = 'Duplicate group/component theo 6 huong bang copy va move native SketchUp.'
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
            if entity.respond_to?(:locked?) && entity.locked?
              skipped << "#{display_name(entity)} (locked)"
              next
            end

            distance = offset_distance(entity, axis[:axis])
            if distance <= 0.0
              skipped << display_name(entity)
              next
            end

            copy = copy_entity(entity)
            next unless copy && copy.valid?

            # Move the copied instance without changing its definition or axes.
            move_copy(copy, axis[:vector], distance)

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
        # ComponentInstance#copy is NOT a SketchUp Ruby API method. Dynamic
        # Components adds a helper with that name which drops instance data.
        # Create an instance of the same definition and preserve its data here.
        if entity.is_a?(Sketchup::Group)
          copy = entity.copy
        else
          parent = entity.parent
          entities = parent.is_a?(Sketchup::Entities) ? parent : parent.entities
          copy = entities.add_instance(entity.definition, entity.transformation)
        end
        preserve_instance_properties(entity, copy)
        dictionaries = entity.attribute_dictionaries
        dictionaries.each do |dictionary|
          dictionary.each_pair do |key, value|
            copy.set_attribute(dictionary.name, key, value)
          end
        end if dictionaries
        copy
      rescue StandardError
        copy.erase! if copy && copy.valid?
        raise
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

      def preserve_instance_properties(source, target)
        preserve_property(source, target, :material, :material=)
        preserve_property(source, target, :layer, :layer=)
        preserve_property(source, target, :casts_shadows?, :casts_shadows=)
        preserve_property(source, target, :receives_shadows?, :receives_shadows=)
        preserve_property(source, target, :name, :name=)
        preserve_property(source, target, :hidden?, :hidden=)
      end

      def preserve_property(source, target, reader, writer)
        return unless source.respond_to?(reader) && target.respond_to?(writer)

        value = source.public_send(reader)
        target.public_send(writer, value) unless target.public_send(reader) == value
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] Khong giu #{reader}: #{e.message}"
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

          cmd.tooltip = "#{axis[:text]} (Copy + Move)"
          cmd.status_bar_text = 'Duplicate group/component bang Copy + Move native SketchUp theo truc da chon.'
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

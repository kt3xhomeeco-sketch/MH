# frozen_string_literal: true

require 'sketchup'
require 'json'

module MH
  # CAD clipboard import and placement for SketchUp.
  module DWG
    TAG_NAME = 'MH_DWG'

    # Reload cancels the previous objects before redefining their classes.
    @placement_tool&.cancel_pending!
    @placement_tool = nil
    @native_tagger&.cancel!
    @native_tagger = nil
    (@pending_native_taggers || []).dup.each(&:cancel!)
    @pending_native_taggers = []
    @native_rotation&.cancel!
    @native_rotation = nil

    # Old class methods must not shadow helpers moved into modules on hot reload.
    def self.load_tool_helpers(owner, *helpers)
      moved = helpers.flat_map { |helper| helper.instance_methods(false) + helper.private_instance_methods(false) }
      local = owner.instance_methods(false) + owner.private_instance_methods(false)
      moved.each { |name| owner.send(:remove_method, name) if local.include?(name) }
      helpers.each { |helper| owner.include(helper) }
    end

    %w[logging clipboard geometry native_placement custom_state custom_preview custom_input
       custom_commit custom_placement native_rotation_support native_rotation import_pipeline].each do |name|
      load File.join(__dir__.dup.force_encoding('UTF-8'), "#{name}.rb")
    end

    unless file_loaded?(__FILE__)
      UI.menu('Plugins').add_item('Paste CAD From Clipboard') { paste_from_clipboard }
      file_loaded(__FILE__)
    end
  end
end

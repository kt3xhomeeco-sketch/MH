# frozen_string_literal: true
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
class ModuleStudioLinkVisibilityTest < Minitest::Test
  def test_active_lifecycle_hides_dim_geometry_and_overlay_extents_without_discarding_links
    script=<<~'RUBY'
      module Geom
        class BoundingBox;end
      end
      module Sketchup
        class Overlay
          def initialize(*);end
        end
        def self.active_model;@model;end
        def self.active_model=(model);@model=model;end
        def self.vcb_label=(_);end
        def self.status_text=(_);end
      end
      require ARGV[0]
      studio=MH::ModuleStudio
      model=Object.new;Sketchup.active_model=model
      tool=studio::AssemblyTool.allocate;tool.instance_variable_set(:@active,true);tool.instance_variable_set(:@record,{'id'=>'retained-link'})
      def tool.draw_geometry(*);raise 'Inactive draft drawing leaked';end
      hud=studio::AssemblyHUD.allocate;hud.instance_variable_set(:@model,model);hud.instance_variable_set(:@tool,tool);hud.instance_variable_set(:@closed,false)
      calls=[];contacts=Object.new;contacts.define_singleton_method(:draw) { |_view| calls << :draw };contacts.define_singleton_method(:extents) { calls << :extents;:contact_bounds }
      hud.instance_variable_set(:@contacts,contacts);overlay=studio::AssemblyOverlay.new(hud)
      view=Object.new;def view.invalidate;end
      raise 'Active HUD hidden' unless hud.visible?
      hud.draw(view);raise 'Active contact display missing' unless calls==[:draw]
      raise 'Active bounds missing' unless overlay.getExtents==:contact_bounds
      tool.deactivate(view)
      hud.draw(view);raise 'Inactive HUD visible' if hud.visible?
      raise 'Inactive extents leaked' unless overlay.getExtents.is_a?(Geom::BoundingBox)
      raise 'Deactivation discarded relationship' unless tool.record['id']=='retained-link'
      raise 'Inactive display drew' unless calls==[:draw,:extents]
      tool.instance_variable_set(:@active,true);raise 'Return to linking stayed hidden' unless hud.visible?
      library=Struct.new(:tool).new(Struct.new(:active).new(true));studio.instance_variable_set(:@library,library)
      raise 'Library placement did not suppress links' if hud.visible?
      studio.instance_variable_set(:@library,nil)
      hud.instance_variable_set(:@closed,true);raise 'Closed HUD visible' if hud.visible?
      hud.instance_variable_set(:@closed,false);Sketchup.active_model=Object.new;raise 'Other model HUD visible' if hud.visible?
      puts 'Link overlay lifetime passed'
    RUBY
    output,status=Open3.capture2e(RbConfig.ruby,'-e',script,File.expand_path('../assembly_tool.rb',__dir__))
    assert status.success?,output
  end
end

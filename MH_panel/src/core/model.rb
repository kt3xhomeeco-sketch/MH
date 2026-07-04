module MH::Panel
  module Model
    def self.get_trans
      Sketchup.active_model.rendering_options["ModelTransparency"]
    end
    def self.set_trans(value)
      return if value.nil?
      Sketchup.active_model.rendering_options["ModelTransparency"] = value
    end
    def self.get_edge_display
      Sketchup.active_model.rendering_options["EdgeDisplayMode"]
    end
    def self.set_edge_display(value)
      return if value.nil?
      Sketchup.active_model.rendering_options["EdgeDisplayMode"] = value
    end
    def self.get_unit_precision
      Sketchup.active_model.options["UnitsOptions"]["LengthPrecision"]
    end
    def self.active_entities
      Sketchup.active_model.active_entities
    end
  end
end

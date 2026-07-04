module MH::Panel::Isolate
  @hidden_entities = []
  def self.start
    model = Sketchup.active_model
    sel = model.selection.to_a
    @hidden_entities = []
    MH::Panel.start
    MH::Panel::Model.active_entities.each do |e|
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      next if e.hidden?
      next if sel.include?(e)
      e.hidden = true
      @hidden_entities << e
    end
    MH::Panel.commit
  end
  def self.stop
    return if @hidden_entities.empty?
    MH::Panel.start
    @hidden_entities.each do |e|
      next unless e.valid?
      e.hidden = false
    end
    MH::Panel.commit
    @hidden_entities = []
  end
end

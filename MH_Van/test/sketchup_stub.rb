# encoding: UTF-8
# Standalone API doubles. Nothing in this file is loaded by the extension.
module Geom
  class Vector3d
    attr_accessor :x, :y, :z
    def initialize(x, y, z); @x, @y, @z = x.to_f, y.to_f, z.to_f; end
    def length; Math.sqrt(x*x + y*y + z*z); end
    def +(v); self.class.new(x+v.x, y+v.y, z+v.z); end
    def *(v); Vector3d.new(y*v.z-z*v.y, z*v.x-x*v.z, x*v.y-y*v.x); end
    def normalize!; size = length; @x /= size; @y /= size; @z /= size; self; end
  end
  class Point3d < Vector3d
    def vector_to(v); Vector3d.new(v.x-x, v.y-y, v.z-z); end
    def transform(t); t.apply(self); end
  end
  class Transformation
    def initialize(columns = [[1,0,0],[0,1,0],[0,0,1]], offset = [0,0,0], weight = 1.0); @columns, @offset, @weight = columns, offset, weight; end
    def axis(index)
      vector = Vector3d.new(*@columns[index])
      vector.length.zero? ? vector : vector.normalize!
    end
    def xaxis; axis(0); end
    def yaxis; axis(1); end
    def zaxis; axis(2); end
    def to_a; @columns.flat_map { |column| column + [0.0] } + @offset + [@weight]; end
    def apply(p)
      values = [p.x,p.y,p.z]
      Point3d.new(*(0..2).map { |i| (@offset[i] + (0..2).sum { |j| @columns[j][i] * values[j] }) / @weight })
    end
    def *(other)
      other_matrix = other.to_a
      axes = [0,4,8].map do |offset|
        values = other_matrix[offset,3].map { |value| value / other_matrix[15] }
        (0..2).map { |i| (0..2).sum { |j| @columns[j][i] * values[j] } / @weight }
      end
      origin = apply(other.apply(Point3d.new(0,0,0)))
      Transformation.new(axes, [origin.x,origin.y,origin.z])
    end
    def self.rotation_x(degrees)
      angle = degrees * Math::PI / 180
      new([[1,0,0],[0,Math.cos(angle),Math.sin(angle)],[0,-Math.sin(angle),Math.cos(angle)]])
    end
    def self.scaling(x,y,z); new([[x,0,0],[0,y,0],[0,0,z]]); end
  end
end
class Numeric
  def to_mm; self * 25.4; end
end

module Sketchup
  class EntityObserver; end
  class ModelObserver; end
  class MaterialsObserver; end
  class EntitiesObserver; end
  class LayersObserver; end
  class AppObserver; end
  class << self
    attr_accessor :active_model, :status_text
    def find_support_file(*); File.expand_path('../..', __dir__); end
    def read_default(dict,key,default); (@defaults ||= {}).fetch([dict,key], default); end
    def write_default(dict,key,value); (@defaults ||= {})[[dict,key]] = value; end
    def add_observer(observer); (@observers ||= []) << observer; end
    def remove_observer(observer); (@observers ||= []).delete(observer); end
    def observers; @observers ||= []; end
    def reset_defaults; @defaults = {}; @observers = []; end
  end
  module Observable
    def add_observer(observer); (@observers ||= []) << observer unless (@observers || []).include?(observer); true; end
    def remove_observer(observer); (@observers ||= []).delete(observer); true; end
    def observers; @observers ||= []; end
  end
  class Entities < Array
    include Observable
    attr_accessor :parent
  end
  Bounds = Struct.new(:width, :height, :depth)
  Vertex = Struct.new(:position)
  Color = Struct.new(:red, :green, :blue)
  class Face
    attr_reader :vertices
    attr_accessor :material, :back_material
    def initialize(vertices); @vertices = vertices; end
    def valid?; true; end
    def normal
      origin = vertices[0].position
      (origin.vector_to(vertices[1].position) * origin.vector_to(vertices[2].position)).normalize!
    end
    def area
      $measurements[:face_area] += 1
      origin = vertices[0].position
      (1...(vertices.size-1)).sum { |i| (origin.vector_to(vertices[i].position) * origin.vector_to(vertices[i+1].position)).length * 0.5 }
    end
  end
  class Edge; end
  class Definition
    attr_reader :entities, :entityID
    def initialize(entities, id); @entities, @entityID = entities, id; entities.parent = self; end
    def bounds
      $measurements[:definition_bounds] += 1
      points = entities.grep(Face).flat_map(&:vertices).map(&:position)
      Bounds.new(*[:x,:y,:z].map { |axis| values = points.map(&axis); values.empty? ? 0.0 : values.max-values.min })
    end
  end
  class Layer
    attr_reader :persistent_id, :name
    attr_accessor :folder
    def initialize(id,name); @persistent_id, @name = id,name; @visible = true; @attributes = {}; end
    def valid?; true; end
    def visible?; @visible; end
    def visible=(value); $measurements[:tag_writes] += 1; @visible = value; end
    def get_attribute(dict,key,default=nil); @attributes.fetch([dict,key],default); end
    def set_attribute(dict,key,value); @attributes[[dict,key]] = value; end
  end
  class Layers < Array
    include Observable
    def initialize; super; self << Layer.new(100_000,'Untagged'); end
    def add(name); layer = Layer.new(100_000 + size,name); self << layer; layer; end
    def [](key); key.is_a?(Integer) ? super : find { |layer| layer.name == key }; end
    def remove(layer,*); delete(layer); end
  end
  class Group
    include Observable
    attr_reader :persistent_id, :definition, :layer
    attr_accessor :transformation, :material, :parent, :valid
    def initialize(id,definition,layer,transform=Geom::Transformation.new)
      @persistent_id, @definition, @layer, @transformation = id,definition,layer,transform
      @valid, @hidden, @attributes = true,false,{}
    end
    def valid?; @valid; end
    def entities; definition.entities; end
    def hidden?; @hidden; end
    def hidden=(value); $measurements[:hidden_writes] += 1; @hidden = value; end
    def visible?; !hidden?; end
    def layer=(value); $measurements[:layer_writes] += 1; @layer = value; end
    def get_attribute(dict,key,default=nil)
      return true if dict == 'ABF' && key == 'is-board'
      @attributes.fetch([dict,key], default)
    end
    def delete_attribute(dict,key); @attributes.delete([dict,key]); end
    def bounds
      $measurements[:entity_bounds] += 1
      points = definition.entities.grep(Face).flat_map(&:vertices).map { |v| v.position.transform(transformation) }
      Bounds.new(*[:x,:y,:z].map { |axis| values = points.map(&axis); values.max-values.min })
    end
  end
  class ComponentInstance < Group; end
  class View
    def invalidate; $measurements[:invalidates] += 1; end
    def zoom(*); $measurements[:zooms] += 1; end
  end
  class Selection < Array
    def add(items); concat(Array(items)); $measurements[:selection_adds] += 1; end
  end
  class Model
    include Observable
    attr_reader :entities, :layers, :selection, :active_view, :attributes, :log
    attr_accessor :fail_write
    def initialize
      @entities = Entities.new; @entities.parent = self
      @layers, @selection, @active_view, @materials = Layers.new,Selection.new,View.new,Entities.new
      @attributes, @log = {},[]
    end
    def materials; @materials; end
    def active_entities; @entities; end
    def find_entity_by_persistent_id(id)
      $measurements[:pid_lookups] += 1
      (@entities + @layers).find { |entity| entity.persistent_id == id }
    end
    def get_attribute(dict,key,default=nil)
      $measurements[:state_reads] += 1
      @attributes.fetch([dict,key], default)
    end
    def set_attribute(dict,key,value)
      raise 'simulated attribute write failure' if fail_write
      $measurements[:state_writes] += 1
      @log << :write
      @attributes[[dict,key]] = value
    end
    def attribute_dictionary(dict,*)
      dictionary = Object.new
      attributes = @attributes
      dictionary.define_singleton_method(:delete_key) { |key| attributes.delete([dict,key]) }
      dictionary
    end
    def start_operation(_name, disable_ui)
      @log << [:start,disable_ui]
      @snapshot = [@attributes.dup, @entities.map { |e| [e,e.layer,e.hidden?] }, @layers.dup, @layers.map { |layer| [layer,layer.visible?] }]
    end
    def commit_operation; @log << :commit; true; end
    def abort_operation; @log << :abort; restore_snapshot; true; end
    def restore_snapshot
      @attributes = @snapshot[0].dup
      @snapshot[1].each { |entity,layer,hidden| entity.layer=layer; entity.hidden=hidden }
      @layers.replace(@snapshot[2]); @snapshot[3].each { |layer,visible| layer.visible=visible }
    end
  end
end

module UI
  class HtmlDialog
    STYLE_DIALOG = 0
    attr_reader :callbacks, :scripts
    def initialize(**)
      @callbacks, @scripts, @visible = {},[],false
    end
    def set_html(html); @html = html; end
    def add_action_callback(name,&block); @callbacks[name] = block; end
    def set_on_closed(&block); @closed = block; end
    def show; @visible = true; end
    def visible?; @visible; end
    def bring_to_front; end
    def execute_script(script); @scripts << script; end
    def close; @visible = false; @closed.call if @closed; end
  end
  class Command
    attr_accessor :tooltip, :status_bar_text
    def initialize(*); end
  end
  class << self
    attr_accessor :timers, :errors
    def menu(*); self; end
    def add_item(*); end
    def start_timer(seconds,repeat,&block); @timers ||= {}; id = (@next_id ||= 0) + 1; @next_id=id; @timers[id]=[seconds,repeat,block]; id; end
    def stop_timer(id); (@timers ||= {}).delete(id); end
    def messagebox(message); (@errors ||= []) << message; end
  end
end
$measurements = Hash.new(0)

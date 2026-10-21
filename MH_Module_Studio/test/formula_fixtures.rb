# encoding: UTF-8
require_relative 'fixtures'

module FormulaFixtures
  extend self
  Core = MH::ModuleStudio::Core
  Frames = MH::ModuleStudio::Frames

  def snapshot
    sample = StudioFixtures.cabinet(18, width: 600, height: 500, depth: 200)
    sample['parts'].reject! { |part| part['key'] == 'shelf' }
    bounds = {
      'left' => [[0, 0, 0], [18, 200, 500]], 'right' => [[582, 0, 0], [600, 200, 500]],
      'top' => [[18, 0, 482], [582, 174, 500]], 'bottom' => [[18, 0, 0], [582, 174, 18]],
      'back' => [[18, 174, 18], [582, 182, 482]]
    }
    sample['parts'].each { |part| part['bounds'] = bounds.fetch(part['key']) }
    sample['envelope'] = Core.union(sample['parts'])
    sample['dc_inputs'] = { '_name' => 'Tủ ATT', '_lengthunits' => 'CENTIMETERS' }
    { 't' => [18, 'Độ dày tấm'], 'b' => [8, 'Độ dày hậu'], 's' => [18, 'Hậu lùi'] }.each do |key, (value, label)|
      sample['dc_inputs'].merge!(key => value / 25.4, "_#{key}_units" => 'MILLIMETERS', "_#{key}_access" => 'TEXTBOX', "_#{key}_formlabel" => label)
    end
    # Stale DC dimensions after stretching: actual envelope must win.
    sample['dc_inputs'].merge!('lenx' => 1000 / 25.4, 'leny' => 200 / 25.4, 'lenz' => 445 / 25.4,
                               '_cut_formula' => 'if(b>0,b+s,0)', '_cut_units' => 'CENTIMETERS', '_cut_formulaunits' => 'CENTIMETERS')
    formulas = {
      'left' => { 'lenx' => 'parent!t' },
      'right' => { 'x' => 'parent!lenx-parent!t', 'lenx' => 'parent!t' },
      'top' => { 'x' => 'parent!t', 'z' => 'parent!lenz-parent!t', 'lenx' => 'parent!lenx-2*parent!t', 'leny' => 'parent!leny-parent!cut', 'lenz' => 'parent!t' },
      'bottom' => { 'x' => 'parent!t', 'lenx' => 'parent!lenx-2*parent!t', 'leny' => 'parent!leny-parent!cut', 'lenz' => 'parent!t' },
      'back' => { 'lenx' => 'parent!w', 'leny' => 'parent!b', 'lenz' => 'parent!h' }
    }
    nodes = []
    sample['parts'].each do |part|
      key = part['key']
      origin = part['bounds'][0].dup
      path = [key]
      if key == 'back'
        path = ['carrier', key]
        origin = [0, 0, 0]
      end
      transform = Frames::IDENTITY.map(&:to_f)
      origin.each_with_index { |value, axis| transform[12 + axis] = value / 25.4 }
      attrs = { '_lengthunits' => 'CENTIMETERS' }
      formulas[key].each { |attribute, formula| attrs["_#{attribute}_formula"] = formula }
      nodes << { 'id' => key, 'name' => part['name'], 'path' => path, 'part_key' => key, 'transform' => transform,
                 'local_bounds' => [[0, 0, 0], Core.dimensions(part['bounds']).map { |value| value / 25.4 }], 'attributes' => attrs }
    end
    transform = Frames::IDENTITY.map(&:to_f)
    [18, 174, 18].each_with_index { |value, axis| transform[12 + axis] = value / 25.4 }
    nodes << { 'id' => 'carrier', 'name' => 'Group hậu', 'path' => ['carrier'], 'part_key' => nil, 'transform' => transform,
               'local_bounds' => [[0, 0, 0], [564, 8, 464].map { |value| value / 25.4 }],
               'attributes' => { '_lengthunits' => 'CENTIMETERS', '_x_formula' => 'parent!t', '_y_formula' => 'parent!leny-parent!s-parent!b',
                                 '_z_formula' => 'parent!t', '_w_units' => 'CENTIMETERS', '_w_formula' => 'parent!lenx-2*parent!t',
                                 '_b_units' => 'CENTIMETERS', '_b_formula' => 'parent!b',
                                 '_h_units' => 'CENTIMETERS', '_h_formula' => 'parent!lenz-2*parent!t' } }
    sample['dc_graph'] = { 'nodes' => nodes, 'root_frame' => Frames::IDENTITY }
    sample
  end
end

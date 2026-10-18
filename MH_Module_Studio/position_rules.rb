# encoding: UTF-8
require_relative 'symbolic_program'

module MH
  module ModuleStudio
    module PositionRules
      extend self
      EDGE_NAMES = [%w[trái phải], %w[trước sau], %w[dưới trên]].freeze
      DIMENSION_NAMES = ['Rộng', 'Sâu', 'Cao'].freeze
      MODULE = '@module'.freeze

      def install!(bundle)
        return bundle if bundle['position_rules_version'] == 2
        parts = bundle['parts'].select { |part| part['visible'] != false }
        engine = bundle['formula_engine']
        program = engine && engine['attribute_program']
        symbolic = program ? DCFormulas::SymbolicProgram.new(program).symbolic_positions : {}
        bundle['constraints'].reject! { |entry| entry['type'] == 'position' }
        parts.each do |part|
          3.times do |axis|
            2.times do |side|
              target = RuleSystem.face(part['key'], axis, side)
              ref = reference_for(bundle, part, axis, side)
              expression = difference(symbolic, bundle, target, ref, side == 0 ? 1 : -1)
              entry = description(part, target, ref, 'distance', expression, !!program,
                                  "Mặt #{EDGE_NAMES[axis][side]} → Mép #{EDGE_NAMES[axis][ref['side']]}")
              entry['formula_indices'] = formula_indices(bundle, program, [target, ref], axis)
              bundle['constraints'] << entry
            end
            low = RuleSystem.face(part['key'], axis, 0)
            high = RuleSystem.face(part['key'], axis, 1)
            expression = difference(symbolic, bundle, high, low, 1)
            entry = description(part, high, low, 'dimension', expression, !!program, DIMENSION_NAMES[axis])
            entry['formula_indices'] = formula_indices(bundle, program, [high, low], axis)
            bundle['constraints'] << entry
          end
        end
        bundle['position_rules_version'] = 2
        bundle
      end

      def description(part, target, ref, measure, expression, att, label)
        RuleSystem.constraint('position', att ? 'dc_attributes' : 'geometry', id: "position:#{part['key']}:#{measure}:#{target['axis']}:#{target['side']}",
                              face: target, other: ref, measure: measure, expression: expression,
                              label: label, part_name: part['name'], drive: false, translated: att)
      end

      def formula_indices(bundle, program, refs, axis)
        return [] unless program
        nodes = program.dig('dc_graph', 'nodes')
        by_id = nodes.to_h { |node| [node.key?('parent_id') ? node['id'] : node['path'].join(' / '), node] }
        ids = ['']
        refs.each do |ref|
          node = nodes.find { |item| item['part_key'] == ref['part'] }
          seen = []
          while node
            id = node.key?('parent_id') ? node['id'] : node['path'].join(' / ')
            break if seen.include?(id)
            seen << id; ids << id
            parent = node.key?('parent_id') ? node['parent_id'] : node['path'][0...-1].join(' / ')
            node = by_id[parent]
          end
        end
        bundle.fetch('attribute_formulas', []).each_index.select do |index|
          entry = bundle['attribute_formulas'][index]
          id = entry['node_id'] || entry['path']
          ids.include?(id) && ([%w[x y z][axis], %w[lenx leny lenz][axis]].include?(entry['attribute']) || (id == '' && !DCFormulas::LENGTHS.include?(entry['attribute'])))
        end.first(18)
      end

      def reference_for(bundle, part, axis, side)
        bounds = part['base_bounds']
        candidates = bundle['parts'].select do |other|
          next false if other['key'] == part['key'] || other['visible'] == false
          box = other['base_bounds']
          contains = box[0][axis] <= bounds[0][axis] + Core::TOLERANCE && box[1][axis] >= bounds[1][axis] - Core::TOLERANCE
          overlaps = ((0..2).to_a - [axis]).map { |a| [box[1][a], bounds[1][a]].min - [box[0][a], bounds[0][a]].max }
          contains && overlaps.all? { |value| value >= -Core::TOLERANCE } && overlaps.any? { |value| value > 0.5 }
        end
        chosen = candidates.min_by { |other| [other['thickness_axis'] == part['thickness_axis'] ? 1 : 0, -Core.dimensions(other['base_bounds'])[axis], other['base_bounds'][0]] }
        RuleSystem.face(chosen ? chosen['key'] : MODULE, axis, side)
      end

      def coordinate(symbolic, bundle, ref)
        if ref['part'] == MODULE
          origin = AffinePosition.constant(bundle['envelope'][0][ref['axis']])
          return ref['side'] == 0 ? origin : AffinePosition.add(origin, AffinePosition.variable("@#{%w[lenx leny lenz][ref['axis']]}"))
        end
        symbolic.dig(ref['part'], ref['side'], ref['axis'])
      end

      def difference(symbolic, bundle, target, ref, sign)
        a = coordinate(symbolic, bundle, target)
        b = coordinate(symbolic, bundle, ref)
        return nil unless a && b
        constant, coefficients = AffinePosition.scale(AffinePosition.add(a, b, -1), sign)
        { 'constant' => constant.abs < 1.0e-8 ? 0.0 : constant.round(8),
          'coefficients' => coefficients.transform_values { |value| value.round(8) }.reject { |_key, value| value.zero? } }
      end
    end
  end
end

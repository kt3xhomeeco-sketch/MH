# encoding: UTF-8

module MH
  module ModuleStudio
    # Sparse linear equations for panel planes; free planes retain candidate positions.
    module PlaneSolver
      extend self

      def solve(equations, baseline)
        pivots = {}
        equations.each do |terms, value, label|
          row = terms.dup
          rhs = Core.number(value)
          loop do
            row.delete_if { |_key, coefficient| coefficient.abs < 1.0e-9 }
            if row.empty?
              raise Core::Error, "Quy tắc xung đột: #{label}." if rhs.abs > 1.0e-6
              break
            end
            pivot = row.keys.min
            unless pivots.key?(pivot)
              divisor = row[pivot]
              pivots[pivot] = [row.transform_values { |coefficient| coefficient / divisor }, rhs / divisor]
              break
            end
            factor = row[pivot]
            prior, result = pivots[pivot]
            prior.each { |key, coefficient| row[key] = row.fetch(key, 0.0) - factor * coefficient }
            rhs -= factor * result
          end
        end
        values = baseline.dup
        pivots.keys.sort.reverse_each do |pivot|
          row, rhs = pivots[pivot]
          values[pivot] = rhs - row.sum { |key, coefficient| key == pivot ? 0.0 : coefficient * values.fetch(key) }
        end
        equations.each do |terms, rhs, label|
          error = terms.sum { |key, coefficient| coefficient * values.fetch(key) } - rhs
          raise Core::Error, "Quy tắc xung đột: #{label}." if error.abs > 1.0e-6
        end
        values
      end
    end
  end
end

# encoding: UTF-8
# Diagnostic artifact (NOT production code). Read-only measurement of the live SketchUp process.
# Q: real CPU cost of each pipeline stage, with no GVL-throttle in play.
module MH
  module ModuleStudio
    module DiagStages
      extend self

      def clock; Process.clock_gettime(Process::CLOCK_MONOTONIC); end
      def r3(x); (x.to_f * 1000).round / 1000.0; end

      def series(n, &blk)
        Array.new(n) do
          t = clock
          blk.call
          (clock - t) * 1000.0
        end
      end

      def stat(a)
        s = a.sort
        { 'n' => a.length, 'min_ms' => r3(s.first), 'median_ms' => r3(s[s.length / 2]),
          'mean_ms' => r3(a.sum / a.length), 'max_ms' => r3(s.last) }
      end

      def safe
        yield
      rescue StandardError => e
        { 'error' => "#{e.class}: #{e.message}" }
      end

      def fixture_data
        s = MH::ModuleStudio
        f = s::NativeOptionsProfile.instance_variable_get(:@fixture)
        raise 'no fixture' unless f && f[:inst] && f[:inst].valid?
        r = f[:inst]
        dict = s::Reader::DICT
        [r, r.get_attribute(dict, 'rule_json'), r.get_attribute(dict, 'parameter_values_json')]
      end

      def stages(reps = 3)
        s = MH::ModuleStudio
        _r, raw, vraw = fixture_data
        parsed = JSON.parse(raw)
        info = {
          'rule_json_bytes' => raw.bytesize, 'values_json_bytes' => vraw ? vraw.bytesize : 0,
          'kind' => parsed['kind'], 'parts' => (parsed['parts'] || []).length,
          'parameters' => (parsed['parameters'] || []).length,
          'constraints' => (parsed['constraints'] || []).length,
          'parametric_variables' => (parsed['parametric_variables'] || []).length,
          'part_formulas' => (parsed['part_formulas'] || {}).length,
          'formula_engine' => !parsed['formula_engine'].nil?
        }
        out = { 'info' => info }
        out['json_parse'] = safe { stat(series(reps) { JSON.parse(raw) }) }
        out['json_generate'] = safe { stat(series(reps) { JSON.generate(parsed) }) }
        out['marshal_roundtrip'] = safe { stat(series(reps) { Marshal.load(Marshal.dump(parsed)) }) }
        out['sha256_of_marshal'] = safe { stat(series(reps) { Digest::SHA256.hexdigest(Marshal.dump(parsed)) }) }
        out['core_rule_bang'] = safe { stat(series(reps) { s::Core.rule!(s::Core.copy_data(parsed)) }) }

        rule = s::ThicknessSymbols.normalize(s::DCCustomAttributes.upgrade(s::Core.rule!(s::Core.copy_data(parsed))))
        vals = vraw ? JSON.parse(vraw) : {}
        rule['parameters'].each { |p| p['value'] = vals.fetch(p['key'], p['value']) if p['editable'] }
        rule.fetch('parametric_variables', []).each do |x|
          x['value'] = vals.fetch(x['binding'], x['value']) if x['binding'] && x['formula'].to_s.empty?
        end
        out['rule_generate_bytes'] = safe { JSON.generate(rule).bytesize }
        var_rows = s::Parametric.variables(s::Core.copy_data(rule))
        ui_rows = s::OptionsParameters.rows(rule, vals)
        out['var_rows'] = var_rows.length
        out['ui_rows'] = ui_rows.length
        out['ui_row_t1'] = ui_rows.find { |x| x['symbol'] == 'T1' }
        out['parametric_variables'] = safe { stat(series(reps) { s::Parametric.variables(s::Core.copy_data(rule)) }) }
        out['edit_variables'] = safe { stat(series(reps) { s::Parametric.edit_variables(s::Core.copy_data(rule), var_rows) }) }
        edited = safe { s::Parametric.edit_variables(s::Core.copy_data(rule), var_rows) }
        out['targets'] = safe { stat(series(reps) { s::Parametric.targets(s::Core.copy_data(edited)) }) }
        out['stamp_metadata'] = safe { stat(series(reps) { s::Parametric.stamp_metadata(s::Core.copy_data(rule), vals) }) }
        out['rule_system_validate'] = safe { stat(series(reps) { s::RuleSystem.validate!(s::Core.copy_data(rule)) }) }
        out['core_copy_data_rule'] = safe { stat(series(reps) { s::Core.copy_data(rule) }) }
        out['reader_live'] = safe { stat(series(reps) { s::Reader.live(_r, label: 'QA', parameter: 20.0) }) }
        out['rule_system_plan'] = safe do
          snap, bindings = s::Reader.live(_r, label: 'Bản thử', parameter: 20.0)
          cur = s::UpdateWork.snapshot(snap)
          targets = s::Parametric.targets(edited)
          {
            'bindings' => (bindings.is_a?(Hash) ? bindings.length : bindings.class.to_s),
            'targets_keys' => (targets.is_a?(Hash) ? targets.keys.first(6) : targets.class.to_s),
            'core_plan' => stat(series(reps) { s::Core.plan(s::Core.copy_data(rule), s::Core.copy_data(cur), targets) })
          }
        end
        out['reader_live_pair'] = safe { stat(series(reps) { s::Reader.live(_r, label: 'Bản thử', parameter: 20.0) }) }
        out
      rescue StandardError => e
        { 'error' => "#{e.class}: #{e.message}", 'backtrace' => e.backtrace.first(6) }
      end
    end
  end
end

# encoding: UTF-8
# Diagnostic artifact (NOT production code).
# A/B of UpdateWork.compute's GVL-yield strategy on REAL work, replicated exactly:
#   TracePoint(:call,:b_call) -> every 64 events, if >=3ms since deadline -> yield -> reset deadline.
# Modes: none (no yield), sleep1ms (current production), sleep0, pass (Thread.pass).
module MH
  module ModuleStudio
    module DiagThrottle
      extend self

      def clock; Process.clock_gettime(Process::CLOCK_MONOTONIC); end
      def r3(x); (x.to_f * 1000).round / 1000.0; end

      def fixture_work
        s = MH::ModuleStudio
        f = s::NativeOptionsProfile.instance_variable_get(:@fixture)
        raise 'no fixture' unless f && f[:inst] && f[:inst].valid?
        r = f[:inst]
        dict = s::Reader::DICT
        raw = r.get_attribute(dict, 'rule_json')
        vraw = r.get_attribute(dict, 'parameter_values_json')
        rule = s::ThicknessSymbols.normalize(s::DCCustomAttributes.upgrade(s::Core.rule!(JSON.parse(raw))))
        vals = vraw ? JSON.parse(vraw) : {}
        rule['parameters'].each { |p| p['value'] = vals.fetch(p['key'], p['value']) if p['editable'] }
        rule.fetch('parametric_variables', []).each do |x|
          x['value'] = vals.fetch(x['binding'], x['value']) if x['binding'] && x['formula'].to_s.empty?
        end
        rows = s::Parametric.variables(rule)
        [rule, rows]
      end

      # one unit of real work (~300 ms unthrottled)
      def unit(rule, rows)
        s = MH::ModuleStudio
        s::Parametric.edit_variables(s::Core.copy_data(rule), rows)
      end

      def bench(mode, rounds: 3)
        rule, rows = fixture_work
        events = 0
        sleeps = 0
        slept = 0.0
        deadline = clock + 0.003
        tp = nil
        unless mode == :none
          tp = TracePoint.new(:call, :b_call) do
            events += 1
            next unless (events % 64).zero?
            next unless clock >= deadline
            a = clock
            case mode
            when :sleep1ms then sleep(0.001)
            when :sleep0 then sleep(0)
            when :pass then Thread.pass
            end
            slept += clock - a
            sleeps += 1
            deadline = clock + 0.003
          end
        end
        t = clock
        if tp
          tp.enable(target_thread: Thread.current) { rounds.times { unit(rule, rows) } }
        else
          rounds.times { unit(rule, rows) }
        end
        wall = clock - t
        { 'mode' => mode.to_s, 'rounds' => rounds, 'wall_ms' => r3(wall * 1000.0),
          'yields' => sleeps, 'yield_total_ms' => r3(slept * 1000.0),
          'events' => events, 'per_round_ms' => r3(wall * 1000.0 / rounds) }
      end

      def run(rounds: 3)
        rule, rows = fixture_work
        t = clock
        unit(rule, rows)
        unthrottled_one = (clock - t) * 1000.0
        out = { 'unthrottled_unit_ms' => r3(unthrottled_one), 'results' => [] }
        %i[none noop sleep1ms sleep0 pass sleep1ms].each do |mode|
          out['results'] << bench(mode, rounds: rounds)
        end
        base = out['results'].find { |x| x['mode'] == 'noop' }
        out['results'].each do |x|
          x['slowdown_vs_noop'] = base && base['wall_ms'] > 0 ? (x['wall_ms'] / base['wall_ms']).round(2) : nil
        end
        out
      rescue StandardError => e
        { 'error' => "#{e.class}: #{e.message}", 'bt' => e.backtrace.first(5) }
      end
    end
  end
end

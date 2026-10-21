# encoding: utf-8
# MH_Thongke P3 harness: benchmark/diff helpers only. Does not change active scanner.

module MH_Thongke
  module P3Harness
    module_function

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rescue
      Time.now.to_f
    end

    def elapsed_ms(start_time)
      ((now - start_time) * 1000.0).round(1)
    end

    def benchmark_session
      src = MH_Thongke.session
      s = MH_Thongke::SessionState.new
      s.group_by = src.group_by
      s.hidden_list = Array(src.hidden_list).dup
      s.unit_overrides = src.unit_overrides.is_a?(Hash) ? src.unit_overrides.dup : {}
      s.imported_excel_data = Array(src.imported_excel_data).map { |row| row.is_a?(Hash) ? row.dup : row }
      s.match_rules = src.match_rules.is_a?(Hash) ? src.match_rules.dup : src.match_rules
      s.general_rules = src.general_rules.is_a?(Hash) ? src.general_rules.dup : src.general_rules
      s.mini_accept_rules = src.mini_accept_rules.is_a?(Hash) ? src.mini_accept_rules.dup : src.mini_accept_rules
      s
    end

    def measure
      t0 = now
      value = yield
      [value, elapsed_ms(t0)]
    rescue => e
      [{ 'error' => "#{e.class}: #{e.message}" }, elapsed_ms(t0 || now)]
    end

    def row_fingerprint(row)
      keys = %i[data_key name product actual_product ten_sp trang_thai count sel_count length sel_length unit is_missing]
      keys.map { |key| [key, row[key] || row[key.to_s]] }.to_h
    rescue
      row.to_s
    end

    def rows_fingerprint(rows)
      Array(rows).map { |row| row_fingerprint(row) }
                 .sort_by { |row| row.is_a?(Hash) ? [row[:product].to_s, row[:name].to_s, row[:data_key].to_s] : row.to_s }
    end

    def snapshot_fingerprint
      snap = MH_Thongke.report_snapshot(false)
      {
        'accessories_count' => Array(snap['accessories']).length,
        'materials_count' => Array(snap['materials']).length,
        'accessories' => rows_fingerprint(snap['accessories']),
        'materials' => rows_fingerprint(snap['materials'])
      }
    end

    def diff_fingerprint(a, b)
      {
        'same_counts' => a['accessories_count'] == b['accessories_count'] && a['materials_count'] == b['materials_count'],
        'same_accessories' => a['accessories'] == b['accessories'],
        'same_materials' => a['materials'] == b['materials'],
        'accessories_count' => [a['accessories_count'], b['accessories_count']],
        'materials_count' => [a['materials_count'], b['materials_count']]
      }
    end

    def diff_pass?(diff)
      diff.is_a?(Hash) &&
        diff['same_counts'] == true &&
        diff['same_accessories'] == true &&
        diff['same_materials'] == true
    rescue
      false
    end

    def capture_runtime_state
      keys = %i[
        data_map mat_data_map prod_groups all_item_names all_item_names_set
        led_per_product current_report_items current_mat_items process_selection_cache_sig
      ]
      keys.each_with_object({}) { |key, out| out[key] = MH_Thongke.instance_variable_get(:"@#{key}") }
    rescue
      {}
    end

    def restore_runtime_state(state)
      state.each { |key, value| MH_Thongke.instance_variable_set(:"@#{key}", value) }
      true
    rescue
      false
    end

    def sync_session_to_module_for_profile(s)
      MH_Thongke.instance_variable_set(:@data_map, s.data_map)
      MH_Thongke.instance_variable_set(:@mat_data_map, s.mat_data_map)
      MH_Thongke.instance_variable_set(:@prod_groups, s.prod_groups)
      MH_Thongke.instance_variable_set(:@all_item_names, s.all_item_names)
      MH_Thongke.instance_variable_set(:@all_item_names_set, s.all_item_names_set)
      MH_Thongke.instance_variable_set(:@led_per_product, s.led_per_product)
      true
    rescue
      false
    end

    def sync_module_to_session_for_profile(s)
      s.data_map = MH_Thongke.instance_variable_get(:@data_map) if MH_Thongke.instance_variable_get(:@data_map).is_a?(Hash)
      s.mat_data_map = MH_Thongke.instance_variable_get(:@mat_data_map) if MH_Thongke.instance_variable_get(:@mat_data_map).is_a?(Hash)
      s.prod_groups = MH_Thongke.instance_variable_get(:@prod_groups) if MH_Thongke.instance_variable_get(:@prod_groups).is_a?(Hash)
      s.all_item_names = MH_Thongke.instance_variable_get(:@all_item_names) || s.all_item_names
      s.all_item_names_set = MH_Thongke.instance_variable_get(:@all_item_names_set) || s.all_item_names_set
      s.led_per_product = MH_Thongke.instance_variable_get(:@led_per_product) || s.led_per_product
      true
    rescue
      false
    end

    def product_codes_from_snapshot(limit = 160)
      snap = MH_Thongke.report_snapshot(false)
      rows = Array(snap['accessories']) + Array(snap['materials'])
      rows.map do |row|
        next nil unless row.is_a?(Hash)

        value = row[:actual_product] || row['actual_product'] ||
                row[:product] || row['product'] ||
                row[:ma_sp] || row['ma_sp']
        value.to_s.strip
      end.compact.reject(&:empty?).reject { |code| code == '--' }.uniq.first(limit.to_i)
    rescue
      []
    end

    def autofill_signature_probe(product_limit: 160, repeats: 1000)
      codes = product_codes_from_snapshot(product_limit)
      excel_rows = Array(MH_Thongke.instance_variable_get(:@imported_excel_data))
      sig_before = MH_Thongke.respond_to?(:excel_rows_signature_cached) ? MH_Thongke.excel_rows_signature_cached : nil
      version_before = MH_Thongke.instance_variable_get(:@excel_data_version) rescue nil

      _, sig_ms = measure do
        repeats.to_i.times { MH_Thongke.excel_rows_signature_cached } if MH_Thongke.respond_to?(:excel_rows_signature_cached)
        true
      end

      first_values, first_ms = measure do
        codes.map { |code| [code, MH_Thongke.import_excel_product_name_for(code, false)] }
      end
      second_values, second_ms = measure do
        codes.map { |code| [code, MH_Thongke.import_excel_product_name_for(code, false)] }
      end

      sig_after = MH_Thongke.respond_to?(:excel_rows_signature_cached) ? MH_Thongke.excel_rows_signature_cached : nil
      version_after = MH_Thongke.instance_variable_get(:@excel_data_version) rescue nil
      cache = MH_Thongke.instance_variable_get(:@excel_product_names_cache) rescue nil

      {
        'product_count' => codes.length,
        'excel_rows' => excel_rows.length,
        'signature_repeats' => repeats.to_i,
        'signature_repeats_ms' => sig_ms,
        'first_ms' => first_ms,
        'second_ms' => second_ms,
        'same_values' => first_values == second_values,
        'signature_same' => sig_before == sig_after,
        'version_before' => version_before,
        'version_after' => version_after,
        'cache_size' => cache.respond_to?(:length) ? cache.length : nil,
        'sample' => Array(first_values).first(8)
      }
    rescue => e
      {
        'error' => "#{e.class}: #{e.message}",
        'backtrace' => Array(e.backtrace).first(5)
      }
    end

    def stage_breakdown(model: Sketchup.active_model, selection: nil)
      selection ||= model.selection
      state = capture_runtime_state
      s = benchmark_session
      rows = []
      total_t0 = now

      run_stage = lambda do |name, &block|
        t0 = now
        error = nil
        begin
          sync_session_to_module_for_profile(s)
          block.call
          sync_module_to_session_for_profile(s)
        rescue => e
          error = "#{e.class}: #{e.message}"
        end
        rows << {
          'name' => name,
          'ms' => elapsed_ms(t0),
          'data_map' => s.data_map.respond_to?(:length) ? s.data_map.length : 0,
          'mat_data_map' => s.mat_data_map.respond_to?(:length) ? s.mat_data_map.length : 0,
          'prod_groups' => s.prod_groups.respond_to?(:length) ? s.prod_groups.length : 0,
          'error' => error
        }
        raise error if error
      end

      run_stage.call('scan_model') { MH_Thongke::Pipeline.stage_scan_model(s, model, selection) }
      run_stage.call('excel_match') { MH_Thongke::Pipeline.stage_excel_match(s) }
      run_stage.call('material_status') { MH_Thongke::Pipeline.stage_material_status(s) }
      run_stage.call('autofill_product_names') { MH_Thongke::Pipeline.stage_autofill_product_names(s) }
      run_stage.call('merge_and_filter') { MH_Thongke::Pipeline.stage_merge_and_filter(s) }
      run_stage.call('apply_overrides') { MH_Thongke::Pipeline.stage_apply_overrides(s) }
      run_stage.call('normalize_status') { MH_Thongke::Pipeline.stage_normalize_status(s) }
      run_stage.call('final_status_rematch') { MH_Thongke::Pipeline.stage_final_status_rematch(s) }
      run_stage.call('finalize') { MH_Thongke::Pipeline.stage_finalize(s, model) }

      {
        'ok' => true,
        'total_ms' => elapsed_ms(total_t0),
        'stages' => rows,
        'data_map' => s.data_map.length,
        'mat_data_map' => s.mat_data_map.length,
        'prod_groups' => s.prod_groups.length
      }
    rescue => e
      {
        'ok' => false,
        'total_ms' => elapsed_ms(total_t0 || now),
        'stages' => rows,
        'error' => e.to_s,
        'backtrace' => Array(e.backtrace).first(8)
      }
    ensure
      restore_runtime_state(state) if state
    end

    def run(model: Sketchup.active_model, selection: nil, include_full_pipeline: true)
      selection ||= model.selection
      result = {
        'ok' => true,
        'active_path' => Array(model.active_path).length,
        'selection_count' => selection.respond_to?(:length) ? selection.length : Array(selection).length
      }

      if defined?(MH::ModelHub)
        MH::ModelHub.invalidate!(:all)
        _, cold_record_ms = measure do
          count = 0
          MH::ModelHub.each_record(root: model.entities, types: %i[group component], depth: -1, include_hidden: false, reject_names: ['__ABF_Nesting']) { |_rec| count += 1 }
          count
        end
        record_count, warm_record_ms = measure do
          count = 0
          MH::ModelHub.each_record(root: model.entities, types: %i[group component], depth: -1, include_hidden: false, reject_names: ['__ABF_Nesting']) { |_rec| count += 1 }
          count
        end
        result['each_record'] = {
          'count' => record_count.is_a?(Integer) ? record_count : 0,
          'cold_ms' => cold_record_ms,
          'warm_ms' => warm_record_ms
        }
      end

      s1 = benchmark_session
      MH::ModelHub.invalidate!(:all) if defined?(MH::ModelHub)
      _, cold_scan_ms = measure { MH_Thongke::Pipeline.stage_scan_model(s1, model, selection) }
      s2 = benchmark_session
      _, warm_scan_ms = measure { MH_Thongke::Pipeline.stage_scan_model(s2, model, selection) }
      result['p3_safe_stage_scan_model'] = {
        'cold_ms' => cold_scan_ms,
        'warm_ms' => warm_scan_ms,
        'data_map' => s2.data_map.length,
        'mat_data_map' => s2.mat_data_map.length,
        'prod_groups' => s2.prod_groups.length
      }

      if include_full_pipeline
        MH_Thongke.process_selection_cached(true)
        before = snapshot_fingerprint
        _, full_ms = measure { MH_Thongke.process_selection_cached(true) }
        after = snapshot_fingerprint
        result['full_pipeline'] = {
          'ms' => full_ms,
          'diff' => diff_fingerprint(before, after)
        }
      end

      result
    rescue => e
      {
        'ok' => false,
        'error' => "#{e.class}: #{e.message}",
        'backtrace' => Array(e.backtrace).first(8)
      }
    end

    def profile_pipeline(include_full_pipeline: true, include_autofill_probe: true, include_stage_breakdown: true, product_limit: 160, signature_repeats: 1000)
      model = Sketchup.active_model
      result = {
        'ok' => true,
        'profile_version' => 1,
        'timestamp' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        'sketchup_version' => Sketchup.version.to_s,
        'model_title' => model.title.to_s,
        'active_path' => Array(model.active_path).length,
        'selection_count' => model.selection.length
      }

      result['autofill_probe'] = autofill_signature_probe(product_limit: product_limit, repeats: signature_repeats) if include_autofill_probe
      result['stage_breakdown'] = stage_breakdown(model: model, selection: model.selection) if include_stage_breakdown
      benchmark = run(model: model, selection: model.selection, include_full_pipeline: include_full_pipeline)
      result['benchmark'] = benchmark
      diff = benchmark.is_a?(Hash) ? benchmark.dig('full_pipeline', 'diff') : nil
      result['bom_diff_pass'] = include_full_pipeline ? diff_pass?(diff) : nil
      result
    rescue => e
      {
        'ok' => false,
        'profile_version' => 1,
        'error' => "#{e.class}: #{e.message}",
        'backtrace' => Array(e.backtrace).first(8)
      }
    end
  end

  def self.p3_harness_run(**kwargs)
    P3Harness.run(**kwargs)
  end

  def self.profile_pipeline(**kwargs)
    P3Harness.profile_pipeline(**kwargs)
  end

  def self.profile_pipeline_summary(result)
    result ||= {}
    bench = result['benchmark'] || {}
    scan = bench['p3_safe_stage_scan_model'] || {}
    full = bench['full_pipeline'] || {}
    autofill = result['autofill_probe'] || {}
    breakdown = result['stage_breakdown'] || {}
    stages = Array(breakdown['stages']).sort_by { |row| -row['ms'].to_f }.first(5)
    stage_line = if stages.empty?
                   "stage_breakdown=none"
                 else
                   "top stages: " + stages.map { |row| "#{row['name']}=#{row['ms']}ms" }.join(", ")
                 end
    [
      "MH_Thongke profile_pipeline",
      "model=#{result['model_title']}",
      "selection=#{result['selection_count']}",
      "autofill first/second=#{autofill['first_ms']}/#{autofill['second_ms']}ms sig#{autofill['signature_repeats']}=#{autofill['signature_repeats_ms']}ms",
      "breakdown_total=#{breakdown['total_ms']}ms ok=#{breakdown['ok']}",
      stage_line,
      "scan cold/warm=#{scan['cold_ms']}/#{scan['warm_ms']}ms",
      "full=#{full['ms']}ms bom_diff=#{result['bom_diff_pass']}"
    ].join("\n")
  rescue => e
    "MH_Thongke profile summary error: #{e.message}"
  end
end

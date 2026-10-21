# encoding: UTF-8
#
# MH_Registry / connectors / thongke.rb
# ---------------------------------------------------------------------------
# Connector cho MH_Thongke.
# - Sau khi MH_Registry tạo file vật liệu/SP, tự nạp output vào MH_Thongke
# - Đồng bộ đường dẫn Fill SP/import Excel để app Thống kê tiếp tục workflow
# ---------------------------------------------------------------------------

module MH
  module RegistryApp
    module Connectors
      module Thongke
        module_function

        def available?
          defined?(::MH_Thongke) &&
            (::MH_Thongke.respond_to?(:remember_import_excel_path) ||
             ::MH_Thongke.respond_to?(:reload_import_excel_from_file!) ||
             ::MH_Thongke.respond_to?(:schedule_import_excel_reload))
        end

        def load_import_excel(file_path, refresh = true)
          return { 'ok' => false, 'error' => 'MH_Thongke chua duoc load.' } unless available?

          path = file_path.to_s.strip
          return { 'ok' => false, 'error' => 'File output khong ton tai.' } if path.empty? || !File.exist?(path)

          reload_thongke_processors
          sync_fill_sp_state(path)

          if ::MH_Thongke.respond_to?(:reload_import_excel_from_file!)
            ::MH_Thongke.reload_import_excel_from_file!(path)
            refresh_views(true) if refresh
            rows = imported_rows_count
            return {
              'ok' => true,
              'path' => path,
              'rows' => rows,
              'material_rows' => material_rows_count,
              'mode' => 'reload_import_excel_from_file'
            }
          end

          if ::MH_Thongke.respond_to?(:schedule_import_excel_reload)
            ::MH_Thongke.schedule_import_excel_reload(path, 'mh_registry')
            return {
            'ok' => true,
            'path' => path,
            'rows' => imported_rows_count,
            'material_rows' => material_rows_count,
            'mode' => 'schedule_import_excel_reload'
          }
        end

          ::MH_Thongke.remember_import_excel_path(path) if ::MH_Thongke.respond_to?(:remember_import_excel_path)
          {
            'ok' => true,
            'path' => path,
            'rows' => imported_rows_count,
            'material_rows' => material_rows_count,
            'mode' => 'remember_import_excel_path'
          }
        rescue => e
          MH::RegistryApp.dbg("[Thongke Connector] load_import_excel error: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          { 'ok' => false, 'error' => e.message }
        end

        def load_import_excel_payload(rows, file_path, refresh = true, options = {})
          return { 'ok' => false, 'error' => 'MH_Thongke chua duoc load.' } unless available?

          path = file_path.to_s.strip
          json_path = option_value(options, :json_path, 'json_path').to_s
          fallback_to_xlsx = truthy?(option_value(options, :fallback_to_xlsx, 'fallback_to_xlsx'))
          source = option_value(options, :source, 'source').to_s
          source = 'mh_registry_payload' if source.empty?
          payload_rows = Array(rows)

          if path.empty? || !File.exist?(path)
            return payload_error(path, json_path, 'File output khong ton tai.')
          end
          if payload_rows.empty?
            err = payload_error(path, json_path, 'payload rows empty.')
            return fallback_to_xlsx ? fallback_import_excel(path, refresh, err) : err
          end

          reload_thongke_processors
          sync_fill_sp_state(path)

          unless ::MH_Thongke.respond_to?(:load_import_excel_rows!)
            err = payload_error(path, json_path, 'MH_Thongke.load_import_excel_rows! chua san sang.')
            return fallback_to_xlsx ? fallback_import_excel(path, refresh, err) : err
          end

          mtime = File.mtime(path).to_f rescue 0.0
          ::MH_Thongke.load_import_excel_rows!(
            payload_rows,
            source_path: path,
            source_mtime: mtime,
            source: source,
            refresh: false,
            json_path: json_path
          )
          refresh_views(true) if refresh
          {
            'ok' => true,
            'path' => path,
            'json_path' => json_path,
            'rows' => imported_rows_count,
            'material_rows' => material_rows_count,
            'mode' => 'load_import_excel_payload',
            'source' => source,
            'fallback_used' => false
          }
        rescue => e
          err = payload_error(path, json_path, e.message)
          fallback_to_xlsx ? fallback_import_excel(path, refresh, err) : err
        end

        def import_classified_payload(payload, file_path, refresh = true, options = {})
          return classified_payload_error(payload, file_path, 'MH_Thongke chua duoc load.') unless defined?(::MH_Thongke)

          reload_thongke_processors
          load_classified_import_processor

          unless ::MH_Thongke.respond_to?(:import_classified_payload!)
            return classified_payload_error(payload, file_path, 'MH_Thongke.import_classified_payload! chua san sang.')
          end

          path = file_path.to_s.strip
          mtime = path.empty? || !File.exist?(path) ? 0.0 : File.mtime(path).to_f
          source = option_value(options, :source, 'source').to_s
          source = 'mh_registry_classified_payload' if source.empty?
          result = ::MH_Thongke.import_classified_payload!(
            payload,
            source_path: path,
            source_mtime: mtime,
            source: source,
            refresh: refresh
          )
          result.is_a?(Hash) ? result : { 'ok' => true, 'mode' => 'classified_import', 'result' => result }
        rescue => e
          classified_payload_error(payload, file_path, e.message)
        end

        def current_status
          return { 'ok' => false, 'available' => false } unless available?

          status = current_import_excel_status
          status['available'] = true
          status
        rescue => e
          { 'ok' => false, 'available' => true, 'error' => e.message }
        end

        def report_snapshot(force = false)
          return { 'ok' => false, 'accessories' => [], 'materials' => [], 'import_excel' => [], 'excel_cache_sources' => [] } unless defined?(::MH_Thongke)
          return ::MH_Thongke.report_snapshot(force) if ::MH_Thongke.respond_to?(:report_snapshot)

          { 'ok' => false, 'accessories' => [], 'materials' => [], 'import_excel' => [], 'excel_cache_sources' => [] }
        rescue => e
          { 'ok' => false, 'accessories' => [], 'materials' => [], 'import_excel' => [], 'excel_cache_sources' => [], 'error' => e.message }
        end

        def bom_for_product(product_code, force = false, include_excel = true)
          return { 'ok' => false, 'product_code' => product_code.to_s, 'accessories' => [], 'materials' => [], 'import_excel' => [], 'counts' => { 'accessories' => 0, 'materials' => 0, 'import_excel' => 0 } } unless defined?(::MH_Thongke)
          return ::MH_Thongke.bom_for_product(product_code, force: force, include_excel: include_excel) if ::MH_Thongke.respond_to?(:bom_for_product)

          snapshot = report_snapshot(force)
          product = normalize_product_code(product_code)
          accessories = Array(snapshot['accessories']).select { |row| product_matches?(hash_value(row, :actual_product, 'actual_product', :product, 'product'), product) }
          materials = Array(snapshot['materials']).select { |row| product_matches?(hash_value(row, :actual_product, 'actual_product', :product, 'product'), product) }
          excel = include_excel ? import_excel_data(product) : []
          {
            'ok' => true,
            'product_code' => product,
            'accessories' => accessories,
            'materials' => materials,
            'import_excel' => excel,
            'counts' => { 'accessories' => accessories.length, 'materials' => materials.length, 'import_excel' => excel.length }
          }
        rescue => e
          MH::RegistryApp.dbg("[Thongke Connector] bom_for_product error: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          { 'ok' => false, 'product_code' => product_code.to_s, 'accessories' => [], 'materials' => [], 'import_excel' => [], 'counts' => { 'accessories' => 0, 'materials' => 0, 'import_excel' => 0 }, 'error' => e.message }
        end

        def import_excel_data(product_code = nil)
          return [] unless defined?(::MH_Thongke)
          return ::MH_Thongke.import_excel_data_snapshot(product_code) if ::MH_Thongke.respond_to?(:import_excel_data_snapshot)
          return ::MH_Thongke.mini_excel_items(product_code, false) if product_code && ::MH_Thongke.respond_to?(:mini_excel_items)

          []
        rescue => e
          MH::RegistryApp.dbg("[Thongke Connector] import_excel_data error: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          []
        end

        def import_excel_cache_sources
          return [] unless defined?(::MH_Thongke) && ::MH_Thongke.respond_to?(:import_excel_cache_sources)
          ::MH_Thongke.import_excel_cache_sources
        rescue => e
          MH::RegistryApp.dbg("[Thongke Connector] import_excel_cache_sources error: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          []
        end

        def begin_external_mutation(source = 'external')
          return false unless defined?(::MH_Thongke)
          return ::MH_Thongke.begin_external_mutation(source) if ::MH_Thongke.respond_to?(:begin_external_mutation)
          return ::MH_Thongke.pause_mini_import_refresh(source) if ::MH_Thongke.respond_to?(:pause_mini_import_refresh)

          false
        rescue => e
          MH::RegistryApp.dbg("[Thongke Connector] begin_external_mutation error: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          false
        end

        def end_external_mutation(source = 'external', refresh = true)
          return false unless defined?(::MH_Thongke)
          return ::MH_Thongke.end_external_mutation(source, refresh) if ::MH_Thongke.respond_to?(:end_external_mutation)
          return ::MH_Thongke.resume_mini_import_refresh(source, refresh) if ::MH_Thongke.respond_to?(:resume_mini_import_refresh)

          false
        rescue => e
          MH::RegistryApp.dbg("[Thongke Connector] end_external_mutation error: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          false
        end

        def selected_product_codes(allow_slow_scan = false)
          codes = if defined?(::MH_Thongke) && ::MH_Thongke.respond_to?(:selected_product_codes)
                    ::MH_Thongke.selected_product_codes(allow_slow_scan)
                  elsif defined?(MH::ProductContext)
                    MH::ProductContext.codes_from_selection(Sketchup.active_model, allow_slow_scan: allow_slow_scan)
                  else
                    []
                  end

          Array(codes).map { |code| normalize_product_code(code) }.reject(&:empty?).uniq
        rescue => e
          MH::RegistryApp.dbg("[Thongke Connector] selected_product_codes error: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          []
        end

        def product_codes_for_entity(entity)
          return [] unless entity && entity.valid?
          codes = if defined?(::MH_Thongke) && ::MH_Thongke.respond_to?(:entity_product_codes)
                    ::MH_Thongke.entity_product_codes(entity)
                  elsif defined?(MH::ProductContext)
                    MH::ProductContext.codes_for_entity(entity)
                  else
                    text = "#{entity.respond_to?(:name) ? entity.name : ''} #{entity.respond_to?(:definition) && entity.definition ? entity.definition.name : ''}"
                    defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:scan_products) ? MH::NameGrammar.scan_products(text) : text.scan(/[A-Z]+\d+[A-Z]?(?:\.\d+)?/i)
                  end
          Array(codes).map { |code| normalize_product_code(code) }.reject(&:empty?).uniq
        rescue => e
          MH::RegistryApp.dbg("[Thongke Connector] product_codes_for_entity error: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          []
        end

        def resolve_product_for_import(instance = nil, _context = {})
          codes = []
          codes.concat(product_codes_for_entity(instance)) if instance
          codes.concat(selected_product_codes(false))
          codes.concat(selected_product_codes(true)) if codes.empty?
          code = codes.find do |value|
            if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:valid?)
              MH::ProductContext.valid?(value)
            else
              value =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?\z/i
            end
          end
          {
            'ok' => !code.to_s.empty?,
            'product_code' => code.to_s,
            'candidates' => codes.uniq
          }
        rescue => e
          { 'ok' => false, 'error' => e.message, 'product_code' => '', 'candidates' => [] }
        end

        def material_codes_for_product(product_code)
          product = normalize_product_code(product_code)
          return [] if product.empty?

          codes = []
          add_code = lambda do |value|
            split_material_codes(value).each do |code|
              if defined?(MH_Thongke) && MH_Thongke.respond_to?(:sanitize_legacy_duplicate_finish_code)
                code = MH_Thongke.sanitize_legacy_duplicate_finish_code(code)
              end
              codes << code unless code.empty? || codes.include?(code)
            end
          end

          imported_rows_for_product(product).each do |row|
            source = hash_value(row, :ma_vl_source, 'ma_vl_source', :Ma_vat_lieu, 'Ma_vat_lieu')
            source = hash_value(row, :ma_vl, 'ma_vl', :material_code, 'material_code') if source.to_s.strip.empty?
            add_code.call(source)
          end

          if codes.empty?
            current_material_rows_for_product(product).each do |row|
              add_code.call(material_base_code(hash_value(row, :name, 'name')))
            end
          end

          codes
        rescue => e
          MH::RegistryApp.dbg("[Thongke Connector] material_codes_for_product error: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          []
        end

        def material_names
          names = []
          add_name = lambda do |value|
            base_material_names(value).each do |text|
              next if text =~ /\AVBO_/i

              names << text unless text.empty? || names.include?(text)
            end
          end

          snapshot = report_snapshot(false)
          rows = snapshot.is_a?(Hash) ? snapshot['materials'] : []
          Array(rows).each do |row|
            add_name.call(hash_value(row, :name, 'name', :material_name, 'material_name'))
          end

          imported = import_excel_data
          Array(imported).each do |row|
            kind = hash_value(row, :kind, 'kind').to_s
            next unless kind.upcase == 'VL'

            add_name.call(hash_value(row, :ma_vl_source, 'ma_vl_source', :Ma_vat_lieu, 'Ma_vat_lieu'))
            add_name.call(hash_value(row, :ma_vl, 'ma_vl', :material_code, 'material_code')) if names.empty?
          end

          names
        rescue => e
          MH::RegistryApp.dbg("[Thongke Connector] material_names error: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          []
        end

        private

        def self.hash_value(row, *keys)
          keys.each do |key|
            return row[key] if row.respond_to?(:key?) && row.key?(key)
          end
          ''
        end

        def self.imported_rows_for_product(product)
          rows = import_excel_data(product)
          rows = import_excel_data if rows.empty?
          Array(rows).select do |row|
            kind = hash_value(row, :kind, 'kind').to_s
            row_product = normalize_product_code(hash_value(row, :ma_sp, 'ma_sp', :Ma_SP, 'Ma_SP'))
            kind.upcase == 'VL' && product_matches?(row_product, product)
          end
        end

        def self.current_material_rows_for_product(product)
          snapshot = report_snapshot(false)
          rows = snapshot.is_a?(Hash) ? snapshot['materials'] : []
          Array(rows).select do |row|
            row_product = hash_value(row, :actual_product, 'actual_product')
            row_product = hash_value(row, :product, 'product') if row_product.to_s.empty? || row_product.to_s == '--'
            product_matches?(normalize_product_code(row_product), product)
          end
        end

        def self.product_matches?(value, target)
          return false if value.to_s.empty? || target.to_s.empty? || value.to_s == '--'
          if defined?(::MH_Thongke) && ::MH_Thongke.respond_to?(:mini_product_code_match?)
            ::MH_Thongke.mini_product_code_match?(value, target, (::MH_Thongke.mini_group_mode rescue 'product'))
          elsif defined?(MH::ProductContext)
            MH::ProductContext.match?(value, target, 'product')
          else
            value.to_s.split('.').first == target.to_s.split('.').first
          end
        end

        def self.split_material_codes(value)
          MH::MaterialCode.split(value)
        end

        def self.material_base_code(material_name)
          MH::MaterialCode.without_thickness(material_name)
        end

        def self.base_material_names(material_name)
          split_material_codes(material_name).map do |part|
            material_code_without_thickness(part)
          end.reject(&:empty?)
        end

        def self.material_code_without_thickness(value)
          MH::MaterialCode.without_thickness(value)
        end

        def self.normalize_product_code(code)
          if defined?(::MH_Thongke) && ::MH_Thongke.respond_to?(:product_code_exact)
            ::MH_Thongke.product_code_exact(code).to_s
          elsif defined?(MH::ProductContext)
            MH::ProductContext.exact(code).to_s
          else
            code.to_s.strip.upcase
          end
        rescue
          code.to_s.strip.upcase
        end

        def self.reload_thongke_processors
          return unless defined?(::MH_Thongke)

          root = if defined?(::MH_Thongke::ROOT_DIR)
            ::MH_Thongke::ROOT_DIR
          elsif defined?(::MH_Thongke::DIR)
            ::MH_Thongke::DIR
          end
          return if root.to_s.empty?

          [
            File.join(root, 'engine', 'processors', 'matching_rules_processor.rb'),
            File.join(root, 'core', 'excel_import.rb'),
            File.join(root, 'ui', 'mini_import', 'logic', 'bom_tables_rendering.rb'),
            File.join(root, 'ui', 'material_hud_render.rb'),
            File.join(root, 'ui', 'material_hud_data.rb')
          ].each do |path|
            load(path) if File.exist?(path)
          end
        rescue => e
          MH::RegistryApp.dbg("[Thongke Connector] reload processors error: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
        end

        def self.load_classified_import_processor
          return unless defined?(::MH_Thongke)
          root = if defined?(::MH_Thongke::ROOT_DIR)
            ::MH_Thongke::ROOT_DIR
          elsif defined?(::MH_Thongke::DIR)
            ::MH_Thongke::DIR
          end
          path = File.join(root.to_s, 'core', 'classified_import.rb')
          load(path) if !path.empty? && File.exist?(path)
        rescue => e
          MH::RegistryApp.dbg("[Thongke Connector] load classified_import error: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
        end

        def self.sync_fill_sp_state(path)
          if ::MH_Thongke.respond_to?(:accept_registry_import_excel_path)
            ::MH_Thongke.accept_registry_import_excel_path(path)
          else
            ::MH_Thongke.fill_sp_sync_import_excel_path(path, auto_reload: false) if ::MH_Thongke.respond_to?(:fill_sp_sync_import_excel_path)
            ::MH_Thongke.remember_import_excel_path(path) if ::MH_Thongke.respond_to?(:remember_import_excel_path)
            ::MH_Thongke.save_preferences if ::MH_Thongke.respond_to?(:save_preferences)
          end
        end

        def self.refresh_views(process_model = true)
          if process_model
            if ::MH_Thongke.respond_to?(:process_selection_cached)
              ::MH_Thongke.process_selection_cached(true)
            elsif ::MH_Thongke.respond_to?(:process_selection)
              ::MH_Thongke.process_selection
            end
          end

          if ::MH_Thongke.respond_to?(:refresh_import_related_views)
            ::MH_Thongke.refresh_import_related_views(false, true, true)
          elsif ::MH_Thongke.respond_to?(:import_excel_refresh_dependent_views)
            ::MH_Thongke.import_excel_refresh_dependent_views(false)
          end

          main_visible = ::MH_Thongke.respond_to?(:main_dialog_visible?) ? ::MH_Thongke.main_dialog_visible? : false
          if ::MH_Thongke.respond_to?(:update_html) && main_visible
            ::MH_Thongke.update_html(true)
          end
        end

        def self.option_value(options, *keys)
          return nil unless options.respond_to?(:[])
          keys.each do |key|
            value = options[key] rescue nil
            return value unless value.nil?
          end
          nil
        end

        def self.truthy?(value)
          value == true || value.to_s.strip.downcase == 'true' || value.to_s.strip == '1'
        end

        def self.payload_error(path, json_path, message)
          {
            'ok' => false,
            'mode' => 'payload_error',
            'path' => path.to_s,
            'json_path' => json_path.to_s,
            'fallback_used' => false,
            'error' => message.to_s
          }
        end

        def self.fallback_import_excel(path, refresh, original_error)
          result = load_import_excel(path, refresh)
          result = {} unless result.is_a?(Hash)
          result['fallback_used'] = true
          result['fallback_mode'] = result['mode']
          result['payload_error'] = original_error
          result
        end

        def self.classified_payload_error(payload, path, message)
          schema_version = if payload.is_a?(Hash)
            (payload['schema_version'] || payload[:schema_version]).to_i
          else
            0
          end
          source = payload.is_a?(Hash) ? (payload['source'] || payload[:source]).to_s : ''
          {
            'ok' => false,
            'mode' => 'classified_import_error',
            'schema_version' => schema_version,
            'source' => source,
            'path' => path.to_s,
            'error' => message.to_s
          }
        end

        def self.imported_rows_count
          rows = import_excel_data
          rows.respond_to?(:length) ? rows.length : 0
        end

        def self.material_rows_count
          snapshot = report_snapshot(false)
          rows = snapshot.is_a?(Hash) ? snapshot['materials'] : []
          rows.respond_to?(:length) ? rows.length : 0
        end

        def self.current_import_excel_status
          if ::MH_Thongke.respond_to?(:import_excel_current_status)
            status = ::MH_Thongke.import_excel_current_status
            return status if status.is_a?(Hash)
          end
          path = ''
          path = ::MH_Thongke.import_excel_loaded_path if ::MH_Thongke.respond_to?(:import_excel_loaded_path)
          path = ::MH_Thongke.import_excel_path if path.to_s.empty? && ::MH_Thongke.respond_to?(:import_excel_path)
          {
            'ok' => true,
            'path' => path.to_s,
            'rows' => imported_rows_count,
            'material_rows' => material_rows_count
          }
        rescue
          { 'ok' => false, 'path' => '', 'rows' => 0, 'material_rows' => 0 }
        end
      end
    end

    Connector.register('thongke', Connectors::Thongke)
  end
end

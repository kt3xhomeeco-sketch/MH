# encoding: UTF-8
#
# MH_Registry / connectors / dc_import / material_code.rb
# ---------------------------------------------------------------------------
# Material-code helpers for DCImportPipeline.
# ---------------------------------------------------------------------------

module MH
  module RegistryApp
    module Connectors
      module DCImportPipeline
        module_function

        # Bỏ độ dày + đuôi .1M/.2M, trả mảng token đã chuẩn hóa (upcase).
        # Nguồn chuẩn là MH::MaterialCode; Material Assign legacy chỉ là fallback.
        def material_family_parts(material_code)
          if defined?(MH::MaterialCode) && MH::MaterialCode.respond_to?(:without_thickness)
            normalized_shared = MH::MaterialCode.without_thickness(material_code)
            normalized_shared = normalized_shared.sub(/(?:\.1M(?:-BCT)?|\.2M(?:-BCT)?)\z/i, '')
            return normalized_shared.split('.').reject(&:empty?)
          end
          if defined?(MH::MaterialApp::MaterialCodeBuilder) &&
             MH::MaterialApp::MaterialCodeBuilder.respond_to?(:material_family_parts)
            return Array(MH::MaterialApp::MaterialCodeBuilder.material_family_parts(material_code))
          end
          normalized = normalize_logical_material_code(material_code).upcase
          normalized = normalized.sub(/(?:\.1M(?:-BCT)?|\.2M(?:-BCT)?)\z/i, '')
          parts = normalized.split('.').reject(&:empty?)
          parts.delete_at(1) if parts.length > 1 && parts[1] =~ /\A\d+(?:\.\d+)?\z/
          parts
        end

        def normalize_logical_material_code(value)
          if defined?(MH::MaterialCode) && MH::MaterialCode.respond_to?(:display)
            return MH::MaterialCode.display(value)
          end
          if defined?(MH::MaterialApp::MaterialCodeBuilder) &&
             MH::MaterialApp::MaterialCodeBuilder.respond_to?(:normalize_logical_material_code)
            return MH::MaterialApp::MaterialCodeBuilder.normalize_logical_material_code(value)
          end

          code = value.to_s.strip.gsub(/\s+/, '')
          return '' if code.empty?
          # HUD/DC phải giữ đúng mã nguồn. Cha/con chỉ tồn tại khi Excel đã
          # khai rõ bằng dấu chấm, không suy diễn MS256SH thành MS.MS256SH.
          code.split('.').map(&:strip).reject(&:empty?).join('.')
        rescue
          value.to_s.strip
        end

        # Legacy shim: luồng mới không còn dc_type_groups.
        # type_key giữ lại như alias của material_code_key để các call cũ không lỗi.
        def type_key(material_code)
          material_code_key(material_code)
        end

        # Key chinh cho bang do day: giu ma vat lieu thuc, chi bo token do day.
        # Vd HDFCA.17.AC.VERSOI -> HDFCA.AC.VERSOI.
        def material_code_key(material_code)
          raw = material_code.to_s
          @material_code_key_cache ||= {}
          return @material_code_key_cache[raw] if @material_code_key_cache.key?(raw)

          key = material_family_parts(raw).join('.').to_s.strip.upcase
          @material_code_key_cache[raw] = key
          key
        end

        def number_or_nil(value)
          text = value.to_s.strip.tr(',', '.')
          return nil if text.empty?
          f = text.to_f
          (f == 0.0 && text !~ /\d/) ? nil : f
        end

        def map_thickness(actual_thickness)
          if defined?(MH::MaterialApp::MaterialCodeBuilder) &&
             MH::MaterialApp::MaterialCodeBuilder.respond_to?(:map_thickness)
            return MH::MaterialApp::MaterialCodeBuilder.map_thickness(
              actual_thickness.to_f,
              fallback_to_actual: true
            ).to_s.gsub(/\.0$/, '')
          end

          value = actual_thickness.to_f
          mapping = (@thickness_map || DEFAULT_THICKNESS_MAP).find do |row|
            value >= row['min'].to_f && value <= row['max'].to_f
          end
          return mapping['value'].to_s.gsub(/\.0$/, '') if mapping
          value.round(1).to_s.gsub(/\.0$/, '')
        end

        def material_name_from_code(material_code, actual_thickness)
          code = material_code.to_s.strip
          return '' if code.empty?
          cache_key = [code.upcase, actual_thickness.to_f.round(4)]
          @material_name_from_code_cache ||= {}
          cached = @material_name_from_code_cache[cache_key]
          return cached if cached

          connector = material_assign_connector rescue nil
          if connector && connector.respond_to?(:material_name_for_code)
            name = connector.material_name_for_code(code, actual_thickness.to_f)
            unless name.to_s.empty?
              @material_name_from_code_cache[cache_key] = name.to_s
              return name.to_s
            end
          end

          if defined?(MH::MaterialApp::MaterialCodeBuilder) &&
             MH::MaterialApp::MaterialCodeBuilder.respond_to?(:material_name_from_code)
            name = MH::MaterialApp::MaterialCodeBuilder.material_name_from_code(
              code,
              actual_thickness.to_f,
              fallback_to_actual: true
            )
            unless name.to_s.empty?
              @material_name_from_code_cache[cache_key] = name.to_s
              return name.to_s
            end
          end

          if code =~ /^MH_/i
            result = code.sub(/^MH_/i, '')
            @material_name_from_code_cache[cache_key] = result
            return result
          end

          thickness_code = map_thickness(actual_thickness)
          parts = code.split('.').map(&:strip).reject(&:empty?)
          result = if parts.length >= 2
                     ([parts[0], thickness_code] + parts[1..-1]).join('.')
                   else
                     "#{code}.#{thickness_code}"
                   end
          @material_name_from_code_cache[cache_key] = result
          result
        end
      end
    end
  end
end

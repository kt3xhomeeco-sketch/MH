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
        # MH::MaterialCode là nguồn chuẩn duy nhất cho mọi MH_* app.
        def material_family_parts(material_code)
          MH::MaterialCode.family_parts(material_code)
        end

        def normalize_logical_material_code(value)
          MH::MaterialCode.display(value)
        end

        # Chi chap nhan ma vat lieu co y nghia.  Du lieu thong ke cu co the
        # dua ma mau (vi du #FFFFFF) vao truong Ma_vat_lieu khi SP chua co
        # vat lieu.  Ma mau la placeholder giao dien, khong phai vat lieu va
        # tuyet doi khong duoc sinh profile do day/HUD.
        def meaningful_material_code?(value)
          code = normalize_logical_material_code(value).to_s.strip
          return false if code.empty?
          return false if code =~ /\A#(?:[0-9A-F]{3}|[0-9A-F]{6}|[0-9A-F]{8})\z/i

          !%w[- -- N/A NA NONE NULL].include?(code.upcase)
        rescue
          false
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
          MH::MaterialCode.map_thickness(
            actual_thickness,
            mappings: @thickness_map,
            fallback_to_actual: true
          ).to_s
        end

        def material_name_from_code(material_code, actual_thickness)
          code = material_code.to_s.strip
          return '' if code.empty?
          cache_key = [code.upcase, actual_thickness.to_f.round(4)]
          @material_name_from_code_cache ||= {}
          cached = @material_name_from_code_cache[cache_key]
          return cached if cached

          result = MH::MaterialCode.material_name(
            code,
            actual_thickness,
            mappings: @thickness_map,
            fallback_to_actual: true
          )
          @material_name_from_code_cache[cache_key] = result
          result
        end
      end
    end
  end
end

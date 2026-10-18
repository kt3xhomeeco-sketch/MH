# encoding: UTF-8
require 'digest'
require_relative 'domain'

module MH
  module ModuleStudio
    module DCFormulas
      # Verified read-only nominal-dimension implementations from the MH library.
      # Random names alone never establish a reference. See feature 016 evidence.
      NOMINAL_FUNCTIONS = {
        'mh_parent_lenx'=>'lenx','mh_parent_leny'=>'leny','mh_parent_lenz'=>'lenz',
        'a389gx49sce6zxae' => 'lenz', 'aane20kv9i5qc67a' => 'lenx', 'bhk8x7o_xuqe2qu0' => 'lenx',
        'cpzeynwg0fll36ms' => 'lenx', 'f9nddlbypg6pau5l' => 'lenx', 'f_pkd9225hweeqn4' => 'lenz',
        'fn11405a6v9_24bt' => 'leny', 'gt3uje8yrls616vd' => 'lenz', 'ho03p_ekzw0y3j77' => 'lenz',
        'j0az_0ieiqf3x64l' => 'leny', 'l0w2a6245627erct' => 'lenx', 'l19xx8ii8dkawgyx' => 'lenx',
        'ljonko56gjwbtrfk' => 'leny', 'mb8s7epjwm95mszv' => 'lenz', 'ppb7o81tvsxocd1c' => 'leny',
        'rbplbrg23zeh1hxn' => 'lenz', 'rpkgtxsx_toea3k3' => 'lenz', 'tudrxkaoptfnld64' => 'lenx',
        'u3syz_eh8d15__6c' => 'leny', 'u6uyt8hmxrpabemg' => 'lenz', 'v4yafzmvqs08ixhv' => 'leny',
        'wdfz2525ta4vhdgl' => 'leny', 'xekrusqrof_v11yt' => 'leny', 'xov36ufic7gasy8i' => 'leny',
        'yo3oe7ej_1zgk34f' => 'leny', 'ysxgyr7hbnxhx5jz' => 'lenz', 'zq3496d7cc786v6g' => 'leny',
        # Shared by the left/right upper corner cabinets; complete reader
        # definitions verified in the right cabinet, feature 024 native audit.
        'b_fkbkvg2v1mubt9' => 'lenx', 'c742hm2gr9l0zgfy' => 'lenx', 'k2dk9fg10mutkx4c' => 'lenx',
        'kovptcuak38rxy81' => 'lenx', 'p4v4g5jdmr_0l5fz' => 'lenz', 'qm9nbgskm_0_m814' => 'lenz',
        'w55q5k_c3b0338le' => 'lenz', 'wy0463aq8mgdkgns' => 'lenz'
      }.freeze
      NOMINAL_SIGNATURE = 'e00f7372eeda57e2bd20070950b72779e3f644618659ceb6e8c5c1634e0334c9'.freeze
      # Complete generated reader template, recognized as data without eval.
      NOMINAL_SOURCE = <<~'SOURCE'.split.join(' ').freeze
        protected
        define_method(:__FUNCTION__) do |val|
          return if !ABF::StoreData.instance.check_dc '__PRODUCT__'
          dict = @source_entity.parent.attribute_dictionaries['dynamic_attributes']
          ret = dict['___LENGTH___nominal']
          unit = dict['_lengthunits'] || 'CENTIMETERS'
          return (ret.to_f * 2.54) if (unit == 'CENTIMETERS')
          return ret.to_f if (unit == 'INCHES')
          return ret
        end
      SOURCE
      NOMINAL_SOURCE_PATTERN = Regexp.new('\\G\\s*' + Regexp.escape(NOMINAL_SOURCE)
        .sub('__FUNCTION__', '(?<name>[a-z_][a-z_0-9]{0,159})')
        .sub('__PRODUCT__', '[a-zA-Z0-9_-]{1,160}')
        .sub('__LENGTH__', '(?<attribute>len[xyz])')).freeze
      # Some older files include unused readers with no bound attribute. Their
      # complete harmless template may coexist with valid nominal readers, but
      # these names are NEVER added to the supported function map.
      UNBOUND_SOURCE = <<~'SOURCE'.split.join(' ').freeze
        protected
        define_method(:__FUNCTION__) do |val|
          return if !ABF::StoreData.instance.check_dc '__PRODUCT__'
          dict = @source_entity.parent.attribute_dictionaries['dynamic_attributes']
          ret = dict['']
          unit = dict['__formulaunits']
          # p '<' + unit.to_s + '>'
          return (ret.to_f * 2.54) if (unit == 'CENTIMETERS')
          return ret.to_f if (unit == 'INCHES' || unit == 'FLOAT')
          return ret
        end
      SOURCE
      UNBOUND_SOURCE_PATTERN = Regexp.new('\\G\\s*' + Regexp.escape(UNBOUND_SOURCE)
        .sub('__FUNCTION__', '(?<name>[a-z_][a-z_0-9]{0,159})')
        .sub('__PRODUCT__', '[a-zA-Z0-9_-]{1,160}')).freeze
      def self.function_aliases(snapshot)
        saved = snapshot.fetch('function_aliases', {})
        unless saved.is_a?(Hash) && saved.length <= 2500 && saved.all? do |name, entry|
          name.is_a?(String) && name.match?(/\A[a-z_][a-z_0-9]*\z/) && entry.is_a?(Hash) &&
            entry['kind'] == 'parent_nominal' && %w[lenx leny lenz].include?(entry['attribute']) && entry['signature'] == NOMINAL_SIGNATURE
        end
          raise Core::Error, 'Bảng dịch hàm ATT không hợp lệ.'
        end
        NOMINAL_FUNCTIONS.merge(saved.transform_values { |entry| entry['attribute'] }).transform_values(&:dup)
      end

      def self.verified_nominal_reference(sequence)
        return nil unless sequence.is_a?(Array) && sequence[0] == 'YARVInstructionSequence/SimpleDataFormat' && sequence[9].to_s == 'block' && sequence[13].is_a?(Array)
        body = JSON.parse(JSON.generate(sequence[13].select { |entry| entry.is_a?(Array) }))
        keys = body.select { |entry| entry[0] == 'opt_aref_with' }.map { |entry| entry[1] }
        return nil unless keys.length == 3 && keys[0] == 'dynamic_attributes' && keys[2] == '_lengthunits' && %w[_lenx_nominal _leny_nominal _lenz_nominal].include?(keys[1])
        return nil unless body.dig(3, 0) == 'putstring'
        body[3][1] = 'DC_KEY'
        body.each { |entry| entry[1] = '_LENGTH_nominal' if entry[0] == 'opt_aref_with' && entry[1] == keys[1] }
        return nil unless Digest::SHA256.hexdigest(JSON.generate(body)) == NOMINAL_SIGNATURE
        { 'kind' => 'parent_nominal', 'attribute' => keys[1][1, 4], 'signature' => NOMINAL_SIGNATURE }
      end

      def self.source_nominal_aliases(source)
        raise Core::Error, 'Nội dung hàm DC quá lớn hoặc không hợp lệ.' unless source.is_a?(String) && source.bytesize.between?(1, 1024 * 1024)
        text = source.split.join(' ')
        position = 0
        aliases = {}
        while position < text.length
          match = NOMINAL_SOURCE_PATTERN.match(text, position)
          unless match
            unbound = UNBOUND_SOURCE_PATTERN.match(text, position)
            if unbound
              position = unbound.end(0)
              next
            end
          end
          raise Core::Error, 'Định nghĩa hàm DC chưa thuộc mẫu đọc kích thước cha đã xác minh.' unless match
          entry = { 'kind' => 'parent_nominal', 'attribute' => match[:attribute], 'signature' => NOMINAL_SIGNATURE }
          name = match[:name]
          raise Core::Error, 'Hàm DC trùng tên nhưng khác định nghĩa.' if aliases.key?(name) && aliases[name] != entry
          aliases[name] = entry
          raise Core::Error, 'Quá nhiều hàm DC.' if aliases.length > 2500
          position = match.end(0)
        end
        raise Core::Error, 'DC không có định nghĩa hàm dùng được.' if aliases.empty?
        aliases
      end

    end
  end
end

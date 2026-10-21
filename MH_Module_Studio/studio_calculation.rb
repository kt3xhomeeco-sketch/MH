# encoding: UTF-8

module MH
  module ModuleStudio
    module StudioCalculation
      extend self

      def prepare(source)
        source=Core.copy_data(source);source['scalar_formula_units_version']=1;source['custom_attributes_version']=1
        ConstructionFrame.enable(DCOptions.scalar_lists(DCCustomInputs.enable(AxisRebase.enable(source))))
      end

      def build_system(snapshots, exposed_parameter_keys: nil)
        snapshots=snapshots.map { |source| prepare(source) }
        snapshot = snapshots.last
        raise Core::Error, 'Đọc module trước khi nhận diện quy tắc.' unless snapshot
        engine = nil
        failure = nil
        if Core.attribute_inventory(snapshot)['count'].positive? || !Core.dc_controls(snapshot).empty?
          begin
            engine = Core.learn_module(snapshots)
          rescue Core::Error => error
            failure = error.message
          end
        end
        begin
          bundle = RuleSystem.build(snapshot, engine)
        rescue Core::Error=>error
          raise Core::Error,"ATT chưa dịch được: #{failure} #{error.message}" if failure
          raise
        end
        bundle['module_name'] = Parametric.module_title(snapshot)
        bundle['module_name_source'] = 'source'
        if failure
          inventory = Core.attribute_inventory(snapshot)
          bundle['attribute_formulas'] = inventory['formulas']
          inventory['formulas'].each do |formula|
            bundle['constraints'] << RuleSystem.constraint('formula', 'dc_attributes', label: "#{formula['path']} · #{formula['attribute']}", formula: formula['formula'], translated: false, drive: false)
          end
          bundle['warnings'] << "ATT chưa dịch được: #{failure} Đang dùng đề xuất hình học; không thực thi ATT."
        end
        previous_exposed = exposed_parameter_keys
        if previous_exposed && !(previous_exposed & bundle['parameters'].map { |p| p['key'] }).empty?
          Core.set_exposed_parameters!(bundle, previous_exposed & bundle['parameters'].map { |p| p['key'] })
        end
        ThicknessSymbols.normalize(RuleSystem.validate!(bundle))
      end

    end
  end
end

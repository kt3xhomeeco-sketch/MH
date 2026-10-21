# encoding: UTF-8

module MH
  # One location for every reader/writer of the existing material workbook.
  module MaterialLibrary
    DEFAULT_DIRECTORY = 'D:/Cong viec/config/nhap_xuatvan'.freeze
    FILENAME = 'material_code_library.xlsx'.freeze

    # Registry and RegistryApp inherit this one implementation. No copied
    # accessor or frozen path is allowed to survive a plugin hot reload.
    module Accessors
      def material_code_library_path
        MH::MaterialLibrary.path
      end
    end

    module_function

    def directory
      ENV.fetch('MH_NHAP_XUATVAN_LIBRARY', DEFAULT_DIRECTORY)
    end

    def path
      File.join(directory, FILENAME)
    end

    def attach(target)
      singleton = target.singleton_class
      if singleton.instance_methods(false).include?(:material_code_library_path)
        singleton.send(:remove_method, :material_code_library_path)
      end
      own_methods = target.instance_methods(false) + target.private_instance_methods(false)
      target.send(:remove_method, :material_code_library_path) if own_methods.include?(:material_code_library_path)
      target.send(:remove_const, :MATERIAL_CODE_LIBRARY_PATH) if target.const_defined?(:MATERIAL_CODE_LIBRARY_PATH, false)
      target.send(:remove_const, :MATERIAL_CODE_LIBRARY_FILENAME) if target.const_defined?(:MATERIAL_CODE_LIBRARY_FILENAME, false)
      target.include(Accessors)
      target.extend(Accessors)
      target
    end
  end
end

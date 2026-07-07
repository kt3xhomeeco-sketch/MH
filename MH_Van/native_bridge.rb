# encoding: UTF-8

module MH
  module Van
    module NativeBridge
      EXTENSION_BASENAME = 'mh_van_native'.freeze

      class << self
        def available?
          !!native_module
        end

        def load_error
          native_module
          @load_error
        end

        def group_rows(items)
          native = native_module
          return nil unless native && native.respond_to?(:group_items)

          buckets = native.group_items(Array(items))
          buckets.is_a?(Hash) ? buckets : nil
        rescue StandardError => e
          @load_error = e
          nil
        end

        private

        def native_module
          if @native_module
            register_shared_provider(@native_module)
            return @native_module
          end
          return nil if @load_attempted

          @load_attempted = true
          native_paths.each do |path|
            begin
              require path
              @native_module = MH::Van::Native if defined?(MH::Van::Native)
              if @native_module
                register_shared_provider(@native_module)
                return @native_module
              end
            rescue LoadError => e
              @load_error = e
            rescue StandardError => e
              @load_error = e
              return nil
            end
          end
          nil
        end

        def register_shared_provider(native)
          return unless defined?(MH::Geo::Cluster)
          return unless MH::Geo::Cluster.respond_to?(:register_native_provider)

          MH::Geo::Cluster.register_native_provider(native)
        rescue StandardError
          nil
        end

        def native_paths
          base_dir = File.dirname(__FILE__)
          [
            File.join(base_dir, 'native', EXTENSION_BASENAME),
            File.join(base_dir, 'native', 'build', EXTENSION_BASENAME),
            EXTENSION_BASENAME
          ]
        end
      end
    end
  end
end

# Load once during extension startup so shared geometry consumers can use the
# provider even before the MH Van dialog is opened.
MH::Van::NativeBridge.available?

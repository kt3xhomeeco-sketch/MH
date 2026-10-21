# encoding: UTF-8

module MH
  module Memo
    module_function

    def local(max_size = nil)
      LocalCache.new(max_size)
    end

    def fetch(cache, key)
      return nil unless cache.respond_to?(:key?)
      cache.key?(key) ? cache[key] : nil
    rescue
      nil
    end

    def store(cache, key, value, max_size = nil)
      return value unless cache.respond_to?(:[]=)
      limit = max_size.to_i
      cache.clear if limit > 0 && cache.respond_to?(:size) && cache.size >= limit
      cache[key] = value
      value
    rescue
      value
    end

    class LocalCache
      def initialize(max_size = nil)
        @max_size = max_size.to_i
        @data = {}
      end

      def fetch(key)
        return @data[key] if @data.key?(key)

        value = block_given? ? yield : nil
        store(key, value)
      end

      def store(key, value)
        @data.clear if @max_size > 0 && @data.size >= @max_size
        @data[key] = value
        value
      end

      def key?(key)
        @data.key?(key)
      end

      def [](key)
        @data[key]
      end

      def []=(key, value)
        store(key, value)
      end

      def size
        @data.size
      end

      def clear
        @data.clear
      end
    end
  end
end

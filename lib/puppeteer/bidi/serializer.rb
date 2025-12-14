# frozen_string_literal: true
# rbs_inline: enabled

require 'json'
require 'puppeteer/bidi/lazy_arg'

module Puppeteer
  module Bidi
    # Serializer converts Ruby values to BiDi Script.LocalValue format
    # Based on Puppeteer's Serializer.ts
    class Serializer
      class << self
        # Serialize a Ruby value to BiDi LocalValue format
        # @param value [Object] Ruby value to serialize
        # @return [Hash] BiDi LocalValue
        # @raise [ArgumentError] for unsupported types or circular references
        def serialize(value)
          value = value.resolve while value.is_a?(LazyArg)

          # Check for circular references first for complex objects
          if complex_object?(value)
            check_circular_reference(value)
          end

          case value
          when JSHandle
            # Handle references (either handle or sharedId)
            serialize_handle(value)
          when String
            { type: 'string', value: value }
          when Integer
            { type: 'number', value: value }
          when Float
            serialize_number(value)
          when TrueClass, FalseClass
            { type: 'boolean', value: value }
          when NilClass
            { type: 'null' }
          when Symbol
            raise ArgumentError, 'Unable to serialize Symbol'
          when Proc, Method
            raise ArgumentError, 'Unable to serialize Proc/Function'
          when Array
            {
              type: 'array',
              value: value.map { |item| serialize(item) }
            }
          when Hash
            # Plain Ruby Hash → BiDi object with [key, value] pairs
            {
              type: 'object',
              value: value.map { |k, v| [k.to_s, serialize(v)] }
            }
          when Set
            {
              type: 'set',
              value: value.map { |item| serialize(item) }
            }
          when Regexp
            {
              type: 'regexp',
              value: {
                pattern: value.source,
                flags: regexp_flags(value)
              }
            }
          when Time, Date, DateTime
            # Convert to ISO 8601 string
            time_value = value.is_a?(Time) ? value : value.to_time
            {
              type: 'date',
              value: time_value.utc.iso8601(3)
            }
          else
            # Unsupported type
            raise ArgumentError, "Unable to serialize #{value.class}. Use plain objects instead"
          end
        end

        private

        # Check if value is a complex object that might have circular references
        def complex_object?(value)
          value.is_a?(Array) || value.is_a?(Hash) || value.is_a?(Set)
        end

        # Check for circular references using JSON encoding
        # This matches Puppeteer's approach
        def check_circular_reference(value)
          JSON.generate(value)
        rescue JSON::GeneratorError => e
          if e.message.include?('circular') || e.message.include?('depth')
            raise ArgumentError, 'Recursive objects are not allowed'
          end
          raise
        end

        # Serialize a JSHandle to a BiDi reference
        def serialize_handle(handle)
          remote_value = handle.remote_value

          # Prefer handle over sharedId
          if remote_value['sharedId']
            { sharedId: remote_value['sharedId'] }
          elsif remote_value['handle']
            { handle: remote_value['handle'] }
          else
            # Fallback: return the full remote value
            remote_value
          end
        end

        # Serialize a Float to BiDi number format, handling special values
        def serialize_number(num)
          if num.nan?
            { type: 'number', value: 'NaN' }
          elsif num == Float::INFINITY
            { type: 'number', value: 'Infinity' }
          elsif num == -Float::INFINITY
            { type: 'number', value: '-Infinity' }
          elsif num.zero? && (1.0 / num).negative?
            # Detect -0.0
            { type: 'number', value: '-0' }
          else
            { type: 'number', value: num }
          end
        end

        # Extract regexp flags from Ruby Regexp
        def regexp_flags(regexp)
          flags = []
          flags << 'i' if (regexp.options & Regexp::IGNORECASE) != 0
          flags << 'm' if (regexp.options & Regexp::MULTILINE) != 0
          flags << 'x' if (regexp.options & Regexp::EXTENDED) != 0
          flags.join
        end
      end
    end
  end
end

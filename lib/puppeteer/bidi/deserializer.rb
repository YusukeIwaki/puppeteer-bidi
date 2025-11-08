# frozen_string_literal: true

require 'time'
require 'set'

module Puppeteer
  module Bidi
    # Deserializer converts BiDi Script.RemoteValue to Ruby values
    # Based on Puppeteer's Deserializer.ts
    class Deserializer
      class << self
        # Deserialize a BiDi RemoteValue to Ruby value
        # @param remote_value [Hash] BiDi RemoteValue
        # @param realm [Core::Realm, nil] Realm for creating handles (optional)
        # @return [Object] Ruby value or JSHandle/ElementHandle if realm provided
        def deserialize(remote_value, realm = nil)
          return remote_value unless remote_value.is_a?(Hash)

          type = remote_value['type']

          case type
          when 'string'
            remote_value['value']
          when 'number'
            deserialize_number(remote_value['value'])
          when 'boolean'
            remote_value['value']
          when 'null'
            nil
          when 'undefined'
            nil
          when 'bigint'
            # BiDi sends bigint as string, convert to Integer
            remote_value['value'].to_i
          when 'array'
            # Deserialize array elements
            return [] unless remote_value['value']
            remote_value['value'].map { |item| deserialize(item, realm) }
          when 'set'
            # Deserialize set elements and return Ruby Set
            return Set.new unless remote_value['value']
            Set.new(remote_value['value'].map { |item| deserialize(item, realm) })
          when 'object'
            # Object is an array of [key, value] tuples
            deserialize_object(remote_value['value'], realm)
          when 'map'
            # Map is an array of [key, value] tuples with non-string keys
            deserialize_map(remote_value['value'], realm)
          when 'regexp'
            # Reconstruct Ruby Regexp
            deserialize_regexp(remote_value['value'])
          when 'date'
            # Parse ISO 8601 datetime string
            Time.parse(remote_value['value'])
          when 'promise'
            # Promise placeholder - return empty hash
            {}
          when 'node'
            # DOM node - create ElementHandle if realm provided
            if realm
              ElementHandle.new(realm, remote_value)
            else
              # Without realm, return the remote value as-is
              remote_value
            end
          else
            # Unknown type - create JSHandle if realm provided
            if realm
              JSHandle.new(realm, remote_value)
            else
              # Without realm, return value as-is or nil
              remote_value['value']
            end
          end
        end

        private

        # Deserialize a BiDi number value (handles special strings)
        def deserialize_number(value)
          case value
          when 'NaN'
            Float::NAN
          when 'Infinity'
            Float::INFINITY
          when '-Infinity'
            -Float::INFINITY
          when '-0'
            -0.0
          else
            value
          end
        end

        # Deserialize BiDi object (array of [key, value] tuples) to Ruby Hash
        def deserialize_object(tuples, realm)
          return {} unless tuples

          tuples.each_with_object({}) do |(key, value), hash|
            # Keys in objects are always strings in BiDi
            hash[key] = deserialize(value, realm)
          end
        end

        # Deserialize BiDi map (array of [key, value] tuples) to Ruby Hash
        # Maps can have non-string keys, so we deserialize keys too
        def deserialize_map(tuples, realm)
          return {} unless tuples

          tuples.each_with_object({}) do |pair, hash|
            key = deserialize(pair[0], realm)
            value = deserialize(pair[1], realm)
            hash[key] = value
          end
        end

        # Deserialize BiDi regexp to Ruby Regexp
        def deserialize_regexp(value)
          pattern = value['pattern']
          flags_str = value['flags'] || ''

          flags = 0
          flags |= Regexp::IGNORECASE if flags_str.include?('i')
          flags |= Regexp::MULTILINE if flags_str.include?('m')
          flags |= Regexp::EXTENDED if flags_str.include?('x')

          Regexp.new(pattern, flags)
        end
      end
    end
  end
end

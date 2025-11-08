# frozen_string_literal: true

require_relative 'js_handle'

module Puppeteer
  module Bidi
    # ElementHandle represents a reference to a DOM element
    # Based on Puppeteer's BidiElementHandle implementation
    # This extends JSHandle with DOM-specific methods
    class ElementHandle < JSHandle
      # Factory method to create ElementHandle from remote value
      # @param remote_value [Hash] BiDi RemoteValue
      # @param realm [Core::Realm] Associated realm
      # @return [ElementHandle] ElementHandle instance
      def self.from(remote_value, realm)
        new(realm, remote_value)
      end

      # Query for a descendant element matching the selector
      # @param selector [String] CSS selector
      # @return [ElementHandle, nil] Element handle if found, nil otherwise
      def query_selector(selector)
        raise 'ElementHandle is disposed' if disposed?

        # Use querySelector on this element
        result = @realm.call_function(
          '(element, selector) => element.querySelector(selector)',
          false,
          arguments: [
            @remote_value,
            Serializer.serialize(selector)
          ]
        )

        # Check for exceptions
        if result['type'] == 'exception'
          exception_details = result['exceptionDetails']
          text = exception_details['text'] || 'Query selector failed'
          raise text
        end

        # Check if result is null
        result_value = result['result']
        return nil if result_value['type'] == 'null' || result_value['type'] == 'undefined'

        # Return ElementHandle for the found element
        ElementHandle.new(@realm, result_value)
      end

      # Query for all descendant elements matching the selector
      # @param selector [String] CSS selector
      # @return [Array<ElementHandle>] Array of element handles
      def query_selector_all(selector)
        raise 'ElementHandle is disposed' if disposed?

        # Use querySelectorAll on this element
        result = @realm.call_function(
          '(element, selector) => Array.from(element.querySelectorAll(selector))',
          false,
          arguments: [
            @remote_value,
            Serializer.serialize(selector)
          ]
        )

        # Check for exceptions
        if result['type'] == 'exception'
          exception_details = result['exceptionDetails']
          text = exception_details['text'] || 'Query selector failed'
          raise text
        end

        # Result should be an array
        result_value = result['result']
        return [] unless result_value['type'] == 'array'

        # Convert each element to ElementHandle
        result_value['value'].map do |element_value|
          ElementHandle.new(@realm, element_value)
        end
      end

      # String representation includes element type
      # @return [String] Formatted string
      def to_s
        return 'ElementHandle@disposed' if disposed?
        'ElementHandle@node'
      end
    end
  end
end

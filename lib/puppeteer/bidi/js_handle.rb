# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # JSHandle represents a reference to a JavaScript object
    # Based on Puppeteer's BidiJSHandle implementation
    class JSHandle
      attr_reader :realm #: Core::Realm

      # @rbs remote_value: Hash[String, untyped]
      # @rbs realm: Core::Realm
      # @rbs return: void
      def initialize(realm, remote_value)
        @realm = realm
        @remote_value = remote_value
        @disposed = false
      end

      # Factory method to create JSHandle from remote value
      # @rbs remote_value: Hash[String, untyped]
      # @rbs realm: Core::Realm
      # @rbs return: JSHandle | ElementHandle
      def self.from(remote_value, realm)
        if remote_value['type'] == 'node'
          ElementHandle.new(realm, remote_value)
        else
          new(realm, remote_value)
        end
      end

      # Get the remote value (BiDi Script.RemoteValue)
      # @rbs return: Hash[String, untyped]
      def remote_value
        @remote_value
      end

      # Get the remote object (alias for remote_value)
      # @rbs return: Hash[String, untyped]
      def remote_object
        @remote_value
      end

      # Check if handle has been disposed
      # @rbs return: bool
      def disposed?
        @disposed
      end

      # Dispose this handle by releasing the remote object
      # @rbs return: void
      def dispose
        return if @disposed

        @disposed = true

        # Release the remote reference if it has a handle
        handle_id = id
        @realm.disown([handle_id]).wait if handle_id
      end

      # Get the handle ID (handle or sharedId)
      # @rbs return: String?
      def id
        @remote_value['handle'] || @remote_value['sharedId']
      end

      # Evaluate JavaScript function with this handle as the first argument
      # @rbs script: String
      # @rbs *args: untyped
      # @rbs return: untyped
      def evaluate(script, *args)
        assert_not_disposed

        # Prepend this handle as first argument
        all_args = [@remote_value] + args.map { |arg| Serializer.serialize(arg) }

        result = @realm.call_function(script, true, arguments: all_args).wait

        # Check for exceptions
        if result['type'] == 'exception'
          handle_evaluation_exception(result)
        end

        # Deserialize result
        Deserializer.deserialize(result['result'])
      end

      # Evaluate JavaScript function and return a handle to the result
      # @rbs script: String
      # @rbs *args: untyped
      # @rbs return: JSHandle
      def evaluate_handle(script, *args)
        assert_not_disposed

        # Prepend this handle as first argument
        all_args = [@remote_value] + args.map { |arg| Serializer.serialize(arg) }

        # Puppeteer passes awaitPromise: true to wait for promises to resolve
        result = @realm.call_function(script, true, arguments: all_args).wait

        # Check for exceptions
        if result['type'] == 'exception'
          handle_evaluation_exception(result)
        end

        # Return handle (don't deserialize)
        JSHandle.from(result['result'], @realm)
      end

      # Get a property of the object
      # @rbs property_name: String
      # @rbs return: JSHandle
      def get_property(property_name)
        assert_not_disposed

        result = @realm.call_function(
          '(object, property) => object[property]',
          false,
          arguments: [
            @remote_value,
            Serializer.serialize(property_name)
          ]
        ).wait

        if result['type'] == 'exception'
          exception_details = result['exceptionDetails']
          text = exception_details['text'] || 'Evaluation failed'
          raise text
        end

        JSHandle.from(result['result'], @realm)
      end

      # Get all properties of the object
      # @rbs return: Hash[String, JSHandle]
      def get_properties
        assert_not_disposed

        # Get own and inherited properties
        result = @realm.call_function(
          <<~JS,
            (object) => {
              const properties = {};
              let current = object;

              // Walk the prototype chain
              while (current) {
                const names = Object.getOwnPropertyNames(current);
                for (const name of names) {
                  if (!(name in properties)) {
                    try {
                      properties[name] = object[name];
                    } catch (e) {
                      // Skip properties that throw on access
                    }
                  }
                }
                current = Object.getPrototypeOf(current);
              }

              return properties;
            }
          JS
          false,
          arguments: [@remote_value]
        ).wait

        if result['type'] == 'exception'
          return {}
        end

        # Get property entries
        properties_object = result['result']
        return {} if properties_object['type'] == 'undefined' || properties_object['type'] == 'null'

        # Get each property as a handle
        props_result = @realm.call_function(
          <<~JS,
            (object) => {
              const entries = [];
              for (const key in object) {
                entries.push([key, object[key]]);
              }
              return entries;
            }
          JS
          false,
          arguments: [properties_object]
        ).wait

        if props_result['type'] == 'exception'
          return {}
        end

        entries = props_result['result']
        return {} unless entries['type'] == 'array'

        # Convert to Hash of JSHandles
        result_hash = {}
        entries['value'].each do |entry|
          next unless entry['type'] == 'array'
          next unless entry['value'].length == 2

          key = Deserializer.deserialize(entry['value'][0])
          value_remote = entry['value'][1]

          result_hash[key] = JSHandle.from(value_remote, @realm)
        end

        result_hash
      end

      # Convert this handle to a JSON-serializable value
      # @rbs return: untyped
      def json_value
        assert_not_disposed

        # Use evaluate with identity function, just like Puppeteer does
        # This leverages BiDi's built-in serialization with returnByValue: true
        evaluate('(value) => value')
      end

      # Convert to ElementHandle if this is an element
      # @rbs return: ElementHandle?
      def as_element
        return nil unless @remote_value['type'] == 'node'

        # Check if it's an element node (nodeType 1) or text node (nodeType 3)
        result = @realm.call_function(
          '(node) => node.nodeType',
          false,
          arguments: [@remote_value]
        ).wait

        return nil if result['type'] == 'exception'

        node_type = result['result']['value']

        # 1 = ELEMENT_NODE, 3 = TEXT_NODE
        if node_type == 1 || node_type == 3
          ElementHandle.new(@realm, @remote_value)
        else
          nil
        end
      end

      # Check if this is a primitive value
      # @rbs return: bool
      def primitive_value?
        type = @remote_value['type']
        %w[string number bigint boolean undefined null].include?(type)
      end

      # String representation of this handle
      # @rbs return: String
      def to_s
        return 'JSHandle@disposed' if @disposed

        if primitive_value?
          value = Deserializer.deserialize(@remote_value)
          # For strings, don't use inspect (no quotes)
          if value.is_a?(String)
            "JSHandle:#{value}"
          else
            "JSHandle:#{value.inspect}"
          end
        else
          "JSHandle@#{@remote_value['type']}"
        end
      end

      private

      # Check if this handle has been disposed and raise error if so
      # @rbs return: void
      def assert_not_disposed
        raise JSHandleDisposedError if @disposed
      end

      # Handle evaluation exceptions
      # @rbs result: Hash[String, untyped]
      # @rbs return: void
      def handle_evaluation_exception(result)
        exception_details = result['exceptionDetails']
        return unless exception_details

        text = exception_details['text'] || 'Evaluation failed'
        exception = exception_details['exception']

        error_message = text

        if exception && exception['type'] != 'error'
          thrown_value = Deserializer.deserialize(exception)
          error_message = "Evaluation failed: #{thrown_value}"
        end

        raise error_message
      end
    end
  end
end

# frozen_string_literal: true

module Puppeteer
  module Bidi
    # Frame represents a frame (main frame or iframe) in the page
    # This is a high-level wrapper around Core::BrowsingContext
    class Frame
      attr_reader :browsing_context

      def initialize(browsing_context)
        @browsing_context = browsing_context
      end

      # Evaluate JavaScript in the frame context
      # @param script [String] JavaScript to evaluate (expression or function)
      # @param *args [Array] Arguments to pass to the function (if script is a function)
      # @return [Object] Result of evaluation
      def evaluate(script, *args)
        raise 'Frame is detached' if @browsing_context.closed?

        # Detect if the script is a function
        script_trimmed = script.strip
        is_function = script_trimmed.match?(/\A\s*(?:async\s+)?(?:\(.*?\)|[a-zA-Z_$][\w$]*)\s*=>/) ||
                      script_trimmed.match?(/\A\s*(?:async\s+)?function\s*\w*\s*\(/)

        if is_function
          # Serialize arguments to BiDi format
          serialized_args = args.map { |arg| serialize_argument(arg) }

          # Use callFunction for function declarations
          options = {}
          options[:arguments] = serialized_args unless serialized_args.empty?
          result = @browsing_context.default_realm.call_function(script_trimmed, true, **options)
        else
          # Use evaluate for expressions
          result = @browsing_context.default_realm.evaluate(script_trimmed, true)
        end

        # Check for exceptions
        if result['type'] == 'exception'
          handle_evaluation_exception(result)
        end

        # Extract the actual result value
        actual_result = result['result'] || result
        deserialize_result(actual_result)
      end

      # Get the frame URL
      # @return [String] Current URL
      def url
        @browsing_context.url
      end

      # Get the frame name
      # @return [String, nil] Frame name
      def name
        # TODO: Implement frame name retrieval
        nil
      end

      # Check if frame is detached
      # @return [Boolean] Whether the frame is detached
      def detached?
        @browsing_context.closed?
      end

      private

      # Handle evaluation exceptions
      # @param result [Hash] BiDi result with exception
      def handle_evaluation_exception(result)
        exception_details = result['exceptionDetails']
        return unless exception_details

        text = exception_details['text'] || 'Evaluation failed'
        exception = exception_details['exception']

        # Create a descriptive error message
        error_message = text

        # For thrown values, use the exception value if available
        if exception && exception['type'] != 'error'
          thrown_value = deserialize_value(exception)
          error_message = "Evaluation failed: #{thrown_value}"
        end

        raise error_message
      end

      # Serialize a Ruby value to BiDi LocalValue format
      def serialize_argument(arg)
        case arg
        when String
          { type: 'string', value: arg }
        when Integer
          { type: 'number', value: arg }
        when Float
          serialize_number(arg)
        when TrueClass, FalseClass
          { type: 'boolean', value: arg }
        when NilClass
          { type: 'null' }
        when Array
          {
            type: 'array',
            value: arg.map { |item| serialize_argument(item) }
          }
        when Hash
          {
            type: 'object',
            value: arg.map { |k, v| [k.to_s, serialize_argument(v)] }
          }
        when Regexp
          {
            type: 'regexp',
            value: {
              pattern: arg.source,
              flags: [
                ('i' if arg.options & Regexp::IGNORECASE != 0),
                ('m' if arg.options & Regexp::MULTILINE != 0),
                ('x' if arg.options & Regexp::EXTENDED != 0)
              ].compact.join
            }
          }
        else
          raise "Unsupported argument type: #{arg.class}"
        end
      end

      def serialize_number(num)
        if num.nan?
          { type: 'number', value: 'NaN' }
        elsif num == Float::INFINITY
          { type: 'number', value: 'Infinity' }
        elsif num == -Float::INFINITY
          { type: 'number', value: '-Infinity' }
        elsif num.zero? && (1.0 / num).negative?
          { type: 'number', value: '-0' }
        else
          { type: 'number', value: num }
        end
      end

      # Deserialize BiDi protocol result value
      def deserialize_result(result)
        deserialize_value(result)
      end

      # Deserialize a BiDi value
      def deserialize_value(val)
        return val unless val.is_a?(Hash)

        case val['type']
        when 'number'
          deserialize_number(val['value'])
        when 'string'
          val['value']
        when 'boolean'
          val['value']
        when 'undefined', 'null'
          nil
        when 'array'
          val['value'].map { |item| deserialize_value(item) }
        when 'object'
          val['value'].each_with_object({}) do |(key, item_val), hash|
            hash[key] = deserialize_value(item_val)
          end
        when 'map'
          val['value'].each_with_object({}) do |pair, hash|
            key = deserialize_value(pair[0])
            value = deserialize_value(pair[1])
            hash[key] = value
          end
        when 'regexp'
          pattern = val['value']['pattern']
          flags_str = val['value']['flags'] || ''
          flags = 0
          flags |= Regexp::IGNORECASE if flags_str.include?('i')
          flags |= Regexp::MULTILINE if flags_str.include?('m')
          flags |= Regexp::EXTENDED if flags_str.include?('x')
          Regexp.new(pattern, flags)
        else
          val['value']
        end
      end

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
    end
  end
end

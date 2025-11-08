# frozen_string_literal: true

require_relative 'js_handle'
require_relative 'element_handle'
require_relative 'serializer'
require_relative 'deserializer'

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

        # Detect if the script is a function (arrow function or regular function)
        # but not an IIFE (immediately invoked function expression)
        script_trimmed = script.strip

        # Check if it's an IIFE - ends with () after the function body
        is_iife = script_trimmed.match?(/\)\s*\(\s*\)\s*\z/)

        # Check if it's a function declaration/expression
        is_function = !is_iife && (
          script_trimmed.match?(/\A\s*(?:async\s+)?(?:\(.*?\)|[a-zA-Z_$][\w$]*)\s*=>/) ||
          script_trimmed.match?(/\A\s*(?:async\s+)?function\s*\w*\s*\(/)
        )

        if is_function
          # Serialize arguments using Serializer
          serialized_args = args.map { |arg| Serializer.serialize(arg) }

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

        # Deserialize using Deserializer
        actual_result = result['result'] || result
        Deserializer.deserialize(actual_result)
      end

      # Evaluate JavaScript and return a handle to the result
      # @param script [String] JavaScript to evaluate (expression or function)
      # @param *args [Array] Arguments to pass to the function (if script is a function)
      # @return [JSHandle] Handle to the result
      def evaluate_handle(script, *args)
        raise 'Frame is detached' if @browsing_context.closed?

        script_trimmed = script.strip

        # Check if it's an IIFE
        is_iife = script_trimmed.match?(/\)\s*\(\s*\)\s*\z/)

        # Check if it's a function
        is_function = !is_iife && (
          script_trimmed.match?(/\A\s*(?:async\s+)?(?:\(.*?\)|[a-zA-Z_$][\w$]*)\s*=>/) ||
          script_trimmed.match?(/\A\s*(?:async\s+)?function\s*\w*\s*\(/)
        )

        if is_function
          # Serialize arguments using Serializer
          serialized_args = args.map { |arg| Serializer.serialize(arg) }

          options = {}
          options[:arguments] = serialized_args unless serialized_args.empty?
          result = @browsing_context.default_realm.call_function(script_trimmed, false, **options)
        else
          result = @browsing_context.default_realm.evaluate(script_trimmed, false)
        end

        # Check for exceptions
        if result['type'] == 'exception'
          handle_evaluation_exception(result)
        end

        # Create handle using factory method
        JSHandle.from(result['result'], @browsing_context.default_realm)
      end

      # Get the document element handle
      # @return [ElementHandle] Document element handle
      def document
        raise 'Frame is detached' if @browsing_context.closed?

        # Get document object
        result = @browsing_context.default_realm.evaluate('document', false)

        if result['type'] == 'exception'
          raise 'Failed to get document'
        end

        ElementHandle.new(@browsing_context.default_realm, result['result'])
      end

      # Query for an element matching the selector
      # @param selector [String] CSS selector
      # @return [ElementHandle, nil] Element handle if found, nil otherwise
      def query_selector(selector)
        document.query_selector(selector)
      end

      # Query for all elements matching the selector
      # @param selector [String] CSS selector
      # @return [Array<ElementHandle>] Array of element handles
      def query_selector_all(selector)
        document.query_selector_all(selector)
      end

      # Evaluate a function on the first element matching the selector
      # @param selector [String] CSS selector
      # @param page_function [String] JavaScript function to evaluate
      # @param *args [Array] Arguments to pass to the function
      # @return [Object] Result of evaluation
      def eval_on_selector(selector, page_function, *args)
        document.eval_on_selector(selector, page_function, *args)
      end

      # Evaluate a function on all elements matching the selector
      # @param selector [String] CSS selector
      # @param page_function [String] JavaScript function to evaluate
      # @param *args [Array] Arguments to pass to the function
      # @return [Object] Result of evaluation
      def eval_on_selector_all(selector, page_function, *args)
        document.eval_on_selector_all(selector, page_function, *args)
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
          thrown_value = Deserializer.deserialize(exception)
          error_message = "Evaluation failed: #{thrown_value}"
        end

        raise error_message
      end
    end
  end
end

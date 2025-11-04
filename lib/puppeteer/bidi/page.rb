# frozen_string_literal: true

require 'base64'
require 'fileutils'

module Puppeteer
  module Bidi
    # Page represents a single page/tab in the browser
    # This is a high-level wrapper around Core::BrowsingContext
    class Page
      attr_reader :browsing_context

      def initialize(browser_context, browsing_context)
        @browser_context = browser_context
        @browsing_context = browsing_context
      end

      # Navigate to a URL
      # @param url [String] URL to navigate to
      # @param wait_until [String] When to consider navigation succeeded ('load', 'domcontentloaded', 'networkidle')
      # @return [HTTPResponse, nil] Main response
      def goto(url, wait_until: 'load')
        raise 'Page is closed' if closed?

        wait = case wait_until
               when 'load'
                 'complete'
               when 'domcontentloaded'
                 'interactive'
               else
                 'none'
               end

        @browsing_context.navigate(url, wait: wait)
        # TODO: Return HTTPResponse object
        nil
      end

      # Set page content
      # @param html [String] HTML content to set
      # @param wait_until [String] When to consider content set ('load', 'domcontentloaded')
      def set_content(html, wait_until: 'load')
        raise 'Page is closed' if closed?

        # Use data URL to set content
        # Encode HTML in base64 to avoid URL encoding issues
        encoded = Base64.strict_encode64(html)
        data_url = "data:text/html;base64,#{encoded}"
        goto(data_url, wait_until: wait_until)
      end

      # Take a screenshot
      # @param path [String, nil] Path to save the screenshot
      # @param type [String] Screenshot type ('png' or 'jpeg')
      # @param full_page [Boolean] Whether to take a screenshot of the full scrollable page
      # @param clip [Hash, nil] Clipping region {x:, y:, width:, height:}
      # @param capture_beyond_viewport [Boolean] Capture screenshot beyond the viewport (default: true)
      # @return [String] Base64-encoded image data
      def screenshot(path: nil, type: 'png', full_page: false, clip: nil, capture_beyond_viewport: true)
        raise 'Page is closed' if closed?

        options = {
          format: {
            type: type == 'jpeg' ? 'image/jpeg' : 'image/png'
          }
        }

        # Handle fullPage screenshot
        if full_page
          # If captureBeyondViewport is false, then we set the viewport to
          # capture the full page. Note this may be affected by on-page CSS and JavaScript.
          unless capture_beyond_viewport
            # Get scroll dimensions
            scroll_dimensions = evaluate(<<~JS)
              (() => {
                const element = document.documentElement;
                return {
                  width: element.scrollWidth,
                  height: element.scrollHeight
                };
              })()
            JS

            # Save original viewport (could be nil)
            original_viewport = viewport

            # If no viewport is set, save current window size
            unless original_viewport
              original_size = evaluate('({ width: window.innerWidth, height: window.innerHeight })')
              original_viewport = { width: original_size['width'].to_i, height: original_size['height'].to_i }
            end

            # Set viewport to full page size
            set_viewport(
              width: scroll_dimensions['width'].to_i,
              height: scroll_dimensions['height'].to_i
            )

            begin
              # Capture screenshot with viewport origin
              options[:origin] = 'viewport'
              data = @browsing_context.capture_screenshot(**options)
            ensure
              # Restore original viewport
              if original_viewport
                set_viewport(
                  width: original_viewport[:width],
                  height: original_viewport[:height]
                )
              end
            end

            # Save to file if path is provided
            if path
              dir = File.dirname(path)
              FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
              File.binwrite(path, Base64.decode64(data))
            end

            return data
          else
            # Capture full document with origin: document
            options[:origin] = 'document'
          end
        elsif !clip
          # If not fullPage and no clip, force captureBeyondViewport to false
          capture_beyond_viewport = false
        end

        # Add clip region if specified
        if clip
          # Set origin based on captureBeyondViewport (only when clip is specified)
          if capture_beyond_viewport
            options[:origin] = 'document'
          else
            options[:origin] = 'viewport'
          end
          box = clip.dup

          # When captureBeyondViewport is false, convert document coordinates to viewport coordinates
          unless capture_beyond_viewport
            # Get viewport offset
            page_left = evaluate('window.visualViewport.pageLeft')
            page_top = evaluate('window.visualViewport.pageTop')

            # Convert to viewport coordinates
            box = {
              x: clip[:x] - page_left,
              y: clip[:y] - page_top,
              width: clip[:width],
              height: clip[:height]
            }
          end

          options[:clip] = {
            type: 'box',
            x: box[:x],
            y: box[:y],
            width: box[:width],
            height: box[:height]
          }
        end

        # Get screenshot data from browsing context
        data = @browsing_context.capture_screenshot(**options)

        # Save to file if path is provided
        if path
          # Ensure directory exists
          dir = File.dirname(path)
          FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

          # data is base64 encoded, decode and write
          File.binwrite(path, Base64.decode64(data))
        end

        data
      end

      # Evaluate JavaScript in the page context
      # @param script [String] JavaScript to evaluate (expression or function)
      # @param *args [Array] Arguments to pass to the function (if script is a function)
      # @return [Object] Result of evaluation
      def evaluate(script, *args)
        raise 'Page is closed' if closed?

        # Detect if the script is a function (arrow function or regular function)
        # by checking if it starts with function keyword or arrow function pattern
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
        # For success, the result is in result['result']
        # For other types, handle appropriately
        actual_result = result['result'] || result
        deserialize_result(actual_result)
      end

      # Handle evaluation exceptions
      # @param result [Hash] BiDi result with exception
      def handle_evaluation_exception(result)
        # Extract error information from exception result
        exception_details = result['exceptionDetails']
        return unless exception_details

        text = exception_details['text'] || 'Evaluation failed'
        exception = exception_details['exception']

        # Create a descriptive error message
        error_message = text

        # For thrown values (strings, numbers, objects, etc.),  use the exception value if available
        if exception && exception['type'] != 'error'
          # For thrown primitives (strings, numbers, etc.), deserialize them
          thrown_value = deserialize_value(exception)
          error_message = "Evaluation failed: #{thrown_value}"
        end

        raise error_message
      end

      private

      # Serialize a Ruby value to BiDi LocalValue format
      # @param arg [Object] Ruby value to serialize
      # @return [Hash] BiDi LocalValue
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

      # Serialize a number to BiDi format, handling special values
      # @param num [Float, Integer] Number to serialize
      # @return [Hash] BiDi LocalValue for number
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
          # Array values are an array of BiDi values
          val['value'].map { |item| deserialize_value(item) }
        when 'object'
          # Object values are an array of [key, value] pairs
          val['value'].each_with_object({}) do |(key, item_val), hash|
            hash[key] = deserialize_value(item_val)
          end
        when 'map'
          # Map values are an array of [key, value] pairs where each is a BiDi value
          # For simplicity, convert to Ruby Hash
          val['value'].each_with_object({}) do |pair, hash|
            # Each pair is an array [key_value, value_value]
            key = deserialize_value(pair[0])
            value = deserialize_value(pair[1])
            hash[key] = value
          end
        when 'regexp'
          # RegExp values have pattern and flags
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

      # Deserialize a number from BiDi format, handling special values
      # @param value [String, Numeric] Number value from BiDi
      # @return [Float, Integer] Ruby number
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

      public

      # Get the page title
      # @return [String] Page title
      def title
        evaluate('document.title')
      end

      # Get the page URL
      # @return [String] Current URL
      def url
        @browsing_context.url
      end

      # Close the page
      def close
        return if closed?

        @browsing_context.close
      end

      # Check if page is closed
      # @return [Boolean] Whether the page is closed
      def closed?
        @browsing_context.closed?
      end

      # Get the main frame
      # @return [Frame] Main frame
      def main_frame
        @main_frame ||= Frame.new(@browsing_context)
      end

      # Wait for navigation
      # @param timeout [Integer] Timeout in milliseconds
      # @return [HTTPResponse, nil] Main response
      def wait_for_navigation(timeout: 30000)
        # TODO: Implement proper navigation waiting
        sleep 0.1
        nil
      end

      # Set viewport size
      # @param width [Integer] Viewport width
      # @param height [Integer] Viewport height
      def set_viewport(width:, height:)
        @viewport = { width: width, height: height }
        @browsing_context.set_viewport(
          viewport: {
            width: width,
            height: height
          }
        )
      end

      # Get current viewport size
      # @return [Hash, nil] Current viewport {width:, height:} or nil
      def viewport
        @viewport
      end

      alias viewport= set_viewport
    end
  end
end

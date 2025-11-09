# frozen_string_literal: true

require 'base64'
require 'fileutils'
require_relative 'js_handle'
require_relative 'element_handle'
require_relative 'mouse'

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
        assert_not_closed

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
        assert_not_closed

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
        assert_not_closed

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
        main_frame.evaluate(script, *args)
      end

      # Evaluate JavaScript and return a handle to the result
      # @param script [String] JavaScript to evaluate (expression or function)
      # @param *args [Array] Arguments to pass to the function (if script is a function)
      # @return [JSHandle] Handle to the result
      def evaluate_handle(script, *args)
        main_frame.evaluate_handle(script, *args)
      end

      # Query for an element matching the selector
      # @param selector [String] CSS selector
      # @return [ElementHandle, nil] Element handle if found, nil otherwise
      def query_selector(selector)
        main_frame.query_selector(selector)
      end

      # Query for all elements matching the selector
      # @param selector [String] CSS selector
      # @return [Array<ElementHandle>] Array of element handles
      def query_selector_all(selector)
        main_frame.query_selector_all(selector)
      end

      # Evaluate a function on the first element matching the selector
      # @param selector [String] CSS selector
      # @param page_function [String] JavaScript function to evaluate
      # @param *args [Array] Arguments to pass to the function
      # @return [Object] Result of evaluation
      def eval_on_selector(selector, page_function, *args)
        main_frame.eval_on_selector(selector, page_function, *args)
      end

      # Evaluate a function on all elements matching the selector
      # @param selector [String] CSS selector
      # @param page_function [String] JavaScript function to evaluate
      # @param *args [Array] Arguments to pass to the function
      # @return [Object] Result of evaluation
      def eval_on_selector_all(selector, page_function, *args)
        main_frame.eval_on_selector_all(selector, page_function, *args)
      end

      # Click an element matching the selector
      # @param selector [String] CSS selector
      # @param button [String] Mouse button ('left', 'right', 'middle')
      # @param count [Integer] Number of clicks (1, 2, 3)
      # @param delay [Numeric] Delay between mousedown and mouseup in milliseconds
      # @param offset [Hash] Click offset {x:, y:} relative to element center
      def click(selector, button: Mouse::LEFT, count: 1, delay: nil, offset: nil)
        main_frame.click(selector, button: button, count: count, delay: delay, offset: offset)
      end

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
        @main_frame ||= Frame.new(self, @browsing_context)
      end

      # Get the mouse instance
      # @return [Mouse] Mouse instance
      def mouse
        @mouse ||= Mouse.new(@browsing_context)
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

      # Set JavaScript enabled state
      # @param enabled [Boolean] Whether JavaScript is enabled
      # @note Changes take effect on next navigation
      def set_javascript_enabled(enabled)
        assert_not_closed
        @browsing_context.set_javascript_enabled(enabled)
      end

      # Check if JavaScript is enabled
      # @return [Boolean] Whether JavaScript is enabled
      def javascript_enabled?
        @browsing_context.javascript_enabled?
      end

      private

      # Check if this page is closed and raise error if so
      # @raise [PageClosedError] If page is closed
      def assert_not_closed
        raise PageClosedError if closed?
      end
    end
  end
end

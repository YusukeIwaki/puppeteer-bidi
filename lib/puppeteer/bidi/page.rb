# frozen_string_literal: true

require 'base64'
require 'fileutils'

module Puppeteer
  module Bidi
    # Page represents a single page/tab in the browser
    # This is a high-level wrapper around Core::BrowsingContext
    class Page
      DEFAULT_TIMEOUT = 30_000

      attr_reader :browsing_context, :browser_context, :timeout_settings

      def initialize(browser_context, browsing_context)
        @browser_context = browser_context
        @browsing_context = browsing_context
        @timeout_settings = TimeoutSettings.new(DEFAULT_TIMEOUT)
      end

      # Navigate to a URL
      # @param url [String] URL to navigate to
      # @param wait_until [String] When to consider navigation succeeded ('load', 'domcontentloaded', 'networkidle')
      # @return [HTTPResponse, nil] Main response
      def goto(url, wait_until: 'load')
        assert_not_closed

        main_frame.goto(url, wait_until: wait_until)
      end

      # Set page content
      # @param html [String] HTML content to set
      # @param wait_until [String] When to consider content set ('load', 'domcontentloaded')
      def set_content(html, wait_until: 'load')
        main_frame.set_content(html, wait_until: wait_until)
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
              data = @browsing_context.capture_screenshot(**options).wait
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
        data = @browsing_context.capture_screenshot(**options).wait

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

      # Type text into an element matching the selector
      # @param selector [String] CSS selector
      # @param text [String] Text to type
      # @param delay [Numeric] Delay between key presses in milliseconds
      def type(selector, text, delay: 0)
        main_frame.type(selector, text, delay: delay)
      end

      # Focus an element matching the selector
      # @param selector [String] CSS selector
      def focus(selector)
        handle = main_frame.query_selector(selector)
        raise SelectorNotFoundError, selector unless handle

        begin
          handle.focus
        ensure
          handle.dispose
        end
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

        @browsing_context.close.wait
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

      # Get the focused frame
      # @return [Frame] Focused frame (may be an iframe if one has focus)
      def focused_frame
        assert_not_closed

        # Evaluate in main frame to find the focused window
        handle = main_frame.evaluate_handle(<<~JS)
          () => {
            let win = window;
            while (
              win.document.activeElement instanceof win.HTMLIFrameElement ||
              win.document.activeElement instanceof win.HTMLFrameElement
            ) {
              if (win.document.activeElement.contentWindow === null) {
                break;
              }
              win = win.document.activeElement.contentWindow;
            }
            return win;
          }
        JS

        # Get the remote value (should be a window object)
        remote_value = handle.remote_value
        handle.dispose

        unless remote_value['type'] == 'window'
          raise "Expected window type, got #{remote_value['type']}"
        end

        # Find the frame with matching context ID
        context_id = remote_value['value']['context']
        frame = frames.find { |f| f.browsing_context.id == context_id }

        raise "Could not find frame with context #{context_id}" unless frame

        frame
      end

      # Get all frames (main frame + child frames)
      # @return [Array<Frame>] All frames
      def frames
        [main_frame] + main_frame.child_frames
      end

      # Get the mouse instance
      # @return [Mouse] Mouse instance
      def mouse
        @mouse ||= Mouse.new(@browsing_context)
      end

      # Get the keyboard instance
      # @return [Keyboard] Keyboard instance
      def keyboard
        @keyboard ||= Keyboard.new(self, @browsing_context)
      end

      # Wait for a function to return a truthy value
      # @param page_function [String] JavaScript function to evaluate
      # @param options [Hash] Options for waiting
      # @option options [String, Numeric] :polling Polling strategy ('raf', 'mutation', or interval in ms)
      # @option options [Numeric] :timeout Timeout in milliseconds (default: 30000)
      # @param args [Array] Arguments to pass to the function
      # @return [JSHandle] Handle to the function's return value
      def wait_for_function(page_function, options = {}, *args, &block)
        main_frame.wait_for_function(page_function, options, *args, &block)
      end

      # Wait for an element matching the selector to appear in the page
      # @param selector [String] CSS selector
      # @param visible [Boolean] Wait for element to be visible
      # @param hidden [Boolean] Wait for element to be hidden or not found
      # @param timeout [Numeric] Timeout in milliseconds (default: 30000)
      # @return [ElementHandle, nil] Element handle if found, nil if hidden option was used and element disappeared
      def wait_for_selector(selector, visible: nil, hidden: nil, timeout: nil, &block)
        main_frame.wait_for_selector(selector, visible: visible, hidden: hidden, timeout: timeout, &block)
      end

      # Set the default timeout for waiting operations (e.g., waitForFunction).
      # @param timeout [Numeric] Timeout in milliseconds (0 disables the timeout)
      def set_default_timeout(timeout)
        raise ArgumentError, 'timeout must be a non-negative number' unless timeout.is_a?(Numeric) && timeout >= 0

        @timeout_settings.set_default_timeout(timeout)
      end

      # Get the current default timeout in milliseconds.
      # @return [Numeric]
      def default_timeout
        @timeout_settings.timeout
      end

      # Wait for navigation to complete
      # @param timeout [Numeric] Timeout in milliseconds (default: 30000)
      # @param wait_until [String] When to consider navigation succeeded ('load', 'domcontentloaded')
      # @yield Optional block to execute that triggers navigation
      # @return [HTTPResponse, nil] Main response (nil for fragment navigation or history API)
      def wait_for_navigation(timeout: 30000, wait_until: 'load', &block)
        main_frame.wait_for_navigation(timeout: timeout, wait_until: wait_until, &block)
      end

      # Wait for network to be idle (no more than concurrency connections for idle_time)
      # Based on Puppeteer's waitForNetworkIdle implementation
      # @param idle_time [Numeric] Time in milliseconds to wait for network to be idle (default: 500)
      # @param timeout [Numeric] Timeout in milliseconds (default: 30000)
      # @param concurrency [Integer] Maximum number of inflight network connections (0 or 2, default: 0)
      # @return [void]
      def wait_for_network_idle(idle_time: 500, timeout: 30000, concurrency: 0)
        assert_not_closed

        promise = Async::Promise.new
        idle_timer = nil
        idle_timer_mutex = Thread::Mutex.new

        # Listener for inflight changes
        inflight_listener = lambda do |data|
          inflight = data[:inflight]

          idle_timer_mutex.synchronize do
            # Cancel existing timer if any
            idle_timer&.stop

            # If inflight requests exceed concurrency, don't start timer
            if inflight > concurrency
              idle_timer = nil
              return
            end

            # Start idle timer
            idle_timer = Async do |task|
              task.sleep(idle_time / 1000.0)
              promise.resolve(nil)
            end
          end
        end

        # Close listener
        close_listener = lambda do |_data|
          promise.reject(PageClosedError.new)
        end

        begin
          # Register listeners
          @browsing_context.on(:inflight_changed, &inflight_listener)
          @browsing_context.on(:closed, &close_listener)

          # Check initial state - if already idle, start timer immediately
          current_inflight = @browsing_context.inflight_requests
          if current_inflight <= concurrency
            idle_timer_mutex.synchronize do
              idle_timer = Async do |task|
                task.sleep(idle_time / 1000.0)
                promise.resolve(nil)
              end
            end
          end

          # Wait with timeout
          AsyncUtils.async_timeout(timeout, promise).wait
        ensure
          # Clean up
          idle_timer_mutex.synchronize do
            idle_timer&.stop
          end
          @browsing_context.off(:inflight_changed, &inflight_listener)
          @browsing_context.off(:closed, &close_listener)
        end

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
        ).wait
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
        @browsing_context.set_javascript_enabled(enabled).wait
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

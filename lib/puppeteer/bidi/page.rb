# frozen_string_literal: true
# rbs_inline: enabled

require 'base64'
require 'fileutils'

module Puppeteer
  module Bidi
    # Page represents a single page/tab in the browser
    # This is a high-level wrapper around Core::BrowsingContext
    class Page
      DEFAULT_TIMEOUT = 30_000 #: Integer

      attr_reader :browsing_context #: Core::BrowsingContext
      attr_reader :browser_context #: BrowserContext
      attr_reader :timeout_settings #: TimeoutSettings

      # @rbs browser_context: BrowserContext
      # @rbs browsing_context: Core::BrowsingContext
      # @rbs return: void
      def initialize(browser_context, browsing_context)
        @browser_context = browser_context
        @browsing_context = browsing_context
        @timeout_settings = TimeoutSettings.new(DEFAULT_TIMEOUT)
        @emitter = Core::EventEmitter.new
      end

      # Event emitter delegation methods
      # Following Puppeteer's trustedEmitter pattern

      # Register an event listener
      # @rbs event: Symbol | String
      # @rbs &block: (untyped) -> void
      # @rbs return: void
      def on(event, &block)
        @emitter.on(event, &block)
      end

      # Register a one-time event listener
      # @rbs event: Symbol | String
      # @rbs &block: (untyped) -> void
      # @rbs return: void
      def once(event, &block)
        @emitter.once(event, &block)
      end

      # Remove an event listener
      # @rbs event: Symbol | String
      # @rbs &block: (untyped) -> void
      # @rbs return: void
      def off(event, &block)
        @emitter.off(event, &block)
      end

      # Emit an event to all registered listeners
      # @rbs event: Symbol | String
      # @rbs data: untyped
      # @rbs return: void
      def emit(event, data = nil)
        @emitter.emit(event, data)
      end

      # Navigate to a URL
      # @rbs url: String
      # @rbs wait_until: String
      # @rbs return: HTTPResponse?
      def goto(url, wait_until: 'load')
        assert_not_closed

        main_frame.goto(url, wait_until: wait_until)
      end

      # Set page content
      # @rbs html: String
      # @rbs wait_until: String
      # @rbs return: void
      def set_content(html, wait_until: 'load')
        main_frame.set_content(html, wait_until: wait_until)
      end

      # Take a screenshot
      # @rbs path: String?
      # @rbs type: String
      # @rbs full_page: bool
      # @rbs clip: Hash[Symbol, Numeric]?
      # @rbs capture_beyond_viewport: bool
      # @rbs return: String
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
      # @rbs script: String
      # @rbs *args: untyped
      # @rbs return: untyped
      def evaluate(script, *args)
        main_frame.evaluate(script, *args)
      end

      # Evaluate JavaScript and return a handle to the result
      # @rbs script: String
      # @rbs *args: untyped
      # @rbs return: JSHandle
      def evaluate_handle(script, *args)
        main_frame.evaluate_handle(script, *args)
      end

      # Query for an element matching the selector
      # @rbs selector: String
      # @rbs return: ElementHandle?
      def query_selector(selector)
        main_frame.query_selector(selector)
      end

      # Query for all elements matching the selector
      # @rbs selector: String
      # @rbs return: Array[ElementHandle]
      def query_selector_all(selector)
        main_frame.query_selector_all(selector)
      end

      # Evaluate a function on the first element matching the selector
      # @rbs selector: String
      # @rbs page_function: String
      # @rbs *args: untyped
      # @rbs return: untyped
      def eval_on_selector(selector, page_function, *args)
        main_frame.eval_on_selector(selector, page_function, *args)
      end

      # Evaluate a function on all elements matching the selector
      # @rbs selector: String
      # @rbs page_function: String
      # @rbs *args: untyped
      # @rbs return: untyped
      def eval_on_selector_all(selector, page_function, *args)
        main_frame.eval_on_selector_all(selector, page_function, *args)
      end

      # Click an element matching the selector
      # @rbs selector: String
      # @rbs button: String
      # @rbs count: Integer
      # @rbs delay: Numeric?
      # @rbs offset: Hash[Symbol, Numeric]?
      # @rbs return: void
      def click(selector, button: Mouse::LEFT, count: 1, delay: nil, offset: nil)
        main_frame.click(selector, button: button, count: count, delay: delay, offset: offset)
      end

      # Type text into an element matching the selector
      # @rbs selector: String
      # @rbs text: String
      # @rbs delay: Numeric
      # @rbs return: void
      def type(selector, text, delay: 0)
        main_frame.type(selector, text, delay: delay)
      end

      # Hover over an element matching the selector
      # @rbs selector: String
      # @rbs return: void
      def hover(selector)
        main_frame.hover(selector)
      end

      # Focus an element matching the selector
      # @rbs selector: String
      # @rbs return: void
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
      # @rbs return: String
      def title
        evaluate('document.title')
      end

      # Get the page URL
      # @rbs return: String
      def url
        @browsing_context.url
      end

      # Close the page
      # @rbs return: void
      def close
        return if closed?

        @browsing_context.close.wait
      end

      # Check if page is closed
      # @rbs return: bool
      def closed?
        @browsing_context.closed?
      end

      # Get the main frame
      # @rbs return: Frame
      def main_frame
        @main_frame ||= Frame.from(self, @browsing_context)
      end

      # Get the focused frame
      # @rbs return: Frame
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

      # Get all frames (main frame + all nested child frames)
      # Following Puppeteer's pattern of returning all frames recursively
      # @rbs return: Array[Frame]
      def frames
        collect_frames(main_frame)
      end

      # Get the mouse instance
      # @rbs return: Mouse
      def mouse
        @mouse ||= Mouse.new(@browsing_context)
      end

      # Get the keyboard instance
      # @rbs return: Keyboard
      def keyboard
        @keyboard ||= Keyboard.new(self, @browsing_context)
      end

      # Wait for a function to return a truthy value
      # @rbs page_function: String
      # @rbs options: Hash[Symbol, untyped]
      # @rbs *args: untyped
      # @rbs &block: ((JSHandle) -> void)?
      # @rbs return: JSHandle
      def wait_for_function(page_function, options = {}, *args, &block)
        main_frame.wait_for_function(page_function, options, *args, &block)
      end

      # Wait for an element matching the selector to appear in the page
      # @rbs selector: String
      # @rbs visible: bool?
      # @rbs hidden: bool?
      # @rbs timeout: Numeric?
      # @rbs &block: ((ElementHandle?) -> void)?
      # @rbs return: ElementHandle?
      def wait_for_selector(selector, visible: nil, hidden: nil, timeout: nil, &block)
        main_frame.wait_for_selector(selector, visible: visible, hidden: hidden, timeout: timeout, &block)
      end

      # Set the default timeout for waiting operations (e.g., waitForFunction).
      # @rbs timeout: Numeric
      # @rbs return: void
      def set_default_timeout(timeout)
        raise ArgumentError, 'timeout must be a non-negative number' unless timeout.is_a?(Numeric) && timeout >= 0

        @timeout_settings.set_default_timeout(timeout)
      end

      # Get the current default timeout in milliseconds.
      # @rbs return: Numeric
      def default_timeout
        @timeout_settings.timeout
      end

      # Wait for navigation to complete
      # @rbs timeout: Numeric
      # @rbs wait_until: String
      # @rbs &block: (-> void)?
      # @rbs return: HTTPResponse?
      def wait_for_navigation(timeout: 30000, wait_until: 'load', &block)
        main_frame.wait_for_navigation(timeout: timeout, wait_until: wait_until, &block)
      end

      # Wait for a file chooser to be opened
      # @rbs timeout: Numeric?
      # @rbs &block: (-> void)?
      # @rbs return: FileChooser
      def wait_for_file_chooser(timeout: nil, &block)
        assert_not_closed

        # Use provided timeout, or default timeout, treating 0 as infinite
        effective_timeout = timeout || @timeout_settings.timeout

        promise = Async::Promise.new

        # Listener for file dialog opened event
        file_dialog_listener = lambda do |info|
          # info contains: element, multiple
          element_info = info['element']
          return unless element_info

          # Create ElementHandle from the element info
          # The element info should have sharedId and/or handle
          element_remote_value = {
            'type' => 'node',
            'sharedId' => element_info['sharedId'],
            'handle' => element_info['handle']
          }.compact

          element = ElementHandle.from(element_remote_value, @browsing_context.default_realm)
          multiple = info['multiple'] || false

          file_chooser = FileChooser.new(element, multiple)
          promise.resolve(file_chooser)
        end

        begin
          # Register listener before executing the block
          @browsing_context.on(:filedialogopened, &file_dialog_listener)

          # Execute the block that triggers the file chooser
          Async(&block).wait if block

          # Wait for file chooser with timeout
          if timeout == 0
            promise.wait
          else
            AsyncUtils.async_timeout(effective_timeout, promise).wait
          end
        rescue Async::TimeoutError
          raise TimeoutError, "Waiting for file chooser timed out after #{effective_timeout}ms"
        ensure
          @browsing_context.off(:filedialogopened, &file_dialog_listener)
        end
      end

      # Wait for network to be idle (no more than concurrency connections for idle_time)
      # Based on Puppeteer's waitForNetworkIdle implementation
      # @rbs idle_time: Numeric
      # @rbs timeout: Numeric
      # @rbs concurrency: Integer
      # @rbs return: void
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
      # @rbs width: Integer
      # @rbs height: Integer
      # @rbs return: void
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
      # @rbs return: Hash[Symbol, Integer]?
      def viewport
        @viewport
      end

      alias viewport= set_viewport
      alias default_timeout= set_default_timeout

      # Set JavaScript enabled state
      # @rbs enabled: bool
      # @rbs return: void
      def set_javascript_enabled(enabled)
        assert_not_closed
        @browsing_context.set_javascript_enabled(enabled).wait
      end

      # Check if JavaScript is enabled
      # @rbs return: bool
      def javascript_enabled?
        @browsing_context.javascript_enabled?
      end

      private

      # Recursively collect all frames starting from the given frame
      # @rbs frame: Frame
      # @rbs return: Array[Frame]
      def collect_frames(frame)
        result = [frame]
        frame.child_frames.each do |child|
          result.concat(collect_frames(child))
        end
        result
      end

      # Check if this page is closed and raise error if so
      # @rbs return: void
      def assert_not_closed
        raise PageClosedError if closed?
      end
    end
  end
end

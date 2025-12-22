# frozen_string_literal: true
# rbs_inline: enabled

require "base64"
require "fileutils"
require "uri"
require "async/semaphore"

module Puppeteer
  module Bidi
    # Page represents a single page/tab in the browser
    # This is a high-level wrapper around Core::BrowsingContext
    class Page
      DEFAULT_TIMEOUT = 30_000 #: Integer

      attr_reader :browsing_context #: Core::BrowsingContext
      attr_reader :browser_context #: BrowserContext
      attr_reader :timeout_settings #: TimeoutSettings

      # @rbs browser_context: BrowserContext -- Parent browser context
      # @rbs browsing_context: Core::BrowsingContext -- Associated browsing context
      # @rbs return: void
      def initialize(browser_context, browsing_context)
        @browser_context = browser_context
        @browsing_context = browsing_context
        @timeout_settings = TimeoutSettings.new(DEFAULT_TIMEOUT)
        @emitter = Core::EventEmitter.new
        @request_interception_semaphore = Async::Semaphore.new(1)
        @request_handlers = begin
          ObjectSpace::WeakMap.new
        rescue NameError
          {}
        end
        @request_interception = nil
        @auth_interception = nil
        @credentials = nil
      end

      # Event emitter delegation methods
      # Following Puppeteer's trustedEmitter pattern

      # Register an event listener
      # @rbs event: Symbol | String -- Event name
      # @rbs &block: (untyped) -> void -- Event handler
      # @rbs return: void
      def on(event, &block)
        return @emitter.on(event, &block) unless event.to_sym == :request

        wrapper = @request_handlers[block]
        unless wrapper
          wrapper = lambda do |request|
            request.enqueue_intercept_action do
              block.call(request)
            end
          end
          @request_handlers[block] = wrapper
        end
        @emitter.on(event, &wrapper)
      end

      # Register a one-time event listener
      # @rbs event: Symbol | String -- Event name
      # @rbs &block: (untyped) -> void -- Event handler
      # @rbs return: void
      def once(event, &block)
        @emitter.once(event, &block)
      end

      # Remove an event listener
      # @rbs event: Symbol | String -- Event name
      # @rbs &block: (untyped) -> void -- Event handler to remove
      # @rbs return: void
      def off(event, &block)
        if event.to_sym == :request && block
          # WeakMap#delete was added in Ruby 3.3, so we need to handle older versions
          wrapper = if @request_handlers.respond_to?(:delete)
                      @request_handlers.delete(block)
                    else
                      @request_handlers[block]
                    end
          return @emitter.off(event, &(wrapper || block))
        end

        @emitter.off(event, &block)
      end

      # Emit an event to all registered listeners
      # @rbs event: Symbol | String -- Event name
      # @rbs data: untyped -- Event data
      # @rbs return: void
      def emit(event, data = nil)
        @emitter.emit(event, data)
      end

      # @rbs return: bool -- Whether any network interception is enabled
      def network_interception_enabled?
        !@request_interception.nil? || !@auth_interception.nil?
      end

      # @rbs return: Hash[Symbol, String]?
      def credentials
        @credentials
      end

      # @rbs return: Async::Semaphore -- Serialize request interception handling
      attr_reader :request_interception_semaphore

      # Navigate to a URL
      # @rbs url: String -- URL to navigate to
      # @rbs wait_until: String -- When to consider navigation complete ('load', 'domcontentloaded')
      # @rbs return: HTTPResponse? -- Main response
      def goto(url, wait_until: 'load')
        assert_not_closed

        main_frame.goto(url, wait_until: wait_until)
      end

      # Set page content
      # @rbs html: String -- HTML content to set
      # @rbs wait_until: String -- When to consider content set ('load', 'domcontentloaded')
      # @rbs return: void
      def set_content(html, wait_until: 'load')
        main_frame.set_content(html, wait_until: wait_until)
      end

      # Take a screenshot
      # @rbs path: String? -- File path to save screenshot
      # @rbs type: String -- Image type ('png' or 'jpeg')
      # @rbs full_page: bool -- Capture full page
      # @rbs clip: Hash[Symbol, Numeric]? -- Clip region
      # @rbs capture_beyond_viewport: bool -- Capture beyond viewport
      # @rbs return: String -- Base64-encoded image data
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
      # @rbs script: String -- JavaScript code to evaluate
      # @rbs *args: untyped -- Arguments to pass to the script
      # @rbs return: untyped -- Result of evaluation
      def evaluate(script, *args)
        main_frame.evaluate(script, *args)
      end

      # Evaluate JavaScript and return a handle to the result
      # @rbs script: String -- JavaScript code to evaluate
      # @rbs *args: untyped -- Arguments to pass to the script
      # @rbs return: JSHandle -- Handle to the result
      def evaluate_handle(script, *args)
        main_frame.evaluate_handle(script, *args)
      end

      # Query for an element matching the selector
      # @rbs selector: String -- Selector to query
      # @rbs return: ElementHandle? -- Matching element or nil
      def query_selector(selector)
        main_frame.query_selector(selector)
      end

      # Query for all elements matching the selector
      # @rbs selector: String -- Selector to query
      # @rbs return: Array[ElementHandle] -- All matching elements
      def query_selector_all(selector)
        main_frame.query_selector_all(selector)
      end

      # Create a locator for a selector or function.
      # @rbs selector: String? -- Selector to locate
      # @rbs function: String? -- JavaScript function for function locator
      # @rbs return: Locator -- Locator instance
      def locator(selector = nil, function: nil)
        assert_not_closed

        if function
          raise ArgumentError, "selector and function cannot both be set" if selector

          FunctionLocator.create(self, function)
        elsif selector
          NodeLocator.create(self, selector)
        else
          raise ArgumentError, "selector or function must be provided"
        end
      end

      # Evaluate a function on the first element matching the selector
      # @rbs selector: String -- Selector to query
      # @rbs page_function: String -- JavaScript function to evaluate
      # @rbs *args: untyped -- Arguments to pass to the function
      # @rbs return: untyped -- Evaluation result
      def eval_on_selector(selector, page_function, *args)
        main_frame.eval_on_selector(selector, page_function, *args)
      end

      # Evaluate a function on all elements matching the selector
      # @rbs selector: String -- Selector to query
      # @rbs page_function: String -- JavaScript function to evaluate
      # @rbs *args: untyped -- Arguments to pass to the function
      # @rbs return: untyped -- Evaluation result
      def eval_on_selector_all(selector, page_function, *args)
        main_frame.eval_on_selector_all(selector, page_function, *args)
      end

      # Click an element matching the selector
      # @rbs selector: String -- Selector to click
      # @rbs button: String -- Mouse button ('left', 'right', 'middle')
      # @rbs count: Integer -- Number of clicks
      # @rbs delay: Numeric? -- Delay between clicks in ms
      # @rbs offset: Hash[Symbol, Numeric]? -- Click offset from element center
      # @rbs return: void
      def click(selector, button: Mouse::LEFT, count: 1, delay: nil, offset: nil)
        main_frame.click(selector, button: button, count: count, delay: delay, offset: offset)
      end

      # Type text into an element matching the selector
      # @rbs selector: String -- Selector to type into
      # @rbs text: String -- Text to type
      # @rbs delay: Numeric -- Delay between key presses in ms
      # @rbs return: void
      def type(selector, text, delay: 0)
        main_frame.type(selector, text, delay: delay)
      end

      # Hover over an element matching the selector
      # @rbs selector: String -- Selector to hover
      # @rbs return: void
      def hover(selector)
        main_frame.hover(selector)
      end

      # Select options on a <select> element matching the selector
      # Triggers 'change' and 'input' events once all options are selected.
      # @rbs selector: String -- Selector for <select> element
      # @rbs *values: String -- Option values to select
      # @rbs return: Array[String] -- Actually selected option values
      def select(selector, *values)
        main_frame.select(selector, *values)
      end

      # Focus an element matching the selector
      # @rbs selector: String -- Selector to focus
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
      # @rbs return: String -- Page title
      def title
        evaluate('document.title')
      end

      # Get the page URL
      # @rbs return: String -- Page URL
      def url
        @browsing_context.url
      end

      # Get the full HTML contents of the page, including the DOCTYPE.
      # @rbs return: String -- Full HTML contents
      def content
        assert_not_closed

        # Port of Puppeteer's Frame.content().
        # https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/api/Frame.ts
        main_frame.evaluate(<<~JS)
          () => {
            let content = '';
            for (const node of document.childNodes) {
              switch (node) {
                case document.documentElement:
                  content += document.documentElement.outerHTML;
                  break;
                default:
                  content += new XMLSerializer().serializeToString(node);
                  break;
              }
            }
            return content;
          }
        JS
      end

      # Close the page
      # @rbs return: void
      def close
        return if closed?

        @browsing_context.close.wait
      end

      # Check if page is closed
      # @rbs return: bool -- Whether page is closed
      def closed?
        @browsing_context.closed?
      end

      # Get the main frame
      # @rbs return: Frame -- Main frame
      def main_frame
        @main_frame ||= Frame.from(self, @browsing_context)
      end

      # Reloads the page.
      # @rbs timeout: Numeric -- Navigation timeout in ms
      # @rbs wait_until: String | Array[String] -- When to consider navigation complete
      # @rbs ignore_cache: bool -- Whether to ignore the browser cache
      # @rbs return: HTTPResponse? -- Response or nil
      def reload(timeout: 30000, wait_until: 'load', ignore_cache: false)
        assert_not_closed

        reload_options = {}
        reload_options[:ignoreCache] = true if ignore_cache

        wait_for_navigation(timeout: timeout, wait_until: wait_until) do
          @browsing_context.reload(**reload_options).wait
        end
      end

      # Enable or disable request interception.
      # @rbs enable: bool -- Whether to enable interception
      # @rbs return: void
      def set_request_interception(enable)
        assert_not_closed

        @request_interception = toggle_interception(
          ["beforeRequestSent"],
          @request_interception,
          enable,
        )
      end

      # Set extra HTTP headers for the page.
      # @rbs headers: Hash[String, String] -- Extra headers
      # @rbs return: void
      def set_extra_http_headers(headers)
        assert_not_closed

        normalized = {}
        headers.each do |key, value|
          normalized[key.to_s] = value.to_s
        end
        @browsing_context.set_extra_http_headers(normalized).wait
      end

      # Authenticate to HTTP Basic auth challenges.
      # @rbs credentials: Hash[Symbol, String]? -- Credentials (username/password) or nil to disable
      # @rbs return: void
      def authenticate(credentials)
        assert_not_closed

        @auth_interception = toggle_interception(
          ["authRequired"],
          @auth_interception,
          !credentials.nil?,
        )

        @credentials = credentials
      end

      # Enable or disable cache.
      # @rbs enabled: bool -- Whether to enable cache
      # @rbs return: void
      def set_cache_enabled(enabled)
        assert_not_closed

        @browsing_context.set_cache_behavior(enabled ? "default" : "bypass").wait
      end

      # Get the focused frame
      # @rbs return: Frame -- Focused frame
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
      # @rbs return: Array[Frame] -- All frames
      def frames
        collect_frames(main_frame)
      end

      # Get the mouse instance
      # @rbs return: Mouse -- Mouse instance
      def mouse
        @mouse ||= Mouse.new(@browsing_context)
      end

      # Get the keyboard instance
      # @rbs return: Keyboard -- Keyboard instance
      def keyboard
        @keyboard ||= Keyboard.new(self, @browsing_context)
      end

      # Wait for a function to return a truthy value
      # @rbs page_function: String -- JavaScript function to evaluate
      # @rbs options: Hash[Symbol, untyped] -- Wait options (timeout, polling)
      # @rbs *args: untyped -- Arguments to pass to the function
      # @rbs &block: ((JSHandle) -> void)? -- Optional block called with result
      # @rbs return: JSHandle -- Handle to the truthy result
      def wait_for_function(page_function, options = {}, *args, &block)
        main_frame.wait_for_function(page_function, options, *args, &block)
      end

      # Wait for an element matching the selector to appear in the page
      # @rbs selector: String -- Selector to wait for
      # @rbs visible: bool? -- Wait for element to be visible
      # @rbs hidden: bool? -- Wait for element to be hidden
      # @rbs timeout: Numeric? -- Wait timeout in ms
      # @rbs &block: ((ElementHandle?) -> void)? -- Optional block called with element
      # @rbs return: ElementHandle? -- Element or nil if hidden
      def wait_for_selector(selector, visible: nil, hidden: nil, timeout: nil, &block)
        main_frame.wait_for_selector(selector, visible: visible, hidden: hidden, timeout: timeout, &block)
      end

      # Set the default timeout for waiting operations (e.g., waitForFunction).
      # @rbs timeout: Numeric -- Timeout in ms
      # @rbs return: void
      def set_default_timeout(timeout)
        raise ArgumentError, 'timeout must be a non-negative number' unless timeout.is_a?(Numeric) && timeout >= 0

        @timeout_settings.set_default_timeout(timeout)
      end

      # Get the current default timeout in milliseconds.
      # @rbs return: Numeric -- Timeout in ms
      def default_timeout
        @timeout_settings.timeout
      end

      # Wait for navigation to complete
      # @rbs timeout: Numeric -- Navigation timeout in ms
      # @rbs wait_until: String -- When to consider navigation complete
      # @rbs &block: (-> void)? -- Optional block to trigger navigation
      # @rbs return: HTTPResponse? -- Response or nil
      def wait_for_navigation(timeout: 30000, wait_until: 'load', &block)
        main_frame.wait_for_navigation(timeout: timeout, wait_until: wait_until, &block)
      end

      # Wait for a request that matches a URL or predicate.
      # @rbs url_or_predicate: String | ^(HTTPRequest) -> boolish -- URL or predicate
      # @rbs timeout: Numeric? -- Timeout in ms (0 for infinite)
      # @rbs &block: (-> void)? -- Optional block to trigger the request
      # @rbs return: HTTPRequest
      def wait_for_request(url_or_predicate, timeout: nil, &block)
        assert_not_closed

        timeout_ms = timeout.nil? ? @timeout_settings.timeout : timeout
        predicate = if url_or_predicate.is_a?(Proc)
                      url_or_predicate
                    else
                      ->(request) { request.url == url_or_predicate }
                    end

        promise = Async::Promise.new
        listener = proc do |request|
          next unless predicate.call(request)

          promise.resolve(request) unless promise.resolved?
        end

        begin
          on(:request, &listener)
          Async(&block).wait if block

          if timeout_ms == 0
            promise.wait
          else
            AsyncUtils.async_timeout(timeout_ms, promise).wait
          end
        ensure
          off(:request, &listener)
        end
      end

      # Wait for a response that matches a URL or predicate.
      # @rbs url_or_predicate: String | ^(HTTPResponse) -> boolish -- URL or predicate
      # @rbs timeout: Numeric? -- Timeout in ms (0 for infinite)
      # @rbs &block: (-> void)? -- Optional block to trigger the response
      # @rbs return: HTTPResponse
      def wait_for_response(url_or_predicate, timeout: nil, &block)
        assert_not_closed

        timeout_ms = timeout.nil? ? @timeout_settings.timeout : timeout
        predicate = if url_or_predicate.is_a?(Proc)
                      url_or_predicate
                    else
                      ->(response) { response.url == url_or_predicate }
                    end

        promise = Async::Promise.new
        listener = proc do |response|
          next unless predicate.call(response)

          promise.resolve(response) unless promise.resolved?
        end

        begin
          on(:response, &listener)
          Async(&block).wait if block

          if timeout_ms == 0
            promise.wait
          else
            AsyncUtils.async_timeout(timeout_ms, promise).wait
          end
        ensure
          off(:response, &listener)
        end
      end

      # Retrieve cookies for the current page.
      # @rbs *urls: Array[String] -- URLs to filter cookies by
      # @rbs return: Array[Hash[String, untyped]]
      def cookies(*urls)
        assert_not_closed

        normalized_urls = (urls.empty? ? [url] : urls).map do |cookie_url|
          parse_cookie_url_strict(cookie_url)
        end

        @browsing_context.get_cookies.wait
                         .map { |cookie| CookieUtils.bidi_to_puppeteer_cookie(cookie) }
                         .select do |cookie|
                           normalized_urls.any? do |normalized_url|
                             CookieUtils.test_url_match_cookie(cookie, normalized_url)
                           end
                         end
      end

      # Set cookies for the current page.
      # @rbs *cookies: Array[Hash[String, untyped]] -- Cookie data
      # @rbs **cookie: untyped -- Single cookie via keyword arguments
      # @rbs return: void
      def set_cookie(*cookies, **cookie)
        assert_not_closed

        cookies = cookies.dup
        cookies << cookie unless cookie.empty?

        page_url = url
        page_url_starts_with_http = page_url&.start_with?("http")

        cookies.each do |raw_cookie|
          normalized_cookie = CookieUtils.normalize_cookie_input(raw_cookie)
          cookie_url = normalized_cookie["url"].to_s
          if cookie_url.empty? && page_url_starts_with_http
            cookie_url = page_url
          end

          if cookie_url == "about:blank"
            raise ArgumentError, "Blank page can not have cookie \"#{normalized_cookie["name"]}\""
          end
          if cookie_url.start_with?("data:")
            raise ArgumentError, "Data URL page can not have cookie \"#{normalized_cookie["name"]}\""
          end

          partition_key = normalized_cookie["partitionKey"]
          if !partition_key.nil? && !partition_key.is_a?(String)
            raise ArgumentError, "BiDi only allows domain partition keys"
          end

          normalized_url = parse_cookie_url(cookie_url)
          domain = normalized_cookie["domain"] || normalized_url&.host
          if domain.nil?
            raise ArgumentError, "At least one of the url and domain needs to be specified"
          end

          bidi_cookie = {
            "domain" => domain,
            "name" => normalized_cookie["name"],
            "value" => { "type" => "string", "value" => normalized_cookie["value"] },
          }
          bidi_cookie["path"] = normalized_cookie["path"] if normalized_cookie.key?("path")
          bidi_cookie["httpOnly"] = normalized_cookie["httpOnly"] if normalized_cookie.key?("httpOnly")
          bidi_cookie["secure"] = normalized_cookie["secure"] if normalized_cookie.key?("secure")
          if normalized_cookie.key?("sameSite") && !normalized_cookie["sameSite"].nil?
            bidi_cookie["sameSite"] = CookieUtils.convert_cookies_same_site_cdp_to_bidi(
              normalized_cookie["sameSite"]
            )
          end
          expiry = CookieUtils.convert_cookies_expiry_cdp_to_bidi(normalized_cookie["expires"])
          bidi_cookie["expiry"] = expiry unless expiry.nil?
          bidi_cookie.merge!(CookieUtils.cdp_specific_cookie_properties_from_puppeteer_to_bidi(
                               normalized_cookie,
                               "sameParty",
                               "sourceScheme",
                               "priority",
                               "url"
                             ))

          if partition_key
            @browser_context.user_context.set_cookie(bidi_cookie, source_origin: partition_key).wait
          else
            @browsing_context.set_cookie(bidi_cookie).wait
          end
        end
      end

      # Delete cookies from the current page.
      # @rbs *cookies: Array[Hash[String, untyped]] -- Cookie filters
      # @rbs **cookie: untyped -- Single cookie filter via keyword arguments
      # @rbs return: void
      def delete_cookie(*cookies, **cookie)
        assert_not_closed

        cookies = cookies.dup
        cookies << cookie unless cookie.empty?

        page_url = url

        tasks = cookies.map do |raw_cookie|
          normalized_cookie = CookieUtils.normalize_cookie_input(raw_cookie)
          cookie_url = normalized_cookie["url"] || page_url
          normalized_url = parse_cookie_url(cookie_url.to_s)
          domain = normalized_cookie["domain"] || normalized_url&.host
          if domain.nil?
            raise ArgumentError, "At least one of the url and domain needs to be specified"
          end

          filter = {
            "domain" => domain,
            "name" => normalized_cookie["name"],
          }
          filter["path"] = normalized_cookie["path"] if normalized_cookie.key?("path")

          -> { @browsing_context.delete_cookie(filter).wait }
        end

        AsyncUtils.await_promise_all(*tasks) unless tasks.empty?
      end

      # Wait for a file chooser to be opened
      # @rbs timeout: Numeric? -- Wait timeout in ms
      # @rbs &block: (-> void)? -- Optional block to trigger file chooser
      # @rbs return: FileChooser -- File chooser instance
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
      # @rbs idle_time: Numeric -- Time to wait for idle in ms
      # @rbs timeout: Numeric -- Wait timeout in ms
      # @rbs concurrency: Integer -- Max allowed inflight requests
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
      # @rbs width: Integer -- Viewport width in pixels
      # @rbs height: Integer -- Viewport height in pixels
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

      # Set geolocation override
      # @rbs longitude: Numeric -- Longitude between -180 and 180
      # @rbs latitude: Numeric -- Latitude between -90 and 90
      # @rbs accuracy: Numeric? -- Non-negative accuracy value
      # @rbs return: void
      def set_geolocation(longitude:, latitude:, accuracy: nil)
        assert_not_closed

        if longitude < -180 || longitude > 180
          raise ArgumentError, "Invalid longitude \"#{longitude}\": precondition -180 <= LONGITUDE <= 180 failed."
        end
        if latitude < -90 || latitude > 90
          raise ArgumentError, "Invalid latitude \"#{latitude}\": precondition -90 <= LATITUDE <= 90 failed."
        end
        accuracy_value = accuracy.nil? ? 0 : accuracy
        if accuracy_value < 0
          raise ArgumentError, "Invalid accuracy \"#{accuracy_value}\": precondition 0 <= ACCURACY failed."
        end

        coordinates = {
          latitude: latitude,
          longitude: longitude
        }
        coordinates[:accuracy] = accuracy unless accuracy.nil?

        @browsing_context.set_geolocation_override(
          coordinates: coordinates
        ).wait
      end

      # Set user agent
      # @rbs user_agent: String? -- User agent string or nil to restore original
      # @rbs user_agent_metadata: Hash[Symbol, untyped]? -- Not supported in BiDi-only mode
      # @rbs return: void
      def set_user_agent(user_agent, user_agent_metadata = nil)
        assert_not_closed

        if user_agent.is_a?(Hash)
          raise UnsupportedOperationError, "options hash is not supported in BiDi-only mode"
        end

        if user_agent_metadata
          raise UnsupportedOperationError, "userAgentMetadata is not supported in BiDi-only mode"
        end

        user_agent = nil if user_agent == ""
        @browsing_context.set_user_agent(user_agent).wait
      end

      # Get current viewport size
      # @rbs return: Hash[Symbol, Integer]? -- Viewport dimensions
      def viewport
        @viewport
      end

      alias viewport= set_viewport
      alias default_timeout= set_default_timeout

      # Set JavaScript enabled state
      # @rbs enabled: bool -- Whether JavaScript is enabled
      # @rbs return: void
      def set_javascript_enabled(enabled)
        assert_not_closed
        @browsing_context.set_javascript_enabled(enabled).wait
      end

      # Check if JavaScript is enabled
      # @rbs return: bool -- Whether JavaScript is enabled
      def javascript_enabled?
        @browsing_context.javascript_enabled?
      end

      # Navigate backward in history
      # @rbs wait_until: String -- When to consider navigation complete
      # @rbs timeout: Numeric -- Navigation timeout in ms
      # @rbs return: HTTPResponse? -- Response or nil
      def go_back(wait_until: 'load', timeout: 30000)
        go(-1, wait_until: wait_until, timeout: timeout)
      end

      # Navigate forward in history
      # @rbs wait_until: String -- When to consider navigation complete
      # @rbs timeout: Numeric -- Navigation timeout in ms
      # @rbs return: HTTPResponse? -- Response or nil
      def go_forward(wait_until: 'load', timeout: 30000)
        go(1, wait_until: wait_until, timeout: timeout)
      end

      private

      # Navigate history by delta.
      #
      # In Firefox, BFCache restores may emit `browsingContext.navigationStarted`
      # without firing `domContentLoaded` / `load`. We treat such navigations as
      # completed if we don't observe a navigation request shortly after start.
      # @rbs delta: Integer -- Steps to go back (negative) or forward (positive)
      # @rbs wait_until: String -- When to consider navigation complete
      # @rbs timeout: Numeric -- Navigation timeout in ms
      # @rbs return: HTTPResponse? -- Response or nil
      def go(delta, wait_until:, timeout:)
        assert_not_closed

        load_event = wait_until == 'domcontentloaded' ? :dom_content_loaded : :load

        started_promise = Async::Promise.new
        load_promise = Async::Promise.new
        navigation_request_promise = Async::Promise.new

        navigation_id = nil
        navigation_url = nil

        session = @browsing_context.user_context.browser.session

        history_listener = proc do
          started_promise.resolve(:history_updated) unless started_promise.resolved?
        end

        fragment_listener = proc do
          started_promise.resolve(:fragment_navigated) unless started_promise.resolved?
        end

        nav_started_listener = proc do |info|
          next unless info['context'] == @browsing_context.id

          navigation_id = info['navigation']
          navigation_url = info['url']
          started_promise.resolve(:navigation_started) unless started_promise.resolved?
        end

        request_listener = proc do |data|
          request = data[:request]
          next unless navigation_id
          next unless request&.navigation == navigation_id

          navigation_request_promise.resolve(nil) unless navigation_request_promise.resolved?
        end

        load_listener = proc do
          load_promise.resolve(nil) unless load_promise.resolved?
        end

        closed_listener = proc do
          started_promise.reject(PageClosedError.new) unless started_promise.resolved?
        end

        begin
          session.on('browsingContext.navigationStarted', &nav_started_listener)
          @browsing_context.on(:history_updated, &history_listener)
          @browsing_context.on(:fragment_navigated, &fragment_listener)
          @browsing_context.on(:request, &request_listener)
          @browsing_context.once(load_event, &load_listener)
          @browsing_context.once(:closed, &closed_listener)

          @browsing_context.traverse_history(delta).wait
        rescue Connection::ProtocolError => e
          # "History entry with delta X not found" - at history edge
          return nil if e.message.include?('not found')
          raise
        end

        begin
          # If nothing starts soon, assume we're at the history edge.
          start_timeout_ms = [timeout.to_i, 500].min
          start_type = AsyncUtils.async_timeout(start_timeout_ms, started_promise).wait
        rescue Async::TimeoutError
          return nil
        end

        case start_type
        when :history_updated, :fragment_navigated
          nil
        when :navigation_started
          # Determine BFCache restore (no navigation request) vs full navigation.
          begin
            AsyncUtils.async_timeout(200, navigation_request_promise).wait

            begin
              AsyncUtils.async_timeout(timeout, load_promise).wait
            rescue Async::TimeoutError
              raise Puppeteer::Bidi::TimeoutError, "Navigation timeout of #{timeout}ms exceeded"
            end

            HTTPResponse.for_bfcache(url: @browsing_context.url)
          rescue Async::TimeoutError
            # No navigation request observed: treat as BFCache restore.
            @browsing_context.instance_variable_set(:@url, navigation_url) if navigation_url
            @browsing_context.navigation&.dispose unless @browsing_context.navigation&.disposed?

            HTTPResponse.for_bfcache(url: navigation_url || @browsing_context.url)
          end
        else
          nil
        end
      ensure
        session.off('browsingContext.navigationStarted', &nav_started_listener)
        @browsing_context.off(:history_updated, &history_listener)
        @browsing_context.off(:fragment_navigated, &fragment_listener)
        @browsing_context.off(:request, &request_listener)
        @browsing_context.off(load_event, &load_listener)
        @browsing_context.off(:closed, &closed_listener)
      end

      # Recursively collect all frames starting from the given frame
      # @rbs frame: Frame -- Starting frame
      # @rbs return: Array[Frame] -- All frames in subtree
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

      # @rbs cookie_url: String -- Cookie URL
      # @rbs return: URI::Generic? -- Parsed URL or nil
      def parse_cookie_url(cookie_url)
        return nil if cookie_url.nil? || cookie_url.empty?

        URI.parse(cookie_url)
      rescue URI::InvalidURIError
        nil
      end

      def parse_cookie_url_strict(cookie_url)
        normalized_url = URI.parse(cookie_url.to_s)
        if normalized_url.scheme.nil? ||
           (normalized_url.scheme.match?(/\Ahttps?\z/i) && normalized_url.host.to_s.empty?)
          raise ArgumentError, "Invalid URL"
        end
        normalized_url
      rescue URI::InvalidURIError
        raise ArgumentError, "Invalid URL"
      end

      def toggle_interception(phases, interception, expected)
        if expected && interception.nil?
          return @browsing_context.add_intercept(phases: phases).wait
        end
        if !expected && interception
          @browsing_context.user_context.browser.remove_intercept(interception).wait
          return nil
        end
        interception
      end
    end
  end
end

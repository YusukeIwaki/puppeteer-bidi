# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # Frame represents a frame (main frame or iframe) in the page
    # This is a high-level wrapper around Core::BrowsingContext
    # Following Puppeteer's BidiFrame implementation
    class Frame
      attr_reader :browsing_context #: Core::BrowsingContext

      # Factory method following Puppeteer's BidiFrame.from pattern
      # @rbs parent: Page | Frame -- Parent page or frame
      # @rbs browsing_context: Core::BrowsingContext -- Associated browsing context
      # @rbs return: Frame -- New frame instance
      def self.from(parent, browsing_context)
        frame = new(parent, browsing_context)
        frame.send(:initialize_frame)
        frame
      end

      # @rbs parent: Page | Frame -- Parent page or frame
      # @rbs browsing_context: Core::BrowsingContext -- Associated browsing context
      # @rbs return: void
      def initialize(parent, browsing_context)
        @parent = parent
        @browsing_context = browsing_context
        @frames = {} # Map of browsing context id to Frame (like WeakMap in JS)
        @exposed_functions = {} # Map of function name to ExposedFunction

        default_core_realm = @browsing_context.default_realm
        internal_core_realm = @browsing_context.create_window_realm("__puppeteer_internal_#{rand(1..10_000)}")

        @main_realm = FrameRealm.new(self, default_core_realm)
        @isolated_realm = FrameRealm.new(self, internal_core_realm)
      end

      # @rbs return: FrameRealm -- Main execution realm
      def main_realm
        @main_realm
      end

      # @rbs return: FrameRealm -- Isolated execution realm
      def isolated_realm
        @isolated_realm
      end

      # Backwards compatibility for call sites that previously accessed Frame#realm.
      # @rbs return: FrameRealm -- Main execution realm
      def realm
        main_realm
      end

      # Get the page that owns this frame
      # Traverses up the parent chain until reaching a Page
      # @rbs return: Page -- Owning page
      def page
        @parent.is_a?(Page) ? @parent : @parent.page
      end

      # Get the parent frame
      # @rbs return: Frame? -- Parent frame or nil for main frame
      def parent_frame
        @parent.is_a?(Frame) ? @parent : nil
      end

      # Evaluate JavaScript in the frame context
      # @rbs script: String -- JavaScript code to evaluate
      # @rbs *args: untyped -- Arguments to pass to the script
      # @rbs return: untyped -- Evaluation result
      def evaluate(script, *args)
        assert_not_detached
        main_realm.evaluate(script, *args)
      end

      # Evaluate JavaScript and return a handle to the result
      # @rbs script: String -- JavaScript code to evaluate
      # @rbs *args: untyped -- Arguments to pass to the script
      # @rbs return: JSHandle -- Handle to the result
      def evaluate_handle(script, *args)
        assert_not_detached
        main_realm.evaluate_handle(script, *args)
      end

      # Get the document element handle
      # @rbs return: ElementHandle -- Document element handle
      def document
        assert_not_detached
        handle = main_realm.evaluate_handle('document')
        unless handle.is_a?(ElementHandle)
          handle.dispose
          raise 'Failed to get document'
        end
        handle
      end

      # Query for an element matching the selector
      # @rbs selector: String -- Selector to query
      # @rbs return: ElementHandle? -- Matching element or nil
      def query_selector(selector)
        doc = document
        begin
          doc.query_selector(selector)
        ensure
          doc.dispose
        end
      end

      # Query for all elements matching the selector
      # @rbs selector: String -- Selector to query
      # @rbs return: Array[ElementHandle] -- All matching elements
      def query_selector_all(selector)
        doc = document
        begin
          doc.query_selector_all(selector)
        ensure
          doc.dispose
        end
      end

      # Create a locator for a selector or function.
      # @rbs selector: String? -- Selector to locate
      # @rbs function: String? -- JavaScript function for function locator
      # @rbs return: Locator -- Locator instance
      def locator(selector = nil, function: nil)
        assert_not_detached

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
        doc = document
        begin
          doc.eval_on_selector(selector, page_function, *args)
        ensure
          doc.dispose
        end
      end

      # Evaluate a function on all elements matching the selector
      # @rbs selector: String -- Selector to query
      # @rbs page_function: String -- JavaScript function to evaluate
      # @rbs *args: untyped -- Arguments to pass to the function
      # @rbs return: untyped -- Evaluation result
      def eval_on_selector_all(selector, page_function, *args)
        doc = document
        begin
          doc.eval_on_selector_all(selector, page_function, *args)
        ensure
          doc.dispose
        end
      end

      # Click an element matching the selector
      # @rbs selector: String -- Selector to click
      # @rbs button: String -- Mouse button ('left', 'right', 'middle')
      # @rbs count: Integer -- Number of clicks
      # @rbs delay: Numeric? -- Delay between clicks in ms
      # @rbs offset: Hash[Symbol, Numeric]? -- Click offset from element center
      # @rbs return: void
      def click(selector, button: 'left', count: 1, delay: nil, offset: nil)
        assert_not_detached

        handle = query_selector(selector)
        raise SelectorNotFoundError, selector unless handle

        begin
          handle.click(button: button, count: count, delay: delay, offset: offset)
        ensure
          handle.dispose
        end
      end

      # Type text into an element matching the selector
      # @rbs selector: String -- Selector to type into
      # @rbs text: String -- Text to type
      # @rbs delay: Numeric -- Delay between key presses in ms
      # @rbs return: void
      def type(selector, text, delay: 0)
        assert_not_detached

        handle = query_selector(selector)
        raise SelectorNotFoundError, selector unless handle

        begin
          handle.type(text, delay: delay)
        ensure
          handle.dispose
        end
      end

      # Hover over an element matching the selector
      # @rbs selector: String -- Selector to hover
      # @rbs return: void
      def hover(selector)
        assert_not_detached

        handle = query_selector(selector)
        raise SelectorNotFoundError, selector unless handle

        begin
          handle.hover
        ensure
          handle.dispose
        end
      end

      # Select options on a <select> element matching the selector
      # Triggers 'change' and 'input' events once all options are selected.
      # @rbs selector: String -- Selector for <select> element
      # @rbs *values: String -- Option values to select
      # @rbs return: Array[String] -- Actually selected option values
      def select(selector, *values)
        assert_not_detached

        handle = query_selector(selector)
        raise SelectorNotFoundError, selector unless handle

        begin
          handle.select(*values)
        ensure
          handle.dispose
        end
      end

      # Get the frame URL
      # @rbs return: String -- Current URL
      def url
        @browsing_context.url
      end

      # Navigate to a URL
      # @rbs url: String -- URL to navigate to
      # @rbs wait_until: String -- When to consider navigation complete ('load', 'domcontentloaded')
      # @rbs timeout: Numeric? -- Navigation timeout in ms (0 for infinite)
      # @rbs return: HTTPResponse? -- Response or nil
      def goto(url, wait_until: 'load', timeout: nil)
        response = wait_for_navigation(timeout: timeout, wait_until: wait_until) do
          @browsing_context.navigate(url, wait: 'interactive').wait
        end
        response
      end

      # Set frame content
      # @rbs html: String -- HTML content to set
      # @rbs wait_until: String | Array[String] -- Lifecycle events to wait for ('load', 'domcontentloaded')
      # @rbs timeout: Numeric? -- Timeout in ms (0 for infinite)
      # @rbs return: void
      def set_content(html, wait_until: 'load', timeout: nil)
        assert_not_detached

        wait_until_values = wait_until.is_a?(Array) ? wait_until : [wait_until]
        unsupported_value = wait_until_values.find do |value|
          !%w[load domcontentloaded].include?(value)
        end
        raise ArgumentError, "Unknown wait_until value: #{unsupported_value}" if unsupported_value

        events = wait_until_values.uniq.map do |value|
          value == 'load' ? :load : :dom_content_loaded
        end
        listeners = []
        promises = events.map do |event|
          promise = Async::Promise.new
          listener = proc { promise.resolve(nil) }
          @browsing_context.once(event, &listener)
          listeners << [event, listener]
          promise
        end

        timeout_ms = timeout.nil? ? page.timeout_settings.navigation_timeout : timeout
        operation = lambda do
          AsyncUtils.await_promise_all(
            -> { set_frame_content(html) },
            *promises
          )
        end

        if timeout_ms == 0
          operation.call
        else
          AsyncUtils.async_timeout(timeout_ms, operation).wait
        end

        nil
      rescue Async::TimeoutError
        raise Puppeteer::Bidi::TimeoutError, "Navigation timeout of #{timeout_ms} ms exceeded"
      ensure
        listeners&.each do |event, listener|
          @browsing_context.off(event, &listener)
        end
      end

      # Set frame content using document.open/write/close
      # This is a low-level method that doesn't wait for load events
      # @rbs content: String -- HTML content to set
      # @rbs return: void
      def set_frame_content(content)
        assert_not_detached

        evaluate(<<~JS, content)
          html => {
            document.open();
            document.write(html);
            document.close();
          }
        JS
      end

      # Get the full HTML contents of the frame, including the DOCTYPE
      # @rbs return: String -- Full HTML content
      def content
        assert_not_detached

        evaluate(<<~JS)
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

      # Get the frame name
      # @rbs return: String -- Frame name
      def name
        @_name || ''
      end

      # Check if frame is detached
      # @rbs return: bool -- Whether frame is detached
      def detached?
        @browsing_context.closed?
      end

      # Get child frames
      # Returns cached frame instances following Puppeteer's pattern
      # @rbs return: Array[Frame] -- Child frames
      def child_frames
        @browsing_context.children.map do |child_context|
          @frames[child_context.id]
        end.compact
      end

      # Get the frame element (iframe/frame DOM element) for this frame
      # Returns nil for the main frame
      # Following Puppeteer's WebDriver BiDi frameElement() implementation.
      # @rbs return: ElementHandle? -- Frame element or nil for main frame
      def frame_element
        assert_not_detached

        parent = parent_frame
        return nil unless parent

        nodes = parent.browsing_context.locate_nodes(
          { type: 'context', value: { context: @browsing_context.id } }
        ).wait
        node = nodes.first
        return nil unless node

        ElementHandle.from(node, parent.main_realm.core_realm)
      end

      # Wait for navigation to complete
      # @rbs timeout: Numeric? -- Navigation timeout in ms (0 for infinite)
      # @rbs wait_until: String | Array[String] -- When to consider navigation complete
      # @rbs &block: (-> void)? -- Optional block to trigger navigation
      # @rbs return: HTTPResponse? -- Response or nil
      def wait_for_navigation(timeout: nil, wait_until: 'load', &block)
        assert_not_detached

        navigation_timeout_ms = timeout || page.timeout_settings.navigation_timeout

        # Normalize wait_until to array
        wait_until_array = wait_until.is_a?(Array) ? wait_until : [wait_until]

        # Separate lifecycle events from network idle events
        lifecycle_events = wait_until_array.select { |e| ['load', 'domcontentloaded'].include?(e) }
        network_idle_events = wait_until_array.select { |e| ['networkidle0', 'networkidle2'].include?(e) }

        # Only wait for lifecycle events if explicitly requested (matches Puppeteer)
        load_event = case lifecycle_events.first
                     when 'load'
                       :load
                     when 'domcontentloaded'
                       :dom_content_loaded
                     else
                       nil
                     end

        # Use Async::Promise for signaling (Fiber-based, not Thread-based)
        # This avoids race conditions and follows Puppeteer's Promise-based pattern
        promise = Async::Promise.new

        # Track navigation type for response creation
        navigation_type = nil  # :full_page, :fragment, or :history
        navigation_obj = nil  # The navigation object we're waiting for
        load_listener_registered = false

        # Define load_listener upfront to satisfy type checker
        load_listener = proc do
          promise.resolve(:full_page) unless promise.resolved?
        end

        # Helper to set up navigation listeners
        setup_navigation_listeners = proc do |navigation|
          navigation_obj = navigation
          navigation_type = :full_page

          # Set up listeners for navigation completion
          # Listen for fragment, failed, aborted events
          navigation.once(:fragment) do
            promise.resolve(nil) unless promise.resolved?
          end

          navigation.once(:failed) do
            promise.resolve(nil) unless promise.resolved?
          end

          navigation.once(:aborted) do
            next if detached?
            promise.resolve(nil) unless promise.resolved?
          end

          # Also listen for load/domcontentloaded events to complete navigation
          if load_event
            unless load_listener_registered
              @browsing_context.once(load_event, &load_listener)
              load_listener_registered = true
            end
          else
            # No lifecycle events requested; resolve once navigation is observed.
            promise.resolve(:full_page) unless promise.resolved?
          end
        end

        # Listen for navigation events from BrowsingContext
        # This follows Puppeteer's pattern: race between 'navigation', 'historyUpdated', and 'fragmentNavigated'
        navigation_listener = proc do |navigation|
          # Only handle if we haven't already attached to a navigation
          next if navigation_obj

          setup_navigation_listeners.call(navigation)
        end

        history_listener = proc do
          # History API navigations (without Navigation object)
          # Only resolve if we haven't attached to a navigation
          promise.resolve(nil) unless navigation_obj || promise.resolved?
        end

        fragment_listener = proc do
          # Fragment navigations (anchor links, hash changes)
          # Only resolve if we haven't attached to a navigation
          promise.resolve(nil) unless navigation_obj || promise.resolved?
        end

        closed_listener = proc do
          # Handle frame detachment by rejecting the promise
          promise.reject(FrameDetachedError.new('Navigating frame was detached')) unless promise.resolved?
        end

        @browsing_context.on(:navigation, &navigation_listener)
        @browsing_context.on(:history_updated, &history_listener)
        @browsing_context.on(:fragment_navigated, &fragment_listener)
        @browsing_context.once(:closed, &closed_listener)

        begin
          # CRITICAL: Check for existing navigation BEFORE executing block
          # This follows Puppeteer's pattern where waitForNavigation can attach to
          # an already-started navigation (e.g., when called after goto)
          existing_nav = @browsing_context.navigation
          if existing_nav && !existing_nav.disposed?
            # Attach to the existing navigation
            setup_navigation_listeners.call(existing_nav)
          end

          # Execute the block if provided (this may trigger navigation)
          # Block executes in the same Fiber context for cooperative multitasking
          Async(&block).wait if block

          # Wait for navigation with timeout using Async (Fiber-based)
          if network_idle_events.any?
            # Puppeteer's pattern: wait for both navigation completion AND network idle
            # Determine concurrency based on network idle event
            concurrency = network_idle_events.include?('networkidle0') ? 0 : 2

            # Wait for both navigation and network idle in parallel using promise_all
            if navigation_timeout_ms == 0
              navigation_result, _ = AsyncUtils.await_promise_all(
                promise,
                -> { page.wait_for_network_idle(idle_time: 500, timeout: timeout, concurrency: concurrency) }
              )
            else
              navigation_result, _ = AsyncUtils.async_timeout(navigation_timeout_ms, -> do
                AsyncUtils.await_promise_all(
                  promise,
                  -> { page.wait_for_network_idle(idle_time: 500, timeout: timeout, concurrency: concurrency) }
                )
              end).wait
            end

            result = navigation_result
          else
            # Only wait for navigation
            result = if navigation_timeout_ms == 0
                       promise.wait
                     else
                       AsyncUtils.async_timeout(navigation_timeout_ms, promise).wait
                     end
          end

          # Return HTTPResponse for full page navigation, nil for fragment/history
          return nil unless result == :full_page

          navigation_response_for(navigation_obj)
        rescue Async::TimeoutError
          raise Puppeteer::Bidi::TimeoutError, "Navigation timeout of #{navigation_timeout_ms} ms exceeded"
        ensure
          # Clean up listeners
          @browsing_context.off(:navigation, &navigation_listener)
          @browsing_context.off(:history_updated, &history_listener)
          @browsing_context.off(:fragment_navigated, &fragment_listener)
          @browsing_context.off(:closed, &closed_listener)
          @browsing_context.off(load_event, &load_listener) if load_listener_registered
        end
      end

      # Wait for a function to return a truthy value
      # @rbs page_function: String -- JavaScript function to evaluate
      # @rbs options: Hash[Symbol, untyped] -- Wait options (timeout, polling)
      # @rbs *args: untyped -- Arguments to pass to the function
      # @rbs &block: ((JSHandle) -> void)? -- Optional block called with result
      # @rbs return: JSHandle -- Handle to the truthy result
      def wait_for_function(page_function, options = {}, *args, &block)
        main_realm.wait_for_function(page_function, options, *args, &block)
      end

      # Wait for an element matching the selector to appear in the frame
      # @rbs selector: String -- Selector to wait for
      # @rbs visible: bool? -- Wait for element to be visible
      # @rbs hidden: bool? -- Wait for element to be hidden
      # @rbs timeout: Numeric? -- Wait timeout in ms
      # @rbs &block: ((ElementHandle?) -> void)? -- Optional block called with element
      # @rbs return: ElementHandle? -- Element or nil if hidden
      def wait_for_selector(selector, visible: nil, hidden: nil, timeout: nil, &block)
        result = QueryHandler.instance.get_query_handler_and_selector(selector)
        result.query_handler.new.wait_for(self, result.updated_selector, visible: visible, hidden: hidden, polling: result.polling, timeout: timeout, &block)
      end

      # Set files on an input element
      # @rbs element: ElementHandle -- Input element
      # @rbs files: Array[String] -- File paths to set
      # @rbs return: void
      def set_files(element, files)
        assert_not_detached

        @browsing_context.set_files(
          element.remote_value_as_shared_reference,
          files
        ).wait
      end

      # Expose a Ruby callable as a function in the frame's global context.
      # The function persists across navigations.
      # @rbs name: String -- Function name to expose on globalThis
      # @rbs apply: Proc? -- Ruby callable to execute when function is called
      # @rbs &block: ?{ (*untyped) -> untyped } -- Ruby block to execute when function is called
      # @rbs return: void
      def expose_function(name, apply = nil, &block)
        assert_not_detached

        if @exposed_functions.key?(name)
          raise Error, "Failed to add page binding with name #{name}: globalThis['#{name}'] already exists!"
        end

        handler = apply || block
        unless handler&.respond_to?(:call)
          raise ArgumentError, "expose_function requires a callable"
        end

        exposed_function = ExposedFunction.from(self, name, handler)
        @exposed_functions[name] = exposed_function
      end

      # Remove an exposed function.
      # @rbs name: String -- Function name to remove
      # @rbs return: void
      def remove_exposed_function(name)
        assert_not_detached

        exposed_function = @exposed_functions.delete(name)
        unless exposed_function
          raise Error, "Failed to remove page binding with name #{name}: window['#{name}'] does not exists!"
        end

        exposed_function.dispose
      end

      # Get the frame ID (browsing context ID)
      # Following Puppeteer's _id pattern
      # @rbs return: String -- Frame ID
      def _id
        @browsing_context.id
      end

      private

      # Initialize the frame by setting up child frame tracking
      # Following Puppeteer's BidiFrame.#initialize pattern exactly
      # @rbs return: void
      def initialize_frame
        # Create Frame objects for existing child contexts
        @browsing_context.children.each do |child_context|
          create_frame_target(child_context)
        end

        # Listen for new child frames
        @browsing_context.on(:browsingcontext) do |browsing_context|
          create_frame_target(browsing_context)
        end

        # Emit framedetached when THIS frame's browsing context is closed
        # Following Puppeteer's pattern: this.browsingContext.on('closed', () => {
        #   this.page().trustedEmitter.emit(PageEvent.FrameDetached, this);
        # });
        @browsing_context.on(:closed) do
          @frames.clear
          page.emit(:framedetached, self)
        end

        # Listen for navigation events and emit framenavigated
        # Following Puppeteer's pattern: emit framenavigated on DOMContentLoaded
        @browsing_context.on(:dom_content_loaded) do
          page.emit(:framenavigated, self)
        end

        # Also emit framenavigated on fragment navigation (anchor links, hash changes)
        # Note: Puppeteer uses navigation.once('fragment'), but we listen to
        # browsingContext's fragment_navigated which is equivalent
        @browsing_context.on(:fragment_navigated) do
          page.emit(:framenavigated, self)
        end

        @browsing_context.on(:request) do |request|
          http_request = HTTPRequest.from(
            request,
            self,
            page.network_interception_enabled?
          )

          request.once(:success) do
            page.emit(:requestfinished, http_request)
          end

          request.once(:error) do
            page.emit(:requestfailed, http_request)
          end
          page.request_interception_semaphore.async do
            http_request.finalize_interceptions
          end
        end

        @browsing_context.on(:log) do |entry|
          if entry["type"] == "console"
            page.emit(:console, console_message_from_log_entry(entry))
          elsif entry["type"] == "javascript"
            page.emit(:pageerror, Error.new(entry["text"].to_s))
          end
        end
      end

      def console_message_from_log_entry(entry)
        args = (entry["args"] || []).map { |arg| JSHandle.from(arg, main_realm.core_realm) }
        text = args.each_with_index.map do |handle, index|
          console_arg_text(entry["args"][index], handle)
        end.join(" ")
        type = console_message_type(entry["method"])

        ConsoleMessage.new(
          type: type,
          text: text,
          args: args,
          location: console_message_location(entry["stackTrace"]),
          stack_trace: console_message_stack_trace(entry["stackTrace"])
        )
      end

      def console_message_type(method)
        case method.to_s
        when "group"
          "startGroup"
        when "groupCollapsed"
          "startGroupCollapsed"
        when "groupEnd"
          "endGroup"
        else
          method.to_s
        end
      end

      def console_arg_text(remote_value, handle)
        return Deserializer.deserialize(remote_value).to_s if handle.primitive_value?

        handle.to_s
      end

      def console_message_location(stack_trace)
        frame = stack_trace&.dig("callFrames", 0)
        return nil unless frame

        {
          url: frame["url"],
          line_number: frame["lineNumber"],
          column_number: frame["columnNumber"]
        }
      end

      def console_message_stack_trace(stack_trace)
        (stack_trace&.fetch("callFrames", nil) || []).map do |frame|
          {
            url: frame["url"],
            line_number: frame["lineNumber"],
            column_number: frame["columnNumber"],
            function_name: frame["functionName"]
          }
        end
      end

      # Create a Frame for a child browsing context
      # Following Puppeteer's BidiFrame.#createFrameTarget pattern exactly:
      #   const frame = BidiFrame.from(this, browsingContext);
      #   this.#frames.set(browsingContext, frame);
      #   this.page().trustedEmitter.emit(PageEvent.FrameAttached, frame);
      #   browsingContext.on('closed', () => {
      #     this.#frames.delete(browsingContext);
      #   });
      # Note: FrameDetached is NOT emitted here - it's emitted in #initialize
      # when the frame's own browsing context closes
      # @rbs browsing_context: Core::BrowsingContext -- Child browsing context
      # @rbs return: Frame -- New child frame
      def create_frame_target(browsing_context)
        frame = Frame.from(self, browsing_context)
        @frames[browsing_context.id] = frame

        # Emit frameattached event
        page.emit(:frameattached, frame)

        # Remove frame from parent's frames map when its context is closed
        # Note: FrameDetached is emitted by the frame itself in its initialize_frame
        browsing_context.once(:closed) do
          @frames.delete(browsing_context.id)
        end

        frame
      end

      # Check if this frame is detached and raise error if so
      # @rbs return: void
      def assert_not_detached
        raise FrameDetachedError, "Attempted to use detached Frame '#{_id}'." if @browsing_context.closed?
      end

      def navigation_response_for(navigation)
        return nil unless navigation&.request

        request = navigation.request
        resolved_request = request.last_redirect || request
        http_request = HTTPRequest.for_core_request(resolved_request)
        return http_request.response if http_request&.response

        wait_for_request_completion(request)

        resolved_request = request.last_redirect || request
        http_request = HTTPRequest.for_core_request(resolved_request)
        http_request&.response
      end

      def wait_for_request_completion(request)
        loop do
          return if request.response || request.error

          promise = Async::Promise.new
          success_listener = proc do
            promise.resolve(:done) unless promise.resolved?
          end
          error_listener = proc do
            promise.resolve(:done) unless promise.resolved?
          end
          redirect_listener = proc do |redirect_request|
            promise.resolve(redirect_request) unless promise.resolved?
          end

          request.on(:success, &success_listener)
          request.on(:error, &error_listener)
          request.on(:redirect, &redirect_listener)

          result = promise.wait
          request.off(:success, &success_listener)
          request.off(:error, &error_listener)
          request.off(:redirect, &redirect_listener)

          return if result == :done

          request = result
        end
      end

    end
  end
end

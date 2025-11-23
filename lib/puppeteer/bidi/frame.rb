# frozen_string_literal: true

module Puppeteer
  module Bidi
    # Frame represents a frame (main frame or iframe) in the page
    # This is a high-level wrapper around Core::BrowsingContext
    class Frame
      attr_reader :browsing_context, :task_manager

      def initialize(parent, browsing_context)
        @parent = parent
        @browsing_context = browsing_context
        @puppeteer_util_handle = nil
        @task_manager = TaskManager.new

        # Set this frame as the environment for the realm
        # Following Puppeteer's design where realm.environment returns the frame
        realm = @browsing_context.default_realm
        realm.environment = self if realm.respond_to?(:environment=)

        # Re-inject puppeteerUtil when realm is updated
        realm.on(:updated) do
          @puppeteer_util_handle&.dispose
          @puppeteer_util_handle = nil
        end
      end

      # Get the page that owns this frame
      # Traverses up the parent chain until reaching a Page
      # @return [Page] The page containing this frame
      def page
        @parent.is_a?(Page) ? @parent : @parent.page
      end

      # Get the parent frame
      # @return [Frame, nil] Parent frame if this is a child frame, nil if top-level
      def parent_frame
        @parent.is_a?(Frame) ? @parent : nil
      end

      # Evaluate JavaScript in the frame context
      # @param script [String] JavaScript to evaluate (expression or function)
      # @param *args [Array] Arguments to pass to the function (if script is a function)
      # @return [Object] Result of evaluation
      def evaluate(script, *args)
        assert_not_detached

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
        assert_not_detached

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
          # Puppeteer passes awaitPromise: true to wait for promises to resolve
          result = @browsing_context.default_realm.call_function(script_trimmed, true, **options)
        else
          # Puppeteer passes awaitPromise: true to wait for promises to resolve
          result = @browsing_context.default_realm.evaluate(script_trimmed, true)
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
        assert_not_detached

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

      # Click an element matching the selector
      # @param selector [String] CSS selector
      # @param button [String] Mouse button
      # @param count [Integer] Number of clicks
      # @param delay [Numeric] Delay between mousedown and mouseup
      # @param offset [Hash] Click offset {x:, y:}
      def click(selector, button: 'left', count: 1, delay: nil, offset: nil)
        assert_not_detached

        handle = query_selector(selector)
        raise SelectorNotFoundError, selector unless handle

        begin
          handle.click(button: button, count: count, delay: delay, offset: offset, frame: self)
        ensure
          handle.dispose
        end
      end

      # Type text into an element matching the selector
      # @param selector [String] CSS selector
      # @param text [String] Text to type
      # @param delay [Numeric] Delay between key presses in milliseconds
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

      # Get the frame URL
      # @return [String] Current URL
      def url
        @browsing_context.url
      end

      # Set frame content
      # @param html [String] HTML content to set
      # @param wait_until [String] When to consider content set ('load', 'domcontentloaded')
      def set_content(html, wait_until: 'load')
        assert_not_detached

        # Puppeteer BiDi implementation:
        # await Promise.all([
        #   this.setFrameContent(html),
        #   firstValueFrom(combineLatest([this.#waitForLoad$(options), this.#waitForNetworkIdle$(options)]))
        # ]);

        # IMPORTANT: Register listener BEFORE document.write to avoid race condition
        load_event = case wait_until
                     when 'load'
                       :load
                     when 'domcontentloaded'
                       :dom_content_loaded
                     else
                       raise ArgumentError, "Unknown wait_until value: #{wait_until}"
                     end

        promise = Async::Promise.new
        listener = proc { promise.resolve(nil) }
        @browsing_context.once(load_event, &listener)

        # Execute both operations: document.write AND wait for load
        # Use promise_all to wait for both to complete (like Puppeteer's Promise.all)
        AsyncUtils.await_promise_all(
          -> { set_frame_content(html) },
          promise
        )

        nil
      end

      # Set frame content using document.open/write/close
      # This is a low-level method that doesn't wait for load events
      # @param content [String] HTML content to set
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

      # Get the isolated realm (default realm) for this frame
      # @return [Core::WindowRealm] The default realm
      def isolated_realm
        @browsing_context.default_realm
      end

      # Get child frames
      # @return [Array<Frame>] Child frames
      def child_frames
        # Get child browsing contexts directly from the browsing context
        child_contexts = @browsing_context.children

        # Create Frame objects for each child
        child_contexts.map do |child_context|
          Frame.new(self, child_context)
        end
      end

      # Wait for navigation to complete
      # @param timeout [Numeric] Timeout in milliseconds (default: 30000)
      # @param wait_until [String] When to consider navigation succeeded ('load', 'domcontentloaded')
      # @yield Optional block to execute that triggers navigation
      # @return [HTTPResponse, nil] Main response (nil for fragment navigation or history API)
      def wait_for_navigation(timeout: 30000, wait_until: 'load', &block)
        assert_not_detached

        # Determine which event to wait for
        load_event = case wait_until
                     when 'load'
                       :load
                     when 'domcontentloaded'
                       :dom_content_loaded
                     else
                       raise ArgumentError, "Unknown wait_until value: #{wait_until}"
                     end

        # Use Async::Promise for signaling (Fiber-based, not Thread-based)
        # This avoids race conditions and follows Puppeteer's Promise-based pattern
        promise = Async::Promise.new

        # Track navigation type for response creation
        navigation_type = nil  # :full_page, :fragment, or :history
        navigation_obj = nil  # The navigation object we're waiting for

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
          @browsing_context.once(load_event) do
            promise.resolve(:full_page) unless promise.resolved?
          end
        end

        # Listen for navigation events from BrowsingContext
        # This follows Puppeteer's pattern: race between 'navigation', 'historyUpdated', and 'fragmentNavigated'
        navigation_listener = proc do |data|
          # Only handle if we haven't already attached to a navigation
          next if navigation_obj

          navigation = data[:navigation]
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
          block.call if block

          # Wait for navigation with timeout using Async (Fiber-based)
          result = AsyncUtils.async_timeout(timeout, promise).wait

          # Return HTTPResponse for full page navigation, nil for fragment/history
          if result == :full_page
            HTTPResponse.new(url: @browsing_context.url, status: 200)
          else
            nil
          end
        rescue Async::TimeoutError
          raise Puppeteer::Bidi::TimeoutError, "Navigation timeout of #{timeout}ms exceeded"
        ensure
          # Clean up listeners
          @browsing_context.off(:navigation, &navigation_listener)
          @browsing_context.off(:history_updated, &history_listener)
          @browsing_context.off(:fragment_navigated, &fragment_listener)
          @browsing_context.off(:closed, &closed_listener)
        end
      end

      # Wait for a function to return a truthy value
      # @param page_function [String] JavaScript function to evaluate
      # @param options [Hash] Options for waiting
      # @option options [String, Numeric] :polling Polling strategy ('raf', 'mutation', or interval in ms)
      # @option options [Numeric] :timeout Timeout in milliseconds (default: 30000)
      # @param args [Array] Arguments to pass to the function
      # @return [JSHandle] Handle to the function's return value
      def wait_for_function(page_function, options = {}, *args, &block)
        assert_not_detached

        # Extract timeout with default from timeoutSettings (like Puppeteer's Realm.ts:65-67)
        # Corresponds to: const { timeout = this.timeoutSettings.timeout(), ... } = options;
        polling = options[:polling] || 'raf'
        timeout = options[:timeout] || page.default_timeout
        wait_task_options = {
          polling: polling,
          timeout: timeout,
          root: options[:root],
        }

        Sync do |task|
          result = WaitTask.new(self, wait_task_options, page_function, *args).result

          if block
            task.async do
              block.call
            end
          end

          result.wait
        end
      end

      # Get Puppeteer utilities (Poller classes, createFunction, etc.)
      # This is injected into the browser and cached
      # @return [JSHandle] Handle to puppeteerUtil object
      def puppeteer_util
        return @puppeteer_util_handle if @puppeteer_util_handle

        # Wrap the injected source in an IIFE that returns the utilities
        # We need to mock 'module' and 'exports' for CommonJS compatibility
        script = "(function() { const module = { exports: {} }; #{PUPPETEER_INJECTED_SOURCE}; return module.exports.default; })()"

        @puppeteer_util_handle = evaluate_handle(script)
      end

      private

      # Check if this frame is detached and raise error if so
      # @raise [FrameDetachedError] If frame is detached
      def assert_not_detached
        raise FrameDetachedError if @browsing_context.closed?
      end

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

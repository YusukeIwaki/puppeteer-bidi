# frozen_string_literal: true

module Puppeteer
  module Bidi
    # Frame represents a frame (main frame or iframe) in the page
    # This is a high-level wrapper around Core::BrowsingContext
    class Frame
      attr_reader :browsing_context

      def initialize(parent, browsing_context)
        @parent = parent
        @browsing_context = browsing_context

        default_core_realm = @browsing_context.default_realm
        internal_core_realm = @browsing_context.create_window_realm("__puppeteer_internal_#{rand(1..10_000)}")

        @main_realm = FrameRealm.new(self, default_core_realm)
        @isolated_realm = FrameRealm.new(self, internal_core_realm)
      end

      def main_realm
        @main_realm
      end

      def isolated_realm
        @isolated_realm
      end

      # Backwards compatibility for call sites that previously accessed Frame#realm.
      def realm
        main_realm
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
        main_realm.evaluate(script, *args)
      end

      # Evaluate JavaScript and return a handle to the result
      # @param script [String] JavaScript to evaluate (expression or function)
      # @param *args [Array] Arguments to pass to the function (if script is a function)
      # @return [JSHandle] Handle to the result
      def evaluate_handle(script, *args)
        assert_not_detached
        main_realm.evaluate_handle(script, *args)
      end

      # Get the document element handle
      # @return [ElementHandle] Document element handle
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
      # @param selector [String] CSS selector
      # @return [ElementHandle, nil] Element handle if found, nil otherwise
      def query_selector(selector)
        doc = document
        begin
          doc.query_selector(selector)
        ensure
          doc.dispose
        end
      end

      # Query for all elements matching the selector
      # @param selector [String] CSS selector
      # @return [Array<ElementHandle>] Array of element handles
      def query_selector_all(selector)
        doc = document
        begin
          doc.query_selector_all(selector)
        ensure
          doc.dispose
        end
      end

      # Evaluate a function on the first element matching the selector
      # @param selector [String] CSS selector
      # @param page_function [String] JavaScript function to evaluate
      # @param *args [Array] Arguments to pass to the function
      # @return [Object] Result of evaluation
      def eval_on_selector(selector, page_function, *args)
        doc = document
        begin
          doc.eval_on_selector(selector, page_function, *args)
        ensure
          doc.dispose
        end
      end

      # Evaluate a function on all elements matching the selector
      # @param selector [String] CSS selector
      # @param page_function [String] JavaScript function to evaluate
      # @param *args [Array] Arguments to pass to the function
      # @return [Object] Result of evaluation
      def eval_on_selector_all(selector, page_function, *args)
        doc = document
        begin
          doc.eval_on_selector_all(selector, page_function, *args)
        ensure
          doc.dispose
        end
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

      def goto(url, wait_until: 'load', timeout: 30000)
        response = wait_for_navigation(timeout: timeout, wait_until: wait_until) do
          @browsing_context.navigate(url, wait: 'interactive').wait
        end
        # Return HTTPResponse with the final URL
        # Note: Currently we don't track HTTP status codes from BiDi protocol
        # Assuming successful navigation (200 OK)
        HTTPResponse.new(url: @browsing_context.url, status: 200)
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
      # @param wait_until [String, Array<String>] When to consider navigation succeeded
      #   ('load', 'domcontentloaded', 'networkidle0', 'networkidle2', or array of these)
      # @yield Optional block to execute that triggers navigation
      # @return [HTTPResponse, nil] Main response (nil for fragment navigation or history API)
      def wait_for_navigation(timeout: 30000, wait_until: 'load', &block)
        assert_not_detached

        # Normalize wait_until to array
        wait_until_array = wait_until.is_a?(Array) ? wait_until : [wait_until]

        # Separate lifecycle events from network idle events
        lifecycle_events = wait_until_array.select { |e| ['load', 'domcontentloaded'].include?(e) }
        network_idle_events = wait_until_array.select { |e| ['networkidle0', 'networkidle2'].include?(e) }

        # Default to 'load' if no lifecycle event specified
        lifecycle_events = ['load'] if lifecycle_events.empty? && network_idle_events.any?

        # Determine which load event to wait for (use the first one)
        load_event = case lifecycle_events.first
                     when 'load'
                       :load
                     when 'domcontentloaded'
                       :dom_content_loaded
                     else
                       :load  # Default
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
          Async(&block).wait if block

          # Wait for navigation with timeout using Async (Fiber-based)
          if network_idle_events.any?
            # Puppeteer's pattern: wait for both navigation completion AND network idle
            # Determine concurrency based on network idle event
            concurrency = network_idle_events.include?('networkidle0') ? 0 : 2

            # Wait for both navigation and network idle in parallel using promise_all
            navigation_result, _ = AsyncUtils.async_timeout(timeout, -> do
              AsyncUtils.await_promise_all(
                promise,
                -> { page.wait_for_network_idle(idle_time: 500, timeout: timeout, concurrency: concurrency) }
              )
            end).wait

            result = navigation_result
          else
            # Only wait for navigation
            result = AsyncUtils.async_timeout(timeout, promise).wait
          end

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
        main_realm.wait_for_function(page_function, options, *args, &block)
      end

      # Wait for an element matching the selector to appear in the frame
      # @param selector [String] CSS selector
      # @param visible [Boolean] Wait for element to be visible
      # @param hidden [Boolean] Wait for element to be hidden or not found
      # @param timeout [Numeric] Timeout in milliseconds (default: 30000)
      # @return [ElementHandle, nil] Element handle if found, nil if hidden option was used and element disappeared
      def wait_for_selector(selector, visible: nil, hidden: nil, timeout: nil, &block)
        result = QueryHandler.instance.get_query_handler_and_selector(selector)
        result.query_handler.new.wait_for(self, result.updated_selector, visible: visible, hidden: hidden, polling: result.polling, timeout: timeout, &block)
      end

      # Set files on an input element
      # @param element [ElementHandle] The input element
      # @param files [Array<String>] File paths to set
      def set_files(element, files)
        assert_not_detached

        @browsing_context.set_files(
          element.remote_value_as_shared_reference,
          files
        ).wait
      end

      private

      # Check if this frame is detached and raise error if so
      # @raise [FrameDetachedError] If frame is detached
      def assert_not_detached
        raise FrameDetachedError if @browsing_context.closed?
      end

    end
  end
end

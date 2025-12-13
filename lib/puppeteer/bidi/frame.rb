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
      # @rbs parent: Page | Frame
      # @rbs browsing_context: Core::BrowsingContext
      # @rbs return: Frame
      def self.from(parent, browsing_context)
        frame = new(parent, browsing_context)
        frame.send(:initialize_frame)
        frame
      end

      # @rbs parent: Page | Frame
      # @rbs browsing_context: Core::BrowsingContext
      # @rbs return: void
      def initialize(parent, browsing_context)
        @parent = parent
        @browsing_context = browsing_context
        @frames = {} # Map of browsing context id to Frame (like WeakMap in JS)

        default_core_realm = @browsing_context.default_realm
        internal_core_realm = @browsing_context.create_window_realm("__puppeteer_internal_#{rand(1..10_000)}")

        @main_realm = FrameRealm.new(self, default_core_realm)
        @isolated_realm = FrameRealm.new(self, internal_core_realm)
      end

      # @rbs return: FrameRealm
      def main_realm
        @main_realm
      end

      # @rbs return: FrameRealm
      def isolated_realm
        @isolated_realm
      end

      # Backwards compatibility for call sites that previously accessed Frame#realm.
      # @rbs return: FrameRealm
      def realm
        main_realm
      end

      # Get the page that owns this frame
      # Traverses up the parent chain until reaching a Page
      # @rbs return: Page
      def page
        @parent.is_a?(Page) ? @parent : @parent.page
      end

      # Get the parent frame
      # @rbs return: Frame?
      def parent_frame
        @parent.is_a?(Frame) ? @parent : nil
      end

      # Evaluate JavaScript in the frame context
      # @rbs script: String
      # @rbs *args: untyped
      # @rbs return: untyped
      def evaluate(script, *args)
        assert_not_detached
        main_realm.evaluate(script, *args)
      end

      # Evaluate JavaScript and return a handle to the result
      # @rbs script: String
      # @rbs *args: untyped
      # @rbs return: JSHandle
      def evaluate_handle(script, *args)
        assert_not_detached
        main_realm.evaluate_handle(script, *args)
      end

      # Get the document element handle
      # @rbs return: ElementHandle
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
      # @rbs selector: String
      # @rbs return: ElementHandle?
      def query_selector(selector)
        doc = document
        begin
          doc.query_selector(selector)
        ensure
          doc.dispose
        end
      end

      # Query for all elements matching the selector
      # @rbs selector: String
      # @rbs return: Array[ElementHandle]
      def query_selector_all(selector)
        doc = document
        begin
          doc.query_selector_all(selector)
        ensure
          doc.dispose
        end
      end

      # Evaluate a function on the first element matching the selector
      # @rbs selector: String
      # @rbs page_function: String
      # @rbs *args: untyped
      # @rbs return: untyped
      def eval_on_selector(selector, page_function, *args)
        doc = document
        begin
          doc.eval_on_selector(selector, page_function, *args)
        ensure
          doc.dispose
        end
      end

      # Evaluate a function on all elements matching the selector
      # @rbs selector: String
      # @rbs page_function: String
      # @rbs *args: untyped
      # @rbs return: untyped
      def eval_on_selector_all(selector, page_function, *args)
        doc = document
        begin
          doc.eval_on_selector_all(selector, page_function, *args)
        ensure
          doc.dispose
        end
      end

      # Click an element matching the selector
      # @rbs selector: String
      # @rbs button: String
      # @rbs count: Integer
      # @rbs delay: Numeric?
      # @rbs offset: Hash[Symbol, Numeric]?
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
      # @rbs selector: String
      # @rbs text: String
      # @rbs delay: Numeric
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
      # @rbs selector: String
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

      # Get the frame URL
      # @rbs return: String
      def url
        @browsing_context.url
      end

      # Navigate to a URL
      # @rbs url: String
      # @rbs wait_until: String
      # @rbs timeout: Numeric
      # @rbs return: HTTPResponse?
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
      # @rbs html: String
      # @rbs wait_until: String
      # @rbs return: void
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
      # @rbs content: String
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

      # Get the frame name
      # @rbs return: String
      def name
        @_name || ''
      end

      # Check if frame is detached
      # @rbs return: bool
      def detached?
        @browsing_context.closed?
      end

      # Get child frames
      # Returns cached frame instances following Puppeteer's pattern
      # @rbs return: Array[Frame]
      def child_frames
        @browsing_context.children.map do |child_context|
          @frames[child_context.id]
        end.compact
      end

      # Get the frame element (iframe/frame DOM element) for this frame
      # Returns nil for the main frame
      # Following Puppeteer's Frame.frameElement() implementation exactly
      # @rbs return: ElementHandle?
      def frame_element
        assert_not_detached

        parent = parent_frame
        return nil unless parent

        # Query all iframe and frame elements in the parent frame
        list = parent.isolated_realm.evaluate_handle('() => document.querySelectorAll("iframe,frame")')

        begin
          # Get the array of elements
          length = list.evaluate('list => list.length')

          length.times do |i|
            iframe = list.evaluate_handle("(list, i) => list[i]", i)
            begin
              # Check if this iframe's content frame matches our frame
              content_frame = iframe.as_element&.content_frame
              if content_frame&.browsing_context&.id == @browsing_context.id
                # Transfer the handle to the main realm (adopt handle)
                # This ensures the returned handle is in the correct execution context
                return parent.main_realm.transfer_handle(iframe.as_element)
              end
            ensure
              iframe.dispose unless iframe.disposed?
            end
          end

          nil
        ensure
          list.dispose unless list.disposed?
        end
      end

      # Wait for navigation to complete
      # @rbs timeout: Numeric
      # @rbs wait_until: String | Array[String]
      # @rbs &block: (-> void)?
      # @rbs return: HTTPResponse?
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
      # @rbs page_function: String
      # @rbs options: Hash[Symbol, untyped]
      # @rbs *args: untyped
      # @rbs &block: ((JSHandle) -> void)?
      # @rbs return: JSHandle
      def wait_for_function(page_function, options = {}, *args, &block)
        main_realm.wait_for_function(page_function, options, *args, &block)
      end

      # Wait for an element matching the selector to appear in the frame
      # @rbs selector: String
      # @rbs visible: bool?
      # @rbs hidden: bool?
      # @rbs timeout: Numeric?
      # @rbs &block: ((ElementHandle?) -> void)?
      # @rbs return: ElementHandle?
      def wait_for_selector(selector, visible: nil, hidden: nil, timeout: nil, &block)
        result = QueryHandler.instance.get_query_handler_and_selector(selector)
        result.query_handler.new.wait_for(self, result.updated_selector, visible: visible, hidden: hidden, polling: result.polling, timeout: timeout, &block)
      end

      # Set files on an input element
      # @rbs element: ElementHandle
      # @rbs files: Array[String]
      # @rbs return: void
      def set_files(element, files)
        assert_not_detached

        @browsing_context.set_files(
          element.remote_value_as_shared_reference,
          files
        ).wait
      end

      # Get the frame ID (browsing context ID)
      # Following Puppeteer's _id pattern
      # @rbs return: String
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
        @browsing_context.on(:browsingcontext) do |data|
          create_frame_target(data[:browsing_context])
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
      # @rbs browsing_context: Core::BrowsingContext
      # @rbs return: Frame
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

    end
  end
end

# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # Visibility options for locators.
    module VisibilityOption
      HIDDEN = "hidden"
      VISIBLE = "visible"
    end

    # Events emitted by locators.
    module LocatorEvent
      ACTION = :action
    end

    class RetryableError < StandardError; end

    # Locators describe a strategy of locating objects and performing an action on them.
    # Actions are retried when the element is not ready.
    class Locator
      RETRY_DELAY = 0.1

      attr_reader :timeout #: Numeric

      def initialize
        @visibility = nil
        @timeout = 30_000
        @ensure_element_is_in_viewport = true
        @wait_for_enabled = true
        @wait_for_stable_bounding_box = true
        @emitter = Core::EventEmitter.new
      end

      # Create a race between multiple locators.
      # @rbs *locators: Array[Locator] -- Locators to race
      # @rbs return: Locator -- Locator that resolves to the first match
      def self.race(*locators)
        locators = locators.first if locators.length == 1 && locators.first.is_a?(Array)
        locators.each do |locator|
          raise Error, "Unknown locator for race candidate" unless locator.is_a?(Locator)
        end
        RaceLocator.new(locators)
      end

      # Register an event listener.
      # @rbs event: Symbol | String -- Event name
      # @rbs &block: (untyped) -> void -- Event handler
      # @rbs return: Locator -- This locator
      def on(event, &block)
        @emitter.on(event, &block)
        self
      end

      # Register a one-time event listener.
      # @rbs event: Symbol | String -- Event name
      # @rbs &block: (untyped) -> void -- Event handler
      # @rbs return: Locator -- This locator
      def once(event, &block)
        @emitter.once(event, &block)
        self
      end

      # Remove an event listener.
      # @rbs event: Symbol | String -- Event name
      # @rbs &block: ((untyped) -> void)? -- Handler to remove
      # @rbs return: Locator -- This locator
      def off(event, &block)
        @emitter.off(event, &block)
        self
      end

      # Clone the locator.
      # @rbs return: Locator -- Cloned locator
      def clone
        _clone
      end

      # Set the total timeout for locator actions.
      # Pass 0 to disable timeout.
      # @rbs timeout: Numeric -- Timeout in ms
      # @rbs return: Locator -- Cloned locator with timeout
      def set_timeout(timeout)
        locator = _clone
        locator.send(:timeout=, timeout)
        locator
      end

      # Set visibility checks for the locator.
      # @rbs visibility: String? -- Visibility option ("hidden", "visible", or nil)
      # @rbs return: Locator -- Cloned locator with visibility option
      def set_visibility(visibility)
        locator = _clone
        locator.send(:visibility=, visibility&.to_s)
        locator
      end

      # Set whether to wait for elements to become enabled.
      # @rbs value: bool -- Whether to wait for enabled state
      # @rbs return: Locator -- Cloned locator with enabled check
      def set_wait_for_enabled(value)
        locator = _clone
        locator.send(:wait_for_enabled=, value)
        locator
      end

      # Set whether to ensure elements are in the viewport.
      # @rbs value: bool -- Whether to ensure viewport visibility
      # @rbs return: Locator -- Cloned locator with viewport check
      def set_ensure_element_is_in_the_viewport(value)
        locator = _clone
        locator.send(:ensure_element_is_in_viewport=, value)
        locator
      end

      # Set whether to wait for a stable bounding box.
      # @rbs value: bool -- Whether to wait for stable bounding box
      # @rbs return: Locator -- Cloned locator with stable bounding box check
      def set_wait_for_stable_bounding_box(value)
        locator = _clone
        locator.send(:wait_for_stable_bounding_box=, value)
        locator
      end

      # Wait for the locator to produce a handle.
      # @rbs return: JSHandle -- Handle to located value
      def wait_handle
        with_retry("Locator.wait_handle") do |deadline, remaining_ms|
          _wait(timeout_ms: remaining_ms, deadline: deadline)
        end
      end

      # Wait for the locator to produce a JSON-serializable value.
      # @rbs return: untyped -- JSON-serializable value
      def wait
        handle = wait_handle
        begin
          handle.json_value
        ensure
          handle.dispose if handle.respond_to?(:dispose)
        end
      end

      # Map the locator using a JavaScript mapper.
      # @rbs mapper: String -- JavaScript mapper function
      # @rbs &block: () -> String -- Optional block returning mapper string
      # @rbs return: Locator -- Mapped locator
      def map(mapper = nil, &block)
        mapper = mapper || block&.call
        raise ArgumentError, "mapper is required" unless mapper

        map_handle(mapper)
      end

      # Filter the locator using a JavaScript predicate.
      # @rbs predicate: String -- JavaScript predicate function
      # @rbs &block: () -> String -- Optional block returning predicate string
      # @rbs return: Locator -- Filtered locator
      def filter(predicate = nil, &block)
        predicate = predicate || block&.call
        raise ArgumentError, "predicate is required" unless predicate

        FilteredLocator.new(_clone, predicate)
      end

      # Click the located element.
      # @rbs button: String -- Mouse button ('left', 'right', 'middle')
      # @rbs count: Integer -- Number of clicks
      # @rbs delay: Numeric? -- Delay between clicks in ms
      # @rbs offset: Hash[Symbol, Numeric]? -- Click offset from element center
      # @rbs return: void
      def click(button: "left", count: 1, delay: nil, offset: nil)
        perform_action("Locator.click", wait_for_enabled: true) do |handle|
          handle.click(button: button, count: count, delay: delay, offset: offset)
          nil
        end
      end

      # Fill the located element with the provided value.
      # @rbs value: String -- Value to fill
      # @rbs return: void
      def fill(value)
        perform_action("Locator.fill", wait_for_enabled: true) do |handle|
          input_type = handle.evaluate(<<~JS)
            (el) => {
              if (el instanceof HTMLSelectElement) {
                return "select";
              }
              if (el instanceof HTMLTextAreaElement) {
                return "typeable-input";
              }
              if (el instanceof HTMLInputElement) {
                if (
                  new Set([
                    "textarea",
                    "text",
                    "url",
                    "tel",
                    "search",
                    "password",
                    "number",
                    "email",
                  ]).has(el.type)
                ) {
                  return "typeable-input";
                }
                return "other-input";
              }

              if (el.isContentEditable) {
                return "contenteditable";
              }

              return "unknown";
            }
          JS

          case input_type
          when "select"
            handle.select(value)
          when "contenteditable", "typeable-input"
            text_to_type = handle.evaluate(<<~JS, value)
              (input, newValue) => {
                const currentValue = input.isContentEditable
                  ? input.innerText
                  : input.value;

                if (
                  newValue.length <= currentValue.length ||
                  !newValue.startsWith(input.value)
                ) {
                  if (input.isContentEditable) {
                    input.innerText = "";
                  } else {
                    input.value = "";
                  }
                  return newValue;
                }
                const originalValue = input.isContentEditable
                  ? input.innerText
                  : input.value;

                if (input.isContentEditable) {
                  input.innerText = "";
                  input.innerText = originalValue;
                } else {
                  input.value = "";
                  input.value = originalValue;
                }
                return newValue.substring(originalValue.length);
              }
            JS
            handle.type(text_to_type)
          when "other-input"
            handle.focus
            handle.evaluate(<<~JS, value)
              (input, newValue) => {
                input.value = newValue;
                input.dispatchEvent(new Event("input", {bubbles: true}));
                input.dispatchEvent(new Event("change", {bubbles: true}));
              }
            JS
          else
            raise StandardError, "Element cannot be filled out."
          end
          nil
        end
      end

      # Hover over the located element.
      # @rbs return: void
      def hover
        perform_action("Locator.hover") do |handle|
          handle.hover
          nil
        end
      end

      # Scroll the located element.
      # @rbs scroll_top: Numeric? -- Scroll top offset
      # @rbs scroll_left: Numeric? -- Scroll left offset
      # @rbs return: void
      def scroll(scroll_top: nil, scroll_left: nil)
        perform_action("Locator.scroll") do |handle|
          handle.evaluate(<<~JS, scroll_top, scroll_left)
            (el, scrollTop, scrollLeft) => {
              if (scrollTop !== undefined && scrollTop !== null) {
                el.scrollTop = scrollTop;
              }
              if (scrollLeft !== undefined && scrollLeft !== null) {
                el.scrollLeft = scrollLeft;
              }
            }
          JS
          nil
        end
      end

      protected

      def copy_options(locator)
        @timeout = locator.timeout
        @visibility = locator.visibility
        @wait_for_enabled = locator.wait_for_enabled?
        @ensure_element_is_in_viewport = locator.ensure_element_is_in_viewport?
        @wait_for_stable_bounding_box = locator.wait_for_stable_bounding_box?
        self
      end

      def visibility
        @visibility
      end

      def wait_for_enabled?
        @wait_for_enabled
      end

      def ensure_element_is_in_viewport?
        @ensure_element_is_in_viewport
      end

      def wait_for_stable_bounding_box?
        @wait_for_stable_bounding_box
      end

      def map_handle(mapper)
        MappedLocator.new(_clone, mapper)
      end

      def _clone
        raise NotImplementedError, "#{self.class}#_clone must be implemented"
      end

      def _wait(timeout_ms:, deadline:)
        raise NotImplementedError, "#{self.class}#_wait must be implemented"
      end

      private

      attr_writer :timeout,
                  :visibility,
                  :wait_for_enabled,
                  :ensure_element_is_in_viewport,
                  :wait_for_stable_bounding_box

      # @rbs cause: String -- Action name
      # @rbs wait_for_enabled: bool -- Whether to wait for enabled
      # @rbs &block: (ElementHandle) -> void -- Action to perform
      # @rbs return: void
      def perform_action(cause, wait_for_enabled: false, &block)
        with_retry(cause) do |deadline, remaining_ms|
          handle = _wait(timeout_ms: remaining_ms, deadline: deadline)
          begin
            ensure_element_is_in_viewport_if_needed(handle, deadline)
            wait_for_stable_bounding_box_if_needed(handle, deadline)
            wait_for_enabled_if_needed(handle, deadline) if wait_for_enabled
            @emitter.emit(LocatorEvent::ACTION, nil)
            block.call(handle)
          rescue StandardError => error
            handle.dispose if handle.respond_to?(:dispose)
            raise error
          end
        end
      end

      # @rbs cause: String -- Action name
      # @rbs &block: (Numeric?, Numeric?) -> untyped -- Retry block
      # @rbs return: untyped
      def with_retry(cause, &block)
        deadline = build_deadline
        loop do
          remaining_ms = deadline ? remaining_time_ms(deadline) : nil
          raise_timeout if deadline && remaining_ms <= 0
          begin
            return block.call(deadline, remaining_ms)
          rescue TimeoutError
            raise
          rescue StandardError
            raise_timeout if deadline && remaining_time_ms(deadline) <= 0
            sleep RETRY_DELAY
          end
        end
      end

      def build_deadline
        return nil if @timeout.nil? || @timeout == 0

        Process.clock_gettime(Process::CLOCK_MONOTONIC) + (@timeout / 1000.0)
      end

      def remaining_time_ms(deadline)
        ((deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)) * 1000.0).ceil
      end

      def raise_timeout
        raise TimeoutError, "Timed out after waiting #{@timeout}ms"
      end

      # @rbs deadline: Numeric? -- Deadline timestamp
      # @rbs &block: () -> boolish -- Condition block
      # @rbs return: void
      def wait_until(deadline, &block)
        loop do
          return if block.call
          raise_timeout if deadline && remaining_time_ms(deadline) <= 0
          sleep RETRY_DELAY
        end
      end

      def ensure_element_is_in_viewport_if_needed(handle, deadline)
        return unless @ensure_element_is_in_viewport

        wait_until(deadline) do
          next true if handle.intersecting_viewport?(threshold: 0)

          handle.scroll_into_view
          false
        end
      end

      def wait_for_stable_bounding_box_if_needed(handle, deadline)
        return unless @wait_for_stable_bounding_box

        wait_until(deadline) do
          rects = handle.evaluate(<<~JS)
            (element) => {
              return new Promise(resolve => {
                window.requestAnimationFrame(() => {
                  const rect1 = element.getBoundingClientRect();
                  window.requestAnimationFrame(() => {
                    const rect2 = element.getBoundingClientRect();
                    resolve([
                      {
                        x: rect1.x,
                        y: rect1.y,
                        width: rect1.width,
                        height: rect1.height,
                      },
                      {
                        x: rect2.x,
                        y: rect2.y,
                        width: rect2.width,
                        height: rect2.height,
                      },
                    ]);
                  });
                });
              });
            }
          JS

          rect1 = rects[0]
          rect2 = rects[1]
          rect1["x"] == rect2["x"] &&
            rect1["y"] == rect2["y"] &&
            rect1["width"] == rect2["width"] &&
            rect1["height"] == rect2["height"]
        end
      end

      def wait_for_enabled_if_needed(handle, deadline)
        return unless @wait_for_enabled

        wait_until(deadline) do
          handle.evaluate(<<~JS)
            (element) => {
              if (!(element instanceof HTMLElement)) {
                return true;
              }
              const isNativeFormControl = [
                "BUTTON",
                "INPUT",
                "SELECT",
                "TEXTAREA",
                "OPTION",
                "OPTGROUP",
              ].includes(element.nodeName);
              return !isNativeFormControl || !element.hasAttribute("disabled");
            }
          JS
        end
      end
    end

    # Locator implementation based on JavaScript functions.
    class FunctionLocator < Locator
      # @rbs page_or_frame: Page | Frame -- Page or frame to evaluate in
      # @rbs function: String -- JavaScript function to evaluate
      # @rbs return: Locator -- Function locator
      def self.create(page_or_frame, function)
        timeout = if page_or_frame.respond_to?(:default_timeout)
                    page_or_frame.default_timeout
                  else
                    page_or_frame.page.default_timeout
                  end
        new(page_or_frame, function).set_timeout(timeout)
      end

      def initialize(page_or_frame, function)
        super()
        @page_or_frame = page_or_frame
        @function = function
      end

      protected

      def _clone
        FunctionLocator.new(@page_or_frame, @function).copy_options(self)
      end

      def _wait(timeout_ms:, deadline:)
        handle = @page_or_frame.evaluate_handle(@function)
        begin
          truthy = handle.evaluate("(value) => Boolean(value)")
          raise RetryableError unless truthy
          handle
        rescue StandardError
          handle.dispose
          raise
        end
      end
    end

    # Abstract locator that delegates to another locator.
    class DelegatedLocator < Locator
      def initialize(delegate)
        super()
        @delegate = delegate
        copy_options(@delegate)
      end

      def set_timeout(timeout)
        locator = super
        locator.delegate = @delegate.set_timeout(timeout)
        locator
      end

      def set_visibility(visibility)
        locator = super
        locator.delegate = @delegate.set_visibility(visibility)
        locator
      end

      def set_wait_for_enabled(value)
        locator = super
        locator.delegate = @delegate.set_wait_for_enabled(value)
        locator
      end

      def set_ensure_element_is_in_the_viewport(value)
        locator = super
        locator.delegate = @delegate.set_ensure_element_is_in_the_viewport(value)
        locator
      end

      def set_wait_for_stable_bounding_box(value)
        locator = super
        locator.delegate = @delegate.set_wait_for_stable_bounding_box(value)
        locator
      end

      protected

      attr_accessor :delegate
    end

    # Locator that filters results using a predicate.
    class FilteredLocator < DelegatedLocator
      def initialize(delegate, predicate)
        super(delegate)
        @predicate = predicate
      end

      protected

      def _clone
        FilteredLocator.new(delegate.clone, @predicate).copy_options(self)
      end

      def _wait(timeout_ms:, deadline:)
        handle = delegate.__send__(:_wait, timeout_ms: timeout_ms, deadline: deadline)
        matched = handle.evaluate(@predicate)
        raise RetryableError unless matched

        handle
      end
    end

    # Locator that maps results using a mapper.
    class MappedLocator < DelegatedLocator
      def initialize(delegate, mapper)
        super(delegate)
        @mapper = mapper
      end

      protected

      def _clone
        MappedLocator.new(delegate.clone, @mapper).copy_options(self)
      end

      def _wait(timeout_ms:, deadline:)
        handle = delegate.__send__(:_wait, timeout_ms: timeout_ms, deadline: deadline)
        handle.evaluate_handle(@mapper)
      end
    end

    # Locator that queries nodes by selector or handle.
    class NodeLocator < Locator
      # @rbs page_or_frame: Page | Frame -- Page or frame to query
      # @rbs selector: String -- Selector to query
      # @rbs return: Locator -- Node locator
      def self.create(page_or_frame, selector)
        timeout = if page_or_frame.respond_to?(:default_timeout)
                    page_or_frame.default_timeout
                  else
                    page_or_frame.page.default_timeout
                  end
        new(page_or_frame, selector).set_timeout(timeout)
      end

      # @rbs page_or_frame: Page | Frame -- Page or frame to query
      # @rbs handle: ElementHandle -- Element handle to wrap
      # @rbs return: Locator -- Node locator
      def self.create_from_handle(page_or_frame, handle)
        timeout = if page_or_frame.respond_to?(:default_timeout)
                    page_or_frame.default_timeout
                  else
                    page_or_frame.page.default_timeout
                  end
        new(page_or_frame, handle).set_timeout(timeout)
      end

      def initialize(page_or_frame, selector_or_handle)
        super()
        @page_or_frame = page_or_frame
        @selector_or_handle = selector_or_handle
      end

      protected

      def _clone
        NodeLocator.new(@page_or_frame, @selector_or_handle).copy_options(self)
      end

      def _wait(timeout_ms:, deadline:)
        handle = if @selector_or_handle.is_a?(String)
                   query_selector_with_pseudo_selectors(@selector_or_handle)
                 else
                   @selector_or_handle
                 end

        raise RetryableError unless handle
        raise RetryableError if handle.respond_to?(:disposed?) && handle.disposed?

        if visibility
          matches_visibility = case visibility
                               when VisibilityOption::VISIBLE
                                 handle.visible?
                               when VisibilityOption::HIDDEN
                                 handle.hidden?
                               else
                                 true
                               end
          unless matches_visibility
            handle.dispose if @selector_or_handle.is_a?(String) && handle.respond_to?(:dispose)
            raise RetryableError
          end
        end

        handle
      end

      def query_selector_with_pseudo_selectors(selector)
        candidates = p_selector_candidates(selector)
        candidates.each do |candidate|
          handle = @page_or_frame.query_selector(candidate)
          return handle if handle
        end
        nil
      end

      def p_selector_candidates(selector)
        return [selector] unless selector.include?("::-p-")

        parts = split_selector_list(selector)
        candidates = parts.filter_map do |part|
          part = part.strip
          match = part.match(/\A::\-p\-(text|xpath)\((.*)\)\z/)
          next unless match

          name = match[1]
          value = unquote_selector_value(match[2])
          prefix = name == "text" ? "text/" : "xpath/"
          "#{prefix}#{value}"
        end

        candidates.empty? ? [selector] : candidates
      end

      def split_selector_list(selector)
        parts = []
        current = +""
        depth = 0
        in_string = nil
        escape = false

        selector.each_char do |char|
          if escape
            current << char
            escape = false
            next
          end

          if in_string
            if char == "\\"
              escape = true
            elsif char == in_string
              in_string = nil
            end
            current << char
            next
          end

          case char
          when "'", '"'
            in_string = char
          when '('
            depth += 1
          when ')'
            depth -= 1 if depth.positive?
          when ','
            if depth.zero?
              parts << current
              current = +""
              next
            end
          end

          current << char
        end

        parts << current unless current.empty?
        parts
      end

      def unquote_selector_value(value)
        stripped = value.strip
        return stripped if stripped.length < 2

        quote = stripped[0]
        return stripped unless quote == "'" || quote == '"'
        return stripped unless stripped.end_with?(quote)

        stripped[1..-2].gsub(/\\([\s\S])/, '\1')
      end
    end

    # Locator that races multiple locators.
    class RaceLocator < Locator
      def initialize(locators)
        super()
        @locators = locators
      end

      protected

      def _clone
        RaceLocator.new(@locators.map(&:clone)).copy_options(self)
      end

      def _wait(timeout_ms:, deadline:)
        found = nil

        wait_until(deadline) do
          @locators.each do |locator|
            begin
              found = locator.__send__(:_wait, timeout_ms: timeout_ms, deadline: deadline)
              break
            rescue RetryableError
              next
            end
          end

          !found.nil?
        end

        found
      end
    end
  end
end

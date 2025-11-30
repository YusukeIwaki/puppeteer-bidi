# frozen_string_literal: true

module Puppeteer
  module Bidi
    # ElementHandle represents a reference to a DOM element
    # Based on Puppeteer's BidiElementHandle implementation
    # This extends JSHandle with DOM-specific methods
    class ElementHandle < JSHandle
      # Factory method to create ElementHandle from remote value
      # @param remote_value [Hash] BiDi RemoteValue
      # @param realm [Core::Realm] Associated realm
      # @return [ElementHandle] ElementHandle instance
      def self.from(remote_value, realm)
        new(realm, remote_value)
      end

      # Query for a descendant element matching the selector
      # Supports CSS selectors and prefixed selectors (xpath/, text/, aria/, pierce/)
      # @param selector [String] Selector (CSS or prefixed)
      # @return [ElementHandle, nil] Element handle if found, nil otherwise
      def query_selector(selector)
        assert_not_disposed

        result = QueryHandler.instance.get_query_handler_and_selector(selector)
        result.query_handler.new.run_query_one(self, result.updated_selector)
      end

      # Query for all descendant elements matching the selector
      # Supports CSS selectors and prefixed selectors (xpath/, text/, aria/, pierce/)
      # @param selector [String] Selector (CSS or prefixed)
      # @return [Array<ElementHandle>] Array of element handles
      def query_selector_all(selector)
        assert_not_disposed

        result = QueryHandler.instance.get_query_handler_and_selector(selector)
        result.query_handler.new.run_query_all(self, result.updated_selector)
      end

      # Evaluate a function on the first element matching the selector
      # @param selector [String] CSS selector
      # @param page_function [String] JavaScript function to evaluate
      # @param *args [Array] Arguments to pass to the function
      # @return [Object] Result of evaluation
      def eval_on_selector(selector, page_function, *args)
        assert_not_disposed

        element_handle = query_selector(selector)
        raise SelectorNotFoundError, selector unless element_handle

        begin
          element_handle.evaluate(page_function, *args)
        ensure
          element_handle.dispose
        end
      end

      # Evaluate a function on all elements matching the selector
      # @param selector [String] CSS selector
      # @param page_function [String] JavaScript function to evaluate
      # @param *args [Array] Arguments to pass to the function
      # @return [Object] Result of evaluation
      def eval_on_selector_all(selector, page_function, *args)
        assert_not_disposed

        # Get all matching elements
        element_handles = query_selector_all(selector)

        begin
          # Create an array handle containing all element handles
          # Use evaluateHandle to create an array in the browser context
          array_handle = @realm.call_function(
            '(...elements) => elements',
            false,
            arguments: element_handles.map(&:remote_value)
          ).wait

          # Create a JSHandle for the array
          array_js_handle = JSHandle.from(array_handle['result'], @realm)

          begin
            # Evaluate the page_function with the array as first argument
            array_js_handle.evaluate(page_function, *args)
          ensure
            array_js_handle.dispose
          end
        ensure
          # Dispose all element handles
          element_handles.each(&:dispose)
        end
      end

      # Wait for an element matching the selector to appear as a descendant of this element
      # @param selector [String] CSS selector
      # @param visible [Boolean] Wait for element to be visible
      # @param hidden [Boolean] Wait for element to be hidden or not found
      # @param timeout [Numeric] Timeout in milliseconds (default: 30000)
      # @return [ElementHandle, nil] Element handle if found, nil if hidden option was used and element disappeared
      def wait_for_selector(selector, visible: nil, hidden: nil, timeout: nil, &block)
        result = QueryHandler.instance.get_query_handler_and_selector(selector)
        result.query_handler.new.wait_for(self, result.updated_selector, visible: visible, hidden: hidden, polling: result.polling, timeout: timeout, &block)
      end

      # Click the element
      # @param button [String] Mouse button
      # @param count [Integer] Number of clicks
      # @param delay [Numeric] Delay between mousedown and mouseup
      # @param offset [Hash] Click offset {x:, y:} relative to element center
      # @param frame [Frame] Frame containing this element (passed from Frame#click)
      def click(button: 'left', count: 1, delay: nil, offset: nil, frame: nil)
        assert_not_disposed

        scroll_into_view_if_needed
        point = clickable_point(offset: offset)

        # Use the frame parameter to get the page
        # Frame is needed because ElementHandle doesn't have direct access to Page
        raise 'Frame parameter required for click' unless frame

        frame.page.mouse.click(point[:x], point[:y], button: button, count: count, delay: delay)
      end

      # Type text into the element
      # @param text [String] Text to type
      # @param delay [Numeric] Delay between key presses in milliseconds
      def type(text, delay: 0)
        assert_not_disposed

        # Focus the element first
        focus

        # Get keyboard instance - use frame.page to access the page
        # Following Puppeteer's pattern: this.frame.page().keyboard
        keyboard = Keyboard.new(frame.page, @realm.browsing_context)
        keyboard.type(text, delay: delay)
      end

      # Press a key on the element
      # @param key [String] Key name (e.g., 'Enter', 'a', 'ArrowLeft')
      # @param delay [Numeric] Delay between keydown and keyup in milliseconds
      # @param text [String, nil] Text parameter (for CDP compatibility, ignored in BiDi)
      def press(key, delay: nil, text: nil)
        assert_not_disposed

        # Focus the element first
        focus

        # Get keyboard instance - use frame.page to access the page
        # Following Puppeteer's pattern: this.frame.page().keyboard
        keyboard = Keyboard.new(frame.page, @realm.browsing_context)
        keyboard.press(key, delay: delay, text: text)
      end

      # Get the frame this element belongs to
      # Following Puppeteer's pattern: realm.environment
      # @return [Frame] The frame containing this element
      def frame
        @realm.environment
      end

      # Focus the element
      def focus
        assert_not_disposed

        evaluate('element => element.focus()')
      end

      # Scroll element into view if needed
      def scroll_into_view_if_needed
        assert_not_disposed

        # Check if element is already visible
        return if intersecting_viewport?(threshold: 1)

        scroll_into_view
      end

      # Scroll element into view
      def scroll_into_view
        assert_not_disposed

        evaluate('element => element.scrollIntoView({block: "center", inline: "center", behavior: "instant"})')
      end

      # Check if element is intersecting the viewport
      # @param threshold [Numeric] Intersection threshold (0.0 to 1.0)
      # @return [Boolean] True if intersecting
      def intersecting_viewport?(threshold: 0)
        assert_not_disposed

        result = evaluate(<<~JS, threshold)
          (element, threshold) => {
            return new Promise(resolve => {
              const observer = new IntersectionObserver(entries => {
                resolve(entries[0].intersectionRatio > threshold);
                observer.disconnect();
              });
              observer.observe(element);
            });
          }
        JS

        result
      end

      # Get clickable point for the element
      # @param offset [Hash, nil] Offset {x:, y:} from element center
      # @return [Hash] Point {x:, y:}
      def clickable_point(offset: nil)
        assert_not_disposed

        box = clickable_box
        raise 'Node is either not clickable or not an Element' unless box

        if offset
          {
            x: box[:x] + offset[:x],
            y: box[:y] + offset[:y]
          }
        else
          {
            x: box[:x] + box[:width] / 2,
            y: box[:y] + box[:height] / 2
          }
        end
      end

      # Get the clickable box for the element
      # Uses getClientRects() to handle wrapped/multi-line elements correctly
      # Following Puppeteer's implementation:
      # https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/api/ElementHandle.ts#clickableBox
      # @return [Hash, nil] Box {x:, y:, width:, height:}
      def clickable_box
        assert_not_disposed

        # Get client rects - returns multiple boxes for wrapped elements
        boxes = evaluate(<<~JS)
          element => {
            if (!(element instanceof Element)) {
              return null;
            }
            return [...element.getClientRects()].map(rect => {
              return {x: rect.x, y: rect.y, width: rect.width, height: rect.height};
            });
          }
        JS

        return nil unless boxes&.is_a?(Array) && !boxes.empty?

        # Intersect boxes with frame boundaries
        intersect_bounding_boxes_with_frame(boxes)

        # TODO: Handle parent frames (for iframe support)
        # frame = self.frame
        # while (parent_frame = frame.parent_frame)
        #   # Adjust coordinates for parent frame offset
        # end

        # Find first box with valid dimensions
        box = boxes.find { |rect| rect['width'] >= 1 && rect['height'] >= 1 }
        return nil unless box

        {
          x: box['x'],
          y: box['y'],
          width: box['width'],
          height: box['height']
        }
      end

      private

      # Intersect bounding boxes with frame viewport boundaries
      # Modifies boxes in-place to clip them to visible area
      # @param boxes [Array<Hash>] Array of boxes with {x:, y:, width:, height:}
      def intersect_bounding_boxes_with_frame(boxes)
        # Get document dimensions using element's evaluate (which handles deserialization)
        dimensions = evaluate(<<~JS)
          element => {
            return {
              documentWidth: element.ownerDocument.documentElement.clientWidth,
              documentHeight: element.ownerDocument.documentElement.clientHeight
            };
          }
        JS

        document_width = dimensions['documentWidth']
        document_height = dimensions['documentHeight']

        # Intersect each box with document boundaries
        boxes.each do |box|
          intersect_bounding_box(box, document_width, document_height)
        end
      end

      # Intersect a single bounding box with given width/height boundaries
      # Modifies box in-place
      # @param box [Hash] Box with {x:, y:, width:, height:}
      # @param width [Numeric] Boundary width
      # @param height [Numeric] Boundary height
      def intersect_bounding_box(box, width, height)
        # Clip width
        box['width'] = [
          box['x'] >= 0 ?
            [width - box['x'], box['width']].min :
            [width, box['width'] + box['x']].min,
          0
        ].max

        # Clip height
        box['height'] = [
          box['y'] >= 0 ?
            [height - box['y'], box['height']].min :
            [height, box['height'] + box['y']].min,
          0
        ].max

        # Ensure non-negative coordinates
        box['x'] = [box['x'], 0].max
        box['y'] = [box['y'], 0].max
      end

      # String representation includes element type
      # @return [String] Formatted string
      def to_s
        return 'ElementHandle@disposed' if disposed?
        'ElementHandle@node'
      end
    end
  end
end

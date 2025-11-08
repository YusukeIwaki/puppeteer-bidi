# frozen_string_literal: true

require_relative 'js_handle'

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
      # @param selector [String] CSS selector
      # @return [ElementHandle, nil] Element handle if found, nil otherwise
      def query_selector(selector)
        assert_not_disposed

        # Use querySelector on this element
        result = @realm.call_function(
          '(element, selector) => element.querySelector(selector)',
          false,
          arguments: [
            @remote_value,
            Serializer.serialize(selector)
          ]
        )

        # Check for exceptions
        if result['type'] == 'exception'
          exception_details = result['exceptionDetails']
          text = exception_details['text'] || 'Query selector failed'
          raise text
        end

        # Check if result is null
        result_value = result['result']
        return nil if result_value['type'] == 'null' || result_value['type'] == 'undefined'

        # Return ElementHandle for the found element
        ElementHandle.new(@realm, result_value)
      end

      # Query for all descendant elements matching the selector
      # @param selector [String] CSS selector
      # @return [Array<ElementHandle>] Array of element handles
      def query_selector_all(selector)
        assert_not_disposed

        # Use querySelectorAll on this element
        result = @realm.call_function(
          '(element, selector) => Array.from(element.querySelectorAll(selector))',
          false,
          arguments: [
            @remote_value,
            Serializer.serialize(selector)
          ]
        )

        # Check for exceptions
        if result['type'] == 'exception'
          exception_details = result['exceptionDetails']
          text = exception_details['text'] || 'Query selector failed'
          raise text
        end

        # Result should be an array
        result_value = result['result']
        return [] unless result_value['type'] == 'array'

        # Convert each element to ElementHandle
        result_value['value'].map do |element_value|
          ElementHandle.new(@realm, element_value)
        end
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
          )

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
      # @return [Hash, nil] Box {x:, y:, width:, height:}
      def clickable_box
        assert_not_disposed

        # Get bounding box using BiDi-compatible approach
        result = evaluate(<<~JS)
          element => {
            if (!element.getBoundingClientRect) {
              return null;
            }
            const rect = element.getBoundingClientRect();
            return {
              x: rect.x,
              y: rect.y,
              width: rect.width,
              height: rect.height
            };
          }
        JS

        return nil unless result
        return nil if result['width'] < 1 || result['height'] < 1

        {
          x: result['x'],
          y: result['y'],
          width: result['width'],
          height: result['height']
        }
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

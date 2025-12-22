# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # ElementHandle represents a reference to a DOM element
    # Based on Puppeteer's BidiElementHandle implementation
    # This extends JSHandle with DOM-specific methods
    class ElementHandle < JSHandle
      # Bounding box data class representing element position and dimensions
      BoundingBox = Data.define(:x, :y, :width, :height)

      # Point data class representing a coordinate
      Point = Data.define(:x, :y)

      # Box model data class representing element's CSS box model
      # Each quad (content, padding, border, margin) contains 4 Points representing corners
      # Corners are ordered: top-left, top-right, bottom-right, bottom-left
      BoxModel = Data.define(:content, :padding, :border, :margin, :width, :height)

      # Factory method to create ElementHandle from remote value
      # @rbs remote_value: Hash[String, untyped] -- BiDi RemoteValue
      # @rbs realm: Core::Realm -- Associated realm
      # @rbs return: ElementHandle -- ElementHandle instance
      def self.from(remote_value, realm)
        new(realm, remote_value)
      end

      # Query for a descendant element matching the selector
      # Supports CSS selectors and prefixed selectors (xpath/, text/, aria/, pierce/)
      # @rbs selector: String -- Selector to query
      # @rbs return: ElementHandle? -- Matching element or nil
      def query_selector(selector)
        assert_not_disposed

        result = QueryHandler.instance.get_query_handler_and_selector(selector)
        result.query_handler.new.run_query_one(self, result.updated_selector)
      end

      # Query for all descendant elements matching the selector
      # Supports CSS selectors and prefixed selectors (xpath/, text/, aria/, pierce/)
      # @rbs selector: String -- Selector to query
      # @rbs return: Array[ElementHandle] -- All matching elements
      def query_selector_all(selector)
        assert_not_disposed

        result = QueryHandler.instance.get_query_handler_and_selector(selector)
        result.query_handler.new.run_query_all(self, result.updated_selector)
      end

      # Evaluate a function on the first element matching the selector
      # @rbs selector: String -- Selector to query
      # @rbs page_function: String -- JavaScript function to evaluate
      # @rbs *args: untyped -- Arguments to pass to the function
      # @rbs return: untyped -- Evaluation result
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
      # @rbs selector: String -- Selector to query
      # @rbs page_function: String -- JavaScript function to evaluate
      # @rbs *args: untyped -- Arguments to pass to the function
      # @rbs return: untyped -- Evaluation result
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

      # Click the element
      # @rbs button: String -- Mouse button ('left', 'right', 'middle')
      # @rbs count: Integer -- Number of clicks
      # @rbs delay: Numeric? -- Delay between clicks in ms
      # @rbs offset: Hash[Symbol, Numeric]? -- Click offset from element center
      # @rbs return: void
      def click(button: 'left', count: 1, delay: nil, offset: nil)
        assert_not_disposed

        scroll_into_view_if_needed
        point = clickable_point(offset: offset)

        frame.page.mouse.click(point.x, point.y, button: button, count: count, delay: delay)
      end

      # Type text into the element
      # @rbs text: String -- Text to type
      # @rbs delay: Numeric -- Delay between key presses in ms
      # @rbs return: void
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
      # @rbs key: String -- Key to press
      # @rbs delay: Numeric? -- Delay between keydown and keyup in ms
      # @rbs text: String? -- Text to send with key press
      # @rbs return: void
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
      # @rbs return: Frame -- Owning frame
      def frame
        @realm.environment
      end

      # Get the content frame for iframe/frame elements
      # Returns the frame that the iframe/frame element refers to
      # @rbs return: Frame? -- Content frame or nil
      def content_frame
        assert_not_disposed

        handle = evaluate_handle(<<~JS)
          element => {
            if (element instanceof HTMLIFrameElement || element instanceof HTMLFrameElement) {
              return element.contentWindow;
            }
            return undefined;
          }
        JS

        begin
          value = handle.remote_value
          if value['type'] == 'window'
            # Find the frame with matching browsing context ID
            context_id = value.dig('value', 'context')
            return nil unless context_id

            frame.page.frames.find { |f| f.browsing_context.id == context_id }
          else
            nil
          end
        ensure
          handle.dispose
        end
      end

      # Check if the element is visible
      # An element is considered visible if:
      # - It has computed styles
      # - Its visibility is not 'hidden' or 'collapse'
      # - Its bounding box is not empty (width > 0 AND height > 0)
      # @rbs return: bool -- Whether element is visible
      def visible?
        check_visibility(true)
      end

      # Check if the element is hidden
      # An element is considered hidden if:
      # - It has no computed styles
      # - Its visibility is 'hidden' or 'collapse'
      # - Its bounding box is empty (width == 0 OR height == 0)
      # @rbs return: bool -- Whether element is hidden
      def hidden?
        check_visibility(false)
      end

      # Convert the current handle to the given element type
      # Validates that the element matches the expected tag name
      # @rbs tag_name: String -- Expected tag name
      # @rbs return: ElementHandle -- This element if matching
      def to_element(tag_name)
        assert_not_disposed

        is_matching = evaluate('(node, tagName) => node.nodeName === tagName.toUpperCase()', tag_name)
        raise "Element is not a(n) `#{tag_name}` element" unless is_matching

        self
      end

      # Focus the element
      # @rbs return: void
      def focus
        assert_not_disposed

        evaluate('element => element.focus()')
      end

      # Select options on a <select> element
      # Triggers 'change' and 'input' events once all options are selected.
      # If not a select element, throws an error.
      # @rbs *values: String -- Option values to select
      # @rbs return: Array[String] -- Actually selected option values
      def select(*values)
        assert_not_disposed

        # Validate all values are strings
        values.each_with_index do |value, index|
          unless value.is_a?(String)
            raise ArgumentError, "Values must be strings. Found value of type #{value.class} at index #{index}"
          end
        end

        # Use isolated realm to avoid user modifications to global objects (like Event).
        realm = frame.isolated_realm
        adopted_element = realm.adopt_handle(self)

        begin
          adopted_element.evaluate(<<~JS, values)
            (element, vals) => {
              const values = new Set(vals);
              if (!(element instanceof HTMLSelectElement)) {
                throw new Error('Element is not a <select> element.');
              }

              const selectedValues = new Set();
              if (!element.multiple) {
                for (const option of element.options) {
                  option.selected = false;
                }
                for (const option of element.options) {
                  if (values.has(option.value)) {
                    option.selected = true;
                    selectedValues.add(option.value);
                    break;
                  }
                }
              } else {
                for (const option of element.options) {
                  option.selected = values.has(option.value);
                  if (option.selected) {
                    selectedValues.add(option.value);
                  }
                }
              }

              element.dispatchEvent(new Event('input', {bubbles: true}));
              element.dispatchEvent(new Event('change', {bubbles: true}));

              return Array.from(selectedValues.values());
            }
          JS
        ensure
          adopted_element&.dispose
        end
      end

      # Hover over the element
      # Scrolls element into view if needed and moves mouse to element center
      # @rbs return: void
      def hover
        assert_not_disposed

        scroll_into_view_if_needed
        point = clickable_point
        frame.page.mouse.move(point.x, point.y)
      end

      # Upload files to this element (for <input type="file">)
      # Following Puppeteer's implementation: ElementHandle.uploadFile -> Frame.setFiles
      # @rbs *files: String -- File paths to upload
      # @rbs return: void
      def upload_file(*files)
        assert_not_disposed

        # Resolve relative paths to absolute paths
        files = files.map do |file|
          if File.absolute_path?(file)
            file
          else
            File.expand_path(file)
          end
        end

        frame.set_files(self, files)
      end

      # Get the remote value as a SharedReference for BiDi commands
      # @rbs return: Hash[Symbol, String] -- SharedReference for BiDi
      def remote_value_as_shared_reference
        if @remote_value['sharedId']
          { sharedId: @remote_value['sharedId'] }
        else
          { handle: @remote_value['handle'] }
        end
      end

      # Scroll element into view if needed
      # @rbs return: void
      def scroll_into_view_if_needed
        assert_not_disposed

        # Check if element is already visible
        return if intersecting_viewport?(threshold: 1)

        scroll_into_view
      end

      # Scroll element into view
      # @rbs return: void
      def scroll_into_view
        assert_not_disposed

        evaluate('element => element.scrollIntoView({block: "center", inline: "center", behavior: "instant"})')
      end

      # Create a locator based on this element handle.
      # @rbs return: Locator -- Locator instance
      def as_locator
        assert_not_disposed

        NodeLocator.create_from_handle(frame, self)
      end

      # Take a screenshot of the element.
      # Following Puppeteer's implementation: ElementHandle.screenshot
      # @rbs path: String? -- File path to save screenshot
      # @rbs type: String -- Image type ('png' or 'jpeg')
      # @rbs clip: Hash[Symbol, Numeric]? -- Clip region relative to element
      # @rbs scroll_into_view: bool -- Scroll element into view before screenshot
      # @rbs return: String -- Base64-encoded image data
      def screenshot(path: nil, type: 'png', clip: nil, scroll_into_view: true)
        assert_not_disposed

        page = frame.page

        # Scroll into view if needed
        scroll_into_view_if_needed if scroll_into_view

        # Get element's bounding box - must not be empty
        # Note: bounding_box returns viewport-relative coordinates from getBoundingClientRect()
        element_box = non_empty_visible_bounding_box

        # Get page scroll offset from visualViewport to convert to document coordinates
        scroll_offset = evaluate(<<~JS)
          () => {
            if (!window.visualViewport) {
              throw new Error('window.visualViewport is not supported.');
            }
            return {
              pageLeft: window.visualViewport.pageLeft,
              pageTop: window.visualViewport.pageTop
            };
          }
        JS

        # Build element clip in document coordinates (viewport coords + scroll offset)
        # Following Puppeteer's implementation: elementClip.x += pageLeft; elementClip.y += pageTop
        element_clip = {
          x: element_box.x + scroll_offset['pageLeft'],
          y: element_box.y + scroll_offset['pageTop'],
          width: element_box.width,
          height: element_box.height
        }

        # Apply user-specified clip if provided
        if clip
          element_clip[:x] += clip[:x]
          element_clip[:y] += clip[:y]
          element_clip[:width] = clip[:width]
          element_clip[:height] = clip[:height]
        end

        # Check if element is larger than viewport - if so, temporarily resize viewport
        current_viewport = page.viewport
        viewport_width = current_viewport ? current_viewport[:width] : page.evaluate('window.innerWidth')
        viewport_height = current_viewport ? current_viewport[:height] : page.evaluate('window.innerHeight')

        needs_viewport_resize = element_clip[:width] > viewport_width || element_clip[:height] > viewport_height

        if needs_viewport_resize
          # Temporarily resize viewport to accommodate the element
          new_width = [element_clip[:width].ceil, viewport_width].max
          new_height = [element_clip[:height].ceil, viewport_height].max
          page.set_viewport(width: new_width, height: new_height)

          # Re-scroll and recalculate bounding box after viewport change
          scroll_into_view_if_needed if scroll_into_view
          element_box = non_empty_visible_bounding_box

          scroll_offset = evaluate(<<~JS)
            () => {
              return {
                pageLeft: window.visualViewport.pageLeft,
                pageTop: window.visualViewport.pageTop
              };
            }
          JS

          element_clip = {
            x: element_box.x + scroll_offset['pageLeft'],
            y: element_box.y + scroll_offset['pageTop'],
            width: element_box.width,
            height: element_box.height
          }

          if clip
            element_clip[:x] += clip[:x]
            element_clip[:y] += clip[:y]
            element_clip[:width] = clip[:width]
            element_clip[:height] = clip[:height]
          end
        end

        begin
          # Pass clip in document coordinates with capture_beyond_viewport: false
          # Page.screenshot will convert document coordinates to viewport coordinates
          # when capture_beyond_viewport is false, which allows it to work with Firefox BiDi
          page.screenshot(
            path: path,
            type: type,
            clip: element_clip,
            capture_beyond_viewport: false
          )
        ensure
          # Restore original viewport if we changed it
          if needs_viewport_resize && current_viewport
            page.set_viewport(width: current_viewport[:width], height: current_viewport[:height])
          end
        end
      end

      # Check if element is intersecting the viewport
      # @rbs threshold: Numeric -- Intersection ratio threshold
      # @rbs return: bool -- Whether element intersects viewport
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
      # @rbs offset: Hash[Symbol, Numeric]? -- Offset from element center
      # @rbs return: Point -- Clickable point coordinates
      def clickable_point(offset: nil)
        assert_not_disposed

        box = clickable_box
        raise 'Node is either not clickable or not an Element' unless box

        if offset
          Point.new(
            x: box[:x] + offset[:x],
            y: box[:y] + offset[:y]
          )
        else
          Point.new(
            x: box[:x] + box[:width] / 2,
            y: box[:y] + box[:height] / 2
          )
        end
      end

      # Get the bounding box of the element
      # Uses getBoundingClientRect() to get the element's position and size
      # @rbs return: BoundingBox? -- Bounding box or nil if not visible
      def bounding_box
        assert_not_disposed

        result = evaluate(<<~JS)
          element => {
            if (!(element instanceof Element)) {
              return null;
            }
            const rect = element.getBoundingClientRect();
            return {x: rect.x, y: rect.y, width: rect.width, height: rect.height};
          }
        JS

        return nil unless result

        # Return nil if element has zero dimensions (not visible)
        return nil if result['width'].zero? && result['height'].zero?

        BoundingBox.new(
          x: result['x'],
          y: result['y'],
          width: result['width'],
          height: result['height']
        )
      end

      # Get the box model of the element (content, padding, border, margin)
      # @rbs return: BoxModel? -- Box model or nil if not visible
      def box_model
        assert_not_disposed

        model = evaluate(<<~JS)
          element => {
            if (!(element instanceof Element)) {
              return null;
            }
            // Element is not visible
            if (element.getClientRects().length === 0) {
              return null;
            }
            const rect = element.getBoundingClientRect();
            const style = window.getComputedStyle(element);
            const offsets = {
              padding: {
                left: parseInt(style.paddingLeft, 10),
                top: parseInt(style.paddingTop, 10),
                right: parseInt(style.paddingRight, 10),
                bottom: parseInt(style.paddingBottom, 10),
              },
              margin: {
                left: -parseInt(style.marginLeft, 10),
                top: -parseInt(style.marginTop, 10),
                right: -parseInt(style.marginRight, 10),
                bottom: -parseInt(style.marginBottom, 10),
              },
              border: {
                left: parseInt(style.borderLeftWidth, 10),
                top: parseInt(style.borderTopWidth, 10),
                right: parseInt(style.borderRightWidth, 10),
                bottom: parseInt(style.borderBottomWidth, 10),
              },
            };
            const border = [
              {x: rect.left, y: rect.top},
              {x: rect.left + rect.width, y: rect.top},
              {x: rect.left + rect.width, y: rect.top + rect.height},
              {x: rect.left, y: rect.top + rect.height},
            ];
            const padding = transformQuadWithOffsets(border, offsets.border);
            const content = transformQuadWithOffsets(padding, offsets.padding);
            const margin = transformQuadWithOffsets(border, offsets.margin);
            return {
              content,
              padding,
              border,
              margin,
              width: rect.width,
              height: rect.height,
            };

            function transformQuadWithOffsets(quad, offsets) {
              return [
                {
                  x: quad[0].x + offsets.left,
                  y: quad[0].y + offsets.top,
                },
                {
                  x: quad[1].x - offsets.right,
                  y: quad[1].y + offsets.top,
                },
                {
                  x: quad[2].x - offsets.right,
                  y: quad[2].y - offsets.bottom,
                },
                {
                  x: quad[3].x + offsets.left,
                  y: quad[3].y - offsets.bottom,
                },
              ];
            }
          }
        JS

        return nil unless model

        # Convert raw arrays to Point objects for each quad
        BoxModel.new(
          content: model['content'].map { |p| Point.new(x: p['x'], y: p['y']) },
          padding: model['padding'].map { |p| Point.new(x: p['x'], y: p['y']) },
          border: model['border'].map { |p| Point.new(x: p['x'], y: p['y']) },
          margin: model['margin'].map { |p| Point.new(x: p['x'], y: p['y']) },
          width: model['width'],
          height: model['height']
        )
      end

      # Get the clickable box for the element
      # Uses getClientRects() to handle wrapped/multi-line elements correctly
      # Following Puppeteer's implementation:
      # https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/api/ElementHandle.ts#clickableBox
      # @rbs return: Hash[Symbol, Numeric]? -- Clickable box or nil
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
      # @rbs boxes: Array[Hash[String, Numeric]] -- Bounding boxes to clip
      # @rbs return: void
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
      # @rbs box: Hash[String, Numeric] -- Box to clip
      # @rbs width: Numeric -- Viewport width
      # @rbs height: Numeric -- Viewport height
      # @rbs return: void
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

      # Check element visibility
      # @rbs visible: bool -- Expected visibility state
      # @rbs return: bool -- Whether element matches visibility state
      def check_visibility(visible)
        assert_not_disposed

        evaluate(<<~JS, visible)
          (node, visible) => {
            const HIDDEN_VISIBILITY_VALUES = ['hidden', 'collapse'];

            if (!node) {
              return visible === false;
            }

            // For text nodes, check parent element
            const element = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
            if (!element) {
              return visible === false;
            }

            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            const isBoundingBoxEmpty = rect.width === 0 || rect.height === 0;

            const isVisible = style &&
              !HIDDEN_VISIBILITY_VALUES.includes(style.visibility) &&
              !isBoundingBoxEmpty;

            return visible === isVisible;
          }
        JS
      end

      # Get bounding box ensuring it's non-empty and visible
      # @rbs return: BoundingBox -- Non-empty bounding box
      def non_empty_visible_bounding_box
        box = bounding_box
        raise 'Node is either not visible or not an HTMLElement' unless box
        raise 'Node has 0 width.' if box.width.zero?
        raise 'Node has 0 height.' if box.height.zero?

        box
      end

      # String representation includes element type
      # @rbs return: String -- String representation
      def to_s
        return 'ElementHandle@disposed' if disposed?
        'ElementHandle@node'
      end
    end
  end
end

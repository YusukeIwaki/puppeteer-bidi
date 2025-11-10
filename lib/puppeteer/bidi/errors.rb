# frozen_string_literal: true

module Puppeteer
  module Bidi
    # Raised when attempting to use a disposed JSHandle or ElementHandle
    class JSHandleDisposedError < Error
      def initialize
        super('JSHandle is disposed')
      end
    end

    # Raised when attempting to use a closed Page
    class PageClosedError < Error
      def initialize
        super('Page is closed')
      end
    end

    # Raised when attempting to use a detached Frame
    class FrameDetachedError < Error
      def initialize
        super('Frame is detached')
      end
    end

    # Raised when a selector does not match any elements
    class SelectorNotFoundError < Error
      attr_reader :selector

      def initialize(selector)
        @selector = selector
        super("Error: failed to find element matching selector \"#{selector}\"")
      end
    end

    # Raised when a timeout occurs (e.g., navigation timeout)
    class TimeoutError < Error
    end
  end
end

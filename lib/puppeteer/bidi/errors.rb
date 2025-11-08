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
  end
end

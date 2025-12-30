# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # Timeout settings helper to share default wait values across realms.
    class TimeoutSettings
      DEFAULT_TIMEOUT = 30_000

      def initialize
        @default_timeout = nil
        @default_navigation_timeout = nil
      end

      # @rbs timeout: Numeric -- Default timeout in ms
      # @rbs return: void
      def set_default_timeout(timeout)
        @default_timeout = timeout
      end

      # @rbs timeout: Numeric -- Default navigation timeout in ms
      # @rbs return: void
      def set_default_navigation_timeout(timeout)
        @default_navigation_timeout = timeout
      end

      # @rbs return: Numeric -- Default timeout in ms
      def timeout
        @default_timeout || DEFAULT_TIMEOUT
      end

      # @rbs return: Numeric -- Default navigation timeout in ms
      def navigation_timeout
        @default_navigation_timeout || @default_timeout || DEFAULT_TIMEOUT
      end
    end
  end
end

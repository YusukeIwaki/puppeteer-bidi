# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # Minimal timeout settings helper to share default wait values across realms.
    class TimeoutSettings
      def initialize(default_timeout)
        @default_timeout = default_timeout
      end

      def timeout
        @default_timeout
      end

      def set_default_timeout(timeout)
        @default_timeout = timeout
      end
    end
  end
end

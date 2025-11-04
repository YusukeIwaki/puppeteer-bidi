# frozen_string_literal: true

require_relative "bidi/version"

module Puppeteer
  module Bidi
    class Error < StandardError; end
  end
end

require_relative "bidi/transport"
require_relative "bidi/connection"
require_relative "bidi/browser_launcher"
require_relative "bidi/core"
require_relative "bidi/browser_context"
require_relative "bidi/page"
require_relative "bidi/browser"

module Puppeteer
  module Bidi

    # Launch a new browser instance
    # @param options [Hash] Launch options
    # @return [Browser] Browser instance
    def self.launch(**options)
      Browser.launch(**options)
    end

    # Connect to an existing browser instance
    # @param ws_endpoint [String] WebSocket endpoint URL
    # @return [Browser] Browser instance
    def self.connect(ws_endpoint)
      Browser.connect(ws_endpoint)
    end
  end
end

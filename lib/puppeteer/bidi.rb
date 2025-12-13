# frozen_string_literal: true
# rbs_inline: enabled

require "puppeteer/bidi/version"
require "puppeteer/bidi/errors"

require "puppeteer/bidi/async_utils"
require "puppeteer/bidi/timeout_settings"
require "puppeteer/bidi/task_manager"
require "puppeteer/bidi/serializer"
require "puppeteer/bidi/deserializer"
require "puppeteer/bidi/injected_source"
require "puppeteer/bidi/lazy_arg"
require "puppeteer/bidi/js_handle"
require "puppeteer/bidi/keyboard"
require "puppeteer/bidi/mouse"
require "puppeteer/bidi/http_response"
require "puppeteer/bidi/element_handle"
require "puppeteer/bidi/query_handler"
require "puppeteer/bidi/wait_task"
require "puppeteer/bidi/realm"
require "puppeteer/bidi/frame"
require "puppeteer/bidi/file_chooser"
require "puppeteer/bidi/page"
require "puppeteer/bidi/target"
require "puppeteer/bidi/browser_context"
require "puppeteer/bidi/transport"
require "puppeteer/bidi/connection"
require "puppeteer/bidi/browser_launcher"
require "puppeteer/bidi/core"
require "puppeteer/bidi/browser"

module Puppeteer
  module Bidi
    # @rbs!
    #   type launch_options = {
    #     ?executable_path: String,
    #     ?user_data_dir: String,
    #     ?headless: bool,
    #     ?args: Array[String],
    #     ?timeout: Numeric
    #   }

    # Launch a new browser instance
    # @rbs **options: launch_options -- Launch options
    # @rbs return: Browser -- Browser instance
    def self.launch(**options)
      Browser.launch(**options)
    end

    # Connect to an existing browser instance
    # @rbs ws_endpoint: String -- WebSocket endpoint URL
    # @rbs return: Browser -- Browser instance
    def self.connect(ws_endpoint)
      Browser.connect(ws_endpoint)
    end
  end
end

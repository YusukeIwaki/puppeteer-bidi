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
    # Launch a new browser instance
    # @rbs executable_path: String? -- Path to Firefox executable
    # @rbs user_data_dir: String? -- User data directory for browser profile
    # @rbs headless: bool -- Run browser in headless mode (default: true)
    # @rbs args: Array[String] -- Additional command line arguments for Firefox
    # @rbs timeout: Numeric -- Timeout in seconds for browser launch (default: 30)
    # @rbs return: Browser
    def self.launch(executable_path: nil, user_data_dir: nil, headless: true, args: [], timeout: 30)
      Browser.launch(
        executable_path: executable_path,
        user_data_dir: user_data_dir,
        headless: headless,
        args: args,
        timeout: timeout
      )
    end

    # Connect to an existing browser instance
    # @rbs ws_endpoint: String
    # @rbs return: Browser
    def self.connect(ws_endpoint)
      Browser.connect(ws_endpoint)
    end
  end
end

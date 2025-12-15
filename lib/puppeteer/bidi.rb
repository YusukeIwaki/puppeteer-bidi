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
    # @rbs executable_path: String? -- Path to browser executable
    # @rbs user_data_dir: String? -- Path to user data directory
    # @rbs headless: bool -- Run browser in headless mode
    # @rbs args: Array[String]? -- Additional browser arguments
    # @rbs timeout: Numeric? -- Launch timeout in seconds
    # @rbs &block: (Browser) -> untyped -- Block to execute with the browser instance
    # @rbs return: untyped
    def self.launch(executable_path: nil, user_data_dir: nil, headless: true, args: nil, timeout: nil, &block)
      unless block
        raise ArgumentError, 'Block is required for launch_with_sync'
      end

      Sync do
        begin
          browser = launch_browser_instance(
            executable_path: executable_path,
            user_data_dir: user_data_dir,
            headless: headless,
            args: args,
            timeout: timeout
          )
          block.call(browser)
        ensure
          browser&.close
        end
      end
    end

    # Launch a new browser instance
    # @rbs executable_path: String? -- Path to browser executable
    # @rbs user_data_dir: String? -- Path to user data directory
    # @rbs headless: bool -- Run browser in headless mode
    # @rbs args: Array[String]? -- Additional browser arguments
    # @rbs timeout: Numeric? -- Launch timeout in seconds
    # @rbs return: Browser -- Browser instance (if no block given)
    def self.launch_browser_instance(executable_path: nil, user_data_dir: nil, headless: true, args: nil, timeout: nil)
      Browser.launch(
        executable_path: executable_path,
        user_data_dir: user_data_dir,
        headless: headless,
        args: args,
        timeout: timeout
      )
    end

    # Connect to an existing browser instance
    # @rbs ws_endpoint: String -- WebSocket endpoint URL
    # @rbs timeout: Numeric? -- Connect timeout in seconds
    # @rbs &block: (Browser) -> untyped -- Block to execute with the browser instance
    # @rbs return: untyped
    def self.connect(ws_endpoint, timeout: nil, &block)
      if block
        Sync do
          begin
            browser = Browser.connect(ws_endpoint, timeout: timeout)
            block.call(browser)
          ensure
            browser&.close
          end
        end
      else
        Browser.connect(ws_endpoint, timeout: timeout)
      end
    end
  end
end

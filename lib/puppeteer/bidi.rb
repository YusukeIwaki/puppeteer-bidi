# frozen_string_literal: true
# rbs_inline: enabled

# Check for Ruby versions affected by https://bugs.ruby-lang.org/issues/20907
# which causes hangs due to "Attempt to unlock a mutex which is not locked" errors.
# Fixed in: Ruby 3.2.7+, 3.3.7+, 3.4+
ruby_version = Gem::Version.new(RUBY_VERSION)
if ruby_version >= Gem::Version.new('3.2.0') && ruby_version < Gem::Version.new('3.2.7')
  raise "Ruby #{RUBY_VERSION} has a known issue that causes puppeteer-bidi to hang. " \
        "Please upgrade to Ruby 3.2.7+ or 3.3.7+ or 3.4+. " \
        "See: https://github.com/socketry/async/issues/424"
elsif ruby_version >= Gem::Version.new('3.3.0') && ruby_version < Gem::Version.new('3.3.7')
  raise "Ruby #{RUBY_VERSION} has a known issue that causes puppeteer-bidi to hang. " \
        "Please upgrade to Ruby 3.3.7+ or 3.4+. " \
        "See: https://github.com/socketry/async/issues/424"
end

require "fileutils"
require "puppeteer/bidi/version"
require "puppeteer/bidi/errors"
require "puppeteer/bidi/debug"

require "puppeteer/bidi/async_utils"
require "puppeteer/bidi/reactor_runner"
require "puppeteer/bidi/timeout_settings"
require "puppeteer/bidi/task_manager"
require "puppeteer/bidi/serializer"
require "puppeteer/bidi/deserializer"
require "puppeteer/bidi/injected_source"
require "puppeteer/bidi/lazy_arg"
require "puppeteer/bidi/cookie_utils"
require "puppeteer/bidi/devices"
require "puppeteer/bidi/http_utils"
require "puppeteer/bidi/js_handle"
require "puppeteer/bidi/keyboard"
require "puppeteer/bidi/mouse"
require "puppeteer/bidi/http_request"
require "puppeteer/bidi/http_response"
require "puppeteer/bidi/console_message"
require "puppeteer/bidi/dialog"
require "puppeteer/bidi/element_handle"
require "puppeteer/bidi/locator"
require "puppeteer/bidi/query_handler"
require "puppeteer/bidi/wait_task"
require "puppeteer/bidi/realm"
require "puppeteer/bidi/exposed_function"
require "puppeteer/bidi/frame"
require "puppeteer/bidi/file_chooser"
require "puppeteer/bidi/screen_recording"
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
    # @rbs accept_insecure_certs: bool -- Accept insecure certificates
    # @rbs logger: (^(String) -> (^(untyped) -> void)?)? -- Logger factory for protocol diagnostics
    # @rbs headers: Hash[String, String]? -- Deprecated handshake headers, superseded by ws_options
    # @rbs ws_options: Hash[Symbol, untyped]? -- WebSocket options (:headers, :keep_alive, :keep_alive_interval_ms)
    # @rbs &block: (Browser) -> untyped -- Block to execute with the browser instance
    # @rbs return: untyped
    def self.launch(executable_path: nil, user_data_dir: nil, headless: true, args: nil, timeout: nil,
                    accept_insecure_certs: false, logger: nil, headers: nil, ws_options: nil, &block)
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
            timeout: timeout,
            accept_insecure_certs: accept_insecure_certs,
            logger: logger,
            headers: headers,
            ws_options: ws_options
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
    # @rbs accept_insecure_certs: bool -- Accept insecure certificates
    # @rbs logger: (^(String) -> (^(untyped) -> void)?)? -- Logger factory for protocol diagnostics
    # @rbs headers: Hash[String, String]? -- Deprecated handshake headers, superseded by ws_options
    # @rbs ws_options: Hash[Symbol, untyped]? -- WebSocket options (:headers, :keep_alive, :keep_alive_interval_ms)
    # @rbs return: Browser -- Browser instance
    def self.launch_browser_instance(executable_path: nil, user_data_dir: nil, headless: true, args: nil, timeout: nil,
                                     accept_insecure_certs: false, logger: nil, headers: nil,
                                     ws_options: nil)
      if async_context?
        Browser.launch(
          executable_path: executable_path,
          user_data_dir: user_data_dir,
          headless: headless,
          args: args,
          timeout: timeout,
          accept_insecure_certs: accept_insecure_certs,
          logger: logger
        )
      else
        runner = ReactorRunner.new
        begin
          browser = runner.sync do
            Browser.launch(
              executable_path: executable_path,
              user_data_dir: user_data_dir,
              headless: headless,
              args: args,
              timeout: timeout,
              accept_insecure_certs: accept_insecure_certs,
              logger: logger
            )
          end
        rescue StandardError
          runner.close
          raise
        end
        # @type var proxy: Browser
        proxy = ReactorRunner::Proxy.new(runner, browser, owns_runner: true)
        proxy
      end
    end

    # Connect to an existing browser instance
    # @rbs ws_endpoint: String -- WebSocket endpoint URL
    # @rbs timeout: Numeric? -- Connect timeout in seconds
    # @rbs accept_insecure_certs: bool -- Accept insecure certificates
    # @rbs logger: (^(String) -> (^(untyped) -> void)?)? -- Logger factory for protocol diagnostics
    # @rbs headers: Hash[String, String]? -- Deprecated handshake headers, superseded by ws_options
    # @rbs ws_options: Hash[Symbol, untyped]? -- WebSocket options (:headers, :keep_alive, :keep_alive_interval_ms)
    # @rbs &block: (Browser) -> untyped -- Block to execute with the browser instance
    # @rbs return: untyped
    def self.connect(ws_endpoint, timeout: nil, accept_insecure_certs: false, logger: nil, headers: nil,
                   ws_options: nil, &block)
      unless block
        raise ArgumentError, 'Block is required for connect_with_sync'
      end

      Sync do
        begin
          browser = connect_to_browser_instance(ws_endpoint, timeout: timeout,
                                                accept_insecure_certs: accept_insecure_certs,
                                                logger: logger, headers: headers,
                                                ws_options: ws_options)
          block.call(browser)
        ensure
          browser&.close
        end
      end
    end

    # Connect to an existing browser instance
    # @rbs ws_endpoint: String -- WebSocket endpoint URL
    # @rbs timeout: Numeric? -- Connect timeout in seconds
    # @rbs accept_insecure_certs: bool -- Accept insecure certificates
    # @rbs logger: (^(String) -> (^(untyped) -> void)?)? -- Logger factory for protocol diagnostics
    # @rbs headers: Hash[String, String]? -- Deprecated handshake headers, superseded by ws_options
    # @rbs ws_options: Hash[Symbol, untyped]? -- WebSocket options (:headers, :keep_alive, :keep_alive_interval_ms)
    # @rbs return: Browser -- Browser instance
    def self.connect_to_browser_instance(ws_endpoint, timeout: nil, accept_insecure_certs: false, logger: nil,
                                         headers: nil, ws_options: nil)
      if async_context?
        Browser.connect(ws_endpoint, timeout: timeout, accept_insecure_certs: accept_insecure_certs,
                          logger: logger, headers: headers, ws_options: ws_options)
      else
        runner = ReactorRunner.new
        begin
          browser = runner.sync do
            Browser.connect(ws_endpoint, timeout: timeout, accept_insecure_certs: accept_insecure_certs,
                          logger: logger, headers: headers, ws_options: ws_options)
          end
        rescue StandardError
          runner.close
          raise
        end
        # @type var proxy: Browser
        proxy = ReactorRunner::Proxy.new(runner, browser, owns_runner: true)
        proxy
      end
    end

    @follow_symlinks = true

    # Defines whether file operations follow symlinks, mirroring upstream
    # `PuppeteerNode.setFollowSymlinks`. Defaults to true for compatibility;
    # when false, writes to symlinked paths raise Errno::ELOOP.
    # @rbs follow_symlinks: bool -- Whether to follow symlinks
    # @rbs return: void
    def self.set_follow_symlinks(follow_symlinks)
      @follow_symlinks = !!follow_symlinks
    end

    # @rbs return: bool -- Whether file operations follow symlinks
    def self.follow_symlinks?
      @follow_symlinks
    end

    # Write binary data to a file, creating parent directories as needed.
    # Honors the global symlink policy: with following disabled, symlinked
    # paths raise Errno::ELOOP instead of being traversed.
    # @rbs path: String -- Destination file path
    # @rbs data: String -- Binary data to write
    # @rbs return: Integer -- Bytes written
    def self.write_binary_file(path, data)
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      unless follow_symlinks?
        if File.const_defined?(:NOFOLLOW)
          flags = File::WRONLY | File::CREAT | File::TRUNC | File::NOFOLLOW
          File.open(path, flags, binmode: true) { |file| file.write(data) }
          return data.bytesize
        end
        raise Errno::ELOOP, path if File.symlink?(path)
      end
      File.binwrite(path, data)
    end

    # @rbs return: bool -- Whether we're inside an Async task
    def self.async_context?
      task = Async::Task.current
      !task.nil?
    rescue RuntimeError, NoMethodError
      false
    end
    private_class_method :async_context?
  end
end

# frozen_string_literal: true
# rbs_inline: enabled

require 'async'
require 'async/promise'

module Puppeteer
  module Bidi
    # Browser represents a browser instance with BiDi connection
    class Browser
      attr_reader :connection #: Connection
      attr_reader :process #: untyped
      attr_reader :default_browser_context #: BrowserContext
      attr_reader :ws_endpoint #: String?

      # @rbs connection: Connection -- BiDi connection
      # @rbs launcher: BrowserLauncher? -- Browser launcher instance
      # @rbs ws_endpoint: String? -- WebSocket endpoint URL
      # @rbs accept_insecure_certs: bool -- Accept insecure certificates
      # @rbs return: Browser -- Browser instance
      def self.create(connection:, launcher: nil, ws_endpoint: nil, accept_insecure_certs: false)
        # Create a new BiDi session
        session = Core::Session.from(
          connection: connection,
          capabilities: {
            alwaysMatch: {
              acceptInsecureCerts: accept_insecure_certs,
              unhandledPromptBehavior: { default: 'ignore' },
              webSocketUrl: true,
            },
          },
        ).wait

        core_browser = Core::Browser.from(session).wait
        session.browser = core_browser

        new(
          connection: connection,
          launcher: launcher,
          core_browser: core_browser,
          session: session,
          ws_endpoint: ws_endpoint,
        )
      end

      # @rbs connection: Connection -- BiDi connection
      # @rbs launcher: BrowserLauncher? -- Browser launcher instance
      # @rbs core_browser: Core::Browser -- Core browser instance
      # @rbs session: Core::Session -- BiDi session
      # @rbs ws_endpoint: String? -- WebSocket endpoint URL
      # @rbs return: void
      def initialize(connection:, launcher:, core_browser:, session:, ws_endpoint:)
        @connection = connection
        @launcher = launcher
        @closed = false
        @disconnected = false
        @core_browser = core_browser
        @session = session
        @ws_endpoint = ws_endpoint

        # Create default browser context
        default_user_context = @core_browser.default_user_context
        @default_browser_context = BrowserContext.new(self, default_user_context)
        @browser_contexts = {
          default_user_context.id => @default_browser_context
        }
      end

      # Launch a new Firefox browser instance
      # @rbs executable_path: String? -- Path to browser executable
      # @rbs user_data_dir: String? -- Path to user data directory
      # @rbs headless: bool -- Run browser in headless mode
      # @rbs args: Array[String]? -- Additional browser arguments
      # @rbs timeout: Numeric? -- Launch timeout in seconds
      # @rbs accept_insecure_certs: bool -- Accept insecure certificates
      # @rbs return: Browser -- Browser instance
      def self.launch(executable_path: nil, user_data_dir: nil, headless: true, args: nil, timeout: nil,
                      accept_insecure_certs: false)
        launcher = BrowserLauncher.new(
          executable_path: executable_path,
          user_data_dir: user_data_dir,
          headless: headless,
          args: args || []
        )

        ws_endpoint = launcher.launch

        # Create transport and connection
        transport = Transport.new(ws_endpoint)
        ws_endpoint = transport.url

        # Start transport connection in background thread with Sync reactor
        # Sync is the preferred way to run async code at the top level
        AsyncUtils.async_timeout((timeout || 30) * 1000, transport.connect).wait

        connection = Connection.new(transport)

        browser = create(connection: connection, launcher: launcher, ws_endpoint: ws_endpoint,
                         accept_insecure_certs: accept_insecure_certs)
        _target = browser.wait_for_target { |target| target.type == 'page' }
        browser
      end

      # Connect to an existing Firefox browser instance
      # @rbs ws_endpoint: String -- WebSocket endpoint URL
      # @rbs timeout: Numeric? -- Connect timeout in seconds
      # @rbs accept_insecure_certs: bool -- Accept insecure certificates
      # @rbs return: Browser -- Browser instance
      def self.connect(ws_endpoint, timeout: nil, accept_insecure_certs: false)
        transport = Transport.new(ws_endpoint)
        ws_endpoint = transport.url
        timeout_ms = ((timeout || 30) * 1000).to_i
        AsyncUtils.async_timeout(timeout_ms, transport.connect).wait
        connection = Connection.new(transport)

        # Verify that this endpoint speaks WebDriver BiDi (and is ready) before creating a new session.
        status = connection.async_send_command('session.status', {}, timeout: timeout_ms).wait
        unless status.is_a?(Hash) && status['ready'] == true
          raise Error, "WebDriver BiDi endpoint is not ready: #{status.inspect}"
        end

        create(connection: connection, launcher: nil, ws_endpoint: ws_endpoint,
               accept_insecure_certs: accept_insecure_certs)
      end

      # Get BiDi session status
      # @rbs return: untyped -- Session status
      def status
        @connection.async_send_command('session.status').wait
      end

      # Get the browser's original user agent
      # @rbs return: String -- User agent string
      def user_agent
        @session.capabilities["userAgent"]
      end

      # Create a new page (Puppeteer-like API)
      # @rbs return: Page -- New page instance
      def new_page
        @default_browser_context.new_page
      end

      # Create a new browser context
      # @rbs return: BrowserContext -- New browser context
      def create_browser_context
        user_context = @core_browser.create_user_context.wait
        browser_context_for(user_context)
      end

      # Get all pages
      # @rbs return: Array[Page] -- All pages
      def pages
        return [] if @closed || @disconnected

        @default_browser_context.pages
      end

      # Get all cookies in the default browser context.
      # @rbs return: Array[Hash[String, untyped]] -- Cookies
      def cookies
        @default_browser_context.cookies
      end

      # Set cookies in the default browser context.
      # @rbs *cookies: Array[Hash[String, untyped]] -- Cookie data
      # @rbs **cookie: untyped -- Single cookie via keyword arguments
      # @rbs return: void
      def set_cookie(*cookies, **cookie)
        @default_browser_context.set_cookie(*cookies, **cookie)
      end

      # Delete cookies in the default browser context.
      # @rbs *cookies: Array[Hash[String, untyped]] -- Cookies to delete
      # @rbs **cookie: untyped -- Single cookie via keyword arguments
      # @rbs return: void
      def delete_cookie(*cookies, **cookie)
        @default_browser_context.delete_cookie(*cookies, **cookie)
      end

      # Delete cookies matching the provided filters in the default browser context.
      # @rbs *filters: Array[Hash[String, untyped]] -- Cookie filters
      # @rbs **filter: untyped -- Single filter via keyword arguments
      # @rbs return: void
      def delete_matching_cookies(*filters, **filter)
        @default_browser_context.delete_matching_cookies(*filters, **filter)
      end

      # Register event handler
      # @rbs event: String | Symbol -- Event name
      # @rbs &block: (untyped) -> void -- Event handler
      # @rbs return: void
      def on(event, &block)
        @connection.on(event, &block)
      end

      # Close the browser
      # @rbs return: void
      def close
        return if @closed

        @closed = true

        begin
          begin
            @connection.async_send_command('browser.close', {}).wait
          rescue StandardError => e
            debug_error(e)
          ensure
            @connection.close
          end
        rescue => e
          debug_error(e)
        end

        @launcher&.kill
      end

      # Disconnect from the browser (does not close the browser process).
      # @rbs return: void
      def disconnect
        return if @closed || @disconnected

        @disconnected = true

        begin
          @session.end_session
        rescue StandardError => e
          debug_error(e)
        ensure
          begin
            @connection.close
          rescue StandardError => e
            debug_error(e)
          end
        end
      end

      # @rbs return: bool
      def closed?
        @closed
      end

      # @rbs return: bool
      def disconnected?
        @disconnected
      end

      # Wait until a target (top-level browsing context) satisfies the predicate.
      # @rbs timeout: Integer? -- Timeout in milliseconds (default: 30000)
      # @rbs &predicate: (BrowserTarget | PageTarget | FrameTarget) -> boolish -- Predicate evaluated against each Target
      # @rbs return: BrowserTarget | PageTarget | FrameTarget -- Matching target
      def wait_for_target(timeout: nil, &predicate)
        predicate ||= ->(_target) { true }
        timeout_ms = timeout || 30_000
        raise ArgumentError, 'timeout must be >= 0' if timeout_ms && timeout_ms.negative?

        if (target = find_target(predicate))
          return target
        end

        promise = Async::Promise.new
        session_listeners = []
        browser_listeners = []

        cleanup = lambda do
          session_listeners.each do |event, listener|
            @session.off(event, &listener)
          end
          session_listeners.clear

          browser_listeners.each do |event, listener|
            @core_browser.off(event, &listener)
          end
          browser_listeners.clear
        end

        check_and_resolve = lambda do
          return if promise.resolved?

          begin
            if (match = find_target(predicate))
              promise.resolve(match)
              cleanup.call
            end
          rescue => error
            promise.reject(error) unless promise.resolved?
            cleanup.call
          end
        end

        session_listener = proc { |_data| check_and_resolve.call }
        session_events = [
          :'browsingContext.contextCreated',
          :'browsingContext.navigationStarted',
          :'browsingContext.historyUpdated',
          :'browsingContext.fragmentNavigated',
          :'browsingContext.domContentLoaded',
          :'browsingContext.load'
        ]

        session_events.each do |event|
          @session.on(event, &session_listener)
          session_listeners << [event, session_listener]
        end

        browser_disconnect_listener = proc do |data|
          next if promise.resolved?

          reason = data[:reason] || 'Browser disconnected'
          promise.reject(Core::BrowserDisconnectedError.new(reason))
          cleanup.call
        end

        @core_browser.on(:disconnected, &browser_disconnect_listener)
        browser_listeners << [:disconnected, browser_disconnect_listener]

        # Re-check after listeners are set up to avoid missing fast events.
        check_and_resolve.call

        begin
          result = if timeout_ms
                     AsyncUtils.async_timeout(timeout_ms, promise).wait
                   else
                     promise.wait
                   end
        rescue Async::TimeoutError
          raise TimeoutError, "Waiting for target failed: timeout #{timeout_ms}ms exceeded"
        ensure
          cleanup.call
        end

        result
      end

      # Wait for browser process to exit
      # @rbs return: void
      def wait_for_exit
        @launcher&.wait
      end

      private

      def debug_error(error)
        return unless ENV['DEBUG_BIDI_COMMAND']

        warn(error.full_message)
      end

      # @rbs &block: (BrowserTarget | PageTarget | FrameTarget) -> void -- Block to yield each target to
      # @rbs return: Enumerator[BrowserTarget | PageTarget | FrameTarget, void] -- Enumerator of targets
      def each_target(&block)
        return enum_for(:each_target) unless block_given?
        return unless @core_browser

        yield BrowserTarget.new(self)

        @core_browser.user_contexts.each do |user_context|
          next if user_context.disposed?

          browser_context = browser_context_for(user_context)
          next unless browser_context

          user_context.browsing_contexts.each do |browsing_context|
            next if browsing_context.disposed?

            page = browser_context.page_for(browsing_context)
            yield PageTarget.new(page) if page
          end
        end
      end

      # @rbs predicate: ^(BrowserTarget | PageTarget | FrameTarget) -> boolish -- Predicate to match targets
      # @rbs return: (BrowserTarget | PageTarget | FrameTarget)? -- Matching target or nil
      def find_target(predicate)
        each_target do |target|
          return target if predicate.call(target)
        end
        nil
      end

      # @rbs user_context: Core::UserContext -- User context to get browser context for
      # @rbs return: BrowserContext -- Browser context
      def browser_context_for(user_context)
        return @browser_contexts[user_context.id] if @browser_contexts.key?(user_context.id)

        context = BrowserContext.new(self, user_context)
        user_context.once(:closed) do
          @browser_contexts.delete(user_context.id)
        end
        @browser_contexts[user_context.id] = context
      end
    end
  end
end

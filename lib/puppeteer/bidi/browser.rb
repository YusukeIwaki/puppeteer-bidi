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

      # @rbs connection: Connection -- BiDi connection
      # @rbs launcher: BrowserLauncher? -- Browser launcher instance
      # @rbs return: Browser -- Browser instance
      def self.create(connection:, launcher: nil)
        # Create a new BiDi session
        session = Core::Session.from(
          connection: connection,
          capabilities: {
            alwaysMatch: {
              acceptInsecureCerts: false,
              webSocketUrl: true,
            },
          },
        ).wait

        # Subscribe to BiDi modules before creating browser
        subscribe_modules = %w[
          browsingContext
          network
          log
          script
          input
        ]
        session.subscribe(subscribe_modules).wait

        core_browser = Core::Browser.from(session).wait
        session.browser = core_browser

        new(
          connection: connection,
          launcher: launcher,
          core_browser: core_browser,
          session: session,
        )
      end

      # @rbs connection: Connection -- BiDi connection
      # @rbs launcher: BrowserLauncher? -- Browser launcher instance
      # @rbs core_browser: Core::Browser -- Core browser instance
      # @rbs session: Core::Session -- BiDi session
      # @rbs return: void
      def initialize(connection:, launcher:, core_browser:, session:)
        @connection = connection
        @launcher = launcher
        @closed = false
        @core_browser = core_browser
        @session = session

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
      # @rbs return: Browser -- Browser instance
      def self.launch(executable_path: nil, user_data_dir: nil, headless: true, args: nil, timeout: nil)
        launcher = BrowserLauncher.new(
          executable_path: executable_path,
          user_data_dir: user_data_dir,
          headless: headless,
          args: args || []
        )

        ws_endpoint = launcher.launch

        # Create transport and connection
        transport = Transport.new(ws_endpoint)

        # Start transport connection in background thread with Sync reactor
        # Sync is the preferred way to run async code at the top level
        AsyncUtils.async_timeout((timeout || 30) * 1000, transport.connect).wait

        connection = Connection.new(transport)

        browser = create(connection: connection, launcher: launcher)
        target = browser.wait_for_target { |target| target.type == 'page' }
        browser
      end

      # Connect to an existing Firefox browser instance
      # @rbs ws_endpoint: String -- WebSocket endpoint URL
      # @rbs return: Browser -- Browser instance
      def self.connect(ws_endpoint)
        transport = Transport.new(ws_endpoint)
        AsyncUtils.async_timeout(30 * 1000, transport.connect).wait
        connection = Connection.new(transport)
        create(connection: connection, launcher: nil)
      end

      # Get BiDi session status
      # @rbs return: untyped -- Session status
      def status
        @connection.async_send_command('session.status').wait
      end

      # Create a new page (Puppeteer-like API)
      # @rbs return: Page -- New page instance
      def new_page
        @default_browser_context.new_page
      end

      # Get all pages
      # @rbs return: Array[Page] -- All pages
      def pages
        @default_browser_context.pages
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
          @connection.close
        rescue => e
          warn "Error closing connection: #{e.message}"
        end

        @launcher&.kill
      end

      # @rbs return: bool
      def closed?
        @closed
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
      # @rbs return: BrowserContext? -- Browser context or nil
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

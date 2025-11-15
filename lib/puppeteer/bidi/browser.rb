# frozen_string_literal: true

require 'async'
require 'async/promise'

module Puppeteer
  module Bidi
    # Browser represents a browser instance with BiDi connection
    class Browser
      attr_reader :connection, :process, :default_browser_context

      def initialize(connection:, launcher: nil, connection_task: nil)
        @connection = connection
        @launcher = launcher
        @connection_task = connection_task
        @closed = false
        @core_browser = nil
        @default_browser_context = nil

        # Create a new BiDi session
        session_info = @connection.send_command('session.new', {
          capabilities: {
            alwaysMatch: {
              acceptInsecureCerts: false,
              webSocketUrl: true,
            },
          },
        })

        # Initialize the Core layer
        @session = Core::Session.new(@connection, session_info)

        # Subscribe to BiDi modules before creating browser
        subscribe_modules = %w[
          browsingContext
          network
          log
          script
          input
        ]
        @session.subscribe(subscribe_modules)

        @core_browser = Core::Browser.from(@session)
        @session.browser = @core_browser

        # Create default browser context
        default_user_context = @core_browser.default_user_context
        @default_browser_context = BrowserContext.new(self, default_user_context)
        @browser_contexts = {
          default_user_context.id => @default_browser_context
        }
      end

      # Launch a new Firefox browser instance
      # @param options [Hash] Launch options
      # @option options [String] :executable_path Path to Firefox executable
      # @option options [Boolean] :headless Run in headless mode (default: true)
      # @option options [Array<String>] :args Additional arguments
      # @option options [String] :user_data_dir User data directory
      # @return [Browser] Browser instance
      def self.launch(**options)
        launcher = BrowserLauncher.new(
          executable_path: options[:executable_path],
          user_data_dir: options[:user_data_dir],
          headless: options.fetch(:headless, true),
          args: options.fetch(:args, [])
        )

        ws_endpoint = launcher.launch

        # Create transport and connection
        transport = Transport.new(ws_endpoint)

        # Start transport connection in background thread with Sync reactor
        # Sync is the preferred way to run async code at the top level
        connection_task = Thread.new do
          Sync do
            transport.connect
          end
        end

        # Wait for connection to be established
        transport.wait_for_connection(timeout: options.fetch(:timeout, 30))

        connection = Connection.new(transport)

        browser = new(connection: connection, launcher: launcher, connection_task: connection_task)
        target = browser.wait_for_target { |target| target.type == 'page' }
        browser
      end

      # Connect to an existing browser instance
      # @param ws_endpoint [String] WebSocket endpoint URL
      # @return [Browser] Browser instance
      def self.connect(ws_endpoint, **options)
        transport = Transport.new(ws_endpoint)

        connection_task = Thread.new do
          Sync do
            transport.connect
          end
        end

        transport.wait_for_connection(timeout: options.fetch(:timeout, 30))

        connection = Connection.new(transport)

        new(connection: connection, connection_task: connection_task)
      end

      # Get BiDi session status
      def status
        @connection.send_command('session.status')
      end

      # Create a new page (Puppeteer-like API)
      # @return [Page] New page instance
      def new_page
        @default_browser_context.new_page
      end

      # Get all pages
      # @return [Array<Page>] All pages
      def pages
        @default_browser_context.pages
      end

      # Create a new browsing context (similar to opening a new tab)
      # @param type [String] Context type ('tab' or 'window')
      # @return [Hash] Context info with 'context' id
      def new_context(type: 'tab')
        @connection.send_command('browsingContext.create', {
          type: type
        })
      end

      # Get all browsing contexts
      # @return [Hash] Contexts tree
      def contexts
        @connection.send_command('browsingContext.getTree', {})
      end

      # Navigate a browsing context to URL
      # @param context [String] Context ID
      # @param url [String] URL to navigate to
      # @param wait [String] Wait condition ('none', 'interactive', 'complete')
      # @return [Hash] Navigation result
      def navigate(context:, url:, wait: 'complete')
        @connection.send_command('browsingContext.navigate', {
          context: context,
          url: url,
          wait: wait
        })
      end

      # Close a browsing context
      # @param context [String] Context ID
      def close_context(context)
        @connection.send_command('browsingContext.close', {
          context: context
        })
      end

      # Subscribe to BiDi events
      # @param events [Array<String>] Event names to subscribe to
      # @param contexts [Array<String>] Context IDs (optional)
      def subscribe(events, contexts: nil)
        params = { events: events }
        params[:contexts] = contexts if contexts

        @connection.send_command('session.subscribe', params)
      end

      # Register event handler
      # @param event [String] Event name
      # @param block [Proc] Event handler
      def on(event, &block)
        @connection.on(event, &block)
      end

      # Close the browser
      def close
        return if @closed

        @closed = true

        begin
          @connection.close
        rescue => e
          warn "Error closing connection: #{e.message}"
        end

        # Wait for connection task to finish
        @connection_task&.join(2)

        @launcher&.kill
      end

      def closed?
        @closed
      end

      # Wait until a target (top-level browsing context) satisfies the predicate.
      # @param timeout [Integer, nil] Timeout in milliseconds (default: 30000).
      # @yield [target] Predicate evaluated against each Target (defaults to truthy).
      # @return [Target] Matching target.
      # @raise [TimeoutError] When timeout is reached without a match.
      # @raise [Core::BrowserDisconnectedError] When browser disconnects before match.
      def wait_for_target(timeout: nil, &predicate)
        predicate ||= ->(_target) { true }
        timeout_ms = timeout.nil? ? 30_000 : timeout
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
      def wait_for_exit
        @launcher&.wait
      end

      private

      def each_target
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

      def find_target(predicate)
        each_target do |target|
          return target if predicate.call(target)
        end
        nil
      end

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

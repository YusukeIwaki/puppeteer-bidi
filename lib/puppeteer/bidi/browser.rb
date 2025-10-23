# frozen_string_literal: true

require 'async'

module Puppeteer
  module Bidi
    # Browser represents a browser instance with BiDi connection
    class Browser
      attr_reader :connection, :process

      def initialize(connection:, launcher: nil, connection_task: nil)
        @connection = connection
        @launcher = launcher
        @connection_task = connection_task
        @closed = false

        # Create a new BiDi session
        @connection.send_command('session.new', {
          capabilities: {
            alwaysMatch: {
              acceptInsecureCerts: false,
              webSocketUrl: true,
            },
          },
        })
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

        new(connection: connection, launcher: launcher, connection_task: connection_task)
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

      # Wait for browser process to exit
      def wait_for_exit
        @launcher&.wait
      end
    end
  end
end

# frozen_string_literal: true
# rbs_inline: enabled

require 'async'
require 'async/websocket/client'
require 'async/http/endpoint'
require 'json'

module Puppeteer
  module Bidi
    # Transport handles WebSocket communication with BiDi server
    # This is the lowest layer that manages raw WebSocket send/receive
    class Transport
      class ClosedError < Error; end

      # Default WebSocket ping interval in milliseconds, mirroring upstream
      # `DEFAULT_KEEP_ALIVE_INTERVAL_MS`. Only used when keep-alive is enabled.
      DEFAULT_KEEP_ALIVE_INTERVAL_MS = 30_000 #: Integer

      # Connection subclass that reports incoming pong frames so the
      # keep-alive loop can tell a live peer from a dead one.
      class KeepAliveConnection < Async::WebSocket::Connection
        attr_writer :pong_handler #: (^(void))? -- Callback invoked on each pong frame

        def receive_pong(_frame)
          @pong_handler&.call
        end
      end

      attr_reader :url

      # @rbs url: String -- WebSocket endpoint URL
      # @rbs logger: (^(String) -> (^(untyped) -> void)?)? -- Logger factory, defaults to env-gated debug output
      # @rbs headers: Hash[String, String]? -- Deprecated handshake headers, superseded by ws_options
      # @rbs ws_options: Hash[Symbol, untyped]? -- WebSocket options (:headers, :keep_alive, :keep_alive_interval_ms)
      # @rbs return: void
      def initialize(url, logger: nil, headers: nil, ws_options: nil)
        @url = url
        @endpoint = nil
        @connection = nil
        @task = nil
        @keep_alive_task = nil
        @keep_alive_awaiting_pong = false
        @connected = false
        @closed = false
        @on_message = nil
        @on_close = nil
        @logger = logger || Debug.default_logger
        @logger_explicit = !logger.nil?
        @debug_error = @logger&.call(Debug::ERROR)
        @headers = ws_option(ws_options, :headers) || headers
        @keep_alive = !!ws_option(ws_options, :keep_alive)
        @keep_alive_interval_ms = ws_option(ws_options, :keep_alive_interval_ms) ||
                                  DEFAULT_KEEP_ALIVE_INTERVAL_MS
      end

      # @rbs return: bool -- Whether WebSocket keep-alive pinging is enabled
      def keep_alive_enabled?
        @keep_alive
      end

      # Connect to WebSocket and start receiving messages
      def connect
        connection_promise = Async::Promise.new
        @task = Async do |task|
          endpoint = Async::HTTP::Endpoint.parse(@url)

          connect_options = {}
          connect_options[:headers] = @headers if @headers
          connect_options[:handler] = KeepAliveConnection if @keep_alive

          # Connect to WebSocket - this matches minibidi's implementation
          Async::WebSocket::Client.connect(endpoint, **connect_options) do |connection|
            @connection = connection
            @connected = true
            connection_promise.resolve(connection)
            start_keepalive(connection) if @keep_alive

            # Start message receiving loop (this will block until connection closes)
            receive_loop(connection)
          end
        rescue => e
          log_error("Transport connect error: #{e.class} - #{e.message}")
          log_error(e.backtrace.join("\n"))
          connection_promise.reject(e)
          close
        ensure
          @connected = false
        end
        connection_promise
      end

      # Send a message to BiDi server
      def async_send_message(message)
        raise ClosedError, 'Transport is closed' if @closed

        debug_print_send(message)
        json = JSON.generate(message)
        Async do
          @connection&.write(json)
          @connection&.flush
        end
      end

      # Register message handler
      def on_message(&block)
        @on_message = block
      end

      # Register close handler
      def on_close(&block)
        @on_close = block
      end

      # Close the WebSocket connection
      def close
        return if @closed

        @closed = true
        stop_keepalive
        @connection&.close
        @on_close&.call
        @task&.stop
      end

      def closed?
        @closed
      end

      def connected?
        @connected && !@closed
      end

      private

      # Read a ws_options entry by snake_case or camelCase key.
      def ws_option(ws_options, name)
        return nil unless ws_options

        camel = name.to_s.gsub(/_([a-z])/) { $1.upcase }.to_sym
        if ws_options.key?(name)
          ws_options[name]
        elsif ws_options.key?(name.to_s)
          ws_options[name.to_s]
        elsif ws_options.key?(camel)
          ws_options[camel]
        elsif ws_options.key?(camel.to_s)
          ws_options[camel.to_s]
        end
      end

      # Periodically ping the peer and locally close the transport when the
      # pong for the previous ping never arrived, mirroring upstream's
      # keep-alive which terminates half-open connections.
      def start_keepalive(connection)
        interval = @keep_alive_interval_ms / 1000.0
        @keep_alive_awaiting_pong = false
        connection.pong_handler = -> { @keep_alive_awaiting_pong = false } if connection.respond_to?(:pong_handler=)
        @keep_alive_task = Async do |keep_alive|
          loop do
            keep_alive.sleep(interval)
            break if @closed

            if @keep_alive_awaiting_pong
              # terminate() rather than close(): the peer is not answering, so
              # a close handshake would hang. Local close surfaces the dead
              # connection to the rest of Puppeteer.
              close
              break
            end

            @keep_alive_awaiting_pong = true
            begin
              connection.send_ping
              # Ping frames are buffered; flush to ensure the peer receives them.
              connection.flush
            rescue => error
              log_error("WebSocket keepalive ping failed: #{error.message}")
              close
              break
            end
          end
        end
      end

      def stop_keepalive
        keep_alive_task = @keep_alive_task
        @keep_alive_task = nil
        @keep_alive_awaiting_pong = false
        return unless keep_alive_task

        # Never stop the calling task itself: stopping the current task
        # raises Stop immediately and would abort the close sequence.
        # The keepalive loop exits on its own via `break` after close.
        keep_alive_task.stop unless keep_alive_task == current_task
      end

      def current_task
        Async::Task.current
      rescue RuntimeError, NoMethodError
        nil
      end

      def receive_loop(connection)
        while (message = connection.read)
          next if message.nil?

          Async do
            data = JSON.parse(message.to_str)
            debug_print_receive(data)
            @on_message&.call(data)
          rescue JSON::ParserError => e
            log_error("Failed to parse BiDi message: #{e.message}")
          end
        end
      rescue IOError, Errno::ECONNRESET, Errno::EPIPE
        # Connection closed - this is expected during shutdown, no need to warn
      rescue => e
        # Only warn for unexpected errors if we weren't intentionally closed
        log_error("Transport receive error: #{e.message}") unless @closed
      ensure
        close unless @closed
      end

      # Protocol traffic itself is logged once by Connection. Without an
      # explicit logger, preserve the legacy DEBUG_PROTOCOL output here.
      def debug_print_send(message)
        return if @logger_explicit

        if %w[1 true].include?(ENV['DEBUG_PROTOCOL'])
          puts "SEND >> #{JSON.generate(message)}"
        end
      end

      def debug_print_receive(message)
        return if @logger_explicit

        if %w[1 true].include?(ENV['DEBUG_PROTOCOL'])
          puts "RECV << #{JSON.generate(message)}"
        end
      end

      # Report diagnostics through the error logger when enabled. Without
      # an explicit logger, fall back to `warn` for legacy behavior.
      def log_error(message)
        if @debug_error
          @debug_error.call(message)
        elsif !@logger_explicit
          warn message
        end
      end
    end
  end
end

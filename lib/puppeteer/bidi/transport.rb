# frozen_string_literal: true
# rbs_inline: enabled

require 'async'
require 'async/websocket/client'
require 'async/http/endpoint'
require 'json'
require 'uri'

module Puppeteer
  module Bidi
    # Transport handles WebSocket communication with BiDi server
    # This is the lowest layer that manages raw WebSocket send/receive
    class Transport
      class ClosedError < Error; end

      attr_reader :url

      def initialize(url)
        # BiDi WebSocket endpoint requires /session path
        @url = url.end_with?('/session') ? url : "#{url}/session"
        @endpoint = nil
        @connection = nil
        @task = nil
        @connected = false
        @closed = false
        @on_message = nil
        @on_close = nil
      end

      # Connect to WebSocket and start receiving messages
      def connect
        connection_promise = Async::Promise.new
        @task = Async do |task|
          endpoint = Async::HTTP::Endpoint.parse(@url)

          # Connect to WebSocket - this matches minibidi's implementation
          Async::WebSocket::Client.connect(endpoint) do |connection|
            @connection = connection
            @connected = true
            connection_promise.resolve(connection)

            # Start message receiving loop (this will block until connection closes)
            receive_loop(connection)
          end
        rescue => e
          warn "Transport connect error: #{e.class} - #{e.message}"
          warn e.backtrace.join("\n")
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

      def receive_loop(connection)
        while (message = connection.read)
          next if message.nil?

          Async do
            data = JSON.parse(message.to_str)
            debug_print_receive(data)
            @on_message&.call(data)
          rescue JSON::ParserError => e
            warn "Failed to parse BiDi message: #{e.message}"
          end
        end
      rescue IOError, Errno::ECONNRESET, Errno::EPIPE
        # Connection closed - this is expected during shutdown, no need to warn
      rescue => e
        # Only warn for unexpected errors if we weren't intentionally closed
        warn "Transport receive error: #{e.message}" unless @closed
      ensure
        close unless @closed
      end

      def debug_print_send(message)
        if %w[1 true].include?(ENV['DEBUG_PROTOCOL'])
          puts "SEND >> #{JSON.generate(message)}"
        end
      end

      def debug_print_receive(message)
        if %w[1 true].include?(ENV['DEBUG_PROTOCOL'])
          puts "RECV << #{JSON.generate(message)}"
        end
      end
    end
  end
end

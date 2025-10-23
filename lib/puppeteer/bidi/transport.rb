# frozen_string_literal: true

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
        @task = Async do |task|
          endpoint = Async::HTTP::Endpoint.parse(@url)

          # Connect to WebSocket - this matches minibidi's implementation
          Async::WebSocket::Client.connect(endpoint) do |connection|
            @connection = connection
            @connected = true

            # Start message receiving loop (this will block until connection closes)
            receive_loop(connection)
          end
        rescue => e
          warn "Transport connect error: #{e.class} - #{e.message}"
          warn e.backtrace.join("\n")
          close
        ensure
          @connected = false
        end
      end

      # Send a message to BiDi server
      def send_message(message)
        raise ClosedError, 'Transport is closed' if @closed

        json = JSON.generate(message)
        Async do
          @connection&.write(json)
          @connection&.flush
        end.wait
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
      end

      def closed?
        @closed
      end

      def connected?
        @connected && !@closed
      end

      # Wait for connection to be established
      def wait_for_connection(timeout: 10)
        deadline = Time.now + timeout
        until connected?
          if Time.now > deadline
            raise ClosedError, 'Timeout waiting for connection'
          end
          sleep(0.05)
        end
        true
      end

      private

      def receive_loop(connection)
        while (message = connection.read)
          next if message.nil?

          begin
            data = JSON.parse(message)
            @on_message&.call(data)
          rescue JSON::ParserError => e
            warn "Failed to parse BiDi message: #{e.message}"
          end
        end
      rescue => e
        warn "Transport receive error: #{e.message}"
      ensure
        close unless @closed
      end
    end
  end
end

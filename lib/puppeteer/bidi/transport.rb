# frozen_string_literal: true

require 'async'
require 'async/websocket/client'
require 'json'

module Puppeteer
  module Bidi
    # Transport handles WebSocket communication with BiDi server
    # This is the lowest layer that manages raw WebSocket send/receive
    class Transport
      class ClosedError < Error; end

      attr_reader :url

      def initialize(url)
        @url = url
        @endpoint = nil
        @connection = nil
        @closed = false
        @on_message = nil
        @on_close = nil
      end

      # Connect to WebSocket and start receiving messages
      def connect
        Async do |task|
          @endpoint = Async::HTTP::Endpoint.parse(@url)

          Async::WebSocket::Client.connect(@endpoint) do |connection|
            @connection = connection

            # Start message receiving loop
            task.async do
              receive_loop(connection)
            end

            # Keep connection alive
            task.sleep
          end
        ensure
          close
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

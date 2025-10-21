# frozen_string_literal: true

require 'async'
require 'async/barrier'
require 'async/queue'
require 'concurrent'

module Puppeteer
  module Bidi
    # Connection manages BiDi protocol communication
    # Handles command sending, response waiting, and event dispatching
    class Connection
      class TimeoutError < Error; end
      class ProtocolError < Error; end

      DEFAULT_TIMEOUT = 30_000 # 30 seconds in milliseconds

      def initialize(transport)
        @transport = transport
        @next_id = 1
        @pending_commands = Concurrent::Map.new
        @event_listeners = Concurrent::Map.new
        @closed = false

        setup_transport_handlers
      end

      # Send a BiDi command and wait for response
      # @param method [String] BiDi method name (e.g., 'browsingContext.navigate')
      # @param params [Hash] Command parameters
      # @param timeout [Integer] Timeout in milliseconds
      # @return [Hash] Command result
      def send_command(method, params = {}, timeout: DEFAULT_TIMEOUT)
        raise ProtocolError, 'Connection is closed' if @closed

        id = next_id
        command = {
          id: id,
          method: method,
          params: params
        }

        # Create promise for this command
        promise = Concurrent::Promises.resolvable_future

        @pending_commands[id] = {
          promise: promise,
          method: method,
          sent_at: Time.now
        }

        # Send command through transport
        @transport.send_message(command)

        # Wait for response with timeout
        begin
          timeout_seconds = timeout / 1000.0
          result = promise.value!(timeout_seconds)

          # Debug output
          if ENV['DEBUG_BIDI']
            puts "[BiDi] Response for #{method}: #{result.inspect}"
          end

          if result['error']
            raise ProtocolError, "BiDi error (#{method}): #{result['error']['message']}"
          end

          result['result']
        rescue Concurrent::TimeoutError
          @pending_commands.delete(id)
          raise TimeoutError, "Timeout waiting for #{method} (#{timeout}ms)"
        end
      end

      # Subscribe to BiDi events
      # @param event [String] Event name (e.g., 'browsingContext.navigationStarted')
      # @param block [Proc] Event handler
      def on(event, &block)
        @event_listeners[event] ||= []
        @event_listeners[event] << block
      end

      # Unsubscribe from BiDi events
      def off(event, &block)
        return unless @event_listeners[event]

        if block
          @event_listeners[event].delete(block)
        else
          @event_listeners.delete(event)
        end
      end

      # Close the connection
      def close
        return if @closed

        @closed = true

        # Reject all pending commands
        @pending_commands.each_value do |pending|
          pending[:promise].reject(ProtocolError.new('Connection closed'))
        end
        @pending_commands.clear

        @transport.close
      end

      def closed?
        @closed
      end

      private

      def next_id
        id = @next_id
        @next_id += 1
        id
      end

      def setup_transport_handlers
        @transport.on_message do |message|
          handle_message(message)
        end

        @transport.on_close do
          close
        end
      end

      def handle_message(message)
        # Response to a command (has 'id' field)
        if message['id']
          handle_response(message)
        # Event (has 'method' but no 'id')
        elsif message['method']
          handle_event(message)
        else
          warn "Unknown BiDi message format: #{message}"
        end
      end

      def handle_response(message)
        id = message['id']
        pending = @pending_commands.delete(id)

        unless pending
          warn "Received response for unknown command id: #{id}"
          return
        end

        # Fulfill the promise with the response
        pending[:promise].fulfill(message)
      end

      def handle_event(message)
        method = message['method']
        params = message['params'] || {}

        listeners = @event_listeners[method]
        return unless listeners

        # Call all registered listeners for this event
        listeners.each do |listener|
          begin
            listener.call(params)
          rescue => e
            warn "Error in event listener for #{method}: #{e.message}"
          end
        end
      end
    end
  end
end

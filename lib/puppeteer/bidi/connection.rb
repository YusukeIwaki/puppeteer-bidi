# frozen_string_literal: true

require 'async'
require 'async/promise'

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
        @pending_commands = {}
        @event_listeners = {}
        @closed = false

        setup_transport_handlers
      end

      # Send a BiDi command and wait for response
      # @param method [String] BiDi method name (e.g., 'browsingContext.navigate')
      # @param params [Hash] Command parameters
      # @param timeout [Integer] Timeout in milliseconds
      # @return [Hash] Command result
      def async_send_command(method, params = {}, timeout: DEFAULT_TIMEOUT)
        raise ProtocolError, 'Connection is closed' if @closed

        id = next_id
        command = {
          id: id,
          method: method,
          params: params
        }

        # Create promise for this command
        promise = Async::Promise.new

        @pending_commands[id] = {
          promise: promise,
          method: method,
          sent_at: Time.now
        }

        # Debug output
        if ENV['DEBUG_BIDI_COMMAND']
          puts "[BiDi] Request #{method}: #{command.inspect}"
        end

        Async do
          # Send command through transport
          @transport.async_send_message(command).wait

          # Wait for response with timeout
          begin
            result = AsyncUtils.async_timeout(timeout, promise).wait

            # Debug output
            if ENV['DEBUG_BIDI_COMMAND']
              puts "[BiDi] Response for #{method}: #{result.inspect}"
            end

            if result['error']
              # BiDi error format: { "error": "error_type", "message": "detailed message", ... }
              error_type = result['error']
              error_message = result['message'] || error_type
              raise ProtocolError, "BiDi error (#{method}): #{error_message}"
            end

            result['result']
          rescue Async::TimeoutError
            @pending_commands.delete(id)
            raise TimeoutError, "Timeout waiting for #{method} (#{timeout}ms)"
          end
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

        # Resolve the promise with the response
        pending[:promise].resolve(message)
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

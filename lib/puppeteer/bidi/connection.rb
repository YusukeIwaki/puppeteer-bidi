# frozen_string_literal: true
# rbs_inline: enabled

require 'async'
require 'async/promise'
require 'json'

module Puppeteer
  module Bidi
    # Connection manages BiDi protocol communication
    # Handles command sending, response waiting, and event dispatching
    class Connection
      class TimeoutError < Error; end
      class ProtocolError < Error; end

      DEFAULT_TIMEOUT = 30_000 #: Integer -- 30 seconds in milliseconds

      # @rbs transport: Transport
      # @rbs logger: (^(String) -> (^(untyped) -> void)?)? -- Logger factory, defaults to env-gated debug output
      # @rbs return: void
      def initialize(transport, logger: nil)
        @transport = transport
        @next_id = 1
        @pending_commands = {} #: Hash[Integer, Hash[Symbol, untyped]]
        @event_listeners = {} #: Hash[String, Array[^(untyped) -> void]]
        @closed = false
        @logger = logger || Debug.default_logger
        @debug_send = @logger&.call(Debug::BIDI_SEND)
        @debug_receive = @logger&.call(Debug::BIDI_RECEIVE)
        @debug_error = @logger&.call(Debug::ERROR)

        setup_transport_handlers
      end

      # Send a BiDi command and wait for response
      # @rbs method: String
      # @rbs params: Hash[String | Symbol, untyped]
      # @rbs timeout: Integer
      # @rbs return: Async::Task[Hash[String, untyped]]
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

        @debug_send&.call(JSON.generate(command))

        Async do
          # Send command through transport
          @transport.async_send_message(command).wait

          # Wait for response with timeout
          begin
            result = AsyncUtils.async_timeout(timeout, promise).wait

            @debug_receive&.call(result.inspect)

            unless result.is_a?(Hash) && result.key?('type')
              raise ProtocolError, "Protocol Error. Message is not in BiDi protocol format: #{result.inspect}"
            end

            case result['type']
            when 'success'
              result['result']
            when 'error'
              # BiDi error format: { "type": "error", "error": "...", "message": "...", ... }
              error_type = result['error'] || 'unknown error'
              error_message = result['message'] || error_type
              raise ProtocolError, "BiDi error (#{method}): #{error_message}"
            else
              raise ProtocolError, "Protocol Error. Unexpected BiDi message type: #{result['type'].inspect}"
            end
          rescue Async::TimeoutError
            raise TimeoutError, "Timeout waiting for #{method} (#{timeout}ms)"
          end
        ensure
          # A send that raises, an encoding failure for instance, would otherwise leave
          # the command and its promise pending for the life of the connection.
          @pending_commands.delete(id)
        end
      end

      # Subscribe to BiDi events
      # @rbs event: String
      # @rbs &block: (untyped) -> void
      # @rbs return: Connection -- This connection
      def on(event, &block)
        @event_listeners[event] ||= []
        @event_listeners[event] << block
        self
      end

      # Unsubscribe from BiDi events
      # @rbs event: String
      # @rbs &block: ((untyped) -> void)?
      # @rbs return: Connection -- This connection
      def off(event, &block)
        return self unless @event_listeners[event]

        if block
          @event_listeners[event].delete(block)
        else
          @event_listeners.delete(event)
        end
        self
      end

      # Close the connection
      # @rbs return: void
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

      # @rbs return: bool
      def closed?
        @closed
      end

      private

      # Report diagnostics through the error logger when enabled,
      # falling back to `warn` otherwise.
      # @rbs message: String -- Diagnostic message
      # @rbs return: void
      def log_error(message)
        if @debug_error
          @debug_error.call(message)
        else
          warn message
        end
      end

      # @rbs return: Integer
      def next_id
        id = @next_id
        @next_id += 1
        id
      end

      # @rbs return: void
      def setup_transport_handlers
        @transport.on_message do |message|
          handle_message(message)
        end

        @transport.on_close do
          close
        end
      end

      # @rbs message: Hash[String, untyped]
      # @rbs return: void
      def handle_message(message)
        # Response to a command (has 'id' field)
        if message['id']
          handle_response(message)
        # Event (has 'method' but no 'id')
        elsif message['method']
          handle_event(message)
        else
          log_error("Unknown BiDi message format: #{message}")
        end
      end

      # @rbs message: Hash[String, untyped]
      # @rbs return: void
      def handle_response(message)
        id = message['id']
        pending = @pending_commands.delete(id)

        unless pending
          log_error("Received response for unknown command id: #{id}")
          return
        end

        # Resolve the promise with the response
        pending[:promise].resolve(message)
      end

      # @rbs message: Hash[String, untyped]
      # @rbs return: void
      def handle_event(message)
        method = message['method']
        params = message['params'] || {}

        @debug_receive&.call("Event #{method}: #{params.inspect}")

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

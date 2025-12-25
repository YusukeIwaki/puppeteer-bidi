# frozen_string_literal: true
# rbs_inline: enabled

require 'json'
require 'securerandom'

module Puppeteer
  module Bidi
    # ExposedFunction manages the lifecycle of a function exposed to the page.
    # It uses a polling mechanism via evaluate to handle function calls from the page.
    class ExposedFunction
      # Create and initialize an exposed function.
      # @rbs frame: Frame -- Frame to expose the function in
      # @rbs name: String -- Function name
      # @rbs block: Proc -- Ruby block to execute
      # @rbs return: ExposedFunction -- Initialized exposed function
      def self.from(frame, name, &block)
        func = new(frame, name, &block)
        func.send(:setup)
        func
      end

      attr_reader :name #: String

      # @rbs frame: Frame -- Frame to expose the function in
      # @rbs name: String -- Function name
      # @rbs block: Proc -- Ruby block to execute
      # @rbs return: void
      def initialize(frame, name, &block)
        @frame = frame
        @name = name
        @block = block
        @channel = "__puppeteer_ruby_#{SecureRandom.uuid.gsub('-', '')}"
        @preload_script_id = nil
        @disposed = false
        @polling_task = nil
      end

      # Check if this exposed function is disposed.
      # @rbs return: bool -- Whether disposed
      def disposed?
        @disposed
      end

      # Dispose this exposed function, removing it from the page.
      # @rbs return: void
      def dispose
        return if @disposed

        @disposed = true

        # Cancel polling task
        @polling_task&.stop rescue nil

        # Remove preload script
        if @preload_script_id
          begin
            browsing_context.remove_preload_script(@preload_script_id).wait
          rescue StandardError
            # Ignore errors during cleanup
          end
        end
      end

      private

      # Set up the exposed function by injecting it into the page.
      # @rbs return: void
      def setup
        # Create the function wrapper script that is self-contained
        wrapper_script = build_preload_script

        # Add as preload script for persistence across navigations
        @preload_script_id = browsing_context.add_preload_script(wrapper_script).wait

        # Also inject into the current page immediately
        inject_into_current_page

        # Start polling for calls
        start_polling
      end

      # Build the JavaScript preload script that sets up the exposed function.
      # This script is self-contained and sets up both the infrastructure and the function.
      # @rbs return: String -- JavaScript code
      def build_preload_script
        <<~JS
          () => {
            const channel = #{@channel.to_json};
            const name = #{@name.to_json};

            // Skip if already defined
            if (globalThis[name]) {
              return;
            }

            // Initialize pending calls storage
            if (!globalThis.__pptr_pending_calls__) {
              globalThis.__pptr_pending_calls__ = {};
            }
            if (!globalThis.__pptr_pending_calls__[channel]) {
              globalThis.__pptr_pending_calls__[channel] = [];
            }

            // Define the exposed function
            globalThis[name] = (...args) => {
              return new Promise((resolve, reject) => {
                const id = Math.random().toString(36).substring(2);

                // Store the resolve/reject handlers
                if (!globalThis.__pptr_callbacks__) {
                  globalThis.__pptr_callbacks__ = {};
                }
                if (!globalThis.__pptr_callbacks__[channel]) {
                  globalThis.__pptr_callbacks__[channel] = {};
                }
                globalThis.__pptr_callbacks__[channel][id] = { resolve, reject };

                // Queue the call for Ruby to pick up
                globalThis.__pptr_pending_calls__[channel].push({ id, name, args });
              });
            };
          }
        JS
      end

      # Inject the function into the current page.
      # @rbs return: void
      def inject_into_current_page
        @frame.evaluate(<<~JS, @channel, @name)
          (channel, name) => {
            // Skip if already defined
            if (globalThis[name]) {
              return;
            }

            // Initialize pending calls storage
            if (!globalThis.__pptr_pending_calls__) {
              globalThis.__pptr_pending_calls__ = {};
            }
            if (!globalThis.__pptr_pending_calls__[channel]) {
              globalThis.__pptr_pending_calls__[channel] = [];
            }

            // Define the exposed function
            globalThis[name] = (...args) => {
              return new Promise((resolve, reject) => {
                const id = Math.random().toString(36).substring(2);

                // Store the resolve/reject handlers
                if (!globalThis.__pptr_callbacks__) {
                  globalThis.__pptr_callbacks__ = {};
                }
                if (!globalThis.__pptr_callbacks__[channel]) {
                  globalThis.__pptr_callbacks__[channel] = {};
                }
                globalThis.__pptr_callbacks__[channel][id] = { resolve, reject };

                // Queue the call for Ruby to pick up
                globalThis.__pptr_pending_calls__[channel].push({ id, name, args });
              });
            };
          }
        JS
      rescue StandardError
        # Ignore errors if frame is not ready
      end

      # Start polling for pending function calls.
      # @rbs return: void
      def start_polling
        @polling_task = Async do
          loop do
            break if @disposed
            break if @frame.detached?

            begin
              process_pending_calls
            rescue StandardError
              # Ignore errors during polling (page might have navigated)
            end

            # Small delay to avoid busy-waiting
            sleep 0.01
          end
        end
      end

      # Process pending calls from the page.
      # @rbs return: void
      def process_pending_calls
        # Get pending calls
        calls = @frame.evaluate(<<~JS, @channel)
          (channel) => {
            const pending = globalThis.__pptr_pending_calls__?.[channel] || [];
            globalThis.__pptr_pending_calls__[channel] = [];
            return pending;
          }
        JS

        # Process each call
        Array(calls).each do |call|
          process_call(call)
        end
      end

      # Process a function call from the page.
      # @rbs call: Hash[String, untyped] -- Call data with id, name, args
      # @rbs return: void
      def process_call(call)
        return unless call.is_a?(Hash)

        id = call['id']
        args = call['args'] || []

        begin
          # Execute the Ruby block with the arguments
          result = @block.call(*args)

          # Handle promises/async results
          result = result.wait if result.respond_to?(:wait)

          # Send result back to page
          send_response(id, result: result)
        rescue StandardError => e
          # Send error back to page
          send_response(id, error: e.message)
        end
      end

      # Send a response back to the page.
      # @rbs id: String -- Call ID
      # @rbs result: untyped -- Result value
      # @rbs error: String? -- Error message
      # @rbs return: void
      def send_response(id, result: nil, error: nil)
        return if @frame.detached?

        if error
          @frame.evaluate(<<~JS, @channel, id, error)
            (channel, id, error) => {
              const callback = globalThis.__pptr_callbacks__?.[channel]?.[id];
              if (callback) {
                delete globalThis.__pptr_callbacks__[channel][id];
                callback.reject(new Error(error));
              }
            }
          JS
        else
          @frame.evaluate(<<~JS, @channel, id, result)
            (channel, id, result) => {
              const callback = globalThis.__pptr_callbacks__?.[channel]?.[id];
              if (callback) {
                delete globalThis.__pptr_callbacks__[channel][id];
                callback.resolve(result);
              }
            }
          JS
        end
      rescue StandardError
        # Ignore errors when sending response (page might have navigated)
      end

      # Get the browsing context.
      # @rbs return: Core::BrowsingContext
      def browsing_context
        @frame.browsing_context
      end
    end
  end
end

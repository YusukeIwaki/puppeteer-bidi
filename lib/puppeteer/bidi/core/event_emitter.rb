# frozen_string_literal: true

module Puppeteer
  module Bidi
    module Core
      # EventEmitter provides event subscription and emission capabilities
      # Similar to Node.js EventEmitter but simpler
      class EventEmitter
        def initialize
          @listeners = Hash.new { |h, k| h[k] = [] }
          @disposed = false
        end

        # Register an event listener
        # @param event [Symbol, String] Event name
        # @param block [Proc] Event handler
        def on(event, &block)
          return if @disposed
          @listeners[event.to_sym] << block
        end

        # Register a one-time event listener
        # @param event [Symbol, String] Event name
        # @param block [Proc] Event handler
        def once(event, &block)
          return if @disposed
          wrapper = lambda do |*args|
            off(event, &wrapper)
            block.call(*args)
          end
          on(event, &wrapper)
        end

        # Remove an event listener
        # @param event [Symbol, String] Event name
        # @param block [Proc] Event handler to remove (optional)
        def off(event, &block)
          event_sym = event.to_sym
          if block
            @listeners[event_sym].delete(block)
          else
            @listeners.delete(event_sym)
          end
        end

        # Remove all listeners for an event or all events
        # @param event [Symbol, String, nil] Event name (optional)
        def remove_all_listeners(event = nil)
          if event
            @listeners.delete(event.to_sym)
          else
            @listeners.clear
          end
        end

        # Emit an event to all registered listeners
        # @param event [Symbol, String] Event name
        # @param data [Object] Event data
        def emit(event, data = nil)
          return if @disposed
          listeners = @listeners[event.to_sym].dup
          listeners.each do |listener|
            begin
              listener.call(data)
            rescue => e
              warn "Error in event listener for #{event}: #{e.message}\n#{e.backtrace.join("\n")}"
            end
          end
        end

        # Dispose the event emitter
        def dispose
          @disposed = true
          @listeners.clear
        end

        def disposed?
          @disposed
        end
      end
    end
  end
end

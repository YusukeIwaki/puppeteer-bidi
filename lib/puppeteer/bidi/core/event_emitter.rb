# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    module Core
      # EventEmitter provides event subscription and emission capabilities
      # Similar to Node.js EventEmitter but simpler
      class EventEmitter
        # @rbs return: void
        def initialize
          @listeners = Hash.new { |h, k| h[k] = [] }
          @disposed = false
        end

        # Register an event listener
        # @rbs event: Symbol | String
        # @rbs &block: (untyped) -> void
        # @rbs return: void
        def on(event, &block)
          return if @disposed
          @listeners[event.to_sym] << block
        end

        # Register a one-time event listener
        # @rbs event: Symbol | String
        # @rbs &block: (untyped) -> void
        # @rbs return: void
        def once(event, &block)
          return if @disposed
          wrapper = lambda do |*args|
            off(event, &wrapper)
            block.call(*args)
          end
          on(event, &wrapper)
        end

        # Remove an event listener
        # @rbs event: Symbol | String
        # @rbs &block: ((untyped) -> void)?
        # @rbs return: void
        def off(event, &block)
          event_sym = event.to_sym
          if block
            @listeners[event_sym].delete(block)
          else
            @listeners.delete(event_sym)
          end
        end

        # Remove all listeners for an event or all events
        # @rbs event: (Symbol | String)?
        # @rbs return: void
        def remove_all_listeners(event = nil)
          if event
            @listeners.delete(event.to_sym)
          else
            @listeners.clear
          end
        end

        # Emit an event to all registered listeners
        # @rbs event: Symbol | String
        # @rbs data: untyped
        # @rbs return: void
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
        # @rbs return: void
        def dispose
          @disposed = true
          @listeners.clear
        end

        # @rbs return: bool
        def disposed?
          @disposed
        end
      end
    end
  end
end

# frozen_string_literal: true

module Puppeteer
  module Bidi
    # Error raised when an operation is aborted via AbortController/AbortSignal
    class AbortError < Error
      def initialize(message = 'The operation was aborted')
        super(message)
      end
    end

    # AbortSignal represents a handle that can be used to observe abort events.
    class AbortSignal
      attr_reader :reason

      def initialize
        @aborted = false
        @listeners = []
        @reason = nil
      end

      # Whether the signal has already been aborted.
      # @return [Boolean]
      def aborted?
        @aborted
      end

      # Register an abort listener. The listener will be invoked immediately if
      # the signal is already aborted.
      # @yield [Exception] Yields the abort reason to the listener.
      def add_abort_listener(&listener)
        raise ArgumentError, 'block required' unless listener

        if @aborted
          listener.call(@reason)
        else
          @listeners << listener
        end
      end

      # Remove a previously registered listener (no-op if not found).
      # @param listener [Proc]
      def remove_abort_listener(listener)
        @listeners.delete(listener)
      end

      # Abort the signal with an optional reason.
      # @param reason [Exception, String, nil]
      def abort(reason = nil)
        return if @aborted

        @aborted = true
        @reason = normalize_reason(reason)

        listeners = @listeners.dup
        @listeners.clear
        listeners.each { |listener| listener.call(@reason) }
      end

      private

      def normalize_reason(reason)
        return reason if reason.is_a?(Exception)
        return AbortError.new(reason.to_s) if reason

        AbortError.new
      end
    end

    # AbortController creates AbortSignal instances and triggers abort events.
    class AbortController
      attr_reader :signal

      def initialize
        @signal = AbortSignal.new
      end

      # Abort the associated signal.
      # @param reason [Exception, String, nil]
      def abort(reason = nil)
        @signal.abort(reason)
      end
    end
  end
end

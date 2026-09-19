# frozen_string_literal: true
# rbs_inline: enabled

require "set"

module Puppeteer
  module Bidi
    # A screen recording started with `Page#record`, backed by the WebDriver
    # BiDi `browsingContext.startScreencast`/`stopScreencast` commands.
    # Mirrors upstream's `ScreenRecording`/`BidiScreenRecording`.
    #
    # Adaptation scope: upstream is a ReadableStream; Ruby exposes the bytes
    # through `each` (blocking until stop, like stream iteration) and `data`.
    # `pipe` accepts IO-like destinations responding to `write`, plus
    # `end`/`close` for completion and optional `once` with `writableFinished`/
    # `closed`/`destroyed` state for completion tracking. There is no Ruby
    # equivalent of the `WritableStream` `pipeTo` overload; `close` covers the
    # async-dispose contract (`close` stops the recording).
    class ScreenRecording
      # Methods consulted, in any combination, to detect an already finished
      # destination, mirroring upstream's
      # `writableFinished || closed || destroyed` check plus Ruby's `closed?`.
      FINISHED_STATE_METHODS = %i[writableFinished closed closed? destroyed].freeze #: Array[Symbol]

      attr_reader :page #: Page -- Recorded page
      attr_reader :options #: Hash[Symbol, untyped] -- Recording options
      attr_reader :data #: String? -- Recorded bytes, available after stop

      # @rbs page: Page -- Page to record
      # @rbs options: Hash[Symbol, untyped] -- Recording options
      # @rbs logger: (^(String) -> (^(untyped) -> void)?)? -- Logger factory, defaults to env-gated debug output
      # @rbs return: void
      def initialize(page, options = {}, logger = nil)
        @page = page
        @options = options
        @logger = logger || Debug.default_logger
        @debug_error = @logger&.call(Debug::ERROR)
        @destinations = Set.new #: Set[untyped]
        @data = nil
        @stopped = false
        @in_flight = false
        # Readable completion, resolved once the bytes are distributed,
        # independently of destination shutdown (upstream closes its
        # readable controller before waiting for destinations).
        @readable = Async::Promise.new #: Async::Promise
        # Stop completion, shared with in-flight waiters like `@guarded`.
        @completion = Async::Promise.new #: Async::Promise
        @screencast_id = nil
        @path = nil

        # Register close handling before starting so a closing page always
        # stops the recording.
        page.main_frame.browsing_context.once(:closed) do
          begin
            stop
          rescue => error
            @debug_error&.call(error)
          end
        end
      end

      # @rbs return: bool -- Whether the recording has stopped
      def stopped?
        @stopped
      end

      # Start the screencast. Called by `Page#record`.
      # @rbs return: void
      def start
        # frameRate takes precedence over its fps alias.
        frame_rate = @options[:frame_rate]
        frame_rate = @options[:fps] if frame_rate.nil?
        video = nil
        unless @options[:max_width].nil? && @options[:max_height].nil? && frame_rate.nil?
          video = {}
          video[:width] = @options[:max_width] unless @options[:max_width].nil?
          video[:height] = @options[:max_height] unless @options[:max_height].nil?
          video[:frameRate] = frame_rate unless frame_rate.nil?
        end

        result = @page.main_frame.browsing_context.start_screencast(
          audio: @options[:audio],
          video: video,
        ).wait
        @screencast_id = result["screencast"]
        @path = result["path"]
      end

      # Pipe the recorded bytes to a writable destination. Each destination
      # receives the bytes once; piping the same destination twice still
      # writes once. Evented destinations are removed on unpipe/error/close/
      # finish, mirroring upstream `pipe`.
      # @rbs destination: untyped -- Object responding to `write`
      # @rbs return: untyped -- The destination
      def pipe(destination)
        @destinations << destination
        if destination.respond_to?(:once)
          [:unpipe, :error, :close, :finish].each do |event|
            destination.once(event) { @destinations.delete(destination) }
          end
        end
        destination
      end

      # Iterate the recorded bytes, blocking until they are available.
      # Reading completes independently of destination shutdown, mirroring
      # async iteration over the upstream stream.
      # @rbs &block: (String) -> void -- Chunk handler
      # @rbs return: Enumerator[String, void] | ScreenRecording -- Enumerator without a block
      def each(&block)
        return enum_for(:each) unless block

        @readable.wait
        yield @data if @data
        self
      end

      # Stop the recording. Callers arriving during an in-flight stop wait
      # for it and share its outcome, mirroring upstream's `@guarded` stop;
      # later calls are no-ops since the recording already stopped.
      # @rbs return: void
      def stop
        if @in_flight
          @completion.wait
          return
        end
        return if @stopped

        @stopped = true
        @in_flight = true
        settled = false
        begin
          perform_stop
          close_destinations
        rescue StandardError => error
          settled = true
          @completion.reject(error)
          raise
        else
          settled = true
          @completion.resolve(nil)
        ensure
          @in_flight = false
          # Cancellations bypass StandardError; still wake any waiters.
          @completion.resolve(nil) unless settled
        end
      end

      # Stop the recording, covering upstream's async-dispose contract.
      # @rbs return: void
      def close
        stop
      end

      private

      # Run the stop sequence once.
      # @rbs return: void
      def perform_stop
        return if @screencast_id.nil?

        result = begin
          @page.main_frame.browsing_context.stop_screencast(@screencast_id).wait
        rescue => error
          @debug_error&.call(error)
          nil
        end

        @debug_error&.call(result["error"]) if result.is_a?(Hash) && result["error"]

        file_path = (result.is_a?(Hash) ? result["path"] : nil) || @path
        # An empty path reads nothing, mirroring the upstream falsy check.
        return if file_path.nil? || file_path.empty?

        begin
          buffer = Bidi.read_binary_file(file_path)
          @data = buffer
          @destinations.each { |destination| destination.write(buffer) }
        rescue => error
          @debug_error&.call(error)
        end
      end

      # End all piped destinations, then wait for every completion together,
      # mirroring upstream `closeDestinations`: listeners are registered for
      # all destinations before waiting for any, so out-of-order completions
      # are never missed. End errors propagate like upstream.
      # Destinations without completion signaling are not waited on; upstream
      # would await them forever.
      # @rbs return: void
      def close_destinations
        # Complete the readable side first, like upstream closing its
        # readable controller before shutting down destinations.
        @readable.resolve(nil)
        # Iterate over a copy: ending a destination fires its removal
        # handlers, which mutate the set.
        @destinations.dup.each do |destination|
          if destination.respond_to?(:end)
            destination.end
          elsif destination.respond_to?(:close)
            destination.close
          end
        end
        completions = @destinations.dup.filter_map do |destination|
          next unless destination.respond_to?(:once)
          next if destination_finished?(destination)

          finished = Async::Promise.new
          [:finish, :close, :error].each do |event|
            destination.once(event) { finished.resolve(nil) unless finished.resolved? }
          end
          finished
        end
        completions.each(&:wait)
        @destinations.clear
      end

      # @rbs destination: untyped -- Piped destination
      # @rbs return: bool -- Whether the destination already completed
      def destination_finished?(destination)
        FINISHED_STATE_METHODS.any? do |method|
          destination.respond_to?(method) && destination.public_send(method)
        end
      end
    end
  end
end

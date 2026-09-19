# frozen_string_literal: true
# rbs_inline: enabled

require "set"

module Puppeteer
  module Bidi
    # A screen recording started with `Page#record`, backed by the WebDriver
    # BiDi `browsingContext.startScreencast`/`stopScreencast` commands.
    # Mirrors upstream's `ScreenRecording`/`BidiScreenRecording`.
    class ScreenRecording
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
        @stop_promise = nil #: Async::Promise? -- Completion of the in-flight stop, if any
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
        !@stop_promise.nil?
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
        if destination.respond_to?(:once)
          [:unpipe, :error, :close, :finish].each do |event|
            destination.once(event) { @destinations.delete(destination) }
          end
        end
        @destinations << destination
        destination
      end

      # Iterate the recorded bytes, mirroring async iteration over the
      # upstream stream. Blocks until the recording has stopped.
      # @rbs &block: (String) -> void -- Chunk handler
      # @rbs return: Enumerator[String, void] | ScreenRecording -- Enumerator without a block
      def each(&block)
        return enum_for(:each) unless block

        @stop_promise&.wait
        yield @data if @data
        self
      end

      # Stop the recording. Concurrent callers wait for the in-flight stop
      # instead of issuing duplicate stop commands, mirroring upstream's
      # guarded stop.
      # @rbs return: void
      def stop
        if @stop_promise
          @stop_promise.wait
          return
        end
        @stop_promise = Async::Promise.new
        begin
          perform_stop
        ensure
          close_destinations
          @stop_promise.resolve(nil)
        end
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
        if file_path
          begin
            buffer = Bidi.read_binary_file(file_path)
            @data = buffer
            @destinations.each { |destination| destination.write(buffer) }
          rescue => error
            @debug_error&.call(error)
          end
        end
      end

      # End all piped destinations, never raising, then wait for evented
      # destinations to finish, mirroring upstream `closeDestinations`.
      # @rbs return: void
      def close_destinations
        # Iterate over a copy: ending a destination fires its removal
        # handlers, which mutate the set.
        @destinations.dup.each do |destination|
          begin
            if destination.respond_to?(:end)
              destination.end
            elsif destination.respond_to?(:close)
              destination.close
            end
          rescue
            nil
          end
        end
        @destinations.dup.each do |destination|
          next unless destination.respond_to?(:once)
          next if destination_finished?(destination)

          finished = Async::Promise.new
          [:finish, :close, :error].each do |event|
            destination.once(event) { finished.resolve(nil) unless finished.resolved? }
          end
          finished.wait
        end
        @destinations.clear
      end

      # @rbs destination: untyped -- Piped destination
      # @rbs return: bool -- Whether the destination already completed
      def destination_finished?(destination)
        return destination.closed? if destination.respond_to?(:closed?)
        return !!destination.destroyed if destination.respond_to?(:destroyed)

        false
      end
    end
  end
end

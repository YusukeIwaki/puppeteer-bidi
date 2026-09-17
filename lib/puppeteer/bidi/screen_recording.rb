# frozen_string_literal: true
# rbs_inline: enabled

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
        @destinations = [] #: Array[untyped]
        @data = nil
        @stopped = false
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

      # Pipe the recorded bytes to a writable destination.
      # @rbs destination: untyped -- Object responding to `write`
      # @rbs return: untyped -- The destination
      def pipe(destination)
        @destinations << destination
        destination
      end

      # Stop the recording. Idempotent: subsequent calls are no-ops.
      # @rbs return: void
      def stop
        return if @stopped

        @stopped = true
        begin
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
              buffer = File.binread(file_path)
              @data = buffer
              @destinations.each { |destination| destination.write(buffer) }
            rescue => error
              @debug_error&.call(error)
            end
          end
        ensure
          close_destinations
        end
      end

      private

      # End all piped destinations, never raising.
      # @rbs return: void
      def close_destinations
        @destinations.each do |destination|
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
        @destinations.clear
      end
    end
  end
end

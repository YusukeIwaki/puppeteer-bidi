# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # ConsoleMessage represents a browser console/log entry.
    class ConsoleMessage
      attr_reader :type, :text, :args, :location, :stack_trace

      # @rbs type: String -- Console message type
      # @rbs text: String -- Console text
      # @rbs args: Array[JSHandle] -- Console argument handles
      # @rbs location: Hash[Symbol, untyped]? -- Source location
      # @rbs stack_trace: Array[Hash[Symbol, untyped]] -- Stack trace frames
      # @rbs return: void
      def initialize(type:, text:, args: [], location: nil, stack_trace: [])
        @type = type
        @text = text
        @args = args
        @location = location
        @stack_trace = stack_trace
      end
    end
  end
end

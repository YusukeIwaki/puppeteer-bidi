# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # Configurable logging, ported from Puppeteer's `Debug` module.
    #
    # A logger is a factory proc: it receives a debug channel prefix (one of
    # the `DEBUG_PREFIXES` values) and returns a callable used to emit logs
    # for that channel, or `nil` when logging is disabled for the channel.
    #
    # ```ruby
    # logger = ->(prefix) do
    #   ->(*args) { puts "[#{prefix}] #{args.map(&:inspect).join(' ')}" } if prefix.include?('protocol')
    # end
    # Puppeteer::Bidi.launch(logger: logger) { |browser| ... }
    # ```
    module Debug
      # Prefix for outgoing WebDriver BiDi protocol messages.
      BIDI_SEND = "puppeteer:webDriverBiDi:SEND \u25BA" #: String
      # Prefix for incoming WebDriver BiDi protocol messages.
      BIDI_RECEIVE = "puppeteer:webDriverBiDi:RECV \u25C0" #: String
      # Prefix for internal errors and diagnostics.
      ERROR = "puppeteer:error" #: String

      # Known debug channel prefixes, mirroring upstream `DEBUG_PREFIXES`.
      DEBUG_PREFIXES = {
        bidi_send: BIDI_SEND,
        bidi_receive: BIDI_RECEIVE,
        error: ERROR
      }.freeze #: Hash[Symbol, String]

      # Default logger factory, used when no explicit logger is given.
      # Channels are enabled through the legacy environment variables:
      # protocol traffic via `DEBUG_BIDI_COMMAND` or `DEBUG_PROTOCOL`,
      # error diagnostics via `DEBUG_BIDI_COMMAND`.
      # @rbs return: ^(String) -> (^(untyped) -> void)? -- Logger factory
      def self.default_logger
        ->(prefix) { enabled?(prefix) ? ->(*args) { log(prefix, args) } : nil }
      end

      # @rbs prefix: String -- Debug channel prefix
      # @rbs return: bool -- Whether the channel is enabled
      def self.enabled?(prefix)
        case prefix
        when BIDI_SEND, BIDI_RECEIVE
          !ENV["DEBUG_BIDI_COMMAND"].nil? || %w[1 true].include?(ENV["DEBUG_PROTOCOL"])
        else
          !ENV["DEBUG_BIDI_COMMAND"].nil?
        end
      end
      private_class_method :enabled?

      # @rbs prefix: String -- Debug channel prefix
      # @rbs args: Array[untyped] -- Logged values
      # @rbs return: void
      def self.log(prefix, args)
        puts "#{prefix} #{args.map(&:to_s).join(" ")}"
      end
      private_class_method :log
    end
  end
end

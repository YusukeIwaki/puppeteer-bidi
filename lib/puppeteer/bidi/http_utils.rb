# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # Utilities for normalizing HTTP data exposed through the Puppeteer API.
    module HTTPUtils
      # Normalize multiline HTTP header values.
      # @rbs name: String -- Lowercase header name
      # @rbs value: String -- Header value
      # @rbs return: String -- Normalized header value
      def self.normalize_header_value(name, value)
        return value unless value.include?("\n")

        separator = name == "set-cookie" ? "\n " : ", "
        value.split("\n").map(&:strip).reject(&:empty?).join(separator)
      end
    end
  end
end

# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # Utilities for normalizing HTTP data exposed through the Puppeteer API.
    module HTTPUtils
      # Normalize multiline HTTP header values to comma-separated values.
      # @rbs header: String -- Header value
      # @rbs return: String -- Normalized header value
      def self.normalize_header_value(header)
        return header unless header.include?("\n")

        header.split("\n").map(&:strip).reject(&:empty?).join(", ")
      end
    end
  end
end

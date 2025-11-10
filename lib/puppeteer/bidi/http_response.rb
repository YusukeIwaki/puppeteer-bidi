# frozen_string_literal: true

module Puppeteer
  module Bidi
    # HTTPResponse represents a response to an HTTP request
    class HTTPResponse
      attr_reader :url

      # @param url [String] Response URL
      # @param status [Integer] HTTP status code
      def initialize(url:, status: 200)
        @url = url
        @status = status
      end

      # Check if the response was successful (status code 200-299)
      # @return [Boolean] True if status code is in 2xx range
      def ok?
        @status >= 200 && @status < 300
      end
    end
  end
end

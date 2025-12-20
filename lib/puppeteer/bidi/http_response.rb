# frozen_string_literal: true
# rbs_inline: enabled

require "json"

module Puppeteer
  module Bidi
    # HTTPResponse represents a response to an HTTP request.
    class HTTPResponse
      # @rbs data: Hash[String, untyped] -- BiDi response data
      # @rbs request: HTTPRequest -- Associated request
      # @rbs return: HTTPResponse
      def self.from(data, request)
        existing = request.response
        if existing
          existing.send(:update_data, data)
          return existing
        end

        response = new(data: data, request: request)
        response.send(:initialize_response)
        response
      end

      attr_reader :request

      # @rbs data: Hash[String, untyped] -- BiDi response data
      # @rbs request: HTTPRequest -- Associated request
      # @rbs return: void
      def initialize(data:, request:)
        @data = data
        @request = request
      end

      # @rbs return: Hash[Symbol, untyped]
      def remote_address
        { ip: "", port: -1 }
      end

      # @rbs return: String
      def url
        @data["url"]
      end

      # @rbs return: Integer
      def status
        @data["status"]
      end

      # @rbs return: String
      def status_text
        @data["statusText"]
      end

      # @rbs return: Hash[String, String]
      def headers
        headers = {}
        (@data["headers"] || []).each do |header|
          value = header["value"]
          next unless value.is_a?(Hash)
          next unless value["type"] == "string"

          headers[header["name"].to_s.downcase] = value["value"]
        end
        headers
      end

      # @rbs return: bool
      def ok?
        current_status = status
        current_status == 0 || (current_status >= 200 && current_status <= 299)
      end

      # @rbs return: Hash[String, untyped]?
      def security_details
        nil
      end

      # @rbs return: Hash[String, Numeric]?
      def timing
        bidi_timing = @request.timing
        return nil if bidi_timing.nil? || bidi_timing.empty?

        {
          "requestTime" => bidi_timing["requestTime"],
          "proxyStart" => -1,
          "proxyEnd" => -1,
          "dnsStart" => bidi_timing["dnsStart"],
          "dnsEnd" => bidi_timing["dnsEnd"],
          "connectStart" => bidi_timing["connectStart"],
          "connectEnd" => bidi_timing["connectEnd"],
          "sslStart" => bidi_timing["tlsStart"],
          "sslEnd" => -1,
          "workerStart" => -1,
          "workerReady" => -1,
          "workerFetchStart" => -1,
          "workerRespondWithSettled" => -1,
          "workerRouterEvaluationStart" => -1,
          "workerCacheLookupStart" => -1,
          "sendStart" => bidi_timing["requestStart"],
          "sendEnd" => -1,
          "pushStart" => -1,
          "pushEnd" => -1,
          "receiveHeadersStart" => bidi_timing["responseStart"],
          "receiveHeadersEnd" => bidi_timing["responseEnd"],
        }
      end

      # @rbs return: String
      def content
        @request.get_response_content
      end

      # @rbs return: String
      def buffer
        content
      end

      # @rbs return: String
      def text
        content.dup.force_encoding("UTF-8")
      end

      # @rbs return: untyped
      def json
        JSON.parse(text)
      end

      # @rbs return: bool
      def from_cache?
        @data["fromCache"] == true
      end

      # @rbs return: bool
      def from_service_worker?
        false
      end

      # @rbs return: Frame?
      def frame
        @request.frame
      end

      private

      def initialize_response
        if from_cache?
          @request.instance_variable_set(:@from_memory_cache, true)
          @request.frame.page.emit(:requestservedfromcache, @request)
        end

        @request.frame.page.emit(:response, self)
      end

      def update_data(data)
        @data = data
      end
    end
  end
end

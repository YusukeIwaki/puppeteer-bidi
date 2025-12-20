# frozen_string_literal: true
# rbs_inline: enabled

require "base64"

module Puppeteer
  module Bidi
    # HTTPRequest represents a request initiated by a page.
    class HTTPRequest
      module InterceptResolutionAction
        ABORT = "abort"
        RESPOND = "respond"
        CONTINUE = "continue"
        DISABLED = "disabled"
        NONE = "none"
        ALREADY_HANDLED = "already-handled"
      end

      DEFAULT_INTERCEPT_RESOLUTION_PRIORITY = 0

      STATUS_TEXTS = {
        "100" => "Continue",
        "101" => "Switching Protocols",
        "102" => "Processing",
        "103" => "Early Hints",
        "200" => "OK",
        "201" => "Created",
        "202" => "Accepted",
        "203" => "Non-Authoritative Information",
        "204" => "No Content",
        "205" => "Reset Content",
        "206" => "Partial Content",
        "207" => "Multi-Status",
        "208" => "Already Reported",
        "226" => "IM Used",
        "300" => "Multiple Choices",
        "301" => "Moved Permanently",
        "302" => "Found",
        "303" => "See Other",
        "304" => "Not Modified",
        "305" => "Use Proxy",
        "306" => "Switch Proxy",
        "307" => "Temporary Redirect",
        "308" => "Permanent Redirect",
        "400" => "Bad Request",
        "401" => "Unauthorized",
        "402" => "Payment Required",
        "403" => "Forbidden",
        "404" => "Not Found",
        "405" => "Method Not Allowed",
        "406" => "Not Acceptable",
        "407" => "Proxy Authentication Required",
        "408" => "Request Timeout",
        "409" => "Conflict",
        "410" => "Gone",
        "411" => "Length Required",
        "412" => "Precondition Failed",
        "413" => "Payload Too Large",
        "414" => "URI Too Long",
        "415" => "Unsupported Media Type",
        "416" => "Range Not Satisfiable",
        "417" => "Expectation Failed",
        "418" => "I'm a teapot",
        "421" => "Misdirected Request",
        "422" => "Unprocessable Entity",
        "423" => "Locked",
        "424" => "Failed Dependency",
        "425" => "Too Early",
        "426" => "Upgrade Required",
        "428" => "Precondition Required",
        "429" => "Too Many Requests",
        "431" => "Request Header Fields Too Large",
        "451" => "Unavailable For Legal Reasons",
        "500" => "Internal Server Error",
        "501" => "Not Implemented",
        "502" => "Bad Gateway",
        "503" => "Service Unavailable",
        "504" => "Gateway Timeout",
        "505" => "HTTP Version Not Supported",
        "506" => "Variant Also Negotiates",
        "507" => "Insufficient Storage",
        "508" => "Loop Detected",
        "510" => "Not Extended",
        "511" => "Network Authentication Required",
      }.freeze

      ERROR_REASONS = {
        "aborted" => "Aborted",
        "accessdenied" => "AccessDenied",
        "addressunreachable" => "AddressUnreachable",
        "blockedbyclient" => "BlockedByClient",
        "blockedbyresponse" => "BlockedByResponse",
        "connectionaborted" => "ConnectionAborted",
        "connectionclosed" => "ConnectionClosed",
        "connectionfailed" => "ConnectionFailed",
        "connectionrefused" => "ConnectionRefused",
        "connectionreset" => "ConnectionReset",
        "internetdisconnected" => "InternetDisconnected",
        "namenotresolved" => "NameNotResolved",
        "timedout" => "TimedOut",
        "failed" => "Failed",
      }.freeze

      REQUESTS = begin
        ObjectSpace::WeakMap.new
      rescue NameError
        {}
      end

      # @rbs core_request: Core::Request -- Underlying BiDi request
      # @rbs frame: Frame -- Owning frame
      # @rbs interception_enabled: bool -- Whether interception is enabled
      # @rbs redirect: HTTPRequest? -- Redirected request
      # @rbs return: HTTPRequest
      def self.from(core_request, frame, interception_enabled, redirect: nil)
        request = new(core_request, frame, interception_enabled, redirect)
        request.send(:initialize_request)
        request
      end

      # @rbs core_request: Core::Request -- Underlying core request
      # @rbs return: HTTPRequest? -- Mapped request
      def self.for_core_request(core_request)
        REQUESTS[core_request]
      end

      attr_reader :id

      # @rbs core_request: Core::Request -- Underlying BiDi request
      # @rbs frame: Frame -- Owning frame
      # @rbs interception_enabled: bool -- Whether interception is enabled
      # @rbs redirect: HTTPRequest? -- Redirected request
      # @rbs return: void
      def initialize(core_request, frame, interception_enabled, redirect)
        @request = core_request
        @frame = frame
        @redirect_chain = redirect ? redirect.send(:redirect_chain_internal) : []
        @response = nil
        @authentication_handled = false
        @from_memory_cache = false
        @id = core_request.id

        @interception = {
          enabled: interception_enabled,
          handled: false,
          handlers: [],
          resolution_state: { action: InterceptResolutionAction::NONE },
          request_overrides: {},
          response: nil,
          abort_reason: nil,
        }

        REQUESTS[@request] = self
      end

      # @rbs return: String -- Request URL
      def url
        @request.url
      end

      # @rbs return: String -- HTTP method
      def method
        @request.method
      end

      # @rbs return: Hash[String, String] -- Lowercased headers
      def headers
        headers = {}
        @request.headers.each do |header|
          name = header["name"].to_s.downcase
          value = header["value"]
          next unless value.is_a?(Hash)
          next unless value["type"] == "string"

          headers[name] = value["value"]
        end
        headers.dup
      end

      # @rbs return: String? -- POST body (if available)
      def post_data
        @request.post_data
      end

      # @rbs return: bool -- Whether request has POST data
      def has_post_data?
        @request.has_post_data?
      end

      # @rbs return: String? -- POST body fetched from browser
      def fetch_post_data
        @request.fetch_post_data.wait
      end

      # @rbs return: String -- Resource type
      def resource_type
        (@request.resource_type || "other").downcase
      end

      # @rbs return: Frame -- Request initiator frame
      def frame
        @frame
      end

      # @rbs return: bool -- Whether this is a navigation request
      def navigation_request?
        !@request.navigation.nil?
      end

      # @rbs return: Array[HTTPRequest] -- Redirect chain
      def redirect_chain
        @redirect_chain.dup
      end

      # @rbs return: HTTPResponse? -- Response if available
      def response
        @response
      end

      # @rbs return: Hash[String, String]? -- Failure info
      def failure
        return nil if @request.error.nil?

        { "errorText" => @request.error }
      end

      # @rbs return: Hash[String, untyped]? -- Initiator metadata
      def initiator
        initiator = @request.initiator
        return nil unless initiator

        normalized = {}
        initiator.each do |key, value|
          normalized[key.to_s] = value
        end
        normalized["type"] ||= "other"
        normalized
      end

      # @rbs return: Hash[String, untyped] -- Timing info
      def timing
        @request.timing
      end

      # @rbs return: Hash[Symbol, untyped] -- Interception resolution state
      def intercept_resolution_state
        return { action: InterceptResolutionAction::DISABLED } unless @request.blocked?

        if !@interception[:enabled]
          return { action: InterceptResolutionAction::DISABLED }
        end
        if @interception[:handled]
          return { action: InterceptResolutionAction::ALREADY_HANDLED }
        end
        @interception[:resolution_state].dup
      end

      # @rbs return: bool -- Whether intercept is already handled
      def intercept_resolution_handled?
        @interception[:handled]
      end

      # @rbs return: Hash[Symbol | String, untyped] -- Continue overrides
      def continue_request_overrides
        @interception[:request_overrides]
      end

      # @rbs return: Hash[Symbol | String, untyped]? -- Response overrides
      def response_for_request
        @interception[:response]
      end

      # @rbs return: String? -- Abort error reason
      def abort_error_reason
        @interception[:abort_reason]
      end

      # @rbs &block: (-> untyped) -- Intercept handler
      # @rbs return: void
      def enqueue_intercept_action(&block)
        @interception[:handlers] << block
      end

      # @rbs return: void
      def finalize_interceptions
        @interception[:handlers].each do |handler|
          AsyncUtils.await(handler.call)
        end
        @interception[:handlers] = []

        case intercept_resolution_state[:action]
        when InterceptResolutionAction::ABORT
          _abort(@interception[:abort_reason])
        when InterceptResolutionAction::RESPOND
          raise "Response is missing for the interception" if @interception[:response].nil?

          _respond(@interception[:response])
        when InterceptResolutionAction::CONTINUE
          _continue(@interception[:request_overrides])
        end
      end

      # @rbs overrides: Hash[Symbol | String, untyped] -- Continue overrides
      # @rbs priority: Integer? -- Cooperative intercept priority
      # @rbs return: void
      def continue(overrides = {}, priority = nil)
        verify_interception
        return unless can_be_intercepted?

        if priority.nil?
          return _continue(overrides)
        end

        @interception[:request_overrides] = overrides
        if @interception[:resolution_state][:priority].nil? || priority > @interception[:resolution_state][:priority]
          @interception[:resolution_state] = { action: InterceptResolutionAction::CONTINUE, priority: priority }
          return
        end
        if priority == @interception[:resolution_state][:priority]
          return if [InterceptResolutionAction::ABORT, InterceptResolutionAction::RESPOND].include?(
            @interception[:resolution_state][:action],
          )

          @interception[:resolution_state][:action] = InterceptResolutionAction::CONTINUE
        end
      end

      # @rbs response: Hash[Symbol | String, untyped] -- Response overrides
      # @rbs priority: Integer? -- Cooperative intercept priority
      # @rbs return: void
      def respond(response = {}, priority = nil)
        verify_interception
        return unless can_be_intercepted?

        if priority.nil?
          return _respond(response)
        end

        @interception[:response] = response
        if @interception[:resolution_state][:priority].nil? || priority > @interception[:resolution_state][:priority]
          @interception[:resolution_state] = { action: InterceptResolutionAction::RESPOND, priority: priority }
          return
        end
        if priority == @interception[:resolution_state][:priority]
          return if @interception[:resolution_state][:action] == InterceptResolutionAction::ABORT

          @interception[:resolution_state][:action] = InterceptResolutionAction::RESPOND
        end
      end

      # @rbs error_code: String -- Abort error code
      # @rbs priority: Integer? -- Cooperative intercept priority
      # @rbs return: void
      def abort(error_code = "failed", priority = nil)
        verify_interception
        return unless can_be_intercepted?

        error_reason = ERROR_REASONS[error_code]
        raise Error, "Unknown error code: #{error_code}" unless error_reason

        if priority.nil?
          return _abort(error_reason)
        end

        @interception[:abort_reason] = error_reason
        if @interception[:resolution_state][:priority].nil? || priority >= @interception[:resolution_state][:priority]
          @interception[:resolution_state] = { action: InterceptResolutionAction::ABORT, priority: priority }
        end
      end

      # @rbs return: String -- Response body (binary string)
      def get_response_content
        @request.response_content.wait
      end

      # @rbs body: String -- Response body
      # @rbs return: Hash[Symbol, untyped]
      def self.get_response(body)
        bytes = body.is_a?(String) ? body.dup.force_encoding("BINARY") : body
        {
          content_length: bytes.bytesize,
          base64: Base64.strict_encode64(bytes),
        }
      end

      private

      def initialize_request
        @request.on(:redirect) do |redirect_request|
          http_request = HTTPRequest.from(
            redirect_request,
            @frame,
            @interception[:enabled],
            redirect: self,
          )
          @redirect_chain << self

          redirect_request.once(:success) do
            @frame.page.emit(:requestfinished, http_request)
          end

          redirect_request.once(:error) do
            @frame.page.emit(:requestfailed, http_request)
          end

          Async do
            http_request.finalize_interceptions
          end
        end

        @request.once(:response) do |data|
          @response = HTTPResponse.from(data, self)
        end

        @request.once(:success) do |data|
          @response = HTTPResponse.from(data, self)
        end

        @request.on(:authenticate) do
          handle_authentication
        end

        @frame.page.emit(:request, self)
      end

      def redirect_chain_internal
        @redirect_chain
      end

      def verify_interception
        raise Error, "Request Interception is not enabled!" unless @interception[:enabled]
        raise Error, "Request is already handled!" if @interception[:handled]
      end

      def can_be_intercepted?
        @request.blocked?
      end

      def _continue(overrides)
        headers = self.class.bidi_headers_from_hash(value_for_key(overrides, :headers, "headers"))
        @interception[:handled] = true

        begin
          @request.continue_request(
            url: value_for_key(overrides, :url, "url"),
            method: value_for_key(overrides, :method, "method"),
            body: body_override(value_for_key(overrides, :postData, "postData")),
            headers: headers.empty? ? nil : headers,
          ).wait
        rescue => error
          @interception[:handled] = false
          self.class.handle_interception_error(error)
        end
      end

      def _abort(_error_reason)
        @interception[:handled] = true
        begin
          @request.fail_request.wait
        rescue => error
          @interception[:handled] = false
          raise error
        end
      end

      def _respond(response)
        @interception[:handled] = true

        parsed_body = nil
        body = value_for_key(response, :body, "body")
        parsed_body = self.class.get_response(body) if body

        headers = self.class.bidi_headers_from_hash(value_for_key(response, :headers, "headers"))
        has_content_length = headers.any? { |header| header["name"] == "content-length" }

        content_type = value_for_key(response, :contentType, "contentType")
        if content_type
          headers << {
            "name" => "content-type",
            "value" => { "type" => "string", "value" => content_type.to_s },
          }
        end

        if parsed_body && !has_content_length
          headers << {
            "name" => "content-length",
            "value" => { "type" => "string", "value" => parsed_body[:content_length].to_s },
          }
        end

        status = value_for_key(response, :status, "status") || 200

        begin
          @request.provide_response(
            status_code: status,
            reason_phrase: STATUS_TEXTS[status.to_s],
            headers: headers.empty? ? nil : headers,
            body: parsed_body ? { type: "base64", value: parsed_body[:base64] } : nil,
          ).wait
        rescue => error
          @interception[:handled] = false
          raise error
        end
      end

      def handle_authentication
        credentials = @frame.page.credentials
        if credentials && !@authentication_handled
          @authentication_handled = true
          @request.continue_with_auth(
            action: "provideCredentials",
            credentials: {
              "type" => "password",
              "username" => credentials[:username],
              "password" => credentials[:password],
            },
          ).wait
        else
          @request.continue_with_auth(action: "cancel").wait
        end
      end

      def body_override(post_data)
        return nil if post_data.nil?

        {
          type: "base64",
          value: Base64.strict_encode64(post_data.to_s.b),
        }
      end

      def value_for_key(hash, symbol_key, string_key)
        return nil unless hash

        if hash.key?(symbol_key)
          hash[symbol_key]
        elsif hash.key?(string_key)
          hash[string_key]
        else
          nil
        end
      end

      def self.bidi_headers_from_hash(raw_headers)
        headers = []
        (raw_headers || {}).each do |name, value|
          next if value.nil?

          values = value.is_a?(Array) ? value : [value]
          values.each do |header_value|
            headers << {
              "name" => name.to_s.downcase,
              "value" => {
                "type" => "string",
                "value" => header_value.to_s,
              },
            }
          end
        end
        headers
      end

      def self.handle_interception_error(error)
        message = error.message.to_s
        if message.include?("Invalid header") ||
           message.include?("Unsafe header") ||
           message.include?('Expected "header"') ||
           message.include?("invalid argument")
          raise error
        end

        warn(error.full_message) if ENV["DEBUG_BIDI_COMMAND"]
        nil
      end
    end
  end
end

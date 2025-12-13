# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    module Core
      # Request represents a network request
      class Request < EventEmitter
        include Disposable::DisposableMixin

        # Create a request instance from a beforeRequestSent event
        # @rbs browsing_context: BrowsingContext -- The browsing context
        # @rbs event: Hash[String, untyped] -- The beforeRequestSent event data
        # @rbs return: Request -- New request instance
        def self.from(browsing_context, event)
          request = new(browsing_context, event)
          request.send(:initialize_request)
          request
        end

        attr_reader :browsing_context, :error, :response

        def initialize(browsing_context, event)
          super()
          @browsing_context = browsing_context
          @event = event
          @error = nil
          @redirect = nil
          @response = nil
          @response_content_promise = nil
          @request_body_promise = nil
          @disposables = Disposable::DisposableStack.new
        end

        # Get request ID
        # @rbs return: String -- Request ID
        def id
          @event.dig('request', 'request')
        end

        # Get request URL
        # @rbs return: String -- Request URL
        def url
          @event.dig('request', 'url')
        end

        # Get request method
        # @rbs return: String -- Request method (GET, POST, etc.)
        def method
          @event.dig('request', 'method')
        end

        # Get request headers
        # @rbs return: Array[Hash[String, untyped]] -- Request headers
        def headers
          @event.dig('request', 'headers') || []
        end

        # Get navigation ID if this is a navigation request
        # @rbs return: String? -- Navigation ID
        def navigation
          @event['navigation']
        end

        # Get redirect request if this request was redirected
        # @rbs return: Request? -- Redirect request
        def redirect
          @redirect
        end

        # Get the last redirect in the chain
        # @rbs return: Request? -- Last redirect request
        def last_redirect
          redirect_request = @redirect
          while redirect_request
            break unless redirect_request.redirect
            redirect_request = redirect_request.redirect
          end
          redirect_request
        end

        # Get request initiator information
        # @rbs return: Hash[String, untyped]? -- Initiator info
        def initiator
          initiator_data = @event['initiator']
          return nil unless initiator_data

          {
            **initiator_data,
            url: @event.dig('request', 'goog:resourceInitiator', 'url'),
            stack: @event.dig('request', 'goog:resourceInitiator', 'stack')
          }.compact
        end

        # Check if the request is blocked
        # @rbs return: bool -- Whether the request is blocked
        def blocked?
          @event['isBlocked'] == true
        end

        # Get resource type (non-standard)
        # @rbs return: String? -- Resource type
        def resource_type
          @event.dig('request', 'goog:resourceType')
        end

        # Get POST data (non-standard)
        # @rbs return: String? -- POST data
        def post_data
          @event.dig('request', 'goog:postData')
        end

        # Check if request has POST data
        # @rbs return: bool -- Whether request has POST data
        def has_post_data?
          (@event.dig('request', 'bodySize') || 0) > 0
        end

        # Get timing information
        # @rbs return: Hash[String, untyped] -- Timing info
        def timing
          @event.dig('request', 'timings') || {}
        end

        # Continue the request with optional modifications
        # @rbs url: String? -- Modified URL
        # @rbs method: String? -- Modified method
        # @rbs headers: Array[Hash[String, untyped]]? -- Modified headers
        # @rbs cookies: Array[Hash[String, untyped]]? -- Modified cookies
        # @rbs body: Hash[String, untyped]? -- Modified body
        # @rbs return: untyped
        def continue_request(url: nil, method: nil, headers: nil, cookies: nil, body: nil)
          params = { request: id }
          params[:url] = url if url
          params[:method] = method if method
          params[:headers] = headers if headers
          params[:cookies] = cookies if cookies
          params[:body] = body if body

          session.send_command('network.continueRequest', params)
        end

        # Fail the request
        def fail_request
          session.send_command('network.failRequest', { request: id })
        end

        # Provide a response for the request
        # @rbs status_code: Integer? -- Response status code
        # @rbs reason_phrase: String? -- Response reason phrase
        # @rbs headers: Array[Hash[String, untyped]]? -- Response headers
        # @rbs body: Hash[String, untyped]? -- Response body
        # @rbs return: untyped
        def provide_response(status_code: nil, reason_phrase: nil, headers: nil, body: nil)
          params = { request: id }
          params[:statusCode] = status_code if status_code
          params[:reasonPhrase] = reason_phrase if reason_phrase
          params[:headers] = headers if headers
          params[:body] = body if body

          session.send_command('network.provideResponse', params)
        end

        # Fetch POST data for the request
        # @rbs return: String? -- POST data
        def fetch_post_data
          return nil unless has_post_data?
          return @request_body_promise if @request_body_promise

          @request_body_promise = begin
            result = session.send_command('network.getData', {
              dataType: 'request',
              request: id
            })

            bytes = result['bytes']
            if bytes['type'] == 'string'
              bytes['value']
            else
              raise "Collected request body data of type #{bytes['type']} is not supported"
            end
          end
        end

        # Get response content
        # @rbs return: String -- Response content as binary string
        def response_content
          return @response_content_promise if @response_content_promise

          @response_content_promise = begin
            result = session.send_command('network.getData', {
              dataType: 'response',
              request: id
            })

            bytes = result['bytes']
            if bytes['type'] == 'base64'
              [bytes['value']].pack('m0')
            else
              bytes['value']
            end
          rescue => e
            if e.message.include?('No resource with given identifier found')
              raise 'Could not load response body for this request. This might happen if the request is a preflight request.'
            end
            raise
          end
        end

        # Continue with authentication
        # @rbs action: String -- 'provideCredentials', 'default', or 'cancel'
        # @rbs credentials: Hash[String, untyped]? -- Credentials hash with username and password
        # @rbs return: untyped
        def continue_with_auth(action:, credentials: nil)
          params = {
            request: id,
            action: action
          }
          params[:credentials] = credentials if action == 'provideCredentials'

          session.send_command('network.continueWithAuth', params)
        end

        protected

        def perform_dispose
          @disposables.dispose
          super
        end

        private

        def session
          @browsing_context.user_context.browser.session
        end

        def initialize_request
          # Listen for browsing context closure
          @browsing_context.once(:closed) do |data|
            @error = data[:reason]
            emit(:error, @error)
            dispose
          end

          # Listen for redirect
          session.on('network.beforeRequestSent') do |event|
            next unless event['context'] == @browsing_context.id
            next unless event.dig('request', 'request') == id

            # Check if this is a redirect
            previous_has_auth = @event.dig('request', 'headers')&.any? do |h|
              h['name'].downcase == 'authorization'
            end
            new_has_auth = event.dig('request', 'headers')&.any? do |h|
              h['name'].downcase == 'authorization'
            end
            is_after_auth = new_has_auth && !previous_has_auth

            next unless event['redirectCount'] == @event['redirectCount'] + 1 || is_after_auth

            @redirect = Request.from(@browsing_context, event)
            emit(:redirect, @redirect)
            dispose
          end

          # Listen for authentication required
          session.on('network.authRequired') do |event|
            next unless event['context'] == @browsing_context.id
            next unless event.dig('request', 'request') == id
            next unless event['isBlocked']

            emit(:authenticate, nil)
          end

          # Listen for fetch error
          session.on('network.fetchError') do |event|
            next unless event['context'] == @browsing_context.id
            next unless event.dig('request', 'request') == id
            next unless event['redirectCount'] == @event['redirectCount']

            @error = event['errorText']
            emit(:error, @error)
            dispose
          end

          # Listen for response completed
          session.on('network.responseCompleted') do |event|
            next unless event['context'] == @browsing_context.id
            next unless event.dig('request', 'request') == id
            next unless event['redirectCount'] == @event['redirectCount']

            @response = event['response']
            @event['request']['timings'] = event.dig('request', 'timings')
            emit(:success, @response)

            # Don't dispose if this is a redirect
            status = @response['status']
            dispose unless status >= 300 && status < 400
          end
        end
      end
    end
  end
end

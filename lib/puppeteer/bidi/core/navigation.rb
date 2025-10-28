# frozen_string_literal: true

require_relative 'event_emitter'
require_relative 'disposable'

module Puppeteer
  module Bidi
    module Core
      # Navigation represents a single navigation operation
      class Navigation < EventEmitter
        include Disposable::DisposableMixin

        # Create a navigation instance
        # @param browsing_context [BrowsingContext] The browsing context
        # @return [Navigation] New navigation instance
        def self.from(browsing_context)
          navigation = new(browsing_context)
          navigation.send(:initialize_navigation)
          navigation
        end

        attr_reader :browsing_context, :request

        def initialize(browsing_context)
          super()
          @browsing_context = browsing_context
          @request = nil
          @navigation = nil
          @id = nil
          @disposables = Disposable::DisposableStack.new
        end

        # Get the nested navigation if any
        # @return [Navigation, nil] Nested navigation
        def navigation
          @navigation
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

        def initialize_navigation
          # Listen for browsing context closure
          @browsing_context.once(:closed) do
            emit(:failed, {
              url: @browsing_context.url,
              timestamp: Time.now
            })
            dispose
          end

          # Listen for requests with navigation ID
          @browsing_context.on(:request) do |data|
            request = data[:request]
            next unless request.navigation
            next unless matches?(request.navigation)

            @request = request
            emit(:request, request)

            # Listen for redirects
            request.on(:redirect) do |redirect_request|
              @request = redirect_request
            end
          end

          # Listen for nested navigation
          session.on('browsingContext.navigationStarted') do |info|
            next unless info['context'] == @browsing_context.id
            next if @navigation && !@navigation.disposed?

            @navigation = Navigation.from(@browsing_context)
          end

          # Listen for navigation completion events
          %w[browsingContext.domContentLoaded browsingContext.load].each do |event_name|
            session.on(event_name) do |info|
              next unless info['context'] == @browsing_context.id
              next if info['navigation'].nil?
              next unless matches?(info['navigation'])

              dispose
            end
          end

          # Listen for navigation end events
          {
            'browsingContext.fragmentNavigated' => :fragment,
            'browsingContext.navigationFailed' => :failed,
            'browsingContext.navigationAborted' => :aborted
          }.each do |event_name, emit_event|
            session.on(event_name) do |info|
              next unless info['context'] == @browsing_context.id
              next unless matches?(info['navigation'])

              emit(emit_event, {
                url: info['url'],
                timestamp: Time.at(info['timestamp'] / 1000.0)
              })
              dispose
            end
          end
        end

        def matches?(navigation_id)
          # If nested navigation exists and is not disposed, this navigation doesn't match
          return false if @navigation && !@navigation.disposed?

          # First navigation event sets the ID
          if @id.nil?
            @id = navigation_id
            return true
          end

          # Check if the navigation ID matches
          @id == navigation_id
        end
      end
    end
  end
end

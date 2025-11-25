# frozen_string_literal: true

module Puppeteer
  module Bidi
    module Core
      # UserContext represents an isolated browsing context (like an incognito session)
      class UserContext < EventEmitter
        include Disposable::DisposableMixin

        DEFAULT = 'default'

        # Create a user context
        # @param browser [Browser] Parent browser
        # @param id [String] Context ID
        # @return [UserContext] New user context
        def self.create(browser, id)
          context = new(browser, id)
          context.send(:initialize_context)
          context
        end

        attr_reader :browser, :id

        def initialize(browser, id)
          super()
          @browser = browser
          @id = id
          @reason = nil
          @disposables = Disposable::DisposableStack.new
          @browsing_contexts = {}
        end

        # Check if the context is closed
        def closed?
          !@reason.nil?
        end

        alias disposed? closed?

        # Get all browsing contexts in this user context
        # @return [Array<BrowsingContext>] Top-level browsing contexts
        def browsing_contexts
          @browsing_contexts.values
        end

        # Create a new browsing context (tab or window)
        # @param type [String] 'tab' or 'window'
        # @param options [Hash] Creation options
        # @option options [BrowsingContext] :reference_context Reference context
        # @return [BrowsingContext] New browsing context
        def create_browsing_context(type, **options)
          raise UserContextClosedError, @reason if closed?

          params = {
            type: type,
            userContext: @id
          }
          params[:referenceContext] = options[:reference_context].id if options[:reference_context]
          params.merge!(options.except(:reference_context))

          result = session.async_send_command('browsingContext.create', params).wait
          context_id = result['context']

          # Since event handling might be async or not working properly,
          # check if the context was already created by the event handler
          browsing_context = @browsing_contexts[context_id]

          # If not created by event handler, create it manually
          if browsing_context.nil?
            browsing_context = BrowsingContext.from(
              self,
              nil, # parent
              context_id,
              'about:blank',  # Initial URL
              nil # originalOpener
            )
            @browsing_contexts[context_id] = browsing_context

            browsing_context.once(:closed) do
              @browsing_contexts.delete(context_id)
            end
          end

          browsing_context
        end

        # Remove this user context
        def remove
          return if closed?

          begin
            session.send_command('browser.removeUserContext', { userContext: @id })
          ensure
            dispose_context('User context removed')
          end
        end

        # Get cookies for this user context
        # @param options [Hash] Cookie filter options
        # @option options [String] :source_origin Source origin
        # @return [Array<Hash>] Cookies
        def get_cookies(**options)
          raise UserContextClosedError, @reason if closed?

          source_origin = options.delete(:source_origin)
          params = options.dup
          params[:partition] = {
            type: 'storageKey',
            userContext: @id
          }
          params[:partition][:sourceOrigin] = source_origin if source_origin

          result = session.send_command('storage.getCookies', params)
          result['cookies']
        end

        # Set a cookie in this user context
        # @param cookie [Hash] Cookie data
        # @option options [String] :source_origin Source origin
        def set_cookie(cookie, **options)
          raise UserContextClosedError, @reason if closed?

          source_origin = options[:source_origin]
          params = {
            cookie: cookie,
            partition: {
              type: 'storageKey',
              userContext: @id
            }
          }
          params[:partition][:sourceOrigin] = source_origin if source_origin

          session.send_command('storage.setCookie', params)
        end

        # Set permissions for an origin
        # @param origin [String] Origin URL
        # @param descriptor [Hash] Permission descriptor
        # @param state [String] Permission state
        def set_permissions(origin, descriptor, state)
          raise UserContextClosedError, @reason if closed?

          session.send_command('permissions.setPermission', {
            origin: origin,
            descriptor: descriptor,
            state: state,
            userContext: @id
          })
        end

        protected

        def perform_dispose
          @reason ||= 'User context closed, probably because the browser disconnected'
          emit(:closed, { reason: @reason })
          @disposables.dispose
          super
        end

        private

        def session
          @browser.session
        end

        def initialize_context
          # Listen for browser closure/disconnection
          @browser.once(:closed) do |data|
            dispose_context("User context closed: #{data[:reason]}")
          end

          @browser.once(:disconnected) do |data|
            dispose_context("User context closed: #{data[:reason]}")
          end

          # Listen for browsing context creation
          session.on(:'browsingContext.contextCreated') do |info|
            # Only handle top-level contexts (no parent)
            next if info['parent']
            next if info['userContext'] != @id

            browsing_context = BrowsingContext.from(
              self,
              nil, # parent
              info['context'],
              info['url'],
              info['originalOpener']
            )

            @browsing_contexts[browsing_context.id] = browsing_context

            # Listen for context closure
            browsing_context.once(:closed) do
              @browsing_contexts.delete(browsing_context.id)
            end

            emit(:browsingcontext, { browsing_context: browsing_context })
          end
        end

        def dispose_context(reason)
          @reason = reason
          dispose
        end
      end
    end
  end
end

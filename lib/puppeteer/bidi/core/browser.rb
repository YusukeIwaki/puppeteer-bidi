# frozen_string_literal: true

module Puppeteer
  module Bidi
    module Core
      # Browser represents the browser instance in the core layer
      # It manages user contexts and provides browser-level operations
      class Browser < EventEmitter
        include Disposable::DisposableMixin

        # Create a browser instance from a session
        # @param session [Session] BiDi session
        # @return [Browser] Browser instance
        def self.from(session)
          browser = new(session)
          Async do
            browser.send(:initialize_browser).wait
            browser
          end
        end

        attr_reader :session

        def initialize(session)
          super()
          @session = session
          @closed = false
          @reason = nil
          @disposables = Disposable::DisposableStack.new
          @user_contexts = {}
          @shared_workers = {}
        end

        # Check if the browser is closed
        def closed?
          @closed
        end

        # Check if the browser is disconnected
        def disconnected?
          !@reason.nil?
        end

        alias disposed? disconnected?

        # Get the default user context
        # @return [UserContext] Default user context
        def default_user_context
          @user_contexts[UserContext::DEFAULT]
        end

        # Get all user contexts
        # @return [Array<UserContext>] All user contexts
        def user_contexts
          @user_contexts.values
        end

        # Close the browser
        def close
          Async do
            return if @closed

            begin
              @session.async_send_command('browser.close', {})
            ensure
              dispose_browser('Browser closed', closed: true)
            end
          end
        end

        # Add a preload script to the browser
        # @param function_declaration [String] JavaScript function to preload
        # @param options [Hash] Preload script options
        # @option options [Array<BrowsingContext>] :contexts Contexts to apply to
        # @option options [String] :sandbox Sandbox name
        # @return [String] Script ID
        def add_preload_script(function_declaration, **options)
          raise BrowserDisconnectedError, @reason if disconnected?

          params = { functionDeclaration: function_declaration }
          if options[:contexts]
            params[:contexts] = options[:contexts].map(&:id)
          end
          params[:sandbox] = options[:sandbox] if options[:sandbox]

          Async do
            result = @session.async_send_command('script.addPreloadScript', params).wait
            result['script']
          end
        end

        # Remove a preload script
        # @param script [String] Script ID
        def remove_preload_script(script)
          raise BrowserDisconnectedError, @reason if disconnected?
          @session.async_send_command('script.removePreloadScript', { script: script })
        end

        # Create a new user context
        # @param options [Hash] User context options
        # @option options [Hash] :proxy Proxy configuration
        # @return [UserContext] New user context
        def create_user_context(**options)
          raise BrowserDisconnectedError, @reason if disconnected?

          params = {}
          if options[:proxy_server]
            params[:proxy] = {
              proxyType: 'manual',
              httpProxy: options[:proxy_server],
              sslProxy: options[:proxy_server],
              noProxy: options[:proxy_bypass_list]
            }.compact
          end

          Async do
            result = @session.async_send_command('browser.createUserContext', params).wait
            user_context_id = result['userContext']

            create_user_context_object(user_context_id)
          end
        end

        # Remove a network intercept
        # @param intercept [String] Intercept ID
        def remove_intercept(intercept)
          raise BrowserDisconnectedError, @reason if disconnected?
          @session.async_send_command('network.removeIntercept', { intercept: intercept })
        end

        protected

        def perform_dispose
          @reason ||= 'Browser was disconnected, probably because the session ended'
          emit(:closed, { reason: @reason }) if @closed
          emit(:disconnected, { reason: @reason })
          @disposables.dispose
          super
        end

        private

        def initialize_browser
          Async do
            # Listen for session end
            @session.on(:ended) do |data|
              dispose_browser(data[:reason])
            end

            # Listen for shared worker creation
            @session.on('script.realmCreated') do |info|
              next unless info['type'] == 'shared-worker'
              # Create SharedWorkerRealm when implemented
              # @shared_workers[info['realm']] = SharedWorkerRealm.from(self, info['realm'], info['origin'])
            end

            # Sync existing user contexts and browsing contexts
            sync_user_contexts.wait
            sync_browsing_contexts.wait
          end
        end

        def sync_user_contexts
          Async do
            result = @session.async_send_command('browser.getUserContexts', {}).wait
            user_contexts = result['userContexts']

            user_contexts.each do |context_info|
              create_user_context_object(context_info['userContext'])
            end
          end
        end

        def sync_browsing_contexts
          Async do
            # Get all browsing contexts
            result = @session.async_send_command('browsingContext.getTree', {}).wait
            contexts = result['contexts']

            # Track context IDs for detecting created/destroyed contexts during sync
            context_ids = []

            # Setup temporary listener for context creation during sync
            temp_listener = @session.on('browsingContext.contextCreated') do |info|
              context_ids << info['context']
            end

            # Process all contexts (including nested ones)
            process_contexts(contexts, context_ids)

            # Remove temporary listener
            # @session.off('browsingContext.contextCreated', &temp_listener)
          end
        end

        def process_contexts(contexts, context_ids)
          contexts.each do |info|
            # Emit context created event if not already tracked
            unless context_ids.include?(info['context'])
              @session.emit('browsingContext.contextCreated', info)
            end

            # Process children recursively
            process_contexts(info['children'], context_ids) if info['children']
          end
        end

        def create_user_context_object(id)
          return @user_contexts[id] if @user_contexts[id]

          user_context = UserContext.create(self, id)
          @user_contexts[id] = user_context

          # Listen for user context closure
          user_context.once(:closed) do
            @user_contexts.delete(id)
          end

          user_context
        end

        def dispose_browser(reason, closed: false)
          @closed = closed
          @reason = reason
          dispose
        end
      end
    end
  end
end

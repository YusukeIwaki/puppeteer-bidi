# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    module Core
      # Session represents a BiDi session with the browser
      # It wraps a Connection and provides session-specific functionality
      class Session < EventEmitter
        include Disposable::DisposableMixin

        # Create a new session from an existing connection
        # @rbs connection: Puppeteer::Bidi::Connection -- The BiDi connection
        # @rbs capabilities: Hash[String, untyped] -- Session capabilities
        # @rbs return: Async::Task[Session]
        def self.from(connection:, capabilities:)
          Async do
            result = connection.async_send_command('session.new', { capabilities: capabilities }).wait
            session = new(connection, result)
            session.send(:initialize_session).wait
            session
          end
        end

        attr_reader :connection, :id, :capabilities
        attr_accessor :browser

        def initialize(connection, info)
          super()
          @connection = connection
          @info = info
          @id = info['sessionId']
          @capabilities = info['capabilities']
          @reason = nil
          @disposables = Disposable::DisposableStack.new

          # Forward BiDi events from connection to session
          setup_event_forwarding
        end

        # Check if the session has ended
        def ended?
          !@reason.nil?
        end

        alias disposed? ended?

        # Send a BiDi command through this session
        # @rbs method: String -- BiDi method name
        # @rbs params: Hash[String | Symbol, untyped] -- Command parameters
        # @rbs return: Async::Task[Hash[String, untyped]]
        def async_send_command(method, params = {})
          raise SessionEndedError, @reason if ended?
          @connection.async_send_command(method, params)
        end

        # Subscribe to BiDi events
        # @rbs events: Array[String] -- Event names to subscribe to
        # @rbs contexts: Array[String]? -- Context IDs (optional)
        # @rbs return: Async::Task[untyped]
        def subscribe(events, contexts = nil)
          raise SessionEndedError, @reason if ended?
          params = { events: events }
          params[:contexts] = contexts if contexts
          async_send_command('session.subscribe', params)
        end

        # Add intercepts (same as subscribe but for interception events)
        # @rbs events: Array[String] -- Event names to intercept
        # @rbs contexts: Array[String]? -- Context IDs (optional)
        # @rbs return: Async::Task[untyped]
        def add_intercepts(events, contexts = nil)
          subscribe(events, contexts)
        end

        # End the session
        def end_session
          return if ended?

          begin
            async_send_command('session.end', {}).wait
          ensure
            dispose_session('Session ended')
          end
        end

        protected

        def perform_dispose
          @reason ||= 'Session destroyed, probably because the connection broke'
          emit(:ended, { reason: @reason })
          @disposables.dispose
          super
        end

        private

        def initialize_session
          # Subscribe to BiDi modules
          # Based on Puppeteer's subscribeModules: browsingContext, network, log, script, input
          subscribe_modules = %w[
            browsingContext
            network
            log
            script
            input
          ]

          subscribe(subscribe_modules)
        end

        def dispose_session(reason)
          @reason = reason
          dispose
        end

        def setup_event_forwarding
          # Forward all BiDi events from connection to this session
          # The existing Connection class uses #on method for event handling
          # We need to set up listeners for all possible BiDi events

          # For now, we'll use a workaround: store the connection's event listeners
          # and forward to our EventEmitter

          # List of common BiDi events to forward
          bidi_events = [
            'browsingContext.contextCreated',
            'browsingContext.contextDestroyed',
            'browsingContext.navigationStarted',
            'browsingContext.fragmentNavigated',
            'browsingContext.domContentLoaded',
            'browsingContext.load',
            'browsingContext.historyUpdated',
            'browsingContext.userPromptOpened',
            'browsingContext.userPromptClosed',
            'network.beforeRequestSent',
            'network.responseStarted',
            'network.responseCompleted',
            'network.fetchError',
            'network.authRequired',
            'script.realmCreated',
            'script.realmDestroyed',
            'script.message',
            'log.entryAdded',
            'input.fileDialogOpened',
          ]

          bidi_events.each do |event_name|
            @connection.on(event_name) do |params|
              emit(event_name.to_sym, params)
            end
          end
        end
      end
    end
  end
end

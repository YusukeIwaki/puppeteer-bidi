# frozen_string_literal: true

require_relative 'event_emitter'
require_relative 'disposable'

module Puppeteer
  module Bidi
    module Core
      # Session represents a BiDi session with the browser
      # It wraps a Connection and provides session-specific functionality
      class Session < EventEmitter
        include Disposable::DisposableMixin

        # Create a new session from an existing connection
        # @param connection [Puppeteer::Bidi::Connection] The BiDi connection
        # @param capabilities [Hash] Session capabilities
        # @return [Session] New session instance
        def self.from(connection, capabilities)
          result = connection.send_command('session.new', { capabilities: capabilities })
          session = new(connection, result)
          session.send(:initialize_session)
          session
        end

        attr_reader :connection, :id, :capabilities

        def initialize(connection, info)
          super()
          @connection = connection
          @info = info
          @id = info['sessionId']
          @capabilities = info['capabilities']
          @reason = nil
          @disposables = Disposable::DisposableStack.new
          @browser = nil

          # Forward BiDi events from connection to session
          setup_event_forwarding
        end

        # Check if the session has ended
        def ended?
          !@reason.nil?
        end

        alias disposed? ended?

        # Send a BiDi command through this session
        # @param method [String] BiDi method name
        # @param params [Hash] Command parameters
        # @return [Hash] Command result
        def send_command(method, params = {})
          raise SessionEndedError, @reason if ended?
          result = @connection.send_command(method, params)
          result
        end

        # Subscribe to BiDi events
        # @param events [Array<String>] Event names to subscribe to
        # @param contexts [Array<String>, nil] Context IDs (optional)
        def subscribe(events, contexts = nil)
          raise SessionEndedError, @reason if ended?
          params = { events: events }
          params[:contexts] = contexts if contexts
          send_command('session.subscribe', params)
        end

        # Add intercepts (same as subscribe but for interception events)
        # @param events [Array<String>] Event names to intercept
        # @param contexts [Array<String>, nil] Context IDs (optional)
        def add_intercepts(events, contexts = nil)
          subscribe(events, contexts)
        end

        # End the session
        def end_session
          return if ended?

          begin
            send_command('session.end', {})
          ensure
            dispose_session('Session ended')
          end
        end

        # Get the browser instance associated with this session
        # @return [Browser] Browser instance
        def browser
          @browser
        end

        # Internal: Set the browser instance
        # @param browser [Browser] Browser instance
        def browser=(browser)
          @browser = browser
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
          # Browser will be created later by the caller
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

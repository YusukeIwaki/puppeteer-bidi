# frozen_string_literal: true

require_relative 'event_emitter'
require_relative 'disposable'

module Puppeteer
  module Bidi
    module Core
      # Realm is the base class for script execution realms
      class Realm < EventEmitter
        include Disposable::DisposableMixin

        attr_reader :id, :origin

        def initialize(id, origin)
          super()
          @id = id
          @origin = origin
          @reason = nil
          @execution_context_id = nil
          @disposables = Disposable::DisposableStack.new
        end

        # Get the target for script execution
        # @return [Hash] BiDi target descriptor
        def target
          { realm: @id }
        end

        # Disown handles (remove references)
        # @param handles [Array<String>] Handle IDs to disown
        def disown(handles)
          raise RealmDestroyedError, @reason if disposed?
          session.send_command('script.disown', {
            target: target,
            handles: handles
          })
        end

        # Call a function in the realm
        # @param function_declaration [String] Function source code
        # @param await_promise [Boolean] Whether to await promise results
        # @param options [Hash] Additional options
        # @return [Hash] Evaluation result (with 'type', 'realm', and optionally 'result'/'exceptionDetails')
        def call_function(function_declaration, await_promise, **options)
          raise RealmDestroyedError, @reason if disposed?
          session.send_command('script.callFunction', {
            functionDeclaration: function_declaration,
            awaitPromise: await_promise,
            target: target,
            **options
          })
        end

        # Evaluate an expression in the realm
        # @param expression [String] JavaScript expression
        # @param await_promise [Boolean] Whether to await promise results
        # @param options [Hash] Additional options
        # @return [Hash] Evaluation result (with 'type', 'realm', and optionally 'result'/'exceptionDetails')
        def evaluate(expression, await_promise, **options)
          raise RealmDestroyedError, @reason if disposed?
          session.send_command('script.evaluate', {
            expression: expression,
            awaitPromise: await_promise,
            target: target,
            **options
          })
        end

        # Resolve the CDP execution context ID for this realm
        # @return [Integer] Execution context ID
        def resolve_execution_context_id
          return @execution_context_id if @execution_context_id

          # This uses a Chrome-specific extension to BiDi
          result = session.connection.send_command('goog:cdp.resolveRealm', { realm: @id })
          @execution_context_id = result['executionContextId']
        end

        protected

        # Abstract method - must be implemented by subclasses
        # @return [Session] The session for this realm
        def session
          raise NotImplementedError, 'Subclasses must implement #session'
        end

        def perform_dispose
          @reason ||= 'Realm destroyed, probably because all associated browsing contexts closed'
          emit(:destroyed, { reason: @reason })
          @disposables.dispose
          super
        end
      end

      # WindowRealm represents a JavaScript realm in a window or iframe
      class WindowRealm < Realm
        # Create a window realm
        # @param browsing_context [BrowsingContext] The browsing context
        # @param sandbox [String, nil] Sandbox name
        # @return [WindowRealm] New window realm
        def self.from(browsing_context, sandbox = nil)
          realm = new(browsing_context, sandbox)
          realm.send(:initialize_realm)
          realm
        end

        attr_reader :browsing_context, :sandbox

        def initialize(browsing_context, sandbox = nil)
          super('', '') # ID and origin will be set when realm is created
          @browsing_context = browsing_context
          @sandbox = sandbox
          @workers = {}
        end

        # Override target to use context-based target
        # @return [Hash] BiDi target descriptor
        def target
          result = { context: @browsing_context.id }
          result[:sandbox] = @sandbox if @sandbox
          result
        end

        protected

        def session
          @browsing_context.user_context.browser.session
        end

        private

        def initialize_realm
          # Listen for browsing context closure
          @browsing_context.once(:closed) do |data|
            dispose_realm(data[:reason])
          end

          # Listen for realm creation (this realm)
          session.on('script.realmCreated') do |info|
            next unless info['type'] == 'window'
            next unless info['context'] == @browsing_context.id
            next unless info['sandbox'] == @sandbox

            # Set the ID and origin for this realm
            @id = info['realm']
            @origin = info['origin']
            @execution_context_id = nil
            emit(:updated, self)
          end

          # Listen for dedicated worker creation
          session.on('script.realmCreated') do |info|
            next unless info['type'] == 'dedicated-worker'
            next unless info['owners']&.include?(@id)

            worker = DedicatedWorkerRealm.from(self, info['realm'], info['origin'])
            @workers[worker.id] = worker

            worker.once(:destroyed) do
              @workers.delete(worker.id)
            end

            emit(:worker, worker)
          end
        end

        def dispose_realm(reason)
          @reason = reason
          dispose
        end
      end

      # DedicatedWorkerRealm represents a JavaScript realm in a dedicated worker
      class DedicatedWorkerRealm < Realm
        # Create a dedicated worker realm
        # @param owner [WindowRealm, DedicatedWorkerRealm, SharedWorkerRealm] Owner realm
        # @param id [String] Realm ID
        # @param origin [String] Realm origin
        # @return [DedicatedWorkerRealm] New dedicated worker realm
        def self.from(owner, id, origin)
          realm = new(owner, id, origin)
          realm.send(:initialize_realm)
          realm
        end

        attr_reader :owners

        def initialize(owner, id, origin)
          super(id, origin)
          @owners = Set.new([owner])
          @workers = {}
        end

        protected

        def session
          # Get session from any owner
          @owners.first.session
        end

        private

        def initialize_realm
          # Listen for realm destruction
          session.on('script.realmDestroyed') do |info|
            next unless info['realm'] == @id
            dispose_realm('Realm destroyed')
          end

          # Listen for nested dedicated worker creation
          session.on('script.realmCreated') do |info|
            next unless info['type'] == 'dedicated-worker'
            next unless info['owners']&.include?(@id)

            worker = DedicatedWorkerRealm.from(self, info['realm'], info['origin'])
            @workers[worker.id] = worker

            worker.once(:destroyed) do
              @workers.delete(worker.id)
            end

            emit(:worker, worker)
          end
        end

        def dispose_realm(reason)
          @reason = reason
          dispose
        end
      end

      # SharedWorkerRealm represents a JavaScript realm in a shared worker
      class SharedWorkerRealm < Realm
        # Create a shared worker realm
        # @param browser [Browser] Browser instance
        # @param id [String] Realm ID
        # @param origin [String] Realm origin
        # @return [SharedWorkerRealm] New shared worker realm
        def self.from(browser, id, origin)
          realm = new(browser, id, origin)
          realm.send(:initialize_realm)
          realm
        end

        attr_reader :browser

        def initialize(browser, id, origin)
          super(id, origin)
          @browser = browser
          @workers = {}
        end

        protected

        def session
          @browser.session
        end

        private

        def initialize_realm
          # Listen for realm destruction
          session.on('script.realmDestroyed') do |info|
            next unless info['realm'] == @id
            dispose_realm('Realm destroyed')
          end

          # Listen for dedicated worker creation
          session.on('script.realmCreated') do |info|
            next unless info['type'] == 'dedicated-worker'
            next unless info['owners']&.include?(@id)

            worker = DedicatedWorkerRealm.from(self, info['realm'], info['origin'])
            @workers[worker.id] = worker

            worker.once(:destroyed) do
              @workers.delete(worker.id)
            end

            emit(:worker, worker)
          end
        end

        def dispose_realm(reason)
          @reason = reason
          dispose
        end
      end
    end
  end
end

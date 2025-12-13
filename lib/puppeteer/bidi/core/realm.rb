# frozen_string_literal: true
# rbs_inline: enabled

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
        # @rbs return: Hash[Symbol, untyped] -- BiDi target descriptor
        def target
          { realm: @id }
        end

        # Disown handles (remove references)
        # @rbs handles: Array[String] -- Handle IDs to disown
        # @rbs return: Async::Task[untyped]
        def disown(handles)
          raise RealmDestroyedError, @reason if disposed?
          session.async_send_command('script.disown', {
            target: target,
            handles: handles
          })
        end

        # Call a function in the realm
        # @rbs function_declaration: String -- Function source code
        # @rbs await_promise: bool -- Whether to await promise results
        # @rbs **options: untyped -- Additional options (arguments, serializationOptions, resultOwnership, etc.)
        # @rbs return: Async::Task[Hash[String, untyped]] -- Evaluation result
        def call_function(function_declaration, await_promise, **options)
          raise RealmDestroyedError, @reason if disposed?

          # Note: In Puppeteer, returnByValue controls serialization, not awaitPromise
          # awaitPromise controls whether to wait for promises
          # For BiDi, we use 'root' ownership by default to keep handles alive
          # Only use 'none' if explicitly requested
          params = {
            functionDeclaration: function_declaration,
            awaitPromise: await_promise,
            target: target,
            resultOwnership: 'root',
            **options
          }

          session.async_send_command('script.callFunction', params)
        end

        # Evaluate an expression in the realm
        # @rbs expression: String -- JavaScript expression
        # @rbs await_promise: bool -- Whether to await promise results
        # @rbs **options: untyped -- Additional options (serializationOptions, resultOwnership, etc.)
        # @rbs return: Async::Task[Hash[String, untyped]] -- Evaluation result
        def evaluate(expression, await_promise, **options)
          raise RealmDestroyedError, @reason if disposed?

          # Use 'root' ownership by default to keep handles alive
          params = {
            expression: expression,
            awaitPromise: await_promise,
            target: target,
            resultOwnership: 'root',
            **options
          }

          session.async_send_command('script.evaluate', params)
        end

        # Resolve the CDP execution context ID for this realm
        # @rbs return: Integer -- Execution context ID
        def resolve_execution_context_id
          return @execution_context_id if @execution_context_id

          # This uses a Chrome-specific extension to BiDi
          result = session.connection.send_command('goog:cdp.resolveRealm', { realm: @id })
          @execution_context_id = result['executionContextId']
        end

        protected

        # Abstract method - must be implemented by subclasses
        # @rbs return: Session -- The session for this realm
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
        # @rbs browsing_context: BrowsingContext -- The browsing context
        # @rbs sandbox: String? -- Sandbox name
        # @rbs return: WindowRealm -- New window realm
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

        # Set the environment (Frame) for this realm
        # This is set by Frame when it's created
        # @rbs frame: untyped -- The frame environment
        # @rbs return: void
        def environment=(frame)
          @environment = frame
        end

        # Get the environment (Frame) for this realm
        # @rbs return: untyped -- The frame environment
        def environment
          @environment
        end

        # Override target to use context-based target
        # @rbs return: Hash[Symbol, untyped] -- BiDi target descriptor
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
        # @rbs owner: WindowRealm | DedicatedWorkerRealm | SharedWorkerRealm -- Owner realm
        # @rbs id: String -- Realm ID
        # @rbs origin: String -- Realm origin
        # @rbs return: DedicatedWorkerRealm -- New dedicated worker realm
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
        # @rbs browser: Browser -- Browser instance
        # @rbs id: String -- Realm ID
        # @rbs origin: String -- Realm origin
        # @rbs return: SharedWorkerRealm -- New shared worker realm
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

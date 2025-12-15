# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    module Core
      # BrowsingContext represents a browsing context (tab, window, or iframe)
      class BrowsingContext < EventEmitter
        include Disposable::DisposableMixin

        # Create a browsing context
        # @rbs user_context: UserContext -- Parent user context
        # @rbs parent: BrowsingContext? -- Parent browsing context
        # @rbs id: String -- Context ID
        # @rbs url: String -- Initial URL
        # @rbs original_opener: String? -- Original opener context ID
        # @rbs return: BrowsingContext -- New browsing context
        def self.from(user_context, parent, id, url, original_opener)
          context = new(user_context, parent, id, url, original_opener)
          context.send(:initialize_context)
          context
        end

        attr_reader :id, :user_context, :parent, :original_opener, :default_realm, :navigation, :inflight_requests

        def initialize(user_context, parent, id, url, original_opener)
          super()
          @user_context = user_context
          @parent = parent
          @id = id
          @url = url
          @original_opener = original_opener
          @reason = nil
          @disposables = Disposable::DisposableStack.new
          @children = {}
          @realms = {}
          @requests = {}
          @navigation = nil
          @emulation_state = { javascript_enabled: true }
          @inflight_requests = 0
          @inflight_mutex = Thread::Mutex.new

          @default_realm = WindowRealm.from(self)
        end

        # Check if the context is closed
        def closed?
          !@reason.nil?
        end

        alias disposed? closed?

        # Get the current URL
        # @rbs return: String -- Current URL
        def url
          @url
        end

        # Get child browsing contexts
        # @rbs return: Array[BrowsingContext] -- Child contexts
        def children
          @children.values
        end

        # Get all realms in this context
        # @rbs return: Array[WindowRealm] -- All realms
        def realms
          [@default_realm] + @realms.values
        end

        # Get the top-level browsing context
        # @rbs return: BrowsingContext -- Top-level context
        def top
          context = self
          while context.parent
            context = context.parent
          end
          context
        end

        # Activate this browsing context
        def activate
          raise BrowsingContextClosedError, @reason if closed?
          session.async_send_command('browsingContext.activate', { context: @id })
        end

        # Navigate to a URL
        # @rbs url: String -- URL to navigate to
        # @rbs wait: String? -- Wait condition ('none', 'interactive', 'complete')
        # @rbs return: Async::Task[untyped]
        def navigate(url, wait: nil)
          Async do
            raise BrowsingContextClosedError, @reason if closed?
            params = { context: @id, url: url }
            params[:wait] = wait if wait
            result = session.async_send_command('browsingContext.navigate', params).wait
            # URL will be updated via browsingContext.load event
            result
          end
        end

        # Reload the page
        # @rbs **options: untyped -- Reload options
        # @rbs return: Async::Task[untyped]
        def reload(**options)
          raise BrowsingContextClosedError, @reason if closed?
          session.async_send_command('browsingContext.reload', options.merge(context: @id))
        end

        # Capture a screenshot
        # @rbs **options: untyped -- Screenshot options
        # @rbs return: Async::Task[String] -- Base64-encoded image data
        def capture_screenshot(**options)
          raise BrowsingContextClosedError, @reason if closed?
          Async do
            result = session.async_send_command('browsingContext.captureScreenshot', options.merge(context: @id)).wait
            result['data']
          end
        end

        # Print to PDF
        # @rbs **options: untyped -- Print options
        # @rbs return: Async::Task[String] -- Base64-encoded PDF data
        def print(**options)
          raise BrowsingContextClosedError, @reason if closed?
          Async do
            result = session.async_send_command('browsingContext.print', options.merge(context: @id)).wait
            result['data']
          end
        end

        # Close this browsing context
        # @rbs prompt_unload: bool -- Whether to prompt before unload
        # @rbs return: Async::Task[void]
        def close(prompt_unload: false)
          raise BrowsingContextClosedError, @reason if closed?

          Async do
            # Close all children first (matches Puppeteer's Promise.all pattern)
            child_close_tasks = children.map do |child|
              -> { child.close(prompt_unload: prompt_unload).wait rescue BrowsingContextClosedError }
            end
            AsyncUtils.promise_all(*child_close_tasks).wait unless child_close_tasks.empty?

            # Ensure page.closed? is true and that the context has been removed
            # from parent registries once this call returns.
            # Register listener BEFORE sending close command to avoid race condition.
            closed_promise = Async::Promise.new
            closed_listener = ->(_) { closed_promise.resolve(nil) }
            on(:closed, &closed_listener)

            begin
              session.async_send_command('browsingContext.close', {
                context: @id,
                promptUnload: prompt_unload
              }).wait
              # Wait for :closed event to ensure state is updated
              closed_promise.wait
            rescue Connection::ProtocolError => e
              # "is not top-level" error occurs for iframes - they are closed
              # automatically when parent closes, so we don't need to wait
              raise unless e.message.include?('is not top-level')
            ensure
              off(:closed, &closed_listener)
            end
          end
        end

        # Traverse history
        # @rbs delta: Integer -- Number of steps to go back (negative) or forward (positive)
        # @rbs return: Async::Task[untyped]
        def traverse_history(delta)
          raise BrowsingContextClosedError, @reason if closed?
          session.async_send_command('browsingContext.traverseHistory', {
            context: @id,
            delta: delta
          })
        end

        # Handle a user prompt
        # @rbs **options: untyped -- Prompt handling options
        # @rbs return: Async::Task[untyped]
        def handle_user_prompt(**options)
          raise BrowsingContextClosedError, @reason if closed?
          session.async_send_command('browsingContext.handleUserPrompt', options.merge(context: @id))
        end

        # Set viewport
        # @rbs **options: untyped -- Viewport options
        # @rbs return: Async::Task[untyped]
        def set_viewport(**options)
          raise BrowsingContextClosedError, @reason if closed?
          session.async_send_command('browsingContext.setViewport', options.merge(context: @id))
        end

        # Perform input actions
        # @rbs actions: Array[Hash[String, untyped]] -- Input actions
        # @rbs return: Async::Task[untyped]
        def perform_actions(actions)
          raise BrowsingContextClosedError, @reason if closed?
          session.async_send_command('input.performActions', {
            context: @id,
            actions: actions
          })
        end

        # Release input actions
        def release_actions
          raise BrowsingContextClosedError, @reason if closed?
          session.async_send_command('input.releaseActions', { context: @id })
        end

        # Set cache behavior
        # @rbs cache_behavior: String -- 'default' or 'bypass'
        # @rbs return: Async::Task[untyped]
        def set_cache_behavior(cache_behavior)
          raise BrowsingContextClosedError, @reason if closed?
          session.async_send_command('network.setCacheBehavior', {
            contexts: [@id],
            cacheBehavior: cache_behavior
          })
        end

        # Create a sandboxed window realm
        # @rbs sandbox: String -- Sandbox name
        # @rbs return: WindowRealm -- New realm
        def create_window_realm(sandbox)
          raise BrowsingContextClosedError, @reason if closed?
          realm = WindowRealm.from(self, sandbox)
          realm.on(:worker) do |worker_realm|
            emit(:worker, { realm: worker_realm })
          end
          realm
        end

        # Add a preload script to this context
        # @rbs function_declaration: String -- JavaScript function
        # @rbs **options: untyped -- Script options
        # @rbs return: Async::Task[String] -- Script ID
        def add_preload_script(function_declaration, **options)
          raise BrowsingContextClosedError, @reason if closed?
          user_context.browser.add_preload_script(
            function_declaration,
            **options.merge(contexts: [self])
          )
        end

        # Remove a preload script
        # @rbs script: String -- Script ID
        # @rbs return: Async::Task[untyped]
        def remove_preload_script(script)
          raise BrowsingContextClosedError, @reason if closed?
          user_context.browser.remove_preload_script(script)
        end

        # Add network intercept
        # @rbs **options: untyped -- Intercept options
        # @rbs return: String -- Intercept ID
        def add_intercept(**options)
          raise BrowsingContextClosedError, @reason if closed?
          result = session.async_send_command('network.addIntercept', options.merge(contexts: [@id]))
          result['intercept']
        end

        # Get cookies
        # @rbs **options: untyped -- Cookie filter options
        # @rbs return: Array[Hash[String, untyped]] -- Cookies
        def get_cookies(**options)
          raise BrowsingContextClosedError, @reason if closed?
          params = options.dup
          params[:partition] = {
            type: 'context',
            context: @id
          }
          result = session.async_send_command('storage.getCookies', params)
          result['cookies']
        end

        # Set a cookie
        # @rbs cookie: Hash[String, untyped] -- Cookie data
        # @rbs return: Async::Task[untyped]
        def set_cookie(cookie)
          raise BrowsingContextClosedError, @reason if closed?
          session.async_send_command('storage.setCookie', {
            cookie: cookie,
            partition: {
              type: 'context',
              context: @id
            }
          })
        end

        # Delete cookies
        # @rbs *cookie_filters: Hash[String, untyped] -- Cookie filters
        # @rbs return: void
        def delete_cookie(*cookie_filters)
          raise BrowsingContextClosedError, @reason if closed?
          cookie_filters.each do |filter|
            session.async_send_command('storage.deleteCookies', {
              filter: filter,
              partition: {
                type: 'context',
                context: @id
              }
            })
          end
        end

        # Set geolocation override
        # @rbs **options: untyped -- Geolocation options
        # @rbs return: Async::Task[untyped]
        def set_geolocation_override(**options)
          raise BrowsingContextClosedError, @reason if closed?
          raise 'Missing coordinates' unless options[:coordinates]

          session.async_send_command('emulation.setGeolocationOverride', {
            coordinates: options[:coordinates],
            contexts: [@id]
          })
        end

        # Set timezone override
        # @rbs timezone_id: String? -- Timezone ID
        # @rbs return: Async::Task[untyped]
        def set_timezone_override(timezone_id = nil)
          raise BrowsingContextClosedError, @reason if closed?

          # Remove GMT prefix for interop between CDP and BiDi
          timezone_id = timezone_id&.sub(/^GMT/, '')

          session.async_send_command('emulation.setTimezoneOverride', {
            timezone: timezone_id,
            contexts: [@id]
          })
        end

        # Set files on an input element
        # @rbs element: Hash[String, untyped] -- Element reference
        # @rbs files: Array[String] -- File paths
        # @rbs return: Async::Task[untyped]
        def set_files(element, files)
          raise BrowsingContextClosedError, @reason if closed?
          session.async_send_command('input.setFiles', {
            context: @id,
            element: element,
            files: files
          })
        end

        # Locate nodes in the context
        # @rbs locator: Hash[String, untyped] -- Node locator
        # @rbs start_nodes: Array[Hash[String, untyped]] -- Starting nodes
        # @rbs return: Array[Hash[String, untyped]] -- Located nodes
        def locate_nodes(locator, start_nodes = [])
          raise BrowsingContextClosedError, @reason if closed?
          params = {
            context: @id,
            locator: locator
          }
          params[:startNodes] = start_nodes unless start_nodes.empty?

          result = session.async_send_command('browsingContext.locateNodes', params)
          result['nodes']
        end

        # Set JavaScript enabled state
        # @rbs enabled: bool -- Whether JavaScript is enabled
        # @rbs return: Async::Task[void]
        def set_javascript_enabled(enabled)
          Async do
            raise BrowsingContextClosedError, @reason if closed?
            session.async_send_command('emulation.setScriptingEnabled', {
              enabled: enabled ? nil : false,
              contexts: [@id]
            }).wait
            @emulation_state[:javascript_enabled] = enabled
          end
        end

        # Check if JavaScript is enabled
        # @rbs return: bool -- Whether JavaScript is enabled
        def javascript_enabled?
          @emulation_state[:javascript_enabled]
        end

        # Subscribe to events for this context
        # @rbs events: Array[String] -- Event names
        # @rbs return: void
        def subscribe(events)
          raise BrowsingContextClosedError, @reason if closed?
          session.subscribe(events, [@id])
        end

        # Add interception for this context
        # @rbs events: Array[String] -- Event names
        # @rbs return: void
        def add_interception(events)
          raise BrowsingContextClosedError, @reason if closed?
          session.subscribe(events, [@id])
        end

        # Override dispose to emit :closed event before setting @disposed = true
        # This is needed because EventEmitter#emit returns early if @disposed is true
        def dispose
          return if disposed?

          @reason ||= 'Browsing context closed, probably because the user context closed'
          emit(:closed, { reason: @reason })

          super # This sets @disposed = true and calls perform_dispose
        end

        protected

        def perform_dispose
          dispose_children('Parent browsing context was disposed')

          begin
            @default_realm.dispose unless @default_realm&.disposed?
          rescue StandardError
            # Ignore realm disposal failures during shutdown
          end

          @realms.values.each do |realm|
            begin
              realm.dispose unless realm.disposed?
            rescue StandardError
              # Ignore per-realm cleanup errors
            end
          end
          @realms.clear

          @disposables.dispose
          super
        end

        private

        def session
          @user_context.browser.session
        end

        def initialize_context
          # Listen for user context closure
          @user_context.once(:closed) do |data|
            dispose_context("Browsing context closed: #{data[:reason]}")
          end

          # Listen for various browsing context events
          setup_event_listeners
        end

        def setup_event_listeners
          # Context destroyed
          session.on('browsingContext.contextDestroyed') do |info|
            next unless info['context'] == @id
            dispose_children('Parent browsing context was disposed')
            dispose_context('Browsing context already closed')
          end

          # Child context created
          session.on('browsingContext.contextCreated') do |info|
            next unless info['parent'] == @id

            child_context = BrowsingContext.from(
              @user_context,
              self,
              info['context'],
              info['url'],
              info['originalOpener']
            )

            @children[child_context.id] = child_context

            child_context.once(:closed) do
              @children.delete(child_context.id)
            end

            emit(:browsingcontext, { browsing_context: child_context })
          end

          # History updated
          session.on('browsingContext.historyUpdated') do |info|
            next unless info['context'] == @id
            @url = info['url']
            emit(:history_updated, nil)
          end

          # Fragment navigated (anchor links, hash changes)
          session.on('browsingContext.fragmentNavigated') do |info|
            next unless info['context'] == @id
            @url = info['url']
            emit(:fragment_navigated, nil)
          end

          # DOM content loaded
          session.on('browsingContext.domContentLoaded') do |info|
            next unless info['context'] == @id
            @url = info['url']
            emit(:dom_content_loaded, nil)
          end

          # Page loaded
          session.on('browsingContext.load') do |info|
            next unless info['context'] == @id
            @url = info['url']
            emit(:load, nil)
          end

          # Navigation started
          session.on('browsingContext.navigationStarted') do |info|
            next unless info['context'] == @id

            # Clean up disposed requests
            @requests.delete_if { |_, request| request.disposed? }

            # Skip if navigation hasn't finished
            next if @navigation && !@navigation.disposed?

            # Create new navigation
            @navigation = Navigation.from(self)

            # Wrap navigation in EventEmitter and register with disposables
            # This follows Puppeteer's pattern: new EventEmitter(this.#navigation)
            navigation_emitter = EventEmitter.new
            @disposables.use(navigation_emitter)

            # Listen for navigation completion events to update URL
            # Puppeteer: for (const eventName of ['fragment', 'failed', 'aborted'])
            [:fragment, :failed, :aborted].each do |event_name|
              @navigation.once(event_name) do |data|
                navigation_emitter.dispose
                @url = data[:url]
              end
            end

            # Emit navigation event for subscribers (e.g., Frame#wait_for_navigation)
            emit(:navigation, { navigation: @navigation })
          end

          # Network events
          session.on('network.beforeRequestSent') do |event|
            next unless event['context'] == @id

            request_id = event['request']['request']
            next if @requests.key?(request_id)

            @requests[request_id] = true

            # Increment inflight requests counter
            @inflight_mutex.synchronize do
              @inflight_requests += 1
              emit(:inflight_changed, { inflight: @inflight_requests })
            end
          end

          session.on('network.responseCompleted') do |event|
            next unless event['context'] == @id

            request_id = event['request']['request']
            next unless @requests.delete(request_id)

            # Decrement inflight requests counter
            @inflight_mutex.synchronize do
              @inflight_requests -= 1
              emit(:inflight_changed, { inflight: @inflight_requests })
            end
          end

          session.on('network.fetchError') do |event|
            next unless event['context'] == @id

            request_id = event['request']['request']
            next unless @requests.delete(request_id)

            # Decrement inflight requests counter
            @inflight_mutex.synchronize do
              @inflight_requests -= 1
              emit(:inflight_changed, { inflight: @inflight_requests })
            end
          end

          # Log entries
          session.on('log.entryAdded') do |entry|
            next unless entry.dig('source', 'context') == @id
            emit(:log, { entry: entry })
          end

          # User prompts
          session.on('browsingContext.userPromptOpened') do |info|
            next unless info['context'] == @id
            # user_prompt = UserPrompt.from(self, info)
            # emit(:userprompt, { user_prompt: user_prompt })
          end

          # File dialog
          session.on('input.fileDialogOpened') do |info|
            next unless info['context'] == @id
            emit(:filedialogopened, info)
          end
        end

        def dispose_children(reason)
          @children.values.each do |child|
            next if child.closed?
            child.send(:dispose_context, reason)
          end
        end

        def dispose_context(reason)
          # IMPORTANT: Set @reason AFTER calling dispose to avoid early return
          # dispose checks disposed? which is aliased to closed?, and closed? returns !@reason.nil?
          dispose
          @reason = reason
        end
      end
    end
  end
end

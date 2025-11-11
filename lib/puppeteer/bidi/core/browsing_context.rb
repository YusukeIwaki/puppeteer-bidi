# frozen_string_literal: true

require_relative 'event_emitter'
require_relative 'disposable'
require_relative 'realm'
require_relative 'navigation'

module Puppeteer
  module Bidi
    module Core
      # BrowsingContext represents a browsing context (tab, window, or iframe)
      class BrowsingContext < EventEmitter
        include Disposable::DisposableMixin

        # Create a browsing context
        # @param user_context [UserContext] Parent user context
        # @param parent [BrowsingContext, nil] Parent browsing context
        # @param id [String] Context ID
        # @param url [String] Initial URL
        # @param original_opener [String, nil] Original opener context ID
        # @return [BrowsingContext] New browsing context
        def self.from(user_context, parent, id, url, original_opener)
          context = new(user_context, parent, id, url, original_opener)
          context.send(:initialize_context)
          context
        end

        attr_reader :id, :user_context, :parent, :original_opener, :default_realm, :navigation

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

          @default_realm = WindowRealm.from(self)
        end

        # Check if the context is closed
        def closed?
          !@reason.nil?
        end

        alias disposed? closed?

        # Get the current URL
        # @return [String] Current URL
        def url
          @url
        end

        # Get child browsing contexts
        # @return [Array<BrowsingContext>] Child contexts
        def children
          @children.values
        end

        # Get all realms in this context
        # @return [Array<WindowRealm>] All realms
        def realms
          [@default_realm] + @realms.values
        end

        # Get the top-level browsing context
        # @return [BrowsingContext] Top-level context
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
          session.send_command('browsingContext.activate', { context: @id })
        end

        # Navigate to a URL
        # @param url [String] URL to navigate to
        # @param wait [String, nil] Wait condition ('none', 'interactive', 'complete')
        def navigate(url, wait: nil)
          raise BrowsingContextClosedError, @reason if closed?
          params = { context: @id, url: url }
          params[:wait] = wait if wait
          result = session.send_command('browsingContext.navigate', params)
          # URL will be updated via browsingContext.load event
          result
        end

        # Reload the page
        # @param options [Hash] Reload options
        def reload(**options)
          raise BrowsingContextClosedError, @reason if closed?
          session.send_command('browsingContext.reload', options.merge(context: @id))
        end

        # Capture a screenshot
        # @param options [Hash] Screenshot options
        # @return [String] Base64-encoded image data
        def capture_screenshot(**options)
          raise BrowsingContextClosedError, @reason if closed?
          result = session.send_command('browsingContext.captureScreenshot', options.merge(context: @id))
          result['data']
        end

        # Print to PDF
        # @param options [Hash] Print options
        # @return [String] Base64-encoded PDF data
        def print(**options)
          raise BrowsingContextClosedError, @reason if closed?
          result = session.send_command('browsingContext.print', options.merge(context: @id))
          result['data']
        end

        # Close this browsing context
        # @param prompt_unload [Boolean] Whether to prompt before unload
        def close(prompt_unload: false)
          raise BrowsingContextClosedError, @reason if closed?

          # Close all children first
          children.each do |child|
            child.close(prompt_unload: prompt_unload)
          end

          # Send close command
          # Note: For non-top-level contexts (iframes), this may fail with
          # "Browsing context ... is not top-level" error, which is expected
          # because parent closure automatically closes children in BiDi protocol
          begin
            session.send_command('browsingContext.close', {
              context: @id,
              promptUnload: prompt_unload
            })
          rescue Connection::ProtocolError => e
            # Ignore "not top-level" errors for iframe contexts
            # This happens when parent context closes and BiDi auto-closes children
            # The error message is in format: "BiDi error (browsingContext.close): Browsing context with id ... is not top-level"
            if ENV['DEBUG_BIDI_COMMAND']
              puts "[BiDi] Close error for context #{@id}: #{e.message.inspect}"
            end
            raise unless e.message.include?('is not top-level')
          end
        end

        # Traverse history
        # @param delta [Integer] Number of steps to go back (negative) or forward (positive)
        def traverse_history(delta)
          raise BrowsingContextClosedError, @reason if closed?
          session.send_command('browsingContext.traverseHistory', {
            context: @id,
            delta: delta
          })
        end

        # Handle a user prompt
        # @param options [Hash] Prompt handling options
        def handle_user_prompt(**options)
          raise BrowsingContextClosedError, @reason if closed?
          session.send_command('browsingContext.handleUserPrompt', options.merge(context: @id))
        end

        # Set viewport
        # @param options [Hash] Viewport options
        def set_viewport(**options)
          raise BrowsingContextClosedError, @reason if closed?
          session.send_command('browsingContext.setViewport', options.merge(context: @id))
        end

        # Perform input actions
        # @param actions [Array<Hash>] Input actions
        def perform_actions(actions)
          raise BrowsingContextClosedError, @reason if closed?
          session.send_command('input.performActions', {
            context: @id,
            actions: actions
          })
        end

        # Release input actions
        def release_actions
          raise BrowsingContextClosedError, @reason if closed?
          session.send_command('input.releaseActions', { context: @id })
        end

        # Set cache behavior
        # @param cache_behavior [String] 'default' or 'bypass'
        def set_cache_behavior(cache_behavior)
          raise BrowsingContextClosedError, @reason if closed?
          session.send_command('network.setCacheBehavior', {
            contexts: [@id],
            cacheBehavior: cache_behavior
          })
        end

        # Create a sandboxed window realm
        # @param sandbox [String] Sandbox name
        # @return [WindowRealm] New realm
        def create_window_realm(sandbox)
          raise BrowsingContextClosedError, @reason if closed?
          realm = WindowRealm.from(self, sandbox)
          realm.on(:worker) do |worker_realm|
            emit(:worker, { realm: worker_realm })
          end
          realm
        end

        # Add a preload script to this context
        # @param function_declaration [String] JavaScript function
        # @param options [Hash] Script options
        # @return [String] Script ID
        def add_preload_script(function_declaration, **options)
          raise BrowsingContextClosedError, @reason if closed?
          user_context.browser.add_preload_script(
            function_declaration,
            **options.merge(contexts: [self])
          )
        end

        # Remove a preload script
        # @param script [String] Script ID
        def remove_preload_script(script)
          raise BrowsingContextClosedError, @reason if closed?
          user_context.browser.remove_preload_script(script)
        end

        # Add network intercept
        # @param options [Hash] Intercept options
        # @return [String] Intercept ID
        def add_intercept(**options)
          raise BrowsingContextClosedError, @reason if closed?
          result = session.send_command('network.addIntercept', options.merge(contexts: [@id]))
          result['intercept']
        end

        # Get cookies
        # @param options [Hash] Cookie filter options
        # @return [Array<Hash>] Cookies
        def get_cookies(**options)
          raise BrowsingContextClosedError, @reason if closed?
          params = options.dup
          params[:partition] = {
            type: 'context',
            context: @id
          }
          result = session.send_command('storage.getCookies', params)
          result['cookies']
        end

        # Set a cookie
        # @param cookie [Hash] Cookie data
        def set_cookie(cookie)
          raise BrowsingContextClosedError, @reason if closed?
          session.send_command('storage.setCookie', {
            cookie: cookie,
            partition: {
              type: 'context',
              context: @id
            }
          })
        end

        # Delete cookies
        # @param cookie_filters [Array<Hash>] Cookie filters
        def delete_cookie(*cookie_filters)
          raise BrowsingContextClosedError, @reason if closed?
          cookie_filters.each do |filter|
            session.send_command('storage.deleteCookies', {
              filter: filter,
              partition: {
                type: 'context',
                context: @id
              }
            })
          end
        end

        # Set geolocation override
        # @param options [Hash] Geolocation options
        def set_geolocation_override(**options)
          raise BrowsingContextClosedError, @reason if closed?
          raise 'Missing coordinates' unless options[:coordinates]

          session.send_command('emulation.setGeolocationOverride', {
            coordinates: options[:coordinates],
            contexts: [@id]
          })
        end

        # Set timezone override
        # @param timezone_id [String, nil] Timezone ID
        def set_timezone_override(timezone_id = nil)
          raise BrowsingContextClosedError, @reason if closed?

          # Remove GMT prefix for interop between CDP and BiDi
          timezone_id = timezone_id&.sub(/^GMT/, '')

          session.send_command('emulation.setTimezoneOverride', {
            timezone: timezone_id,
            contexts: [@id]
          })
        end

        # Set files on an input element
        # @param element [Hash] Element reference
        # @param files [Array<String>] File paths
        def set_files(element, files)
          raise BrowsingContextClosedError, @reason if closed?
          session.send_command('input.setFiles', {
            context: @id,
            element: element,
            files: files
          })
        end

        # Locate nodes in the context
        # @param locator [Hash] Node locator
        # @param start_nodes [Array<Hash>] Starting nodes
        # @return [Array<Hash>] Located nodes
        def locate_nodes(locator, start_nodes = [])
          raise BrowsingContextClosedError, @reason if closed?
          params = {
            context: @id,
            locator: locator
          }
          params[:startNodes] = start_nodes unless start_nodes.empty?

          result = session.send_command('browsingContext.locateNodes', params)
          result['nodes']
        end

        # Set JavaScript enabled state
        # @param enabled [Boolean] Whether JavaScript is enabled
        def set_javascript_enabled(enabled)
          raise BrowsingContextClosedError, @reason if closed?
          session.send_command('emulation.setScriptingEnabled', {
            enabled: enabled ? nil : false,
            contexts: [@id]
          })
          @emulation_state[:javascript_enabled] = enabled
        end

        # Check if JavaScript is enabled
        # @return [Boolean] Whether JavaScript is enabled
        def javascript_enabled?
          @emulation_state[:javascript_enabled]
        end

        # Subscribe to events for this context
        # @param events [Array<String>] Event names
        def subscribe(events)
          raise BrowsingContextClosedError, @reason if closed?
          session.subscribe(events, [@id])
        end

        # Add interception for this context
        # @param events [Array<String>] Event names
        def add_interception(events)
          raise BrowsingContextClosedError, @reason if closed?
          session.subscribe(events, [@id])
        end

        protected

        def perform_dispose
          @reason ||= 'Browsing context closed, probably because the user context closed'
          emit(:closed, { reason: @reason })

          # Dispose all children
          @children.values.each do |child|
            child.send(:dispose_context, 'Parent browsing context was disposed')
          end

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
            next if @requests.key?(event['request']['request'])

            # request = Request.from(self, event)
            # @requests[request.id] = request
            # emit(:request, { request: request })
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

        def dispose_context(reason)
          @reason = reason
          dispose
        end
      end
    end
  end
end

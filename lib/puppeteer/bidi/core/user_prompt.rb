# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    module Core
      # UserPrompt represents a user prompt (alert, confirm, prompt)
      class UserPrompt < EventEmitter
        include Disposable::DisposableMixin

        # Create a user prompt instance
        # @rbs browsing_context: BrowsingContext -- The browsing context
        # @rbs info: Hash[String, untyped] -- The userPromptOpened event data
        # @rbs return: UserPrompt -- New user prompt instance
        def self.from(browsing_context, info)
          prompt = new(browsing_context, info)
          prompt.send(:initialize_prompt)
          prompt
        end

        attr_reader :browsing_context, :info, :result

        def initialize(browsing_context, info)
          super()
          @browsing_context = browsing_context
          @info = info
          @reason = nil
          @result = nil
          @disposables = Disposable::DisposableStack.new
        end

        # Check if the prompt is closed
        def closed?
          !@reason.nil?
        end

        alias disposed? closed?

        # Check if the prompt has been handled
        # Auto-handled prompts return true immediately
        # @rbs return: bool -- Whether the prompt is handled
        def handled?
          handler = @info['handler']
          return true if handler == 'accept' || handler == 'dismiss'
          !@result.nil?
        end

        # Handle the user prompt
        # @rbs accept: bool? -- Whether to accept the prompt
        # @rbs user_text: String? -- Text to enter (for prompt dialogs)
        # @rbs return: Async::Task[Hash[String, untyped]] -- Result of handling the prompt
        def handle(accept: nil, user_text: nil)
          Async do
            raise UserPromptClosedError, @reason if closed?

            params = { context: @info["context"] }
            params[:accept] = accept unless accept.nil?
            params[:userText] = user_text if user_text

            session.async_send_command("browsingContext.handleUserPrompt", params).wait

            # The handled event is emitted before the command response resolves.
            @result
          end
        end

        def dispose
          return if @disposed

          @reason ||= "User prompt already closed, probably because the associated browsing context was destroyed."
          emit(:closed, @reason)
          super
        end

        protected

        def perform_dispose
          @browsing_context.off(:closed, &@context_closed_listener) if @context_closed_listener
          session.off("browsingContext.userPromptClosed", &@prompt_closed_listener) if @prompt_closed_listener
          @disposables.dispose
          remove_all_listeners
        end

        private

        def session
          @browsing_context.user_context.browser.session
        end

        def initialize_prompt
          # Listen for browsing context closure
          @context_closed_listener = proc do |reason|
            dispose_prompt("User prompt already closed: #{reason}")
          end
          @browsing_context.on(:closed, &@context_closed_listener)

          # Listen for prompt closed event
          @prompt_closed_listener = method(:handle_prompt_closed).to_proc
          session.on("browsingContext.userPromptClosed", &@prompt_closed_listener)
        end

        def handle_prompt_closed(params)
          return unless params["context"] == @browsing_context.id

          @result = params
          emit(:handled, params)
          dispose_prompt("User prompt already handled.")
        end

        def dispose_prompt(reason)
          @reason = reason
          dispose
        end
      end
    end
  end
end

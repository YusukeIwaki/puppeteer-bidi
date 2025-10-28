# frozen_string_literal: true

require_relative 'event_emitter'
require_relative 'disposable'

module Puppeteer
  module Bidi
    module Core
      # UserPrompt represents a user prompt (alert, confirm, prompt)
      class UserPrompt < EventEmitter
        include Disposable::DisposableMixin

        # Create a user prompt instance
        # @param browsing_context [BrowsingContext] The browsing context
        # @param info [Hash] The userPromptOpened event data
        # @return [UserPrompt] New user prompt instance
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
        # @return [Boolean] Whether the prompt is handled
        def handled?
          handler = @info['handler']
          return true if handler == 'accept' || handler == 'dismiss'
          !@result.nil?
        end

        # Handle the user prompt
        # @param accept [Boolean, nil] Whether to accept the prompt
        # @param user_text [String, nil] Text to enter (for prompt dialogs)
        # @return [Hash] Result of handling the prompt
        def handle(accept: nil, user_text: nil)
          raise "User prompt closed: #{@reason}" if closed?

          params = { context: @info['context'] }
          params[:accept] = accept unless accept.nil?
          params[:userText] = user_text if user_text

          session.send_command('browsingContext.handleUserPrompt', params)

          # The result is set by the userPromptClosed event before this returns
          @result
        end

        protected

        def perform_dispose
          @reason ||= 'User prompt closed, probably because the browsing context was destroyed'
          emit(:closed, { reason: @reason })
          @disposables.dispose
          super
        end

        private

        def session
          @browsing_context.user_context.browser.session
        end

        def initialize_prompt
          # Listen for browsing context closure
          @browsing_context.once(:closed) do |data|
            dispose_prompt("User prompt closed: #{data[:reason]}")
          end

          # Listen for prompt closed event
          session.on('browsingContext.userPromptClosed') do |params|
            next unless params['context'] == @browsing_context.id

            @result = params
            emit(:handled, params)
            dispose_prompt('User prompt handled')
          end
        end

        def dispose_prompt(reason)
          @reason = reason
          dispose
        end
      end
    end
  end
end

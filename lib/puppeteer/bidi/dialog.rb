# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # Dialog instances are dispatched by Page via the :dialog event.
    class Dialog
      attr_reader :type #: String
      attr_reader :message #: String
      attr_reader :default_value #: String

      # @rbs prompt: Core::UserPrompt -- Core user prompt
      # @rbs return: Dialog -- Public dialog wrapper
      def self.from(prompt)
        new(prompt)
      end

      # @rbs prompt: Core::UserPrompt -- Core user prompt
      # @rbs return: void
      def initialize(prompt)
        @prompt = prompt
        @type = prompt.info["type"]
        @message = prompt.info["message"]
        @default_value = prompt.info.fetch("defaultValue", "")
        @handled = prompt.handled?

        prompt.once(:handled) do
          @handled = true
        end
      end

      # @rbs return: bool -- Whether the dialog has been handled
      def handled?
        @handled
      end

      # @rbs prompt_text: String? -- Text entered into a prompt dialog
      # @rbs return: void
      def accept(prompt_text = nil)
        raise Error, "Cannot accept dialog which is already handled!" if handled?

        @handled = true
        handle(accept: true, text: prompt_text)
      end

      # @rbs return: void
      def dismiss
        raise Error, "Cannot dismiss dialog which is already handled!" if handled?

        @handled = true
        handle(accept: false)
      end

      private

      # @rbs accept: bool -- Whether to accept the dialog
      # @rbs text: String? -- Prompt text
      # @rbs return: void
      def handle(accept:, text: nil)
        @prompt.handle(accept: accept, user_text: text).wait
        nil
      end
    end
  end
end

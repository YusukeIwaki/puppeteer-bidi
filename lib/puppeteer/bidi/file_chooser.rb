# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # FileChooser represents a file chooser dialog opened by an input element
    # Based on Puppeteer's FileChooser implementation
    class FileChooser
      # @param element [ElementHandle] The input element that opened the file chooser
      # @param multiple [Boolean] Whether multiple files can be selected
      def initialize(element, multiple)
        @element = element
        @multiple = multiple
        @handled = false
      end

      # Check if multiple files can be selected
      # @return [Boolean] True if multiple files can be selected
      def multiple?
        @multiple
      end

      # Accept the file chooser with the given file paths
      # @param paths [Array<String>] File paths to accept
      # @raise [RuntimeError] If the file chooser has already been handled
      # @raise [RuntimeError] If multiple files passed to single-file input
      def accept(paths)
        raise 'Cannot accept FileChooser which is already handled!' if @handled

        # Validate that single-file inputs don't receive multiple files
        if !@multiple && paths.length > 1
          raise 'Multiple file paths passed to a file input that does not accept multiple files'
        end

        @handled = true
        @element.upload_file(*paths)
      end

      # Cancel the file chooser
      # @raise [RuntimeError] If the file chooser has already been handled
      def cancel
        raise 'Cannot cancel FileChooser which is already handled!' if @handled

        @handled = true
        @element.evaluate(<<~JAVASCRIPT)
        element => {
          element.dispatchEvent(new Event('cancel', {bubbles: true}));
        }
        JAVASCRIPT
      end
    end
  end
end

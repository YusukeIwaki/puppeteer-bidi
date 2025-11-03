# frozen_string_literal: true

module Puppeteer
  module Bidi
    # BrowserContext represents an isolated browsing session
    # This is a high-level wrapper around Core::UserContext
    class BrowserContext
      attr_reader :user_context

      def initialize(browser, user_context)
        @browser = browser
        @user_context = user_context
        @pages = {}
      end

      # Create a new page (tab/window)
      # @return [Page] New page instance
      def new_page
        browsing_context = @user_context.create_browsing_context('tab')
        page = Page.new(self, browsing_context)
        @pages[browsing_context.id] = page

        # Remove from pages when closed
        browsing_context.once(:closed) do
          @pages.delete(browsing_context.id)
        end

        page
      end

      # Get all pages in this context
      # @return [Array<Page>] All pages
      def pages
        @pages.values
      end

      # Close the browser context
      def close
        @user_context.close
      end

      # Check if context is closed
      # @return [Boolean] Whether the context is closed
      def closed?
        @user_context.disposed?
      end
    end
  end
end

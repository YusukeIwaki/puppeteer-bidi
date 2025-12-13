# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # BrowserContext represents an isolated browsing session
    # This is a high-level wrapper around Core::UserContext
    class BrowserContext
      attr_reader :user_context #: Core::UserContext
      attr_reader :browser #: Browser

      # @rbs browser: Browser -- Parent browser instance
      # @rbs user_context: Core::UserContext -- Associated user context
      # @rbs return: void
      def initialize(browser, user_context)
        @browser = browser
        @user_context = user_context
        @pages = {}
      end

      # Create a new page (tab/window)
      # @rbs return: Page -- New page instance
      def new_page
        browsing_context = @user_context.create_browsing_context('tab')
        page_for(browsing_context)
      end

      # Get all pages in this context
      # @rbs return: Array[Page] -- All pages
      def pages
        @pages.values
      end

      # Get or create a Page for the given browsing context
      # @rbs browsing_context: Core::BrowsingContext -- Browsing context
      # @rbs return: Page -- Page instance
      def page_for(browsing_context)
        @pages[browsing_context.id] ||= begin
          page = Page.new(self, browsing_context)

          browsing_context.once(:closed) do
            @pages.delete(browsing_context.id)
          end

          page
        end
      end

      # Close the browser context
      # @rbs return: void
      def close
        @user_context.close
      end

      # Check if context is closed
      # @rbs return: bool -- Whether the context is closed
      def closed?
        @user_context.disposed?
      end
    end
  end
end

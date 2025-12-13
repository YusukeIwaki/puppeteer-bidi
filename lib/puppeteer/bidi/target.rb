# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # @rbs!
    #   type Target = BrowserTarget | PageTarget | FrameTarget

    class BrowserTarget
      # @rbs browser: Browser
      # @rbs return: void
      def initialize(browser)
        @browser = browser
      end

      # @rbs return: nil
      def page
        nil
      end

      # @rbs return: String
      def url
        ''
      end

      # @rbs return: String
      def type
        'browser'
      end

      # @rbs return: Browser
      def browser
        @browser
      end

      # @rbs return: BrowserContext
      def browser_context
        @browser.default_browser_context
      end
    end

    class PageTarget
      # @rbs page: Page
      # @rbs return: void
      def initialize(page)
        @page = page
      end

      # @rbs return: Page
      def page
        @page
      end

      # @rbs return: String
      def url
        @page.url
      end

      # @rbs return: String
      def type
        'page'
      end

      # @rbs return: Browser
      def browser
        @page.browser_context.browser
      end

      # @rbs return: BrowserContext
      def browser_context
        @page.browser_context
      end
    end

    class FrameTarget
      # @rbs frame: Frame
      # @rbs return: void
      def initialize(frame)
        @frame = frame
      end

      # @rbs return: Page
      def page
        @frame.page
      end

      # @rbs return: String
      def url
        @frame.url
      end

      # @rbs return: String
      def type
        'frame'
      end

      # @rbs return: Browser
      def browser
        @frame.browser_context.browser
      end

      # @rbs return: BrowserContext
      def browser_context
        @frame.browser_context
      end
    end
  end
end

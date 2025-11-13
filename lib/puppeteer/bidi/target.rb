module Puppeteer
  module Bidi
    class BrowserTarget
      def initialize(browser)
        @browser = browser
      end

      def page
        nil
      end

      def url
        ''
      end

      def type
        'browser'
      end

      def browser
        @browser
      end

      def browser_context
        @browser.default_browser_context
      end
    end

    class PageTarget
      def initialize(page)
        @page = page
      end

      def page
        @page
      end

      def url
        @page.url
      end

      def type
        'page'
      end

      def browser
        @page.browser_context.browser
      end

      def browser_context
        @page.browser_context
      end
    end

    class FrameTarget
      def initialize(frame)
        @frame = frame
      end

      def page
        @frame.page
      end

      def url
        @frame.url
      end

      def type
        'frame'
      end

      def browser
        @frame.browser_context.browser
      end

      def browser_context
        @frame.browser_context
      end
    end
  end
end

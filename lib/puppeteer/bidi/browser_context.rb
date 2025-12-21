# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # BrowserContext represents an isolated browsing session
    # This is a high-level wrapper around Core::UserContext
    class BrowserContext
      # Maps web permission names to protocol permission names
      # Based on Puppeteer's WEB_PERMISSION_TO_PROTOCOL_PERMISSION
      WEB_PERMISSION_TO_PROTOCOL_PERMISSION = {
        'accelerometer' => 'sensors',
        'ambient-light-sensor' => 'sensors',
        'background-sync' => 'backgroundSync',
        'camera' => 'videoCapture',
        'clipboard-read' => 'clipboardReadWrite',
        'clipboard-sanitized-write' => 'clipboardSanitizedWrite',
        'clipboard-write' => 'clipboardReadWrite',
        'geolocation' => 'geolocation',
        'gyroscope' => 'sensors',
        'idle-detection' => 'idleDetection',
        'keyboard-lock' => 'keyboardLock',
        'magnetometer' => 'sensors',
        'microphone' => 'audioCapture',
        'midi' => 'midi',
        'midi-sysex' => 'midiSysex',
        'notifications' => 'notifications',
        'payment-handler' => 'paymentHandler',
        'persistent-storage' => 'durableStorage',
        'pointer-lock' => 'pointerLock'
      }.freeze

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
        return [] if closed?

        # Return pages for all currently-known top-level browsing contexts.
        # Browsing contexts are synchronized from `browsingContext.getTree` during browser/session
        # initialization, so this allows `Puppeteer::Bidi.connect` to expose existing pages without
        # requiring an explicit enumeration via `wait_for_target`.
        @user_context.browsing_contexts
                     .reject(&:disposed?)
                     .map { |browsing_context| page_for(browsing_context) }
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

      # Override permissions for an origin
      # @rbs origin: String -- Origin URL
      # @rbs permissions: Array[String] -- Permissions to grant
      # @rbs return: void
      def override_permissions(origin, permissions)
        # Validate all permissions are known
        permissions_set = permissions.map do |permission|
          protocol_permission = WEB_PERMISSION_TO_PROTOCOL_PERMISSION[permission.to_s]
          raise ArgumentError, "Unknown permission: #{permission}" unless protocol_permission

          permission.to_s
        end.to_set

        # Set each permission
        WEB_PERMISSION_TO_PROTOCOL_PERMISSION.each_key do |permission|
          state = permissions_set.include?(permission) ? 'granted' : 'denied'
          begin
            @user_context.set_permissions(origin, { name: permission }, state).wait
          rescue StandardError
            # Ignore errors for denied permissions (some may not be supported)
            raise if permissions_set.include?(permission)
          end
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

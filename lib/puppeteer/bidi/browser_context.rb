# frozen_string_literal: true
# rbs_inline: enabled

require "uri"

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
        @frame_targets = {}
        @overrides = []
      end

      # Create a new page (tab/window)
      # @rbs background: bool? -- Whether to open the page in background
      # @rbs type: String? -- 'tab' or 'window'
      # @rbs window_bounds: Hash[Symbol | String, untyped]? -- Initial window bounds for window pages
      # @rbs return: Page -- New page instance
      def new_page(background: nil, type: nil, window_bounds: nil)
        create_type = type.to_s == 'window' ? 'window' : 'tab'
        browsing_context = @user_context.create_browsing_context(create_type, background: background)
        page = page_for(browsing_context)

        if create_type == 'window' && window_bounds
          begin
            @browser.set_window_bounds(browsing_context.window_id, window_bounds)
          rescue StandardError => error
            debug_error(error)
          end
        end

        page
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

      # Get all known targets in this browser context.
      # @rbs return: Array[PageTarget | FrameTarget] -- Known targets
      def targets
        pages.flat_map do |page|
          [page.target] + page.frames.drop(1).map { |frame| target_for_frame(frame) }
        end
      end

      # Wait until a target in this context satisfies the predicate.
      # @rbs timeout: Integer? -- Timeout in milliseconds (default: 30000)
      # @rbs &predicate: (PageTarget | FrameTarget) -> boolish -- Predicate evaluated against each target
      # @rbs return: PageTarget | FrameTarget -- Matching target
      def wait_for_target(timeout: nil, &predicate)
        predicate ||= ->(_target) { true }

        browser.wait_for_target(timeout: timeout) do |target|
          (target.is_a?(PageTarget) || target.is_a?(FrameTarget)) &&
            target.browser_context == self &&
            predicate.call(target)
        end #: PageTarget | FrameTarget
      end

      # Get all cookies in this context.
      # @rbs return: Array[Hash[String, untyped]] -- Cookies
      def cookies
        return [] if closed?

        @user_context.get_cookies.wait.map do |cookie|
          CookieUtils.bidi_to_puppeteer_cookie(cookie, return_composite_partition_key: true)
        end
      end

      # Set cookies in this context.
      # @rbs *cookies: Array[Hash[String, untyped]] -- Cookie data
      # @rbs **cookie: untyped -- Single cookie via keyword arguments
      # @rbs return: void
      def set_cookie(*cookies, **cookie)
        cookies = cookies.dup
        cookies << cookie unless cookie.empty?

        tasks = cookies.map do |raw_cookie|
          normalized_cookie = CookieUtils.normalize_cookie_input(raw_cookie)
          domain = normalized_cookie["domain"]
          if domain.nil?
            raise ArgumentError, "At least one of the url and domain needs to be specified"
          end

          bidi_cookie = {
            "domain" => domain,
            "name" => normalized_cookie["name"],
            "value" => { "type" => "string", "value" => normalized_cookie["value"] },
          }
          bidi_cookie["path"] = normalized_cookie["path"] if normalized_cookie.key?("path")
          bidi_cookie["httpOnly"] = normalized_cookie["httpOnly"] if normalized_cookie.key?("httpOnly")
          bidi_cookie["secure"] = normalized_cookie["secure"] if normalized_cookie.key?("secure")
          if normalized_cookie.key?("sameSite") && !normalized_cookie["sameSite"].nil?
            bidi_cookie["sameSite"] = CookieUtils.convert_cookies_same_site_cdp_to_bidi(
              normalized_cookie["sameSite"]
            )
          end
          expiry = CookieUtils.convert_cookies_expiry_cdp_to_bidi(normalized_cookie["expires"])
          bidi_cookie["expiry"] = expiry unless expiry.nil?
          bidi_cookie.merge!(CookieUtils.cdp_specific_cookie_properties_from_puppeteer_to_bidi(
                               normalized_cookie,
                               "sameParty",
                               "sourceScheme",
                               "priority",
                               "url"
                             ))

          partition_key = CookieUtils.convert_cookies_partition_key_from_puppeteer_to_bidi(
            normalized_cookie["partitionKey"]
          )
          -> { @user_context.set_cookie(bidi_cookie, source_origin: partition_key).wait }
        end

        AsyncUtils.await_promise_all(*tasks) unless tasks.empty?
      end

      # Delete cookies in this context.
      # @rbs *cookies: Array[Hash[String, untyped]] -- Cookies to delete
      # @rbs **cookie: untyped -- Single cookie via keyword arguments
      # @rbs return: void
      def delete_cookie(*cookies, **cookie)
        cookies = cookies.dup
        cookies << cookie unless cookie.empty?

        delete_candidates = cookies.map do |raw_cookie|
          normalized_cookie = CookieUtils.normalize_cookie_input(raw_cookie)
          normalized_cookie.merge("expires" => 1)
        end

        set_cookie(*delete_candidates)
      end

      # Delete cookies matching the provided filters.
      # @rbs *filters: Array[Hash[String, untyped]] -- Cookie filters
      # @rbs **filter: untyped -- Single cookie filter via keyword arguments
      # @rbs return: void
      def delete_matching_cookies(*filters, **filter)
        filters = filters.dup
        filters << filter unless filter.empty?

        cookies_to_delete = cookies.select do |cookie|
          filters.any? { |filter_entry| cookie_matches_filter?(cookie, filter_entry) }
        end

        delete_cookie(*cookies_to_delete)
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
            @overrides << { origin: origin, permission: permission }
          rescue StandardError
            # Ignore errors for denied permissions (some may not be supported)
            raise if permissions_set.include?(permission)
          end
        end
      end

      # Set permission states for one or more permission descriptors.
      # @rbs origin: String | Symbol -- Origin URL (must not be '*')
      # @rbs *permissions: Hash[Symbol | String, untyped] -- Permission descriptors with states
      # @rbs return: void
      def set_permission(origin, *permissions)
        if origin.to_s == '*'
          raise UnsupportedOperationError, 'Origin (*) is not supported by WebDriver BiDi'
        end

        tasks = permissions.map do |permission_entry|
          descriptor = permission_entry[:permission] || permission_entry['permission']
          state = permission_entry[:state] || permission_entry['state']
          raise ArgumentError, 'permission descriptor is required' unless descriptor.is_a?(Hash)
          raise ArgumentError, 'permission state is required' if state.nil?
          descriptor = descriptor.transform_keys(&:to_sym)

          if descriptor[:allowWithoutSanitization] || descriptor[:allow_without_sanitization]
            raise UnsupportedOperationError, 'allowWithoutSanitization is not supported by WebDriver BiDi'
          end
          if descriptor[:panTiltZoom] || descriptor[:pan_tilt_zoom]
            raise UnsupportedOperationError, 'panTiltZoom is not supported by WebDriver BiDi'
          end
          if descriptor[:userVisibleOnly] || descriptor[:user_visible_only]
            raise UnsupportedOperationError, 'userVisibleOnly is not supported by WebDriver BiDi'
          end
          raise ArgumentError, 'permission name is required' if descriptor[:name].nil?

          -> { @user_context.set_permissions(origin.to_s, { name: descriptor[:name] }, state.to_s).wait }
        end

        AsyncUtils.await_promise_all(*tasks) unless tasks.empty?
      end

      # Clear permissions set through #override_permissions.
      # @rbs return: void
      def clear_permission_overrides
        tasks = @overrides.map do |override|
          lambda do
            begin
              @user_context.set_permissions(override[:origin], { name: override[:permission] }, 'prompt').wait
            rescue StandardError => error
              debug_error(error)
            end
          end
        end

        @overrides = []
        AsyncUtils.await_promise_all(*tasks) unless tasks.empty?
      end

      # Close the browser context
      # @rbs return: void
      def close
        return if closed?

        @user_context.remove.wait
      end

      # Check if context is closed
      # @rbs return: bool -- Whether the context is closed
      def closed?
        @user_context.disposed?
      end

      private

      # @rbs frame: Frame -- Frame to get target for
      # @rbs return: FrameTarget -- Frame target
      def target_for_frame(frame)
        context_id = frame.browsing_context.id
        @frame_targets[context_id] ||= begin
          target = FrameTarget.new(frame)
          frame.browsing_context.once(:closed) do
            @frame_targets.delete(context_id)
          end
          target
        end
      end

      def cookie_matches_filter?(cookie, raw_filter)
        filter = CookieUtils.normalize_cookie_input(raw_filter)
        return false unless filter["name"] == cookie["name"]

        return true if filter.key?("domain") && filter["domain"] == cookie["domain"]
        return true if filter.key?("path") && filter["path"] == cookie["path"]

        if filter.key?("partitionKey") && cookie.key?("partitionKey")
          cookie_partition = cookie["partitionKey"]
          unless cookie_partition.is_a?(Hash)
            raise Error, "Unexpected string partition key"
          end

          filter_partition = filter["partitionKey"]
          if filter_partition.is_a?(String)
            return true if filter_partition == cookie_partition["sourceOrigin"]
          elsif filter_partition.is_a?(Hash)
            normalized_partition = CookieUtils.normalize_cookie_input(filter_partition)
            return true if normalized_partition["sourceOrigin"] == cookie_partition["sourceOrigin"]
          end
        end

        if filter.key?("url")
          url = URI.parse(filter["url"])
          url_path = url.path
          url_path = "/" if url_path.nil? || url_path.empty?
          return true if url.host == cookie["domain"] && url_path == cookie["path"]
        end

        true
      end

      def debug_error(error)
        return unless ENV['DEBUG_BIDI_COMMAND']

        warn(error.full_message)
      end
    end
  end
end

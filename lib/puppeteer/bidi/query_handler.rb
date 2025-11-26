require 'singleton'

module Puppeteer
  module Bidi
    # @api private
    class QueryHandler
      include Singleton

      QUERY_SEPARATORS = %w[= /].freeze
      BUILTIN_QUERY_HANDLERS = {
        'aria' => 'ARIAQueryHandler',
        'pierce' => 'PierceQueryHandler',
        'xpath' => 'XPathQueryHandler',
        'text' => 'TextQueryHandler'
      }.freeze

      Result = Data.define(:updated_selector, :polling, :query_handler)

      def get_query_handler_and_selector(selector)
        builtin_query_handler_entries.each do |name, handler|
          if (result = detect_handler_from_selector(name, handler, selector))
            return result
          end
        end

        default_query_handler_result(selector)
      end

      private

      def builtin_query_handler_entries
        Enumerator.new do |y|
          BUILTIN_QUERY_HANDLERS.each do |name, const_name|
            if (handler = resolve_handler_constant(const_name))
              y << [name, handler]
            end
          end
        end
      end

      def detect_handler_from_selector(name, handler, selector)
        QUERY_SEPARATORS.each do |separator|
          prefix = "#{name}#{separator}"
          next unless selector.start_with?(prefix)

          updated_selector = selector[prefix.length..]
          return Result.new(
            updated_selector: updated_selector,
            polling: (name == 'aria' ? 'raf' : 'mutation'),
            query_handler: handler,
          )
        end

        nil
      end

      def default_query_handler_result(selector)
        Result.new(
          updated_selector: selector,
          polling: 'mutation',
          query_handler: resolve_handler_constant('CSSQueryHandler'),
        )
      end

      def resolve_handler_constant(const_name)
        return const_name if const_name.is_a?(Module)

        Puppeteer::Bidi.const_get(const_name, false)
      rescue NameError
        nil
      end

      def build_query_handler_result(handler, selector, handler_name)
        {
          updated_selector: selector,
          polling: (handler_name == 'aria' ? 'raf' : 'mutation'),
          query_handler: handler,
        }
      end
    end

    class BaseQueryHandler
      def wait_for(element_or_frame, selector, visible: nil, hidden: nil, timeout: nil, polling: nil, &block)
        if element_or_frame.is_a?(Frame)
          wait_for_in_frame(element_or_frame, nil, selector, visible: visible, hidden: hidden, timeout: timeout, polling: polling, &block)
        elsif element_or_frame.is_a?(ElementHandle)
          frame = element_or_frame.frame
          root = frame.isolated_realm.adopt_handle(element_or_frame)
          wait_for_in_frame(frame, root, selector, visible: visible, hidden: hidden, timeout: timeout, polling: polling, &block)
        else
          raise ArgumentError, "Unsupported query root: #{element_or_frame.class}"
        end
      end

      private

      def wait_for_selector_script
        <<~JAVASCRIPT
        ({checkVisibility, createFunction}, query, selector, root, visibility) => {
          const querySelector = createFunction(query)
          const element = querySelector(root || document, selector);
          // Convert null to undefined for checkVisibility
          return checkVisibility(element, visibility === null ? undefined : visibility);
        }
        JAVASCRIPT
      end

      def wait_for_in_frame(frame, root, selector, visible:, hidden:, timeout:, polling:, &block)
        raise FrameDetachedError if frame.detached?

        visibility = if visible
                        true
                      elsif hidden
                        false
                      end

        resolved_polling = (visible || hidden ? 'raf' : polling)

        options = {}
        options[:polling] = resolved_polling if resolved_polling
        options[:timeout] = timeout if timeout

        begin
          handle = frame.isolated_realm.wait_for_function(
            wait_for_selector_script,
            options,
            frame.isolated_realm.puppeteer_util,
            query_one(frame.isolated_realm.puppeteer_util),
            selector,
            root,
            visibility,
            &block
          )

          return nil unless handle

          unless handle.is_a?(ElementHandle)
            begin
              handle.dispose
            rescue StandardError
              # Ignored: primitive handles may not support dispose.
            end
            return nil
          end

          frame.main_realm.transfer_handle(handle)
        rescue Puppeteer::Bidi::TimeoutError => e
          raise Puppeteer::Bidi::TimeoutError,
                "Waiting for selector `#{selector}` failed: Waiting failed: #{e.message.split(': ').last}"
        end
      end
    end

    class CSSQueryHandler < BaseQueryHandler
      def query_one(puppeteer_util)
        # (root, selector) => root.querySelector(selector)
        puppeteer_util.evaluate('({cssQuerySelector}) => cssQuerySelector.toString()')
      end
    end

    class XPathQueryHandler < BaseQueryHandler
      def query_one(puppeteer_util)
        fn = puppeteer_util.evaluate('({xpathQuerySelectorAll}) => xpathQuerySelectorAll.toString()')

        <<~JAVASCRIPT
        (root, selector) => {
          const fn = #{fn};
          for (const result of fn(root, selector, 1)) {
            return result;
          }
          return null;
        }
        JAVASCRIPT
      end
    end
  end
end

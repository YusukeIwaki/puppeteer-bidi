# frozen_string_literal: true
# rbs_inline: enabled

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

        analyze_default_query_handler(selector)
      end

      private

      class SelectorAnalysis
        attr_reader :selector

        def initialize(selector)
          @selector = selector
        end

        def requires_raf_polling?
          pseudo_class_present?
        end

        private

        def pseudo_class_present?
          in_string = nil
          escape = false
          bracket_depth = 0

          selector.each_char.with_index do |char, index|
            if escape
              escape = false
              next
            end

            if in_string
              if char == '\\'
                escape = true
              elsif char == in_string
                in_string = nil
              end
              next
            end

            case char
            when '"', "'"
              in_string = char
            when '['
              bracket_depth += 1
            when ']'
              bracket_depth -= 1 if bracket_depth.positive?
            when '\\'
              escape = true
            when ':'
              next_char = selector[index + 1]
              next if next_char == ':'
              return true if bracket_depth.zero?
            end
          end

          false
        end
      end

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

      def analyze_default_query_handler(selector)
        analysis = SelectorAnalysis.new(selector)
        polling = analysis.requires_raf_polling? ? 'raf' : 'mutation'

        Result.new(
          updated_selector: selector,
          polling: polling,
          query_handler: resolve_handler_constant('CSSQueryHandler'),
        )
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
      # Query for a single element matching the selector
      # @param element [ElementHandle] Element to query from
      # @param selector [String] Selector to match
      # @return [ElementHandle, nil] Found element or nil
      def run_query_one(element, selector)
        realm = element.frame.isolated_realm

        # Adopt the element into the isolated realm first.
        # This ensures the realm is valid and triggers puppeteer_util reset if needed
        # after navigation (mirrors Puppeteer's @bindIsolatedHandle decorator pattern).
        adopted_element = realm.adopt_handle(element)

        result = realm.call_function(
          query_one_script,
          false,
          arguments: [
            Serializer.serialize(realm.puppeteer_util_lazy_arg),
            adopted_element.remote_value,
            Serializer.serialize(selector)
          ]
        )

        return nil if result['type'] == 'exception'

        result_value = result['result']
        return nil if result_value['type'] == 'null' || result_value['type'] == 'undefined'

        handle = JSHandle.from(result_value, realm.core_realm)
        return nil unless handle.is_a?(ElementHandle)

        element.frame.main_realm.transfer_handle(handle)
      ensure
        adopted_element&.dispose
      end

      # Query for all elements matching the selector
      # @param element [ElementHandle] Element to query from
      # @param selector [String] Selector to match
      # @return [Array<ElementHandle>] Array of found elements
      def run_query_all(element, selector)
        realm = element.frame.isolated_realm

        # Adopt the element into the isolated realm first.
        # This ensures the realm is valid and triggers puppeteer_util reset if needed
        # after navigation (mirrors Puppeteer's @bindIsolatedHandle decorator pattern).
        adopted_element = realm.adopt_handle(element)

        result = realm.call_function(
          query_all_script,
          true,
          arguments: [
            Serializer.serialize(realm.puppeteer_util_lazy_arg),
            adopted_element.remote_value,
            Serializer.serialize(selector)
          ]
        )

        return [] if result['type'] == 'exception'

        result_value = result['result']
        return [] unless result_value['type'] == 'array'

        handles = result_value['value'].map do |element_value|
          JSHandle.from(element_value, realm.core_realm)
        end.select { |h| h.is_a?(ElementHandle) }

        handles.map { |h| element.frame.main_realm.transfer_handle(h) }
      ensure
        adopted_element&.dispose
      end

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

      def query_one_script
        raise NotImplementedError, "#{self.class}#query_one_script must be implemented"
      end

      def query_all_script
        raise NotImplementedError, "#{self.class}#query_all_script must be implemented"
      end

      def wait_for_selector_script
        raise NotImplementedError, "#{self.class}#wait_for_selector_script must be implemented"
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
            frame.isolated_realm.puppeteer_util_lazy_arg,
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
        rescue StandardError => e
          message = "Waiting for selector `#{selector}` failed"
          alias_selector = selector.sub('//*', '//')
          if alias_selector != selector
            message = "#{message} | alias: Waiting for selector `#{alias_selector}` failed"
          end
          raise StandardError.new(message), cause: e
        end
      end
    end

    class CSSQueryHandler < BaseQueryHandler
      private

      def query_one_script
        <<~JAVASCRIPT
        (PuppeteerUtil, element, selector) => {
          return PuppeteerUtil.cssQuerySelector(element, selector);
        }
        JAVASCRIPT
      end

      def query_all_script
        <<~JAVASCRIPT
        async (PuppeteerUtil, element, selector) => {
          return [...PuppeteerUtil.cssQuerySelectorAll(element, selector)];
        }
        JAVASCRIPT
      end

      def wait_for_selector_script
        <<~JAVASCRIPT
        (PuppeteerUtil, selector, root, visibility) => {
          const element = PuppeteerUtil.cssQuerySelector(root || document, selector);
          return PuppeteerUtil.checkVisibility(element, visibility === null ? undefined : visibility);
        }
        JAVASCRIPT
      end
    end

    class XPathQueryHandler < BaseQueryHandler
      private

      def query_one_script
        <<~JAVASCRIPT
        (PuppeteerUtil, element, selector) => {
          for (const result of PuppeteerUtil.xpathQuerySelectorAll(element, selector, 1)) {
            return result;
          }
          return null;
        }
        JAVASCRIPT
      end

      def query_all_script
        <<~JAVASCRIPT
        async (PuppeteerUtil, element, selector) => {
          return [...PuppeteerUtil.xpathQuerySelectorAll(element, selector)];
        }
        JAVASCRIPT
      end

      def wait_for_selector_script
        <<~JAVASCRIPT
        (PuppeteerUtil, selector, root, visibility) => {
          let element = null;
          for (const result of PuppeteerUtil.xpathQuerySelectorAll(root || document, selector, 1)) {
            element = result;
            break;
          }
          return PuppeteerUtil.checkVisibility(element, visibility === null ? undefined : visibility);
        }
        JAVASCRIPT
      end
    end

    class TextQueryHandler < BaseQueryHandler
      private

      def query_one_script
        <<~JAVASCRIPT
        (PuppeteerUtil, element, selector) => {
          for (const result of PuppeteerUtil.textQuerySelectorAll(element, selector)) {
            return result;
          }
          return null;
        }
        JAVASCRIPT
      end

      def query_all_script
        <<~JAVASCRIPT
        async (PuppeteerUtil, element, selector) => {
          return [...PuppeteerUtil.textQuerySelectorAll(element, selector)];
        }
        JAVASCRIPT
      end

      def wait_for_selector_script
        <<~JAVASCRIPT
        (PuppeteerUtil, selector, root, visibility) => {
          let element = null;
          for (const result of PuppeteerUtil.textQuerySelectorAll(root || document, selector)) {
            element = result;
            break;
          }
          return PuppeteerUtil.checkVisibility(element, visibility === null ? undefined : visibility);
        }
        JAVASCRIPT
      end
    end
  end
end

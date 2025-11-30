require 'json'
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
          @p_selector_json = nil
        end

        def requires_p_selector?
          deep_combinator? || custom_pseudo_element?
        end

        def pure_css?
          !requires_p_selector?
        end

        def requires_raf_polling?
          pseudo_class_present?
        end

        def has_aria_pseudo_element?
          selector.include?('::-p-aria')
        end

        def p_selector_json
          return @p_selector_json if @p_selector_json
          return unless deep_combinator?

          @p_selector_json = DeepSelectorParser.new(selector).parse
        rescue DeepSelectorParser::ParseError
          @p_selector_json = nil
        end

        private

        def deep_combinator?
          selector.include?('>>>>') || selector.include?('>>>')
        end

        def custom_pseudo_element?
          selector.include?('::-p-')
        end

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

      class DeepSelectorParser
        class ParseError < StandardError; end

        def initialize(selector)
          @selector = selector
        end

        def parse
          selectors = []
          current_complex = []
          current_compound = []
          current_complex << current_compound
          selectors << current_complex

          buffer = +''
          in_string = nil
          escape = false
          bracket_depth = 0
          paren_depth = 0

          i = 0
          while i < @selector.length
            char = @selector[i]

            if escape
              buffer << char
              escape = false
              i += 1
              next
            end

            if in_string
              buffer << char
              if char == '\\'
                escape = true
              elsif char == in_string
                in_string = nil
              end
              i += 1
              next
            end

            case char
            when '"', "'"
              buffer << char
              in_string = char
              i += 1
              next
            when '\\'
              buffer << char
              escape = true
              i += 1
              next
            when '['
              bracket_depth += 1
              buffer << char
              i += 1
              next
            when ']'
              bracket_depth -= 1 if bracket_depth.positive?
              buffer << char
              i += 1
              next
            when '('
              paren_depth += 1
              buffer << char
              i += 1
              next
            when ')'
              paren_depth -= 1 if paren_depth.positive?
              buffer << char
              i += 1
              next
            end

            if bracket_depth.zero? && paren_depth.zero?
              if @selector.start_with?('>>>>', i)
                push_compound!(current_compound, buffer)
                raise ParseError if current_compound.empty?
                current_complex << '>>>>'
                current_compound = []
                current_complex << current_compound
                i += 4
                next
              elsif @selector.start_with?('>>>', i)
                push_compound!(current_compound, buffer)
                raise ParseError if current_compound.empty?
                current_complex << '>>>'
                current_compound = []
                current_complex << current_compound
                i += 3
                next
              elsif char == ','
                push_compound!(current_compound, buffer)
                raise ParseError if current_complex.flatten.empty?
                current_complex = []
                current_compound = []
                current_complex << current_compound
                selectors << current_complex
                i += 1
                next
              end
            end

            buffer << char
            i += 1
          end

          push_compound!(current_compound, buffer)
          validate!(selectors)

          JSON.generate(selectors)
        end

        private

        def push_compound!(compound, buffer)
          text = buffer.strip
          compound << text unless text.empty?
          buffer.clear
        end

        def validate!(selectors)
          selectors.each do |complex|
            complex.each do |part|
              if part.is_a?(Array)
                raise ParseError if part.empty?
              end
            end
          end
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
        if (p_selector = analysis.p_selector_json)
          polling = analysis.has_aria_pseudo_element? ? 'raf' : 'mutation'
          return Result.new(
            updated_selector: p_selector,
            polling: polling,
            query_handler: resolve_handler_constant('PQueryHandler'),
          )
        end

        if analysis.pure_css?
          polling = analysis.requires_raf_polling? ? 'raf' : 'mutation'
          return Result.new(
            updated_selector: selector,
            polling: polling,
            query_handler: resolve_handler_constant('CSSQueryHandler'),
          )
        end

        default_query_handler_result(selector)
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
            frame.isolated_realm.puppeteer_util_lazy_arg,
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

    class PQueryHandler < BaseQueryHandler
      def query_one(puppeteer_util)
        puppeteer_util.evaluate('({pQuerySelector}) => pQuerySelector.toString()')
      end

      def wait_for_selector_script
        <<~JAVASCRIPT
        ({checkVisibility, pQuerySelector}, selector, root, visibility) => {
          const element = pQuerySelector(root || document, selector);
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
              # Ignore dispose errors.
            end
            return nil
          end

          frame.main_realm.transfer_handle(handle)
        rescue Puppeteer::Bidi::TimeoutError => e
          raise Puppeteer::Bidi::TimeoutError,
                "Waiting for selector `#{selector}` failed: Waiting failed: #{e.message.split(': ').last}"
        rescue StandardError => e
          raise StandardError.new("Waiting for selector `#{selector}` failed"), cause: e
        end
      end
    end
  end
end

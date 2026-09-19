# frozen_string_literal: true
# rbs_inline: enabled

module Puppeteer
  module Bidi
    # Parser for Puppeteer P-selectors (`>>>`, `>>>>`, `-p` pseudo-elements),
    # ported from upstream `PSelectorParser.ts` on top of a Ruby port of the
    # `parsel-js` tokenizer subset it relies on.
    module PSelectorParser
      # A flat lexical token. Only combinators and commas are normalized;
      # every other token keeps its raw CSS text in `content`.
      Token = Struct.new(:type, :content, :name, :argument, :pos, keyword_init: true)

      DESCENDENT_COMBINATOR = ">>>"
      CHILD_COMBINATOR = ">>>>"

      P_PSEUDO_PREFIX = "-p-"
      PSEUDO_ELEMENT_CSS = "pierce"
      PSEUDO_ELEMENT_SHADOW_TEXT = "pierceShadowText"

      ESCAPE_PLACEHOLDER = ""
      STRING_PLACEHOLDER = ""
      PAREN_PLACEHOLDER = "¶"

      # Grammar order mirrors parsel-js: attribute, id, class, comma,
      # combinator (with the upstream `>>>>?` override), pseudo-element,
      # pseudo-class, universal, type, nesting.
      WORD = "\\-\\w\\u0080-\\u{10FFFF}"
      GRAMMAR = [
        ["attribute",
         /\[\s*(?:(?<namespace>\*|[#{WORD}]*)\\|)?(?<name>[#{WORD}]+)\s*(?:(?<operator>\W?=)\s*(?<value>.+?)\s*(\s(?<caseSensitive>[iIsS]))?\s*)?\]/u],
        ["id", /#(?<name>[#{WORD}]+)/u],
        ["class", /\.(?<name>[#{WORD}]+)/u],
        ["comma", /\s*,\s*/],
        ["combinator", /\s*(>>>>?|[\s>+~])\s*/],
        ["pseudo-element", /::(?<name>[#{WORD}]+)(?:\((?<argument>#{Regexp.escape(PAREN_PLACEHOLDER)}*)\))?/u],
        ["pseudo-class", /:(?<name>[#{WORD}]+)(?:\((?<argument>#{Regexp.escape(PAREN_PLACEHOLDER)}*)\))?/u],
        ["universal", /(?:(?<namespace>\*|[#{WORD}]*)\\|)?\*/u],
        ["type", /(?:(?<namespace>\*|[#{WORD}]*)\\|)?(?<name>[#{WORD}]+)/u],
        ["nesting", /&/],
      ].freeze

      TRIM_TOKEN_TYPES = %w[combinator comma].freeze

      class << self
        # Tokenize a selector, mirroring parsel-js `tokenize`.
        # @rbs selector: String -- Selector source
        # @rbs return: Array[Token] -- Flat tokens
        def tokenize(selector)
          selector = selector.strip
          return [] if selector.empty?

          replacements = []
          selector = replace_with_placeholders(selector, /\\./, replacements) do |value, _|
            ESCAPE_PLACEHOLDER * value.length
          end
          selector = replace_with_placeholders(selector, /(['"])([^\\\n]*?)\1/, replacements) do |_, match|
            quote = match[1]
            content = match[2]
            "#{quote}#{STRING_PLACEHOLDER * content.length}#{quote}"
          end
          selector = replace_parens_with_placeholders(selector, replacements)

          tokens = tokenize_by(selector)

          replacements.reverse_each do |replacement|
            tokens.each do |token|
              offset = replacement[:offset]
              value = replacement[:value]
              next unless token.pos[0] <= offset && offset + value.length <= token.pos[1]

              token_offset = offset - token.pos[0]
              content = token.content
              token.content =
                content[0...token_offset] + value + content[(token_offset + value.length)..]
            end
          end

          tokens.each do |token|
            pattern = argument_pattern_for(token.type)
            raise "Unknown token type: #{token.type}" unless pattern

            match = pattern.match(token.content)
            raise "Unable to parse content for #{token.type}: #{token.content}" unless match

            token.name = match[:name] if match.names.include?("name")
            token.argument = match[:argument] if match.names.include?("argument")
          end

          tokens
        end

        # Reconstitute CSS text from flat tokens, mirroring parsel-js `stringify`.
        # @rbs tokens: Array[Token] -- Flat tokens
        # @rbs return: String -- CSS text
        def stringify(tokens)
          tokens.map(&:content).join("")
        end

        # Parse a P-selector, mirroring upstream `parsePSelectors`.
        # @rbs selector: String -- Selector source
        # @rbs return: Array[untyped] -- Parsed selectors, pure CSS flag, pseudo-class flag, aria flag
        def parse_p_selectors(selector)
          tokens = tokenize(selector)

          is_pure_css = true
          has_pseudo_classes = false
          has_aria = false
          return [[], is_pure_css, has_pseudo_classes, false] if tokens.empty?

          compound_selector = []
          complex_selector = [compound_selector]
          selectors = [complex_selector]
          storage = []

          tokens.each do |token|
            case token.type
            when "combinator"
              if token.content == CHILD_COMBINATOR || token.content == DESCENDENT_COMBINATOR
                is_pure_css = false
                if storage.length > 0
                  compound_selector << stringify(storage)
                  storage.clear
                end
                compound_selector = []
                complex_selector << PCombinator.for_content(token.content)
                complex_selector << compound_selector
                next
              end
              # Any other combinator breaks out of the switch and is kept as CSS text.
            when "pseudo-element"
              unless token.name.start_with?(P_PSEUDO_PREFIX)
                # Non-p pseudo-elements such as `::before` stay plain CSS text.
                storage << token
                next
              end
              is_pure_css = false
              if storage.length > 0
                compound_selector << stringify(storage)
                storage.clear
              end
              name = token.name[P_PSEUDO_PREFIX.length..]
              has_aria = true if name == "aria"
              compound_selector << { name: name, value: unquote(token.argument || "") }
              next
            when "pseudo-class"
              has_pseudo_classes = true
              storage << token
              next
            when "comma"
              if storage.length > 0
                compound_selector << stringify(storage)
                storage.clear
              end
              compound_selector = []
              complex_selector = [compound_selector]
              selectors << complex_selector
              next
            else
              storage << token
              next
            end
            storage << token
          end

          compound_selector << stringify(storage) if storage.length > 0

          [selectors, is_pure_css, has_pseudo_classes, has_aria]
        end

        # Unquote a `-p` pseudo-element argument, mirroring upstream `unquote`.
        # @rbs text: String -- Raw argument
        # @rbs return: String -- Unquoted argument
        def unquote(text)
          return text if text.length <= 1

          if (text[0] == '"' || text[0] == "'") && text.end_with?(text[0])
            text = text[1...-1]
          end
          text.gsub(/\\[\s\S]/) { |match| match[1] }
        end

        private

        # @rbs text: String -- Selector being scanned
        # @rbs return: Array[Token] -- Flat tokens
        def tokenize_by(text)
          return [] if text.empty?

          tokens = [text] #: Array[String | Token]
          GRAMMAR.each do |type, pattern|
            index = 0
            while index < tokens.length
              token = tokens[index]
              unless token.is_a?(String)
                index += 1
                next
              end
              match = pattern.match(token)
              unless match
                index += 1
                next
              end
              content = match[0]
              before = token[0...match.begin(0)]
              after = token[(match.begin(0) + content.length)..]
              replacement = []
              replacement << before unless before.empty?
              groups = {}
              match.names.each { |name| groups[name] = match[name] }
              replacement << Token.new(
                type: type,
                content: content,
                name: groups["name"],
                argument: groups["argument"],
                pos: nil
              )
              replacement << after unless after.nil? || after.empty?
              tokens[index, 1] = replacement
              index += replacement.length - 1
              index += 1
            end
          end

          offset = 0
          result = [] #: Array[Token]
          tokens.each do |token|
            raise "Unexpected sequence #{token} found" if token.is_a?(String)

            token.pos = [offset, offset + token.content.length]
            offset += token.content.length
            token.content = token.content.strip.empty? ? " " : token.content.strip if TRIM_TOKEN_TYPES.include?(token.type)
            result << token
          end
          result
        end

        # @rbs type: String -- Token type
        # @rbs return: Regexp? -- Pattern used to refresh token groups
        def argument_pattern_for(type)
          _, pattern = GRAMMAR.find { |entry_type, _| entry_type == type }
          return nil unless pattern

          if type == "pseudo-element" || type == "pseudo-class"
            # Mirror parsel-js `getArgumentPatternByType`: only the argument
            # group widens from placeholders to any text.
            Regexp.new(
              pattern.source.sub("(?<argument>#{PAREN_PLACEHOLDER}*)", "(?<argument>.*)"),
              pattern.options
            )
          else
            pattern
          end
        end

        # @rbs selector: String -- Working selector text
        # @rbs pattern: Regexp -- Placeholder pattern
        # @rbs replacements: Array[Hash[Symbol, untyped]] -- Collected replacements
        # @rbs &block: (String, MatchData?) -> String -- Placeholder replacement
        # @rbs return: String -- Selector with placeholders
        def replace_with_placeholders(selector, pattern, replacements)
          selector.gsub(pattern) do
            value = Regexp.last_match[0]
            offset = Regexp.last_match.begin(0)
            replacements << { value: value, offset: offset }
            yield(value, Regexp.last_match)
          end
        end

        # @rbs selector: String -- Working selector text
        # @rbs replacements: Array[Hash[Symbol, untyped]] -- Collected replacements
        # @rbs return: String -- Selector with paren placeholders
        def replace_parens_with_placeholders(selector, replacements)
          pos = 0
          while (offset = selector.index("(", pos))
            value = gobble_parens(selector, offset)
            replacements << { value: value, offset: offset }
            selector = "#{selector[0...offset]}(#{PAREN_PLACEHOLDER * (value.length - 2)})#{selector[(offset + value.length)..]}"
            pos = offset + value.length
          end
          selector
        end

        # @rbs text: String -- Selector text
        # @rbs offset: Integer -- Index of the opening paren
        # @rbs return: String -- Balanced paren group
        def gobble_parens(text, offset)
          nesting = 0
          result = +""
          while offset < text.length
            char = text[offset]
            nesting += 1 if char == "("
            nesting -= 1 if char == ")"
            result += char
            return result if nesting == 0

            offset += 1
          end
          result
        end
      end

      # Pierce combinator markers, mirroring upstream `PCombinator`.
      module PCombinator
        Descendent = ">>>"
        Child = ">>>>"

        # @rbs content: String -- Combinator text
        # @rbs return: String -- Combinator marker
        def self.for_content(content)
          content == Child ? Child : Descendent
        end
      end
    end
  end
end

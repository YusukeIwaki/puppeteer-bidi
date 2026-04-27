# frozen_string_literal: true

# Matchers that mirror small RSpec semantics not covered by Smartest's
# built-ins, so direct ports of existing specs do not need to rewrite assertion
# style.
module RSpecCompatMatchers
  # Like RSpec's `include`:
  #   - multi-arg form  : `include('a', 'b')` requires every arg to be present.
  #   - hash subset form: `include(key: value)` checks the hash contains all
  #     given key/value pairs.
  def include_all(*expected_items)
    IncludeAllMatcher.new(expected_items)
  end

  # `expect(a).to be_equal(b)` corresponds to RSpec's `equal` (object identity).
  def be_equal(expected)
    BeEqualMatcher.new(expected)
  end

  class IncludeAllMatcher
    def initialize(expected_items)
      @expected_items = expected_items
    end

    def matches?(actual)
      @actual = actual
      @missing = @expected_items.reject { |item| matches_item?(actual, item) }
      @missing.empty?
    end

    def failure_message
      "expected #{@actual.inspect} to include #{@missing.map(&:inspect).join(', ')}"
    end

    def negated_failure_message
      "expected #{@actual.inspect} not to include #{@expected_items.map(&:inspect).join(', ')}"
    end

    def description
      "include #{@expected_items.map(&:inspect).join(', ')}"
    end

    private

    def matches_item?(actual, item)
      if actual.is_a?(Hash) && item.is_a?(Hash)
        item.all? { |key, value| actual.key?(key) && actual[key] == value }
      else
        actual.include?(item)
      end
    rescue NoMethodError
      false
    end
  end

  class BeEqualMatcher
    def initialize(expected)
      @expected = expected
    end

    def matches?(actual)
      @actual = actual
      actual.equal?(@expected)
    end

    def failure_message
      "expected #{@actual.inspect} to be the same object as #{@expected.inspect}"
    end

    def negated_failure_message
      "expected #{@actual.inspect} not to be the same object as #{@expected.inspect}"
    end

    def description
      "be equal #{@expected.inspect}"
    end
  end
end

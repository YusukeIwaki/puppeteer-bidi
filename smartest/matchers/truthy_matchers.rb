# frozen_string_literal: true

# Adds RSpec-compatible truthiness matchers to Smartest.
#
# - `expect(x).to be_truthy`  : passes when x is neither nil nor false.
# - `expect(x).to be_falsey`  : passes when x is nil or false.
module TruthyMatchers
  def be_truthy
    BeTruthyMatcher.new
  end

  def be_falsey
    BeFalseyMatcher.new
  end
  alias be_falsy be_falsey

  class BeTruthyMatcher
    def matches?(actual)
      @actual = actual
      !!actual
    end

    def failure_message
      "expected #{@actual.inspect} to be truthy"
    end

    def negated_failure_message
      "expected #{@actual.inspect} not to be truthy"
    end

    def description
      "be truthy"
    end
  end

  class BeFalseyMatcher
    def matches?(actual)
      @actual = actual
      !actual
    end

    def failure_message
      "expected #{@actual.inspect} to be falsey"
    end

    def negated_failure_message
      "expected #{@actual.inspect} not to be falsey"
    end

    def description
      "be falsey"
    end
  end
end

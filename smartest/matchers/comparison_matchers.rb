# frozen_string_literal: true

# Adds numeric / ordering matchers similar to RSpec's `be > x` family.
#
#   expect(x).to be_greater_than(5)
#   expect(x).to be_less_than(10)
#   expect(x).to be_greater_than_or_equal_to(5)
#   expect(x).to be_less_than_or_equal_to(10)
#   expect(x).to be_within(0.1).of(target)
module ComparisonMatchers
  def be_greater_than(expected)
    ComparisonMatcher.new(:>, expected)
  end

  def be_less_than(expected)
    ComparisonMatcher.new(:<, expected)
  end

  def be_greater_than_or_equal_to(expected)
    ComparisonMatcher.new(:>=, expected)
  end

  def be_less_than_or_equal_to(expected)
    ComparisonMatcher.new(:<=, expected)
  end

  def be_within(delta)
    BeWithinMatcher.new(delta)
  end

  class ComparisonMatcher
    OPERATOR_NAMES = {
      :> => "greater than",
      :< => "less than",
      :>= => "greater than or equal to",
      :<= => "less than or equal to"
    }.freeze

    def initialize(operator, expected)
      @operator = operator
      @expected = expected
    end

    def matches?(actual)
      @actual = actual
      actual.public_send(@operator, @expected)
    end

    def failure_message
      "expected #{@actual.inspect} to be #{OPERATOR_NAMES[@operator]} #{@expected.inspect}"
    end

    def negated_failure_message
      "expected #{@actual.inspect} not to be #{OPERATOR_NAMES[@operator]} #{@expected.inspect}"
    end

    def description
      "be #{OPERATOR_NAMES[@operator]} #{@expected.inspect}"
    end
  end

  class BeWithinMatcher
    def initialize(delta)
      @delta = delta
    end

    def of(expected)
      @expected = expected
      self
    end

    def matches?(actual)
      @actual = actual
      raise ArgumentError, "be_within(#{@delta}) requires `.of(value)`" unless defined?(@expected)

      (actual - @expected).abs <= @delta
    end

    def failure_message
      "expected #{@actual.inspect} to be within #{@delta} of #{@expected.inspect}"
    end

    def negated_failure_message
      "expected #{@actual.inspect} not to be within #{@delta} of #{@expected.inspect}"
    end

    def description
      "be within #{@delta} of #{@expected.inspect}"
    end
  end
end

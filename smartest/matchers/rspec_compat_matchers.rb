# frozen_string_literal: true

module RSpecCompatMatchers
  UNSET = Object.new.freeze

  class BaseMatcher
    def inspect_value(value)
      value.inspect
    end

    def or(other)
      OrMatcher.new(self, other)
    end
  end

  class OrMatcher < BaseMatcher
    def initialize(left, right)
      @left = left
      @right = right
    end

    def matches?(actual)
      @actual = actual
      @left.matches?(actual) || @right.matches?(actual)
    end

    def failure_message
      "expected #{inspect_value(@actual)} to match #{@left.failure_message} or #{@right.failure_message}"
    end

    def negated_failure_message
      "expected #{inspect_value(@actual)} not to match either matcher"
    end
  end

  class IdentityMatcher < BaseMatcher
    def initialize(expected)
      @expected = expected
    end

    def matches?(actual)
      @actual = actual
      actual.equal?(@expected)
    end

    def failure_message
      "expected #{inspect_value(@actual)} to be #{inspect_value(@expected)}"
    end

    def negated_failure_message
      "expected #{inspect_value(@actual)} not to be #{inspect_value(@expected)}"
    end
  end

  class KindOfMatcher < BaseMatcher
    def initialize(expected_class)
      @expected_class = expected_class
    end

    def matches?(actual)
      @actual = actual
      actual.is_a?(@expected_class)
    end

    def failure_message
      "expected #{inspect_value(@actual)} to be a #{@expected_class}"
    end

    def negated_failure_message
      "expected #{inspect_value(@actual)} not to be a #{@expected_class}"
    end
  end

  class TruthyMatcher < BaseMatcher
    def matches?(actual)
      @actual = actual
      !!actual
    end

    def failure_message
      "expected #{inspect_value(@actual)} to be truthy"
    end

    def negated_failure_message
      "expected #{inspect_value(@actual)} not to be truthy"
    end
  end

  class FalseyMatcher < BaseMatcher
    def matches?(actual)
      @actual = actual
      !actual
    end

    def failure_message
      "expected #{inspect_value(@actual)} to be falsey"
    end

    def negated_failure_message
      "expected #{inspect_value(@actual)} not to be falsey"
    end
  end

  class MatchMatcher < BaseMatcher
    def initialize(pattern)
      @pattern = pattern
    end

    def matches?(actual)
      @actual = actual
      @pattern === actual || (actual.respond_to?(:match?) && actual.match?(@pattern))
    end

    def failure_message
      "expected #{inspect_value(@actual)} to match #{@pattern.inspect}"
    end

    def negated_failure_message
      "expected #{inspect_value(@actual)} not to match #{@pattern.inspect}"
    end
  end

  class IncludeMatcher < BaseMatcher
    def initialize(expected)
      @expected = expected
    end

    def matches?(actual)
      @actual = actual
      @expected.all? { |expected| includes?(actual, expected) }
    end

    def failure_message
      "expected #{inspect_value(@actual)} to include #{@expected.map(&:inspect).join(", ")}"
    end

    def negated_failure_message
      "expected #{inspect_value(@actual)} not to include #{@expected.map(&:inspect).join(", ")}"
    end

    private

    def includes?(actual, expected)
      if actual.is_a?(Hash) && expected.is_a?(Hash)
        expected.all? { |key, value| actual.key?(key) && actual[key] == value }
      else
        actual.include?(expected)
      end
    rescue NoMethodError
      false
    end
  end

  class EqualMatcher < BaseMatcher
    def initialize(expected)
      @expected = expected
    end

    def matches?(actual)
      @actual = actual
      actual.equal?(@expected)
    end

    def failure_message
      "expected #{inspect_value(@actual)} to equal #{inspect_value(@expected)}"
    end

    def negated_failure_message
      "expected #{inspect_value(@actual)} not to equal #{inspect_value(@expected)}"
    end
  end

  class StartWithMatcher < BaseMatcher
    def initialize(expected)
      @expected = expected
    end

    def matches?(actual)
      @actual = actual
      actual.respond_to?(:start_with?) && actual.start_with?(*@expected)
    end

    def failure_message
      "expected #{inspect_value(@actual)} to start with #{@expected.map(&:inspect).join(", ")}"
    end

    def negated_failure_message
      "expected #{inspect_value(@actual)} not to start with #{@expected.map(&:inspect).join(", ")}"
    end
  end

  class EndWithMatcher < BaseMatcher
    def initialize(expected)
      @expected = expected
    end

    def matches?(actual)
      @actual = actual
      actual.respond_to?(:end_with?) && actual.end_with?(*@expected)
    end

    def failure_message
      "expected #{inspect_value(@actual)} to end with #{@expected.map(&:inspect).join(", ")}"
    end

    def negated_failure_message
      "expected #{inspect_value(@actual)} not to end with #{@expected.map(&:inspect).join(", ")}"
    end
  end

  class HaveKeyMatcher < BaseMatcher
    def initialize(expected_key)
      @expected_key = expected_key
    end

    def matches?(actual)
      @actual = actual
      actual.respond_to?(:key?) && actual.key?(@expected_key)
    end

    def failure_message
      "expected #{inspect_value(@actual)} to have key #{inspect_value(@expected_key)}"
    end

    def negated_failure_message
      "expected #{inspect_value(@actual)} not to have key #{inspect_value(@expected_key)}"
    end
  end

  class MatchArrayMatcher < BaseMatcher
    def initialize(expected)
      @expected = expected
    end

    def matches?(actual)
      @actual = actual
      actual.to_a.sort == @expected.to_a.sort
    rescue NoMethodError, ArgumentError
      false
    end

    def failure_message
      "expected #{inspect_value(@actual)} to match array #{inspect_value(@expected)}"
    end

    def negated_failure_message
      "expected #{inspect_value(@actual)} not to match array #{inspect_value(@expected)}"
    end
  end

  class ComparisonBuilder
    def >(expected)
      ComparisonMatcher.new(:>, expected)
    end

    def >=(expected)
      ComparisonMatcher.new(:>=, expected)
    end

    def <(expected)
      ComparisonMatcher.new(:<, expected)
    end

    def <=(expected)
      ComparisonMatcher.new(:<=, expected)
    end
  end

  class ComparisonMatcher < BaseMatcher
    def initialize(operator, expected)
      @operator = operator
      @expected = expected
    end

    def matches?(actual)
      @actual = actual
      actual.public_send(@operator, @expected)
    end

    def failure_message
      "expected #{inspect_value(@actual)} to be #{@operator} #{inspect_value(@expected)}"
    end

    def negated_failure_message
      "expected #{inspect_value(@actual)} not to be #{@operator} #{inspect_value(@expected)}"
    end
  end

  class RaiseErrorMatcher < BaseMatcher
    attr_reader :actual_error

    def initialize(expected_error = StandardError, expected_message = nil)
      @expected_error, @expected_message = normalize_expectation(expected_error, expected_message)
      @actual_error = nil
      @callable = true
    end

    def matches?(actual)
      @actual_error = nil
      @callable = actual.respond_to?(:call)
      return false unless @callable

      actual.call
      false
    rescue Exception => error
      raise if Smartest.fatal_exception?(error)

      @actual_error = error
      error_matches?(error)
    end

    def does_not_match?(actual)
      @actual_error = nil
      @callable = actual.respond_to?(:call)
      return false unless @callable

      actual.call
      true
    rescue Exception => error
      raise if Smartest.fatal_exception?(error)

      @actual_error = error
      false
    end

    def failure_message
      return "expected a block to raise #{@expected_error}" unless @callable
      return "expected block to raise #{@expected_error}, but nothing was raised" unless @actual_error

      "expected block to raise #{@expected_error}, but raised #{@actual_error.class}: #{@actual_error.message}"
    end

    def negated_failure_message
      return "expected a block not to raise #{@expected_error}" unless @callable

      "expected block not to raise #{@expected_error}, but raised #{@actual_error.class}: #{@actual_error.message}"
    end

    private

    def normalize_expectation(expected_error, expected_message)
      case expected_error
      when Class
        [expected_error, expected_message]
      when String, Regexp
        [StandardError, expected_error]
      else
        [expected_error, expected_message]
      end
    end

    def error_matches?(error)
      error.is_a?(@expected_error) && message_matches?(error.message)
    end

    def message_matches?(message)
      return true if @expected_message.nil?
      return message.match?(@expected_message) if @expected_message.is_a?(Regexp)

      message == @expected_message
    end
  end

  def be(expected = UNSET)
    return ComparisonBuilder.new if expected.equal?(UNSET)

    IdentityMatcher.new(expected)
  end

  def be_a(expected_class)
    KindOfMatcher.new(expected_class)
  end

  alias be_an be_a

  def be_truthy
    TruthyMatcher.new
  end

  def be_falsey
    FalseyMatcher.new
  end

  alias be_falsy be_falsey

  def match(pattern)
    MatchMatcher.new(pattern)
  end

  def include(*expected)
    IncludeMatcher.new(expected)
  end

  def equal(expected)
    EqualMatcher.new(expected)
  end

  def start_with(*expected)
    StartWithMatcher.new(expected)
  end

  def end_with(*expected)
    EndWithMatcher.new(expected)
  end

  def have_key(expected_key)
    HaveKeyMatcher.new(expected_key)
  end

  def match_array(expected)
    MatchArrayMatcher.new(expected)
  end

  def raise_error(expected_error = StandardError, expected_message = nil)
    RaiseErrorMatcher.new(expected_error, expected_message)
  end
end

module SmartestExpectationTargetCompat
  def to(matcher, message = nil)
    return self if matcher.matches?(@actual).tap { |matched| yield(matcher.actual_error) if matched && block_given? && matcher.respond_to?(:actual_error) }

    raise Smartest::AssertionFailed, message || matcher.failure_message
  end

  def not_to(matcher, message = nil)
    if matcher.respond_to?(:does_not_match?)
      return self if matcher.does_not_match?(@actual)

      raise Smartest::AssertionFailed, message || matcher.negated_failure_message
    end

    return self unless matcher.matches?(@actual)

    raise Smartest::AssertionFailed, message || matcher.negated_failure_message
  end
end

Smartest::ExpectationTarget.prepend(SmartestExpectationTargetCompat)

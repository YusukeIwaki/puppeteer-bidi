# frozen_string_literal: true

module PredicateMatcher
  class Matcher
    def initialize(predicate_name, args)
      @predicate_name = predicate_name
      @args = args
    end

    def matches?(actual)
      @actual = actual
      actual.public_send(:"#{@predicate_name}?", *@args)
    rescue NoMethodError
      false
    end

    def failure_message
      "expected #{@actual.inspect} to be #{@predicate_name.tr("_", " ")}"
    end

    def negated_failure_message
      "expected #{@actual.inspect} not to be #{@predicate_name.tr("_", " ")}"
    end
  end

  def method_missing(method_name, *args)
    method_text = method_name.to_s
    return Matcher.new(method_text.delete_prefix("be_"), args) if method_text.start_with?("be_")

    super
  end

  def respond_to_missing?(method_name, include_private = false)
    method_name.to_s.start_with?("be_") || super
  end
end

# frozen_string_literal: true

module SmartestHelpers
  include GoldenComparator
  include CookieHelpers

  def headless_mode?
    !%w[0 false].include?(ENV["HEADLESS"])
  end

  def linux?
    RUBY_PLATFORM.include?("linux")
  end
end

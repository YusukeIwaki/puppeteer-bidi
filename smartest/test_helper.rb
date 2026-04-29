# frozen_string_literal: true

require "timeout"

require "smartest/autorun"
require "puppeteer/bidi"

require_relative "support/test_server"
require_relative "support/golden_comparator"
require_relative "support/cookie_helpers"

module TestShortInspect
  def inspect
    "#<#{self.class} 0x#{object_id.to_s(16)}>"
  end
end

Puppeteer::Bidi::BrowserContext.prepend(TestShortInspect)
Puppeteer::Bidi::Page.prepend(TestShortInspect)
Puppeteer::Bidi::ElementHandle.prepend(TestShortInspect)
Puppeteer::Bidi::HTTPRequest.prepend(TestShortInspect)

Dir[File.join(__dir__, "fixtures", "**", "*.rb")].sort.each do |fixture_file|
  require fixture_file
end

Dir[File.join(__dir__, "matchers", "**", "*.rb")].sort.each do |matcher_file|
  require matcher_file
end

module BrowserTestHelpers
  include CookieHelpers
  include GoldenComparator

  def headless_mode?
    !%w[0 false].include?(ENV["HEADLESS"])
  end

  def linux?
    RUBY_PLATFORM.include?("linux")
  end

  def asset_path(relative_path)
    File.expand_path(File.join("assets", relative_path), __dir__)
  end

  def with_browser(**options)
    options[:headless] = headless_mode?
    Puppeteer::Bidi.launch(**options) do |browser|
      yield(browser)
    end
  end
end

around_suite do |suite|
  use_fixture BrowserFixture
  use_fixture ServerFixture
  use_matcher PredicateMatcher

  around_test do |test|
    use_helper BrowserTestHelpers

    Timeout.timeout(15) do
      test.run
    end
  end

  puts "\n[Test Suite] Starting..."
  result = nil
  Sync do |parent|
    result = suite.run
    parent.reactor.print_hierarchy if ENV["DEBUG_ASYNC_HIERARCHY"]
  end
  result
end

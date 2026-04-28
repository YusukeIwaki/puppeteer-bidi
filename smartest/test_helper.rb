# frozen_string_literal: true

require "smartest/autorun"
require "async"
require "timeout"

require "puppeteer/bidi"

# Load smartest fixtures, matchers, and support files.
Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |file| require file }
Dir[File.join(__dir__, "fixtures", "**", "*.rb")].sort.each { |file| require file }
Dir[File.join(__dir__, "matchers", "**", "*.rb")].sort.each { |file| require file }

# Compact inspect for objects that show up in assertion failure messages.
module SmartestShortInspect
  def inspect
    "#<#{self.class} 0x#{object_id.to_s(16)}>"
  end
end

Puppeteer::Bidi::BrowserContext.prepend(SmartestShortInspect)
Puppeteer::Bidi::Page.prepend(SmartestShortInspect)
Puppeteer::Bidi::ElementHandle.prepend(SmartestShortInspect)
Puppeteer::Bidi::HTTPRequest.prepend(SmartestShortInspect)

around_suite do |suite|
  use_fixture BrowserFixture
  use_fixture ServerFixture

  use_matcher PredicateMatcher
  use_matcher TruthyMatchers
  use_matcher ComparisonMatchers
  use_matcher RSpecCompatMatchers

  around_test do |test|
    use_helper SmartestHelpers
    Sync do
      Timeout.timeout(15) do
        test.run
      end
    end
  end

  Sync do
    suite.run
  end
end

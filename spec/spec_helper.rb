# frozen_string_literal: true

require "puppeteer/bidi"

module TestShortInspect
  def inspect
    "#<#{self.class} 0x#{object_id.to_s(16)}>"
  end
end

Puppeteer::Bidi::BrowserContext.prepend(TestShortInspect)
Puppeteer::Bidi::Page.prepend(TestShortInspect)
Puppeteer::Bidi::ElementHandle.prepend(TestShortInspect)
Puppeteer::Bidi::HTTPRequest.prepend(TestShortInspect)

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # https://github.com/rspec/rspec-core/blob/v3.13.2/lib/rspec/core/configuration.rb#L2091-L2103
  rspec_around_suite_patch = Module.new do
    def with_suite_hooks(...)
      puts "\n[Test Suite] Starting..."
      result = nil
      Sync do |parent|
        result = super(...)
        parent.reactor.print_hierarchy if ENV["DEBUG_ASYNC_HIERARCHY"]
      end
      result
    end
  end
  RSpec::Core::Configuration.prepend(rspec_around_suite_patch)
end

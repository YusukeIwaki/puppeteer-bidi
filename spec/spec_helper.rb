# frozen_string_literal: true

require "puppeteer/bidi"
require 'timeout'

# Load support files
require_relative 'support/test_server'
require_relative 'support/golden_comparator'
require_relative 'support/cookie_helpers'

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

  # spec/integration/* should be run as type=:integration
  config.define_derived_metadata(file_path: %r{spec/integration/}) do |metadata|
    metadata[:type] = :integration
  end

  # https://github.com/rspec/rspec-core/blob/v3.13.2/lib/rspec/core/configuration.rb#L2091-L2103
  rspec_around_suite_patch = Module.new do
    def with_suite_hooks(...)
      puts "\n[Test Suite] Starting..."
      result = nil
      Sync do |parent|
        result = super(...)
        parent.reactor.print_hierarchy if ENV['DEBUG_ASYNC_HIERARCHY']
      end
      result
    end
  end
  RSpec::Core::Configuration.prepend(rspec_around_suite_patch)

  # Shared browser instance for integration tests
  # This is created once per test suite and reused across all tests
  config.before(:suite) do
    if RSpec.configuration.files_to_run.any? { |f| f.include?('spec/integration') }
      headless = !%w[0 false].include?(ENV['HEADLESS'])
      $shared_browser = Puppeteer::Bidi.launch_browser_instance(headless: headless, accept_insecure_certs: true)
      $shared_test_server = TestServer::Server.new
      $shared_https_test_server = TestServer::Server.new(
        scheme: 'https',
        ssl_context: TestServer.ssl_context
      )
      $shared_test_server.start
      $shared_https_test_server.start
      puts "\n[Test Suite] Browser and server started (will be reused across tests)"
    end
  end

  config.after(:suite) do
    if $shared_browser
      $shared_browser.close
      puts "\n[Test Suite] Browser closed"
    end
    if $shared_test_server
      $shared_test_server.stop
      puts "[Test Suite] Server stopped"
    end
    if $shared_https_test_server
      $shared_https_test_server.stop
      puts "[Test Suite] HTTPS server stopped"
    end
  end

  config.around(:each, type: :integration) do |example|
    Timeout.timeout(15) do
      example.run
    end
  end

  # Clean up custom routes after each test
  config.after(:each, type: :integration) do
    if $shared_test_server
      $shared_test_server.clear_routes
    end
  end

  helper_module = Module.new do
    include GoldenComparator
    include CookieHelpers

    def headless_mode?
      !%w[0 false].include?(ENV['HEADLESS'])
    end

    def linux?
      RUBY_PLATFORM.include?('linux')
    end

    # Legacy helper - launches a new browser for each call
    # Use with_test_state for better performance
    def with_browser(**options)
      options[:headless] = headless_mode?
      Puppeteer::Bidi.launch(**options) do |browser|
        yield(browser)
      end
    end

    # Optimized helper - reuses shared browser, creates new page per test
    # This is much faster as it avoids browser launch overhead
    def with_test_state
      # Create a new page (tab) for this test
      page = $shared_browser.new_page
      context = $shared_browser.default_browser_context

      begin
        yield(page: page, server: $shared_test_server, https_server: $shared_https_test_server,
              browser: $shared_browser, context: context)
      ensure
        # Close the page to clean up resources
        page.close unless page.closed?
      end
    end
  end
  config.include helper_module, type: :integration
end

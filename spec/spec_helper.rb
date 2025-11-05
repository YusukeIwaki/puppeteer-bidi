# frozen_string_literal: true

require "puppeteer/bidi"

# Load support files
require_relative 'support/test_server'
require_relative 'support/golden_comparator'

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

  # Shared browser instance for integration tests
  # This is created once per test suite and reused across all tests
  config.before(:suite) do
    if RSpec.configuration.files_to_run.any? { |f| f.include?('spec/integration') }
      headless = !%w[0 false].include?(ENV['HEADLESS'])
      $shared_browser = Puppeteer::Bidi.launch(headless: headless)
      $shared_test_server = TestServer::Server.new
      $shared_test_server.start
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
  end

  helper_module = Module.new do
    include GoldenComparator

    def headless_mode?
      !%w[0 false].include?(ENV['HEADLESS'])
    end

    # Legacy helper - launches a new browser for each call
    # Use with_test_state for better performance
    def with_browser(**options)
      options[:headless] = headless_mode?
      browser = Puppeteer::Bidi.launch(**options)
      yield(browser)
    ensure
      browser&.close
    end

    # Optimized helper - reuses shared browser, creates new page per test
    # This is much faster as it avoids browser launch overhead
    def with_test_state(**options)
      # Use shared browser if available, otherwise fall back to per-test browser
      if $shared_browser && options.empty?
        # Create a new page (tab) for this test
        page = $shared_browser.new_page
        context = $shared_browser.default_browser_context

        begin
          yield(page: page, server: $shared_test_server, browser: $shared_browser, context: context)
        ensure
          # Close the page to clean up resources
          page.close unless page.closed?
        end
      else
        # Fall back to per-test browser for tests with custom options
        server = TestServer::Server.new
        server.start

        begin
          with_browser(**options) do |browser|
            context = browser.default_browser_context
            page = browser.new_page
            yield(page: page, server: server, browser: browser, context: context)
          end
        ensure
          server.stop
        end
      end
    end
  end
  config.include helper_module, type: :integration
end

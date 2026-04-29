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

module BrowserTestResources
  class << self
    attr_reader :browser, :server, :https_server

    def start
      return if @browser

      headless = !%w[0 false].include?(ENV["HEADLESS"])
      @browser = Puppeteer::Bidi.launch_browser_instance(headless: headless, accept_insecure_certs: true)
      @server = TestServer::Server.new
      @https_server = TestServer::Server.new(
        scheme: "https",
        ssl_context: TestServer.ssl_context
      )
      @server.start
      @https_server.start
      puts "\n[Test Suite] Browser and server started (will be reused across tests)"
    end

    def stop
      if @browser
        @browser.close
        @browser = nil
        puts "\n[Test Suite] Browser closed"
      end
      if @server
        @server.stop
        @server = nil
        puts "[Test Suite] Server stopped"
      end
      if @https_server
        @https_server.stop
        @https_server = nil
        puts "[Test Suite] HTTPS server stopped"
      end
    end
  end
end

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

  def with_test_state
    BrowserTestResources.start
    page = BrowserTestResources.browser.new_page
    context = BrowserTestResources.browser.default_browser_context

    begin
      yield(
        page: page,
        server: BrowserTestResources.server,
        https_server: BrowserTestResources.https_server,
        browser: BrowserTestResources.browser,
        context: context
      )
    ensure
      page.close unless page.closed?
      BrowserTestResources.server.clear_routes
      BrowserTestResources.https_server.clear_routes
    end
  end
end

around_suite do |suite|
  use_fixture BrowserFixture
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
    BrowserTestResources.start
    result = suite.run
    parent.reactor.print_hierarchy if ENV["DEBUG_ASYNC_HIERARCHY"]
  ensure
    BrowserTestResources.stop
  end
  result
end

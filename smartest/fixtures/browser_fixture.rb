# frozen_string_literal: true

class BrowserFixture < Smartest::Fixture
  suite_fixture :browser do
    headless = !%w[0 false].include?(ENV["HEADLESS"])
    browser = Puppeteer::Bidi.launch_browser_instance(
      headless: headless,
      accept_insecure_certs: true
    )
    cleanup do
      browser.close unless browser.closed?
      puts "\n[Test Suite] Browser closed"
    end
    puts "\n[Test Suite] Browser started (will be reused across tests)"
    browser
  end

  fixture :context do |browser:|
    browser.default_browser_context
  end

  fixture :page do |browser:|
    page = browser.new_page
    cleanup { page.close unless page.closed? }
    page
  end

  fixture :cookie_state do |browser:, server:, https_server:|
    context = browser.create_browser_context
    page = context.new_page

    cleanup do
      page.close unless page.closed?
      context.close
    end

    {
      page: page,
      server: server,
      https_server: https_server,
      browser: browser,
      context: context,
    }
  end
end

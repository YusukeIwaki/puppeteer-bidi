# frozen_string_literal: true

# Suite-scoped fixtures for the shared Firefox browser instance and per-test
# resources derived from it (page, default browser context).
#
# `browser` is launched once per Smartest run and cleaned up after the entire
# suite finishes. `page` and `context` are test-scoped: a fresh page is created
# for every test, then closed afterwards so each test starts from a clean tab.
class BrowserFixture < Smartest::Fixture
  suite_fixture :browser do
    headless = !%w[0 false].include?(ENV["HEADLESS"])
    browser = Puppeteer::Bidi.launch_browser_instance(
      headless: headless,
      accept_insecure_certs: true
    )
    cleanup { browser.close }
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
end

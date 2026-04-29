# frozen_string_literal: true

class BrowserFixture < Smartest::Fixture
  suite_fixture :browser do
    BrowserTestResources.start
    BrowserTestResources.browser
  end

  suite_fixture :test_server do
    BrowserTestResources.start
    BrowserTestResources.server
  end

  suite_fixture :test_https_server do
    BrowserTestResources.start
    BrowserTestResources.https_server
  end

  fixture :server do |test_server:|
    cleanup { test_server.clear_routes }
    test_server
  end

  fixture :https_server do |test_https_server:|
    cleanup { test_https_server.clear_routes }
    test_https_server
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

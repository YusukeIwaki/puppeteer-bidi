# frozen_string_literal: true

require "test_helper"

# These are demonstration tests that walk through the BiDi Core API end-to-end.
# They navigate to live external URLs (example.com / w3.org), so they require
# network access. They each launch their own browser to avoid leaking state into
# the shared suite browser.

def with_isolated_browser
  headless = !%w[0 false].include?(ENV["HEADLESS"])
  Puppeteer::Bidi.launch(headless: headless, accept_insecure_certs: true) do |legacy_browser|
    yield(legacy_browser)
  end
end

test("[Core BiDi implementation] basic usage with core classes") do
  skip "Demo test that hits live external URLs" unless ENV["RUN_LIVE_DEMOS"]

  with_isolated_browser do |legacy_browser|
    connection = legacy_browser.connection
    session_info = { 'sessionId' => 'default-session', 'capabilities' => {} }
    session = Puppeteer::Bidi::Core::Session.new(connection, session_info)
    browser = Puppeteer::Bidi::Core::Browser.from(session).wait
    session.browser = browser
    user_context = browser.default_user_context
    browsing_context = user_context.create_browsing_context('tab')
    browsing_context.subscribe(['browsingContext.load', 'browsingContext.domContentLoaded'])

    load_promise = Async::Promise.new
    browsing_context.once(:load) { load_promise.resolve(true) }
    browsing_context.on(:navigation) {}

    browsing_context.navigate('https://example.com', wait: 'complete').wait
    Puppeteer::Bidi::AsyncUtils.async_timeout(5000, load_promise).wait

    expect(browsing_context.url).to start_with('https://example.com')
    result = browsing_context.default_realm.evaluate('document.title', true).wait
    expect(result['value']).to be_a(String)

    browsing_context.close.wait
  end
end

test("[Core BiDi implementation] event handling") do
  skip "Demo test that hits live external URLs" unless ENV["RUN_LIVE_DEMOS"]

  with_isolated_browser do |legacy_browser|
    connection = legacy_browser.connection
    session_info = { 'sessionId' => 'default-session', 'capabilities' => {} }
    session = Puppeteer::Bidi::Core::Session.new(connection, session_info)
    browser = Puppeteer::Bidi::Core::Browser.from(session).wait
    session.browser = browser
    user_context = browser.default_user_context
    browsing_context = user_context.create_browsing_context('tab')

    events_received = { navigation: false, dom_content_loaded: false, load: false }
    browsing_context.on(:navigation) { events_received[:navigation] = true }
    browsing_context.on(:dom_content_loaded) { events_received[:dom_content_loaded] = true }
    browsing_context.on(:load) { events_received[:load] = true }

    browsing_context.subscribe([
      'browsingContext.navigationStarted',
      'browsingContext.domContentLoaded',
      'browsingContext.load'
    ])

    browsing_context.navigate('https://example.com', wait: 'complete')
    sleep 1

    expect(events_received[:load] || events_received[:dom_content_loaded]).to eq(true)

    browsing_context.close
  end
end

test("[Core BiDi implementation] multiple contexts") do
  skip "Demo test that hits live external URLs" unless ENV["RUN_LIVE_DEMOS"]

  with_isolated_browser do |legacy_browser|
    connection = legacy_browser.connection
    session_info = { 'sessionId' => 'default-session', 'capabilities' => {} }
    session = Puppeteer::Bidi::Core::Session.new(connection, session_info)
    browser = Puppeteer::Bidi::Core::Browser.from(session).wait
    session.browser = browser
    user_context = browser.default_user_context

    context1 = user_context.create_browsing_context('tab')
    context2 = user_context.create_browsing_context('tab')

    context1.subscribe(['browsingContext.load'])
    context2.subscribe(['browsingContext.load'])

    context1.navigate('https://example.com', wait: 'complete')
    context2.navigate('https://www.w3.org/', wait: 'complete')

    contexts = user_context.browsing_contexts
    expect(contexts.size).to be_greater_than_or_equal_to(2)

    context1.close
    context2.close
  end
end

test("[Core BiDi implementation] user context isolation") do
  skip "Demo test that hits live external URLs" unless ENV["RUN_LIVE_DEMOS"]

  with_isolated_browser do |legacy_browser|
    connection = legacy_browser.connection
    session_info = { 'sessionId' => 'default-session', 'capabilities' => {} }
    session = Puppeteer::Bidi::Core::Session.new(connection, session_info)
    browser = Puppeteer::Bidi::Core::Browser.from(session).wait
    session.browser = browser

    default_context = browser.default_user_context
    incognito_context = browser.create_user_context.wait

    default_tab = default_context.create_browsing_context('tab')
    incognito_tab = incognito_context.create_browsing_context('tab')

    default_tab.navigate('https://example.com', wait: 'complete')
    incognito_tab.navigate('https://example.com', wait: 'complete')

    expect(default_tab.url).to start_with('https://example.com')
    expect(incognito_tab.url).to start_with('https://example.com')

    default_tab.close
    incognito_tab.close
    incognito_context.remove
  end
end

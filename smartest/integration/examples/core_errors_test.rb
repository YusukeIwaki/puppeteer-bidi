require "test_helper"

test(['Core error handling', 'raises custom exceptions when resources are disposed'].join(" ")) do
  with_browser do |legacy_browser|
    connection = legacy_browser.connection
    session_info = { 'sessionId' => 'default-session', 'capabilities' => {} }
    session = Puppeteer::Bidi::Core::Session.new(connection, session_info)
    browser = Puppeteer::Bidi::Core::Browser.from(session).wait
    session.browser = browser
    context = browser.default_user_context

    # Create and close a browsing context
    browsing_context = context.create_browsing_context('tab')

    # Manually dispose the context to simulate closure
    browsing_context.send(:dispose_context, 'Test closure')

    # Verify BrowsingContextClosedError is raised
    error = nil
    begin
      browsing_context.navigate('https://example.com').wait
    rescue Puppeteer::Bidi::Core::BrowsingContextClosedError => e
      error = e
    end
    expect(error).to be_a(Puppeteer::Bidi::Core::BrowsingContextClosedError)
    expect(error.resource_type).to eq('Browsing context')
    expect(error.reason).to eq('Test closure')
    expect(error.message).to include('Browsing context already disposed')

    browser.close
  end
end

test(['Core error handling', 'custom exceptions have proper inheritance'].join(" ")) do
  # Verify exception hierarchy
  ancestors = Puppeteer::Bidi::Core::RealmDestroyedError.new('test').class.ancestors
  expect(ancestors).to include(Puppeteer::Bidi::Core::DisposedError)
  expect(ancestors).to include(Puppeteer::Bidi::Core::Error)
  expect(ancestors).to include(Puppeteer::Bidi::Error)
  expect(ancestors).to include(StandardError)

  ancestors = Puppeteer::Bidi::Core::BrowsingContextClosedError.new('test').class.ancestors
  expect(ancestors).to include(Puppeteer::Bidi::Core::DisposedError)
  expect(ancestors).to include(Puppeteer::Bidi::Core::Error)

  ancestors = Puppeteer::Bidi::Core::UserContextClosedError.new('test').class.ancestors
  expect(ancestors).to include(Puppeteer::Bidi::Core::DisposedError)
end

test(['Core error handling', 'disposed errors have informative messages'].join(" ")) do
  error = Puppeteer::Bidi::Core::RealmDestroyedError.new('context was closed')
  expect(error.message).to eq('Realm already disposed: context was closed')
  expect(error.resource_type).to eq('Realm')
  expect(error.reason).to eq('context was closed')

  error2 = Puppeteer::Bidi::Core::BrowsingContextClosedError.new('user closed')
  expect(error2.message).to eq('Browsing context already disposed: user closed')
  expect(error2.resource_type).to eq('Browsing context')
  expect(error2.reason).to eq('user closed')
end

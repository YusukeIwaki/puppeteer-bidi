# frozen_string_literal: true

require "test_helper"

test("[Core error handling] raises custom exceptions when resources are disposed") do |browser:|
  connection = browser.connection
  session_info = { 'sessionId' => 'default-session', 'capabilities' => {} }
  session = Puppeteer::Bidi::Core::Session.new(connection, session_info)
  core_browser = Puppeteer::Bidi::Core::Browser.from(session).wait
  session.browser = core_browser
  context = core_browser.default_user_context

  browsing_context = context.create_browsing_context('tab')

  browsing_context.send(:dispose_context, 'Test closure')

  begin
    browsing_context.navigate('https://example.com').wait
    raise "expected BrowsingContextClosedError"
  rescue Puppeteer::Bidi::Core::BrowsingContextClosedError => error
    expect(error.resource_type).to eq('Browsing context')
    expect(error.reason).to eq('Test closure')
    expect(error.message).to include('Browsing context already disposed')
  end
end

test("[Core error handling] custom exceptions have proper inheritance") do
  expect(Puppeteer::Bidi::Core::RealmDestroyedError.new('test').class.ancestors).to include(Puppeteer::Bidi::Core::DisposedError)
  expect(Puppeteer::Bidi::Core::RealmDestroyedError.new('test').class.ancestors).to include(Puppeteer::Bidi::Core::Error)
  expect(Puppeteer::Bidi::Core::RealmDestroyedError.new('test').class.ancestors).to include(Puppeteer::Bidi::Error)
  expect(Puppeteer::Bidi::Core::RealmDestroyedError.new('test').class.ancestors).to include(StandardError)

  expect(Puppeteer::Bidi::Core::BrowsingContextClosedError.new('test').class.ancestors).to include(Puppeteer::Bidi::Core::DisposedError)
  expect(Puppeteer::Bidi::Core::BrowsingContextClosedError.new('test').class.ancestors).to include(Puppeteer::Bidi::Core::Error)

  expect(Puppeteer::Bidi::Core::UserContextClosedError.new('test').class.ancestors).to include(Puppeteer::Bidi::Core::DisposedError)
end

test("[Core error handling] disposed errors have informative messages") do
  error = Puppeteer::Bidi::Core::RealmDestroyedError.new('context was closed')
  expect(error.message).to eq('Realm already disposed: context was closed')
  expect(error.resource_type).to eq('Realm')
  expect(error.reason).to eq('context was closed')

  error2 = Puppeteer::Bidi::Core::BrowsingContextClosedError.new('user closed')
  expect(error2.message).to eq('Browsing context already disposed: user closed')
  expect(error2.resource_type).to eq('Browsing context')
  expect(error2.reason).to eq('user closed')
end

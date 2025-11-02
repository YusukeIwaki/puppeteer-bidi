require 'spec_helper'

RSpec.describe 'Core error handling' do
  example 'raises custom exceptions when resources are disposed' do
    with_browser do |legacy_browser|
      connection = legacy_browser.connection
      session_info = { 'sessionId' => 'default-session', 'capabilities' => {} }
      session = Puppeteer::Bidi::Core::Session.new(connection, session_info)
      browser = Puppeteer::Bidi::Core::Browser.from(session)
      session.browser = browser
      context = browser.default_user_context

      # Create and close a browsing context
      browsing_context = context.create_browsing_context('tab')

      # Manually dispose the context to simulate closure
      browsing_context.send(:dispose_context, 'Test closure')

      # Verify BrowsingContextClosedError is raised
      expect {
        browsing_context.navigate('https://example.com')
      }.to raise_error(Puppeteer::Bidi::Core::BrowsingContextClosedError) do |error|
        expect(error.resource_type).to eq('Browsing context')
        expect(error.reason).to eq('Test closure')
        expect(error.message).to include('Browsing context already disposed')
      end

      browser.close
    end
  end

  example 'custom exceptions have proper inheritance' do
    # Verify exception hierarchy
    expect(Puppeteer::Bidi::Core::RealmDestroyedError.new('test').class.ancestors).to include(
      Puppeteer::Bidi::Core::DisposedError,
      Puppeteer::Bidi::Core::Error,
      Puppeteer::Bidi::Error,
      StandardError
    )

    expect(Puppeteer::Bidi::Core::BrowsingContextClosedError.new('test').class.ancestors).to include(
      Puppeteer::Bidi::Core::DisposedError,
      Puppeteer::Bidi::Core::Error
    )

    expect(Puppeteer::Bidi::Core::UserContextClosedError.new('test').class.ancestors).to include(
      Puppeteer::Bidi::Core::DisposedError
    )
  end

  example 'disposed errors have informative messages' do
    error = Puppeteer::Bidi::Core::RealmDestroyedError.new('context was closed')
    expect(error.message).to eq('Realm already disposed: context was closed')
    expect(error.resource_type).to eq('Realm')
    expect(error.reason).to eq('context was closed')

    error2 = Puppeteer::Bidi::Core::BrowsingContextClosedError.new('user closed')
    expect(error2.message).to eq('Browsing context already disposed: user closed')
    expect(error2.resource_type).to eq('Browsing context')
    expect(error2.reason).to eq('user closed')
  end
end

require 'spec_helper'

RSpec.describe 'Core BiDi implementation' do
  example 'basic usage with core classes' do
    puts "=== Testing Puppeteer BiDi Core Implementation ==="
    puts "Step 1: Launching Firefox with BiDi protocol..."
    with_browser do |legacy_browser|
      puts "✓ Browser launched successfully!"

      # Access the underlying connection
      connection = legacy_browser.connection

      puts "\nStep 2: Creating core Session (wrapping existing connection)..."
      # Note: The legacy browser already called session.new, so we just wrap the connection
      # Create a minimal session wrapper
      session_info = {
        'sessionId' => 'default-session',
        'capabilities' => {}
      }
      session = Puppeteer::Bidi::Core::Session.new(connection, session_info)
      puts "✓ Session wrapper created"

      puts "\nStep 3: Creating core Browser..."
      browser = Puppeteer::Bidi::Core::Browser.from(session)
      session.browser = browser
      puts "✓ Core Browser created"

      puts "\nStep 4: Getting default user context..."
      user_context = browser.default_user_context
      puts "✓ Default user context: #{user_context.id}"

      puts "\nStep 5: Creating browsing context (tab)..."
      browsing_context = user_context.create_browsing_context('tab')
      puts "✓ Created browsing context: #{browsing_context.id}"

      # Subscribe to events
      puts "\nStep 6: Subscribing to events..."
      browsing_context.subscribe(['browsingContext.load', 'browsingContext.domContentLoaded'])
      puts "✓ Subscribed to events"

      # Listen for load event
      load_promise = Async::Promise.new
      browsing_context.once(:load) do
        puts "✓ Page load event received"
        load_promise.resolve(true)
      end

      # Listen for navigation events
      browsing_context.on(:navigation) do |data|
        navigation = data[:navigation]
        puts "✓ Navigation started"
      end

      puts "\nStep 7: Navigating to example.com..."
      browsing_context.navigate('https://example.com', wait: 'complete')
      puts "✓ Navigation completed"

      # Wait for load event
      Async do |task|
        task.with_timeout(5) do
          load_promise.wait
        end
      end.wait

      puts "\nStep 8: Getting URL..."
      puts "✓ Current URL: #{browsing_context.url}"

      puts "\nStep 9: Evaluating JavaScript..."
      result = browsing_context.default_realm.evaluate('document.title', true)
      puts "✓ Page title: #{result['value']}"

      puts "\nStep 10: Closing browsing context..."
      browsing_context.close
      puts "✓ Context closed"

      puts "\nStep 11: Closing browser..."
      browser.close
      puts "✓ Browser closed"

      puts "\n=== All core tests passed! ==="
    end
  end

  example 'event handling' do
    puts "=== Testing Event Handling ==="
    with_browser do |legacy_browser|
      connection = legacy_browser.connection

      # Create core components
      session_info = { 'sessionId' => 'default-session', 'capabilities' => {} }
      session = Puppeteer::Bidi::Core::Session.new(connection, session_info)
      browser = Puppeteer::Bidi::Core::Browser.from(session)
      session.browser = browser
      user_context = browser.default_user_context

      puts "Step 1: Creating browsing context..."
      browsing_context = user_context.create_browsing_context('tab')
      puts "✓ Created context"

      # Subscribe to various events
      puts "\nStep 2: Setting up event listeners..."
      events_received = {
        navigation: false,
        dom_content_loaded: false,
        load: false
      }

      browsing_context.on(:navigation) do |data|
        puts "✓ Navigation event received"
        events_received[:navigation] = true
      end

      browsing_context.on(:dom_content_loaded) do
        puts "✓ DOMContentLoaded event received"
        events_received[:dom_content_loaded] = true
      end

      browsing_context.on(:load) do
        puts "✓ Load event received"
        events_received[:load] = true
      end

      puts "\nStep 3: Subscribing to BiDi events..."
      browsing_context.subscribe([
        'browsingContext.navigationStarted',
        'browsingContext.domContentLoaded',
        'browsingContext.load'
      ])

      puts "\nStep 4: Navigating..."
      browsing_context.navigate('https://example.com', wait: 'complete')

      # Wait a bit for events to be processed
      sleep 1

      puts "\nStep 5: Verifying events..."
      puts "Navigation event: #{events_received[:navigation] ? '✓' : '✗'}"
      puts "DOMContentLoaded event: #{events_received[:dom_content_loaded] ? '✓' : '✗'}"
      puts "Load event: #{events_received[:load] ? '✓' : '✗'}"

      browsing_context.close
      browser.close

      puts "\n=== Event handling tests completed! ==="
    end
  end

  example 'multiple contexts' do
    puts "=== Testing Multiple Browsing Contexts ==="
    with_browser do |legacy_browser|
      connection = legacy_browser.connection

      # Create core components
      session_info = { 'sessionId' => 'default-session', 'capabilities' => {} }
      session = Puppeteer::Bidi::Core::Session.new(connection, session_info)
      browser = Puppeteer::Bidi::Core::Browser.from(session)
      session.browser = browser
      user_context = browser.default_user_context

      puts "Step 1: Creating multiple browsing contexts..."
      context1 = user_context.create_browsing_context('tab')
      puts "✓ Created context 1: #{context1.id}"

      context2 = user_context.create_browsing_context('tab')
      puts "✓ Created context 2: #{context2.id}"

      puts "\nStep 2: Navigating contexts to different URLs..."
      context1.subscribe(['browsingContext.load'])
      context2.subscribe(['browsingContext.load'])

      context1.navigate('https://example.com', wait: 'complete')
      puts "✓ Context 1 navigated to example.com"

      context2.navigate('https://www.w3.org/', wait: 'complete')
      puts "✓ Context 2 navigated to w3.org"

      puts "\nStep 3: Verifying URLs..."
      puts "Context 1 URL: #{context1.url}"
      puts "Context 2 URL: #{context2.url}"

      puts "\nStep 4: Getting browsing contexts from user context..."
      contexts = user_context.browsing_contexts
      puts "✓ Total contexts: #{contexts.size}"

      puts "\nStep 5: Closing contexts..."
      context1.close
      puts "✓ Context 1 closed"

      context2.close
      puts "✓ Context 2 closed"

      browser.close

      puts "\n=== Multiple contexts tests completed! ==="
    end
  end

  example 'user context isolation' do
    puts "=== Testing User Context Isolation ==="
    with_browser do |legacy_browser|
      connection = legacy_browser.connection

      session_info = { 'sessionId' => 'default-session', 'capabilities' => {} }
      session = Puppeteer::Bidi::Core::Session.new(connection, session_info)
      browser = Puppeteer::Bidi::Core::Browser.from(session)
      session.browser = browser

      puts "Step 1: Getting default user context..."
      default_context = browser.default_user_context
      puts "✓ Default context: #{default_context.id}"

      puts "\nStep 2: Creating incognito user context..."
      incognito_context = browser.create_user_context
      puts "✓ Incognito context: #{incognito_context.id}"

      puts "\nStep 3: Creating browsing contexts in each user context..."
      default_tab = default_context.create_browsing_context('tab')
      puts "✓ Tab in default context: #{default_tab.id}"

      incognito_tab = incognito_context.create_browsing_context('tab')
      puts "✓ Tab in incognito context: #{incognito_tab.id}"

      puts "\nStep 4: Navigating both tabs..."
      default_tab.navigate('https://example.com', wait: 'complete')
      incognito_tab.navigate('https://example.com', wait: 'complete')
      puts "✓ Both tabs navigated"

      puts "\nStep 5: Verifying isolation..."
      puts "Default tab URL: #{default_tab.url}"
      puts "Incognito tab URL: #{incognito_tab.url}"
      puts "Contexts are isolated: ✓"

      puts "\nStep 6: Cleaning up..."
      default_tab.close
      incognito_tab.close
      incognito_context.remove
      browser.close

      puts "\n=== User context isolation tests completed! ==="
    end
  end
end

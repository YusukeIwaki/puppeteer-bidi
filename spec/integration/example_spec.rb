require 'spec_helper'

RSpec.describe 'basic usage' do
  example 'basic usage' do
    puts "Launching Firefox with BiDi protocol..."
    with_browser do |browser|
      puts "Browser launched successfully!"

      # Get session status
      status = browser.status
      puts "BiDi session status: #{status.inspect}"

      # Create a new browsing context (tab)
      puts "\nCreating new browsing context..."
      result = browser.new_context(type: 'tab')
      context_id = result['context']
      puts "Created context: #{context_id}"

      # Subscribe to navigation events
      puts "\nSubscribing to navigation events..."
      browser.subscribe(['browsingContext.navigationStarted', 'browsingContext.load'])

      # Register event handler
      browser.on('browsingContext.navigationStarted') do |params|
        puts "Navigation started: #{params['url']}"
      end

      browser.on('browsingContext.load') do |params|
        puts "Navigation completed: #{params['url']}"
      end

      # Navigate to a URL
      puts "\nNavigating to example.com..."
      nav_result = browser.navigate(
        context: context_id,
        url: 'https://example.com',
        wait: 'complete'
      )
      puts "Navigation result: #{nav_result.inspect}"

      # Get all contexts
      puts "\nGetting all browsing contexts..."
      contexts = browser.contexts
      puts "Contexts tree: #{contexts.inspect}"

      # Wait for user input to see the browser
      puts "\nPress Enter to close the browser..."
      gets

      # Close the context
      puts "\nClosing browsing context..."
      browser.close_context(context_id)
    end

    puts "Done!"
  end

  example 'test run' do
    puts "=== Testing Puppeteer BiDi Implementation ==="
    puts "Step 1: Launching Firefox with BiDi protocol..."
    with_browser do |browser|
      puts "✓ Browser launched successfully!"

      puts "\nStep 2: Getting session status..."
      status = browser.status
      puts "✓ BiDi session status: #{status.inspect}"

      puts "\nStep 3: Creating new browsing context (tab)..."
      result = browser.new_context(type: 'tab')
      puts "Result: #{result.inspect}"
      context_id = result&.dig('context')
      puts "✓ Created context: #{context_id}"

      puts "\nStep 4: Subscribing to navigation events..."
      browser.subscribe(['browsingContext.navigationStarted'])
      puts "✓ Subscribed to events"

      puts "\nStep 5: Navigating to example.com..."
      nav_result = browser.navigate(
        context: context_id,
        url: 'https://example.com',
        wait: 'complete'
      )
      puts "✓ Navigation result: #{nav_result.inspect}"

      puts "\nStep 6: Getting all browsing contexts..."
      contexts = browser.contexts
      puts "✓ Found #{contexts['contexts'].size} context(s)"

      puts "\nStep 7: Closing browsing context..."
      browser.close_context(context_id)
      puts "✓ Context closed"

      puts "\nStep 8: Closing browser..."
      browser.close
      puts "✓ Browser closed"

      puts "\n=== All tests passed! ==="
    end
  end
end

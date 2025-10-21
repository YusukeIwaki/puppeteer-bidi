#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'puppeteer/bidi'

begin
  puts "=== Testing Puppeteer BiDi Implementation ==="
  puts "Step 1: Launching Firefox with BiDi protocol..."

  browser = Puppeteer::Bidi.launch(
    headless: true,  # Run in headless mode for testing
  )

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
  exit 0
rescue => e
  puts "\n!!! Error occurred !!!"
  puts "Error: #{e.class} - #{e.message}"
  puts "\nBacktrace:"
  puts e.backtrace.join("\n")
  exit 1
end

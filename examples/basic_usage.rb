#!/usr/bin/env ruby
# frozen_string_literal: true

# Example of basic usage of puppeteer-bidi
# This demonstrates launching Firefox, creating a context, and navigating to a URL

require 'bundler/setup'
require 'puppeteer/bidi'

begin
  puts "Launching Firefox with BiDi protocol..."
  browser = Puppeteer::Bidi.launch(
    headless: false,  # Set to true to run in headless mode
    # executable_path: '/path/to/firefox'  # Uncomment to specify Firefox path
  )

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

  # Close the browser
  puts "Closing browser..."
  browser.close

  puts "Done!"
rescue => e
  puts "Error: #{e.class} - #{e.message}"
  puts e.backtrace.join("\n")
  exit 1
end

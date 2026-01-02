#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'puppeteer/bidi'

FIREFOX_PATH = ENV.fetch('FIREFOX_PATH', '/tmp/Firefox139.app/Contents/MacOS/firefox')
ITERATIONS = 150

html_template = ->(i) { <<~HTML }
  <!DOCTYPE html>
  <html>
  <head><title>Page #{i}</title></head>
  <body>
    <div id="content">
      <h1>Benchmark Page #{i}</h1>
      <ul>
        #{(1..20).map { |j| "<li>Item #{j}</li>" }.join("\n        ")}
      </ul>
      <p class="description">This is test page number #{i}</p>
    </div>
  </body>
  </html>
HTML

puts "=== puppeteer-bidi Benchmark (Firefox #{`#{FIREFOX_PATH} --version`.strip.split.last}) ==="
puts "Iterations: #{ITERATIONS}"
puts

total_time = nil
begin
  Puppeteer::Bidi.launch(
    executable_path: FIREFOX_PATH,
    headless: true
  ) do |browser|
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    page = browser.new_page

    ITERATIONS.times do |i|
      # Set HTML content
      page.set_content(html_template.call(i))

      # Query selectors
      title = page.query_selector('h1')
      items = page.query_selector_all('li')
      desc = page.query_selector('.description')

      # Evaluate JavaScript
      page.evaluate('() => document.title')
      page.evaluate('(el) => el.textContent', title)
      page.evaluate('(els) => els.length', items)
      page.evaluate('(el) => el.textContent', desc)

      # More evaluations
      page.evaluate('() => window.innerWidth')
      page.evaluate('() => document.querySelectorAll("li").length')

      print '.' if (i + 1) % 10 == 0
    end
    total_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
  end
end

puts
puts
puts "Total time: #{total_time.round(2)} seconds"
puts "Average per iteration: #{(total_time / ITERATIONS * 1000).round(2)} ms"

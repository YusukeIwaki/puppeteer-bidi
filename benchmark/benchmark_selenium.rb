#!/usr/bin/env ruby
# frozen_string_literal: true

require 'selenium-webdriver'
require 'erb'

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

puts "=== Selenium WebDriver Benchmark (Firefox #{`#{FIREFOX_PATH} --version`.strip.split.last}) ==="
puts "Iterations: #{ITERATIONS}"
puts

options = Selenium::WebDriver::Firefox::Options.new
options.binary = FIREFOX_PATH
options.add_argument('-headless')

total_time = nil
begin
  driver = Selenium::WebDriver.for(:firefox, options: options)
  start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  ITERATIONS.times do |i|
    # Set HTML content via data URL
    html = html_template.call(i)
    driver.navigate.to("data:text/html;charset=utf-8,#{ERB::Util.url_encode(html)}")

    # Query selectors
    title = driver.find_element(:css, 'h1')
    items = driver.find_elements(:css, 'li')
    desc = driver.find_element(:css, '.description')

    # Get text content (equivalent to evaluate)
    driver.title
    title.text
    items.size
    desc.text

    # Execute JavaScript
    driver.execute_script('return window.innerWidth')
    driver.execute_script("return document.querySelectorAll('li').length")

    print '.' if (i + 1) % 10 == 0
  end
  total_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
ensure
  driver&.quit
end

puts
puts
puts "Total time: #{total_time.round(2)} seconds"
puts "Average per iteration: #{(total_time / ITERATIONS * 1000).round(2)} ms"

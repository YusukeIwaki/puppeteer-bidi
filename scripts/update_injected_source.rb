#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to update Puppeteer injected source from unpkg
# Usage: bundle exec ruby scripts/update_injected_source.rb [VERSION]
#
# Example:
#   bundle exec ruby scripts/update_injected_source.rb 24.31.0

require 'net/http'
require 'json'

VERSION = ARGV[0] || '24.31.0'
URL = "https://unpkg.com/puppeteer-core@#{VERSION}/lib/esm/puppeteer/generated/injected.js"
OUTPUT_FILE = File.join(__dir__, '..', 'lib', 'puppeteer', 'bidi', 'injected.js')

puts "Downloading Puppeteer injected source..."
puts "  URL: #{URL}"
puts "  Version: #{VERSION}"
puts

# Download the file
uri = URI(URL)
response = Net::HTTP.get_response(uri)

unless response.is_a?(Net::HTTPSuccess)
  puts "ERROR: Failed to download file (#{response.code} #{response.message})"
  exit 1
end

content = response.body

# Extract the source string value from: export const source = "...";
match = content.match(/export const source = (\".*\");/m)
unless match
  puts "ERROR: Could not find 'export const source =' in downloaded file"
  exit 1
end

source_value = match[1]

# Parse JSON to unescape the string
begin
  js_code = JSON.parse(source_value)
rescue JSON::ParserError => e
  puts "ERROR: Failed to parse JSON: #{e.message}"
  exit 1
end

# Write to output file
File.write(OUTPUT_FILE, js_code)

puts "✓ Successfully updated #{OUTPUT_FILE}"
puts "  Size: #{js_code.length} bytes"
puts
puts "To verify the update:"
puts "  bundle exec ruby -e \"require './lib/puppeteer/bidi/injected_source'; puts PUPPETEER_INJECTED_SOURCE[0..100]\""

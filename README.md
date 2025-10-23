# Puppeteer::BiDi

A Ruby port of [Puppeteer](https://pptr.dev/) using the WebDriver BiDi protocol for Firefox automation.

## Overview

`puppeteer-bidi` is a Ruby implementation of Puppeteer that leverages the [WebDriver BiDi protocol](https://w3c.github.io/webdriver-bidi/) to automate Firefox browsers. Unlike the existing [puppeteer-ruby](https://github.com/YusukeIwaki/puppeteer-ruby) gem which uses the Chrome DevTools Protocol (CDP), this gem focuses specifically on BiDi protocol support for cross-browser automation.

### Why BiDi?

- **Cross-browser compatibility**: BiDi is a W3C standard protocol designed to work across different browsers
- **Firefox-first**: While CDP is Chrome-centric, BiDi provides better support for Firefox automation
- **Future-proof**: BiDi represents the future direction of browser automation standards

### Relationship with puppeteer-ruby

This gem complements the existing `puppeteer-ruby` ecosystem:

- **puppeteer-ruby**: Uses CDP (Chrome DevTools Protocol) → Best for Chrome/Chromium automation
- **puppeteer-bidi** (this gem): Uses BiDi protocol → Best for Firefox automation

This gem ports only the BiDi-related portions of Puppeteer to Ruby, intentionally excluding CDP implementations.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add puppeteer-bidi
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install puppeteer-bidi
```

Or add this line to your application's Gemfile:

```ruby
gem 'puppeteer-bidi'
```

## Prerequisites

- Ruby 3.0 or higher
- Firefox browser with BiDi support

## Usage

### Basic Usage

```ruby
require 'puppeteer/bidi'

# Launch Firefox with BiDi protocol
browser = Puppeteer::Bidi.launch(headless: false)

# Create a new browsing context (tab)
result = browser.new_context(type: 'tab')
context_id = result['context']

# Navigate to a URL
browser.navigate(
  context: context_id,
  url: 'https://example.com',
  wait: 'complete'
)

# Close the browsing context
browser.close_context(context_id)

# Close the browser
browser.close
```

### Launch Options

```ruby
browser = Puppeteer::Bidi.launch(
  headless: true,              # Run in headless mode (default: true)
  executable_path: '/path/to/firefox',  # Path to Firefox executable (optional)
  user_data_dir: '/path/to/profile',    # User data directory (optional)
  args: ['--width=1280', '--height=720'] # Additional Firefox arguments
)
```

### Event Handling

```ruby
require 'puppeteer/bidi'

browser = Puppeteer::Bidi.launch(headless: false)

# Subscribe to BiDi events
browser.subscribe([
  'browsingContext.navigationStarted',
  'browsingContext.navigationComplete'
])

# Register event handlers
browser.on('browsingContext.navigationStarted') do |params|
  puts "Navigation started: #{params['url']}"
end

browser.on('browsingContext.navigationComplete') do |params|
  puts "Navigation completed: #{params['url']}"
end

# Create context and navigate
result = browser.new_context(type: 'tab')
browser.navigate(context: result['context'], url: 'https://example.com')
```

### Connecting to Existing Browser

```ruby
# Connect to an already running Firefox instance with BiDi
browser = Puppeteer::Bidi.connect('ws://localhost:9222/session')

# Use the browser
status = browser.status
puts "Connected to browser: #{status.inspect}"

browser.close
```

For more examples, see the [examples](examples/) directory and integration tests in [spec/integration/](spec/integration/).

## Testing

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run integration tests (launches actual Firefox browser)
bundle exec rspec spec/integration/

# Run specific integration test
bundle exec rspec spec/integration/example_spec.rb
```

### Integration Tests

Integration tests in `spec/integration/` demonstrate real-world usage by launching Firefox and performing browser automation tasks. These tests are useful for:

- Verifying end-to-end functionality
- Learning by example
- Ensuring browser compatibility

## Project Status

This project is in early development. The API may change as the implementation progresses.

### Implemented Features

- ✅ Browser launching with Firefox
- ✅ BiDi protocol connection (WebSocket-based)
- ✅ Browsing context management (create/close tabs)
- ✅ Basic navigation
- ✅ Event subscription and handling
- ✅ Command execution with timeout

### Planned Features

- Page navigation and lifecycle management
- JavaScript evaluation
- DOM manipulation and element interaction
- Network interception and monitoring
- Screenshots and PDF generation
- Cookie management
- Input simulation (mouse, keyboard)

## Comparison with Puppeteer (Node.js)

This gem aims to provide a Ruby-friendly API that closely mirrors the original Puppeteer API while following Ruby conventions and idioms.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/YusukeIwaki/puppeteer-bidi.

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

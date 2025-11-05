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

- Ruby 3.2 or higher (required by socketry/async dependency)
- Firefox browser with BiDi support

## Usage

### High-Level Page API (Recommended)

```ruby
require 'puppeteer/bidi'

# Launch Firefox with BiDi protocol
browser = Puppeteer::Bidi.launch(headless: false)

# Create a new page
page = browser.new_page

# Set viewport size
page.set_viewport(width: 1280, height: 720)

# Navigate to a URL
page.goto('https://example.com')

# Take a screenshot
page.screenshot(path: 'screenshot.png')

# Take a full page screenshot
page.screenshot(path: 'fullpage.png', full_page: true)

# Screenshot with clipping
page.screenshot(
  path: 'clip.png',
  clip: { x: 0, y: 0, width: 100, height: 100 }
)

# Evaluate JavaScript expressions
title = page.evaluate('document.title')
puts "Page title: #{title}"

# Evaluate JavaScript functions with arguments
sum = page.evaluate('(a, b) => a + b', 3, 4)
puts "Sum: #{sum}"  # => 7

# Access frame and evaluate
frame = page.main_frame
result = frame.evaluate('() => window.innerWidth')

# Set page content
page.set_content('<h1>Hello, World!</h1>')

# Close the page
page.close

# Close the browser
browser.close
```

### Low-Level BiDi API

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

### Using Core Layer (Advanced)

The Core layer provides a structured API over BiDi protocol:

```ruby
require 'puppeteer/bidi'

# Launch browser and access connection
browser = Puppeteer::Bidi.launch(headless: false)

# Create Core layer objects
session_info = { 'sessionId' => 'default-session', 'capabilities' => {} }
session = Puppeteer::Bidi::Core::Session.new(browser.connection, session_info)
core_browser = Puppeteer::Bidi::Core::Browser.from(session)
session.browser = core_browser

# Get default user context
context = core_browser.default_user_context

# Create browsing context with Core API
browsing_context = context.create_browsing_context('tab')

# Subscribe to events
browsing_context.on(:load) do
  puts "Page loaded!"
end

browsing_context.subscribe(['browsingContext.load'])

# Navigate
browsing_context.navigate('https://example.com', wait: 'complete')

# Evaluate JavaScript
result = browsing_context.default_realm.evaluate('document.title', true)
puts "Title: #{result['value']}"

# Take screenshot
image_data = browsing_context.capture_screenshot(format: 'png')

# Error handling with custom exceptions
begin
  browsing_context.navigate('https://example.com')
rescue Puppeteer::Bidi::Core::BrowsingContextClosedError => e
  puts "Context was closed: #{e.reason}"
end

# Clean up
browsing_context.close
core_browser.close
```

For more details on the Core layer, see `lib/puppeteer/bidi/core/README.md`.

For more examples, see the [examples](examples/) directory and integration tests in [spec/integration/](spec/integration/).

## Testing

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run integration tests (launches actual Firefox browser)
bundle exec rspec spec/integration/

# Run evaluation tests (23 examples, ~7 seconds)
bundle exec rspec spec/integration/evaluation_spec.rb

# Run screenshot tests (12 examples, ~8 seconds)
bundle exec rspec spec/integration/screenshot_spec.rb

# Run all integration tests (35 examples, ~10 seconds)
bundle exec rspec spec/integration/evaluation_spec.rb spec/integration/screenshot_spec.rb

# Run in non-headless mode for debugging
HEADLESS=false bundle exec rspec spec/integration/
```

### Integration Tests

Integration tests in `spec/integration/` demonstrate real-world usage by launching Firefox and performing browser automation tasks. These tests are useful for:

- Verifying end-to-end functionality
- Learning by example
- Ensuring browser compatibility

**Performance Note**: Integration tests are optimized to reuse a single browser instance across all tests (~19x faster than launching per test). Each test gets a fresh page (tab) for proper isolation.

#### Evaluation Tests

The `evaluation_spec.rb` includes 23 comprehensive tests ported from Puppeteer:

- JavaScript expression and function evaluation
- Argument serialization (numbers, arrays, objects, special values)
- Result deserialization (NaN, Infinity, -0, Maps)
- Exception handling and thrown values
- IIFE (Immediately Invoked Function Expression) support
- Frame.evaluate functionality

#### Screenshot Tests

The `screenshot_spec.rb` includes 12 comprehensive tests ported from Puppeteer:

- Basic screenshots and clipping regions
- Full page screenshots with viewport management
- Parallel execution across single/multiple pages
- Retina display compatibility
- Viewport restoration

All tests use golden image comparison with tolerance for cross-platform compatibility.

## Project Status

This project is in early development. The API may change as the implementation progresses.

### Implemented Features

#### High-Level Page API (`lib/puppeteer/bidi/`)
Puppeteer-compatible API for browser automation:

- ✅ **Browser**: Browser instance management
- ✅ **BrowserContext**: Isolated browsing sessions
- ✅ **Page**: High-level page automation
  - ✅ Navigation (`goto`, `set_content`)
  - ✅ JavaScript evaluation (`evaluate`) with functions, arguments, and IIFE support
  - ✅ Screenshots (basic, clipping, full page, parallel)
  - ✅ Viewport management with automatic restoration
  - ✅ Page state queries (`title`, `url`, `viewport`)
  - ✅ Frame access (`main_frame`)
- ✅ **Frame**: Frame-level operations
  - ✅ JavaScript evaluation with full feature parity to Page

#### Screenshot Features
Comprehensive screenshot functionality with 12 passing tests:

- ✅ Basic screenshots
- ✅ Clipping regions (document/viewport coordinates)
- ✅ Full page screenshots (with/without viewport expansion)
- ✅ Thread-safe parallel execution (single/multiple pages)
- ✅ Retina display compatibility (odd-sized clips)
- ✅ Automatic viewport restoration
- ✅ Base64 encoding

#### Foundation Layer
- ✅ Browser launching with Firefox
- ✅ BiDi protocol connection (WebSocket-based)
- ✅ WebSocket transport with async/await support
- ✅ Command execution with timeout
- ✅ Event subscription and handling

#### Core Layer (`lib/puppeteer/bidi/core/`)
A low-level object-oriented abstraction over the WebDriver BiDi protocol:

- ✅ **Infrastructure**: EventEmitter, Disposable, Custom Exceptions
- ✅ **Session Management**: BiDi session lifecycle
- ✅ **Browser & Contexts**: Browser, UserContext, BrowsingContext
- ✅ **Navigation**: Navigation lifecycle tracking
- ✅ **JavaScript Execution**: Realm classes (Window, Worker)
- ✅ **Network**: Request/Response management with interception
- ✅ **User Interaction**: UserPrompt handling (alert/confirm/prompt)

#### BiDi Operations
- ✅ Browsing context management (create/close tabs/windows)
- ✅ Page navigation with wait conditions
- ✅ JavaScript evaluation (`script.evaluate`, `script.callFunction`)
  - ✅ Expression evaluation
  - ✅ Function calls with argument serialization
  - ✅ Result deserialization (numbers, strings, arrays, objects, Maps, special values)
  - ✅ Exception handling and propagation
  - ✅ IIFE support
- ✅ Screenshot capture
- ✅ PDF generation
- ✅ Cookie management (get/set/delete)
- ✅ Network request interception
- ✅ Geolocation and timezone emulation

### Planned Features

- DOM manipulation and element interaction
- Full element selector support
- Input simulation (mouse, keyboard)
- File upload handling
- Enhanced network monitoring (NetworkManager)
- Frame management (FrameManager)
- Service Worker support

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

[![Gem Version](https://badge.fury.io/rb/puppeteer-bidi.svg)](https://badge.fury.io/rb/puppeteer-bidi)

# Puppeteer::BiDi

Ruby bindings for the WebDriver BiDi-powered version of [Puppeteer](https://pptr.dev/), focused on modern Firefox automation with a familiar, synchronous API.

## At a glance

- **Standards-first**: Uses the [WebDriver BiDi](https://w3c.github.io/webdriver-bidi/) protocol so scripts stay compatible as browsers converge on the standard.
- **Firefox-native**: Optimized for Firefox (Nightly recommended), including capabilities that are not available through CDP.
- **Async-powered, less flaky**: Fiber-backed concurrency instead of threads makes the synchronous-feeling API resilient against timing flakiness common in UI tests.
- **Typed-friendly Ruby**: Ships RBS signatures so editors and type checkers can guide you while coding.
- **Puppeteer ergonomics in Ruby**: Automatic waits and expressive helpers for navigation, selectors, and input.
- **Full-browser automation**: Screenshots, network interception, multi-context control, and event subscriptions without extra drivers.

### How it compares

- **Capybara (Ruby)**: Great for acceptance tests and Rack/Test drivers, but headless browser control depends on adapters like Selenium or Cuprite. Puppeteer::BiDi ships a single, consistent API aimed at end-to-end browser automation (screenshots, tracing, network control) rather than HTML-only flows.
- **Selenium WebDriver (Ruby)**: Broad browser coverage via the classic WebDriver protocol. Puppeteer::BiDi trades some breadth for higher-level defaults (auto-waiting, rich screenshot helpers) and BiDi-first features like network interception without extra extensions.
- **Playwright / Puppeteer (Node.js)**: Similar mental model and API surface, but require JavaScript. Puppeteer::BiDi keeps that productivity while fitting naturally into Ruby apps and test suites.
- **puppeteer-ruby (CDP)**: Use `puppeteer-ruby` for Chrome/Chromium via the DevTools Protocol. Puppeteer::BiDi intentionally focuses on the BiDi path.

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
gem "puppeteer-bidi"
```

## Prerequisites

- Ruby 3.2 or higher (required by the `async` dependency)
- Firefox with BiDi support (Nightly recommended for the newest protocol features)

## Quickstart

### High-level page API (recommended)

```ruby
require "puppeteer/bidi"

# Launch Firefox with BiDi
Puppeteer::Bidi.launch(headless: false) do |browser|
  page = browser.new_page
  page.goto("https://example.com")
  puts page.title

  page.click("button#get-started")
  page.type("input[name='email']", "user@example.com")
  page.screenshot(path: "hero.png", full_page: true)
end
```

### Launch options

```ruby
Puppeteer::Bidi.launch(
  headless: true,
  executable_path: "/path/to/firefox",
  user_data_dir: "/path/to/profile",
  args: ["--width=1280", "--height=720"]
)
```

### Connect to an existing browser

```ruby
ws_endpoint = nil

Sync do
  browser = Puppeteer::Bidi.launch_browser_instance(headless: true)
  ws_endpoint = browser.ws_endpoint
  browser.disconnect
end

Puppeteer::Bidi.connect(ws_endpoint) do |session|
  puts "Reconnected to browser"
  session.new_page.goto("https://example.com")
end
```

### Core layer (advanced)

Need protocol-level control? Build on the Core layer for explicit BiDi calls while keeping a structured API:

```ruby
require "puppeteer/bidi"

Puppeteer::Bidi.launch(headless: false) do |browser|
  session_info = { "sessionId" => "default-session", "capabilities" => {} }
  session = Puppeteer::Bidi::Core::Session.new(browser.connection, session_info)
  core_browser = Puppeteer::Bidi::Core::Browser.from(session)
  session.browser = core_browser

  context = core_browser.default_user_context
  browsing_context = context.create_browsing_context("tab")
  browsing_context.subscribe(["browsingContext.load"])
  browsing_context.navigate("https://example.com", wait: "complete")
end
```

For more examples, see the [examples](examples/) directory and integration tests in [spec/integration/](spec/integration/).

For development and testing commands, see [DEVELOPMENT.md](DEVELOPMENT.md).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/YusukeIwaki/puppeteer-bidi.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

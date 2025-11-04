# Puppeteer-BiDi Development Guide

This document outlines the design philosophy, architecture, and implementation guidelines for the puppeteer-bidi gem.

## Project Overview

### Purpose
Port the WebDriver BiDi protocol portions of Puppeteer to Ruby, providing a standards-based tool for Firefox automation.

### Comparison with Existing Tools

| Gem | Protocol | Target Browser | Features |
|-----|----------|---------------|----------|
| **puppeteer-ruby** | CDP (Chrome DevTools Protocol) | Chrome/Chromium | Chrome-specific, full-featured |
| **puppeteer-bidi** (this gem) | WebDriver BiDi | Firefox (primary) | W3C standard, cross-browser |

### Development Principles
- **BiDi-only**: Do not port CDP protocol-related code
- **Standards compliance**: Adhere to W3C WebDriver BiDi specification
- **Firefox optimization**: Maximize BiDi protocol capabilities
- **Ruby conventions**: Design Ruby-idiomatic interfaces

## Understanding Puppeteer's Architecture

### Hierarchical Object Model

Puppeteer adopts an intuitive API design that mirrors browser structure:

```
Browser
├── BrowserContext (isolated sessions)
│   └── Page (tabs/windows)
│       ├── Frame (main/iframes)
│       │   ├── ExecutionContext
│       │   └── ElementHandle/JSHandle
│       └── NetworkManager
```

#### Key Components

| Component | Role | Creation Method |
|-----------|------|-----------------|
| **Browser** | Entire browser instance | `puppeteer.launch()` / `puppeteer.connect()` |
| **BrowserContext** | Isolated user session | `browser.createIncognitoBrowserContext()` |
| **Page** | Single tab/popup | `context.newPage()` |
| **Frame** | Frame within page | Auto-generated (iframe/frame tags) |
| **ElementHandle** | Reference to DOM element | `page.$()` / `page.$$()` |

### Three-Layer Architecture

```
┌─────────────────────────────────┐
│  Upper Layer                    │
│  Puppeteer API & Browser        │
│  (High-level API, user-facing)  │
├─────────────────────────────────┤
│  Middle Layer                   │
│  Communication Protocol (BiDi)  │
│  (WebSocket, commands/events)   │
├─────────────────────────────────┤
│  Base Layer                     │
│  Ruby Environment               │
│  (WebSocket client, JSON)       │
└─────────────────────────────────┘
```

## WebDriver BiDi Protocol

### Characteristics
- **Communication**: WebSocket (bidirectional)
- **Message format**: JSON-RPC compliant
- **Standardization**: W3C standard specification
- **Browser support**: Firefox, Chrome, Edge (in progress)

### Communication Flow

#### Command Sending
```json
{
  "id": 1,
  "method": "browsingContext.navigate",
  "params": {
    "context": "context-id",
    "url": "https://example.com"
  }
}
```

#### Response Receiving
```json
{
  "id": 1,
  "result": {
    "navigation": "navigation-id",
    "url": "https://example.com"
  }
}
```

#### Event Receiving
```json
{
  "method": "browsingContext.navigationStarted",
  "params": {
    "context": "context-id",
    "navigation": "navigation-id",
    "url": "https://example.com"
  }
}
```

### Protocol Comparison

| Feature | CDP | WebDriver BiDi |
|---------|-----|----------------|
| **Communication Model** | Bidirectional (WebSocket) | Bidirectional (WebSocket) |
| **Standardization** | Non-standard (Google) | W3C standard |
| **Browser Support** | Chromium only | All browsers |
| **API Stability** | Low (frequent changes) | High (standardized) |

## Implementation Guidelines

### Essential Components

#### 1. Protocol Layer
- **WebSocket communication**: Connection management with BiDi server
- **Command sending**: Method invocation and response waiting
- **Event handling**: Subscription and processing of async events
- **Session management**: Connection state management

#### 2. Core API
- **Browser**: Browser instance management
- **BrowserContext**: Isolated browsing contexts
- **Page**: Core of page operations
- **Frame**: Frame management

#### 3. State Management
- **FrameManager**: Frame tree tracking
  - `browsingContext.contextCreated`
  - `browsingContext.contextDestroyed`
  - `browsingContext.navigationStarted`

- **NetworkManager**: Network activity monitoring
  - `network.beforeRequestSent`
  - `network.responseCompleted`
  - `network.fetchError`

### Anatomy of API Calls

#### Navigation Example
```ruby
page.goto('https://example.com', wait_until: 'networkidle')
```

Internal processing flow:
1. **Issue command**: `browsingContext.navigate`
2. **Subscribe to events**: NavigationManager monitors events
3. **Track state**: NetworkManager tracks requests
4. **Check conditions**: Determine `networkidle` condition
5. **Resolve promise**: Complete when condition is satisfied

#### Click Example
```ruby
page.click(selector)
```

Internal processing flow:
1. **Find element**: Execute selector via `script.evaluate`
2. **Check preconditions**: Verify visibility and validity
3. **Scroll**: Scroll element into viewport if needed
4. **Calculate coordinates**: Get element position and size
5. **Send events**: Simulate click via `input.performActions`

### Major BiDi Modules

| Module | Role | Key Methods |
|--------|------|-------------|
| `browsingContext` | Context management | navigate, create, close |
| `script` | JavaScript execution | evaluate, callFunction |
| `input` | User input | performActions, releaseActions |
| `network` | Network | addIntercept, continueRequest |
| `session` | Session management | subscribe, unsubscribe |

## Core Layer Architecture

The `lib/puppeteer/bidi/core/` module provides a structured, object-oriented abstraction over the WebDriver BiDi protocol.

### Design Philosophy

The Core layer follows Puppeteer's BiDi core design principles:

1. **Required vs Optional Arguments**: Required arguments are method parameters, optional ones are keyword arguments
2. **Session Visibility**: Session is never exposed on public APIs except Browser
3. **Spec Compliance**: Strictly follows WebDriver BiDi specification, not Puppeteer's needs
4. **Minimal Implementation**: Comprehensive but minimal - implements all required nodes and edges

### Core Classes

#### Infrastructure Classes
- **EventEmitter** (`event_emitter.rb`): Event subscription and emission system
- **Disposable** (`disposable.rb`): Resource management with DisposableStack pattern
- **Errors** (`errors.rb`): Custom exception hierarchy for type-safe error handling

#### Protocol Management Classes
- **Session** (`session.rb`): BiDi session management, wraps Connection
- **Browser** (`browser.rb`): Browser instance management with user contexts
- **UserContext** (`user_context.rb`): Isolated browsing contexts (incognito-like)
- **BrowsingContext** (`browsing_context.rb`): Tab/window/iframe management with full BiDi operations
- **Navigation** (`navigation.rb`): Navigation lifecycle tracking with nested navigation support
- **Request** (`request.rb`): Network request management with interception
- **UserPrompt** (`user_prompt.rb`): User prompt (alert/confirm/prompt) handling

#### JavaScript Execution Classes
- **Realm** (`realm.rb`): Base class for JavaScript execution contexts
  - **WindowRealm**: Window and iframe script execution
  - **DedicatedWorkerRealm**: Web Worker script execution
  - **SharedWorkerRealm**: Shared Worker script execution

### Exception Hierarchy

```
StandardError
└── Puppeteer::Bidi::Error
    └── Puppeteer::Bidi::Core::Error
        └── Puppeteer::Bidi::Core::DisposedError
            ├── RealmDestroyedError
            ├── BrowsingContextClosedError
            ├── UserContextClosedError
            ├── UserPromptClosedError
            ├── SessionEndedError
            └── BrowserDisconnectedError
```

### Usage Example

```ruby
# Create session from existing connection
session = Puppeteer::Bidi::Core::Session.new(connection, session_info)

# Create browser and get default context
browser = Puppeteer::Bidi::Core::Browser.from(session)
session.browser = browser
context = browser.default_user_context

# Create browsing context (tab)
browsing_context = context.create_browsing_context('tab')

# Navigate and evaluate JavaScript
browsing_context.navigate('https://example.com', wait: 'complete')
result = browsing_context.default_realm.evaluate('document.title', true)
puts result['value']  # => "Example Domain"

# Handle errors
begin
  browsing_context.navigate('https://example.com')
rescue Puppeteer::Bidi::Core::BrowsingContextClosedError => e
  puts "Context was closed: #{e.reason}"
end
```

### Event Handling Pattern

Core classes use EventEmitter for async event handling:

```ruby
# Listen for navigation events
browsing_context.on(:navigation) do |data|
  navigation = data[:navigation]
  puts "Navigation started"
end

# Listen for load events
browsing_context.on(:load) do
  puts "Page loaded"
end

# Subscribe to BiDi events
browsing_context.subscribe([
  'browsingContext.navigationStarted',
  'browsingContext.load'
])
```

### Resource Management

Core classes implement Disposable pattern for proper cleanup:

```ruby
# Resources are automatically disposed when parent is disposed
browser.close  # Disposes all user contexts, browsing contexts, etc.

# Check disposal status
browsing_context.closed?  # => true
browsing_context.disposed?  # => true
```

For detailed documentation, see `lib/puppeteer/bidi/core/README.md`.

## Development Roadmap

### Phase 1: Foundation ✅ COMPLETED
- [x] WebSocket communication layer (`lib/puppeteer/bidi/transport.rb`)
- [x] Basic BiDi protocol implementation (`lib/puppeteer/bidi/connection.rb`)
- [x] Browser/BrowserContext/Page base classes (`lib/puppeteer/bidi/browser.rb`)
- [x] **Core layer implementation** (`lib/puppeteer/bidi/core/`)
  - EventEmitter and Disposable patterns
  - Session management
  - Browser, UserContext, BrowsingContext classes
  - Navigation, Request, UserPrompt classes
  - Realm classes (WindowRealm, DedicatedWorkerRealm, SharedWorkerRealm)
  - Custom exception hierarchy

### Phase 2: Core Features ✅ COMPLETED
- [x] Navigation (`browsingContext.navigate`)
- [x] JavaScript execution (`script.evaluate`)
- [x] Event handling system (EventEmitter)
- [ ] Element operations (click, input) - **TODO**
- [ ] FrameManager implementation - **TODO**

### Phase 3: Advanced Features 🚧 IN PROGRESS
- [x] Network request management (Request class)
- [ ] NetworkManager implementation - **TODO**
- [ ] Network interception (partial support in Request)
- [x] Screenshot/PDF generation (BrowsingContext methods)
- [x] Enhanced event handling (Core layer)

### Phase 4: Stabilization 🚧 IN PROGRESS
- [x] Error handling (Custom exception classes)
- [ ] Timeout management - **TODO**
- [x] Test suite development (integration tests)
- [x] Documentation enhancement (Core README.md)

## Technical Considerations

### Performance
- Single operations may involve multiple communication round-trips
- WebSocket connection maintenance cost
- Event listener memory management

### Reliability
- Reconnection strategy for WebSocket disconnections
- Appropriate timeout settings
- Cleanup on error conditions

### Debugging
- BiDi protocol message logging
- Internal state visualization
- WebSocket traffic monitoring

## References

### Specifications & Documentation
- [WebDriver BiDi Specification](https://w3c.github.io/webdriver-bidi/)
- [Puppeteer Documentation](https://pptr.dev/)
- [Puppeteer Source Code](https://github.com/puppeteer/puppeteer)

### Implementation References
- [puppeteer-ruby](https://github.com/YusukeIwaki/puppeteer-ruby) - CDP implementation reference
- [Puppeteer BiDi implementation](https://github.com/puppeteer/puppeteer/tree/main/packages/puppeteer-core/src/bidi) - Original implementation

## Coding Conventions

### Ruby Conventions
- Use Ruby 3.0+ features
- Follow RuboCop guidelines
- Provide RBS type definitions

### Naming Conventions
- Class names: `PascalCase`
- Method names: `snake_case`
- Constants: `SCREAMING_SNAKE_CASE`

### Testing
- Use RSpec
- Unit tests + integration tests
- Appropriate use of mocks/stubs

### Test Organization
- **Unit tests**: `spec/` - Fast, isolated component tests
- **Integration tests**: `spec/integration/` - End-to-end browser automation tests
- Run integration tests: `bundle exec rspec spec/integration/`
- Integration tests launch actual Firefox browser instances

### Integration Test Helpers

The `spec/spec_helper.rb` provides a `with_browser` helper for integration tests:

```ruby
# spec/integration/my_test_spec.rb
RSpec.describe 'my feature' do
  example 'test something' do
    with_browser do |browser|
      # Browser is automatically launched and closed
      result = browser.new_context(type: 'tab')
      # ... test code
    end
  end
end
```

**Environment Variables:**
- `HEADLESS=false` - Run browser in non-headless mode (default: headless)

## Async Programming with socketry/async

This project uses the [socketry/async](https://github.com/socketry/async) library for asynchronous operations.

### Best Practices

1. **Use `Sync` at top level**: When running async code at the top level of a thread or application, use `Sync { }` instead of `Async { }`
   ```ruby
   Thread.new do
     Sync do
       # async operations here
     end
   end
   ```

2. **Reactor lifecycle**: The reactor is automatically managed by `Sync { }`. No need to create explicit `Async::Reactor` instances in application code.

3. **Background operations**: For long-running background tasks (like WebSocket connections), wrap `Sync { }` in a Thread:
   ```ruby
   connection_task = Thread.new do
     Sync do
       transport.connect  # Async operation that blocks until connection closes
     end
   end
   ```

### Current Implementation

The Browser class uses this pattern for WebSocket connection management:

```ruby
# lib/puppeteer/bidi/browser.rb
connection_task = Thread.new do
  Sync do
    transport.connect
  end
end
```

This ensures:
- Async operations run efficiently in an event loop
- Main thread remains responsive
- Proper cleanup on browser close

### References
- [Async Best Practices](https://socketry.github.io/async/guides/best-practices/)
- [Async Documentation](https://socketry.github.io/async/)

## Implementation Best Practices

### Porting Puppeteer Tests to Ruby

#### 1. Reference Implementation First

**Always consult the official Puppeteer implementation before implementing features:**

- **TypeScript source files**:
  - `packages/puppeteer-core/src/bidi/Page.ts` - High-level Page API
  - `packages/puppeteer-core/src/bidi/BrowsingContext.ts` - Core BiDi context
  - `packages/puppeteer-core/src/api/Page.ts` - Common Page interface

- **Test files**:
  - `test/src/screenshot.spec.ts` - Screenshot test suite
  - `test/golden-firefox/` - Golden images for visual regression testing

**Example workflow:**
```ruby
# 1. Read Puppeteer's TypeScript implementation
# 2. Understand the BiDi protocol calls being made
# 3. Implement Ruby equivalent with same logic flow
# 4. Port corresponding test cases
```

#### 2. Test Infrastructure Setup

**Use Sinatra + WEBrick for test servers** (standard, simple):

```ruby
# spec/support/test_server.rb
class App < Sinatra::Base
  set :public_folder, File.join(__dir__, '../assets')
  set :static, true
  set :logging, false
end

# Suppress WEBrick logs
App.run!(
  port: @port,
  server_settings: {
    Logger: WEBrick::Log.new('/dev/null'),
    AccessLog: []
  }
)
```

**Helper pattern for integration tests:**

```ruby
# spec/spec_helper.rb
def with_test_state(**options)
  server = TestServer::Server.new
  server.start

  begin
    with_browser(**options) do |browser|
      page = browser.new_page
      yield(page: page, server: server, browser: browser)
    end
  ensure
    server.stop
  end
end
```

#### 3. Golden Image Testing

**Download and compare pixel-by-pixel with tolerance:**

```bash
# Download golden images
curl -sL https://raw.githubusercontent.com/puppeteer/puppeteer/main/test/golden-firefox/screenshot-sanity.png \
  -o spec/golden-firefox/screenshot-sanity.png
```

**Implement tolerant comparison** (rendering engines differ slightly):

```ruby
def compare_with_golden(screenshot_base64, golden_filename,
                        max_diff_pixels: 0,
                        pixel_threshold: 1)
  # pixel_threshold: 1 allows ±1 RGB difference per channel
  # Handles Firefox version/platform rendering variations
end
```

#### 4. BiDi Protocol Data Deserialization

**BiDi returns values in special format - always deserialize:**

```ruby
# BiDi response format:
# [["width", {"type" => "number", "value" => 500}],
#  ["height", {"type" => "number", "value" => 1000}]]

def deserialize_result(result)
  value = result['value']
  return value unless value.is_a?(Array)

  # Convert to Ruby Hash
  if value.all? { |item| item.is_a?(Array) && item.length == 2 }
    value.each_with_object({}) do |(key, val), hash|
      hash[key] = deserialize_value(val)
    end
  else
    value
  end
end

def deserialize_value(val)
  case val['type']
  when 'number' then val['value']
  when 'string' then val['value']
  when 'boolean' then val['value']
  when 'undefined', 'null' then nil
  else val['value']
  end
end
```

#### 5. Implementing Puppeteer-Compatible APIs

**Follow Puppeteer's exact logic flow:**

Example: `fullPage` screenshot implementation

```ruby
# From Puppeteer's Page.ts:
# if (options.fullPage) {
#   if (!options.captureBeyondViewport) {
#     // Resize viewport to full page
#   }
# } else {
#   options.captureBeyondViewport = false;
# }

if full_page
  unless capture_beyond_viewport
    scroll_dimensions = evaluate(...)
    set_viewport(scroll_dimensions)
    begin
      data = capture_screenshot(origin: 'viewport')
    ensure
      set_viewport(original_viewport)  # Always restore
    end
  else
    options[:origin] = 'document'
  end
elsif !clip
  capture_beyond_viewport = false  # Match Puppeteer behavior
end
```

**Key principles:**
- Use `begin/ensure` blocks for cleanup (viewport restoration, etc.)
- Match Puppeteer's parameter defaults exactly
- Follow the same conditional logic order

#### 6. Layer Architecture

**Maintain clear separation:**

```
High-level API (lib/puppeteer/bidi/)
├── Browser        - User-facing browser interface
├── BrowserContext - Session management
└── Page           - Page automation API

Core Layer (lib/puppeteer/bidi/core/)
├── Session        - BiDi session management
├── Browser        - Low-level browser operations
├── UserContext    - BiDi user context
└── BrowsingContext - BiDi browsing context (tab/frame)
```

**Implementation pattern:**

```ruby
# High-level Page wraps Core::BrowsingContext
class Page
  def initialize(browser_context, browsing_context)
    @browsing_context = browsing_context  # Core layer
  end

  def screenshot(...)
    # High-level logic
    data = @browsing_context.capture_screenshot(...)  # Delegate to core
    # Post-processing
  end
end
```

#### 7. Multiple Pages and Parallel Execution

**Creating multiple pages in same context:**

```ruby
# Browser exposes default_browser_context
class Browser
  attr_reader :default_browser_context

  def new_page
    @default_browser_context.new_page
  end
end

# Test can access context to create multiple pages
with_test_state do |page:, context:, **|
  pages = (0...2).map do
    new_page = context.new_page
    new_page.goto("#{server.prefix}/grid.html")
    new_page
  end

  # Run in parallel using Ruby threads
  threads = pages.map do |p|
    Thread.new { p.screenshot(...) }
  end
  screenshots = threads.map(&:value)

  pages.each(&:close)
end
```

**Key points:**
- BrowserContext manages multiple Page instances
- Pages in same context share cookies/localStorage but have separate browsing contexts
- Thread-safe screenshot execution (BiDi protocol handles concurrency)

#### 8. Setting Page Content

**Use data URLs with base64 encoding:**

```ruby
def set_content(html, wait_until: 'load')
  # Encode HTML in base64 to avoid URL encoding issues
  encoded = Base64.strict_encode64(html)
  data_url = "data:text/html;base64,#{encoded}"
  goto(data_url, wait_until: wait_until)
end
```

**Why base64:**
- Avoids URL encoding issues with special characters
- Handles multi-byte characters correctly
- Standard approach in browser automation tools

#### 9. Viewport Restoration

**Always restore viewport after temporary changes:**

```ruby
# Save current viewport (may be nil)
original_viewport = viewport

# If no viewport set, save window size
unless original_viewport
  original_size = evaluate('({ width: window.innerWidth, height: window.innerHeight })')
  original_viewport = { width: original_size['width'].to_i, height: original_size['height'].to_i }
end

# Change viewport temporarily
set_viewport(width: new_width, height: new_height)

begin
  # Do work
ensure
  # Always restore
  set_viewport(**original_viewport) if original_viewport
end
```

**Important:**
- Use `begin/ensure` to guarantee restoration even on errors
- Handle nil viewport case (no explicit viewport was set)
- Save window.innerWidth/innerHeight as fallback

### Testing Strategy

#### Integration Tests Organization

```
spec/
├── unit/                    # Fast unit tests (future)
├── integration/             # Browser automation tests
│   ├── examples/           # Example-based tests
│   │   └── screenshot_spec.rb
│   └── screenshot_spec.rb  # Feature test suites
├── assets/                 # Test HTML/CSS/JS files
│   ├── grid.html
│   ├── scrollbar.html
│   ├── empty.html
│   └── digits/*.png
├── golden-firefox/         # Reference images
│   └── screenshot-*.png
└── support/               # Test utilities
    ├── test_server.rb
    └── golden_comparator.rb
```

#### Implemented Screenshot Tests

All 12 tests ported from [Puppeteer's screenshot.spec.ts](https://github.com/puppeteer/puppeteer/blob/main/test/src/screenshot.spec.ts):

1. **should work** - Basic screenshot functionality
2. **should clip rect** - Clipping specific region
3. **should get screenshot bigger than the viewport** - Offscreen clip with captureBeyondViewport
4. **should clip bigger than the viewport without "captureBeyondViewport"** - Viewport coordinate transformation
5. **should run in parallel** - Thread-safe parallel screenshots on single page
6. **should take fullPage screenshots** - Full page with document origin
7. **should take fullPage screenshots without captureBeyondViewport** - Full page with viewport resize
8. **should run in parallel in multiple pages** - Concurrent screenshots across multiple pages
9. **should work with odd clip size on Retina displays** - Odd pixel dimensions (11x11)
10. **should return base64** - Base64 encoding verification
11. **should take fullPage screenshots when defaultViewport is null** - No explicit viewport
12. **should restore to original viewport size** - Viewport restoration after fullPage

Run tests:
```bash
bundle exec rspec spec/integration/screenshot_spec.rb
# Expected: 12 examples, 0 failures (completes in ~68 seconds)
```

#### Environment Variables

```bash
HEADLESS=false  # Run browser in non-headless mode for debugging
```

### Debugging Techniques

#### 1. Save Screenshots for Inspection

```ruby
# In golden_comparator.rb
def save_screenshot(screenshot_base64, filename)
  output_dir = File.join(__dir__, '../output')
  FileUtils.mkdir_p(output_dir)
  File.binwrite(File.join(output_dir, filename),
                Base64.decode64(screenshot_base64))
end
```

#### 2. Compare Images Pixel-by-Pixel

```ruby
cat > /tmp/compare.rb << 'EOF'
require 'chunky_png'

golden = ChunkyPNG::Image.from_file('spec/golden-firefox/screenshot.png')
actual = ChunkyPNG::Image.from_file('spec/output/debug.png')

diff_count = 0
(0...golden.height).each do |y|
  (0...golden.width).each do |x|
    if golden[x, y] != actual[x, y]
      diff_count += 1
      puts "Diff at (#{x}, #{y})" if diff_count <= 10
    end
  end
end
puts "Total: #{diff_count} pixels differ"
EOF
ruby /tmp/compare.rb
```

#### 3. Debug BiDi Responses

```ruby
# Temporarily add debugging
result = @browsing_context.default_realm.evaluate(script, true)
puts "BiDi result: #{result.inspect}"
deserialize_result(result)
```

### Common Pitfalls and Solutions

#### 1. BiDi Protocol Differences

**Problem:** BiDi `origin` parameter behavior differs from expectations

**Solution:** Consult BiDi spec and test both `'document'` and `'viewport'` origins

```ruby
# document: Absolute coordinates in full page
# viewport: Relative to current viewport
options[:origin] = capture_beyond_viewport ? 'document' : 'viewport'
```

#### 2. Image Comparison Failures

**Problem:** Golden images don't match exactly (1-2 pixel differences)

**Solution:** Implement tolerance in comparison

```ruby
# Allow small rendering differences (±1 RGB per channel)
compare_with_golden(screenshot, 'golden.png', pixel_threshold: 1)
```

#### 3. Viewport State Management

**Problem:** Viewport not restored after fullPage screenshot

**Solution:** Use `ensure` block

```ruby
begin
  set_viewport(full_page_dimensions)
  screenshot = capture_screenshot(...)
ensure
  set_viewport(original_viewport) if original_viewport
end
```

#### 4. Thread Safety

**Problem:** Parallel screenshots cause race conditions

**Solution:** BiDi protocol handles this naturally - test with threads

```ruby
threads = (0...3).map do |i|
  Thread.new { page.screenshot(clip: {...}) }
end
screenshots = threads.map(&:value)
```

### Documentation References

**Essential reading for implementation:**

1. **WebDriver BiDi Spec**: https://w3c.github.io/webdriver-bidi/
2. **Puppeteer Source**: https://github.com/puppeteer/puppeteer
3. **Puppeteer BiDi Tests**: https://github.com/puppeteer/puppeteer/tree/main/test/src
4. **Firefox BiDi Impl**: Check Firefox implementation notes for quirks

**Reference implementation workflow:**
1. Find corresponding Puppeteer test in `test/src/`
2. Read TypeScript implementation in `packages/puppeteer-core/src/`
3. Check BiDi spec for protocol details
4. Implement Ruby version maintaining same logic
5. Download golden images and verify pixel-perfect match (with tolerance)

## Summary

puppeteer-bidi aims to provide a Ruby implementation that inherits Puppeteer's design philosophy while leveraging WebDriver BiDi protocol characteristics. Through layered architecture, event-driven design, and adoption of standardized protocols, we deliver a reliable Firefox automation tool.

**Development workflow:**
1. Study Puppeteer's implementation first
2. Understand BiDi protocol calls
3. Implement with proper deserialization
4. Port tests with golden image verification
5. Handle platform/version rendering differences gracefully

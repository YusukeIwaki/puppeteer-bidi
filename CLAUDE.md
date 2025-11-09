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
- [x] JavaScript execution (`script.evaluate`, `script.callFunction`)
- [x] **Page.evaluate and Frame.evaluate** - Full JavaScript evaluation with argument serialization
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

## JavaScript Evaluation Implementation

### Page.evaluate and Frame.evaluate

The `evaluate` method supports both JavaScript expressions and functions with proper argument serialization.

#### Detection Logic

The implementation distinguishes between three types of JavaScript code:

1. **Expressions**: Simple JavaScript code
2. **Functions**: Arrow functions or function declarations (use `script.callFunction`)
3. **IIFE**: Immediately Invoked Function Expressions (use `script.evaluate`)

```ruby
# Expression - uses script.evaluate
page.evaluate('7 * 3')  # => 21

# Function - uses script.callFunction
page.evaluate('(a, b) => a + b', 3, 4)  # => 7

# IIFE - uses script.evaluate (not script.callFunction)
page.evaluate('(() => document.title)()')  # => "Page Title"
```

#### IIFE Detection Pattern

**Critical**: IIFE must be detected and treated as expressions:

```ruby
# Check if it's an IIFE - ends with () after the function body
is_iife = script_trimmed.match?(/\)\s*\(\s*\)\s*\z/)

# Only treat as function if not IIFE
is_function = !is_iife && (
  script_trimmed.match?(/\A\s*(?:async\s+)?(?:\(.*?\)|[a-zA-Z_$][\w$]*)\s*=>/) ||
  script_trimmed.match?(/\A\s*(?:async\s+)?function\s*\w*\s*\(/)
)
```

**Why this matters**: IIFE like `(() => {...})()` looks like a function but must be evaluated as an expression. Using `script.callFunction` on IIFE causes syntax errors.

#### Argument Serialization

Arguments are serialized to BiDi `LocalValue` format:

```ruby
# Special numbers
{ type: 'number', value: 'NaN' }
{ type: 'number', value: 'Infinity' }
{ type: 'number', value: '-0' }

# Collections
{ type: 'array', value: [...] }
{ type: 'object', value: [[key, value], ...] }
{ type: 'map', value: [[key, value], ...] }
```

#### Result Deserialization

BiDi returns results in special format that must be deserialized:

```ruby
# BiDi response format
{
  "type" => "success",
  "realm" => "...",
  "result" => {
    "type" => "number",
    "value" => 42
  }
}

# Extract and deserialize
actual_result = result['result'] || result
deserialize_result(actual_result)  # => 42
```

#### Exception Handling

Exceptions from JavaScript are returned in the result, not thrown by BiDi:

```ruby
if result['type'] == 'exception'
  exception_details = result['exceptionDetails']
  text = exception_details['text']  # "ReferenceError: notExistingObject is not defined"
  raise text
end
```

### Core::Realm Return Values

**Important**: Core::Realm methods return the **complete BiDi result**, not just the value:

```ruby
# Core::Realm.call_function returns:
{
  "type" => "success" | "exception",
  "realm" => "...",
  "result" => {...} | nil,
  "exceptionDetails" => {...} | nil
}

# NOT result['result'] (this was a bug that was fixed)
```

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
# Expected: 12 examples, 0 failures (completes in ~8 seconds with optimized spec_helper)
```

#### Test Performance Optimization

**Critical**: Integration tests are ~19x faster with browser reuse strategy.

##### Before Optimization (Per-test Browser Launch)
```ruby
def with_test_state(**options)
  server = TestServer::Server.new
  server.start

  with_browser(**options) do |browser|  # New browser per test!
    context = browser.default_browser_context
    page = browser.new_page
    yield(page: page, server: server, browser: browser, context: context)
  end
ensure
  server.stop
end
```

**Performance**: ~195 seconds for 35 tests (browser launch overhead × 35)

##### After Optimization (Shared Browser)
```ruby
# In spec_helper.rb
config.before(:suite) do
  if RSpec.configuration.files_to_run.any? { |f| f.include?('spec/integration') }
    $shared_browser = Puppeteer::Bidi.launch(headless: headless_mode?)
    $shared_test_server = TestServer::Server.new
    $shared_test_server.start
  end
end

def with_test_state(**options)
  if $shared_browser && options.empty?
    # Create new page (tab) per test
    page = $shared_browser.new_page
    context = $shared_browser.default_browser_context

    begin
      yield(page: page, server: $shared_test_server, browser: $shared_browser, context: context)
    ensure
      page.close unless page.closed?  # Clean up tab
    end
  else
    # Fall back to per-test browser for custom options
  end
end
```

**Performance**: ~10 seconds for 35 tests (1 browser launch + 35 tab creations)

##### Performance Results

| Test Suite | Before | After | Improvement |
|------------|--------|-------|-------------|
| **evaluation_spec (23 tests)** | 127s | **7.17s** | **17.7x faster** |
| **screenshot_spec (12 tests)** | 68s | **8.47s** | **8.0x faster** |
| **Combined (35 tests)** | 195s | **10.33s** | **18.9x faster** 🚀 |

**Key Benefits**:
- Browser launch only once per suite
- Each test gets fresh page (tab) for isolation
- Cleanup handled automatically
- Backward compatible (custom options fall back to per-test browser)

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

## JSHandle and ElementHandle Implementation

### Overview

JSHandle and ElementHandle are fundamental classes for interacting with JavaScript objects in the browser. This section documents the implementation details and debugging techniques learned during development.

### Architecture

```
Puppeteer::Bidi
├── Serializer        # Ruby → BiDi LocalValue
├── Deserializer      # BiDi RemoteValue → Ruby
├── JSHandle          # JavaScript object reference
└── ElementHandle     # DOM element reference (extends JSHandle)
```

### Key Implementation Files

| File | Purpose | Lines |
|------|---------|-------|
| `lib/puppeteer/bidi/serializer.rb` | Centralized argument serialization | 136 |
| `lib/puppeteer/bidi/deserializer.rb` | Centralized result deserialization | 132 |
| `lib/puppeteer/bidi/js_handle.rb` | JavaScript object handles | 291 |
| `lib/puppeteer/bidi/element_handle.rb` | DOM element handles | 91 |

**Code reduction**: ~300 lines of duplicate serialization code eliminated from Frame and Page classes.

### Critical BiDi Protocol Parameters

#### 1. resultOwnership - Handle Lifecycle Management

**Problem**: BiDi returns `{"type" => "object"}` without `handle` or `sharedId`, making it impossible to reference the object later.

**Root Cause**: Missing `resultOwnership` parameter in `script.callFunction` and `script.evaluate`.

**Solution**: Always set `resultOwnership: 'root'` when you need a handle:

```ruby
# lib/puppeteer/bidi/core/realm.rb
def call_function(function_declaration, await_promise, **options)
  # Critical: Use 'root' ownership to keep handles alive
  unless options.key?(:resultOwnership)
    options[:resultOwnership] = 'root'
  end

  session.send_command('script.callFunction', {
    functionDeclaration: function_declaration,
    awaitPromise: await_promise,
    target: target,
    **options
  })
end
```

**BiDi resultOwnership values**:
- `'root'`: Keep handle alive (garbage collection resistant)
- `'none'`: Don't return handle (for one-time evaluations)

**Important**: Don't confuse with `awaitPromise`:
- `awaitPromise`: Controls whether to wait for promises to resolve
- `resultOwnership`: Controls handle lifecycle (independent concern)

#### 2. serializationOptions - Control Serialization Depth

**When requesting handles**, set `maxObjectDepth: 0` to prevent deep serialization:

```ruby
# When awaitPromise is false (returning handle):
options[:serializationOptions] = {
  maxObjectDepth: 0,  # Don't serialize, return handle
  maxDomDepth: 0      # Don't serialize DOM children
}
```

**Without serializationOptions**: BiDi may serialize the entire object graph, losing the handle reference.

### Debugging Techniques

#### 1. Protocol Message Inspection

Use `DEBUG_BIDI_COMMAND=1` to see all BiDi protocol messages:

```bash
DEBUG_BIDI_COMMAND=1 bundle exec rspec spec/integration/jshandle_spec.rb:24
```

**Output**:
```
[BiDi] Request script.callFunction: {
  id: 1,
  method: "script.callFunction",
  params: {
    functionDeclaration: "() => navigator",
    awaitPromise: false,
    target: {context: "..."},
    resultOwnership: "root",           # ← Check this!
    serializationOptions: {            # ← Check this!
      maxObjectDepth: 0
    }
  }
}

[BiDi] Response for script.callFunction: {
  type: "success",
  result: {
    type: "object",
    handle: "6af2844f-..."  # ← Should have handle!
  }
}
```

#### 2. Comparing with Puppeteer's Protocol Messages

**Workflow**:
1. Clone Puppeteer repository: `git clone https://github.com/puppeteer/puppeteer`
2. Set up Puppeteer: `npm install && npm run build`
3. Enable protocol logging: `DEBUG_PROTOCOL=1 npm test -- test/src/jshandle.spec.ts`
4. Compare messages side-by-side with Ruby implementation

**Example comparison**:
```bash
# Puppeteer (TypeScript)
DEBUG_PROTOCOL=1 npm test -- test/src/jshandle.spec.ts -g "should accept object handle"

# Ruby implementation
DEBUG_BIDI_COMMAND=1 bundle exec rspec spec/integration/jshandle_spec.rb:24
```

**Look for differences in**:
- Parameter names (camelCase vs snake_case)
- Missing parameters (resultOwnership, serializationOptions)
- Parameter values (arrays vs strings)

#### 3. Extracting Specific Protocol Messages

Use `grep` to filter specific BiDi methods:

```bash
DEBUG_BIDI_COMMAND=1 bundle exec rspec spec/integration/jshandle_spec.rb:227 \
  --format documentation 2>&1 | grep -A 5 "script\.disown"
```

**Output**:
```
[BiDi] Request script.disown: {
  id: 6,
  method: "script.disown",
  params: {
    target: {context: "..."},
    handles: "6af2844f-..."  # ← ERROR: Should be array!
  }
}
```

#### 4. Step-by-Step Protocol Flow Analysis

For complex issues, trace the entire flow:

```ruby
# Add temporary debugging in code
def evaluate_handle(script, *args)
  puts "1. Input script: #{script}"
  puts "2. Serialized args: #{serialized_args.inspect}"

  result = @realm.call_function(script, false, arguments: serialized_args)
  puts "3. BiDi result: #{result.inspect}"

  handle = JSHandle.from(result['result'], @realm)
  puts "4. Created handle: #{handle.inspect}"

  handle
end
```

### Common Pitfalls and Solutions

#### 1. Handle Parameters Must Be Arrays

**Problem**: BiDi error "Expected 'handles' to be an array, got [object String]"

**Root Cause**: `script.disown` expects `handles` parameter as array, but single string was passed:

```ruby
# WRONG
@realm.disown(handle_id)  # → {handles: "abc-123"}

# CORRECT
@realm.disown([handle_id])  # → {handles: ["abc-123"]}
```

**Location**: `lib/puppeteer/bidi/js_handle.rb:57`

**Fix**:
```ruby
def dispose
  handle_id = id
  @realm.disown([handle_id]) if handle_id  # Wrap in array
end
```

#### 2. Handle Not Returned from evaluate_handle

**Symptoms**:
- `remote_value['handle']` is `nil`
- BiDi returns `{"type" => "object"}` without handle
- Error: "Expected 'serializedKeyValueList' to be an array"

**Root Cause**: Missing `resultOwnership` and `serializationOptions` parameters

**Fix**: Add to `Core::Realm#call_function` (see section 1 above)

#### 3. Confusing awaitPromise with returnByValue

**Common mistake**: Thinking `awaitPromise` controls serialization

**Reality**:
- `awaitPromise`: Wait for promises? (`true`/`false`)
- `resultOwnership`: Return handle? (`'root'`/`'none'`)
- These are **independent** concerns!

**Example**:
```ruby
# Want handle to a promise result? Use both!
call_function(script, true, resultOwnership: 'root')  # await=true, handle=yes

# Want serialized promise result? Different!
call_function(script, true, resultOwnership: 'none')  # await=true, serialize=yes
```

#### 4. Date Serialization in json_value

**Problem**: Dates converted to strings instead of Time objects

**Wrong approach**:
```ruby
# DON'T: Using JSON.stringify loses BiDi's native date type
result = evaluate('(value) => JSON.stringify(value)')
JSON.parse(result)  # Date becomes string!
```

**Correct approach**:
```ruby
# DO: Use BiDi's built-in serialization
def json_value
  evaluate('(value) => value')  # BiDi handles dates natively
end
```

**BiDi date format**:
```ruby
# BiDi returns: {type: 'date', value: '2020-05-27T01:31:38.506Z'}
# Deserializer converts to: Time.parse('2020-05-27T01:31:38.506Z')
```

### Testing Strategy for Handle Implementation

#### Test Organization

```
spec/integration/
├── jshandle_spec.rb         # 21 tests - JSHandle functionality
├── queryselector_spec.rb    # 8 tests - DOM querying
└── evaluation_spec.rb       # Updated - ElementHandle arguments
```

#### Test Coverage Checklist

When implementing handle-related features, ensure tests cover:

- ✅ Handle creation from primitives and objects
- ✅ Handle passing as function arguments
- ✅ Property access (single and multiple)
- ✅ JSON value serialization
- ✅ Special values (dates, circular references, undefined)
- ✅ Type conversion (`as_element`)
- ✅ String representation (`to_s`)
- ✅ Handle disposal and error handling
- ✅ DOM querying (single and multiple)
- ✅ Empty result handling

#### Running Handle Tests

```bash
# All handle-related tests
bundle exec rspec spec/integration/jshandle_spec.rb spec/integration/queryselector_spec.rb

# With protocol debugging
DEBUG_BIDI_COMMAND=1 bundle exec rspec spec/integration/jshandle_spec.rb:24

# Specific test
bundle exec rspec spec/integration/jshandle_spec.rb:227 --format documentation
```

### Code Patterns and Best Practices

#### 1. Serializer Usage

**Always use Serializer** for argument preparation:

```ruby
# Good
args = [element, selector].map { |arg| Serializer.serialize(arg) }
call_function(script, true, arguments: args)

# Bad - manual serialization (duplicates logic)
args = [
  { type: 'object', handle: element.id },
  { type: 'string', value: selector }
]
```

#### 2. Deserializer Usage

**Always use Deserializer** for result processing:

```ruby
# Good
result = call_function(script, true)
Deserializer.deserialize(result['result'])

# Bad - manual deserialization (misses edge cases)
result['result']['value']  # Breaks for dates, handles, etc.
```

#### 3. Factory Pattern for Handle Creation

**Use `JSHandle.from`** for polymorphic handle creation:

```ruby
# Good - automatically creates ElementHandle for nodes
handle = JSHandle.from(remote_value, realm)

# Bad - manual type checking
if remote_value['type'] == 'node'
  ElementHandle.new(realm, remote_value)
else
  JSHandle.new(realm, remote_value)
end
```

#### 4. Handle Disposal Pattern

**Always check disposal state** before operations:

```ruby
def get_property(name)
  raise 'JSHandle is disposed' if @disposed

  # ... implementation
end
```

### Performance Considerations

#### Handle Lifecycle

**Handles consume browser memory** - dispose when no longer needed:

```ruby
# Manual disposal
handle = page.evaluate_handle('window')
# ... use handle
handle.dispose

# Automatic disposal via block (future enhancement)
page.evaluate_handle('window') do |handle|
  # handle automatically disposed after block
end
```

#### Serialization vs Handle References

**Trade-off**:
- **Serialization** (`resultOwnership: 'none'`): One-time use, no memory overhead
- **Handle** (`resultOwnership: 'root'`): Reusable, requires disposal

```ruby
# One-time evaluation - serialize
page.evaluate('document.title')  # No handle created

# Reusable reference - handle
handle = page.evaluate_handle('document')  # Keep for multiple operations
handle.evaluate('doc => doc.title')
handle.evaluate('doc => doc.body.innerHTML')
handle.dispose  # Clean up
```

### Reference Implementation Mapping

| Puppeteer TypeScript | Ruby Implementation | Notes |
|---------------------|---------------------|-------|
| `BidiJSHandle.from()` | `JSHandle.from()` | Factory method |
| `BidiJSHandle#dispose()` | `JSHandle#dispose` | Handle cleanup |
| `BidiJSHandle#jsonValue()` | `JSHandle#json_value` | Uses evaluate trick |
| `BidiJSHandle#getProperty()` | `JSHandle#get_property` | Single property |
| `BidiJSHandle#getProperties()` | `JSHandle#get_properties` | Walks prototype chain |
| `BidiElementHandle#$()` | `ElementHandle#query_selector` | CSS selector |
| `BidiElementHandle#$$()` | `ElementHandle#query_selector_all` | Multiple elements |
| `BidiSerializer.serialize()` | `Serializer.serialize()` | Centralized |
| `BidiDeserializer.deserialize()` | `Deserializer.deserialize()` | Centralized |

### Future Enhancements

Potential improvements for handle implementation:

1. **Automatic disposal**: Block-based API with automatic cleanup
2. **Handle pooling**: Reuse handle IDs to reduce memory overhead
3. **Lazy deserialization**: Defer conversion until value is accessed
4. **Type hints**: RBS type definitions for better IDE support
5. **Handle debugging**: Track handle creation/disposal for leak detection

### Lessons Learned

1. **Always compare protocol messages** with Puppeteer when debugging BiDi issues
2. **resultOwnership is critical** for handle-based APIs - always set it explicitly
3. **Don't confuse awaitPromise with serialization** - they control different aspects
4. **BiDi arrays must be arrays** - wrapping single values is often necessary
5. **Use Puppeteer's tricks** - like `evaluate('(value) => value')` for json_value
6. **Test disposal thoroughly** - handle lifecycle bugs are subtle and common
7. **Centralize serialization** - eliminates duplication and ensures consistency

## Selector Evaluation Methods Implementation

### Overview

The `eval_on_selector` and `eval_on_selector_all` methods provide convenient shortcuts for querying elements and evaluating JavaScript functions on them, equivalent to Puppeteer's `$eval` and `$$eval`.

### API Design

#### Method Naming Convention

Ruby cannot use `$` in method names, so we use descriptive alternatives:

| Puppeteer | Ruby | Description |
|-----------|------|-------------|
| `$eval` | `eval_on_selector` | Evaluate on first matching element |
| `$$eval` | `eval_on_selector_all` | Evaluate on all matching elements |

#### Implementation Hierarchy

Following Puppeteer's delegation pattern:

```
Page#eval_on_selector(_all)
  ↓ delegates to
Frame#eval_on_selector(_all)
  ↓ delegates to
ElementHandle#eval_on_selector(_all) (on document)
  ↓ implementation
  1. query_selector(_all) - Find element(s)
  2. Validate results
  3. evaluate() - Execute function
  4. dispose - Clean up handles
```

### Implementation Details

#### Page and Frame Methods

```ruby
# lib/puppeteer/bidi/page.rb
def eval_on_selector(selector, page_function, *args)
  main_frame.eval_on_selector(selector, page_function, *args)
end

# lib/puppeteer/bidi/frame.rb
def eval_on_selector(selector, page_function, *args)
  document.eval_on_selector(selector, page_function, *args)
end
```

**Design rationale**: Page and Frame act as thin wrappers, delegating to the document element handle.

#### ElementHandle#eval_on_selector

```ruby
def eval_on_selector(selector, page_function, *args)
  assert_not_disposed

  element_handle = query_selector(selector)
  raise SelectorNotFoundError, selector unless element_handle

  begin
    element_handle.evaluate(page_function, *args)
  ensure
    element_handle.dispose
  end
end
```

**Key points**:
- Throws `SelectorNotFoundError` if no element found (matches Puppeteer behavior)
- Uses `begin/ensure` to guarantee handle disposal
- Searches within element's subtree (not page-wide)

#### ElementHandle#eval_on_selector_all

```ruby
def eval_on_selector_all(selector, page_function, *args)
  assert_not_disposed

  element_handles = query_selector_all(selector)

  begin
    # Create array handle in browser context
    array_handle = @realm.call_function(
      '(...elements) => elements',
      false,
      arguments: element_handles.map(&:remote_value)
    )

    array_js_handle = JSHandle.from(array_handle['result'], @realm)

    begin
      array_js_handle.evaluate(page_function, *args)
    ensure
      array_js_handle.dispose
    end
  ensure
    element_handles.each(&:dispose)
  end
end
```

**Key points**:
- Returns result for empty array without error (differs from `eval_on_selector`)
- Creates array handle using spread operator trick: `(...elements) => elements`
- Nested `ensure` blocks for proper resource cleanup
- Disposes both individual element handles and array handle

### Error Handling Differences

| Method | Behavior when no elements found |
|--------|--------------------------------|
| `eval_on_selector` | Throws `SelectorNotFoundError` |
| `eval_on_selector_all` | Returns evaluation result (e.g., `0` for `divs => divs.length`) |

This matches Puppeteer's behavior:
- `$eval`: Must find exactly one element
- `$$eval`: Works with zero or more elements

### Usage Examples

```ruby
# Basic usage
page.set_content('<section id="test">Hello</section>')
id = page.eval_on_selector('section', 'e => e.id')
# => "test"

# With arguments
text = page.eval_on_selector('section', '(e, suffix) => e.textContent + suffix', '!')
# => "Hello!"

# ElementHandle arguments
div = page.query_selector('div')
result = page.eval_on_selector('section', '(e, div) => e.textContent + div.textContent', div)

# eval_on_selector_all with multiple elements
page.set_content('<div>A</div><div>B</div><div>C</div>')
count = page.eval_on_selector_all('div', 'divs => divs.length')
# => 3

# Subtree search with ElementHandle
tweet = page.query_selector('.tweet')
likes = tweet.eval_on_selector('.like', 'node => node.innerText')
# Only searches within .tweet element
```

### Test Coverage

**Total**: 13 integration tests

**Page.eval_on_selector** (4 tests):
- Basic functionality (property access)
- Argument passing
- ElementHandle arguments
- Error on missing selector

**ElementHandle.eval_on_selector** (3 tests):
- Basic functionality
- Subtree isolation
- Error on missing selector

**Page.eval_on_selector_all** (4 tests):
- Basic functionality (array length)
- Extra arguments
- ElementHandle arguments
- Large element count (1001 elements)

**ElementHandle.eval_on_selector_all** (2 tests):
- Subtree retrieval
- Empty result handling

### Performance Considerations

#### Handle Lifecycle

- **eval_on_selector**: Creates 1 temporary handle per call
- **eval_on_selector_all**: Creates N+1 handles (N elements + 1 array)
- All handles automatically disposed after evaluation

#### Large Element Sets

Tested with 1001 elements without issues. The implementation efficiently:
1. Queries all elements at once
2. Creates single array handle
3. Evaluates function in single round-trip
4. Disposes all handles in parallel

### Reference Implementation

Based on Puppeteer's implementation:
- [Page.$eval](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/api/Page.ts)
- [Frame.$eval](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/api/Frame.ts)
- [ElementHandle.$eval](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/api/ElementHandle.ts)
- [Test specs](https://github.com/puppeteer/puppeteer/blob/main/test/src/queryselector.spec.ts)

## Error Handling and Custom Exceptions

### Philosophy

Use custom exception classes instead of inline string raises for:
- **Type safety**: Enable `rescue` by specific exception type
- **DRY principle**: Centralize error messages
- **Debugging**: Attach contextual data to exception objects
- **Consistency**: Uniform error handling across codebase

### Custom Exception Hierarchy

```ruby
StandardError
└── Puppeteer::Bidi::Error
    ├── JSHandleDisposedError
    ├── PageClosedError
    ├── FrameDetachedError
    └── SelectorNotFoundError
```

All custom exceptions inherit from `Puppeteer::Bidi::Error` for consistent rescue patterns.

### Exception Classes

#### JSHandleDisposedError

**When raised**: Attempting to use a disposed JSHandle or ElementHandle

**Location**: `lib/puppeteer/bidi/errors.rb`

```ruby
class JSHandleDisposedError < Error
  def initialize
    super('JSHandle is disposed')
  end
end
```

**Usage**:
```ruby
# JSHandle and ElementHandle
private

def assert_not_disposed
  raise JSHandleDisposedError if @disposed
end
```

**Affected methods**:
- `JSHandle#evaluate`, `#evaluate_handle`, `#get_property`, `#get_properties`, `#json_value`
- `ElementHandle#query_selector`, `#query_selector_all`, `#eval_on_selector`, `#eval_on_selector_all`

#### PageClosedError

**When raised**: Attempting to use a closed Page

**Location**: `lib/puppeteer/bidi/errors.rb`

```ruby
class PageClosedError < Error
  def initialize
    super('Page is closed')
  end
end
```

**Usage**:
```ruby
# Page
private

def assert_not_closed
  raise PageClosedError if closed?
end
```

**Affected methods**:
- `Page#goto`, `#set_content`, `#screenshot`

#### FrameDetachedError

**When raised**: Attempting to use a detached Frame

**Location**: `lib/puppeteer/bidi/errors.rb`

```ruby
class FrameDetachedError < Error
  def initialize
    super('Frame is detached')
  end
end
```

**Usage**:
```ruby
# Frame
private

def assert_not_detached
  raise FrameDetachedError if @browsing_context.closed?
end
```

**Affected methods**:
- `Frame#evaluate`, `#evaluate_handle`, `#document`

#### SelectorNotFoundError

**When raised**: CSS selector doesn't match any elements in `eval_on_selector`

**Location**: `lib/puppeteer/bidi/errors.rb`

```ruby
class SelectorNotFoundError < Error
  attr_reader :selector

  def initialize(selector)
    @selector = selector
    super("Error: failed to find element matching selector \"#{selector}\"")
  end
end
```

**Usage**:
```ruby
# ElementHandle#eval_on_selector
element_handle = query_selector(selector)
raise SelectorNotFoundError, selector unless element_handle
```

**Contextual data**: The `selector` value is accessible via the exception object for debugging.

### Implementation Pattern

#### 1. Define Custom Exception

```ruby
# lib/puppeteer/bidi/errors.rb
class MyCustomError < Error
  def initialize(context = nil)
    @context = context
    super("Error message with #{context}")
  end
end
```

#### 2. Add Private Assertion Method

```ruby
class MyClass
  private

  def assert_valid_state
    raise MyCustomError, @context if invalid?
  end
end
```

#### 3. Replace Inline Raises

```ruby
# Before
def my_method
  raise 'Invalid state' if invalid?
  # ...
end

# After
def my_method
  assert_valid_state
  # ...
end
```

### Benefits

**Type-safe error handling**:
```ruby
begin
  page.eval_on_selector('.missing', 'e => e.id')
rescue SelectorNotFoundError => e
  puts "Selector '#{e.selector}' not found"
rescue JSHandleDisposedError
  puts "Handle was disposed"
end
```

**Consistent error messages**: Single source of truth for error text

**Reduced duplication**: 16 inline raises eliminated across codebase

**Better debugging**: Exception objects carry contextual information

### Testing Custom Exceptions

Tests use regex matching for backward compatibility:

```ruby
# Test remains compatible with custom exception
expect {
  page.eval_on_selector('non-existing', 'e => e.id')
}.to raise_error(/failed to find element matching selector/)
```

This allows tests to pass with both string raises and custom exceptions.

### Refactoring Statistics

| Class | Inline Raises Replaced | Private Assert Method |
|-------|------------------------|----------------------|
| JSHandle | 5 | `assert_not_disposed` |
| ElementHandle | 4 + 1 (selector) | (inherited) |
| Page | 3 | `assert_not_closed` |
| Frame | 3 | `assert_not_detached` |
| **Total** | **16** | **3 methods** |

### Future Considerations

When adding new error conditions:

1. **Create custom exception** in `lib/puppeteer/bidi/errors.rb`
2. **Add to exception hierarchy** by inheriting from `Error`
3. **Include contextual data** as `attr_reader` if needed
4. **Create private assert method** in the relevant class
5. **Replace inline raises** with assert method calls
6. **Update tests** to use regex matching for flexibility

This pattern ensures consistency and maintainability across the entire codebase.

## Click Implementation and Mouse Input

### Overview

Implemented full click functionality following Puppeteer's architecture, including mouse input actions, element visibility detection, and automatic scrolling.

### Architecture

```
Page#click
  ↓ delegates to
Frame#click
  ↓ delegates to
ElementHandle#click
  ↓ implementation
  1. scroll_into_view_if_needed
  2. clickable_point calculation
  3. Mouse#click (BiDi input.performActions)
```

### Key Components

#### Mouse Class (`lib/puppeteer/bidi/mouse.rb`)

Implements mouse input actions via BiDi `input.performActions`:

```ruby
def click(x, y, button: LEFT, count: 1, delay: nil)
  actions = []
  if @x != x || @y != y
    actions << {
      type: 'pointerMove',
      x: x.to_i,
      y: y.to_i,
      origin: 'viewport'  # BiDi expects string, not hash!
    }
  end
  @x = x
  @y = y
  bidi_button = button_to_bidi(button)
  count.times do
    actions << { type: 'pointerDown', button: bidi_button }
    actions << { type: 'pause', duration: delay.to_i } if delay
    actions << { type: 'pointerUp', button: bidi_button }
  end
  perform_actions(actions)
end
```

**Critical BiDi Protocol Detail**: The `origin` parameter must be the string `'viewport'`, NOT a hash like `{type: 'viewport'}`. This caused a protocol error during initial implementation.

#### ElementHandle Click Methods

##### scroll_into_view_if_needed

Uses IntersectionObserver API to detect viewport visibility:

```ruby
def scroll_into_view_if_needed
  return if intersecting_viewport?

  scroll_info = evaluate(<<~JS)
    element => {
      if (!element.isConnected) return 'Node is detached from document';
      if (element.nodeType !== Node.ELEMENT_NODE) return 'Node is not of type HTMLElement';

      element.scrollIntoView({
        block: 'center',
        inline: 'center',
        behavior: 'instant'
      });
      return false;
    }
  JS

  raise scroll_info if scroll_info
end
```

##### intersecting_viewport?

Uses browser's IntersectionObserver for accurate visibility detection:

```ruby
def intersecting_viewport?(threshold: 0)
  evaluate(<<~JS, threshold)
    (element, threshold) => {
      return new Promise(resolve => {
        const observer = new IntersectionObserver(entries => {
          resolve(entries[0].intersectionRatio > threshold);
          observer.disconnect();
        });
        observer.observe(element);
      });
    }
  JS
end
```

##### clickable_point

Calculates click coordinates with optional offset:

```ruby
def clickable_point(offset: nil)
  box = clickable_box
  if offset
    { x: box[:x] + offset[:x], y: box[:y] + offset[:y] }
  else
    { x: box[:x] + box[:width] / 2, y: box[:y] + box[:height] / 2 }
  end
end
```

### Critical Bug Fixes

#### 1. Missing session.subscribe Call

**Problem**: Navigation events (browsingContext.load, etc.) were not firing, causing tests to timeout.

**Root Cause**: Missing subscription to BiDi modules. Puppeteer subscribes to these modules on session creation:
- browsingContext
- network
- log
- script
- input

**Fix**: Added subscription in two places:

```ruby
# lib/puppeteer/bidi/browser.rb
subscribe_modules = %w[
  browsingContext
  network
  log
  script
  input
]
@session.subscribe(subscribe_modules)

# lib/puppeteer/bidi/core/session.rb
def initialize_session
  subscribe_modules = %w[
    browsingContext
    network
    log
    script
    input
  ]
  subscribe(subscribe_modules)
end
```

**Impact**: This fix enabled all navigation-related functionality, including the "click links which cause navigation" test.

#### 2. Event-Based URL Updates

**Problem**: Initial implementation updated `@url` directly in `navigate()` method, which is not how Puppeteer works.

**Puppeteer's Approach**: URL updates happen via BiDi events:
- `browsingContext.historyUpdated`
- `browsingContext.domContentLoaded`
- `browsingContext.load`

**Fix**: Removed direct URL assignment from navigate():

```ruby
# lib/puppeteer/bidi/core/browsing_context.rb
def navigate(url, wait: nil)
  raise BrowsingContextClosedError, @reason if closed?
  params = { context: @id, url: url }
  params[:wait] = wait if wait
  result = session.send_command('browsingContext.navigate', params)
  # URL will be updated via browsingContext.load event
  result
end
```

Event handlers (already implemented) update URL automatically:

```ruby
# History updated
session.on('browsingContext.historyUpdated') do |info|
  next unless info['context'] == @id
  @url = info['url']
  emit(:history_updated, nil)
end

# DOM content loaded
session.on('browsingContext.domContentLoaded') do |info|
  next unless info['context'] == @id
  @url = info['url']
  emit(:dom_content_loaded, nil)
end

# Page loaded
session.on('browsingContext.load') do |info|
  next unless info['context'] == @id
  @url = info['url']
  emit(:load, nil)
end
```

**Why this matters**: Event-based updates ensure URL synchronization even when navigation is triggered by user actions (like clicking links) rather than explicit `navigate()` calls.

### Test Coverage

#### Click Tests (20 tests in spec/integration/click_spec.rb)

Ported from [Puppeteer's click.spec.ts](https://github.com/puppeteer/puppeteer/blob/main/test/src/click.spec.ts):

1. **Basic clicking**: button, svg, wrapped links
2. **Edge cases**: window.Node removed, span with inline elements
3. **Navigation**: click after navigation, click links causing navigation
4. **Scrolling**: offscreen buttons, scrollable content
5. **Multi-click**: double click, triple click (text selection)
6. **Different buttons**: left, right (contextmenu), middle (auxclick)
7. **Visibility**: partially obscured button, rotated button
8. **Form elements**: checkbox toggle (input and label)
9. **Error handling**: missing selector
10. **Special cases**: disabled JavaScript, iframes (pending)

#### Page Tests (3 tests in spec/integration/page_spec.rb)

1. **Page.url**: Verify URL updates after navigation
2. **Page.setJavaScriptEnabled**: Control JavaScript execution (pending - Firefox limitation)

**All 108 integration tests pass** (4 pending due to Firefox BiDi limitations).

### Firefox BiDi Limitations

- `emulation.setScriptingEnabled`: Part of WebDriver BiDi spec but not yet implemented in Firefox
- Tests gracefully skip with clear messages using RSpec's `skip` feature

### Implementation Best Practices Learned

#### 1. Always Consult Puppeteer's Implementation First

**Workflow**:
1. Read Puppeteer's TypeScript implementation
2. Understand BiDi protocol calls being made
3. Implement Ruby equivalent with same logic flow
4. Port corresponding test cases

**Example**: The click implementation journey revealed that Puppeteer's architecture (Page → Frame → ElementHandle delegation) is critical for proper functionality.

#### 2. Stay Faithful to Puppeteer's Test Structure

**Initial mistake**: Created complex polling logic for navigation test
**Correction**: Simplified to match Puppeteer's simple approach:

```ruby
# Simple and correct (matches Puppeteer)
page.set_content("<a href=\"#{server.empty_page}\">empty.html</a>")
page.click('a')  # Should not hang
```

#### 3. Event Subscription is Critical

**Key lesson**: BiDi requires explicit subscription to event modules. Without it:
- Navigation events don't fire
- URL updates don't work
- Tests timeout mysteriously

**Solution**: Subscribe early in browser/session initialization.

#### 4. Use RSpec `it` Syntax

Per Ruby/RSpec conventions, use `it` instead of `example`:

```ruby
# Correct
it 'should click the button' do
  # ...
end

# Incorrect
example 'should click the button' do
  # ...
end
```

### BiDi Protocol Format Requirements

#### Origin Parameter Format

**Critical**: BiDi `input.performActions` expects `origin` as a string, not a hash:

```ruby
# CORRECT
origin: 'viewport'

# WRONG - causes protocol error
origin: { type: 'viewport' }
```

**Error message if wrong**:
```
Expected "origin" to be undefined, "viewport", "pointer", or an element,
got: [object Object] {"type":"viewport"}
```

### Performance and Reliability

- **IntersectionObserver**: Fast and accurate visibility detection
- **Auto-scrolling**: Ensures elements are clickable before interaction
- **Event-driven**: URL updates via events enable proper async handling
- **Thread-safe**: BiDi protocol handles concurrent operations naturally

### Future Enhancements

Potential improvements for click/mouse functionality:

1. **Drag and drop**: Implement drag operations
2. **Hover**: Mouse move without click
3. **Wheel**: Mouse wheel scrolling
4. **Touch**: Touch events for mobile emulation
5. **Keyboard modifiers**: Click with Ctrl/Shift/Alt
6. **Frame support**: Click inside iframes (currently pending)

### Reference Implementation

Based on Puppeteer's implementation:
- [Page.click](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/api/Page.ts)
- [Frame.click](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/api/Frame.ts)
- [ElementHandle.click](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/api/ElementHandle.ts)
- [Mouse input](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/bidi/Input.ts)
- [Test specs](https://github.com/puppeteer/puppeteer/blob/main/test/src/click.spec.ts)

### Key Takeaways

1. **session.subscribe is mandatory** for BiDi event handling - don't forget it!
2. **Event-based state management** (URL updates via events, not direct assignment)
3. **BiDi protocol details matter** (string vs hash for origin parameter)
4. **Follow Puppeteer's architecture** (delegation patterns, event handling)
5. **Test simplicity** - stay faithful to Puppeteer's test structure
6. **Browser limitations** - gracefully handle unimplemented features (setScriptingEnabled)

### Test Assets Policy

**CRITICAL**: Always use Puppeteer's official test assets without modification.

- **Source**: https://github.com/puppeteer/puppeteer/tree/main/test/assets
- **Rule**: Never modify test asset files (HTML, CSS, images) in `spec/assets/`
- **Experiments**: If you need to modify assets for experiments, **always revert to official version** before creating Pull Requests
- **Verification**: Before creating PR, verify all `spec/assets/` files match Puppeteer's official versions

**Example workflow**:
```bash
# During development - OK to experiment
vim spec/assets/test.html  # Temporary modification for debugging

# Before PR - MUST revert to official
curl -sL https://raw.githubusercontent.com/puppeteer/puppeteer/main/test/assets/test.html \
  -o spec/assets/test.html
```

**Why this matters**: Test assets are designed to test specific edge cases (rotated elements, complex layouts, etc.). Using simplified versions defeats the purpose of these tests.


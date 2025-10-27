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

## Development Roadmap

### Phase 1: Foundation
- [ ] WebSocket communication layer
- [ ] Basic BiDi protocol implementation
- [ ] Browser/BrowserContext/Page base classes

### Phase 2: Core Features
- [ ] Navigation (`browsingContext.navigate`)
- [ ] JavaScript execution (`script.evaluate`)
- [ ] Element operations (click, input)
- [ ] FrameManager implementation

### Phase 3: Advanced Features
- [ ] NetworkManager implementation
- [ ] Network interception
- [ ] Screenshot/PDF generation
- [ ] Enhanced event handling

### Phase 4: Stabilization
- [ ] Error handling
- [ ] Timeout management
- [ ] Test suite development
- [ ] Documentation enhancement

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

## Summary

puppeteer-bidi aims to provide a Ruby implementation that inherits Puppeteer's design philosophy while leveraging WebDriver BiDi protocol characteristics. Through layered architecture, event-driven design, and adoption of standardized protocols, we deliver a reliable Firefox automation tool.

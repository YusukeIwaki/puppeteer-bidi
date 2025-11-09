# Puppeteer BiDi Core

The `core` module provides a low-level layer that sits above the WebSocket transport to provide a structured API to WebDriver BiDi's flat API. It provides object-oriented semantics around WebDriver BiDi resources and automatically carries out the correct order of events through the use of events.

This implementation is a Ruby port of Puppeteer's BiDi core layer, following the same design principles.

## Design Principles

The following design decisions should be considered when developing or using the core layer:

### 1. Required vs Optional Arguments

- **Required arguments** are method parameters
- **Optional arguments** are keyword arguments

This follows Ruby conventions and makes required parameters explicit.

```ruby
# Required parameter first, optional as keyword arguments
browsing_context.navigate(url, wait: 'complete')
```

### 2. Session Visibility

- The session shall **never be exposed** on any public method except on Browser
- Private access to session is allowed

This prevents obfuscation of the session's origin. By only allowing it on the browser, the origin is well-defined.

### 3. WebDriver BiDi Compliance

- `core` implements WebDriver BiDi plus its surrounding specifications
- Always follow the spec, not Puppeteer's needs
- This allows precise bug identification (spec issue vs implementation issue)

### 4. Comprehensive but Minimal

- Implements all edges and nodes required by a feature
- Never skips intermediate nodes or composes edges
- Ensures WebDriver BiDi semantics are carried out correctly

Example: Fragment navigation must flow through Navigation to BrowsingContext, not directly from fragment navigation to BrowsingContext.

## Architecture

The core module provides these main classes:

### Foundation Classes

- **EventEmitter**: Event subscription and emission
- **Disposable**: Resource management and cleanup with DisposableStack

### Protocol Classes

- **Session**: BiDi session management, wraps Connection
- **Browser**: Browser instance management
- **UserContext**: Isolated browsing contexts (similar to incognito)
- **BrowsingContext**: Individual tabs/windows/frames
- **Navigation**: Navigation tracking and lifecycle
- **Request**: Network request management
- **UserPrompt**: User prompt (alert/confirm/prompt) handling

### Execution Context Classes

- **Realm**: Base class for JavaScript execution contexts
  - **WindowRealm**: Window/iframe realms
  - **DedicatedWorkerRealm**: Dedicated worker realms
  - **SharedWorkerRealm**: Shared worker realms

## Object Hierarchy

```
Browser
├── Session (wrapped Connection)
└── UserContext (isolated session)
    └── BrowsingContext (tab/window/frame)
        ├── Navigation (navigation lifecycle)
        ├── Request (network requests)
        ├── UserPrompt (alerts, confirms, prompts)
        └── Realm (JavaScript execution)
            ├── WindowRealm (main window/iframe)
            ├── DedicatedWorkerRealm (web workers)
            └── SharedWorkerRealm (shared workers)
```

## Usage Example

```ruby
require 'puppeteer/bidi/core'

# Create a session from an existing connection
session = Puppeteer::Bidi::Core::Session.from(connection, capabilities)

# Create a browser instance
browser = Puppeteer::Bidi::Core::Browser.from(session)

# Get the default user context
context = browser.default_user_context

# Create a browsing context (tab)
browsing_context = context.create_browsing_context('tab')

# Listen for navigation events
browsing_context.on(:navigation) do |data|
  navigation = data[:navigation]
  puts "Navigation started to #{browsing_context.url}"
end

# Navigate to a URL
browsing_context.navigate('https://example.com', wait: 'complete')

# Evaluate JavaScript in the default realm
result = browsing_context.default_realm.evaluate('document.title', true)
puts "Page title: #{result['value']}"

# Close the browsing context
browsing_context.close
```

## Event Handling

All core classes extend `EventEmitter` and emit various events:

```ruby
# Browser events
browser.on(:closed) { |data| puts "Browser closed: #{data[:reason]}" }
browser.on(:disconnected) { |data| puts "Browser disconnected: #{data[:reason]}" }

# BrowsingContext events
browsing_context.on(:navigation) { |data| puts "Navigation: #{data[:navigation]}" }
browsing_context.on(:request) { |data| puts "Request: #{data[:request].url}" }
browsing_context.on(:load) { puts "Page loaded" }
browsing_context.on(:dom_content_loaded) { puts "DOM ready" }

# Request events
request.on(:redirect) { |redirect| puts "Redirected to: #{redirect.url}" }
request.on(:success) { |response| puts "Response: #{response['status']}" }
request.on(:error) { |error| puts "Request failed: #{error}" }
```

## Resource Management

Core classes implement the `Disposable` pattern for proper resource cleanup:

```ruby
# Resources are automatically disposed when parent is disposed
browser.close  # Disposes all user contexts, browsing contexts, etc.

# Disposal triggers appropriate events
browsing_context.on(:closed) do |data|
  puts "Context closed: #{data[:reason]}"
end

# Check disposal status
puts "Disposed: #{browsing_context.disposed?}"
```

## Differences from TypeScript Implementation

1. **Ruby Conventions**: Uses snake_case instead of camelCase
2. **Keyword Arguments**: Uses Ruby keyword arguments instead of options hashes
3. **Symbols**: Uses symbols for event names instead of strings
4. **No Decorators**: Decorators like `@throwIfDisposed` are implemented as method guards
5. **Async Primitives**: Uses Ruby's Async library (Fiber-based) instead of JavaScript promises (similar to async/await)

## References

- [WebDriver BiDi Specification](https://w3c.github.io/webdriver-bidi/)
- [Puppeteer BiDi Core (TypeScript)](https://github.com/puppeteer/puppeteer/tree/main/packages/puppeteer-core/src/bidi/core)
